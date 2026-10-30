"""Scheduled reminders (Celery beat). Each one is sent at most once per (person, kind, thing, day)
thanks to ReminderLog, so a slow or repeated beat never double-sends.

Times are local (settings.TIME_ZONE). Beat runs most of these every 15 minutes; each job looks at the
15-minute window that starts now.
"""
import logging
from datetime import datetime, timedelta

from celery import shared_task
from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.utils import timezone

from .models import ReminderLog, ReminderPreference, StaffNotificationPreference
from .services import notify, send_template
from apps.common.utils import dfmt

log = logging.getLogger("reminders")
User = get_user_model()
WINDOW = timedelta(minutes=15)


def once(user, kind, ref, day):
    """True the first time only."""
    try:
        with transaction.atomic():
            ReminderLog.objects.create(user=user, kind=kind, ref=str(ref)[:60], day=day)
        return True
    except IntegrityError:
        return False


def _prefs(user):
    p = getattr(user, "reminder_prefs", None)
    return p or ReminderPreference(user=user)


def _active_clients():
    return (User.objects.filter(role="client", status="active", is_active=True,
                                client_profile__removed_at__isnull=True)
            .select_related("client_profile", "reminder_prefs"))


def _local_now():
    return timezone.localtime()


# ---------------------------------------------------------------- workouts and sessions
@shared_task
def workout_reminders():
    """'1 hour before your session or planned workout'."""
    from apps.clients.metrics import active_program, program_day_for
    from apps.scheduling.models import Session

    now = timezone.now()
    sent = 0
    for s in Session.objects.filter(status="booked", reminder_sent_at__isnull=True,
                                    start__gte=now + timedelta(minutes=45), start__lt=now + timedelta(minutes=75)) \
            .select_related("client", "trainer"):
        if _prefs(s.client).workout:
            where = "on a call" if s.is_call else (s.place or "at the gym")
            notify(s.client, "session_reminder", f"{s.get_kind_display()} in 1 hour",
                   f"With {s.trainer.first_name} at {dfmt(timezone.localtime(s.start), '%-I:%M %p')} · {where}",
                   data={"route": "/train"})
            sent += 1
        s.reminder_sent_at = now
        s.save(update_fields=["reminder_sent_at"])
    local = _local_now()
    today = local.date()
    for c in _active_clients():
        p = _prefs(c)
        if not p.workout:
            continue
        at = timezone.make_aware(datetime.combine(today, p.workout_time)) - timedelta(hours=1)
        if not (at <= local < at + WINDOW):
            continue
        pd = program_day_for(active_program(c, today), today)
        if pd is None or pd.is_rest:
            continue
        if Session.objects.filter(client=c, start__date=today).exclude(status="cancelled").exists():
            continue  # the session reminder covers it
        if once(c, "workout", pd.id, today):
            notify(c, "workout_reminder", f"Today: {pd.name or 'your workout'}",
                   "Your workout is planned in an hour.", data={"route": "/train"})
            sent += 1
    return sent


# ---------------------------------------------------------------- meals
@shared_task
def meal_reminders():
    from apps.nutrition.models import MealDayState, MealPlanAssignment, meals_on
    from apps.nutrition.services import meal_kcal

    local = _local_now()
    today = local.date()
    sent = 0
    rows = (MealPlanAssignment.objects.filter(status="active", start_date__lte=today, client__status="active",
                                              plan__status="published")
            .select_related("client__reminder_prefs", "plan", "custom_plan"))
    for a in rows:
        if not _prefs(a.client).meal:
            continue
        for m in meals_on(a.followed, today.weekday()):  # the client's own copy and that weekday's meals
            at = timezone.make_aware(datetime.combine(today, m.time))
            if not (at <= local < at + WINDOW):
                continue
            if MealDayState.objects.filter(client=a.client, date=today, meal=m, status__in=["logged", "skipped"]) \
                    .exists():
                continue
            if once(a.client, "meal", m.id, today):
                # what the meal's foods add up to, not a separate meal target (Probid 2026-10-30)
                kcal = meal_kcal(a.client, m, today)
                notify(a.client, "meal_reminder", f"{m.name} time", f"{kcal:,} kcal planned. Tap to log it.",
                       data={"route": "/food"})
                sent += 1
    return sent


# ---------------------------------------------------------------- check-ins
@shared_task
def checkin_reminders():
    """Weekly check-in due today (a week after the last one), at 9 am."""
    from apps.checkins.models import Submission

    local = _local_now()
    if not (local.hour == 9 and local.minute < 15):
        return 0
    today = local.date()
    sent = 0
    for c in _active_clients():
        if not _prefs(c).checkin:
            continue
        last = Submission.objects.filter(client=c, form_type="weekly").order_by("-date").first()
        start = c.client_profile.start_date or c.date_joined.date()
        due = (last.date + timedelta(days=7)) if last else start + timedelta(days=7)
        if due == today and once(c, "checkin", due, today):
            send_template(c, "checkin-reminder", data={"route": "/checkins"})
            sent += 1
    return sent


# ---------------------------------------------------------------- water and supplements
WATER_HOURS = (10, 12, 14, 16, 18, 20)  # "every 2 hours when you are behind"
SUPP_TIMES = {"breakfast": 8, "morning": 8, "pre_workout": None, "post_workout": None, "any": 12, "night": 21, "before_bed": 22}


@shared_task
def water_reminders():
    """Every 2 hours from 10 am to 8 pm when today's water is behind the day's pace (7 am – 10 pm)."""
    from apps.clients.metrics import active_meal_plan
    from apps.nutrition.models import WaterLog

    local = _local_now()
    if local.hour not in WATER_HOURS or local.minute >= 15:
        return 0
    today = local.date()
    sent = 0
    for c in _active_clients():
        if not _prefs(c).water:
            continue
        mp = active_meal_plan(c, today)
        goal = mp.plan.water_ml if mp else 0
        if not goal:
            continue
        had = WaterLog.objects.filter(client=c, date=today).values_list("ml", flat=True).first() or 0
        due = goal * min(1, (local.hour - 7) / 15)
        behind = due - had
        if behind >= 500 and once(c, "water", local.hour, today):
            left = f"{behind / 1000:.1f}".rstrip("0").rstrip(".")
            notify(c, "water_reminder", "Water reminder",
                   f"You are {left} L behind for the day at {dfmt(local, '%-I:%M %p').lower()}.",
                   data={"route": "/habits"})
            sent += 1
    return sent


@shared_task
def supplement_reminders():
    """At the supplement's time of day (breakfast / morning 8 am, any time noon, night 9 pm, before bed 10 pm),
    for the ones not taken yet. Post-workout ones have no clock time, so no reminder."""
    from apps.habits.models import SupplementAssignment, SupplementLog

    local = _local_now()
    if local.minute >= 15:
        return 0
    today = local.date()
    timings = [t for t, h in SUPP_TIMES.items() if h == local.hour]
    if not timings:
        return 0
    sent = 0
    for c in _active_clients():
        if not _prefs(c).supps:
            continue
        items = [i for a in SupplementAssignment.objects.filter(client=c, active=True, start_date__lte=today)
                 .prefetch_related("plan__items", "custom_plan__items") for i in a.followed.items.all()
                 if i.timing in timings and (not i.days or today.weekday() in i.days)]
        taken = set(SupplementLog.objects.filter(client=c, date=today).values_list("item_id", flat=True))
        left = [i for i in items if i.id not in taken]
        if left and once(c, "supps", local.hour, today):
            names = " and ".join(i.name for i in left[:2]) + (f" and {len(left) - 2} more" if len(left) > 2 else "")
            notify(c, "supplement_reminder", "Supplement time", f"{names} · tap to mark as taken.",
                   data={"route": "/habits"})
            sent += 1
    return sent


# ---------------------------------------------------------------- habits
@shared_task
def habit_reminders():
    """8 pm: habits due today and not done yet."""
    from apps.habits.models import HabitAssignment, HabitLog

    local = _local_now()
    if not (local.hour == 20 and local.minute < 15):
        return 0
    today = local.date()
    sent = 0
    for c in _active_clients():
        if not _prefs(c).habit:
            continue
        due = [a.habit for a in HabitAssignment.objects.filter(client=c, active=True).select_related("habit")
               if a.habit.is_due_on(today) and a.habit.frequency != "times_week"]
        done = set(HabitLog.objects.filter(client=c, date=today, done=True).values_list("habit_id", flat=True))
        left = [h for h in due if h.id not in done]
        if left and once(c, "habit", "evening", today):
            names = ", ".join(h.name for h in left[:2]) + (f" and {len(left) - 2} more" if len(left) > 2 else "")
            notify(c, "habit_reminder", "Habits left today", names, data={"route": "/habits"})
            sent += 1
    return sent


# ---------------------------------------------------------------- onboarding
@shared_task
def onboarding_reminders():
    """Setup not finished. The time the client picked in "Finish setup later?" wins;
    otherwise next day, 9 am (up to 3 days). "Off" stops both."""
    local = _local_now()
    sent = 0
    picked = _active_clients().filter(client_profile__onboarding__has_key="_remind")
    for c in picked:
        cp = c.client_profile
        r = cp.onboarding.get("_remind") or {}
        if r.get("sent") or not r.get("at") or len(cp.client_steps_done) >= 5:
            continue
        if datetime.fromisoformat(r["at"]) <= local:
            send_template(c, "onboarding-form-reminder", data={"route": "/welcome"})
            cp.onboarding["_remind"] = {**r, "sent": True}
            cp.save(update_fields=["onboarding"])
            sent += 1
    if not (local.hour == 9 and local.minute < 15):
        return sent
    today = local.date()
    for c in _active_clients().filter(date_joined__date__lt=today,
                                      date_joined__date__gte=today - timedelta(days=3)):
        cp = c.client_profile
        if len(cp.onboarding_done or []) >= 5 or (cp.onboarding or {}).get("_remind"):
            continue
        if once(c, "onboarding", "setup", today):
            send_template(c, "onboarding-form-reminder", data={"route": "/welcome"})
            sent += 1
    return sent


# ---------------------------------------------------------------- team
@shared_task
def document_expiry_reminders():
    """'Remind me before it expires' — 30 days before, on the Dashboard (and a notice)."""
    from apps.trainers.models import TrainerDocument

    today = timezone.localdate()
    admin = User.objects.filter(role="admin").first()
    sent = 0
    for d in TrainerDocument.objects.filter(remind_before_expiry=True, expires_on__isnull=False,
                                            expires_on__lte=today + timedelta(days=30),
                                            expires_on__gte=today).select_related("trainer__user"):
        if admin and once(admin, "doc_expiry", d.id, d.expires_on):
            days = (d.expires_on - today).days
            notify(admin, "document_expiring", f"{d.trainer.user.full_name}: {d.name} expires in {days} days",
                   "Ask for the new certificate.", data={"route": f"/trainers/{d.trainer.user_id}?tab=documents"})
            sent += 1
    return sent


@shared_task
def nightly_client_stats():
    """Adherence + at-risk for every active client; tells the trainer about new at-risk clients."""
    from apps.clients.metrics import refresh_client_stats

    from .staff import team_alert
    from apps.clients.models import ClientProfile

    n = 0
    newly = []
    for cp in ClientProfile.objects.filter(removed_at__isnull=True, user__status="active").select_related(
            "user", "trainer").iterator(chunk_size=200):
        try:
            if refresh_client_stats(cp):
                newly.append(cp)
        except Exception:
            log.exception("stats failed for %s", cp.user_id)
        n += 1
    for cp in newly:
        t = cp.trainer
        if t is None:
            continue
        team_alert("missed_workout", cp.user, f"{cp.user.full_name} needs you", cp.at_risk_reason,
                   notify_event="client_at_risk", trainer=t, pref="missed_workouts",
                   data={"route": f"/clients/{cp.user_id}"})
    return n


# ---------------------------------------------------------------- coach notices (D-60)
@shared_task
def coach_daily_notices(today=None):
    """9 am, to each client's trainer: "Riya missed yesterday's workout" (a planned training day with no finished
    workout and no session; bell only, Me → Notifications → Missed workouts) and "Riya's plan ends Fri, 6 Nov"
    (once per plan, 7 days before; bell and push)."""
    from apps.clients.metrics import active_program, program_day_for
    from apps.scheduling.models import Session
    from apps.training.models import AssignmentStatus, ProgramAssignment, WorkoutLog

    from .staff import coach_notice

    today = today or _local_now().date()
    yday = today - timedelta(days=1)
    sent = 0
    for c in _active_clients().filter(client_profile__trainer__isnull=False):
        pd = program_day_for(active_program(c, yday), yday)
        if pd is None or pd.is_rest:
            continue
        if WorkoutLog.objects.filter(client=c, date=yday, status=WorkoutLog.Status.COMPLETED).exists():
            continue
        if Session.objects.filter(client=c, start__date=yday).exclude(status="cancelled").exists():
            continue
        if once(c, "missed_coach", pd.id, yday):
            sent += len(coach_notice(c, "client_missed_workout", f"{c.first_name} missed yesterday’s workout",
                                     pd.name or "Planned training day", pref="missed_workouts",
                                     route=f"/clients/{c.id}?tab=logs"))
    for a in (ProgramAssignment.objects.filter(status=AssignmentStatus.ACTIVE, end_date__gte=today,
                                               end_date__lte=today + timedelta(days=7),
                                               client__client_profile__trainer__isnull=False)
              .select_related("client__client_profile__trainer", "program", "custom_program")):
        if once(a.client, "plan_end_coach", a.id, a.end_date):
            days = (a.end_date - today).days
            when = "today" if days == 0 else ("tomorrow" if days == 1 else dfmt(a.end_date, "%a, %-d %b"))
            sent += len(coach_notice(a.client, "client_plan_ending", f"{a.client.first_name}’s plan ends {when}",
                                     f"{a.effective_program.name} · pick what comes next", push=True))
    return sent


# ---------------------------------------------------------------- housekeeping
@shared_task
def roll_plans():
    from apps.nutrition.services import roll_meal_plans
    from apps.training.services import roll_assignments

    roll_meal_plans()
    return roll_assignments()


@shared_task
def auto_save_workouts():
    from apps.training.services import auto_save_stale_workouts

    return auto_save_stale_workouts()


@shared_task
def purge_deleted():
    """Soft-deleted rows and removed clients are kept 30 days for Undo / restore, then removed."""
    from django.apps import apps as django_apps

    from apps.clients.models import ClientProfile
    from apps.common.models import SoftDeleteModel

    cutoff = timezone.now() - timedelta(days=30)
    total = 0
    for model in django_apps.get_models():
        if issubclass(model, SoftDeleteModel) and not model._meta.abstract:
            try:
                n, _ = model.all_objects.filter(deleted_at__lt=cutoff).delete()
                total += n
            except Exception:  # protected rows (e.g. a food used in logs) stay soft-deleted
                log.info("kept protected rows of %s", model.__name__)
    for cp in ClientProfile.objects.filter(removed_at__lt=cutoff).select_related("user"):
        cp.user.delete()
        total += 1
    ReminderLog.objects.filter(day__lt=timezone.localdate() - timedelta(days=60)).delete()
    from apps.common.models import IdempotencyRecord

    IdempotencyRecord.objects.filter(created_at__lt=timezone.now() - timedelta(days=14)).delete()
    return total


# ---------------------------------------------------------------- team: Daily summary
DAILY_SUMMARY_HOUR = 8  # Trainer Me → Notifications: "Email at 8:00 am with your day"


@shared_task
def daily_summaries():
    """8 am: one message a trainer with Daily summary on (bell, push, email): today's sessions, check-ins to
    review and clients who need you, the same numbers as the Dashboard."""
    from .staff import send_daily_summary, team

    local = _local_now()
    if not (local.hour == DAILY_SUMMARY_HOUR and local.minute < 15):
        return 0
    today = local.date()
    sent = 0
    for u in team("daily_summary"):
        if once(u, "daily_summary", "day", today):
            try:
                send_daily_summary(u)
                sent += 1
            except Exception:
                log.exception("daily summary failed for %s", u.id)
    return sent


@shared_task
def staff_digests():
    """8 am: Emails & alerts → Daily digest (Off / Daily / Weekly on Mondays), one email a staff member."""
    from .staff import send_digests

    local = _local_now()
    if not (local.hour == DAILY_SUMMARY_HOUR and local.minute < 15):
        return 0
    return len(send_digests(local, first=lambda u: once(u, "digest", "day", local.date())))
