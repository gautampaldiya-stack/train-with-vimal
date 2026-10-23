"""Gautam 2026-10-23: the admin can give one trainer Automations and Assign clients; the "What clients see" and
access saves use PUT; the gym profile has social links."""
from apps.accounts.models import User
from apps.trainers.models import AccessMode


def _grant(email, **perms):
    tp = User.objects.get(email=email).trainer_profile
    tp.access_mode = AccessMode.CUSTOM
    tp.permissions = {**tp.effective_permissions(), **perms}
    tp.save()
    return tp


def test_admin_saves_trainer_visibility_and_access_with_put(admin):
    aman = User.objects.get(email="aman@trainwithvimal.com")
    vis = admin.get(f"/api/v1/trainers/{aman.id}/visibility/").json()["visibility"]
    key = next(iter(vis))
    r = admin.put(f"/api/v1/trainers/{aman.id}/visibility/", {key: not vis[key]}, format="json")
    assert r.status_code == 200, r.content
    assert r.json()["visibility"][key] is (not vis[key])
    r = admin.put(f"/api/v1/trainers/{aman.id}/access/", {"access_mode": "custom", "permissions": {"automations.manage": True}},
                  format="json")
    assert r.status_code == 200, r.content
    # a plain PUT on the trainer itself is still not allowed (PATCH edits it)
    assert admin.put(f"/api/v1/trainers/{aman.id}/", {}, format="json").status_code == 405


def test_automations_need_the_permission(trainer):
    assert trainer.get("/api/v1/automations/").status_code == 403
    me = trainer.get("/api/v1/auth/me/").json()
    assert me["permissions"]["automations.manage"] is False
    _grant("aman@trainwithvimal.com", **{"automations.manage": True})
    assert trainer.get("/api/v1/automations/").status_code == 200
    assert trainer.get("/api/v1/message-templates/").status_code == 200


def test_assign_clients_permission_lets_a_trainer_change_the_trainer(trainer):
    aman = User.objects.get(email="aman@trainwithvimal.com")
    client = User.objects.filter(client_profile__trainer=aman).first()
    url = f"/api/v1/clients/{client.id}/trainers/"
    assert trainer.get(url).status_code == 403
    _grant("aman@trainwithvimal.com", **{"clients.assign": True})
    assert trainer.get(url).status_code == 200


def test_gym_social_links(admin):
    r = admin.patch("/api/v1/settings/gym/", {"youtube": "youtube.com/@twv", "facebook": "facebook.com/twv"}, format="json")
    assert r.status_code == 200 and r.json()["youtube"] == "youtube.com/@twv" and r.json()["profile_saved_at"]
    pub = admin.get("/api/v1/gym/").json()
    assert pub["facebook"] == "facebook.com/twv"
