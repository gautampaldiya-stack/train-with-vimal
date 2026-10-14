from apps.accounts.models import User


def test_trainer_sees_only_own_clients(trainer):
    names = {row["full_name"] for row in trainer.get("/api/v1/clients/").json()["results"]}
    assert "Riya Sharma" in names
    assert "Ananya Iyer" not in names  # Neha's client


def test_other_trainers_client_is_404(trainer):
    other = User.objects.get(email="ananya@example.com")
    assert trainer.get(f"/api/v1/clients/{other.id}/").status_code == 404


def test_client_cannot_open_admin_screens(client_user):
    assert client_user.get("/api/v1/dashboard/admin/").status_code == 403
    assert client_user.get("/api/v1/trainers/").status_code == 403


def test_admin_dashboard_loads(admin):
    assert admin.get("/api/v1/dashboard/admin/").status_code == 200
