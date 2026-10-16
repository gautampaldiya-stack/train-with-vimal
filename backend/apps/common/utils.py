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


def data_url_file(item, name, field="photo"):
    """A photo the app sent as a data URL ("data:image/jpeg;base64,…"), so it can wait in the offline outbox."""
    import base64
    import binascii

    from django.core.files.base import ContentFile
    from rest_framework.exceptions import ValidationError

    head, _, body = str(item).partition(",")
    ext = {"image/png": "png", "image/webp": "webp"}.get(head[5:].split(";")[0], "jpg")
    if not head.startswith("data:image/") or not body:
        raise ValidationError({field: ["Send the photo as an image."]})
    try:
        raw = base64.b64decode(body, validate=True)
    except (binascii.Error, ValueError):
        raise ValidationError({field: ["Send the photo as an image."]})
    if len(raw) > 10 * 1024 * 1024:
        raise ValidationError({field: ["Photos can be up to 10 MB."]})
    return ContentFile(raw, name=f"{name}.{ext}")


def dfmt(value, fmt):
    """strftime with "%-d" / "%-I" / "%-H" / "%-m" (no leading zero) on every OS. Windows' strftime refuses "%-"."""
    for code, val in (("%-d", value.day if hasattr(value, "day") else 0),
                      ("%-m", value.month if hasattr(value, "month") else 0),
                      ("%-H", getattr(value, "hour", 0)),
                      ("%-I", (getattr(value, "hour", 0) % 12) or 12)):
        fmt = fmt.replace(code, str(val))
    return value.strftime(fmt)
