"""Client profile → Plans tab: the 4 slots for one client (current / up next / history, assign, end)."""
from datetime import timedelta

from django.utils import timezone

from apps.habits.models import Habit, HabitAssignment, SupplementAssignment, SupplementPlan
from apps.nutrition.models import MealPlan, MealPlanAssignment
from apps.nutrition.services import roll_meal_plans
from apps.training.models import ProgramAssignment


def _riya(trainer):
    return trainer.get("/api/v1/clients/", {"search": "riya"}).json()["results"][0]["id"]


def test_workout_rows_carry_master_week_and_who_set_it(trainer):
    rid = _riya(trainer)
    d = trainer.get(f"/api/v1/clients/{rid}/programs/").json()
    assert set(d) == {"current", "up_next", "history"}
    for a in d["current"]:
        for k in ("master_name", "days_per_week", "assigned_by", "week"):
            assert k in a
        assert 1 <= a["week"] <= a["weeks"]


def test_up_next_workout_is_removed_not_ended(trainer):
    rid = _riya(trainer)
    cur = trainer.get(f"/api/v1/clients/{rid}/programs/").json()["current"]
    assert cur, "Riya has a workout plan in the demo data"
    r = trainer.post(f"/api/v1/clients/{rid}/programs/", {"program": cur[0]["program"], "when": "after_current"},
                     format="json")
    assert r.status_code == 201, r.content
    assert r.json()["status"] == "up_next"
    r = trainer.post(f"/api/v1/clients/{rid}/programs/{r.json()['id']}/end/")
    assert r.status_code == 204
    assert not ProgramAssignment.objects.filter(client_id=rid, status="up_next").exists()


def test_meal_plan_assign_now_later_end_and_roll(trainer):
    rid = _riya(trainer)
    plan = MealPlan.objects.first()
    base = f"/api/v1/clients/{rid}/meal-plans/"
    r = trainer.post(base, {"plan": str(plan.id)}, format="json")
    assert r.status_code == 201, r.content
    d = trainer.get(base).json()
    assert [a["plan"] for a in d["current"]] == [str(plan.id)]
    later = timezone.localdate() + timedelta(days=5)
    r = trainer.post(base, {"plan": str(plan.id), "start_date": later.isoformat(), "notify": False}, format="json")
    assert r.json()["status"] == "up_next"
    assert len(trainer.get(base).json()["up_next"]) == 1
    assert roll_meal_plans(today=later) == 1
    assert MealPlanAssignment.objects.filter(client_id=rid, status="active").count() == 1
    cur = trainer.get(base).json()["current"][0]
    r = trainer.post(f"{base}{cur['id']}/end/")
    assert r.status_code == 200 and r.json()["status"] == "ended"
    assert trainer.get(base).json()["current"] == []


def test_supplements_next_to_current_or_replace(trainer):
    rid = _riya(trainer)
    base = f"/api/v1/clients/{rid}/supplement-plans/"
    plans = list(SupplementPlan.objects.all()[:2])
    assert len(plans) == 2
    trainer.post(base, {"plan": str(plans[0].id), "when": "now"}, format="json")
    r = trainer.post(base, {"plan": str(plans[1].id), "when": "next"}, format="json")
    assert r.status_code == 201, r.content
    assert {a["plan"] for a in r.json()["current"]} >= {str(plans[0].id), str(plans[1].id)}
    r = trainer.post(base, {"plan": str(plans[0].id), "when": "now"}, format="json")
    assert [a["plan"] for a in r.json()["current"]] == [str(plans[0].id)]
    assert SupplementAssignment.objects.get(client_id=rid, plan=plans[1]).active is False


def test_habits_assign_later_and_end(trainer):
    rid = _riya(trainer)
    base = f"/api/v1/clients/{rid}/habit-plan/"
    h = Habit.objects.exclude(assignments__client_id=rid, assignments__active=True).first()
    later = timezone.localdate() + timedelta(days=3)
    r = trainer.post(base, {"habits": [str(h.id)], "when": "date", "start_date": later.isoformat()}, format="json")
    assert r.status_code == 201, r.content
    row = next(a for a in r.json()["up_next"] if a["habit"]["id"] == str(h.id))
    r = trainer.post(f"{base}{row['id']}/end/")  # not started yet: gone, not in history
    assert r.status_code == 200
    assert not HabitAssignment.objects.filter(client_id=rid, habit=h).exists()
    bad = trainer.post(base, {"habits": [], "when": "next"}, format="json")
    assert bad.status_code == 400


def test_other_trainers_clients_are_hidden(trainer):
    from apps.clients.models import ClientProfile

    other = ClientProfile.objects.exclude(trainer__email="aman@trainwithvimal.com").first()
    if other is None:
        return
    for slot in ("meal-plans", "supplement-plans", "habit-plan"):
        assert trainer.get(f"/api/v1/clients/{other.user_id}/{slot}/").status_code == 404
