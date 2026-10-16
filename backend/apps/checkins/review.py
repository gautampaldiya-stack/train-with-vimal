"""The coach's view of one check-in (review drawer on the trainer dashboard and Check-ins page):
4 numbers on top, the week's answers with last week beside them, what the client wrote, photos."""
from datetime import timedelta

from django.db.models import Avg


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


def review_view(sub):
    from apps.clients.metrics import active_meal_plan, active_program, planned_workout_days
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
        per_day = mp.plan.meals.count()
        days = max(0, (b - max(a, mp.start_date)).days + 1)
        meals_planned = per_day * days
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
        rows.append((short, str(val), ""))
    one = lambda v: f"{v:.0f}" if v is not None and abs(v - round(v)) < .05 else (f"{v:.1f}" if v is not None else "")
    for key, label, fmt in (("energy", "Energy", lambda v: f"{one(v)} / 5"),
                            ("sleep_hours", "Sleep", lambda v: f"{one(v)} h a night"),
                            ("hunger", "Hunger", lambda v: f"{one(v)} / 5"),
                            ("mood", "Mood", lambda v: f"{one(v)} / 5")):
        now_v, last_v = _daily_avg(c, a, b, key), _daily_avg(c, pa, pb, key)
        if now_v is not None:
            short = (lambda v: one(v)) if key != "sleep_hours" else (lambda v: f"{one(v)} h")
            rows.append((label, fmt(now_v), _cmp(now_v, last_v, short)))
    wv, wl = _water(c, a, b), _water(c, pa, pb)
    if wv is not None:
        rows.append(("Water", f"{wv:g} L a day" if wv == round(wv, 1) else f"{wv:.1f} L a day",
                     _cmp(wv, wl, lambda v: f"{v:.1f} L".replace(".0 L", " L"))))
    sv, sl = _steps(c, a, b), _steps(c, pa, pb)
    if sv is not None:
        rows.append(("Steps", f"{round(sv):,} a day", _cmp(sv, sl, lambda v: f"{round(v):,}")))

    note = ""
    for ans in sub.answers.select_related("question"):
        if ans.question.type == "long" and isinstance(ans.value, str) and ans.value.strip():
            note = ans.value.strip()
    note = note or (m.get("note") or "")
    return {"kpis": [{"label": k, "value": v} for k, v in kpis],
            "rows": [{"label": k, "value": v, "last": l} for k, v, l in rows],
            "note": note, "line": line(sub, w, rows, note)}


def line(sub, weight, rows, note):
    """'Weight 61.8 kg · energy 3/5 · knees sore'."""
    bits = [f"Weight {weight:g} kg"] if weight is not None else []
    for k, v, _ in rows:
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
