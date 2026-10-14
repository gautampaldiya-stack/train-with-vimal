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


def test_wrong_password_counts_down_then_locks(db):
    from rest_framework.test import APIClient

    from django.core.cache import cache

    cache.clear()
    c = APIClient(HTTP_HOST="localhost")
    body = {"identifier": "riya@example.com", "password": "nope"}
    try:
        r = c.post("/api/v1/auth/login/", body, format="json")
        assert r.status_code == 400
        assert r.json()["error"]["code"] == "invalid_login"
        assert r.json()["error"]["fields"]["tries_left"] == ["4"]
        for _ in range(4):
            r = c.post("/api/v1/auth/login/", body, format="json")
        assert r.json()["error"]["code"] == "locked"
        r = c.post("/api/v1/auth/login/", {**body, "password": "Demo@1234"}, format="json")
        assert r.status_code == 400  # still locked even with the right password
    finally:
        cache.clear()


def test_login_returns_client_setup(db):
    from rest_framework.test import APIClient

    c = APIClient(HTTP_HOST="localhost")
    r = c.post("/api/v1/auth/login/", {"identifier": "riya@example.com", "password": "Demo@1234"}, format="json")
    u = r.json()["user"]
    assert len(u["client"]["setup_done"]) == 5 and u["client"]["coach"]["first_name"]
