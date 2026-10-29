"""Client app → Progress tab (boards ClientProgress / ClientProgressWeb).

`progress_page` is the whole tab in one answer (goal, weigh-ins, measurements, lifts, adherence, photos);
the app filters the weight chart by range itself, so switching 4 wk / 12 wk / 6 mo / All needs no request.
`history` is the History page: every day's logs (workouts, meals, check-ins, weigh-ins), newest first, paged
by days.
"""
from collections import defaultdict
from datetime import timedelta

from django.utils import timezone

from .models import DEFAULT_MEASURES, MEASURE_KEYS, MEASURES, Measurement, PhotoSet, Submission, WeightLog
from apps.common.utils import dfmt

HISTORY_RANGES = {"week": 7, "month": 30, "3months": 91}
HISTORY_TYPES = ("workout", "meal", "checkin", "weight")


def _f(v):
    return float(v) if v is not None else None


def _monday(d):
    return d - timedelta(days=d.weekday())


def _goal_eta(weights, goal, today):
    """When the goal is reached at the pace of the last 8 weeks (None if not heading there)."""
    if goal is None or len(weights) < 2:
        return None
    last = weights[-1]
    back = [w for w in weights if w.date <= last.date - timedelta(weeks=8)]
    first = back[-1] if back else weights[0]
    weeks = (last.date - first.date).days / 7
    if weeks < 1:
        return None
    rate = (float(first.weight_kg) - float(last.weight_kg)) / weeks  # kg per week, + = losing
    gap = float(last.weight_kg) - float(goal)
    if gap == 0 or rate == 0 or (gap > 0) != (rate > 0):
        return None
    return today + timedelta(weeks=min(gap / rate, 520))


def _lifts(client, limit=4):
    from django.db.models import Count

    from apps.clients.metrics import active_program
    from apps.training.models import ProgramExercise, SetLog

    base = SetLog.objects.filter(workout__client=client, workout__status="completed", done=True, is_warmup=False,
                                 weight_kg__isnull=False)
    top = base.values("exercise_id", "exercise__name").annotate(n=Count("id")).order_by("-n")[:limit]
    pa = active_program(client)
    out = []
    for row in top:
        sets = list(base.filter(exercise_id=row["exercise_id"]).order_by("workout__date", "-weight_kg", "-reps")
                    .values("workout__date", "weight_kg", "reps"))
        by_day = {}
        for s in sets:
            by_day.setdefault(s["workout__date"], s)  # heaviest set of the day
        series = [{"date": d, "kg": float(s["weight_kg"])} for d, s in by_day.items()]
        best = max(sets, key=lambda s: (s["weight_kg"], s["reps"] or 0))
        ups = sum(1 for a, b in zip(series, series[1:]) if b["kg"] > a["kg"])
        note = ""
        if pa:
            pe = (ProgramExercise.objects.filter(day__week__program=pa.effective_program, exercise_id=row["exercise_id"])
                  .exclude(note="").first())
            note = pe.note if pe else ""
        out.append({"exercise": row["exercise_id"], "name": row["exercise__name"],
                    "best": {"kg": float(best["weight_kg"]), "reps": best["reps"]},
                    "started": series[0], "last": series[-1]["date"], "ups": ups, "note": note, "series": series})
    return out


def _adherence(client, today):
    from apps.clients.metrics import active_program, program_day_for

    from .client_page import _week_counts

    pa = active_program(client, today)
    weeks = []
    for i in range(5, -1, -1):
        mon = _monday(today) - timedelta(weeks=i)
        c = _week_counts(client, mon)
        parts = []
        if c["workouts_planned"]:
            parts.append(100 * min(c["workouts_done"], c["workouts_planned"]) / c["workouts_planned"])
        if c["meals_pct"] is not None:
            parts.append(c["meals_pct"])
        weeks.append({"start": mon, "done": c["workouts_done"], "planned": c["workouts_planned"],
                      "pct": round(sum(parts) / len(parts)) if parts else None})
    out = {"program": None, "since": None, "done": 0, "planned": 0, "missed": [], "today": "", "weeks": weeks}
    if not pa:
        return out
    from apps.clients.metrics import planned_workout_days
    from apps.training.models import WorkoutLog

    done_days = set(WorkoutLog.objects.filter(client=client, status="completed", date__gte=pa.start_date)
                    .values_list("date", flat=True))
    planned = planned_workout_days(pa, pa.start_date, today - timedelta(days=1))
    pd = program_day_for(pa, today)
    out.update({
        "program": pa.effective_program.name, "since": pa.start_date,
        "done": len({d for d in done_days if d <= today}),
        "planned": len(planned) + (1 if today in done_days else 0),
        "missed": [d for d in planned if d not in done_days],
        "today": pd.name if pd and not pd.is_rest and today not in done_days else "",
    })
    return out


def progress_page(client, request=None):
    from .serializers import PhotoSetSerializer

    today = timezone.localdate()
    cp = client.client_profile
    weights = list(WeightLog.objects.filter(client=client).order_by("date"))[-400:]
    first = weights[0] if weights else None
    last = weights[-1] if weights else None
    goal = cp.target_weight_kg
    measures = list(Measurement.objects.filter(client=client).order_by("date"))
    tracked = set(cp.measure_keys or DEFAULT_MEASURES)
    from .services import measure_entry, next_measure_due, next_photos_due, week_number

    sets = PhotoSet.objects.filter(client=client).prefetch_related("photos").order_by("date", "created_at")
    # Photos page "Next set due": the coach's N weeks (default 2) after the last set, on that week's Sunday,
    # the same week the weekly check-in asks for photos.
    p_sunday = next_photos_due(client, today)
    m_open = measure_entry(client, today)
    m_sunday = next_measure_due(client, today)
    return {
        "start": {"kg": _f(cp.start_weight_kg if cp.start_weight_kg is not None else getattr(first, "weight_kg", None)),
                  "date": first.date if first else (cp.start_date or client.date_joined.date())},
        "now": {"kg": _f(last.weight_kg), "date": last.date} if last else None,
        "goal": {"kg": _f(goal), "eta": _goal_eta(weights, goal, today)} if goal is not None else None,
        "weights": [{"id": w.id, "date": w.date, "kg": float(w.weight_kg), "source": w.source} for w in weights],
        "measurements": [{"date": m.date, **m.values} for m in measures],
        # The measurements this client tracks (the coach's pick, else the default set) plus any already logged.
        "measures": [{"key": k, "label": lbl, "unit": u, "tracked": k in tracked} for k, lbl, u in MEASURES
                     if k in tracked or any(k in m.values for m in measures)],
        # One measurement entry per photo period (D-25); due N weeks after the current entry's week.
        "next_measure": {"date": m_sunday, "week": week_number(client, m_sunday),
                         "every_weeks": cp.photo_every_weeks},
        # This period's entry (logging again changes it), or null when a new one is due.
        "measure_entry": {"date": m_open.date, "values": m_open.values} if m_open else None,
        "next_photos": {"date": p_sunday, "week": week_number(client, p_sunday)},
        "lifts": _lifts(client),
        "adherence": _adherence(client, today),
        "photo_sets": [s for s in PhotoSetSerializer(sets, many=True, context={"request": request}).data
                       if s["photos"]],
        "coach": cp.trainer.first_name if cp.trainer else "",
    }


# ─────────────────────────────── History


def _sets_line(sets):
    kg = max((s.weight_kg for s in sets if s.weight_kg is not None), default=None)
    reps = max((s.reps for s in sets if s.reps), default=None)
    secs = max((s.seconds for s in sets if s.seconds), default=None)
    km = max((s.distance_km for s in sets if s.distance_km), default=None)
    line = f"{len(sets)} × {reps}" if reps else (f"{round(secs / 60)} min" if secs and secs >= 120 else
                                                 f"{len(sets)} × {secs} s" if secs else f"{len(sets)} sets")
    if km:
        line += f" · {float(km):g} km"
    if kg:
        line += f" · {float(kg):g} kg"
    return line


def _kg(v):
    return f"{float(v):.1f} kg"


def _chg(v):
    v = round(float(v), 1)
    return ("+" if v > 0 else "−" if v < 0 else "±") + f"{abs(v):.1f} kg"


def history(client, *, rng="week", kind=None, offset=0, limit=7):
    from apps.clients.metrics import active_meal_plan, active_program, adherence, program_day_for
    from apps.common.calc import nutrition_totals, show_kcal
    from apps.nutrition.models import FoodLogEntry, Meal, MealDayState
    from apps.training.models import ProgramExercise, WorkoutLog

    today = timezone.localdate()
    n = HISTORY_RANGES.get(rng, 7)
    start = today - timedelta(days=n - 1)
    days = [today - timedelta(days=i) for i in range(n)]
    pa = active_program(client, today)
    mp = active_meal_plan(client, today)
    coach = client.client_profile.trainer
    coach = coach.first_name if coach else "your coach"

    workouts = defaultdict(list)
    for w in (WorkoutLog.objects.filter(client=client, status="completed", date__range=(start, today))
              .prefetch_related("sets__exercise").order_by("started_at")):
        workouts[w.date].append(w)
    meals = list(Meal.objects.filter(plan=mp.plan).order_by("time", "order")) if mp else []
    states = defaultdict(dict)
    for s in MealDayState.objects.filter(client=client, date__range=(start, today), status="logged"):
        states[s.date][s.meal_id] = s
    food = defaultdict(list)
    for e in FoodLogEntry.objects.filter(client=client, date__range=(start, today)).order_by("logged_at"):
        food[e.date].append(e)
    subs = defaultdict(list)
    for s in (Submission.objects.filter(client=client, date__range=(start, today), form_type__in=["weekly", "daily"])
              .order_by("created_at")):
        subs[s.date].append(s)
    photo_days = set(PhotoSet.objects.filter(client=client, date__range=(start, today)).values_list("date", flat=True))
    all_w = list(WeightLog.objects.filter(client=client, date__lte=today).order_by("date"))
    all_m = list(Measurement.objects.filter(client=client, date__lte=today).order_by("date"))
    m_names = {k: (lbl, u) for k, lbl, u in MEASURES}

    def amt(k, v):
        u = m_names.get(k, ("", "cm"))[1]
        return f"{v:g}%" if u == "%" else f"{v:g} {u}"

    target = (mp.plan.kcal_target if mp else None) or None
    protein_target = (mp.plan.protein_g if mp else None) or None

    def clock(t):
        return dfmt(t, "%-I:%M %p").lower()

    out_days, kcal_days, protein_days, wo_done, wo_planned = [], [], [], 0, 0
    scores = []
    for d in days:
        es = []
        pd = program_day_for(pa, d) if pa else None
        done = workouts.get(d, [])
        for w in done:
            by_ex = defaultdict(list)
            for s in w.sets.all():
                if s.done and not s.is_warmup:
                    by_ex[s.exercise].append(s)
            planned_ex = ProgramExercise.objects.filter(day_id=w.program_day_id).count() if w.program_day_id else 0
            mins = round(w.duration_seconds / 60) if w.duration_seconds else None
            bits = ["Done"] + ([f"{mins} min"] if mins else []) + \
                [f"{len(by_ex)} of {max(planned_ex, len(by_ex))} exercises"]
            es.append({"type": "workout", "title": w.name or (pd.name if pd else "Workout"), "sub": " · ".join(bits),
                       "detail": [[ex.name, _sets_line(ss)] for ex, ss in by_ex.items()] +
                                 ([["Time", f"{mins} min"]] if mins else [])})
        if pd and not pd.is_rest:
            wo_planned += 1
            if done:
                wo_done += 1
            elif d < today:
                es.append({"type": "workout", "title": pd.name or "Workout", "sub": "Missed · not logged",
                           "badge": "Missed", "badge_color": "amber", "missed": True,
                           "detail": [["Planned", f"{pd.exercises.count()} exercises"]]})
        logged = states.get(d, {})
        rows = food.get(d, [])
        if meals and (d >= mp.start_date) or rows:
            tot = nutrition_totals(rows)
            kc, pr = show_kcal(tot["kcal"]), round(tot["protein"])
            det = []
            for m in meals:
                if m.id in logged:
                    names = [e.name for e in rows if e.meal_id == m.id and e.source == "plan"]
                    det.append([f"{m.name} · {clock(m.time)}", ", ".join(names) or "Logged"])
            extra = [e for e in rows if not (e.meal_id and e.source == "plan")]
            for e in extra:
                det.append([f"{e.meal_name} · {clock(timezone.localtime(e.logged_at))}", e.name])
            title = f"Meals · {len(logged)} of {len(meals)} logged" if meals else f"Food · {len(rows)} logged"
            if logged or rows or d < today:
                es.append({"type": "meal", "title": title,
                           "sub": f"{kc:,} kcal · {pr} g protein" if rows else "Nothing logged",
                           "detail": det, "partial": d == today})
                if rows and d < today:
                    kcal_days.append(kc)
                    protein_days.append(pr)
        for s in subs.get(d, []):
            m = s.metrics or {}
            if s.form_type == "weekly":
                title = f"Week {s.week_number} check-in" if s.week_number else "Weekly check-in"
            else:
                title = "Daily check-in"
            replied = bool(s.reply)
            det = [[k, v] for k, v in (
                ("Weight", _kg(m["weight"]) if m.get("weight") else None),
                ("Sleep", f"{m['sleep_hours']:g} h" if isinstance(m.get("sleep_hours"), (int, float)) else None),
                ("Energy", f"{m['energy']} / 5" if m.get("energy") else None),
                ("Mood", f"{m['mood']} / 5" if m.get("mood") else None),
                ("Stress", f"{m['stress']} / 5" if m.get("stress") else None),
            ) if v]
            if s.form_type == "weekly":
                det.append(["Photos", "Added" if d in photo_days else "None this week"])
            es.append({"type": "checkin", "title": title,
                       "sub": f"Sent · {coach} replied" if replied else
                       ("Sent · seen by " + coach if s.reviewed_at else f"Sent · waiting for {coach}"),
                       "badge": "Reply" if replied else "", "badge_color": "green" if replied else "",
                       "detail": det, "note": f"{coach}: {s.reply}" if replied else "", "id": str(s.id)})
        w = next((x for x in all_w if x.date == d), None)
        if w:
            prev = next((x for x in reversed(all_w) if x.date < d), None)
            es.append({"type": "weight", "title": f"Weight · {_kg(w.weight_kg)}",
                       "sub": f"Weigh-in · {_chg(w.weight_kg - prev.weight_kg)} vs {prev.date.day} "
                              f"{prev.date.strftime('%b')}" if prev else "First weigh-in",
                       "detail": [["Weigh-in", _kg(w.weight_kg)]] +
                                 ([["Since start", _chg(w.weight_kg - all_w[0].weight_kg)]] if all_w else [])})
        m = next((x for x in all_m if x.date == d), None)
        if m and m.values:
            # Body measurements sit with the weigh-ins (Weight filter), each row with its change since the last time.
            keys = sorted(m.values, key=lambda k: MEASURE_KEYS.index(k) if k in MEASURE_KEYS else 99)
            det = []
            for k in keys:
                before = next((x.values[k] for x in reversed(all_m) if x.date < d and k in x.values), None)
                ch = "" if before is None else f" ({'+' if m.values[k] > before else ''}{round(m.values[k] - before, 1):g})" \
                    if m.values[k] != before else " (same)"
                det.append([m_names.get(k, (k, ""))[0], amt(k, m.values[k]) + ch])
            es.append({"type": "weight", "title": f"Measurements · {len(keys)} logged",
                       "sub": ", ".join(f"{m_names.get(k, (k, ''))[0]} {amt(k, m.values[k])}" for k in keys[:3])
                              + (f" +{len(keys) - 3}" if len(keys) > 3 else ""),
                       "detail": det})
        score = adherence(client, 1, d)
        if score is not None and d < today:
            scores.append(score)
        if es:
            out_days.append({"date": d, "score": score, "entries": es})

    in_range = [x for x in all_w if x.date >= start]
    summary = {
        "days": n, "adherence": round(sum(scores) / len(scores)) if scores else None,
        "workouts_done": wo_done, "workouts_planned": wo_planned,
        "avg_kcal": round(sum(kcal_days) / len(kcal_days)) if kcal_days else None, "kcal_target": target,
        "avg_protein": round(sum(protein_days) / len(protein_days)) if protein_days else None,
        "protein_target": protein_target,
        "weight_from": _f(in_range[0].weight_kg) if len(in_range) > 1 else None,
        "weight_to": _f(in_range[-1].weight_kg) if len(in_range) > 1 else None,
    }
    if kind in HISTORY_TYPES:
        out_days = [{**x, "entries": [e for e in x["entries"] if e["type"] == kind]} for x in out_days]
        out_days = [x for x in out_days if x["entries"]]
    total = len(out_days)
    return {"range": rng if rng in HISTORY_RANGES else "week", "type": kind or "", "from": start, "to": today,
            "summary": summary, "count": total, "offset": offset, "days": out_days[offset:offset + limit]}
