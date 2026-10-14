from rest_framework.test import APIClient


def test_login_by_mobile_works(db):
    c = APIClient(HTTP_HOST="localhost")
    r = c.post("/api/v1/auth/login/", {"identifier": "+919810000002", "password": "Demo@1234"}, format="json")
    assert r.status_code == 200


def test_wrong_password_uses_error_shape(db):
    c = APIClient(HTTP_HOST="localhost")
    r = c.post("/api/v1/auth/login/", {"identifier": "aman@trainwithvimal.com", "password": "nope"}, format="json")
    assert r.status_code == 400
    assert set(r.json()["error"]) >= {"code", "message"}


def test_anonymous_is_refused(db):
    assert APIClient(HTTP_HOST="localhost").get("/api/v1/clients/").status_code == 401
