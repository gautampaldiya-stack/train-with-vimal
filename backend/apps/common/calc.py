"""The one place every number is worked out (Phase 1): volume, duration, rest, records, nutrition totals.

Client app, trainer and admin screens all show what these functions return, so a number is the same everywhere.
Rules: work on unrounded values, round only when the number is shown (`show_kcal`, `show_g`). Weights in kg,
durations in whole seconds. Tests with real numbers: tests/test_calc.py.
"""
from decimal import Decimal

KCAL_PER_G = {"protein": 4, "carbs": 4, "fat": 9}


# ---------------------------------------------------------------- volume
def set_volume(s, body_kg=None):
    """kg × reps of one done working set.

    0 for: a warm-up set, a set not ticked done, 0 / no reps, cardio and timed sets (no reps).
    Bodyweight set: (body weight on the workout day + any added load) × reps; no body weight recorded → body counts 0,
    only the added load is counted. `body_kg` comes from `apps.training.services.body_weights` (that day's weigh-in,
    else the last one before it).
    """
    if s.is_warmup or not s.done or not s.reps:
        return 0.0
    load = float(s.weight_kg) if s.weight_kg is not None else 0.0
    if s.is_bodyweight:
        load += body_kg or 0.0
    return load * s.reps


def workout_volume(w, body_kg=None):
    """Session volume = Σ set_volume over every set of the workout."""
    return sum(set_volume(s, body_kg) for s in w.sets.all())


# ---------------------------------------------------------------- time
def duration_seconds(started_at, finished_at, paused_seconds=0, extra_segments=()):
    """Workout time = (finished − started − paused) + every later segment ("Log more sets" after finish).

    Example: 10:00 → 10:50 with 5 min paused = 2700 s; plus a 4 min added segment = 2940 s. Never below 0.
    """
    if started_at is None or finished_at is None:
        main = 0
    else:
        main = max(0, int((finished_at - started_at).total_seconds()) - int(paused_seconds or 0))
    return main + sum(max(0, int(x or 0)) for x in extra_segments)


def rest_taken(set_done_at, next_started_at):
    """Actual rest after a set = next set's start − this set's completion, in whole seconds.

    None when either time is missing (last set of the workout, or a set never ticked); never negative.
    """
    if set_done_at is None or next_started_at is None:
        return None
    return max(0, int((next_started_at - set_done_at).total_seconds()))


# ---------------------------------------------------------------- records
def e1rm(weight_kg, reps):
    """Estimated 1-rep max, Epley: weight × (1 + reps / 30). 1 rep = the weight itself; no weight / reps → None."""
    if weight_kg is None or not reps:
        return None
    w = float(weight_kg)
    return w if reps == 1 else w * (1 + reps / 30)


def records(workouts, body_kg_on=None):
    """Records of one exercise. `workouts`: [(date, [sets])], only that exercise's sets per session.

    heaviest: the heaviest done working set (weight, reps, date); best_volume: the session with the biggest
    Σ set_volume; best_e1rm: the highest Epley estimate of any done working set. Warm-ups and sets not done never
    count. Each is None when nothing qualifies. `body_kg_on(date)` gives the body weight for bodyweight sets.
    """
    heaviest = best_volume = best_1rm = None
    for day, sets in workouts:
        body = body_kg_on(day) if body_kg_on else None
        vol = sum(set_volume(s, body) for s in sets)
        if vol and (best_volume is None or vol > best_volume["volume"]):
            best_volume = {"volume": vol, "date": day}
        for s in sets:
            if s.is_warmup or not s.done or not s.reps or s.weight_kg is None or s.is_bodyweight:
                continue
            w = float(s.weight_kg)
            if heaviest is None or (w, s.reps) > (heaviest["weight_kg"], heaviest["reps"]):
                heaviest = {"weight_kg": w, "reps": s.reps, "date": day}
            est = e1rm(w, s.reps)
            if best_1rm is None or est > best_1rm["e1rm"]:
                best_1rm = {"e1rm": est, "weight_kg": w, "reps": s.reps, "date": day}
    return {"heaviest": heaviest, "best_volume": best_volume, "best_e1rm": best_1rm}


# ---------------------------------------------------------------- nutrition
def food_macros(food, grams):
    """kcal, protein, carbs, fat in `grams` of a food stored per 100 g. Unrounded (stored like this)."""
    f = Decimal(str(grams)) / Decimal(100)
    return {"kcal": float(food.kcal * f), "protein": float(food.protein * f), "carbs": float(food.carbs * f),
            "fat": float(food.fat * f)}


def nutrition_totals(entries):
    """Day (or meal) total = Σ of the eaten entries' stored values. Skipped meals have no entries, so they add 0.

    `entries`: FoodLogEntry rows or dicts with kcal / protein / carbs / fat. Returns unrounded floats.
    """
    out = {"kcal": 0.0, "protein": 0.0, "carbs": 0.0, "fat": 0.0}
    for e in entries:
        for k in out:
            v = e[k] if isinstance(e, dict) else getattr(e, k)
            out[k] += float(v or 0)
    return out


def kcal_from_macros(protein, carbs, fat):
    """Calories the grams add up to: 4 kcal/g protein, 4 kcal/g carbs, 9 kcal/g fat."""
    return 4 * float(protein or 0) + 4 * float(carbs or 0) + 9 * float(fat or 0)


def macros_match(kcal, protein, carbs, fat):
    """True when the stated kcal is within 15 kcal or 10 % of it of 4P + 4C + 9F ("Calories match" badge)."""
    kcal = float(kcal or 0)
    return abs(kcal_from_macros(protein, carbs, fat) - kcal) <= max(15, 0.1 * kcal)


def show_kcal(v):
    """kcal as shown: whole number (half up)."""
    return int(Decimal(str(v or 0)).quantize(Decimal("1"), rounding="ROUND_HALF_UP"))


def show_g(v):
    """Grams as shown: 1 decimal (half up)."""
    return float(Decimal(str(v or 0)).quantize(Decimal("0.1"), rounding="ROUND_HALF_UP"))
