import pytest
from django.core.management import call_command
from rest_framework.test import APIClient


@pytest.fixture(scope="session")
def django_db_setup(django_db_setup, django_db_blocker):
    with django_db_blocker.unblock():
        call_command("seed_demo", verbosity=0)


def login(identifier, password="Demo@1234"):
    c = APIClient(HTTP_HOST="localhost")
    r = c.post("/api/v1/auth/login/", {"identifier": identifier, "password": password}, format="json")
    assert r.status_code == 200, r.content
    c.credentials(HTTP_AUTHORIZATION=f"Bearer {r.json()['access']}")
    return c


@pytest.fixture
def admin(db):
    return login("vimal@trainwithvimal.com")


@pytest.fixture
def trainer(db):
    return login("aman@trainwithvimal.com")


@pytest.fixture
def client_user(db):
    return login("riya@example.com")


@pytest.fixture
def fresh_measure_period(db):
    """Measurements are one entry per photo period (D-25). The demo data logs one every 2 weeks from Riya's start,
    so on some days today is still inside a seeded entry's period and a log edits it instead of adding one.
    Tests that expect "today's first log" clear the last 30 days first, so they pass on any date."""
    from datetime import timedelta

    from django.utils import timezone

    from apps.checkins.models import Measurement

    Measurement.objects.filter(client__email="riya@example.com",
                               date__gte=timezone.localdate() - timedelta(days=30)).delete()
