"""X1 / X2 (Probid 2026-11-04): a setup questionnaire that is not finished must show on Check-ins and Home, also
with 0 answers after "Finish later", and the reminder the client picked must reach a client waiting for approval."""
from datetime import timedelta

from django.utils import timezone

from apps.accounts.models import User
from tests.conftest import login


def _fresh(email="isha@example.com"):
    u = User.objects.get(email=email)
    cp = u.client_profile
    cp.onboarding = {}
    cp.onboarding_skipped_at = None
    cp.save()
    return u


def test_unfinished_setup_shows_on_checkins_and_home_even_with_nothing_answered(db):
    u = _fresh()
    c = login(u.email)
    r = c.delete("/api/v1/me/onboarding/", {"remind": "tomorrow"}, format="json")  # Finish and leave, 0 answered
    assert r.status_code == 200, r.content
    ob = c.get("/api/v1/me/checkins/").json()["onboarding"]
    assert ob and ob["filled"] < ob["total"] and ob["later"] is True  # name / phone from sign-up may count
    home = c.get("/api/v1/me/home/").json()
    assert home["checkin_today"]["onboarding"]["total"] == ob["total"]


def test_picked_reminder_reaches_a_client_waiting_for_approval(db, monkeypatch):
    from apps.notifications import reminders
    from apps.notifications.models import ReminderLog  # noqa: F401 (models loaded)

    u = _fresh()
    c = login(u.email)
    r = c.delete("/api/v1/me/onboarding/", {"remind": "tomorrow"}, format="json")
    at = r.json()["remind"]["at"]
    User.objects.filter(id=u.id).update(status="pending")
    sent = []
    monkeypatch.setattr(reminders, "send_template", lambda user, key, **kw: sent.append((user.id, key, kw.get("data"))))
    from datetime import datetime

    monkeypatch.setattr(reminders, "_local_now", lambda: datetime.fromisoformat(at) + timedelta(minutes=5))
    assert reminders.onboarding_reminders() >= 1
    assert (u.id, "onboarding-form-reminder", {"route": "/setup"}) in sent
    u.refresh_from_db()
    assert u.client_profile.onboarding["_remind"]["sent"] is True
    assert datetime.fromisoformat(at).tzinfo is not None and timezone.is_aware(datetime.fromisoformat(at))


def test_approved_client_who_never_opened_setup_sees_onboarding(db):
    """Probid 2026-11-04: a new client approved before filling anything must see Onboarding on Home and
    Check-ins (nothing showed: neither page had an onboarding card)."""
    u = _fresh()
    User.objects.filter(id=u.id).update(status="active")
    c = login(u.email)
    assert c.get("/api/v1/me/checkins/").json()["onboarding"]["complete"] is False
    row = c.get("/api/v1/me/home/").json()["checkin_today"]["onboarding"]
    assert row is not None and row["total"] > 0
