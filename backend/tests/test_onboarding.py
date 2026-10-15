import pytest
from django.contrib.auth import get_user_model

from apps.accounts.models import AccountStatus, Role
from apps.clients.models import ClientProfile

from .conftest import login

pytestmark = pytest.mark.django_db

STEPS = {
    "goal": {"goal": "fat_loss", "level": "beginner"},
    "about": {"age": 29, "height_cm": 162, "weight_kg": 78, "target_weight_kg": 68, "place": "gym"},
    "schedule": {"days": ["mon", "tue", "thu"], "session_min": 45, "wake_time": "06:30"},
    "health": {"injuries": ["knee"], "conditions": ["none"], "activity": "desk", "notes": "Right knee hurts on deep squats"},
    "food": {"diet": "veg", "meals_per_day": 5, "avoid": ["eggs"]},
}


def new_client():
    User = get_user_model()
    trainer = User.objects.filter(role=Role.TRAINER, status=AccountStatus.ACTIVE).first()
    u = User.objects.create_user(email="new.onb@example.com", password="Demo@1234", full_name="New Onb",
                                 role=Role.CLIENT, status=AccountStatus.ACTIVE)
    ClientProfile.objects.create(user=u, trainer=trainer, onboarding_done=["account"])
    return u


def test_client_steps_fill_staff_checklist():
    new_client()
    c = login("new.onb@example.com")
    r = c.get("/api/v1/me/onboarding/")
    assert r.json()["done"] == [] and r.json()["steps"] == list(STEPS)
    for i, (step, data) in enumerate(STEPS.items()):
        r = c.post("/api/v1/me/onboarding/", {"step": step, "data": data}, format="json")
        assert r.status_code == 200, r.json()
        assert len(r.json()["done"]) == i + 1
    assert r.json()["progress"]["done"] == 5
    cp = ClientProfile.objects.get(user__email="new.onb@example.com")
    assert cp.goal == "fat_loss" and float(cp.target_weight_kg) == 68
    assert "knee" in cp.health_notes.lower()


def test_step_validation():
    new_client()
    c = login("new.onb@example.com")
    r = c.post("/api/v1/me/onboarding/", {"step": "schedule", "data": {"days": ["mon"], "session_min": 45}},
               format="json")
    assert r.status_code == 400
    assert "days" in str(r.json()["error"]["fields"])


def test_save_and_leave_reminder():
    new_client()
    c = login("new.onb@example.com")
    r = c.delete("/api/v1/me/onboarding/", {"remind": "tonight"}, format="json")
    assert r.status_code == 200 and r.json()["remind"]["at"]
    r = c.delete("/api/v1/me/onboarding/", {"remind": "never"}, format="json")
    assert r.status_code == 400


def test_heart_condition_needs_doctor_ok():
    new_client()
    c = login("new.onb@example.com")
    body = {"injuries": ["none"], "conditions": ["heart"], "activity": "desk", "doctor_ok": False}
    r = c.post("/api/v1/me/onboarding/", {"step": "health", "data": body}, format="json")
    assert r.status_code == 400 and "doctor_ok" in str(r.json()["error"]["fields"])
    r = c.post("/api/v1/me/onboarding/", {"step": "health", "data": {**body, "doctor_ok": True}}, format="json")
    assert r.status_code == 200
