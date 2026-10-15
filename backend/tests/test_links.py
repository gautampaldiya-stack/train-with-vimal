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
        row = OneTimeToken.objects.get(user=u, purpose=purpose, used_at__isnull=True)
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


def test_forgot_password_says_when_no_account_matches(db):
    r = _anon().post("/api/v1/auth/password/forgot/", {"identifier": "nobody@example.com"}, format="json")
    assert r.status_code == 400 and r.json()["error"]["code"] == "no_account"
    r = _anon().post("/api/v1/auth/password/forgot/", {"identifier": "riya@example.com"}, format="json")
    assert r.status_code == 200


def test_used_login_link_still_names_the_coach(db):
    from apps.accounts.models import OneTimeToken, User
    from apps.accounts.tokens import issue_one_time_token

    u = User.objects.get(email="sana@example.com")
    raw = issue_one_time_token(u, OneTimeToken.Purpose.LOGIN_LINK)
    _anon().post("/api/v1/auth/login-link/not-me/", {"token": raw}, format="json")
    r = _anon().post("/api/v1/auth/login-link/check/", {"token": raw}, format="json")
    assert r.json()["error"]["fields"]["coach_first_name"] == ["Aman"]
