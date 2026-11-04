"""Water reminder (Probid 2026-11-04: "har baar same water 1L remind karta hai"): the goal is the one the Water card
shows (the coach's water-habit target), the text says what was drunk out of it, so it changes as the day goes on,
and no water habit means no reminder."""
from datetime import datetime, timedelta

import pytest
from django.utils import timezone

from apps.accounts.models import User
from apps.habits.models import Habit, HabitAssignment
from apps.nutrition.models import WaterLog
from apps.notifications import reminders


@pytest.fixture
def riya(db):
    return User.objects.get(email="riya@example.com")


def _at(monkeypatch, hour):
    now = timezone.make_aware(datetime.combine(timezone.localdate(), datetime.min.time().replace(hour=hour)))
    monkeypatch.setattr(reminders, "_local_now", lambda: now)


def _sent(monkeypatch):
    out = []
    monkeypatch.setattr(reminders, "notify", lambda u, ev, title, body="", **k: out.append((u.email, body, (k.get("data") or {}).get("route"))))
    return out


def _water(riya, target, unit):
    HabitAssignment.objects.filter(client=riya, habit__icon="water").delete()
    h = Habit.objects.create(name="Drink water", kind=Habit.Kind.COUNTER, target=target, unit=unit, icon="water")
    HabitAssignment.objects.create(habit=h, client=riya, start_date=timezone.localdate(), active=True)


def _log(riya, ml, minutes_ago):
    WaterLog.objects.update_or_create(client=riya, date=timezone.localdate(), defaults={"ml": ml})
    WaterLog.objects.filter(client=riya, date=timezone.localdate()).update(
        updated_at=reminders._local_now() - timedelta(minutes=minutes_ago))


def test_nothing_logged_says_so(riya, monkeypatch):
    _water(riya, 12, "glasses")  # 3 L
    WaterLog.objects.filter(client=riya, date=timezone.localdate()).delete()
    sent = _sent(monkeypatch)
    _at(monkeypatch, 12)  # pace 3 L × 5/15 = 1 L
    reminders.water_reminders()
    assert [b for e, b, _ in sent if e == riya.email] == ["No water logged yet today. Aim for 1 L by now."]
    assert [r for e, _, r in sent if e == riya.email] == ["/food?water=1"]


def test_uses_the_water_card_goal_and_says_what_was_drunk(riya, monkeypatch):
    _water(riya, 16, "glasses")  # 4 L, not the meal plan's water
    sent = _sent(monkeypatch)
    _at(monkeypatch, 12)  # pace 4 L × 5/15 = 1.33 L → 1.25 L
    _log(riya, 500, 120)
    reminders.water_reminders()
    assert [b for e, b, _ in sent if e == riya.email] == ["You've had 500 ml of 4 L today. Aim for 1.25 L by now."]

    sent.clear()
    _at(monkeypatch, 16)  # pace 2.4 L → 2.5 L
    _log(riya, 1000, 90)
    reminders.water_reminders()
    assert [b for e, b, _ in sent if e == riya.email] == ["You've had 1 L of 4 L today. Aim for 2.5 L by now."]


def test_no_reminder_right_after_logging(riya, monkeypatch):
    _water(riya, 12, "glasses")
    sent = _sent(monkeypatch)
    _at(monkeypatch, 14)
    _log(riya, 250, 20)
    reminders.water_reminders()
    assert not [1 for e, _, _ in sent if e == riya.email]


def test_no_water_habit_no_reminder(riya, monkeypatch):
    HabitAssignment.objects.filter(client=riya, habit__icon="water").delete()
    sent = _sent(monkeypatch)
    _at(monkeypatch, 14)
    reminders.water_reminders()
    assert not [1 for e, _, _ in sent if e == riya.email]
