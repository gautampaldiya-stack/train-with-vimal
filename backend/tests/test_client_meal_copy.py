"""Client profile → Plans → Meal plan → Edit for X: the client's own copy of the meal plan (foods, portions,
meal names, per-weekday meals), Reset to master; plus per-client habit edits and the program level."""
from django.utils import timezone

from apps.habits.models import Habit, HabitAssignment
from apps.nutrition.models import MealDayState, MealPlan, MealPlanAssignment, meals_on
from apps.nutrition.services import day_view, mark_eaten
from apps.training.models import Program


def _riya(trainer):
    return trainer.get("/api/v1/clients/", {"search": "riya"}).json()["results"][0]["id"]


def _current(trainer, rid):
    cur = trainer.get(f"/api/v1/clients/{rid}/meal-plans/").json()["current"]
    assert cur, "Riya has a meal plan in the demo data"
    return cur[0]


def _payload(meals):
    """The GET shape back as a PUT body (food / unit ids, quantities)."""
    return [{"id": m["id"], "name": m["name"], "time": m["time"], "kcal_target": m["kcal_target"],
             "options": [{"id": o["id"], "name": o["name"], "is_default": o["is_default"],
                          "items": [{"id": i["id"], "food": i["food"], "quantity": i["quantity"], "unit": i["unit"]}
                                    for i in o["items"]]} for o in m["options"]]} for m in meals]


def test_first_edit_makes_a_copy_and_leaves_the_master(trainer):
    rid = _riya(trainer)
    a = _current(trainer, rid)
    url = f"/api/v1/clients/{rid}/meal-plans/{a['id']}/meals/"
    d = trainer.get(url).json()
    assert d["custom"] is False and d["copy"] is None
    master = MealPlan.objects.get(id=a["plan"])
    before = [(m.id, m.name) for m in master.meals.all()]
    meals = _payload(d["meals"])
    meals[0]["name"] = "Early breakfast"
    item = meals[0]["options"][0]["items"][0]
    item["quantity"] = "2"
    r = trainer.put(url, {"weekday": 0, "every_day": True, "meals": meals}, format="json")
    assert r.status_code == 200, r.content
    d = r.json()
    assert d["custom"] is True and d["copy"]
    assert "Early breakfast" in [m["name"] for m in d["meals"]]
    assert all(m["weekday"] is None for m in d["meals"])
    # master untouched, copy hidden from the library
    assert [(m.id, m.name) for m in master.meals.all()] == before
    ids = [p["id"] for p in trainer.get("/api/v1/meal-plans/", {"page_size": 100}).json()["results"]]
    assert d["copy"] not in ids
    row = _current(trainer, rid)
    assert row["custom"] is True and row["plan"] == a["plan"]


def test_one_weekday_gets_its_own_meals(trainer):
    rid = _riya(trainer)
    a = _current(trainer, rid)
    url = f"/api/v1/clients/{rid}/meal-plans/{a['id']}/meals/"
    meals = _payload(trainer.get(url).json()["meals"])
    n = len(meals)
    tue = [dict(m, options=[dict(o) for o in m["options"]]) for m in meals[:-1]]  # drop the last meal on Tuesday
    tue[0]["name"] = "Tuesday breakfast"
    r = trainer.put(url, {"weekday": 1, "every_day": False, "meals": tue}, format="json")
    assert r.status_code == 200, r.content
    d = r.json()
    assert d["own_days"] == [1]
    copy = MealPlanAssignment.objects.get(id=a["id"]).followed
    assert meals_on(copy, 1).count() == n - 1
    assert meals_on(copy, 2).count() == n
    assert "Tuesday breakfast" in [m.name for m in meals_on(copy, 1)]
    assert "Tuesday breakfast" not in [m.name for m in meals_on(copy, 2)]
    # Apply to every day: Tuesday's meals become every day's, the other days' own meals go
    tue_meals = [m for m in d["meals"] if m["weekday"] == 1]
    r = trainer.put(url, {"weekday": 1, "every_day": True, "meals": _payload(tue_meals)}, format="json")
    assert r.status_code == 200, r.content
    d = r.json()
    assert d["own_days"] == []
    assert len(d["meals"]) == n - 1 and all(m["weekday"] is None for m in d["meals"])


def test_client_food_tab_follows_the_copy_and_keeps_todays_log(trainer):
    rid = _riya(trainer)
    a = _current(trainer, rid)
    ma = MealPlanAssignment.objects.select_related("plan", "client").get(id=a["id"])
    today = timezone.localdate()
    first = meals_on(ma.plan, today.weekday()).first()
    mark_eaten(ma.client, first, today)
    url = f"/api/v1/clients/{rid}/meal-plans/{a['id']}/meals/"
    meals = _payload(trainer.get(url).json()["meals"])
    meals[0]["name"] = "Renamed today"
    r = trainer.put(url, {"weekday": today.weekday(), "every_day": False, "meals": meals}, format="json")
    assert r.status_code == 200, r.content
    v = day_view(ma.client, today)
    names = [m["name"] for m in v["meals"]]
    assert "Renamed today" in names
    renamed = next(m for m in v["meals"] if m["name"] == "Renamed today")
    assert renamed["pill"] == "logged"  # the day state moved with the meal
    assert not MealDayState.objects.filter(client=ma.client, date=today, meal=first).exists()


def test_reset_to_master_drops_the_copy(trainer):
    rid = _riya(trainer)
    a = _current(trainer, rid)
    url = f"/api/v1/clients/{rid}/meal-plans/{a['id']}/meals/"
    meals = _payload(trainer.get(url).json()["meals"])
    trainer.put(url, {"weekday": 3, "every_day": False, "meals": meals[:1]}, format="json")
    copy = MealPlanAssignment.objects.get(id=a["id"]).custom_plan
    assert copy is not None
    r = trainer.post(f"/api/v1/clients/{rid}/meal-plans/{a['id']}/reset/")
    assert r.status_code == 200, r.content
    assert r.json()["custom"] is False
    assert MealPlanAssignment.objects.get(id=a["id"]).custom_plan is None
    assert trainer.get(url).json()["custom"] is False


def test_meal_day_needs_names_and_a_weekday(trainer):
    rid = _riya(trainer)
    a = _current(trainer, rid)
    url = f"/api/v1/clients/{rid}/meal-plans/{a['id']}/meals/"
    meals = _payload(trainer.get(url).json()["meals"])
    meals[0]["name"] = "  "
    assert trainer.put(url, {"weekday": 0, "meals": meals}, format="json").status_code == 400
    assert trainer.put(url, {"weekday": 9, "meals": meals[1:]}, format="json").status_code == 400
    assert MealPlanAssignment.objects.get(id=a["id"]).custom_plan is None


def test_habit_edit_for_one_client(trainer):
    rid = _riya(trainer)
    base = f"/api/v1/clients/{rid}/habit-plan/"
    ha = HabitAssignment.objects.filter(client_id=rid, active=True, habit__kind=Habit.Kind.COUNTER) \
        .select_related("habit").first()
    assert ha, "Riya has a counter habit in the demo data"
    lib_target = ha.habit.target
    r = trainer.patch(f"{base}{ha.id}/", {"target": lib_target + 5, "frequency": "days", "days": [0, 2, 4],
                                          "note": "Only on gym days"}, format="json")
    assert r.status_code == 200, r.content
    row = next(x for x in r.json()["current"] + r.json()["up_next"] if str(x["id"]) == str(ha.id))
    assert row["custom"] is True
    assert row["habit"]["target"] == lib_target + 5 and row["habit"]["days"] == [0, 2, 4]
    assert row["habit"]["why"] == "Only on gym days" and row["library"]["target"] == lib_target
    assert Habit.objects.get(id=ha.habit_id).target == lib_target  # library habit untouched
    # same as the library again = cleared
    r = trainer.patch(f"{base}{ha.id}/", {"target": lib_target, "frequency": "", "note": ""}, format="json")
    assert r.status_code == 200
    ha.refresh_from_db()
    assert ha.custom is False
    assert trainer.patch(f"{base}{ha.id}/", {"frequency": "times_week", "times_per_week": 9},
                         format="json").status_code == 400


def test_program_level_in_the_library(trainer):
    rows = trainer.get("/api/v1/programs/", {"page_size": 100}).json()["results"]
    assert rows and all("level" in p and "level_label" in p for p in rows)
    p = Program.objects.filter(is_master=True).first()
    assert p.level in ("beginner", "intermediate", "advanced", "any")
