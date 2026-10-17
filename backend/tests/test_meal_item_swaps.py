"""Client profile → Plans → Meal plan → Edit for X → Portion and swaps: each planned food's swaps belong to that
client's copy (MealItem.alternatives), seeded from the food's library swaps; match %; Was: line; Add a unit."""
from apps.nutrition.models import Food, FoodUnit, MealItem, MealPlanAssignment
from apps.nutrition.services import day_view
from apps.nutrition.swaps import match_percent


def _cid(trainer, name):
    return trainer.get("/api/v1/clients/", {"search": name}).json()["results"][0]["id"]


def _url(trainer, cid):
    a = trainer.get(f"/api/v1/clients/{cid}/meal-plans/").json()["current"][0]
    return a, f"/api/v1/clients/{cid}/meal-plans/{a['id']}/meals/"


def _payload(meals, swaps=True):
    def item(i):
        out = {"id": i["id"], "food": i["food"], "quantity": i["quantity"], "unit": i["unit"]}
        if swaps:
            out["swaps"] = [{"food": s["food"], "quantity": s["quantity"], "unit": s["unit"]} for s in i["swaps"]]
        return out
    return [{"id": m["id"], "name": m["name"], "time": m["time"], "kcal_target": m["kcal_target"],
             "options": [{"id": o["id"], "name": o["name"], "is_default": o["is_default"],
                          "items": [item(i) for i in o["items"]]} for o in m["options"]]} for m in meals]


def _items(d):
    return [i for m in d["meals"] for o in m["options"] for i in o["items"]]


def _with_library_swap():
    """A master item whose food has library swaps (the demo data has some)."""
    f = Food.objects.filter(swaps__isnull=False, meal_items__isnull=False).distinct().first()
    assert f is not None, "demo data has a planned food with library swaps"
    return f


def test_copy_seeds_swaps_and_put_changes_only_that_client(trainer):
    food = _with_library_swap()
    riya, aditya = _cid(trainer, "riya"), _cid(trainer, "aditya")
    a_r, url_r = _url(trainer, riya)
    a_a, url_a = _url(trainer, aditya)
    assert a_r["plan"] == a_a["plan"], "both on the same master in the demo data"

    # master shown with the food's library swaps, each with amount, match % and kcal
    d = trainer.get(url_r).json()
    it = next(i for i in _items(d) if i["food"] == str(food.id))
    lib = {str(x.id) for x in food.swaps.all()}
    assert {s["food"] for s in it["swaps"]} == lib
    for s in it["swaps"]:
        assert 0 <= s["match"] <= 100 and s["amount"] and s["kcal"] >= 0
        assert s["match"] == match_percent(food, Food.objects.get(id=s["food"]))
    assert it["was"] is None  # master: no Was line

    # first save without touching swaps → Riya's copy is made, swaps seeded from the library
    r = trainer.put(url_r, {"weekday": 0, "every_day": True, "meals": _payload(d["meals"], swaps=False)},
                    format="json")
    assert r.status_code == 200, r.content
    d = r.json()
    assert d["custom"] is True
    copy_items = MealItem.objects.filter(option__meal__plan_id=d["copy"], food=food)
    assert copy_items and all({s["food"] for s in ci.alternatives} == lib for ci in copy_items)
    assert all(i["was"] is None for i in _items(d)), "nothing changed yet"

    # Riya: drop every swap of that food, add one new one
    other = Food.objects.exclude(id=food.id).exclude(id__in=food.swaps.all()).filter(owner_client__isnull=True,
                                                                                     units__isnull=False).first()
    unit = other.units.first()
    meals = _payload(d["meals"])
    for m in meals:
        for o in m["options"]:
            for i in o["items"]:
                if i["food"] == str(food.id):
                    i["swaps"] = [{"food": str(other.id), "quantity": "1.5", "unit": unit.id}]
    r = trainer.put(url_r, {"weekday": 0, "every_day": True, "meals": meals}, format="json")
    assert r.status_code == 200, r.content
    it = next(i for i in _items(r.json()) if i["food"] == str(food.id))
    assert [(s["food"], s["quantity"], s["unit"]) for s in it["swaps"]] == [(str(other.id), 1.5, unit.id)]
    assert "match" in it["swaps"][0]

    # the library and Aditya (same master, no copy) keep the old swaps
    assert {str(x.id) for x in Food.objects.get(id=food.id).swaps.all()} == lib
    it_a = next(i for i in _items(trainer.get(url_a).json()) if i["food"] == str(food.id))
    assert {s["food"] for s in it_a["swaps"]} == lib

    # Riya's Food tab counts her own swaps
    a = MealPlanAssignment.objects.get(id=a_r["id"])
    from django.utils import timezone
    day = day_view(a.client, timezone.localdate())
    rows = [i for m in day["meals"] for i in m["items"] if i["food"] == food.id and not i["swapped_from"]]
    assert rows and all(i["swaps"] == 1 for i in rows)


def test_was_line_and_bad_swap_unit(trainer):
    riya = _cid(trainer, "riya")
    _, url = _url(trainer, riya)
    d = trainer.get(url).json()
    meals = _payload(d["meals"])
    first = meals[0]["options"][0]["items"][0]
    first["quantity"] = str(float(first["quantity"]) * 2)
    r = trainer.put(url, {"weekday": 0, "every_day": True, "meals": meals}, format="json")
    assert r.status_code == 200, r.content
    was = r.json()["meals"][0]["options"][0]["items"][0]["was"]
    assert was and was != "not in the master"

    # a unit of another food is refused
    meals = _payload(r.json()["meals"])
    f1, f2 = Food.objects.filter(units__isnull=False, owner_client__isnull=True).distinct()[:2]
    meals[0]["options"][0]["items"][0]["swaps"] = [{"food": str(f1.id), "quantity": 1, "unit": f2.units.first().id}]
    r = trainer.put(url, {"weekday": 0, "every_day": True, "meals": meals}, format="json")
    assert r.status_code == 400


def test_swap_options_and_add_unit(trainer):
    food = _with_library_swap()
    r = trainer.get(f"/api/v1/foods/{food.id}/swap-options/", {"grams": 100, "scope": "all", "client_diet": "veg"})
    assert r.status_code == 200, r.content
    rows = r.json()
    assert rows and all({"match", "quantity", "unit", "amount", "macros", "kcal"} <= set(x) for x in rows)
    assert [x["match"] for x in rows] == sorted((x["match"] for x in rows), reverse=True)
    assert all(x["diet"] in ("veg", "vegan") for x in rows)
    # same calories as 100 g of the food (within rounding)
    want = float(food.kcal)
    assert all(abs(x["macros"]["kcal"] - want) <= max(25, want * 0.3) for x in rows if float(x["kcal"]))

    r = trainer.post(f"/api/v1/foods/{food.id}/units/", {"name": "1 big bowl", "grams": "220"}, format="json")
    assert r.status_code == 201, r.content
    assert FoodUnit.objects.filter(food=food, name="1 big bowl").exists()
    r = trainer.post(f"/api/v1/foods/{food.id}/units/", {"name": "1 big bowl", "grams": "200"}, format="json")
    assert r.status_code == 400
