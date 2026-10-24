"""Gautam 2026-10-24: two trainer switches for invite links (Trainer profile → Access → Clients), and the access
notice names what changed."""
from apps.accounts.models import User
from apps.notifications.models import Notification

L = "/api/v1/invite-links/"


def _aman():
    return User.objects.get(email="aman@trainwithvimal.com")


def _set(admin, **perms):
    aman = _aman()
    now = aman.trainer_profile.effective_permissions()
    r = admin.put(f"/api/v1/trainers/{aman.id}/access/", {"access_mode": "custom", "permissions": {**now, **perms}},
                  format="json")
    assert r.status_code == 200, r.content


def test_access_notice_names_the_changes(admin):
    _set(admin, **{"clients.approve_signups": True, "clients.pause": True})
    n = Notification.objects.filter(recipient=_aman(), event="access_changed").latest("created_at")
    assert n.title == "Vimal changed your access"
    assert n.body == "Approve sign-ups: on · Pause or resume clients: on"
    count = Notification.objects.filter(event="access_changed").count()
    _set(admin)  # saved with nothing changed: no notice
    assert Notification.objects.filter(event="access_changed").count() == count


def test_trainer_makes_links_only_for_himself(admin, trainer):
    other = User.objects.filter(role="trainer").exclude(email="aman@trainwithvimal.com").first()
    r = trainer.post(L, {"label": "Insta", "trainer_id": str(other.id)}, format="json")
    assert r.status_code == 201, r.content
    assert r.json()["trainer"]["id"] == str(_aman().id)
    assert trainer.patch(f"{L}{r.json()['id']}/", {"trainer_id": str(other.id)}, format="json").status_code == 403


def test_new_links_switch(admin, trainer):
    _set(admin, **{"clients.invite_new": False})
    assert trainer.post(L, {"label": "Insta"}, format="json").status_code == 403
    assert trainer.get(L).status_code == 200  # he still shares the links he has


def test_invite_switch_stops_his_links(admin, trainer):
    from rest_framework.test import APIClient

    code = trainer.post(L, {"label": "Insta"}, format="json").json()["code"]
    _set(admin, **{"clients.invite": False})
    assert trainer.get(L).status_code == 403
    page = APIClient().get(f"/api/v1/join/{code}/").json()
    assert (page["state"], page["reason"]) == ("off", "off")
    row = next(x for x in admin.get(L).json() if x["code"] == code)
    assert row["access_off"] is True and row["state"] == "off"
    _set(admin, **{"clients.invite": True})
    assert APIClient().get(f"/api/v1/join/{code}/").json()["state"] == "on"
