import base64
from io import BytesIO

import pytest
from django.contrib.auth import get_user_model

from apps.accounts.models import AccountStatus, Role
from apps.clients.models import ClientProfile

from .conftest import login

pytestmark = pytest.mark.django_db


def photo():
    from PIL import Image

    buf = BytesIO()
    Image.new("RGB", (8, 8), (200, 210, 240)).save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


# The gym's coaching form in its 9 steps (D-36).
STEPS = {
    "goal": {"goal": "fat_loss", "goal_detail": "Wedding in March", "experience": "beginner"},
    "about": {"enrolled_for": "3", "phone": "9876501234", "date_of_birth": "1997-03-14", "gender": "female",
              "weight_kg": 78, "height_cm": 162, "target_weight_kg": 68},
    "training": {"workout_days": 5, "workout_place": "gym", "workout_time": "evening",
                 "current_exercise": "Not performing", "activity_level": "sedentary"},
    "health": {"injury_areas": ["knee"], "health_notes": "Right knee hurts on deep squats", "conditions": ["none"],
               "past_injuries": "None", "surgeries": "None", "addictions": "None", "digestive_issues": "None",
               "stresses": "Work, sleep, travel"},
    "food": {"diet_type": "veg", "common_foods": "Roti, dal, rice", "food_allergies": "no", "smoking": "no"},
    "meals": {"meal_breakfast": "Poha", "meal_mid_morning": "Fruit", "meal_lunch": "Roti, dal",
              "meal_pre_workout": "Banana", "meal_post_workout": "Milk", "meal_evening": "Tea",
              "meal_dinner": "Khichdi"},
    "supplements": {"takes_supplements": False, "open_to_supplements": "yes", "takes_medicines": False},
    "body": {"measure_neck": 32, "measure_bicep_l": 29, "measure_bicep_r": 29.5, "measure_chest": 92,
             "measure_abdomen": 90, "measure_waist": 84, "measure_hips": 102, "measure_thigh_l": 58,
             "measure_thigh_r": 58, "measure_calf_l": 36, "measure_calf_r": 36},
    "agree": {"terms": True},
}


def new_client(email="new.onb@example.com"):
    User = get_user_model()
    trainer = User.objects.filter(role=Role.TRAINER, status=AccountStatus.ACTIVE).first()
    u = User.objects.create_user(email=email, password="Demo@1234", full_name="New Onb",
                                 role=Role.CLIENT, status=AccountStatus.ACTIVE)
    ClientProfile.objects.create(user=u, trainer=trainer, onboarding_done=["account"])
    return u


def steps_with_photos():
    p = photo()
    return {**STEPS, "body": {**STEPS["body"], "photo_front": p, "photo_side": p, "photo_back": p}}


def test_client_steps_fill_staff_checklist():
    new_client()
    c = login("new.onb@example.com")
    r = c.get("/api/v1/me/onboarding/")
    assert r.json()["done"] == [] and r.json()["steps"] == list(STEPS)
    for i, (step, data) in enumerate(steps_with_photos().items()):
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
    r = c.post("/api/v1/me/onboarding/", {"step": "training", "data": {"workout_days": 9, "workout_place": "gym"}},
               format="json")
    assert r.status_code == 400
    f = r.json()["error"]["fields"]
    assert "workout_days" in f and "workout_time" in f and "activity_level" in f


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
    body = {**STEPS["health"], "injury_areas": ["none"], "conditions": ["heart"], "doctor_ok": False}
    r = c.post("/api/v1/me/onboarding/", {"step": "health", "data": body}, format="json")
    assert r.status_code == 400 and "doctor_ok" in r.json()["error"]["fields"]
    r = c.post("/api/v1/me/onboarding/", {"step": "health", "data": {**body, "doctor_ok": True}}, format="json")
    assert r.status_code == 200
