"""Weekly adherence (Probid 2026-11-03): planned workouts, meals, daily check-ins and habits against what was done.
Today counts only what is already due or done."""
from datetime import datetime, time, timedelta

from django.contrib.auth import get_user_model
from django.utils import timezone

from apps.clients.metrics import plan_adherence
from apps.habits.models import Habit, HabitAssignment, HabitLog
from apps.nutrition.models import MealDayState, MealPlanAssignment


def test_meals_and_habits_today_only_when_due(db):
    User = get_user_model()
    riya = User.objects.get(email="riya@example.com")
    master = MealPlanAssignment.objects.filter(client=riya, status="active").first().plan
    who = User.objects.create_user(email="adh-rule@example.com", password="x", full_name="Adh Rule")
    today = timezone.localdate()
    MealPlanAssignment.objects.create(client=who, plan=master, start_date=today - timedelta(days=1), status="active")
    meals = list(master.meals.filter(weekday__isnull=True).order_by("time"))
    n = len(meals)
    first = meals[0]
    tick = Habit.objects.create(name="Stretch", kind=Habit.Kind.TICK)
    HabitAssignment.objects.create(habit=tick, client=who, start_date=today - timedelta(days=1))
    HabitLog.objects.create(habit=tick, client=who, date=today - timedelta(days=1), done=True)

    # Just before the first meal's time: yesterday's meals all count (none logged), today's none yet.
    tz = timezone.get_current_timezone()
    early = datetime.combine(today, time(0, 0), tzinfo=tz)
    if first.time > time(0, 0):
        a = plan_adherence(who, today - timedelta(days=1), today, now=early)
        meals_part = next(p for p in a["parts"] if p["key"] == "meals")
        assert (meals_part["done"], meals_part["planned"]) == (0, n)
        habits = next(p for p in a["parts"] if p["key"] == "habits")
        assert (habits["done"], habits["planned"]) == (1, 1)  # today's not done yet: not counted

    # Today's first meal logged early: it counts at once, done and planned.
    MealDayState.objects.create(client=who, date=today, meal=first, status="logged")
    a = plan_adherence(who, today - timedelta(days=1), today, now=early)
    meals_part = next(p for p in a["parts"] if p["key"] == "meals")
    assert (meals_part["done"], meals_part["planned"]) == (1, n + 1)

    # End of the day: every meal of today is due.
    late = datetime.combine(today, time(23, 59), tzinfo=tz)
    a = plan_adherence(who, today - timedelta(days=1), today, now=late)
    meals_part = next(p for p in a["parts"] if p["key"] == "meals")
    assert (meals_part["done"], meals_part["planned"]) == (1, 2 * n)
    assert a["pct"] == round(100 * a["done"] / a["planned"])
    assert {p["key"] for p in a["parts"]} <= {"workouts", "meals", "checkins", "habits"}


def test_nothing_planned_is_none(db):
    who = get_user_model().objects.create_user(email="adh-none@example.com", password="x", full_name="Adh None")
    today = timezone.localdate()
    a = plan_adherence(who, today - timedelta(days=6), today)
    # a new client: no plan, no habits; the check-in counts only from the day they joined (today, not sent yet)
    assert a["pct"] is None and a["parts"] == []
