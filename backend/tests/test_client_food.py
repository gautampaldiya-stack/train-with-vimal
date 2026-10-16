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


def test_change_and_remove_the_photo_of_a_logged_meal(client_user):
    today = timezone.localdate().isoformat()
    meal = _day(client_user)["meals"][-1]
    url = f"/api/v1/me/food/meals/{meal['id']}/photo/"
    # not logged yet: no photo on its own
    assert client_user.post(url, {"date": today, "photo": PNG}, format="json").status_code == 400
    client_user.post(f"/api/v1/me/food/meals/{meal['id']}/eat/", {"date": today}, format="json")
    r = client_user.post(url, {"date": today, "photo": PNG}, format="json")
    assert r.status_code == 200
    assert next(m for m in r.json()["meals"] if m["id"] == meal["id"])["photo"].startswith("http")
    r = client_user.post(url, {"date": today, "photo": None}, format="json")
    m = next(m for m in r.json()["meals"] if m["id"] == meal["id"])
    assert m["photo"] is None and m["pill"] == "logged"


def test_copy_yesterday_can_be_undone(client_user):
    from datetime import timedelta
    today = timezone.localdate()
    meal = _day(client_user)["meals"][0]
    client_user.post(f"/api/v1/me/food/meals/{meal['id']}/eat/", {"date": (today - timedelta(days=1)).isoformat()},
                     format="json")
    MealDayState.objects.filter(meal_id=meal["id"], date=today).delete()
    FoodLogEntry.objects.filter(meal_id=meal["id"], date=today).delete()
    r = client_user.post("/api/v1/me/food-log/copy-yesterday/", {}, format="json")
    c = r.json()
    assert c["copied"] == len(c["ids"]) > 0 and meal["id"] in c["meals"]
    assert next(m for m in _day(client_user)["meals"] if m["id"] == meal["id"])["pill"] == "logged"
    # copying again does not log the same plan meal twice
    again = client_user.post("/api/v1/me/food-log/copy-yesterday/", {}, format="json").json()
    assert meal["id"] not in again["meals"]
    client_user.post("/api/v1/me/food-log/undo-copy/", {"ids": again["ids"], "meals": again["meals"]}, format="json")
    r = client_user.post("/api/v1/me/food-log/undo-copy/", {"ids": c["ids"], "meals": c["meals"]}, format="json")
    assert r.json()["removed"] == c["copied"]
    assert next(m for m in _day(client_user)["meals"] if m["id"] == meal["id"])["pill"] != "logged"


def test_other_time_entry_has_its_own_name_and_time(client_user):
    from datetime import timedelta
    at = timezone.now() - timedelta(minutes=50)
    apple = Food.objects.get(name="Apple", owner_client=None)
    r = client_user.post("/api/v1/me/food-log/", {"meal_name": "Evening chai", "other_time": True, "food": str(apple.id),
                                                  "logged_at": at.isoformat()}, format="json")
    assert r.status_code == 201, r.content
    e = r.json()
    assert e["other_time"] and e["source"] == "off_plan" and e["meal_name"] == "Evening chai"
    row = next(x for x in _day(client_user)["log"] if x["id"] == e["id"])
    assert row["other_time"] and abs((timezone.datetime.fromisoformat(row["time"]) - at).total_seconds()) < 1
    client_user.delete(f"/api/v1/me/food-log/{e['id']}/")
