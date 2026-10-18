"""Swaps of one planned food (MealItem.alternatives): the foods a client may eat instead, with an amount that gives
about the same calories, and how close each one is in protein / carbs / fat (match %)."""
from decimal import Decimal

from .models import Food

MAX_SWAPS = 8


def match_percent(a, b):
    """Match % of food `b` as a swap for food `a` (both per 100 g), from 0 to 100.

    Each food's calories are split into the share from protein (4 kcal/g), carbs (4 kcal/g) and fat (9 kcal/g), so
    the score does not depend on the amount. The score is 100 × (1 − half the sum of the share differences):

        match = 100 × (1 − (|Pa − Pb| + |Ca − Cb| + |Fa − Fb|) / 2)

    Same split → 100 %, no overlap at all (e.g. pure protein vs pure fat) → 0 %. Example: whey (80/10/10) vs Greek
    yogurt (55/22/23) → 100 × (1 − (0.25 + 0.12 + 0.13) / 2) = 75 %."""
    def split(f):
        kcal = float(4 * f.protein + 4 * f.carbs + 9 * f.fat) or 1.0
        return (4 * float(f.protein) / kcal, 4 * float(f.carbs) / kcal, 9 * float(f.fat) / kcal)

    sa, sb = split(a), split(b)
    diff = sum(abs(x - y) for x, y in zip(sa, sb)) / 2  # 0..1
    return max(0, round(100 * (1 - diff)))


def same_kcal_grams(original, original_grams, alt):
    """'Amounts give the same calories as 60 g.'"""
    kcal = float(original.kcal) * float(original_grams) / 100
    if not alt.kcal:
        return None
    return round(kcal * 100 / float(alt.kcal))


def same_kcal_amount(kcal, alt, unit="default"):
    """(quantity, unit) of `alt` giving about `kcal`: in its default unit, rounded to a half (1.5 × 150 g), else in
    grams rounded to 5 g. `unit` picks another FoodUnit (None = grams)."""
    u = alt.default_unit if unit == "default" else unit
    per100 = float(alt.kcal or 0)
    if per100 <= 0:
        return (1.0, u) if u else (100.0, None)
    if u is not None:
        q = kcal / (per100 * float(u.grams) / 100)
        return max(0.5, round(q * 2) / 2), u
    return float(max(5, round(kcal * 100 / per100 / 5) * 5)), None


def item_kcal(item):
    return float(item.food.kcal) * float(item.grams) / 100


def seed_from_food(item):
    """The food's library swaps (Food.swaps) as this item's swaps, each with the same calories as the item."""
    kcal = item_kcal(item)
    out = []
    for f in item.food.swaps.select_related("default_unit").all()[:MAX_SWAPS]:
        q, u = same_kcal_amount(kcal, f)
        out.append({"food": str(f.id), "quantity": q, "unit": u.id if u else None})
    return out


def item_swaps(item):
    """The raw swaps of a planned food: its own list, else (never set) the food's library swaps."""
    if item.alternatives is not None:
        return list(item.alternatives)
    return seed_from_food(item)


_FRAC = {0: "", 25: "¼", 50: "½", 75: "¾"}
_PLURAL = {"piece": "pieces", "slice": "slices", "cup": "cups", "scoop": "scoops", "plate": "plates", "bowl": "bowls",
           "glass": "glasses", "handful": "handfuls"}


def friendly_qty(q):
    """0.5 → '½', 1.5 → '1½', 2 → '2', 0.3 → '0.3'."""
    q = float(q)
    whole = int(q)
    f = _FRAC.get(round((q - whole) * 100))
    if f is None:
        return f"{round(q, 1):g}"
    return f if whole == 0 and f else f"{whole}{f}"


def portion_label(quantity, unit):
    """'½ katori', '1½ katori', '2 pieces', '150 g' (never '0.5 × 1 katori'). Same as the app's `portionText`."""
    q = float(quantity)
    if unit is None:
        return f"{q:g} g"
    name = unit.name.strip()
    if not name.startswith("1 "):
        return name if q == 1 else f"{friendly_qty(q)} × {name}"
    noun = name[2:].strip()
    if q > 1:
        noun = _PLURAL.get(noun, noun)
    return f"{friendly_qty(q)} {noun}"


def amount_label(quantity, unit):
    """'1½ scoop · 48 g', '1 medium · 118 g', '150 g'."""
    if unit is None:
        return portion_label(quantity, None)
    g = float(quantity) * float(unit.grams)
    return f"{portion_label(quantity, unit)} · {round(g, 1):g} g"


def resolve(item, cache=None):
    """The item's swaps for the app: food, amount, kcal / P / C / F and the match % against the item's food."""
    from .serializers import FoodPickSerializer

    raw = item_swaps(item)
    cache = {} if cache is None else cache
    need = [str(r.get("food")) for r in raw if str(r.get("food")) not in cache]
    if need:
        for f in Food.all_objects.filter(id__in=need).select_related("default_unit").prefetch_related("units"):
            cache[str(f.id)] = f
    out = []
    for r in raw:
        f = cache.get(str(r.get("food")))
        if f is None:
            continue
        unit = next((u for u in f.units.all() if u.id == r.get("unit")), None) if r.get("unit") else None
        q = float(r.get("quantity") or 0) or 1.0
        grams = Decimal(str(q)) * (unit.grams if unit else Decimal(1))
        m = f.per_grams(grams)
        out.append({"food": str(f.id), "quantity": q, "unit": unit.id if unit else None,
                    "unit_name": unit.name if unit else "g", "name": f.name, "amount": amount_label(q, unit),
                    "grams": float(grams), **m, "match": match_percent(item.food, f),
                    "food_detail": FoodPickSerializer(f).data})
    return out


def clean(item_food, rows):
    """Validated swaps from the app: [{"food": Food, "quantity": Decimal, "unit": FoodUnit | None}] → JSON."""
    out, seen = [], set()
    for r in rows:
        f = r["food"]
        if f.id == item_food.id or f.id in seen:
            continue
        seen.add(f.id)
        u = r.get("unit")
        out.append({"food": str(f.id), "quantity": float(r["quantity"]), "unit": u.id if u else None})
    return out[:MAX_SWAPS]

