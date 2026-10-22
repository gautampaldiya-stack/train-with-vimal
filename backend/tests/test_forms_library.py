"""Admin → Forms & check-ins and the Form builder (boards Forms / FormBuilder, D-50)."""
from apps.checkins.models import Form


def _form(name):
    return Form.objects.get(name=name, client__isnull=True)


def test_list_says_how_each_form_is_sent(admin):
    rows = {r["name"]: r for r in admin.get("/api/v1/forms/").json()["results"]}
    assert rows["New client questionnaire"]["built_in"] == "Client setup · asked at sign-up"
    assert rows["New client questionnaire"]["question_count"] == 57
    assert rows["Weekly check-in"]["built_in"].startswith("Client app · every week")
    assert rows["Morning check-in"]["built_in"] == "Client app · every day"
    # PAR-Q stays a form in the list; it is sent from Forms, not asked at sign-up
    assert rows["PAR-Q health screening"]["built_in"] == ""
    assert rows["Monthly feedback"]["has_draft"] is False


def test_published_form_edits_wait_for_publish(admin):
    f = _form("Monthly feedback")
    d = admin.get(f"/api/v1/forms/{f.id}/").json()
    assert set(d["stats"]) == {"sent", "answered", "rate", "latest"}
    qs = d["questions"]
    new = qs + [{"text": "Rate the app", "type": "scale", "required": False}]
    r = admin.put(f"/api/v1/forms/{f.id}/questions/", {"questions": new}, format="json")
    assert r.status_code == 200, r.content
    assert r.json()["has_draft"] and len(r.json()["questions"]) == 4
    # clients still get the live 3 questions
    assert f.questions.filter(is_removed=False).count() == 3
    r = admin.post(f"/api/v1/forms/{f.id}/publish/")
    assert r.status_code == 200 and r.json()["has_draft"] is False
    assert f.questions.filter(is_removed=False).count() == 4


def test_move_back_to_draft_and_undo(admin):
    f = _form("Liability waiver")
    r = admin.post(f"/api/v1/forms/{f.id}/draft/").json()
    assert r["has_draft"] and r["status"] == "published"
    r = admin.post(f"/api/v1/forms/{f.id}/discard/").json()
    assert r["has_draft"] is False


def test_draft_form_saves_straight_away(admin):
    r = admin.post("/api/v1/forms/", {"name": "Bridal shred intake", "type": "onboarding", "start": "blank"},
                   format="json")
    fid = r.json()["id"]
    q = [{"text": "Wedding date", "type": "short", "required": True}]
    assert admin.put(f"/api/v1/forms/{fid}/questions/", {"questions": q}, format="json").json()["has_draft"] is False
    assert Form.objects.get(id=fid).questions.count() == 1


def test_profile_question_keeps_its_answer_type(admin):
    f = _form("New client questionnaire")
    qs = admin.get(f"/api/v1/forms/{f.id}/").json()["questions"]
    keyed = next(q for q in qs if q["profile_key"] == "surgeries")
    keyed.update(type="short", text="Any surgery in the past?")
    admin.put(f"/api/v1/forms/{f.id}/questions/", {"questions": qs}, format="json")
    admin.post(f"/api/v1/forms/{f.id}/publish/")
    q = f.questions.get(profile_key="surgeries")
    assert q.text == "Any surgery in the past?" and q.type != "short"
