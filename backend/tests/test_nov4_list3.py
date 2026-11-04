"""Probid 2026-11-04 (list 3): logs only from the day the client was active, Copy yesterday only with something
to copy, client deletes own food (Undo, logs stay), plan builder sees a deleted food, Habits / Coming up cards."""
from datetime import timedelta
from decimal import Decimal

from django.utils import timezone

from apps.accounts.models import User
from tests.conftest import login


def test_logs_start_on_the_day_a_sign_up_was_approved(admin):
    from apps.clients.logs import client_start
    from apps.clients.models import Approval

    u = User.objects.get(email="riya@example.com")
    before = client_start(u)
    approved = timezone.now() - timedelta(days=2)
    Approval.objects.create(client=u, status=Approval.Status.APPROVED, decided_at=approved)
    assert client_start(u) == max(before, timezone.localtime(approved).date())
    r = admin.get(f"/api/v1/clients/{u.id}/checkins/?kind=daily&range=30days")
    assert r.status_code == 200, r.content
    rows = r.json()["results"]
    assert rows and all(str(x["date"]) >= str(timezone.localtime(approved).date()) for x in rows)


def test_copy_yesterday_needs_something_logged(client_user):
    from apps.nutrition.models import FoodLogEntry

    riya = User.objects.get(email="riya@example.com")
    y = timezone.localdate() - timedelta(days=1)
    FoodLogEntry.objects.filter(client=riya, date=y).delete()
    assert client_user.get("/api/v1/me/food/").json()["yesterday_logged"] == 0
    FoodLogEntry.objects.create(client=riya, date=y, meal_name="Snack", name="Apple", kcal=Decimal("52"))
    assert client_user.get("/api/v1/me/food/").json()["yesterday_logged"] == 1


def test_client_deletes_own_food_and_undo(client_user):
    from apps.nutrition.models import Food, FoodLogEntry

    r = client_user.post("/api/v1/me/foods/", {"name": "Mom's poha", "serving": "1 plate", "kcal": 250, "protein": 6,
                                               "carbs": 40, "fat": 7}, format="json")
    assert r.status_code == 201, r.content
    fid = r.json()["id"]
    riya = User.objects.get(email="riya@example.com")
    FoodLogEntry.objects.create(client=riya, date=timezone.localdate(), meal_name="Snack", food_id=fid,
                                name="Mom's poha", kcal=Decimal("250"))
    assert client_user.delete(f"/api/v1/me/foods/{fid}/").status_code == 204
    mine = client_user.get("/api/v1/me/foods/?group=mine").json()
    assert fid not in [f["id"] for f in mine.get("results", mine)]
    assert FoodLogEntry.objects.filter(food_id=fid, name="Mom's poha").exists()  # the day keeps it
    assert client_user.post(f"/api/v1/me/foods/{fid}/restore/").status_code == 200
    assert Food.objects.filter(id=fid).exists()
    # a team food can't be deleted by a client
    team = Food.objects.filter(owner_client__isnull=True).first()
    assert client_user.delete(f"/api/v1/me/foods/{team.id}/").status_code == 404


def test_plan_builder_marks_a_deleted_food(admin):
    from apps.nutrition.models import MealItem

    it = MealItem.objects.select_related("food", "option__meal__plan").first()
    it.food.soft_delete()
    plan = it.option.meal.plan
    d = admin.get(f"/api/v1/meal-plans/{plan.id}/").json()
    items = [x for m in d.get("meals", []) for o in m.get("options", []) for x in o.get("items", [])]
    assert any(x["id"] == it.id and x["food_deleted"] for x in items)


def test_habits_and_coming_up_are_home_cards(client_user):
    d = client_user.get("/api/v1/me/home/").json()
    assert {"habits", "coming", "supps"} <= set(d["layout"])


def test_progress_adherence_is_empty_without_a_plan(db):
    from apps.checkins.progress import _adherence
    from apps.habits.models import HabitAssignment
    from apps.nutrition.models import MealPlanAssignment
    from apps.training.models import ProgramAssignment

    u = User.objects.get(email="riya@example.com")
    ProgramAssignment.objects.filter(client=u).delete()
    MealPlanAssignment.objects.filter(client=u).delete()
    HabitAssignment.objects.filter(client=u).delete()
    a = _adherence(u, timezone.localdate())
    assert a["weeks"] == [] and a["overall"] is None and a["plan_since"] is None
