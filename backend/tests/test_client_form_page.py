"""Client fills a form the coach sent (boards ClientForm / ClientFormWeb, D-49)."""
from apps.accounts.models import User
from apps.checkins import services
from apps.checkins.models import Form, FormRequest, Submission


def _send(name="Monthly feedback"):
    riya = User.objects.get(email="riya@example.com")
    aman = User.objects.get(email="aman@trainwithvimal.com")
    FormRequest.objects.filter(client=riya).delete()
    form = Form.objects.get(name=name, client__isnull=True)
    return services.send_form(riya, form, actor=aman)


def test_sent_form_shows_on_checkins_and_opens(client_user):
    req = _send()
    d = client_user.get("/api/v1/me/checkins/").json()
    card = next(f for f in d["forms"] if f["id"] == str(req.id))
    assert card["name"] == "Monthly feedback" and card["from"] == "Aman"
    assert card["question_count"] == 3 and card["filled_at"] is None
    assert card["why"] == "3 questions. Takes about a minute."
    r = client_user.get(f"/api/v1/me/forms/{req.id}/")
    assert r.status_code == 200
    qs = r.json()["form"]["questions"]
    assert [q["type"] for q in qs] == ["scale", "long", "long"]
    assert r.json()["submission"] is None


def test_fill_marks_it_sent_once(client_user):
    req = _send()
    qs = client_user.get(f"/api/v1/me/forms/{req.id}/").json()["form"]["questions"]
    # The required scale question needs an answer.
    r = client_user.post("/api/v1/me/submissions/", {"request": str(req.id), "answers": {}}, format="json")
    assert r.status_code == 400
    body = {"request": str(req.id), "answers": {str(qs[0]["id"]): 4, str(qs[2]["id"]): "More food swaps"}}
    r = client_user.post("/api/v1/me/submissions/", body, format="json")
    assert r.status_code == 201, r.content
    got = client_user.get(f"/api/v1/me/forms/{req.id}/").json()
    assert got["filled_at"] and got["submission"]["answers"][str(qs[0]["id"])] == 4
    card = next(f for f in client_user.get("/api/v1/me/checkins/").json()["forms"] if f["id"] == str(req.id))
    assert card["filled_at"]
    r = client_user.post("/api/v1/me/submissions/", body, format="json")
    assert r.status_code == 400
    assert Submission.objects.filter(request=req).count() == 1


def test_form_notification_opens_the_form(db):
    from apps.notifications.models import Notification

    req = _send()
    n = Notification.objects.filter(recipient=req.client, event="form_request").latest("created_at")
    assert n.data["route"] == f"/checkins/forms/{req.id}"


def test_other_clients_form_is_not_found(client_user):
    other = User.objects.filter(role="client").exclude(email="riya@example.com").first()
    form = Form.objects.get(name="Monthly feedback", client__isnull=True)
    req = services.send_form(other, form)
    assert client_user.get(f"/api/v1/me/forms/{req.id}/").status_code == 404


def test_undo_puts_the_form_back_to_fill(client_user):
    req = _send()
    qs = client_user.get(f"/api/v1/me/forms/{req.id}/").json()["form"]["questions"]
    sub = client_user.post("/api/v1/me/submissions/", {"request": str(req.id), "answers": {str(qs[0]["id"]): 5}},
                           format="json").json()
    assert client_user.delete(f"/api/v1/me/submissions/{sub['id']}/").status_code == 204
    assert client_user.get(f"/api/v1/me/forms/{req.id}/").json()["filled_at"] is None
