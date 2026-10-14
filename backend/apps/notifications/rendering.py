"""Template variables. Plain string replacement only (no template engine), so text an
admin types can never run code."""
import re

from django.conf import settings
from django.utils import timezone

VARIABLES = ["first_name", "coach_name", "gym_name", "package_name", "date"]
_VAR_RE = re.compile(r"\{\{\s*([a-z_]+)\s*\}\}")


def context_for(user, extra=None):
    profile = getattr(user, "client_profile", None)
    trainer = getattr(profile, "trainer", None) if profile else None
    ctx = {
        "first_name": user.first_name,
        "coach_name": trainer.full_name if trainer else "",
        "gym_name": settings.APP_NAME,
        "package_name": getattr(profile, "package_name", "") if profile else "",
        "date": timezone.localdate().strftime("%a, %-d %b"),
    }
    ctx.update(extra or {})
    return ctx


def render(text, ctx):
    return _VAR_RE.sub(lambda m: str(ctx.get(m.group(1), m.group(0))), text or "")
