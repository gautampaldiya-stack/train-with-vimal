import base64

from django.utils import timezone

from apps.nutrition.models import Food, FoodLogEntry, MealDayState

PNG = "data:image/png;base64," + base64.b64encode(bytes.fromhex(
    "89504e470d0a1a0a0000000d4948445200000001000000010806000000"
    "1f15c4890000000d49444154789c6360000002000154a24f5d0000000049454e44ae426082")).decode()


def _day(c, **q):
    r = c.get("/api/v1/me/food/", q)
    assert r.status_code == 200, r.content
    return r.json()


def test_food_day_has_week_done_and_meal_macros(client_user):
    d = _day(client_user)
    assert len(d["week"]) == 7 and all("done" in w and "meals_logged" in w for w in d["week"])
    m = d["meals"][0]
    assert {"protein", "carbs", "fat", "photo"} <= set(m)


def test_mark_eaten_with_an_optional_photo(client_user):
    d = _day(client_user)
    meal = next(m for m in d["meals"] if m["pill"] != "logged")
    today = timezone.localdate().isoformat()
    r = client_user.post(f"/api/v1/me/food/meals/{meal['id']}/eat/", {"date": today, "photo": PNG}, format="json")
    assert r.status_code == 200, r.content
    after = next(m for m in r.json()["meals"] if m["id"] == meal["id"])
    assert after["pill"] == "logged" and after["photo"].startswith("http")
    rows = [x for x in r.json()["log"] if x["meal"] == meal["id"]]
    assert rows and all(x["photo"] == after["photo"] for x in rows)
    # Undo takes the photo away too
    r = client_user.post(f"/api/v1/me/food/meals/{meal['id']}/unlog/", {"date": today}, format="json")
    assert next(m for m in r.json()["meals"] if m["id"] == meal["id"])["photo"] is None
    # no photo is fine
    r = client_user.post(f"/api/v1/me/food/meals/{meal['id']}/eat/", {"date": today}, format="json")
    assert r.status_code == 200 and not MealDayState.objects.get(meal_id=meal["id"], date=today).photo
    r = client_user.post(f"/api/v1/me/food/meals/{meal['id']}/eat/", {"date": today, "photo": "nope"}, format="json")
    assert r.status_code == 400


def test_off_plan_entry_keeps_its_reason_and_undo_by_unit_name(client_user):
    food = Food.objects.filter(owner_client__isnull=True, units__isnull=False).first()
    unit = food.units.first()
    r = client_user.post("/api/v1/me/food-log/", {"meal_name": "Snack", "food": food.id, "quantity": 2,
                                                  "unit_name": unit.name, "off_plan": True, "reason": "Party"},
                         format="json")
    assert r.status_code == 201, r.content
    e = FoodLogEntry.objects.get(id=r.json()["id"])
    assert e.source == "off_plan" and e.reason == "Party" and e.unit_name == unit.name
    r = client_user.post("/api/v1/me/food-log/", {"meal_name": "Snack", "kcal": 200, "off_plan": True,
                                                  "reason": "Ate out"}, format="json")
    assert r.status_code == 201 and r.json()["source"] == "off_plan" and r.json()["reason"] == "Ate out"


def test_create_custom_food_by_serving(client_user):
    r = client_user.post("/api/v1/me/foods/", {"name": "Mom's veg upma", "serving": "1 katori", "kcal": 210,
                                               "protein": 6, "carbs": 32, "fat": 7}, format="json")
    assert r.status_code == 201, r.content
    f = r.json()
    assert f["mine"] and f["default_unit"]["name"] == "1 katori"
    food = Food.objects.get(id=f["id"])
    assert food.per_grams(food.default_unit.grams)["kcal"] == 210
    r = client_user.get("/api/v1/me/foods/", {"group": "mine"})
    assert any(x["id"] == f["id"] for x in r.json()["results"])
    r = client_user.post("/api/v1/me/foods/", {"name": "x", "serving": "", "kcal": 0}, format="json")
    assert r.status_code == 400
