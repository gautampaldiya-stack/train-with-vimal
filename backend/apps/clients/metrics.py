"""Numbers shown about a client: adherence, the Last 7 days grid, weight trend.

Adherence (design footnote) = share of planned workouts and meals done in the last N days.
"""
from datetime import timedelta

from django.db.models import Count, Q
from django.utils import timezone
from apps.common.utils import dfmt


def active_program(client, on=None):
    from apps.training.models import AssignmentStatus, ProgramAssignment

    on = on or timezone.localdate()
    return (ProgramAssignment.objects.filter(client=client, status=AssignmentStatus.ACTIVE, start_date__lte=on)
            .select_related("program", "custom_program").order_by("-start_date").first())


def active_meal_plan(client, on=None):
    from apps.nutrition.models import MealPlanAssignment

    on = on or timezone.localdate()
    return (MealPlanAssignment.objects.filter(client=client, status="active", start_date__lte=on)
            .select_related("plan").order_by("-start_date").first())


def program_day_for(assignment, day):
    """The ProgramDay planned on `day` for this assignment, or None (rest / outside the plan)."""
    from apps.training.models import ProgramDay

    if assignment is None or day < assignment.start_date:
        return None
    program = assignment.effective_program
    week_no = (day - assignment.start_date).days // 7 + 1
    if week_no > program.weeks:
        return None
    return (ProgramDay.objects.filter(week__program=program, week__number=week_no, weekday=day.weekday())
            .first())


def planned_workout_days(assignment, start, end):
    """Dates in [start, end] with a (non-rest) workout planned."""
    from apps.training.models import ProgramDay

    if assignment is None:
        return []
    program = assignment.effective_program
    days = {(d.week.number, d.weekday): d for d in ProgramDay.objects.filter(week__program=program, is_rest=False)
            .select_related("week")}
    out = []
    d = max(start, assignment.start_date)
    while d <= end:
        week_no = (d - assignment.start_date).days // 7 + 1
        if week_no <= program.weeks and (week_no, d.weekday()) in days:
            out.append(d)
        d += timedelta(days=1)
    return out


def adherence(client, days=7, end=None):
    """Percent of planned workouts + meals done in the last `days` days (None if nothing was planned)."""
    from apps.nutrition.models import MealDayState
    from apps.training.models import WorkoutLog

    end = end or timezone.localdate() - timedelta(days=1)  # today is not over yet
    start = end - timedelta(days=days - 1)
    planned_w = planned_workout_days(active_program(client, end), start, end)
    done_w = WorkoutLog.objects.filter(client=client, status=WorkoutLog.Status.COMPLETED, date__range=(start, end))
    done_w = min(done_w.values("date").distinct().count(), len(planned_w))
    mp = active_meal_plan(client, end)
    meals_per_day = mp.plan.meals.count() if mp else 0
    meal_days = max(0, (end - max(start, mp.start_date)).days + 1) if mp else 0
    planned_m = meals_per_day * meal_days
    done_m = MealDayState.objects.filter(client=client, date__range=(start, end),
                                         status=MealDayState.Status.LOGGED).count() if mp else 0
    planned = len(planned_w) + planned_m
    if not planned:
        return None
    return round(100 * (done_w + min(done_m, planned_m)) / planned)


def last_7_days(client, end=None):
    """Overview → 'Last 7 days' grid: one column per day, rows workout / meals / check-in / habits.
    Cell values: done | missed | partial | rest | none | today."""
    from apps.checkins.models import Submission
    from apps.habits.models import HabitAssignment, HabitLog
    from apps.nutrition.models import MealDayState
    from apps.training.models import WorkoutLog

    today = timezone.localdate()
    end = end or today
    start = end - timedelta(days=6)
    pa = active_program(client, end)
    planned_w = set(planned_workout_days(pa, start, end))
    done_w = set(WorkoutLog.objects.filter(client=client, status=WorkoutLog.Status.COMPLETED,
                                           date__range=(start, end)).values_list("date", flat=True))
    mp = active_meal_plan(client, end)
    n_meals = mp.plan.meals.count() if mp else 0
    meals = dict(MealDayState.objects.filter(client=client, date__range=(start, end), status="logged")
                 .values("date").annotate(n=Count("id")).values_list("date", "n"))
    checkins = set(Submission.objects.filter(client=client, form_type="daily", date__range=(start, end))
                   .values_list("date", flat=True))
    n_habits = HabitAssignment.objects.filter(client=client, active=True).count()
    habits = dict(HabitLog.objects.filter(client=client, date__range=(start, end), done=True)
                  .values("date").annotate(n=Count("id")).values_list("date", "n"))

    def cell(planned, done, d, partial=False):
        if d > today:
            return "none"
        if done:
            return "done"
        if partial:
            return "partial"
        if not planned:
            return "rest"
        return "today" if d == today else "missed"

    cols = []
    d = start
    while d <= end:
        m = meals.get(d, 0)
        h = habits.get(d, 0)
        cols.append({
            "date": d,
            "workout": cell(d in planned_w, d in done_w, d),
            "meals": cell(n_meals > 0, n_meals and m >= n_meals, d, partial=0 < m < n_meals),
            "checkin": cell(True, d in checkins, d),
            "habits": cell(n_habits > 0, n_habits and h >= n_habits, d, partial=0 < h < n_habits),
        })
        d += timedelta(days=1)
    return cols


RANGES = {"7d": 7, "30d": 30, "90d": 90, "6m": 182}


def resolve_range(params, client):
    """Range picker on every chart: 7d / 30d / 90d / 6m / start / plan:<assignment id> / custom (from, to)."""
    from apps.training.models import ProgramAssignment

    today = timezone.localdate()
    r = params.get("range", "30d")
    if r in RANGES:
        return today - timedelta(days=RANGES[r] - 1), today
    if r == "start":
        cp = client.client_profile
        return cp.start_date or client.date_joined.date(), today
    if r.startswith("plan:"):
        pa = ProgramAssignment.objects.filter(client=client, id=r[5:]).first()
        if pa:
            return pa.start_date, min(pa.end_date or today, today)
    if r == "custom":
        from django.utils.dateparse import parse_date

        a, b = parse_date(params.get("from") or ""), parse_date(params.get("to") or "")
        if a and b and a <= b and (b - a).days <= 3660:
            return a, b
    return today - timedelta(days=29), today


def weight_series(client, start, end):
    from apps.checkins.models import WeightLog

    return [{"date": w.date, "kg": float(w.weight_kg)}
            for w in WeightLog.objects.filter(client=client, date__range=(start, end)).order_by("date")]


def refresh_client_stats(cp):
    """Nightly job: adherence + at-risk flag for one ClientProfile."""
    from apps.training.models import WorkoutLog

    client = cp.user
    a7 = adherence(client, 7)
    a30 = adherence(client, 30)
    reason = ""
    today = timezone.localdate()
    seen = client.last_seen_at
    if seen and (timezone.now() - seen).days >= 7:
        reason = f"Not opened the app for {(timezone.now() - seen).days} days"
    else:
        pa = active_program(client)
        planned = planned_workout_days(pa, today - timedelta(days=7), today - timedelta(days=1))
        done = set(WorkoutLog.objects.filter(client=client, status="completed",
                                             date__gte=today - timedelta(days=7)).values_list("date", flat=True))
        missed = [d for d in planned if d not in done]
        if len(missed) >= 2:
            reason = f"Missed {len(missed)} workouts this week"
        elif a7 is not None and a7 < 50:
            reason = f"Adherence {a7}% this week"
    cp.adherence_7d = a7
    cp.adherence_30d = a30
    was = cp.at_risk
    cp.at_risk = bool(reason)
    cp.at_risk_reason = reason
    cp.stats_updated_at = timezone.now()
    cp.save(update_fields=["adherence_7d", "adherence_30d", "at_risk", "at_risk_reason", "stats_updated_at"])
    return (not was) and cp.at_risk


def needs_attention(client):
    """Overview → Needs attention: flagged notes, check-ins to review, missed workouts."""
    from apps.checkins.models import Submission
    from apps.training.models import WorkoutLog

    from .models import ClientNote

    items = []
    for n in ClientNote.objects.filter(client=client, is_flag=True)[:3]:
        items.append({"kind": "flag", "title": n.body.split("\n")[0][:80], "detail": n.body[80:200].strip(),
                      "id": str(n.id)})
    for s in Submission.objects.filter(client=client, reviewed_at__isnull=True,
                                       form_type__in=["weekly", "daily"]).order_by("-created_at")[:2]:
        label = f"Week {s.week_number} check-in to review" if s.week_number else "Check-in to review"
        items.append({"kind": "checkin", "title": label, "detail": f"Sent {dfmt(s.created_at, '%a, %-d %b')}",
                      "id": str(s.id)})
    today = timezone.localdate()
    pa = active_program(client)
    planned = planned_workout_days(pa, today - timedelta(days=7), today - timedelta(days=1))
    done = set(WorkoutLog.objects.filter(client=client, status="completed",
                                         date__gte=today - timedelta(days=7)).values_list("date", flat=True))
    for d in [d for d in planned if d not in done][-2:]:
        pd = program_day_for(pa, d)
        items.append({"kind": "missed", "title": f"Missed {pd.name or 'a workout'} on {d:%A}" if pd
                      else f"Missed a workout on {d:%A}", "detail": "", "date": d})
    return items


def counts_between(client, start, end):
    from apps.checkins.models import Submission
    from apps.training.models import WorkoutLog

    pa = active_program(client, end)
    return {
        "workouts_done": WorkoutLog.objects.filter(client=client, status="completed",
                                                   date__range=(start, end)).count(),
        "workouts_planned": len(planned_workout_days(pa, start, end)),
        "checkins_sent": Submission.objects.filter(client=client, form_type="weekly",
                                                   date__range=(start, end)).count(),
        "checkins_reviewed": Submission.objects.filter(Q(reviewed_at__isnull=False), client=client,
                                                       form_type="weekly", date__range=(start, end)).count(),
    }
