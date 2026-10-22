"""Client profile → Logs tab (staff): the range summary line, Compare plans, and coach comments.

The tables themselves come from the app that owns the data (training `clients/<id>/workouts/`, nutrition
`clients/<id>/food/`, checkins `clients/<id>/checkins/`, habits `clients/<id>/habits/`); they share
`page_of` and `days_desc` from here so every log pages the same way.
"""
from collections import Counter
from datetime import timedelta

from django.db.models import Avg, Count, Q
from django.utils import timezone

from apps.common.utils import dfmt

LOG_PAGE_SIZE = 10


def page_of(rows, params, size=LOG_PAGE_SIZE):
    """{count, page, page_size, results} for one page (`?page=`, `?page_size=` up to 50) of a built list."""
    try:
        size = max(1, min(50, int(params.get("page_size") or size)))
    except (TypeError, ValueError):
        pass
    try:
        page = max(1, int(params.get("page") or 1))
    except (TypeError, ValueError):
        page = 1
    return {"count": len(rows), "page": page, "page_size": size, "results": rows[(page - 1) * size:page * size]}


def client_start(client):
    cp = client.client_profile
    return cp.start_date or client.date_joined.date()


def days_desc(start, end, client=None):
    """Days of a log range, newest first; never before the client joined or after today."""
    today = timezone.localdate()
    if client is not None:
        start = max(start, client_start(client))
    end = min(end, today)
    out, d = [], end
    while d >= start:
        out.append(d)
        d -= timedelta(days=1)
    return out


def summary(client, start, end):
    """'14 workouts · 138 meals logged · 27 check-ins' for the picked range."""
    from apps.checkins.models import Submission
    from apps.nutrition.models import MealDayState
    from apps.training.models import WorkoutLog

    return {
        "from": start, "to": end,
        "workouts": WorkoutLog.objects.filter(client=client, status="completed", date__range=(start, end)).count(),
        "meals": MealDayState.objects.filter(client=client, status="logged", date__range=(start, end)).count(),
        "checkins": Submission.objects.filter(client=client, form_type__in=["daily", "weekly"],
                                              date__range=(start, end)).count(),
    }


# ─────────────────────────────── Compare plans


def _pct(a, b):
    return round(100 * a / b) if b else None


def _period(client, pa):
    today = timezone.localdate()
    start = pa.start_date
    end = min(pa.end_date or today, today)
    if end < start:
        end = start
    return start, end


def _assignments(client, start, end):
    """Workout plans that ran some time in [start, end], oldest first."""
    from apps.training.models import ProgramAssignment

    return list(ProgramAssignment.objects.filter(client=client, start_date__lte=end)
                .filter(Q(end_date__isnull=True) | Q(end_date__gte=start))
                .select_related("program", "custom_program").order_by("start_date"))


def _weeks(start, end):
    return max(1, ((end - start).days + 1) / 7)


def _workouts(client, start, end, pa=None):
    """[pa] = the plan picked for this side; for a date range every plan that ran in it counts."""
    from apps.clients.metrics import planned_workout_days
    from apps.training.models import SetLog, WorkoutLog
    from apps.training.services import body_weights, workout_volume

    weeks = _weeks(start, end)
    pas = [pa] if pa else _assignments(client, start, end)
    planned = sorted({d for x in pas for d in planned_workout_days(x, start, min(end, x.end_date or end))})
    planned_past = [d for d in planned if d < timezone.localdate()] or planned
    logs = list(WorkoutLog.objects.filter(client=client, status="completed", date__range=(start, end)))
    done_days = {w.date for w in logs}
    missed = [d for d in planned_past if d not in done_days]
    sets_done = sum(w.sets_done for w in logs)
    sets_planned = sum(w.sets_planned for w in logs)
    vols = []
    body = body_weights(client.id)
    for w in logs:
        v = workout_volume(w, body(w.date))
        if v:
            vols.append(v)
    mins = [w.duration_seconds / 60 for w in logs if w.duration_seconds]
    by_day = Counter(d.strftime("%A") for d in missed)
    program = pas[-1].effective_program if pas else None
    wk1 = program.program_weeks.order_by("number").first() if program else None
    per_week = wk1.days.filter(is_rest=False).count() if wk1 else None
    best = {}
    for s in (SetLog.objects.filter(workout__client=client, workout__status="completed", workout__date__range=(start, end),
                                    done=True, is_warmup=False, weight_kg__isnull=False)
              .select_related("exercise")):
        cur = best.get(s.exercise_id)
        if cur is None or (s.weight_kg, s.reps or 0) > (cur.weight_kg, cur.reps or 0):
            best[s.exercise_id] = s
    return {
        "planned_week": per_week,
        "done_week": round(len(done_days) / weeks, 1),
        "completed": _pct(min(len(done_days), len(planned_past)), len(planned_past)),
        "sets": _pct(sets_done, sets_planned),
        "volume": round(sum(vols) / len(vols)) if vols else None,
        "minutes": round(sum(mins) / len(mins)) if mins else None,
        "missed": len(missed),
        "missed_day": by_day.most_common(1)[0][0] if by_day else None,
        "best": [{"key": str(e), "name": s.exercise.name, "kg": float(s.weight_kg), "reps": s.reps}
                 for e, s in best.items()],
    }


def _meals(client, start, end):
    from apps.nutrition.models import FoodLogEntry, MealDayState, MealPlanAssignment
    from apps.nutrition.services import totals

    mps = list(MealPlanAssignment.objects.filter(client=client, start_date__lte=end)
               .filter(Q(end_date__isnull=True) | Q(end_date__gte=start)).select_related("plan").order_by("start_date"))
    from apps.clients.metrics import meals_by_weekday
    from apps.nutrition.models import meals_on

    mp = mps[-1] if mps else None
    plan = mp.followed if mp else None  # the client's own copy, else the master
    today = timezone.localdate()
    days = [d for d in days_desc(start, min(end, today - timedelta(days=1)), client)]
    per_weekday = meals_by_weekday(mp) if mp else {w: 0 for w in range(7)}
    n_meals = max(per_weekday.values())
    logged = dict(MealDayState.objects.filter(client=client, status="logged", date__range=(start, end))
                  .values("date").annotate(n=Count("id")).values_list("date", "n"))
    food_days = set(FoodLogEntry.objects.filter(client=client, date__range=(start, end)).values_list("date", flat=True))
    by_day = {d: totals(client, d) for d in days if d in food_days}
    tot = list(by_day.values())
    target = plan.kcal_target if plan else None
    on_plan = over = 0
    for d in days:
        t = by_day.get(d)
        if t and target and t["kcal"] > target * 1.05:
            over += 1
        elif per_weekday[d.weekday()] and logged.get(d, 0) >= per_weekday[d.weekday()]:
            on_plan += 1
    per_meal = []
    if plan:
        # Days each meal is planned on: a weekday's own meals only that weekday, every-day meals on the others.
        planned_on = {}
        for d in days:
            for mid in meals_on(plan, d.weekday()).values_list("id", flat=True):
                planned_on.setdefault(mid, []).append(d)
        for m in plan.meals.all():
            mdays = planned_on.get(m.id, [])
            if not mdays:
                continue
            n = MealDayState.objects.filter(client=client, status="logged", meal=m, date__in=mdays).count()
            per_meal.append({"name": m.name, "pct": _pct(min(n, len(mdays)), len(mdays))})

    def avg(k):
        return round(sum(t[k] for t in tot) / len(tot)) if tot else None

    return {
        "target": target, "kcal": avg("kcal"), "protein": avg("protein"), "carbs": avg("carbs"), "fat": avg("fat"),
        "on_plan": _pct(on_plan, len(days)), "over": _pct(over, len(days)),
        "per_day": round(sum(logged.get(d, 0) for d in days) / len(days), 1) if days else None,
        "meals": n_meals or None, "per_meal": per_meal,
    }


def _checkins(client, start, end):
    from apps.checkins.models import Submission

    days = days_desc(start, min(end, timezone.localdate() - timedelta(days=1)), client)
    daily = list(Submission.objects.filter(client=client, form_type="daily", date__range=(start, end)).only("metrics"))
    sundays = [d for d in days if d.weekday() == 6]
    weekly = Submission.objects.filter(client=client, form_type="weekly", date__range=(start, end))

    def share(key, good):
        vals = [s.metrics.get(key) for s in daily if isinstance(s.metrics.get(key), (int, float))]
        return _pct(sum(1 for v in vals if good(v)), len(vals)) if vals else None

    sleep = [s.metrics["sleep_hours"] for s in daily if isinstance(s.metrics.get("sleep_hours"), (int, float))]
    on_time = weekly.filter(date__in=sundays).count()
    return {
        "daily": _pct(min(len(daily), len(days)), len(days)),
        "weekly_on_time": on_time, "weekly_due": len(sundays),
        "sleep": round(sum(sleep) / len(sleep), 1) if sleep else None,
        "energy": share("energy", lambda v: v >= 4), "mood": share("mood", lambda v: v >= 4),
        "hunger": share("hunger", lambda v: v >= 4),
    }


def _habits(client, start, end):
    from apps.habits.models import HabitAssignment, HabitLog
    from apps.nutrition.models import WaterLog

    days = days_desc(start, min(end, timezone.localdate() - timedelta(days=1)), client)
    out, all_done = [], Counter()
    for a in HabitAssignment.objects.filter(client=client, start_date__lte=end).select_related("habit"):
        h = a.habit
        due = [d for d in days if d >= a.start_date and h.is_due_on(d)]
        done = set(HabitLog.objects.filter(client=client, habit=h, done=True, date__in=due).values_list("date", flat=True))
        for d in done:
            all_done[d] += 1
        out.append({"key": f"h{h.id}", "name": h.name, "pct": _pct(len(done), len(due))})
    n = len(out)
    steps = HabitLog.objects.filter(client=client, date__range=(start, end), habit__name__icontains="steps",
                                    value__gt=0).aggregate(x=Avg("value"))["x"]
    water = WaterLog.objects.filter(client=client, date__range=(start, end), ml__gt=0).aggregate(x=Avg("ml"))["x"]
    return {"items": out, "all": _pct(sum(1 for d in days if n and all_done[d] >= n), len(days)) if n else None,
            "steps": round(steps) if steps else None, "water": round(water / 1000, 1) if water else None}


def _supps(client, start, end):
    from apps.habits.models import SupplementAssignment, SupplementLog

    days = days_desc(start, min(end, timezone.localdate() - timedelta(days=1)), client)
    out, took = [], Counter()
    n = 0
    for sa in SupplementAssignment.objects.filter(client=client, start_date__lte=end).select_related("plan",
                                                                                                     "custom_plan"):
        for it in sa.followed.items.all():
            due = [d for d in days if d >= sa.start_date and (not it.days or d.weekday() in it.days)]
            done = set(SupplementLog.objects.filter(client=client, item=it, date__in=due).values_list("date", flat=True))
            for d in done:
                took[d] += 1
            n += 1
            out.append({"key": it.name.strip().lower(), "name": it.name, "pct": _pct(len(done), len(due))})
    from apps.activity.models import ActivityEvent

    ran_out = ActivityEvent.objects.filter(client=client, meta__history="stock_out", created_at__date__range=(start, end))
    return {"items": out, "all": _pct(sum(1 for d in days if n and took[d] >= n), len(days)) if n else None,
            "ran_out": ran_out.count()}


def _body(client, start, end):
    from apps.checkins.models import Measurement, WeightLog

    w = list(WeightLog.objects.filter(client=client, date__range=(start, end)).order_by("date"))
    m = list(Measurement.objects.filter(client=client, date__range=(start, end)).order_by("date"))
    ch = round(float(w[-1].weight_kg) - float(w[0].weight_kg), 1) if len(w) > 1 else None

    def mch(key):
        vals = [x.values[key] for x in m if key in x.values]
        return round(vals[-1] - vals[0], 1) if len(vals) > 1 else None

    return {"weight": ch, "per_week": round(ch / _weeks(start, end), 2) if ch is not None else None,
            "waist": mch("waist"), "body_fat": mch("body_fat")}


def period(client, start, end, *, pa=None, name=None):
    """One side of Compare plans: what the client did in [start, end] (a plan's run, part of it, or any dates)."""
    from apps.nutrition.models import MealPlanAssignment

    today = timezone.localdate()
    end = min(end, today)
    if end < start:
        end = start
    mp = (MealPlanAssignment.objects.filter(client=client, start_date__lte=end).select_related("plan")
          .order_by("-start_date").first())
    weeks = max(1, round(((end - start).days + 1) / 7))
    bits = ["Workout"] if pa or _assignments(client, start, end) else []
    if mp and mp.plan.kcal_target:
        bits.append(f"{mp.plan.kcal_target:,} kcal")
    to = "now" if end >= today and (pa is None or pa.end_date is None or pa.end_date >= today) else dfmt(end, "%-d %b")
    when = f"{dfmt(start, '%-d %b')} – {to}"
    return {
        "id": str(pa.id) if pa else None,
        "name": name or (pa.effective_program.name if pa else f"{dfmt(start, '%-d %b')} – {dfmt(end, '%-d %b')}"),
        "from": start, "to": end,
        "sub": " · ".join(x for x in [" + ".join(bits), when, f"{weeks} week{'s' if weeks != 1 else ''}"] if x),
        "workouts": _workouts(client, start, end, pa), "meals": _meals(client, start, end),
        "checkins": _checkins(client, start, end), "habits": _habits(client, start, end),
        "supps": _supps(client, start, end), "body": _body(client, start, end),
    }


def plan_period(client, pa):
    """What the client did while on this workout plan (and the meal plan then)."""
    start, end = _period(client, pa)
    return period(client, start, end, pa=pa)


def compare(client, a, b):
    """[a] / [b]: a ProgramAssignment, or (start, end) dates."""
    def side(x):
        return plan_period(client, x) if not isinstance(x, tuple) else period(client, *x)

    return {"a": side(a), "b": side(b)}


# ─────────────────────────────── Comments


def comment(client, *, actor, about, day, text):
    """'Comment on this workout…' / 'Comment on her meals for this day…': the client gets it in the app."""
    from apps.activity.services import log as activity_log
    from apps.notifications.services import notify

    coach = actor.first_name or actor.full_name
    what = {"workout": "your workout", "meals": "your meals"}.get(about, "your log")
    when = dfmt(day, "%a, %-d %b") if day else ""
    route = {"workout": "/progress/history", "meals": f"/food?date={day}" if day else "/food"}.get(about, "/progress/history")
    notify(client, "coach_comment", f"{coach} commented on {what}" + (f" · {when}" if when else ""), text,
           data={"route": route, "about": about, "date": str(day) if day else ""}, actor=actor)
    activity_log(f"commented on {what}", "note", actor=actor, target=client, target_label=when, client=client)
