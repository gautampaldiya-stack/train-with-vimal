from django.core.management import call_command

from apps.accounts.models import Role, User
from apps.clients.models import ClientProfile


def test_seed_demo_keeps_the_live_admin(db):
    """Live site: the admin came from createsuperuser with his own email. seed_demo must not make a second admin
    (only one may exist); the demo clients of "Vimal" go to him and his login stays his own (D-57)."""
    admin = User.objects.get(role=Role.ADMIN)
    admin.email = "owner@example.org"
    admin.set_password("Owner@1234")
    admin.save()

    call_command("seed_demo", verbosity=0)

    admins = list(User.objects.filter(role=Role.ADMIN))
    assert admins == [admin]
    admin.refresh_from_db()
    assert admin.email == "owner@example.org" and admin.check_password("Owner@1234")
    assert ClientProfile.objects.filter(trainer=admin).exists()
