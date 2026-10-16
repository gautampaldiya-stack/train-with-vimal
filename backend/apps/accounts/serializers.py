from django.contrib.auth import authenticate, password_validation
from django.core.cache import cache
from django.db.models import Q
from django.utils.translation import gettext_lazy as _
from rest_framework import serializers

from apps.common.validators import IMAGE_EXTENSIONS, normalize_phone, validate_file_size, validate_phone

from .models import AccountStatus, Role, User, UserSession


def email_or_phone_taken(email=None, phone=None, exclude_id=None):
    """Business rule: one email / one mobile = one person, across every role."""
    q = Q()
    if email:
        q |= Q(email__iexact=email.strip())
    if phone:
        q |= Q(phone=normalize_phone(phone))
    if not q:
        return None
    qs = User.objects.filter(q)
    if exclude_id:
        qs = qs.exclude(id=exclude_id)
    hit = qs.first()
    if hit is None:
        return None
    if email and hit.email and hit.email.lower() == email.strip().lower():
        return "email"
    return "phone"


class PhoneField(serializers.CharField):
    def to_internal_value(self, data):
        value = super().to_internal_value(data)
        if not value:
            return None
        try:
            validate_phone(value)
        except Exception:
            raise serializers.ValidationError(_("Enter a valid mobile number, e.g. +91 98200 12345."))
        return normalize_phone(value)


class UserSerializer(serializers.ModelSerializer):
    initials = serializers.CharField(read_only=True)
    avatar_color = serializers.CharField(read_only=True)
    first_name = serializers.CharField(read_only=True)
    email_verified = serializers.SerializerMethodField()
    client = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            "id", "email", "phone", "full_name", "first_name", "initials", "avatar_color", "avatar", "role",
            "status", "gender", "date_of_birth", "city", "email_verified", "pending_email",
            "unit_weight", "unit_length", "unit_water", "timezone", "week_start", "theme", "share_photos",
            "usage_data", "date_joined", "last_seen_at", "deletion_requested_at", "client",
        ]
        read_only_fields = fields

    def get_email_verified(self, obj):
        return obj.email_verified_at is not None

    def get_client(self, obj):
        """Clients only: what the app needs right after log in (approval wait, setup steps, coach name)."""
        cp = getattr(obj, "client_profile", None) if obj.role == Role.CLIENT else None
        if cp is None:
            return None
        t = cp.trainer
        return {
            "setup_done": cp.client_steps_done,
            "setup_total": 5,
            "setup_later": cp.onboarding_skipped_at is not None,
            "coach": {"id": t.id, "full_name": t.full_name, "first_name": t.first_name} if t else None,
        }


class MeUpdateSerializer(serializers.ModelSerializer):
    """What a person may change on their own profile. Role and status are not here. The mobile number
    can be changed from More → Edit profile (board ClientMore); during setup it is locked
    ("only Aman can change it", board ClientJoinLink)."""

    avatar = serializers.ImageField(required=False, allow_null=True,
                                    validators=[validate_file_size(10)])
    email = serializers.EmailField(required=False)
    phone = serializers.CharField(required=False, max_length=20)

    class Meta:
        model = User
        fields = ["full_name", "avatar", "gender", "date_of_birth", "city", "email", "phone", "unit_weight",
                  "unit_length", "unit_water", "timezone", "week_start", "theme", "share_photos", "usage_data"]

    def validate_phone(self, v):
        validate_phone(v)
        v = normalize_phone(v)
        if v != self.instance.phone and email_or_phone_taken(phone=v, exclude_id=self.instance.id):
            raise serializers.ValidationError("Another account already uses this mobile number.")
        return v

    def validate_full_name(self, v):
        v = " ".join(v.split())
        if len(v) < 2:
            raise serializers.ValidationError("Enter your full name.")
        return v

    def validate_avatar(self, f):
        if f and f.name.rsplit(".", 1)[-1].lower() not in IMAGE_EXTENSIONS:
            raise serializers.ValidationError("Use a JPG, PNG or WebP image.")
        return f

    def validate_email(self, v):
        v = v.strip().lower()
        if email_or_phone_taken(email=v, exclude_id=self.instance.id):
            raise serializers.ValidationError("Another account already uses this email.")
        return v


class LoginSerializer(serializers.Serializer):
    identifier = serializers.CharField(help_text="Email or mobile number")
    password = serializers.CharField(trim_whitespace=False, style={"input_type": "password"})
    device_name = serializers.CharField(required=False, allow_blank=True, max_length=120)
    platform = serializers.ChoiceField(choices=["android", "ios", "web"], required=False)

    MAX_TRIES = 5
    LOCK_SECONDS = 15 * 60

    def validate(self, attrs):
        key = "login-fail:" + attrs["identifier"].strip().lower()
        tries = cache.get(key, 0)
        if tries >= self.MAX_TRIES:
            raise serializers.ValidationError(
                {"non_field_errors": [_("Too many tries. Wait 15 minutes, or reset your password.")]}, code="locked"
            )
        user = authenticate(self.context.get("request"), username=attrs["identifier"], password=attrs["password"])
        if user is None:
            tries += 1
            cache.set(key, tries, self.LOCK_SECONDS)
            left = self.MAX_TRIES - tries
            if left <= 0:
                raise serializers.ValidationError(
                    {"non_field_errors": [_("Too many tries. Wait 15 minutes, or reset your password.")]}, code="locked"
                )
            raise serializers.ValidationError(
                {"password": [_("Wrong password. Tap the field to type it again, or reset it.")],
                 "tries_left": [str(left)]}, code="invalid_login"
            )
        cache.delete(key)
        if user.status == AccountStatus.REJECTED:
            raise serializers.ValidationError(
                {"non_field_errors": [_("Your sign-up was not approved. Talk to the gym team.")]}, code="rejected"
            )
        if user.status == AccountStatus.DEACTIVATED:
            raise serializers.ValidationError(
                {"non_field_errors": [_("This account was turned off by the gym.")]}, code="deactivated"
            )
        attrs["user"] = user
        return attrs


class RefreshSerializer(serializers.Serializer):
    refresh = serializers.CharField()


class PasswordChangeSerializer(serializers.Serializer):
    current_password = serializers.CharField(trim_whitespace=False)
    new_password = serializers.CharField(trim_whitespace=False)

    def validate_current_password(self, v):
        if not self.context["request"].user.check_password(v):
            raise serializers.ValidationError("Your current password is not right.")
        return v

    def validate(self, attrs):
        password_validation.validate_password(attrs["new_password"], self.context["request"].user)
        if attrs["new_password"] == attrs["current_password"]:
            raise serializers.ValidationError({"new_password": ["Pick a password you have not used just now."]})
        return attrs


class ForgotPasswordSerializer(serializers.Serializer):
    identifier = serializers.CharField(help_text="Email or mobile number")


class TokenSerializer(serializers.Serializer):
    token = serializers.CharField(max_length=200)


class SetPasswordSerializer(TokenSerializer):
    password = serializers.CharField(trim_whitespace=False)
    confirm_password = serializers.CharField(trim_whitespace=False)

    def validate(self, attrs):
        if attrs["password"] != attrs["confirm_password"]:
            raise serializers.ValidationError({"confirm_password": ["The two passwords do not match."]})
        return attrs


class SessionSerializer(serializers.ModelSerializer):
    this_device = serializers.SerializerMethodField()

    class Meta:
        model = UserSession
        fields = ["id", "device_name", "platform", "city", "ip_address", "last_active_at", "created_at",
                  "this_device"]

    def get_this_device(self, obj):
        auth = getattr(self.context.get("request"), "auth", None)
        return bool(auth and str(auth.get("sid")) == str(obj.id))
