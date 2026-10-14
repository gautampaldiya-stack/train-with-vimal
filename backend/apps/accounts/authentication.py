from django.core.cache import cache
from django.utils import timezone
from rest_framework import exceptions
from rest_framework_simplejwt.authentication import JWTAuthentication

from .models import UserSession

SEEN_EVERY_SECONDS = 60


class SessionJWTAuthentication(JWTAuthentication):
    """JWT auth that also checks the device session was not logged out
    ("Log out" / "Log out of all others" take effect right away, not after the token expires)."""

    def get_user(self, validated_token):
        user = super().get_user(validated_token)
        sid = validated_token.get("sid")
        if sid:
            key = f"sess-revoked:{sid}"
            revoked = cache.get(key)
            if revoked is None:
                revoked = not UserSession.objects.filter(id=sid, revoked_at__isnull=True).exists()
                cache.set(key, revoked, 30)
            if revoked:
                raise exceptions.AuthenticationFailed("You were logged out on this device.", code="session_revoked")
            seen_key = f"sess-seen:{sid}"
            if not cache.get(seen_key):
                now = timezone.now()
                UserSession.objects.filter(id=sid).update(last_active_at=now)
                type(user).objects.filter(pk=user.pk).update(last_seen_at=now)
                cache.set(seen_key, 1, SEEN_EVERY_SECONDS)
        return user


def forget_session_cache(session_ids):
    cache.delete_many([f"sess-revoked:{s}" for s in session_ids])
