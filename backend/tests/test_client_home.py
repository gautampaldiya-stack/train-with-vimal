from datetime import date

from django.utils import timezone

from apps.habits.models import HabitLog
from apps.nutrition.models import WaterLog


def _home(c):
    r = c.get("/api/v1/me/home/")
    assert r.status_code == 200, r.content
    return r.json()


def test_home_has_every_card(client_user):
    d = _home(client_user)
    assert d["first_name"] == "Riya" and d["goal"] == "Fat loss"
    assert len(d["strip"]) == 7
    days = [date.fromisoformat(x["date"]) for x in d["strip"]]
    assert days[0].weekday() == 0 and sum(x["today"] for x in d["strip"]) == 1
    for x in d["strip"]:
        assert x["is_rest"] == (not x["exercises"])
        if x["done"]:
            assert x["done_line"].startswith("Done · ")
    assert [m["name"] for m in d["meals"]] == ["Breakfast", "Lunch", "Snack", "Dinner"]
    assert all(m["foods"] and m["kcal"] > 0 for m in d["meals"])
    assert {s["name"] for s in d["supplements"]} == {"Whey protein", "Vitamin D3", "Magnesium"}
    assert d["habits_soon"][0]["name"] == "No sugary drinks"
    assert "No sugary drinks" not in [h["name"] for h in d["habits"]]
    kinds = [c["kind"] for c in d["coming_up"]]
    assert kinds == ["session", "checkin", "plan_end"]
    assert d["coming_up"][0]["place"] == "Gym floor" and d["coming_up"][1]["questions"] > 0
    assert d["unread"] == sum(not n["read"] for n in d["notices"])
    assert d["trainer_note"]["by"]["full_name"] == "Aman Verma" and d["trainer_note"]["body"]


def test_home_is_client_only(trainer):
    assert trainer.get("/api/v1/me/home/").status_code == 403


def test_water_moves_the_water_habit(client_user):
    today = timezone.localdate()
    HabitLog.objects.filter(client__email="riya@example.com", date=today).delete()
    WaterLog.objects.filter(client__email="riya@example.com", date=today).delete()
    r = client_user.post("/api/v1/me/food-log/water/", {"ml": 750, "date": today.isoformat()}, format="json")
    assert r.status_code in (200, 201), r.content
    water = next(h for h in _home(client_user)["habits"] if h["icon"] == "water")
    assert water["value"] == 3 and not water["done"]
    for ml in (2000, 250):
        client_user.post("/api/v1/me/food-log/water/", {"ml": ml, "date": today.isoformat()}, format="json")
    water = next(h for h in _home(client_user)["habits"] if h["icon"] == "water")
    assert water["value"] == 12 and water["done"]
    client_user.post("/api/v1/me/food-log/water/", {"ml": -250, "date": today.isoformat()}, format="json")
    log = HabitLog.objects.get(client__email="riya@example.com", date=today, habit__icon="water")
    assert log.value == 11 and not log.done


def test_mark_all_read_clears_the_bell(client_user):
    assert client_user.post("/api/v1/notifications/read_all/").status_code == 200
    assert _home(client_user)["unread"] == 0
