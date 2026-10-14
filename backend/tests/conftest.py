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
