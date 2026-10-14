import re

from django.core.exceptions import ValidationError
from django.utils.deconstruct import deconstructible
from django.utils.translation import gettext_lazy as _

PHONE_RE = re.compile(r"^\+[1-9]\d{7,14}$")


def normalize_phone(value: str) -> str:
    """'+91 98200 12345' -> '+919820012345'. Ten bare digits are treated as Indian numbers."""
    if not value:
        return value
    digits = re.sub(r"[^\d+]", "", value.strip())
    if digits.startswith("00"):
        digits = "+" + digits[2:]
    if not digits.startswith("+"):
        if len(digits) == 10:
            digits = "+91" + digits
        elif len(digits) == 12 and digits.startswith("91"):
            digits = "+" + digits
    return digits


def validate_phone(value: str):
    if not PHONE_RE.match(normalize_phone(value) or ""):
        raise ValidationError(_("Enter a valid mobile number with country code, e.g. +91 98200 12345."))


@deconstructible
class validate_file_size:  # noqa: N801  (used like a function: validate_file_size(10))
    def __init__(self, max_mb: int):
        self.max_mb = max_mb

    def __call__(self, f):
        if f and f.size > self.max_mb * 1024 * 1024:
            raise ValidationError(_("File is too large. The limit is %(mb)s MB."), params={"mb": self.max_mb})

    def __eq__(self, other):
        return isinstance(other, validate_file_size) and other.max_mb == self.max_mb


IMAGE_EXTENSIONS = ["jpg", "jpeg", "png", "webp"]
DOCUMENT_EXTENSIONS = ["pdf", "jpg", "jpeg", "png"]
VIDEO_EXTENSIONS = ["mp4", "mov", "webm", "m4v"]
