"""The coach's view of one check-in (review drawer on the trainer dashboard and Check-ins page):
4 numbers on top, the week's answers with last week beside them, what the client wrote, photos."""
from datetime import timedelta

from django.db.models import Avg
from django.utils import timezone


def _n(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _kg(v):
    return f"{v:g} kg" if v is not None else "—"


def _week_of(sub):
    end = sub.date
    return end - timedelta(days=6), end


def _daily_avg(client, a, b, key):
    from .models import Submission

    vals = [_n(s.metrics.get(key)) for s in Submission.objects.filter(client=client, form_type="daily",
                                                                    date__range=(a, b)).only("metrics")]
    vals = [v for v in vals if v is not None]
    return sum(vals) / len(vals) if vals else None


def _water(client, a, b):
    from apps.nutrition.models import WaterLog

    v = WaterLog.objects.filter(client=client, date__range=(a, b), ml__gt=0).aggregate(x=Avg("ml"))["x"]
    return v / 1000 if v else None


def _steps(client, a, b):
    from apps.habits.models import HabitLog

    v = (HabitLog.objects.filter(client=client, date__range=(a, b), habit__name__icontains="steps", value__gt=0)
         .aggregate(x=Avg("value"))["x"])
    return v


def _cmp(now, last, fmt):
    """'last 4' / 'same' / '' — the grey note after a value."""
    if now is None or last is None:
        return ""
    if fmt(now) == fmt(last):
        return "same"
    return f"last {fmt(last)}"


def _trend(now, last, higher_better=True):
    """'up' when this week is better than last (green on the Check-ins page), 'down' when worse (red), else ''."""
    if now is None or last is None or abs(now - last) < 0.05:
        return ""
    return "up" if (now > last) == higher_better else "down"


# Daily answers where a lower number is better (shown green when it went down).
LOWER_BETTER = {"hunger", "soreness", "stress"}


def _daily_view(sub):
    """A daily check-in: that day's sleep, energy, workout and steps on top; the other answers with the previous
    daily check-in's answer beside them; water and planned meals for that day."""
    from apps.clients.metrics import active_meal_plan, active_program, meals_per_day, program_day_for
    from apps.habits.models import HabitLog
    from apps.nutrition.models import MealDayState, WaterLog
    from apps.training.models import WorkoutLog

    from .models import Submission

    c, d = sub.client, sub.date
    m = sub.metrics or {}
    prev = (Submission.objects.filter(client=c, form_type="daily", created_at__lt=sub.created_at)
            .prefetch_related("answers__question").order_by("-created_at").first())
    pm = (prev.metrics or {}) if prev else {}
    one = lambda v: f"{v:.0f}" if abs(v - round(v)) < .05 else f"{v:.1f}"

    pa = active_program(c, d)
    pd = program_day_for(pa, d) if pa else None
    if WorkoutLog.objects.filter(client=c, date=d, status="completed").exists():
        workout = "Done"
    elif pd is None or getattr(pd, "is_rest", False):
        workout = "Rest day"
    else:
        workout = "Not done" if d < timezone.localdate() else "Planned"
    steps = HabitLog.objects.filter(client=c, date=d, habit__name__icontains="steps").values_list("value", flat=True).first()
    psteps = HabitLog.objects.filter(client=c, date=d - timedelta(days=1), habit__name__icontains="steps").values_list("value", flat=True).first()
    sl, en = _n(m.get("sleep_hours")), _n(m.get("energy"))
    kpis = [
        ("Sleep", f"{one(sl)} h" if sl is not None else "—", _trend(sl, _n(pm.get("sleep_hours")))),
        ("Energy", f"{one(en)} / 5" if en is not None else "—", _trend(en, _n(pm.get("energy")))),
        ("Workout", workout, "down" if workout == "Not done" else ""),
        ("Steps", f"{steps:,}" if steps else "—", _trend(_n(steps), _n(psteps)) if steps else ""),
    ]

    last = {}
    if prev:
        for a in prev.answers.all():
            last[a.question.metric or a.question.text] = a.value
    rows = []
    for ans in sub.answers.select_related("question").order_by("question__order"):
        q = ans.question
        key = q.metric or q.text
        if ans.photo or q.type in ("photo", "long") or ans.value in (None, "", []) or key in ("sleep_hours", "energy", "weight"):
            continue

        def show(v):
            if q.type == "scale" and isinstance(v, (int, float)):
                return f"{one(float(v))} / 5"
            return str(v)

        lv = last.get(key)
        trend = ""
        if q.type == "scale" and isinstance(ans.value, (int, float)) and isinstance(lv, (int, float)):
            trend = _trend(float(ans.value), float(lv), key not in LOWER_BETTER)
        rows.append((q.text, show(ans.value), f"last {show(lv)}" if lv not in (None, "", []) else "", trend))
    if m.get("weight") is not None:
        w, pw = _n(m.get("weight")), _n(pm.get("weight"))
        rows.insert(0, ("Morning weight", _kg(w), f"last {_kg(pw)}" if pw is not None else "", ""))
    water = WaterLog.objects.filter(client=c, date=d).values_list("ml", flat=True).first()
    pwater = WaterLog.objects.filter(client=c, date=d - timedelta(days=1)).values_list("ml", flat=True).first()
    if water:
        rows.append(("Water", f"{water / 1000:g} L", f"last {pwater / 1000:g} L" if pwater else "", _trend(water, pwater)))
    mp = active_meal_plan(c, d)
    if mp:
        per_day = meals_per_day(mp, d)  # the client's own copy, that weekday's meals
        prev_day = meals_per_day(mp, d - timedelta(days=1))
        n = MealDayState.objects.filter(client=c, date=d, status="logged").count()
        pn = MealDayState.objects.filter(client=c, date=d - timedelta(days=1), status="logged").count()
        rows.append(("Meals on plan", f"{min(n, per_day)} of {per_day}", f"last {min(pn, prev_day)} of {prev_day}", _trend(n, pn)))

    note = ""
    for ans in sub.answers.select_related("question"):
        if ans.question.type == "long" and isinstance(ans.value, str) and ans.value.strip():
            note = ans.value.strip()
    note = note or (m.get("note") or "")
    return {"kpis": [{"label": k, "value": v, "trend": t} for k, v, t in kpis],
            "rows": [{"label": k, "value": v, "last": l, "trend": t} for k, v, l, t in rows],
            "note": note, "line": line(sub, _n(m.get("weight")), [(k, v) for k, v, *_ in rows], note)}


def review_view(sub):
    if sub.form_type == "daily":
        return _daily_view(sub)
    from apps.clients.metrics import active_meal_plan, active_program, planned_meals, planned_workout_days
    from apps.nutrition.models import MealDayState
    from apps.training.models import WorkoutLog

    from .models import Submission

    c = sub.client
    a, b = _week_of(sub)
    pa, pb = a - timedelta(days=7), a - timedelta(days=1)
    m = sub.metrics or {}
    prev = (Submission.objects.filter(client=c, form_type=sub.form_type, created_at__lt=sub.created_at)
            .order_by("-created_at").first())
    w, pw = _n(m.get("weight")), _n((prev.metrics or {}).get("weight")) if prev else None

    planned = planned_workout_days(active_program(c, b), a, b)
    done = WorkoutLog.objects.filter(client=c, status="completed", date__range=(a, b)).values("date").distinct().count()
    mp = active_meal_plan(c, b)
    meals = 0
    if mp:
        meals_planned = planned_meals(mp, a, b)
        logged = MealDayState.objects.filter(client=c, date__range=(a, b), status="logged").count()
        meals = round(100 * min(logged, meals_planned) / meals_planned) if meals_planned else None
    kpis = [("Weight", _kg(w)),
            ("Change", "—" if w is None or pw is None else f"{'−' if w - pw < 0 else '+'}{abs(w - pw):.1f} kg"),
            ("Workouts", f"{min(done, len(planned))} of {len(planned)}" if planned else "—"),
            ("Meals on plan", f"{meals}%" if mp and meals is not None else "—")]

    rows = []
    # The weekly form's own answers first (week rating, meal plan), then the week of daily check-ins and habits.
    for ans in sub.answers.select_related("question").order_by("question__order"):
        q = ans.question
        if ans.photo or q.metric or q.type in ("photo", "long") or ans.value in (None, "", []):
            continue
        val = ans.value
        if q.type == "scale" and isinstance(val, (int, float)) and q.scale_labels:
            labels = q.scale_labels
            val = labels[int(val) - 1] if 1 <= int(val) <= len(labels) else val
        short = {"How was your week?": "Week", "Did you follow the meal plan?": "Meal plan"}.get(q.text, q.text)
        rows.append((short, str(val), "", ""))
    one = lambda v: f"{v:.0f}" if v is not None and abs(v - round(v)) < .05 else (f"{v:.1f}" if v is not None else "")
    for key, label, fmt, up in (("energy", "Energy", lambda v: f"{one(v)} / 5", True),
                                ("sleep_hours", "Sleep", lambda v: f"{one(v)} h a night", True),
                                ("hunger", "Hunger", lambda v: f"{one(v)} / 5", False),
                                ("mood", "Mood", lambda v: f"{one(v)} / 5", True)):
        now_v, last_v = _daily_avg(c, a, b, key), _daily_avg(c, pa, pb, key)
        if now_v is not None:
            short = (lambda v: one(v)) if key != "sleep_hours" else (lambda v: f"{one(v)} h")
            rows.append((label, fmt(now_v), _cmp(now_v, last_v, short), _trend(now_v, last_v, up)))
    wv, wl = _water(c, a, b), _water(c, pa, pb)
    if wv is not None:
        rows.append(("Water", f"{wv:g} L a day" if wv == round(wv, 1) else f"{wv:.1f} L a day",
                     _cmp(wv, wl, lambda v: f"{v:.1f} L".replace(".0 L", " L")), _trend(wv, wl)))
    sv, sl = _steps(c, a, b), _steps(c, pa, pb)
    if sv is not None:
        rows.append(("Steps", f"{round(sv):,} a day", _cmp(sv, sl, lambda v: f"{round(v):,}"), _trend(sv, sl)))

    note = ""
    for ans in sub.answers.select_related("question"):
        if ans.question.type == "long" and isinstance(ans.value, str) and ans.value.strip():
            note = ans.value.strip()
    note = note or (m.get("note") or "")
    # Weight change is good when it moves toward the goal weight.
    target = _n(c.client_profile.target_weight_kg)
    change_trend = "" if w is None or pw is None or target is None or abs(w - pw) < .05 else \
        ("up" if abs(w - target) < abs(pw - target) else "down")
    trends = {"Change": change_trend}
    return {"kpis": [{"label": k, "value": v, "trend": trends.get(k, "")} for k, v in kpis],
            "rows": [{"label": k, "value": v, "last": l, "trend": t} for k, v, l, t in rows],
            "note": note, "line": line(sub, w, rows, note)}


def line(sub, weight, rows, note):
    """'Weight 61.8 kg · energy 3/5 · knees sore'."""
    bits = [f"Weight {weight:g} kg"] if weight is not None else []
    for k, v, *_ in rows:
        if k == "Energy":
            bits.append("energy " + v.replace(" / ", "/"))
        elif k == "Sleep" and len(bits) < 2:
            bits.append("sleep " + v.replace(" a night", ""))
    if note:
        first = note.split(".")[0].split(",")[0].strip()
        if len(first) <= 28:
            bits.append(first[0].lower() + first[1:] if first[:1].isupper() and not first[1:2].isupper() else first)
    n = sub.answers.exclude(photo="").exclude(photo__isnull=True).count()
    if n:
        bits.append(f"{n} photos")
    return " · ".join(bits[:3]) or sub.form.name
