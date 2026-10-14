"""Automation engine.

Two ways a run starts:
- event triggers (client_approved, plan_starts, form_sent, goal_weight) call `fire_event` from the code
  where the thing happens;
- every other trigger is checked by `poll_triggers`, which Celery beat runs every 15 minutes.

A run is one client going through one automation. The unique (automation, client, dedupe_key) row means
the same trigger never starts the same flow twice, even if two workers poll at once.
Steps run in order; a Wait step parks the run with `next_run_at`, and `process_due_runs` (every minute)
picks it up again. With `stop_on_response`, a form sent in or a habit/meal/workout logged stops the rest.
"""
import logging
from datetime import datetime, time, timedelta

from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.utils import timezone

from .models import EVENT_TRIGGERS, Automation, AutomationRun, Step, TrainerTask

log = logging.getLogger(__name__)
User = get_user_model()

POLL_MINUTES = 15


# ---------------------------------------------------------------- starting runs
def applies_to(automation, client):
    cp = getattr(client, "client_profile", None)
    if cp is None or client.status != "active" or cp.removed_at:
        return False
    if automation.scope_package and cp.package_name != automation.scope_package:
        return False
    if automation.scope_trainer_id and cp.trainer_id != automation.scope_trainer_id:
        return False
    return True


def _config_matches(automation, context):
    cfg = automation.trigger_config or {}
    if automation.trigger == "form_sent" and cfg.get("form"):
        return str(cfg["form"]) == str((context or {}).get("form"))
    if automation.trigger in ("plan_starts", "plan_ends") and cfg.get("plan_type", "any") != "any":
        return cfg["plan_type"] == (context or {}).get("plan_type", "program")
    return True


def start_run(automation, client, dedupe):
    try:
        with transaction.atomic():
            run = AutomationRun.objects.create(automation=automation, client=client, dedupe_key=dedupe[:80],
                                               next_run_at=timezone.now(), status=AutomationRun.Status.RUNNING)
    except IntegrityError:
        return None
    from . import tasks

    transaction.on_commit(lambda: tasks.advance_run.delay(str(run.id)))
    return run


def fire_event(trigger, client, *, dedupe=None, context=None):
    """Called by app code. Never raises: an automation problem must not break the user's action."""
    try:
        autos = Automation.objects.filter(status=Automation.Status.ON, trigger=trigger)
        started = 0
        for a in autos:
            if applies_to(a, client) and _config_matches(a, context):
                if start_run(a, client, dedupe or trigger):
                    started += 1
        return started
    except Exception:  # pragma: no cover - logged, swallowed on purpose
        log.exception("fire_event %s failed", trigger)
        return 0


def response_received(client):
    """The client sent a form / logged something: stop runs that wait for a response."""
    runs = AutomationRun.objects.filter(client=client, automation__stop_on_response=True,
                                        status__in=[AutomationRun.Status.WAITING, AutomationRun.Status.RUNNING],
                                        step_index__gt=0)
    for r in runs:
        r.status = AutomationRun.Status.STOPPED
        r.finished_at = timezone.now()
        r.last_message = f"{r.last_message} · stopped at step {r.step_index}".strip(" ·")
        r.next_run_at = None
        r.save(update_fields=["status", "finished_at", "last_message", "next_run_at", "updated_at"])


# ---------------------------------------------------------------- running steps
def _describe(step):
    c = step.config or {}
    if step.kind == Step.Kind.WAIT:
        d, h = c.get("days", 0), c.get("hours", 0)
        return f"Wait {d} day{'s' if d != 1 else ''}" if d else f"Wait {h} hours"
    if step.kind == Step.Kind.MESSAGE:
        return f"Send '{c.get('template')}'"
    if step.kind == Step.Kind.FORM:
        return "Send the form"
    return f"Task: {c.get('title', '')}"


def _resolve_form(cfg):
    from apps.checkins.models import Form

    if cfg.get("form"):
        return Form.objects.filter(id=cfg["form"]).first()
    if cfg.get("form_name"):
        return Form.objects.filter(name=cfg["form_name"], status="published").first()
    return None


def run_step(run, step):
    """Do one step. Returns a datetime to wait until, or None to go straight on."""
    c = step.config or {}
    client = run.client
    if step.kind == Step.Kind.WAIT:
        return timezone.now() + timedelta(days=int(c.get("days", 0)), hours=int(c.get("hours", 0)))
    if step.kind == Step.Kind.MESSAGE:
        from apps.notifications.services import send_template

        send_template(client, c.get("template", ""), channels=c.get("channels") or None, automation_run=run,
                      data={"automation": str(run.automation_id)})
        run.last_message = "Sent a message"
    elif step.kind == Step.Kind.FORM:
        from apps.checkins.services import send_form

        form = _resolve_form(c)
        if form is None:
            raise ValueError("The form of this step was deleted.")
        send_form(client, form, automation_run=run, channels=c.get("channels") or None,
                  due_at=timezone.now() + timedelta(days=1))
        run.last_message = "Sent the form"
    elif step.kind == Step.Kind.TASK:
        cp = client.client_profile
        if c.get("assignee") == "owner" or cp.trainer is None:
            assignee = User.objects.filter(role="admin").first()
        else:
            assignee = cp.trainer
        t = TrainerTask.objects.create(
            assignee=assignee, client=client, automation_run=run,
            title=c.get("title", "Follow up").replace("the client", client.first_name)[:160],
            detail=f"From automation · {run.automation.name}"[:200],
            due_on=timezone.localdate() + timedelta(days=int(c.get("due_days", 1))))
        from apps.notifications.services import notify

        notify(assignee, "task_created", t.title, t.detail, data={"route": "/", "task": str(t.id)})
        run.last_message = "Trainer task made"
    return None


def advance(run):
    """Run steps from run.step_index until a wait, the end, or an error."""
    if run.status in (AutomationRun.Status.FINISHED, AutomationRun.Status.STOPPED, AutomationRun.Status.FAILED):
        return run
    a = run.automation
    if a.status != Automation.Status.ON or a.deleted_at:
        run.status = AutomationRun.Status.STOPPED
        run.last_message = "Automation turned off"
        run.finished_at = timezone.now()
        run.save()
        return run
    steps = list(a.steps.all())
    run.status = AutomationRun.Status.RUNNING
    while run.step_index < len(steps):
        step = steps[run.step_index]
        try:
            wait_until = run_step(run, step)
        except Exception as e:
            log.exception("automation step failed")
            run.status = AutomationRun.Status.FAILED
            run.last_message = str(e)[:200]
            run.log = (run.log or []) + [{"at": timezone.now().isoformat(), "step": run.step_index + 1,
                                          "error": str(e)[:200]}]
            run.save()
            return run
        run.log = (run.log or []) + [{"at": timezone.now().isoformat(), "step": run.step_index + 1,
                                      "did": _describe(step)}][-50:]
        run.step_index += 1
        if wait_until is not None:
            run.status = AutomationRun.Status.WAITING
            run.next_run_at = wait_until
            run.last_message = f"Waiting · step {run.step_index + 1} of {len(steps)}"
            run.save()
            return run
    run.status = AutomationRun.Status.FINISHED
    run.finished_at = timezone.now()
    run.next_run_at = None
    run.last_message = "Finished"
    run.save()
    return run


def process_due_runs(limit=500):
    ids = list(AutomationRun.objects.filter(status__in=[AutomationRun.Status.WAITING, AutomationRun.Status.RUNNING],
                                            next_run_at__lte=timezone.now())
               .order_by("next_run_at").values_list("id", flat=True)[:limit])
    for rid in ids:
        with transaction.atomic():
            run = (AutomationRun.objects.select_for_update(skip_locked=True).select_related("automation", "client")
                   .filter(id=rid).first())
            if run is None:
                continue
            if run.status == AutomationRun.Status.RUNNING and run.updated_at > timezone.now() - timedelta(minutes=5) \
                    and run.step_index > 0:
                continue  # another worker is on it
            advance(run)
    return len(ids)


# ---------------------------------------------------------------- polling
def _in_window(now, hhmm):
    """True if local `now` is within the 15-minute poll window starting at hh:mm."""
    try:
        h, m = (int(x) for x in str(hhmm or "09:00").split(":")[:2])
    except ValueError:
        h, m = 9, 0
    start = now.replace(hour=h, minute=m, second=0, microsecond=0)
    return start <= now < start + timedelta(minutes=POLL_MINUTES)


def _clients():
    return User.objects.filter(role="client", status="active", client_profile__removed_at__isnull=True) \
        .select_related("client_profile")


def candidates(automation, now):
    """Yield (client, dedupe_key) pairs that meet a polled trigger right now."""
    from apps.checkins.models import Submission, WeightLog
    from apps.clients.metrics import active_program, planned_workout_days
    from apps.training.models import ProgramAssignment, WorkoutLog

    t, cfg = automation.trigger, automation.trigger_config or {}
    today = now.date()
    if t == "every_day" and _in_window(now, cfg.get("time")):
        for c in _clients():
            yield c, f"day:{today}"
    elif t == "every_week" and now.weekday() == int(cfg.get("weekday", 6)) and _in_window(now, cfg.get("time")):
        for c in _clients():
            yield c, f"week:{today}"
    elif t == "on_date" and str(today) == str(cfg.get("date")) and _in_window(now, cfg.get("time")):
        for c in _clients():
            yield c, f"date:{today}"
    elif t == "birthday" and _in_window(now, cfg.get("time", "09:00")):
        for c in _clients().filter(date_of_birth__month=today.month, date_of_birth__day=today.day):
            yield c, f"bday:{today.year}"
    elif t == "package_ending":
        target = today + timedelta(days=int(cfg.get("days_before", 7)))
        for c in _clients().filter(client_profile__package_ends_on=target):
            yield c, f"pkg:{target}"
    elif t == "plan_ends":
        target = today + timedelta(days=int(cfg.get("days_before", 3)))
        if cfg.get("plan_type", "any") in ("any", "program"):
            for a in ProgramAssignment.objects.filter(status="active", end_date=target).select_related(
                    "client__client_profile"):
                yield a.client, f"pend:{a.id}"
        if cfg.get("plan_type", "any") in ("any", "meal_plan"):
            from apps.nutrition.models import MealPlanAssignment

            for a in MealPlanAssignment.objects.filter(status="active", end_date=target).select_related(
                    "client__client_profile"):
                yield a.client, f"mend:{a.id}"
    elif t == "no_activity":
        days = int(cfg.get("days", 7))
        for c in _clients().filter(last_seen_at__lt=now - timedelta(days=days)):
            yield c, f"idle:{c.last_seen_at.date()}"
    elif t == "missed_checkin":
        hours = int(cfg.get("hours", 24))
        for c in _clients():
            last = Submission.objects.filter(client=c, form_type="weekly").order_by("-created_at").first()
            start = last.created_at if last else timezone.make_aware(datetime.combine(
                c.client_profile.start_date or c.date_joined.date(), time(9)))
            due = start + timedelta(days=7)
            if now >= due + timedelta(hours=hours):
                yield c, f"late:{due.date()}"
    elif t == "missed_workouts":
        n = int(cfg.get("count", 2))
        for c in _clients():
            pa = active_program(c)
            if not pa:
                continue
            planned = planned_workout_days(pa, today - timedelta(days=21), today - timedelta(days=1))
            done = set(WorkoutLog.objects.filter(client=c, status="completed", date__gte=today - timedelta(days=21))
                       .values_list("date", flat=True))
            streak = 0
            for d in reversed(planned):
                if d in done:
                    break
                streak += 1
            if streak >= n:
                yield c, f"miss:{planned[-1]}"
    elif t == "workout_streak":
        n = int(cfg.get("days", 7))
        for c in _clients():
            days = set(WorkoutLog.objects.filter(client=c, status="completed",
                                                 date__gte=today - timedelta(days=n + 1))
                       .values_list("date", flat=True))
            d, run = today, 0
            if d not in days:
                d -= timedelta(days=1)
            while d in days:
                run += 1
                d -= timedelta(days=1)
            if run >= n:
                yield c, f"streak:{d + timedelta(days=1)}"
    elif t == "weight_flat":
        weeks = int(cfg.get("weeks", 3))
        since = today - timedelta(weeks=weeks)
        for c in _clients():
            ws = list(WeightLog.objects.filter(client=c, date__gte=since).values_list("weight_kg", "date"))
            if len(ws) < max(2, weeks):
                continue
            kgs = [w for w, _ in ws]
            spans_period = min(d for _, d in ws) <= since + timedelta(days=3)
            if spans_period and max(kgs) - min(kgs) <= 0.3:
                yield c, f"flat:{today.isocalendar()[1]}"


def poll_triggers(now=None):
    now = timezone.localtime(now or timezone.now())
    started = 0
    for a in Automation.objects.filter(status=Automation.Status.ON).exclude(trigger__in=EVENT_TRIGGERS) \
            .exclude(trigger=""):
        try:
            for client, key in candidates(a, now):
                if applies_to(a, client) and start_run(a, client, key):
                    started += 1
        except Exception:
            log.exception("polling %s failed", a.id)
    return started


# ---------------------------------------------------------------- validation
def problems(automation):
    """'Not ready to turn on — <first problem>'."""
    out = []
    if not automation.trigger:
        out.append("Pick a trigger.")
    cfg = automation.trigger_config or {}
    if automation.trigger == "on_date" and not cfg.get("date"):
        out.append("Pick the date.")
    if automation.trigger == "form_sent" and not cfg.get("form"):
        out.append("Pick the form.")
    steps = list(automation.steps.all())
    if not steps:
        out.append("Add at least one step.")
    if steps and steps[-1].kind == Step.Kind.WAIT:
        out.append("The last step is a wait. Add what should happen after it.")
    from apps.notifications.models import MessageTemplate

    for i, s in enumerate(steps, start=1):
        c = s.config or {}
        if s.kind == Step.Kind.MESSAGE:
            if not MessageTemplate.objects.filter(key=c.get("template")).exists():
                out.append(f"Step {i}: pick a message template.")
            if not c.get("channels"):
                out.append(f"Step {i}: pick at least one channel.")
        elif s.kind == Step.Kind.FORM and _resolve_form(c) is None:
            out.append(f"Step {i}: pick a published form.")
        elif s.kind == Step.Kind.TASK and not (c.get("title") or "").strip():
            out.append(f"Step {i}: name the task.")
        elif s.kind == Step.Kind.WAIT and not (int(c.get("days", 0) or 0) or int(c.get("hours", 0) or 0)):
            out.append(f"Step {i}: set how long to wait.")
    return out
