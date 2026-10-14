import hashlib
import secrets

AVATAR_COLORS = ["c1", "c2", "c3", "c4", "c5", "c6"]


def initials(name: str) -> str:
    parts = [p for p in (name or "").split() if p]
    if not parts:
        return "?"
    if len(parts) == 1:
        return parts[0][:2].upper()
    return (parts[0][0] + parts[-1][0]).upper()


def avatar_color(name: str) -> str:
    """Design rule: rotate avatar colours by name, never random."""
    h = int(hashlib.md5((name or "").encode()).hexdigest(), 16)
    return AVATAR_COLORS[h % len(AVATAR_COLORS)]


def new_token(nbytes: int = 32) -> str:
    return secrets.token_urlsafe(nbytes)


def hash_token(token: str) -> str:
    """Only hashes of one-time tokens are stored, so a DB leak does not leak live links."""
    return hashlib.sha256(token.encode()).hexdigest()


def sync_day(value, *, back_days=7):
    """Date sent by the app for something logged offline. None → today. Only today and the last
    `back_days` days are accepted, never the future."""
    from django.utils import timezone
    from django.utils.dateparse import parse_date
    from rest_framework.exceptions import ValidationError

    today = timezone.localdate()
    if not value:
        return today
    d = value if hasattr(value, "year") else parse_date(str(value))
    if d is None:
        raise ValidationError({"date": ["Send the date as YYYY-MM-DD."]})
    if d > today or d < today - timezone.timedelta(days=back_days):
        raise ValidationError({"date": [f"You can log today or the last {back_days} days."]})
    return d


def sync_time(value):
    """Time the app logged something offline (ISO). Clamped to now."""
    from django.utils import timezone
    from django.utils.dateparse import parse_datetime

    now = timezone.now()
    t = parse_datetime(str(value)) if value else None
    if t is None:
        return now
    if timezone.is_naive(t):
        t = timezone.make_aware(t)
    return min(t, now)
