import re

from rest_framework import serializers

from apps.common.validators import IMAGE_EXTENSIONS

from .models import ROLE_PERMISSIONS, GymSettings, Integration

HEX_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")


class GymProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = GymSettings
        fields = ["name", "email", "phone", "address", "instagram", "timezone", "language", "tagline", "website", "whatsapp",
                  "support_hours", "coach_role", "coach_intro", "coach_stats"]

    def validate_timezone(self, v):
        import zoneinfo

        if v not in zoneinfo.available_timezones():
            raise serializers.ValidationError("Pick a time zone from the list.")
        return v


class BrandingSerializer(serializers.ModelSerializer):
    applied = serializers.SerializerMethodField()

    class Meta:
        model = GymSettings
        fields = ["logo", "accent_color", "theme", "branding_applied_at", "branding_draft", "applied"]
        read_only_fields = ["branding_applied_at", "applied", "logo"]

    def get_applied(self, obj):
        return not obj.branding_draft

    def validate_accent_color(self, v):
        if not HEX_RE.match(v):
            raise serializers.ValidationError("Use a colour like #2563EB.")
        return v.upper()


class LogoSerializer(serializers.Serializer):
    logo = serializers.ImageField()

    def validate_logo(self, f):
        if f.name.rsplit(".", 1)[-1].lower() not in IMAGE_EXTENSIONS + ["svg"]:
            raise serializers.ValidationError("Use a PNG, JPG, WebP or SVG.")
        if f.size > 5 * 1024 * 1024:
            raise serializers.ValidationError("The logo can be at most 5 MB.")
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

    class Meta:
        model = Integration
        fields = ["kind", "label", "status", "config", "connected_at", "updated_at"]
        read_only_fields = ["kind", "label", "status", "connected_at", "updated_at"]
