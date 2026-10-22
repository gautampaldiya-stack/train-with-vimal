"""Admin Clients and Approvals (boards Clients, ClientsMobile, Approvals, ApprovalsMobile, ClientProfile)."""
from django.contrib.auth import get_user_model

from apps.accounts.models import Role

User = get_user_model()


def _riya():
    return User.objects.get(email="riya@example.com")


def _other_trainer(exclude):
    return User.objects.filter(role=Role.TRAINER, trainer_profile__isnull=False).exclude(id=exclude).first()


# ---------------------------------------------------------------- Clients list
def test_admin_sees_every_client_with_trainer_and_counts(admin):
    r = admin.get("/api/v1/clients/", {"page_size": 50})
    assert r.status_code == 200
    rows = r.json()["results"]
    trainers = {(x["trainer"] or {}).get("full_name") for x in rows}
    assert len(trainers) > 1  # not only one trainer's clients
    assert {"date_joined", "trainer", "onboarding", "badge"} <= set(rows[0])
    c = admin.get("/api/v1/clients/counts/").json()
    assert {"all", "active", "pending", "paused", "at_risk", "no_trainer"} <= set(c)


def test_filter_by_trainer_and_no_trainer(admin):
    riya = _riya()
    tid = riya.client_profile.trainer_id
    rows = admin.get("/api/v1/clients/", {"trainer": str(tid), "page_size": 50}).json()["results"]
    assert rows and all(x["trainer"]["id"] == str(tid) for x in rows)
    none = admin.get("/api/v1/clients/", {"trainer": "none", "page_size": 50}).json()["results"]
    assert all(x["trainer"] is None for x in none)


def test_add_client_active_and_to_approvals(admin):
    r = admin.post("/api/v1/clients/", {"full_name": "Kavya Menon", "phone": "9000011111", "goal": "fat_loss",
                                       "mode": "active"}, format="json")
    assert r.status_code == 201, r.content
    assert r.json()["status"] == "active"
    again = admin.post("/api/v1/clients/", {"full_name": "Kavya M", "phone": "9000011111"}, format="json")
    assert again.status_code == 400
    assert "phone" in again.json()["error"]["fields"]
    r = admin.post("/api/v1/clients/", {"full_name": "Tarini Bose", "phone": "9000011112", "mode": "approvals"},
                   format="json")
    assert r.status_code == 201
    assert r.json()["status"] == "pending"
    waiting = admin.get("/api/v1/approvals/", {"q": "Tarini"}).json()["results"]
    assert [w["client"]["full_name"] for w in waiting] == ["Tarini Bose"]


# ---------------------------------------------------------------- Change trainer
def test_trainers_list_marks_current_and_full(admin):
    riya = _riya()
    r = admin.get(f"/api/v1/clients/{riya.id}/trainers/")
    assert r.status_code == 200
    d = r.json()
    assert d["trainers"][0]["current"] is True
    assert d["current"]["id"] == str(riya.client_profile.trainer_id)
    assert "open_checkins" in d and "since" in d
    assert all({"clients", "max_clients", "full", "good_fit"} <= set(t) for t in d["trainers"])


def test_trainer_cannot_open_change_trainer(trainer):
    riya = _riya()
    assert trainer.get(f"/api/v1/clients/{riya.id}/trainers/").status_code == 403


def test_change_trainer_with_note_and_fresh_start(admin, django_capture_on_commit_callbacks):
    from apps.checkins.models import Submission
    from apps.clients.models import ClientNote

    riya = _riya()
    old = riya.client_profile.trainer
    new = _other_trainer(old.id)
    r = admin.post(f"/api/v1/clients/{riya.id}/change-trainer/",
                   {"trainer": str(new.id), "move_checkins": False, "tell_old": True,
                    "note": "Knee issue, prefers veg meals"}, format="json")
    assert r.status_code == 200, r.content
    riya.client_profile.refresh_from_db()
    assert riya.client_profile.trainer_id == new.id
    assert riya.client_profile.trainer_since is not None
    assert not Submission.objects.filter(client=riya, reviewed_at__isnull=True).exists()
    assert ClientNote.objects.filter(client=riya, body="Knee issue, prefers veg meals").exists()
    same = admin.post(f"/api/v1/clients/{riya.id}/change-trainer/", {"trainer": str(new.id)}, format="json")
    assert same.status_code == 400


# ---------------------------------------------------------------- Edit profile → Sign-in
def test_admin_sets_password_trainer_cannot(admin, trainer):
    riya = _riya()
    short = admin.patch(f"/api/v1/clients/{riya.id}/", {"password": "abc"}, format="json")
    assert short.status_code == 400 and "password" in short.json()["error"]["fields"]
    assert trainer.patch(f"/api/v1/clients/{riya.id}/", {"password": "NewPass@2026"}, format="json").status_code == 403
    ok = admin.patch(f"/api/v1/clients/{riya.id}/", {"password": "NewPass@2026"}, format="json")
    assert ok.status_code == 200
    riya.refresh_from_db()
    assert riya.check_password("NewPass@2026")
    assert not riya.password.startswith("NewPass")  # stored as a hash
    riya.set_password("Demo@1234")
    riya.save()


def test_send_reset_link(admin):
    riya = _riya()
    r = admin.post(f"/api/v1/clients/{riya.id}/send-reset/")
    assert r.status_code == 200
    assert r.json()["sent_to"] == riya.email


# ---------------------------------------------------------------- Invite links
def test_invite_links_create_toggle_delete(admin):
    t = _other_trainer(None)
    code = admin.get("/api/v1/invite-links/suggest-code/", {"trainer": str(t.id)}).json()["code"]
    r = admin.post("/api/v1/invite-links/", {"trainer_id": str(t.id), "label": "Instagram · October", "code": code,
                                            "needs_approval": True}, format="json")
    assert r.status_code == 201, r.content
    link = r.json()
    assert link["code"] == code and link["state"] == "on" and link["url"].endswith(code)
    off = admin.patch(f"/api/v1/invite-links/{link['id']}/", {"is_on": False}, format="json")
    assert off.json()["state"] == "off"
    s = admin.get("/api/v1/invite-links/summary/").json()
    assert {"links", "on", "joined", "waiting"} <= set(s)
    assert admin.delete(f"/api/v1/invite-links/{link['id']}/").status_code == 204
    assert code not in [x["code"] for x in admin.get("/api/v1/invite-links/").json()]


# ---------------------------------------------------------------- Approvals
def _waiting(admin):
    rows = admin.get("/api/v1/approvals/").json()["results"]
    assert rows, "seed has sign-ups waiting"
    return rows


def test_approvals_list_detail_and_search(admin):
    rows = _waiting(admin)
    a = rows[0]
    assert {"signed_up_from_label", "setup_done", "waiting_hours", "has_health_note"} <= set(a)
    d = admin.get(f"/api/v1/approvals/{a['id']}/").json()
    assert {"answers", "invite_code", "steps", "health_notes"} <= set(d)
    name = a["client"]["full_name"].split()[0]
    found = admin.get("/api/v1/approvals/", {"q": name}).json()["results"]
    assert any(x["id"] == a["id"] for x in found)
    assert admin.get("/api/v1/approvals/", {"q": "zzzz-nobody"}).json()["results"] == []


def test_approve_reject_move_back_and_ask(admin):
    rows = _waiting(admin)
    a = rows[0]
    tr = admin.get(f"/api/v1/approvals/{a['id']}/trainers/").json()
    pick = next(t for t in tr["trainers"] if t["tag"] != "full")
    ok = admin.post(f"/api/v1/approvals/{a['id']}/approve/", {"trainer": str(pick["id"])}, format="json")
    assert ok.status_code == 200 and ok.json()["status"] == "approved"
    assert User.objects.get(id=a["client"]["id"]).status == "active"

    b = _waiting(admin)[0]
    ask = admin.post(f"/api/v1/approvals/{b['id']}/ask-info/",
                     {"items": ["setup", "photo"], "channels": ["email", "in_app"], "message": "Hi, finish setup"},
                     format="json")
    assert ask.status_code == 200 and ask.json()["asked"] == 2
    need_msg = admin.post(f"/api/v1/approvals/{b['id']}/reject/", {"reason": "other"}, format="json")
    assert need_msg.status_code == 400
    rej = admin.post(f"/api/v1/approvals/{b['id']}/reject/", {"reason": "has_account"}, format="json")
    assert rej.json()["status"] == "rejected"
    hist = admin.get("/api/v1/approvals/", {"tab": "history", "decision": "rejected"}).json()["results"]
    assert any(h["id"] == b["id"] for h in hist)
    back = admin.post(f"/api/v1/approvals/{b['id']}/move-back/", {}, format="json")
    assert back.json()["status"] == "waiting" and back.json()["moved_back"] is True
    assert _waiting(admin)[0]["id"] == b["id"]  # moved back shows on top


def test_check_phone_while_typing(admin):
    riya = _riya()
    assert admin.get("/api/v1/clients/check-phone/", {"phone": "12"}).json() == {"valid": False, "taken": None}
    assert admin.get("/api/v1/clients/check-phone/", {"phone": riya.phone}).json()["taken"] == "phone"
    assert admin.get("/api/v1/clients/check-phone/", {"phone": "+919000099999"}).json() == {"valid": True, "taken": None}


def test_add_client_with_trainer_program_and_meal_plan(admin):
    from apps.nutrition.models import MealPlan
    from apps.training.models import Program

    t = _other_trainer(None)
    prog = Program.objects.filter(is_master=True, archived_at__isnull=True).first()
    plan = MealPlan.objects.filter(deleted_at__isnull=True).first()
    r = admin.post("/api/v1/clients/", {"full_name": "Meher Kaur", "phone": "9000011113", "trainer": str(t.id),
                                       "program": str(prog.id), "meal_plan": str(plan.id)}, format="json")
    assert r.status_code == 201, r.content
    assert r.json()["trainer"]["id"] == str(t.id)
    bad = admin.post("/api/v1/clients/", {"full_name": "Meher K", "phone": "9000011114",
                                         "meal_plan": "00000000-0000-0000-0000-000000000000"}, format="json")
    assert bad.status_code == 400
    assert not User.objects.filter(phone="+919000011114").exists()  # nothing half made
