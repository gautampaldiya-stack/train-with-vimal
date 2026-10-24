from rest_framework.test import APIClient

from apps.accounts.models import Role, User
from apps.trainers.models import TrainerProfile


def admin_client(admin):
    c = APIClient(HTTP_HOST="localhost")
    c.force_authenticate(user=admin)
    return c


def test_admin_always_has_trainer_profile(db):
    admin = User.objects.get(role=Role.ADMIN)
    assert TrainerProfile.objects.get(user=admin).is_owner


def test_admin_with_no_trainers_can_create_invite_link(db):
    """Gym me koi trainer na ho, tab bhi admin ke naam se link banna chahiye."""
    admin = User.objects.get(role=Role.ADMIN)
    User.objects.filter(role=Role.TRAINER).update(status="deactivated")
    c = admin_client(admin)

    r = c.post("/api/v1/invite-links/", {"label": "Instagram"}, format="json")

    assert r.status_code == 201, r.content
    assert r.json()["trainer"]["id"] == str(admin.id)
    assert r.json()["state"] == "on"


def test_admin_can_pick_himself_as_link_trainer(db):
    admin = User.objects.get(role=Role.ADMIN)
    c = admin_client(admin)

    r = c.post("/api/v1/invite-links/", {"label": "Walk-in", "trainer_id": str(admin.id)}, format="json")

    assert r.status_code == 201, r.content
    assert r.json()["trainer"]["id"] == str(admin.id)


def test_admin_can_pick_a_trainer_for_link(db):
    admin = User.objects.get(role=Role.ADMIN)
    aman = User.objects.get(email="aman@trainwithvimal.com")
    c = admin_client(admin)

    r = c.post("/api/v1/invite-links/", {"label": "Aman", "trainer_id": str(aman.id)}, format="json")

    assert r.status_code == 201, r.content
    assert r.json()["trainer"]["id"] == str(aman.id)
