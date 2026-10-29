"""Phase 1 (batch 1): the shared calculation module, with real sample numbers. Expected values are worked out by
hand in each test's comment, so a wrong formula shows as a wrong number."""
from datetime import datetime, timedelta, timezone

import pytest

from apps.common import calc

T0 = datetime(2026, 10, 29, 10, 0, tzinfo=timezone.utc)


# ---------------------------------------------------------------- volume
def test_three_sets_of_60kg_for_10_reps():
    # 3 × 60 × 10 = 1800
    assert calc.workout_volume([{"weight": 60, "reps": 10}] * 3) == 1800


def test_warmup_undone_zero_reps_and_drop_sets():
    sets = [
        {"weight": 20, "reps": 10, "warmup": True},       # warm-up: 0
        {"weight": 60, "reps": 10, "done": False},         # not done: 0
        {"weight": 60, "reps": 0},                         # zero reps: 0
        {"weight": 60, "reps": 8},                         # working: 480
        {"weight": 40, "reps": 6},                         # drop set: 240 (counts)
    ]
    assert calc.workout_volume(sets) == 720


def test_bodyweight_uses_the_day_body_weight_plus_added_load():
    # 72 kg body × 15 = 1080; with a 10 kg vest: (72 + 10) × 15 = 1230; no body weight recorded: 0 + 10 × 15 = 150
    assert calc.set_volume(None, 15, bodyweight=True, body_kg=72) == 1080
    assert calc.set_volume(None, 15, bodyweight=True, body_kg=72, added_kg=10) == 1230
    assert calc.set_volume(None, 15, bodyweight=True, body_kg=None, added_kg=10) == 150


def test_empty_session_and_zero_weight():
    assert calc.workout_volume([]) == 0
    assert calc.set_volume(0, 10) == 0


def test_weights_stay_unrounded():
    # 62.5 × 9 = 562.5 (not rounded here)
    assert calc.set_volume(62.5, 9) == 562.5


# ---------------------------------------------------------------- time
def test_workout_time_minus_pause():
    # 10:00 → 10:50 = 50 min, minus 5 min paused = 45 min = 2700 s
    assert calc.workout_seconds(T0, T0 + timedelta(minutes=50), paused_seconds=300) == 2700


def test_sets_added_after_finish_are_a_separate_segment():
    # 45 min (2700 s) + 4 min added (240 s) = 49 min = 2940 s
    assert calc.workout_seconds(T0, T0 + timedelta(minutes=50), 300, extra_segments=[240]) == 2940


def test_empty_or_clock_skew_gives_zero_not_negative():
    assert calc.workout_seconds(T0, T0) == 0
    assert calc.workout_seconds(T0, T0 + timedelta(minutes=1), paused_seconds=600) == 0


# ---------------------------------------------------------------- rest
def test_rest_taken_is_actual_not_planned():
    # set done 10:00:00, next set starts 10:01:45 → 105 s (plan was 120 s)
    assert calc.rest_taken(T0, T0 + timedelta(seconds=105)) == 105


def test_rest_missing_or_negative_is_zero():
    assert calc.rest_taken(None, T0) == 0
    assert calc.rest_taken(T0, T0 - timedelta(seconds=5)) == 0


# ---------------------------------------------------------------- records
def test_epley_one_rep_max():
    # 60 × (1 + 10/30) = 80; one rep is the weight itself
    assert calc.epley_1rm(60, 10) == pytest.approx(80)
    assert calc.epley_1rm(100, 1) == 100
    assert calc.epley_1rm(0, 5) == 0


def test_records_heaviest_best_session_and_1rm():
    sets = [(80, 5), (60, 10), (100, 0)]  # the 100 kg set has 0 reps: not a record
    recs = calc.records([1200.0, 1800.0], sets)
    assert recs.heaviest_kg == 80
    assert recs.best_session_volume == 1800
    assert recs.best_1rm == pytest.approx(max(80 * (1 + 5 / 30), 80))  # 93.33


# ---------------------------------------------------------------- nutrition
def test_macro_kcal_per_gram():
    # 30 g protein × 4 + 40 g carbs × 4 + 10 g fat × 9 = 370
    assert calc.macro_kcal(30, 40, 10) == 370


def test_totals_skip_skipped_entries_and_keep_decimals():
    entries = [
        {"kcal": 250.4, "protein": 20.2, "carbs": 30.0, "fat": 5.1, "eaten": True},
        {"kcal": 300, "protein": 10, "carbs": 40, "fat": 9, "eaten": False},   # skipped: excluded
        {"kcal": 99.6, "protein": 4.0, "carbs": 10.0, "fat": 2.5, "eaten": True},
    ]
    t = calc.nutrition_totals(entries)
    assert t["kcal"] == pytest.approx(350.0)
    assert t["protein"] == pytest.approx(24.2)
    assert t["carbs"] == pytest.approx(40.0)
    assert t["fat"] == pytest.approx(7.6)


def test_empty_day_totals_are_zero():
    assert calc.nutrition_totals([]) == {"kcal": 0.0, "protein": 0.0, "carbs": 0.0, "fat": 0.0}
