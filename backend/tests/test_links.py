from datetime import timedelta

from django.utils import timezone
from rest_framework.test import APIClient


def _anon():
    return APIClient(HTTP_HOST="localhost")


def test_link_lifetimes_follow_the_boards(db):
    from apps.accounts.models import OneTimeToken, User
    from apps.accounts.tokens import issue_one_time_token

    u = User.objects.get(email="riya@example.com")
    for purpose, minutes in [(OneTimeToken.Purpose.PASSWORD_RESET, 15), (OneTimeToken.Purpose.EMAIL_VERIFY, 24 * 60)]:
        issue_one_time_token(u, purpose)
        row = OneTimeToken.objects.filter(user=u, purpose=purpose).latest("id")
        left = (row.expires_at - timezone.now()).total_seconds() / 60
        assert minutes - 1 < left <= minutes


def test_join_link_says_why_it_ended(db):
    from apps.clients.models import InviteLink

    r = _anon().get("/api/v1/join/AMAN-4821/")
    assert r.status_code == 200
    assert r.json()["reason"] is None and r.json()["code"] == "AMAN-4821"
    link = InviteLink.objects.get(code="AMAN-4821")
    link.expires_at = timezone.now() - timedelta(minutes=1)
    link.save()
    assert _anon().get("/api/v1/join/AMAN-4821/").json()["reason"] == "expired"
    body = {"full_name": "Test Person", "email": "tp@example.com", "phone": "+919800011122",
            "password": "Abcd1234", "accept_terms": True, "platform": "web"}
    r = _anon().post("/api/v1/join/AMAN-4821/", body, format="json")
    assert r.status_code == 400 and r.json()["error"]["code"] == "link_expired"
    link.expires_at = None
    link.is_on = False
    link.save()
    assert _anon().get("/api/v1/join/AMAN-4821/").json()["reason"] == "off"


def test_login_link_not_me_turns_the_link_off(db):
    from apps.accounts.models import OneTimeToken, User
    from apps.accounts.tokens import issue_one_time_token

    u = User.objects.get(email="sana@example.com")
    raw = issue_one_time_token(u, OneTimeToken.Purpose.LOGIN_LINK)
    r = _anon().post("/api/v1/auth/login-link/check/", {"token": raw}, format="json")
    assert r.status_code == 200 and r.json()["coach"]["first_name"]
    r = _anon().post("/api/v1/auth/login-link/not-me/", {"token": raw}, format="json")
    assert r.status_code == 200
    r = _anon().post("/api/v1/auth/login-link/check/", {"token": raw}, format="json")
    assert r.status_code == 400 and r.json()["error"]["code"] == "link_used"
