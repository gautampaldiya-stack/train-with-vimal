"""Phase 1: every formula in apps/common/calc.py with real numbers (input → expected).

Formulas (same as the code comments):
  set volume      = (weight [+ body weight on that day for a bodyweight set]) × reps; warm-up / not done / no reps = 0
  session volume  = Σ set volume
  duration        = finished − started − paused + Σ added segments   (whole seconds, never < 0)
  rest taken      = next set start − this set done                    (None if one is missing, never < 0)
  e1RM (Epley)    = weight × (1 + reps / 30); 1 rep = weight
  nutrition total = Σ stored (unrounded) values of eaten entries; kcal check 4P + 4C + 9F
"""
from datetime import date, datetime, timedelta
from decimal import Decimal
from types import SimpleNamespace as S

import pytest

from apps.common import calc

T0 = datetime(2026, 10, 29, 10, 0, 0)


def st(kg=None, reps=None, done=True, wu=False, bw=False):
    return S(weight_kg=None if kg is None else Decimal(str(kg)), reps=reps, done=done, is_warmup=wu, is_bodyweight=bw)


# ---------------------------------------------------------------- volume
@pytest.mark.parametrize("s, body, expected", [
    (st(60, 10), None, 600.0),                  # 60 kg × 10
    (st(62.5, 8), None, 500.0),                 # decimals kept: 62.5 × 8
    (st(60, 0), None, 0.0),                     # zero reps
    (st(60, 10, done=False), None, 0.0),        # skipped / not ticked
    (st(40, 12, wu=True), None, 0.0),           # warm-up excluded
    (st(None, None), None, 0.0),                # cardio / timed set: no reps
    (st(None, 15, bw=True), 72.0, 1080.0),      # bodyweight: 72 kg × 15
    (st(10, 8, bw=True), 72.0, 656.0),          # bodyweight + 10 kg belt: 82 × 8
    (st(None, 15, bw=True), None, 0.0),         # bodyweight, no body weight recorded
])
def test_set_volume(s, body, expected):
    assert calc.set_volume(s, body) == expected


def test_session_volume():
    sets = [st(40, 10, wu=True), st(60, 10), st(60, 10), st(60, 8), st(60, 10, done=False)]
    w = S(sets=S(all=lambda: sets))
    assert calc.workout_volume(w) == 1680.0  # 600 + 600 + 480; warm-up and the skipped set add 0
    assert calc.workout_volume(S(sets=S(all=lambda: []))) == 0  # empty session


# ---------------------------------------------------------------- duration and rest
def test_duration():
    assert calc.duration_seconds(T0, T0 + timedelta(minutes=50), paused_seconds=300) == 2700  # 45 min
    assert calc.duration_seconds(T0, T0 + timedelta(minutes=50), 300, extra_segments=[240]) == 2940  # 45 + 4 min
    assert calc.duration_seconds(T0, T0) == 0  # empty session
    assert calc.duration_seconds(T0, T0 + timedelta(minutes=5), paused_seconds=600) == 0  # never below 0
    assert calc.duration_seconds(T0, None) == 0  # not finished


def test_rest_taken():
    assert calc.rest_taken(T0, T0 + timedelta(seconds=105)) == 105  # planned 2:00, took 1:45
    assert calc.rest_taken(T0, T0 + timedelta(minutes=3, seconds=10)) == 190
    assert calc.rest_taken(T0, None) is None  # last set
    assert calc.rest_taken(None, T0) is None  # set never ticked
    assert calc.rest_taken(T0, T0 - timedelta(seconds=5)) == 0  # clock skew never negative


# ---------------------------------------------------------------- records
def test_e1rm():
    assert calc.e1rm(60, 10) == pytest.approx(80.0)  # 60 × (1 + 10/30)
    assert calc.e1rm(100, 5) == pytest.approx(116.6667, abs=1e-4)
    assert calc.e1rm(140, 1) == 140.0  # one rep = the weight
    assert calc.e1rm(60, 0) is None and calc.e1rm(None, 5) is None


def test_records():
    d1, d2 = date(2026, 10, 20), date(2026, 10, 27)
    sessions = [
        (d1, [st(60, 10), st(60, 10), st(60, 10)]),              # 1800 kg
        (d2, [st(50, 12, wu=True), st(80, 3), st(70, 8, done=False), st(65, 8)]),  # 240 + 520 = 760 kg
    ]
    r = calc.records(sessions)
    assert r["heaviest"] == {"weight_kg": 80.0, "reps": 3, "date": d2}
    assert r["best_volume"] == {"volume": 1800.0, "date": d1}
    # e1RM: 60×10 → 80.0 (d1), 80×3 → 88.0 (d2), 65×8 → 82.33 (d2); the 70×8 set was not done
    assert r["best_e1rm"]["e1rm"] == pytest.approx(88.0) and r["best_e1rm"]["date"] == d2
    assert calc.records([]) == {"heaviest": None, "best_volume": None, "best_e1rm": None}
    assert calc.records([(d1, [st(60, 10, done=False)])])["heaviest"] is None


def test_records_best_e1rm_picks_the_highest():
    d = date(2026, 10, 27)
    r = calc.records([(d, [st(60, 10), st(80, 3), st(70, 6)])])
    # 60×10 → 80.0, 80×3 → 88.0, 70×6 → 84.0
    assert r["best_e1rm"] == {"e1rm": pytest.approx(88.0), "weight_kg": 80.0, "reps": 3, "date": d}


# ---------------------------------------------------------------- nutrition
def test_food_macros_unrounded():
    oats = S(kcal=Decimal("389"), protein=Decimal("16.9"), carbs=Decimal("66.3"), fat=Decimal("6.9"))
    m = calc.food_macros(oats, Decimal("45"))
    assert m == {"kcal": pytest.approx(175.05), "protein": pytest.approx(7.605), "carbs": pytest.approx(29.835),
                 "fat": pytest.approx(3.105)}


def test_nutrition_totals_no_rounding_drift():
    # ten portions of 52.4 kcal: rounding each first gives 10 × 52 = 520; the true total is 524
    rows = [{"kcal": 52.4, "protein": 1.04, "carbs": 9.06, "fat": 1.25}] * 10
    t = calc.nutrition_totals(rows)
    assert calc.show_kcal(t["kcal"]) == 524 and calc.show_g(t["protein"]) == 10.4
    assert calc.show_g(t["carbs"]) == 90.6 and calc.show_g(t["fat"]) == 12.5


def test_nutrition_totals_cases():
    eggs = {"kcal": 143.0, "protein": 12.6, "carbs": 0.7, "fat": 9.5}
    rice = {"kcal": 195.0, "protein": 4.0, "carbs": 42.0, "fat": 0.6}
    assert calc.nutrition_totals([eggs]) == {"kcal": 143.0, "protein": 12.6, "carbs": 0.7, "fat": 9.5}  # single
    assert calc.nutrition_totals([eggs, rice])["kcal"] == 338.0  # multiple
    half_rice = {k: v / 2 for k, v in rice.items()}
    assert calc.nutrition_totals([eggs, half_rice])["kcal"] == 240.5  # portion change
    assert calc.nutrition_totals([]) == {"kcal": 0.0, "protein": 0.0, "carbs": 0.0, "fat": 0.0}  # skipped / deleted


def test_kcal_from_macros_and_match():
    assert calc.kcal_from_macros(30, 40, 10) == 370  # 30×4 + 40×4 + 10×9
    assert calc.macros_match(370, 30, 40, 10)
    assert calc.macros_match(380, 30, 40, 10)  # 10 kcal off: within 15
    assert not calc.macros_match(500, 30, 40, 10)  # 130 off
    assert calc.macros_match(0, 0, 0, 0)


def test_show_rounding_half_up():
    assert calc.show_kcal(1799.5) == 1800 and calc.show_kcal(1799.4) == 1799 and calc.show_kcal(None) == 0
    assert calc.show_g(2.25) == 2.3 and calc.show_g(2.24) == 2.2


# ---------------------------------------------------------------- through the real food log (regression)
def test_logged_entries_are_stored_unrounded_and_total_once(client_user, admin):
    """Bug: each entry was rounded (kcal int) before adding up, so a day of small foods drifted."""
    from apps.accounts.models import User
    from apps.nutrition import services
    from apps.nutrition.models import Food, FoodLogEntry

    from django.utils import timezone

    riya = User.objects.get(email="riya@example.com")
    day = timezone.localdate() - timedelta(days=1)  # inside Riya's plan, so the coach's diary lists the day
    FoodLogEntry.objects.filter(client=riya, date=day).delete()
    mp = services._active_plan(riya, day)
    if mp:
        type(mp.followed).objects.filter(id=mp.followed.id).update(allow_off_plan=True)
    food = Food.objects.create(name="Test almonds", kcal=Decimal("579"), protein=Decimal("21.2"),
                               carbs=Decimal("21.6"), fat=Decimal("49.9"))
    for _ in range(3):
        services.log_food(riya, meal_name="Snack", food=food, quantity=Decimal("7"), day=day, off_plan=True)
    e = FoodLogEntry.objects.filter(client=riya, date=day).first()
    assert e.kcal == Decimal("40.530")  # 579 × 7 / 100, not 41
    t = services.totals(riya, day)
    assert t["kcal"] == pytest.approx(121.59)  # 3 × 40.53 (rounded first it was 3 × 41 = 123)
    assert calc.show_kcal(t["kcal"]) == 122
    # client app: each entry shown rounded (41), the day total from the unrounded sum (122, not 123)
    d = client_user.get(f"/api/v1/me/food/?date={day}").json()
    assert [x["kcal"] for x in d["log"]] == [41, 41, 41]
    assert d["ring"]["eaten"] == 122 and d["macros"]["protein"] == 4.5  # 3 × 1.484 = 4.452
    # admin / trainer food diary: the same 122
    rows = admin.get(f"/api/v1/clients/{riya.id}/food/?range=custom&from={day}&to={day}").json()
    rows = rows.get("results", rows) if isinstance(rows, dict) else rows
    assert [r["kcal"] for r in rows if str(r["date"]) == str(day)] == [122]
