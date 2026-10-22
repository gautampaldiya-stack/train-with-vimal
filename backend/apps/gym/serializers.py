import re

from rest_framework import serializers

from apps.common.validators import IMAGE_EXTENSIONS

from .models import ROLE_PERMISSIONS, GymSettings, Integration

HEX_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")
PHONE_RE = re.compile(r"^\+?[0-9 ]{8,18}$")
DOMAIN_RE = re.compile(r"^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$")
LANGUAGES = {"en": "English"}


class GymProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = GymSettings
        fields = ["name", "email", "phone", "address", "instagram", "timezone", "language", "tagline", "website", "whatsapp",
                  "support_hours", "coach_role", "coach_intro", "coach_stats", "default_units", "week_start",
                  "profile_saved_at"]
        read_only_fields = ["profile_saved_at"]

    def validate_name(self, v):
        v = " ".join(v.split())
        if not v:
            raise serializers.ValidationError("Enter the gym or business name.")
        return v

    def validate_phone(self, v):
        v = " ".join(v.split())
        if v and not PHONE_RE.match(v):
            raise serializers.ValidationError("Use digits, spaces and + only, like +91 98200 12345.")
        return v

    def validate_language(self, v):
        if v not in LANGUAGES:
            raise serializers.ValidationError("Pick a language from the list.")
        return v

    def validate_timezone(self, v):
        import zoneinfo

        if v not in zoneinfo.available_timezones():
            raise serializers.ValidationError("Pick a time zone from the list.")
        return v


class BrandingSerializer(serializers.ModelSerializer):
    applied = serializers.SerializerMethodField()
    logo_name = serializers.SerializerMethodField()
    logo_px = serializers.SerializerMethodField()

    class Meta:
        model = GymSettings
        fields = ["logo", "logo_name", "logo_px", "accent_color", "theme", "branding_applied_at", "branding_draft",
                  "applied", "name"]
        read_only_fields = ["branding_applied_at", "applied", "logo", "name"]

    def get_applied(self, obj):
        return not obj.branding_draft

    def get_logo_name(self, obj):
        return obj.logo.name.rsplit("/", 1)[-1] if obj.logo else None

    def get_logo_px(self, obj):
        """"512 x 512" for the upload toast; None for SVG or a missing file."""
        if not obj.logo or obj.logo.name.lower().endswith(".svg"):
            return None
        try:
            from PIL import Image

            with obj.logo.open("rb") as f, Image.open(f) as im:
                return f"{im.width} x {im.height}"
        except (OSError, ValueError):
            return None

    def validate_accent_color(self, v):
        if not HEX_RE.match(v):
            raise serializers.ValidationError("Use a colour like #2563EB.")
        return v.upper()


class LogoSerializer(serializers.Serializer):
    logo = serializers.FileField()

    def validate_logo(self, f):
        ext = f.name.rsplit(".", 1)[-1].lower()
        if ext not in IMAGE_EXTENSIONS + ["svg"]:
            raise serializers.ValidationError("Use a PNG, JPG, WebP or SVG.")
        if f.size > 5 * 1024 * 1024:
            raise serializers.ValidationError("The logo can be at most 5 MB.")
        if ext == "svg":
            text = f.read().decode("utf-8", "ignore").lower()
            f.seek(0)
            if "<svg" not in text or any(bad in text for bad in ("<script", "javascript:", "<foreignobject")) \
                    or re.search(r"\son[a-z]+\s*=", text):
                raise serializers.ValidationError("This SVG cannot be used. Try a PNG.")
            return f
        from PIL import Image, UnidentifiedImageError

        try:
            with Image.open(f) as im:
                w, h = im.size
        except (UnidentifiedImageError, OSError):
            raise serializers.ValidationError("This file is not an image.") from None
        f.seek(0)
        if w < 512 or h < 512:
            raise serializers.ValidationError(f"This logo is {w} x {h}. Use one at least 512 x 512.")
        return f


class RoleMatrixSerializer(serializers.Serializer):
    trainer = serializers.DictField(child=serializers.BooleanField())
    client = serializers.DictField(child=serializers.BooleanField())

    def validate(self, attrs):
        keys = {k for k, _ in ROLE_PERMISSIONS}
        for role in ("trainer", "client"):
            unknown = set(attrs[role]) - keys
            if unknown:
                raise serializers.ValidationError({role: [f"Unknown permission: {', '.join(sorted(unknown))}"]})
        return attrs


class IntegrationSerializer(serializers.ModelSerializer):
    label = serializers.CharField(source="get_kind_display", read_only=True)
    meta = serializers.SerializerMethodField()
    used = serializers.SerializerMethodField()

    class Meta:
        model = Integration
        fields = ["kind", "label", "status", "config", "meta", "used", "connected_at", "updated_at"]
        read_only_fields = fields

    def get_meta(self, obj):
        """The grey line at the bottom of the card."""
        from apps.notifications.models import NotificationSettings

        if obj.status == Integration.Status.NOT_CONNECTED:
            return "Not set up"
        if obj.kind == Integration.Kind.WHATSAPP:
            return NotificationSettings.load().whatsapp_number or "No business number yet"
        if obj.kind == Integration.Kind.EMAIL_DOMAIN:
            if obj.status == Integration.Status.PENDING:
                return "Sending from the platform address for now"
            return Integration.from_email() or "Sending from the platform address"
        n = (obj.config or {}).get("linked", 0)
        return f"{n} client{'' if n == 1 else 's'} linked" if n else "No clients linked yet"

    def get_used(self, obj):
        return (self.context.get("used") or {}).get(obj.kind, [])


class IntegrationConfigSerializer(serializers.Serializer):
    """What Connect / Save may change. WhatsApp: the business number; email: the sending domain;
    health: which data types are read."""

    number = serializers.CharField(required=False, allow_blank=True)
    domain = serializers.CharField(required=False)
    types = serializers.DictField(child=serializers.BooleanField(), required=False)

    def validate_number(self, v):
        v = " ".join(v.split())
        if not PHONE_RE.match(v):
            raise serializers.ValidationError("Use digits, spaces and + only, like +91 98200 12345.")
        return v

    def validate_domain(self, v):
        v = v.strip().lower().removeprefix("https://").removeprefix("http://").removeprefix("www.").rstrip("/")
        if not DOMAIN_RE.match(v):
            raise serializers.ValidationError("Enter a domain like trainwithvimal.com.")
        return v

    def validate_types(self, v):
        keys = {"steps", "sleep", "hr", "workouts"}
        if set(v) - keys:
            raise serializers.ValidationError("Unknown health data.")
        if not any(v.values()):
            raise serializers.ValidationError("Turn on at least one.")
        return {k: bool(v.get(k)) for k in sorted(keys)}
