from datetime import timedelta

from django.conf import settings
from django.utils import timezone
from rest_framework_simplejwt.tokens import RefreshToken

from apps.common.middleware import client_source
from apps.common.utils import hash_token, new_token

from .models import OneTimeToken, UserSession


def _ip(request):
    if request is None:
        return None
    fwd = request.META.get("HTTP_X_FORWARDED_FOR")
    return (fwd.split(",")[0].strip() if fwd else request.META.get("REMOTE_ADDR")) or None


def start_session(user, request, device_name="", platform=""):
    """Creates the device session and returns {access, refresh} carrying its id (`sid`)."""
    platform = (platform or (request.headers.get("X-Client", "") if request else "")).lower()[:20]
    session = UserSession.objects.create(
        user=user,
        device_name=(device_name or client_source(request))[:120],
        platform=platform,
        ip_address=_ip(request),
        user_agent=(request.META.get("HTTP_USER_AGENT", "") if request else "")[:300],
    )
    refresh = RefreshToken.for_user(user)
    refresh["sid"] = str(session.id)
    refresh["role"] = user.role
    access = refresh.access_token
    access["sid"] = str(session.id)
    access["role"] = user.role
    user.last_login = timezone.now()
    user.save(update_fields=["last_login"])
    return {"access": str(access), "refresh": str(refresh), "session_id": str(session.id)}


def issue_one_time_token(user, purpose, email=""):
    """Returns the raw token (goes into the link) and stores only its hash.
    Older unused tokens of the same purpose stop working ("The old link stops working")."""
    OneTimeToken.objects.filter(user=user, purpose=purpose, used_at__isnull=True).update(used_at=timezone.now())
    raw = new_token()
    OneTimeToken.objects.create(
        user=user,
        purpose=purpose,
        token_hash=hash_token(raw),
        email=email,
        expires_at=timezone.now() + timedelta(hours=settings.TOKEN_TTL_HOURS[purpose]),
    )
    return raw


def consume_one_time_token(raw, purpose):
    """Returns (token_row, problem). problem is None, 'invalid', 'used' or 'expired'."""
    row = OneTimeToken.objects.select_related("user").filter(token_hash=hash_token(raw or ""), purpose=purpose).first()
    if row is None:
        return None, "invalid"
    if row.used_at is not None:
        return row, "used"
    if row.expires_at <= timezone.now():
        return row, "expired"
    return row, None
