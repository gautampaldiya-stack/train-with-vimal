"""Adherence and the other "meals a day" numbers count the plan the client follows — their own copy (Edit for X),
with a weekday's own meals — not the master plan."""
from datetime import timedelta

from django.contrib.auth import get_user_model
from django.utils import timezone

from apps.clients import metrics
from apps.nutrition.models import Meal, MealDayState, MealPlan, MealPlanAssignment
from apps.nutrition.services import client_copy


def _assignment(client, plan, start):
    return MealPlanAssignment.objects.create(client=client, plan=plan, start_date=start, status="active")


def test_client_copy_changes_the_adherence_denominator(db):
    User = get_user_model()
    riya = User.objects.get(email="riya@example.com")
    master = MealPlanAssignment.objects.filter(client=riya, status="active").first().plan
    n_master = master.meals.count()
    assert n_master >= 3
    # A fresh client with no other plans or logs, on Riya's master plan for the last week.
    who = User.objects.create_user(email="copy-adh@example.com", password="x", full_name="Copy Adh")
    end = timezone.localdate() - timedelta(days=1)
    start = end - timedelta(days=6)
    a = _assignment(who, master, start)
    a = metrics.active_meal_plan(who, end)
    assert metrics.planned_meals(a, start, end) == 7 * n_master

    # One meal logged every day of the week.
    first = master.meals.order_by("time").first()
    for i in range(7):
        MealDayState.objects.create(client=who, date=start + timedelta(days=i), meal=first, status="logged")
    assert metrics.adherence(who, end=end) == round(100 * 7 / (7 * n_master))

    # Edit for Copy: their copy keeps only two every-day meals, and Mondays get just one meal.
    copy, _ = client_copy(a, actor=None)
    keep = list(copy.meals.order_by("time")[:2])
    Meal.objects.filter(plan=copy).exclude(id__in=[m.id for m in keep]).delete()
    Meal.objects.create(plan=copy, name="Monday brunch", time=keep[0].time, weekday=0)
    a = metrics.active_meal_plan(who, end)
    assert a.followed == copy and master.meals.count() == n_master  # the master is untouched
    planned = 6 * 2 + 1  # seven days: one Monday with its own meal, six days with the two every-day meals
    assert metrics.planned_meals(a, start, end) == planned
    assert metrics.meals_per_day(a, start + timedelta(days=(0 - start.weekday()) % 7)) == 1
    logged = MealDayState.objects.filter(client=who, date__range=(start, end), status="logged").count()
    assert metrics.adherence(who, end=end) == round(100 * min(logged, planned) / planned)
    assert metrics.adherence(who, end=end) != round(100 * 7 / (7 * n_master))
    grid = metrics.last_7_days(who, end=end)
    assert all(c["meals"] in ("done", "partial", "missed", "rest") for c in grid)


def test_completed_onboarding_form_carries_the_start_photos(trainer):
    """Forms → Onboarding questionnaire: a completed form lists the start photos (front / side / back)."""
    rid = trainer.get("/api/v1/clients/", {"search": "riya"}).json()["results"][0]["id"]
    row = next(r for r in trainer.get(f"/api/v1/clients/{rid}/forms/").json()["sent"] if r["key"] == "onboarding")
    assert row["status"] == "done"
    assert [p["pose"] for p in row["photos"]] == ["front", "side", "back"]
    assert all(p["url"].startswith("http") for p in row["photos"])
