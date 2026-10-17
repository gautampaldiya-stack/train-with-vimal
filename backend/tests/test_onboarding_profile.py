"""Onboarding = the gym's coaching form (D-36): the answers are kept on the client profile, the coach edits them in
Edit profile (PATCH clients/<id>/), and Overview → About / Forms → Onboarding questionnaire read them."""
from datetime import date

import pytest
from django.contrib.auth import get_user_model
from django.utils import timezone

from apps.accounts.models import AccountStatus, Role
from apps.checkins.models import Form, Measurement, PhotoSet, Question, WeightLog
from apps.clients.models import ClientProfile

from .conftest import login
from .test_onboarding import STEPS, photo, steps_with_photos

pytestmark = pytest.mark.django_db
User = get_user_model()
EMAIL = "form.client@example.com"


def make_client():
    aman = User.objects.get(email="aman@trainwithvimal.com")
    u = User.objects.create_user(email=EMAIL, password="Demo@1234", full_name="Meera Kapoor", role=Role.CLIENT,
                                 status=AccountStatus.ACTIVE, phone="+919811122233")
    ClientProfile.objects.create(user=u, trainer=aman, onboarding_done=["account"])
    return u


def fill(c, steps=None):
    for step, data in (steps or steps_with_photos()).items():
        r = c.post("/api/v1/me/onboarding/", {"step": step, "data": data}, format="json")
        assert r.status_code == 200, (step, r.json())
    return r.json()


def test_answers_are_saved_on_the_profile():
    u = make_client()
    c = login(EMAIL)
    d = fill(c)
    assert len(d["done"]) == 9
    u.refresh_from_db()
    cp = u.client_profile
    assert u.phone == "+919876501234" and u.date_of_birth == date(1997, 3, 14) and u.gender == "female"
    assert cp.goal == "fat_loss" and cp.goal_detail == "Wedding in March" and cp.experience == "beginner"
    assert cp.enrolled_for == "3" and float(cp.height_cm) == 162 and float(cp.start_weight_kg) == 78
    assert cp.workout_days == 5 and cp.workout_place == "gym" and cp.workout_time == "evening"
    assert cp.activity_level == "sedentary" and cp.injury_areas == ["knee"] and cp.conditions == ["none"]
    assert cp.diet_type == "veg" and cp.meal_dinner == "Khichdi" and cp.takes_medicines is False
    assert cp.terms_agreed_at is not None
    # Weight is the first weigh-in, the measurements the first Measurement, the photos the start set.
    today = timezone.localdate()
    assert float(WeightLog.objects.get(client=u, date=today).weight_kg) == 78
    m = Measurement.objects.get(client=u)
    assert m.values["neck"] == 32 and m.values["calf_r"] == 36 and len(m.values) == 11
    ps = PhotoSet.objects.get(client=u)
    assert ps.label == "Start photos" and {p.pose for p in ps.photos.all()} == {"front", "side", "back"}
    # GET gives the answers back by field key, and the photos already added.
    g = c.get("/api/v1/me/onboarding/").json()
    assert g["values"]["surgeries"] == "None" and g["values"]["measure_waist"] == 84
    assert set(g["photos"]) == {"front", "side", "back"} and g["terms"] and g["agree_text"]


def test_required_answers_terms_photos_and_phone():
    make_client()
    c = login(EMAIL)
    r = c.post("/api/v1/me/onboarding/", {"step": "agree", "data": {"terms": False}}, format="json")
    assert r.status_code == 400 and "terms" in r.json()["error"]["fields"]
    r = c.post("/api/v1/me/onboarding/", {"step": "body", "data": STEPS["body"]}, format="json")
    assert r.status_code == 400 and "photo_front" in r.json()["error"]["fields"]
    taken = {**STEPS["about"], "phone": "9820000000"}  # Riya's number
    r = c.post("/api/v1/me/onboarding/", {"step": "about", "data": taken}, format="json")
    assert r.status_code == 400 and "phone" in r.json()["error"]["fields"]
    r = c.post("/api/v1/me/onboarding/", {"step": "about", "data": {**STEPS["about"], "phone": "12345"}},
               format="json")
    assert r.status_code == 400 and "phone" in r.json()["error"]["fields"]
    meds = {**STEPS["supplements"], "takes_medicines": True}
    r = c.post("/api/v1/me/onboarding/", {"step": "supplements", "data": meds}, format="json")
    assert r.status_code == 400 and "medicines_detail" in r.json()["error"]["fields"]
    # A photo added once does not have to be sent again.
    p = photo()
    body = {**STEPS["body"], "photo_front": p, "photo_side": p, "photo_back": p}
    assert c.post("/api/v1/me/onboarding/", {"step": "body", "data": body}, format="json").status_code == 200
    r = c.post("/api/v1/me/onboarding/", {"step": "body", "data": {**STEPS["body"], "measure_neck": 33}},
               format="json")
    assert r.status_code == 200 and Measurement.objects.get(client__email=EMAIL).values["neck"] == 33


def test_form_questions_drive_the_steps_and_extra_answers_show_in_forms():
    u = make_client()
    form = Form.objects.get(name="New client questionnaire")
    surgeries = form.questions.get(profile_key="surgeries")
    surgeries.is_removed = True
    surgeries.save()
    q = Question.objects.create(form=form, order=200, text="How did you hear about us?", type="short",
                                required=True)
    try:
        c = login(EMAIL)
        g = c.get("/api/v1/me/onboarding/").json()
        keys = [f["key"] for f in g["fields"]]
        assert "surgeries" not in keys and "past_injuries" in keys
        assert [x["text"] for x in g["extra"]] == ["How did you hear about us?"]
        health = {k: v for k, v in STEPS["health"].items() if k != "surgeries"}
        steps = {**steps_with_photos(), "health": health}
        r = c.post("/api/v1/me/onboarding/", {"step": "agree", "data": {"terms": True}}, format="json")
        assert r.status_code == 400 and f"q{q.id}" in r.json()["error"]["fields"]
        steps["agree"] = {"terms": True, "extra": {str(q.id): "Instagram"}}
        fill(c, steps)
        rows = login("aman@trainwithvimal.com").get(f"/api/v1/clients/{u.id}/forms/").json()["sent"]
        onb = next(r for r in rows if r["key"] == "onboarding")
        assert onb["status"] == "done"
        answers = {x["q"]: x["a"] for s in onb["sections"] for x in s["rows"]}
        assert answers["How did you hear about us?"] == "Instagram"
        assert "Any surgeries?" not in answers and answers["What injuries have you had in the past?"] == "None"
        assert answers["Contact number"] == "+91 98765 01234"
    finally:
        surgeries.is_removed = False
        surgeries.save()
        q.delete()


def test_trainer_edits_onboarding_fields_in_edit_profile(django_capture_on_commit_callbacks):
    u = make_client()
    fill(login(EMAIL))
    t = login("aman@trainwithvimal.com")
    with django_capture_on_commit_callbacks(execute=True):
        r = t.patch(f"/api/v1/clients/{u.id}/", {
            "goal": "muscle_gain", "diet_type": "non_veg", "workout_days": 6, "workout_time": "Before office, 6 am",
            "activity_level": "moderate", "conditions": ["thyroid"], "takes_medicines": True,
            "medicines_detail": "Thyronorm 50 mcg for 2 years", "surgeries": "Appendix removed in 2018",
            "experience": "intermediate", "meal_lunch": "Rice, dal, chicken"}, format="json")
    assert r.status_code == 200, r.json()
    p = r.json()["profile"]
    assert p["diet_type"] == "non_veg" and p["workout_days"] == 6 and p["conditions"] == ["thyroid"]
    assert p["medicines_detail"].startswith("Thyronorm") and r.json()["options"]["activity_level"]
    cp = ClientProfile.objects.get(user=u)
    assert cp.surgeries == "Appendix removed in 2018" and cp.meal_lunch == "Rice, dal, chicken"
    # Goal changes still leave their line in History.
    from apps.activity.models import ActivityEvent

    assert ActivityEvent.objects.filter(client=u, verb="changed goal").exists()
    bad = t.patch(f"/api/v1/clients/{u.id}/", {"activity_level": "lazy", "workout_days": 9}, format="json")
    assert bad.status_code == 400
    assert {"activity_level", "workout_days"} <= set(bad.json()["error"]["fields"])


def test_overview_about_reads_the_profile():
    u = make_client()
    t = login("aman@trainwithvimal.com")
    items = {x["key"]: x for x in t.get(f"/api/v1/clients/{u.id}/overview/").json()["about"]["items"]}
    assert items["age"]["value"] == "—" and items["diet"]["value"] == "—"  # nothing filled yet
    fill(login(EMAIL))
    items = {x["key"]: x for x in t.get(f"/api/v1/clients/{u.id}/overview/").json()["about"]["items"]}
    today = timezone.localdate()
    age = today.year - 1997 - ((today.month, today.day) < (3, 14))
    assert items["age"]["value"] == str(age) and items["gender"]["value"] == "Female"
    assert items["height"]["value"] == "162 cm" and items["start_weight"]["value"] == "78.0 kg"
    assert items["diet"]["value"] == "Veg, no egg" and items["trains_at"]["value"] == "Gym · 5 days a week"
    assert items["experience"]["value"] == "0 – 6 months" and items["activity"]["value"] == "Sedentary"
    assert items["workout_time"]["value"] == "Evening" and items["enrolled_for"]["value"] == "3 months"
    assert items["injuries"]["value"] == "Right knee hurts on deep squats" and items["injuries"]["warn"]


def test_demo_clients_have_a_full_about():
    t = login("aman@trainwithvimal.com")
    for email in ("riya@example.com", "aditya@example.com"):
        u = User.objects.get(email=email)
        items = t.get(f"/api/v1/clients/{u.id}/overview/").json()["about"]["items"]
        assert all(x["value"] != "—" for x in items), (email, items)
        assert len(u.client_profile.client_steps_done) == 9
