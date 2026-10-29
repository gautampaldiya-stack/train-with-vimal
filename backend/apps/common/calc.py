"""Shared calculation module (Phase 1, batch 1): volume, workout time, rest, records and nutrition totals.

Every screen (client app, trainer and admin views, history, progress, activity feed) gets its numbers from
these functions, so the same workout shows the same number everywhere. Pure functions: no database access.

Storage rules: weights in kg, time in whole seconds, values unrounded. Round only for display.

Formulas (each one has a test in tests/test_calc.py with real numbers):
- Volume of a set      = weight_kg × reps.  Warm-up sets, undone sets, sets with 0 reps and cardio count 0.
                          Drop sets count. Bodyweight sets lift the body weight that day plus any added load.
- Workout time         = finished − started − paused. Sets added after finish are a separate segment, summed.
- Rest taken           = next set start − set done (or rest end − set done), in whole seconds, never negative.
- Epley 1RM            = weight × (1 + reps / 30). One rep is the weight itself.
- Nutrition totals     = sum of the stored per-entry values of eaten entries only. Skipped entries add nothing.
- Calories from macros = 4 × protein_g + 4 × carbs_g + 9 × fat_g (kcal per gram).
"""

from dataclasses import dataclass

KCAL_PER_G = {"protein": 4, "carbs": 4, "fat": 9}


def set_volume(weight_kg, reps, *, done=True, warmup=False, bodyweight=False, body_kg=None, added_kg=0):
    """kg × reps for one set. A bodyweight set lifts the day's body weight plus any added load."""
    if warmup or not done or not reps:
        return 0.0
    if bodyweight:
        load = (float(body_kg) if body_kg is not None else 0.0) + float(added_kg or 0)
    else:
        load = float(weight_kg) if weight_kg is not None else 0.0
    return load * int(reps)


def workout_volume(sets, body_kg=None):
    """Total volume of a list of set dicts (keys as in set_volume; `weight` = weight_kg)."""
    return sum(
        set_volume(s.get("weight"), s.get("reps"), done=s.get("done", True), warmup=s.get("warmup", False),
                   bodyweight=s.get("bodyweight", False), body_kg=body_kg, added_kg=s.get("added", 0))
        for s in sets
    )


def workout_seconds(started, finished, paused_seconds=0, extra_segments=()):
    """Time of one workout in whole seconds: finished − started − paused, plus each later segment (sets added
    after finish). Negative spans (clock skew) count as 0."""
    main = max(int((finished - started).total_seconds()) - int(paused_seconds or 0), 0)
    return main + sum(max(int(s), 0) for s in extra_segments)


def rest_taken(set_done_at, next_start_at):
    """Actual rest between one set being done and the next set starting, whole seconds, never negative."""
    if set_done_at is None or next_start_at is None:
        return 0
    return max(int((next_start_at - set_done_at).total_seconds()), 0)


def epley_1rm(weight_kg, reps):
    """Estimated one-rep max (Epley). One rep is the lifted weight itself."""
    if not weight_kg or not reps:
        return 0.0
    w, r = float(weight_kg), int(reps)
    return w if r == 1 else w * (1 + r / 30)


@dataclass(frozen=True)
class Records:
    heaviest_kg: float
    best_session_volume: float
    best_1rm: float


def records(session_volumes, sets):
    """Records for one exercise. `session_volumes`: volume of each session. `sets`: (weight_kg, reps) pairs of
    working sets, every session. Heaviest = the heaviest single set weight (not counting zero-rep sets)."""
    heaviest = max((float(w) for w, r in sets if w and r), default=0.0)
    best_session = max((float(v) for v in session_volumes), default=0.0)
    best_1rm = max((epley_1rm(w, r) for w, r in sets if w and r), default=0.0)
    return Records(heaviest, best_session, best_1rm)


def macro_kcal(protein_g, carbs_g, fat_g):
    return KCAL_PER_G["protein"] * float(protein_g or 0) + KCAL_PER_G["carbs"] * float(carbs_g or 0) \
        + KCAL_PER_G["fat"] * float(fat_g or 0)


def nutrition_totals(entries):
    """Totals of eaten entries. `entries`: dicts with kcal, protein, carbs, fat and `eaten` (False = skipped).
    Numbers stay unrounded; the screen rounds."""
    out = {"kcal": 0.0, "protein": 0.0, "carbs": 0.0, "fat": 0.0}
    for e in entries:
        if not e.get("eaten", True):
            continue
        for k in out:
            out[k] += float(e.get(k) or 0)
    return out
