"""Client profile → Content, Forms and Notes tabs (trainer view)."""

from django.utils import timezone

from apps.accounts.models import User
from apps.checkins.client_page import client_weekly_form
from apps.checkins.models import Form, FormRequest, FormSchedule
from apps.content.models import ContentItem, ContentShare


def _riya():
    return User.objects.get(email="riya@example.com")


# ---------------------------------------------------------------- Content


def test_content_tab_lists_what_she_sees_and_why(trainer, client_user):
    riya = _riya()
    d = trainer.get(f"/api/v1/clients/{riya.id}/content/").json()
    lib = client_user.get("/api/v1/me/library/").json()
    assert d["count"] == d["counts"]["all"] == lib["total"]
    assert d["counts"]["all"] == d["counts"]["assigned"] + d["counts"]["plan"] + d["counts"]["everyone"]
    box = next(r for r in d["results"] if r["title"] == "Box squat: how to")
    assert box["why"] == "assigned" and box["why_label"] == "Assigned to Riya" and box["added_by"] == "Aman Verma"
    leg = next(r for r in d["results"] if r["title"] == "How to warm up for leg day")
    assert leg["why"] == "plan" and leg["why_label"].startswith("From ")
    plan = trainer.get(f"/api/v1/clients/{riya.id}/content/", {"why": "plan"}).json()
    assert plan["count"] == d["counts"]["plan"] and all(r["why"] == "plan" for r in plan["results"])


def test_remove_and_hide_for_her_with_undo(trainer, client_user):
    riya = _riya()
    url = f"/api/v1/clients/{riya.id}/content/"
    box = ContentItem.objects.get(title="Box squat: how to")
    welcome = ContentItem.objects.get(title="Welcome to Train With Vimal")
    for item in (box, welcome):
        assert trainer.post(f"{url}{item.id}/unshare/").status_code == 204
        titles = {x["title"] for x in client_user.get("/api/v1/me/library/").json()["results"]}
        assert item.title not in titles
        assert item.title not in {r["title"] for r in trainer.get(url).json()["results"]}
        assert trainer.post(f"{url}{item.id}/restore/").status_code == 204
        assert item.title in {x["title"] for x in client_user.get("/api/v1/me/library/").json()["results"]}
    assert ContentShare.objects.get(item=box, client=riya).note  # Undo keeps the note
    assert not ContentShare.objects.filter(item=welcome, client=riya).exists()


def test_assign_several_with_note_and_how_long(trainer, client_user):
    riya = _riya()
    aman = User.objects.get(email="aman@trainwithvimal.com")
    a = ContentItem.objects.create(kind="article", title="Sleep basics", body="Sleep 7 hours.", created_by=aman)
    b = ContentItem.objects.create(kind="article", title="Water basics", body="Drink 3 L.", created_by=aman)
    lib = trainer.get(f"/api/v1/clients/{riya.id}/content/library/", {"q": "basics"}).json()
    assert {x["title"]: x["has"] for x in lib["results"]} == {"Sleep basics": False, "Water basics": False}
    day = (timezone.localdate() + timezone.timedelta(days=10)).isoformat()
    r = trainer.post(f"/api/v1/clients/{riya.id}/content/", {"items": [str(a.id), str(b.id)], "note": "Read these",
                                                            "until": "date", "date": day}, format="json")
    assert r.status_code == 201 and r.json()["added"] == 2
    s = ContentShare.objects.get(item=a, client=riya)
    assert s.note == "Read these" and str(s.expires_on) == day
    lib = trainer.get(f"/api/v1/clients/{riya.id}/content/library/", {"q": "basics"}).json()
    assert all(x["has"] for x in lib["results"])
    # ran out: gone from her Library
    ContentShare.objects.filter(item=a, client=riya).update(expires_on=timezone.localdate() - timezone.timedelta(days=1))
    assert "Sleep basics" not in {x["title"] for x in client_user.get("/api/v1/me/library/").json()["results"]}
    past = trainer.post(f"/api/v1/clients/{riya.id}/content/{b.id}/until/", {"until": "date", "date": "2020-01-01"},
                        format="json")
    assert past.status_code == 400
    ok = trainer.post(f"/api/v1/clients/{riya.id}/content/{b.id}/until/", {"until": "always"}, format="json").json()
    assert ok["until_label"] == "Always"
    assert trainer.post(f"/api/v1/clients/{riya.id}/content/{b.id}/remind/").status_code == 200
    assert ContentShare.objects.get(item=b, client=riya).reminded_at is not None


def test_content_tab_is_only_for_his_clients(trainer):
    other = User.objects.filter(role="client").exclude(client_profile__trainer__email="aman@trainwithvimal.com").first()
    assert trainer.get(f"/api/v1/clients/{other.id}/content/").status_code == 404


# ---------------------------------------------------------------- Forms


def test_forms_list_send_remind_and_withdraw(trainer):
    riya = _riya()
    base = f"/api/v1/clients/{riya.id}/forms/"
    d = trainer.get(base).json()
    keys = [r["key"] for r in d["sent"]]
    assert keys[0] == "onboarding" and "weekly" in keys
    fb = next(f for f in d["can_send"] if f["name"] == "Monthly feedback")
    r = trainer.post(base, {"form": fb["id"], "mode": "once", "send": "now", "by": "push_whatsapp"}, format="json")
    assert r.status_code == 201
    key = r.json()["key"]
    card = trainer.get(f"{base}{key}/").json()
    assert card["status"] == "waiting" and card["questions"] and "not answered yet" in card["cap"]
    assert trainer.post(f"{base}{key}/remind/").status_code == 200
    assert "A reminder went out" in trainer.get(f"{base}{key}/").json()["waiting"]
    sent = next(f for f in trainer.get(base).json()["can_send"] if f["name"] == "Monthly feedback")
    assert sent["has"].startswith("Sent ")
    assert trainer.post(f"{base}{key}/stop/").status_code == 200
    assert not FormRequest.objects.filter(id=key[4:]).exists()


def test_edit_weekly_for_her_keeps_the_master(trainer):
    riya = _riya()
    base = f"/api/v1/clients/{riya.id}/forms/"
    master = Form.objects.get(type="weekly", status="published")
    before = list(master.questions.values_list("text", "required"))
    qs = trainer.get(f"{base}weekly/questions/").json()["questions"]
    qs[1]["required"] = not qs[1]["required"]
    qs.append({"text": "How does your knee feel?", "type": "scale", "required": True})
    r = trainer.put(f"{base}weekly/questions/", {"questions": qs}, format="json")
    assert r.status_code == 200, r.content
    d = r.json()
    assert d["edited"] and d["changes"] == "1 question added, 1 changed"
    assert d["questions"][-1]["change"] == "Added for Riya" and d["questions"][1]["change"].startswith("Was: ")
    assert list(master.questions.values_list("text", "required")) == before
    mine = client_weekly_form(riya)
    assert mine.status == Form.Status.CLIENT and mine.master_id == master.id
    assert str(mine.id) not in trainer.get("/api/v1/forms/", {"page_size": 100}).content.decode()  # not a library form
    # Stop sending → her app has no weekly check-in; Undo → back on
    trainer.post(f"{base}weekly/stop/")
    assert client_weekly_form(riya) is None
    trainer.post(f"{base}weekly/start/")
    assert client_weekly_form(riya).id == mine.id
    # Reset to master
    assert trainer.post(f"{base}weekly/reset/").status_code == 200
    assert client_weekly_form(riya).id == master.id


def test_duplicate_and_repeat(trainer):
    riya = _riya()
    base = f"/api/v1/clients/{riya.id}/forms/"
    fb = Form.objects.get(name="Monthly feedback", status="published")
    qs = [{"id": q.id, "text": q.text, "type": q.type, "required": q.required, "options": q.options}
          for q in fb.questions.filter(is_removed=False)]
    day = (timezone.localdate() + timezone.timedelta(days=3)).isoformat()
    r = trainer.post(f"{base}duplicate/", {"form": str(fb.id), "name": "Monthly feedback · Riya",
                                           "questions": qs[:2], "first_send": day}, format="json")
    assert r.status_code == 201, r.content
    s = FormSchedule.objects.get(id=r.json()["key"][6:])
    assert s.form.status == Form.Status.CLIENT and s.form.client == riya and s.next_at
    r = trainer.post(base, {"form": str(fb.id), "mode": "repeat", "every": "month", "month_day": 1, "time": "10:00"},
                     format="json")
    rep = FormSchedule.objects.get(id=r.json()["key"][6:])
    assert rep.repeat == "month" and rep.next_at > timezone.now()
    from apps.checkins.client_forms import run_schedules

    FormSchedule.objects.filter(id=rep.id).update(next_at=timezone.now())
    assert run_schedules() >= 1
    rep.refresh_from_db()
    assert rep.next_at > timezone.now() and FormRequest.objects.filter(schedule=rep).count() == 1


# ---------------------------------------------------------------- Notes


def test_notes_flag_on_top_edit_delete_undo(trainer, admin):
    riya = _riya()
    url = f"/api/v1/clients/{riya.id}/notes/"
    n = trainer.post(url, {"body": "Knee hurts on lunges", "is_flag": True}, format="json").json()
    rows = trainer.get(url).json()["results"]
    assert rows[0]["is_flag"]
    over = trainer.get(f"/api/v1/clients/{riya.id}/overview/").json()
    assert any(x["kind"] == "flag" for x in over["needs_attention"])
    assert trainer.patch(f"{url}{n['id']}/", {"body": "Knee better", "is_flag": False}, format="json").json()[
        "body"] == "Knee better"
    assert trainer.delete(f"{url}{n['id']}/").status_code == 204
    assert all(x["id"] != n["id"] for x in trainer.get(url).json()["results"])
    assert trainer.post(f"{url}{n['id']}/restore/").status_code == 200
    mine = admin.post(url, {"body": "Vimal's note"}, format="json").json()
    assert trainer.delete(f"{url}{mine['id']}/").status_code == 403
