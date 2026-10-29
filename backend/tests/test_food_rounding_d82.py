"""Phase 1 part 2 (D-82): food amounts are kept unrounded, so a day's total is the sum of exact values and only the
screen rounds. Before: each entry was rounded (kcal to a whole number) before the day was added up."""
from decimal import Decimal

from apps.nutrition.models import Food


def _food(kcal, p, c, f):
    return Food(name="t", kcal=kcal, protein=Decimal(p), carbs=Decimal(c), fat=Decimal(f))


def test_per_grams_is_unrounded():
    # 173 kcal per 100 g; 150 g → 259.5 kcal, not 260 (the old rounding)
    m = _food(173, "9.9", "27.0", "2.5").per_grams(150)
    assert m["kcal"] == 259.5
    assert round(m["protein"], 4) == 14.85


def test_day_total_adds_exact_values():
    # three entries of 100 g: 173.3 + 173.3 + 173.3 = 519.9; the old per-entry rounding gave 173 × 3 = 519
    foods = [_food(Decimal("173.3"), "0", "0", "0")] * 3
    total = sum(f.per_grams(100)["kcal"] for f in foods)
    assert round(total, 1) == 519.9
