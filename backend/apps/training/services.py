from datetime import timedelta

from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import Max
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from apps.activity.services import log as activity_log
from apps.notifications.services import notify

from .models import (
    AssignmentStatus,
    Program,
    ProgramAssignment,
    ProgramDay,
    ProgramExercise,
    ProgramWeek,
    SetLog,
    WorkoutLog,
)

User = get_user_model()

EXERCISE_FIELDS = ["exercise_id", "order", "superset_group", "sets", "reps", "rpe", "rest_seconds", "tempo",
                   "target_weight_kg", "note", "override"]


# ---------------------------------------------------------------- program tree
def new_program(*, name, weeks, days_per_week, goal_line="", actor=None):
    """New program modal: N weeks, the first `days_per_week` days are workout days, the rest rest days."""
    with transaction.atomic():
        p = Program.objects.create(name=name, weeks=weeks, days_per_week=days_per_week, goal_line=goal_line,
                                   created_by=actor)
        for n in range(1, weeks + 1):
            w = ProgramWeek.objects.create(program=p, number=n)
            ProgramDay.objects.bulk_create([
                ProgramDay(week=w, weekday=i, is_rest=i >= days_per_week,
                           name="" if i < days_per_week else "Rest") for i in range(7)
            ])
    return p


def copy_tree(src, dst):
    """Copy every week/day/exercise of `src` into the (empty) program `dst`."""
    for w in src.program_weeks.prefetch_related("days__exercises"):
        nw = ProgramWeek.objects.create(program=dst, number=w.number)
        for d in w.days.all():
            nd = ProgramDay.objects.create(week=nw, weekday=d.weekday, name=d.name, is_rest=d.is_rest,
                                           rest_note=d.rest_note)
            ProgramExercise.objects.bulk_create([
                ProgramExercise(day=nd, **{f: getattr(e, f) for f in EXERCISE_FIELDS}) for e in d.exercises.all()
            ])


@transaction.atomic
def duplicate_program(src, *, actor=None, name=None, as_master=True, master=None):
    dst = Program.objects.create(name=name or f"{src.name} (copy)"[:120], goal_line=src.goal_line,
                                 weeks=src.weeks, days_per_week=src.days_per_week, is_master=as_master,
                                 master=master, created_by=actor)
    copy_tree(src, dst)
    return dst


@transaction.atomic
def sync_structure(program, weeks_data):
    """Make the program's tree equal `weeks_data`. Rows with an id are updated in place, so workouts
    already logged against a day keep pointing at it; rows without an id are created; the rest go."""
    existing_weeks = {w.id: w for w in program.program_weeks.all()}
    keep_weeks = set()
    # Week numbers are unique: park the kept ones on high numbers first so renumbering never clashes.
    for w in program.program_weeks.all():
        w.number += 1000
        w.save(update_fields=["number"])
    for wd in weeks_data:
        w = existing_weeks.get(wd.get("id")) if wd.get("id") else None
        if w is None:
            w = ProgramWeek.objects.create(program=program, number=wd["number"])
        else:
            w.number = wd["number"]
            w.save(update_fields=["number"])
        keep_weeks.add(w.id)
        existing_days = {d.id: d for d in w.days.all()}
        for d in w.days.all():
            d.weekday += 10
            d.save(update_fields=["weekday"])
        keep_days = set()
        for dd in wd.get("days", []):
            d = existing_days.get(dd.get("id")) if dd.get("id") else None
            if d is None:
                # a day moved in from another week keeps its id
                d = ProgramDay.objects.filter(id=dd.get("id"), week__program=program).first() if dd.get("id") else None
            if d is None:
                d = ProgramDay(week=w)
            d.week = w
            d.weekday = dd["weekday"]
            d.name = dd.get("name", "")
            d.is_rest = dd.get("is_rest", False)
            d.rest_note = dd.get("rest_note", "")
            d.save()
            keep_days.add(d.id)
            existing_ex = {e.id: e for e in d.exercises.all()}
            keep_ex = set()
            for i, ed in enumerate(dd.get("exercises", [])):
                e = existing_ex.get(ed.get("id")) if ed.get("id") else None
                if e is None:
                    e = ProgramExercise(day=d)
                e.exercise = ed["exercise"]
                e.order = i
                for f in ("superset_group", "sets", "reps", "rpe", "rest_seconds", "tempo", "target_weight_kg",
                          "note", "override"):
                    if f in ed:
                        setattr(e, f, ed[f])
                e.save()
                keep_ex.add(e.id)
            d.exercises.exclude(id__in=keep_ex).delete()
        w.days.exclude(id__in=keep_days).delete()
    program.program_weeks.exclude(id__in=keep_weeks).delete()
    n = len(weeks_data)
    week1 = next((w for w in weeks_data if w["number"] == 1), None)
    program.weeks = n
    if week1:
        program.days_per_week = sum(1 for d in week1.get("days", []) if not d.get("is_rest"))
    program.save(update_fields=["weeks", "days_per_week", "updated_at"])
    return program


@transaction.atomic
def copy_week(program, number):
    """Copy week N → N+1 (replacing it), or on the last week make a new week."""
    src = program.program_weeks.prefetch_related("days__exercises").get(number=number)
    dst = program.program_weeks.filter(number=number + 1).first()
    if dst is None:
        dst = ProgramWeek.objects.create(program=program, number=number + 1)
        program.weeks = max(program.weeks, number + 1)
        program.save(update_fields=["weeks", "updated_at"])
    else:
        dst.days.all().delete()
    for d in src.days.all():
        nd = ProgramDay.objects.create(week=dst, weekday=d.weekday, name=d.name, is_rest=d.is_rest,
                                       rest_note=d.rest_note)
        ProgramExercise.objects.bulk_create([
            ProgramExercise(day=nd, **{f: getattr(e, f) for f in EXERCISE_FIELDS}) for e in d.exercises.all()
        ])
    return dst


# ---------------------------------------------------------------- assigning
def _current(client):
    return ProgramAssignment.objects.filter(client=client, status=AssignmentStatus.ACTIVE).order_by(
        "-start_date").first()


@transaction.atomic
def assign_program(client, program_id, *, actor=None, start_date=None, when="now", notify_client=True):
    program = program_id if isinstance(program_id, Program) else Program.objects.filter(id=program_id).first()
    if program is None or program.archived_at:
        raise ValidationError({"program": ["Pick an active program."]})
    today = timezone.localdate()
    current = _current(client)
    status = AssignmentStatus.ACTIVE
    if when == "after_current" and current:
        cur_end = current.end_date or current.start_date + timedelta(weeks=current.effective_program.weeks)
        start_date = cur_end + timedelta(days=1)
        status = AssignmentStatus.UP_NEXT
    else:
        start_date = start_date or client.client_profile.start_date or today
        if start_date > today:
            status = AssignmentStatus.UP_NEXT
        elif current:
            current.status = AssignmentStatus.ENDED
            current.end_date = today
            current.save(update_fields=["status", "end_date", "updated_at"])
    a = ProgramAssignment.objects.create(
        client=client, program=program, start_date=start_date, status=status, assigned_by=actor,
        end_date=start_date + timedelta(weeks=program.weeks) - timedelta(days=1),
    )
    activity_log("assigned a workout plan", "plan", actor=actor, target=client, target_label=program.name,
                 client=client)
    if notify_client and status == AssignmentStatus.ACTIVE:
        notify(client, "plan_assigned", f"New workout plan: {program.name}", "Open Train to see today's workout.",
               actor=actor, data={"route": "/train"})
    if status == AssignmentStatus.ACTIVE:
        from apps.automations.engine import fire_event

        transaction.on_commit(lambda: fire_event("plan_starts", client, dedupe=f"pa:{a.id}"))
    return a


@transaction.atomic
def set_program_clients(program, client_ids, *, actor):
    """Assign drawer: the program's followers become exactly `client_ids`."""
    current = set(ProgramAssignment.objects.filter(program=program, status=AssignmentStatus.ACTIVE)
                  .values_list("client_id", flat=True))
    wanted = set(client_ids)
    added, removed = wanted - current, current - wanted
    from apps.clients.services import visible_clients

    clients = {u.id: u for u in visible_clients(actor).filter(id__in=added).select_related("client_profile")}
    for cid in added:
        if cid in clients:
            assign_program(clients[cid], program, actor=actor, start_date=timezone.localdate())
    if removed:
        ProgramAssignment.objects.filter(program=program, status=AssignmentStatus.ACTIVE,
                                         client_id__in=removed).update(status=AssignmentStatus.ENDED,
                                                                       end_date=timezone.localdate())
    return len([c for c in added if c in clients]), len(removed)


@transaction.atomic
def customise_for_client(assignment, *, actor):
    """'Edit X for Riya' — the client gets their own copy; the master stays the same."""
    if assignment.custom_program_id:
        return assignment.custom_program
    copy = duplicate_program(assignment.program, actor=actor, name=assignment.program.name, as_master=False,
                             master=assignment.program)
    assignment.custom_program = copy
    assignment.save(update_fields=["custom_program", "updated_at"])
    _relink_logs(assignment, copy)
    activity_log("edited a plan for one client", "plan", actor=actor, target=assignment.client,
                 target_label=copy.name, client=assignment.client)
    return copy


def _relink_logs(assignment, program):
    """Point today's in-progress workout at the matching day of the new tree."""
    for wl in WorkoutLog.objects.filter(assignment=assignment, status=WorkoutLog.Status.IN_PROGRESS,
                                        program_day__isnull=False).select_related("program_day__week"):
        pd = ProgramDay.objects.filter(week__program=program, week__number=wl.program_day.week.number,
                                       weekday=wl.program_day.weekday).first()
        wl.program_day = pd
        wl.save(update_fields=["program_day"])


@transaction.atomic
def reset_to_master(assignment, *, actor):
    custom = assignment.custom_program
    if not custom:
        return assignment
    assignment.custom_program = None
    assignment.save(update_fields=["custom_program", "updated_at"])
    _relink_logs(assignment, assignment.program)
    custom.soft_delete()
    activity_log("reset a plan to master", "plan", actor=actor, target=assignment.client,
                 target_label=assignment.program.name, client=assignment.client)
    return assignment


def end_assignment(assignment, *, actor):
    assignment.status = AssignmentStatus.ENDED
    assignment.end_date = timezone.localdate()
    assignment.save(update_fields=["status", "end_date", "updated_at"])
    activity_log("ended a plan", "plan", actor=actor, target=assignment.client,
                 target_label=assignment.effective_program.name, client=assignment.client)


def roll_assignments(today=None):
    """Daily: up-next plans start; finished plans end. Returns (started, ended)."""
    from apps.automations.engine import fire_event

    today = today or timezone.localdate()
    ended = 0
    for a in ProgramAssignment.objects.filter(status=AssignmentStatus.ACTIVE, end_date__lt=today):
        a.status = AssignmentStatus.ENDED
        a.save(update_fields=["status", "updated_at"])
        fire_event("plan_ends", a.client, dedupe=f"pa-end:{a.id}")
        ended += 1
    started = 0
    for a in ProgramAssignment.objects.filter(status=AssignmentStatus.UP_NEXT, start_date__lte=today) \
            .select_related("client", "program"):
        ProgramAssignment.objects.filter(client=a.client, status=AssignmentStatus.ACTIVE).update(
            status=AssignmentStatus.ENDED, end_date=today - timedelta(days=1))
        a.status = AssignmentStatus.ACTIVE
        a.save(update_fields=["status", "updated_at"])
        notify(a.client, "plan_assigned", f"New workout plan: {a.program.name}", "It starts today.",
               data={"route": "/train"})
        fire_event("plan_starts", a.client, dedupe=f"pa:{a.id}")
        started += 1
    return started, ended


# ---------------------------------------------------------------- logging
def today_plan(client, day=None):
    """Train tab: the week strip and today's planned day."""
    from apps.clients.metrics import active_program, program_day_for

    day = day or timezone.localdate()
    pa = active_program(client, day)
    monday = day - timedelta(days=day.weekday())
    done = set(WorkoutLog.objects.filter(client=client, status=WorkoutLog.Status.COMPLETED,
                                         date__range=(monday, monday + timedelta(days=6)))
               .values_list("date", flat=True))
    strip = []
    for i in range(7):
        d = monday + timedelta(days=i)
        pd = program_day_for(pa, d)
        strip.append({"date": d, "name": pd.name if pd else "", "is_rest": (pd is None) or pd.is_rest,
                      "done": d in done, "today": d == day})
    pd = program_day_for(pa, day)
    week = (day - pa.start_date).days // 7 + 1 if pa else None
    return pa, pd, strip, week


def last_performance(client, exercise_ids):
    """'Prev' column and 'Last time: 40 kg × 6': the best working set of the last workout per exercise."""
    out = {}
    rows = (SetLog.objects.filter(workout__client=client, workout__status=WorkoutLog.Status.COMPLETED,
                                  exercise_id__in=exercise_ids, done=True, is_warmup=False)
            .order_by("exercise_id", "-workout__date", "set_number")
            .values("exercise_id", "workout_id", "set_number", "weight_kg", "reps", "seconds", "is_bodyweight"))
    for r in rows:
        ex = r["exercise_id"]
        bucket = out.setdefault(ex, {"workout": r["workout_id"], "sets": []})
        if bucket["workout"] == r["workout_id"]:
            bucket["sets"].append({"set": r["set_number"], "weight_kg": r["weight_kg"], "reps": r["reps"],
                                   "seconds": r["seconds"], "bw": r["is_bodyweight"]})
    return {k: v["sets"] for k, v in out.items()}


def personal_bests(client, exercise_ids):
    rows = (SetLog.objects.filter(workout__client=client, exercise_id__in=exercise_ids, done=True, is_warmup=False,
                                  weight_kg__isnull=False)
            .values("exercise_id").annotate(best=Max("weight_kg")))
    best = {r["exercise_id"]: r["best"] for r in rows}
    out = {}
    for ex, w in best.items():
        s = (SetLog.objects.filter(workout__client=client, exercise_id=ex, done=True, is_warmup=False, weight_kg=w)
             .order_by("-reps").first())
        out[ex] = {"weight_kg": w, "reps": s.reps if s else None}
    return out


@transaction.atomic
def start_workout(client, *, program_day=None, name=""):
    open_one = WorkoutLog.objects.filter(client=client, status=WorkoutLog.Status.IN_PROGRESS).first()
    if open_one:
        return open_one, False  # "Leaving this screen does not stop it"
    from apps.clients.metrics import active_program

    pa = active_program(client)
    planned_sets = 0
    if program_day is not None:
        planned_sets = sum(e.sets for e in program_day.exercises.all())
        name = name or program_day.name
    wl = WorkoutLog.objects.create(client=client, assignment=pa, program_day=program_day, name=name or "Workout",
                                   sets_planned=planned_sets)
    if program_day is not None:
        sets = []
        for e in program_day.exercises.select_related("exercise"):
            for n in range(1, e.sets + 1):
                sets.append(SetLog(workout=wl, program_exercise=e, exercise=e.exercise, set_number=n,
                                   weight_kg=e.target_weight_kg,
                                   is_bodyweight=e.exercise.log_type == "bodyweight_reps"))
        SetLog.objects.bulk_create(sets)
    return wl, True


def mark_set(set_log, *, done):
    """Tick a set. Returns True when it's a new best (weight) for this exercise."""
    set_log.done = done
    set_log.done_at = timezone.now() if done else None
    is_pr = False
    if done and not set_log.is_warmup and set_log.weight_kg is not None:
        prev = (SetLog.objects.filter(workout__client=set_log.workout.client, exercise=set_log.exercise, done=True,
                                      is_warmup=False, weight_kg__isnull=False)
                .exclude(id=set_log.id).aggregate(m=Max("weight_kg"))["m"])
        is_pr = prev is not None and set_log.weight_kg > prev
    set_log.is_pr = is_pr
    set_log.save(update_fields=["done", "done_at", "is_pr"])
    return is_pr


@transaction.atomic
def finish_workout(wl, *, effort=None, note="", duration_seconds=None, time_breakdown=None, auto=False):
    wl.status = WorkoutLog.Status.COMPLETED
    wl.finished_at = timezone.now()
    if auto:
        last = wl.sets.filter(done=True).order_by("-done_at").first()
        wl.finished_at = last.done_at if last else wl.started_at
    wl.duration_seconds = duration_seconds if duration_seconds is not None else int(
        (wl.finished_at - wl.started_at).total_seconds())
    wl.time_breakdown = time_breakdown or wl.time_breakdown
    wl.effort = effort
    wl.note = note or ""
    wl.sets_done = wl.sets.filter(done=True, is_warmup=False).count()
    wl.sets_planned = max(wl.sets_planned, wl.sets.filter(is_warmup=False).count())
    wl.auto_saved = auto
    wl.save()
    wl.sets.filter(done=False).delete()
    client = wl.client
    trainer = client.client_profile.trainer
    activity_log("finished a workout", "workout", actor=None if auto else client, target=wl, target_label=wl.name,
                 client=client, meta={"sets_done": wl.sets_done, "sets_planned": wl.sets_planned})
    if trainer:
        from apps.notifications.realtime import send_to_user

        # live refresh of the trainer's dashboard / client logs; no push for every workout
        transaction.on_commit(lambda: send_to_user(trainer.id, "client_activity", {
            "client": str(client.id), "kind": "workout_done", "workout": str(wl.id)}))
    return wl


def auto_save_stale_workouts():
    """'If you don't answer, the workout is saved at your last set after 3 hours.'"""
    cutoff = timezone.now() - timedelta(hours=3)
    n = 0
    for wl in WorkoutLog.objects.filter(status=WorkoutLog.Status.IN_PROGRESS, started_at__lt=cutoff) \
            .select_related("client__client_profile"):
        last = wl.sets.filter(done=True).order_by("-done_at").first()
        if last is None:
            if wl.started_at < cutoff:
                wl.status = WorkoutLog.Status.DISCARDED
                wl.save(update_fields=["status"])
            continue
        if last.done_at < cutoff:
            finish_workout(wl, auto=True)
            n += 1
    return n
