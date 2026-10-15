"""Client app → Check-ins page (boards ClientCheckin / ClientCheckinWeb).

The weekly check-in is due every Sunday at 6:00 pm (a calendar week, Monday to Sunday). A week with no
weekly check-in is shown as Missed; a day with no daily check-in is shown as Missed (after the 9 pm
reminder). History is paged with `before` (a date), newest first.
"""
from datetime import datetime, time, timedelta

from django.utils import timezone

from .defaults import CHIPS
from .models import Form, QuestionType, Submission, WeightLog

WEEKLY_DUE = time(18, 0)  # Sunday 6:00 pm
DAILY_REMINDER = "9:00 pm"
PAGE = 20


def _monday(d):
    return d - timedelta(days=d.weekday())


def _due_at(sunday):
    return timezone.make_aware(datetime.combine(sunday, WEEKLY_DUE))


def _start(client):
    cp = client.client_profile
    return cp.start_date or client.date_joined.date()


def _chip(q):
    if q.text in CHIPS:
        return CHIPS[q.text]
    if q.metric == "weight":
        return "Weight"
    if q.type == QuestionType.PHOTO:
        return "Photos"
    t = q.text.rstrip("?").strip()
    return t if len(t) <= 18 else t[:17].rstrip() + "…"


def form_payload(form, coach_first):
    if form is None:
        return None
    qs = [q for q in form.questions.all() if not q.is_removed]
    return {"id": str(form.id), "name": form.name, "type": form.type, "questions": [{
        "id": q.id, "text": q.text, "type": q.type, "options": q.options, "scale_labels": q.scale_labels,
        "allow_other": q.allow_other, "help_text": q.help_text.replace("{coach}", coach_first or "your coach"),
        "required": q.required, "metric": q.metric, "chip": _chip(q)} for q in qs]}


def _week_counts(client, monday):
    """Workouts done / planned and the share of planned meals logged, Monday to Sunday."""
    from apps.clients.metrics import active_meal_plan, active_program, planned_workout_days
    from apps.nutrition.models import MealDayState
    from apps.training.models import WorkoutLog

    sunday = monday + timedelta(days=6)
    end = min(sunday, timezone.localdate())
    planned = len(planned_workout_days(active_program(client, end), monday, sunday))
    done = (WorkoutLog.objects.filter(client=client, status=WorkoutLog.Status.COMPLETED, date__range=(monday, end))
            .values("date").distinct().count())
    mp = active_meal_plan(client, end)
    meals = None
    if mp:
        days = max(0, (end - max(monday, mp.start_date)).days + 1)
        want = mp.plan.meals.count() * days
        if want:
            got = MealDayState.objects.filter(client=client, date__range=(monday, end),
                                              status=MealDayState.Status.LOGGED).count()
            meals = round(100 * min(got, want) / want)
    return {"workouts_done": done, "workouts_planned": planned, "meals_pct": meals}


def _habit_day(client, day):
    """Steps and water for one day (the daily check-in takes them from Habits)."""
    from apps.habits.models import HabitLog
    from apps.nutrition.models import WaterLog

    steps = (HabitLog.objects.filter(client=client, date=day, habit__icon="steps").values_list("value", flat=True)
             .first())
    water = WaterLog.objects.filter(client=client, date=day).values_list("ml", flat=True).first()
    return {"steps": steps, "water_ml": water}


def _row(sub):
    m = sub.metrics or {}
    return {"id": str(sub.id), "kind": "sent", "date": sub.date, "sent_at": sub.created_at,
            "week_number": sub.week_number, "metrics": m, "reviewed": sub.reviewed_at is not None,
            "reviewed_at": sub.reviewed_at, "reply": sub.reply, "edited_at": sub.edited_at,
            "photo_count": getattr(sub, "n_photos", 0)}


def _photo_counts(subs):
    from django.db.models import Count, Q

    ids = [s.id for s in subs]
    counts = dict(Submission.objects.filter(id__in=ids).annotate(
        n=Count("answers", filter=Q(answers__photo__gt=""))).values_list("id", "n"))
    for s in subs:
        s.n_photos = counts.get(s.id, 0)


def weekly_rows(client, before=None):
    from .services import week_number

    today = timezone.localdate()
    this_monday = _monday(today)
    start = _start(client)
    subs = list(Submission.objects.filter(client=client, form_type="weekly").order_by("-date", "-created_at"))
    _photo_counts(subs)
    by_week = {}
    for s in subs:
        by_week.setdefault(_monday(s.date), []).append(s)
    rows = []
    for s in subs:
        r = _row(s)
        r["week_number"] = s.week_number or week_number(client, s.date)
        r["on_time"] = s.created_at <= _due_at(_monday(s.date) + timedelta(days=6))
        rows.append(r)
    # Missed: every finished week since the start with nothing sent.
    m = _monday(start)
    while m < this_monday:
        sunday = m + timedelta(days=6)
        if sunday >= start and m not in by_week:
            rows.append({"id": None, "kind": "missed", "date": sunday, "week_number": week_number(client, sunday),
                         "due_at": _due_at(sunday)})
        m += timedelta(days=7)
    rows.sort(key=lambda r: (r["date"], r.get("sent_at") or _due_at(r["date"])), reverse=True)
    # Weight change against the check-in before (the label says "In 2 weeks" across a gap).
    sent = [r for r in rows if r["kind"] == "sent"]
    for i, r in enumerate(sent):
        w = r["metrics"].get("weight")
        prev = next((p for p in sent[i + 1:] if p["metrics"].get("weight") is not None), None)
        if w is not None and prev is not None:
            r["change_kg"] = round(float(w) - float(prev["metrics"]["weight"]), 1)
            r["change_weeks"] = max(1, round((r["date"] - prev["date"]).days / 7))
    return rows


def daily_rows(client, form):
    today = timezone.localdate()
    start = max(_start(client), today - timedelta(days=365))
    subs = list(Submission.objects.filter(client=client, form_type="daily", date__gte=start).order_by("-date"))
    rows = [_row(s) for s in subs]
    if form is not None:
        have = {s.date for s in subs}
        d = today - timedelta(days=1)
        while d >= start:
            if d not in have:
                rows.append({"id": None, "kind": "missed", "date": d, "reminder": DAILY_REMINDER})
            d -= timedelta(days=1)
    rows.sort(key=lambda r: r["date"], reverse=True)
    return rows


def page(rows, before=None, size=PAGE):
    if before:
        rows = [r for r in rows if r["date"] < before]
    return rows[:size], len(rows) > size


def checkins_page(client, tab="weekly", before=None):
    from apps.clients.metrics import active_program

    from .services import streak, week_number

    today = timezone.localdate()
    cp = client.client_profile
    coach = cp.trainer
    coach_first = coach.first_name if coach else ""
    weekly = Form.objects.filter(type="weekly", status="published").prefetch_related("questions").first()
    daily = Form.objects.filter(type="daily", status="published").prefetch_related("questions").first()

    w_rows = weekly_rows(client)
    sent_w = [r for r in w_rows if r["kind"] == "sent"]
    due_weeks = [r for r in w_rows if r["kind"] == "missed" or _monday(r["date"]) < _monday(today)]
    this_week = next((r for r in sent_w if _monday(r["date"]) == _monday(today)), None)
    due_total = len(due_weeks) + (1 if this_week else 0)
    on_time = len([r for r in sent_w if r.get("on_time")])
    last_change = next((r.get("change_kg") for r in sent_w if r.get("change_kg") is not None), None)

    if tab == "daily":
        rows, more = page(daily_rows(client, daily), before)
        for r in rows:
            r.update(_habit_day(client, r["date"]))
    else:
        rows, more = page(w_rows, before)
        for r in rows:
            r.update(_week_counts(client, _monday(r["date"])))

    d_today = Submission.objects.filter(client=client, form_type="daily", date=today).first()
    last_w = WeightLog.objects.filter(client=client, date__lt=today).order_by("-date").first()
    today_w = WeightLog.objects.filter(client=client, date=today).first()
    prev_weekly_w = next((r["metrics"]["weight"] for r in sent_w
                          if r["metrics"].get("weight") is not None and r is not this_week), None)
    pa = active_program(client, today)
    sunday = _monday(today) + timedelta(days=6)
    return {
        "coach": {"name": coach.full_name, "first_name": coach_first, "initials": coach.initials,
                  "avatar_color": coach.avatar_color} if coach else None,
        "program": {"name": pa.effective_program.name, "week": week_number(client, today),
                    "weeks": pa.effective_program.weeks} if pa else None,
        "stats": {"streak": streak(client, "daily"), "weekly_on_time": on_time, "weekly_due": due_total,
                  "last_change_kg": last_change},
        "daily": {"date": today, "form": form_payload(daily, coach_first),
                  "sent": _row(d_today) if d_today else None, **_habit_day(client, today),
                  "last_weight": {"date": last_w.date, "kg": float(last_w.weight_kg)} if last_w else None,
                  "today_weight": float(today_w.weight_kg) if today_w else None},
        "weekly": {"week": week_number(client, today), "due_at": _due_at(sunday),
                   "form": form_payload(weekly, coach_first), "sent": this_week,
                   "last_weight": float(prev_weekly_w) if prev_weekly_w is not None else None},
        "tab": tab, "history": rows, "has_more": more,
        "next_before": rows[-1]["date"] if rows and more else None,
    }
