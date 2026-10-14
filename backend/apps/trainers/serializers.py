from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework import serializers

from apps.accounts.models import Gender
from apps.accounts.serializers import PhoneField, email_or_phone_taken
from apps.common.validators import DOCUMENT_EXTENSIONS

from .models import AccessMode, AccessRequest, TrainerDocument, TrainerProfile
from .permissions_catalog import ALL_KEYS, GROUPS, VISIBILITY_DEFAULTS

User = get_user_model()


def _csv_list(value):
    """"Strength, Fat loss" -> ["Strength", "Fat loss"] (the drawer takes a comma list)."""
    if isinstance(value, list):
        items = value
    else:
        items = (value or "").split(",")
    out = []
    for item in items:
        item = " ".join(str(item).split())
        if item and item.lower() not in {o.lower() for o in out}:
            out.append(item[:40])
    return out[:12]


class CsvListField(serializers.Field):
    def to_internal_value(self, data):
        return _csv_list(data)

    def to_representation(self, value):
        return value


class TrainerRowSerializer(serializers.ModelSerializer):
    """One row of the Trainers table."""

    speciality = serializers.ListField(source="trainer_profile.speciality")
    max_clients = serializers.IntegerField(source="trainer_profile.max_clients")
    clients = serializers.SerializerMethodField()
    checkins_to_review = serializers.SerializerMethodField()
    adherence = serializers.SerializerMethodField()
    access_mode = serializers.CharField(source="trainer_profile.access_mode")
    access_label = serializers.SerializerMethodField()
    is_owner = serializers.BooleanField(source="trainer_profile.is_owner")
    is_full = serializers.SerializerMethodField()
    joining_date = serializers.DateField(source="trainer_profile.joining_date")

    class Meta:
        model = User
        fields = ["id", "full_name", "email", "phone", "initials", "avatar_color", "avatar", "status", "speciality",
                  "max_clients", "clients", "is_full", "checkins_to_review", "adherence", "access_mode",
                  "access_label", "is_owner", "joining_date", "last_seen_at"]

    def get_clients(self, obj):
        return obj.n_clients if hasattr(obj, "n_clients") else obj.trainer_profile.active_client_count

    def get_is_full(self, obj):
        return self.get_clients(obj) >= obj.trainer_profile.max_clients

    def get_checkins_to_review(self, obj):
        return getattr(obj, "n_review", 0)

    def get_adherence(self, obj):
        v = getattr(obj, "avg_adherence", None)
        return round(v) if v is not None else None

    def get_access_label(self, obj):
        tp = obj.trainer_profile
        if tp.access_mode == AccessMode.CUSTOM:
            on = sum(1 for v in tp.effective_permissions().values() if v)
            return f"Custom · {on} of {len(ALL_KEYS)}"
        return tp.get_access_mode_display()


class TrainerProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = TrainerProfile
        fields = ["speciality", "max_clients", "bio", "experience_since", "mode", "languages", "works_best_with",
                  "instagram", "youtube", "page_link", "website", "joining_date", "access_mode", "visibility",
                  "is_owner"]


class TrainerDetailSerializer(TrainerRowSerializer):
    profile = TrainerProfileSerializer(source="trainer_profile")
    permissions = serializers.SerializerMethodField()

    class Meta(TrainerRowSerializer.Meta):
        fields = TrainerRowSerializer.Meta.fields + ["gender", "date_of_birth", "city", "profile", "permissions",
                                                     "password_changed_at"]

    def get_permissions(self, obj):
        return obj.trainer_profile.effective_permissions()


class TrainerWriteSerializer(serializers.Serializer):
    """Add trainer drawer and Edit details drawer."""

    full_name = serializers.CharField(max_length=120)
    phone = PhoneField(max_length=20)
    email = serializers.EmailField()
    gender = serializers.ChoiceField(choices=Gender.choices, required=False, allow_blank=True)
    date_of_birth = serializers.DateField(required=False, allow_null=True)
    city = serializers.CharField(max_length=80, required=False, allow_blank=True)
    speciality = CsvListField(required=False)
    languages = CsvListField(required=False)
    max_clients = serializers.IntegerField(min_value=1, max_value=500, required=False)
    bio = serializers.CharField(max_length=1500, required=False, allow_blank=True)
    experience_since = serializers.IntegerField(min_value=1970, required=False, allow_null=True)
    mode = serializers.ChoiceField(choices=["gym", "online", "gym_online"], required=False)
    works_best_with = serializers.CharField(max_length=200, required=False, allow_blank=True)
    instagram = serializers.CharField(max_length=120, required=False, allow_blank=True)
    youtube = serializers.CharField(max_length=200, required=False, allow_blank=True)
    page_link = serializers.CharField(max_length=200, required=False, allow_blank=True)
    website = serializers.URLField(required=False, allow_blank=True)
    joining_date = serializers.DateField(required=False)
    access_mode = serializers.ChoiceField(choices=AccessMode.choices, required=False)
    send_invite = serializers.BooleanField(default=True)
    send_password_reset = serializers.BooleanField(default=False)

    PROFILE_FIELDS = ["speciality", "languages", "max_clients", "bio", "experience_since", "mode",
                      "works_best_with", "instagram", "youtube", "page_link", "website", "joining_date",
                      "access_mode"]

    def validate_full_name(self, v):
        v = " ".join(v.split())
        if len(v) < 2:
            raise serializers.ValidationError("Enter the full name.")
        return v

    def validate_experience_since(self, v):
        if v and v > timezone.localdate().year:
            raise serializers.ValidationError("Pick a year that has passed.")
        return v

    def validate(self, attrs):
        if "email" in attrs:
            attrs["email"] = attrs["email"].strip().lower()
        exclude = self.instance.id if self.instance else None
        clash = email_or_phone_taken(email=attrs.get("email"), phone=attrs.get("phone"), exclude_id=exclude)
        if clash == "phone":
            raise serializers.ValidationError({"phone": ["A trainer or client already uses this number."]})
        if clash == "email":
            raise serializers.ValidationError({"email": ["Someone already uses this email."]})
        if self.instance and "max_clients" in attrs:
            now = self.instance.trainer_profile.active_client_count
            if attrs["max_clients"] < now:
                raise serializers.ValidationError(
                    {"max_clients": [f"They have {now} clients now. Move some first or keep {now} or more."]})
        return attrs


class AccessSerializer(serializers.Serializer):
    access_mode = serializers.ChoiceField(choices=AccessMode.choices)
    permissions = serializers.DictField(child=serializers.BooleanField(), required=False)

    def validate_permissions(self, v):
        bad = [k for k in v if k not in ALL_KEYS]
        if bad:
            raise serializers.ValidationError(f"Unknown permission: {', '.join(bad)}")
        return v


class VisibilitySerializer(serializers.Serializer):
    def to_internal_value(self, data):
        if not isinstance(data, dict):
            raise serializers.ValidationError("Send the fields as on/off.")
        out = {}
        for k, v in data.items():
            if k not in VISIBILITY_DEFAULTS:
                raise serializers.ValidationError({k: "Unknown field."})
            out[k] = bool(v)
        out["photo_name"] = True  # locked
        return out


class MoveClientsSerializer(serializers.Serializer):
    """Move clients to another trainer. `to` = one trainer, or "share" between trainers with space."""

    to = serializers.CharField()
    clients = serializers.ListField(child=serializers.UUIDField(), required=False)
    tell_clients = serializers.BooleanField(default=True)


class AssignClientsSerializer(serializers.Serializer):
    clients = serializers.ListField(child=serializers.UUIDField(), allow_empty=False, max_length=200)
    tell_clients = serializers.BooleanField(default=True)
    keep_plans = serializers.BooleanField(default=True)


class DocumentSerializer(serializers.ModelSerializer):
    status = serializers.CharField(read_only=True)
    verified_by_name = serializers.CharField(source="verified_by.full_name", read_only=True, default=None)
    file_url = serializers.SerializerMethodField()

    class Meta:
        model = TrainerDocument
        fields = ["id", "kind", "name", "issuer", "issued_on", "expires_on", "visibility", "remind_before_expiry",
                  "file", "file_url", "verified_at", "verified_by_name", "signed", "status", "created_at"]
        read_only_fields = ["verified_at", "signed"]
        extra_kwargs = {"file": {"write_only": True}}

    def get_file_url(self, obj):
        req = self.context.get("request")
        return req.build_absolute_uri(obj.file.url) if req and obj.file else None

    def validate_file(self, f):
        ext = f.name.rsplit(".", 1)[-1].lower()
        if ext not in DOCUMENT_EXTENSIONS:
            raise serializers.ValidationError("Upload a PDF, JPG or PNG.")
        return f

    def validate(self, attrs):
        issued, expires = attrs.get("issued_on"), attrs.get("expires_on")
        if issued and expires and expires < issued:
            raise serializers.ValidationError({"expires_on": ["Expiry is before the issue date."]})
        return attrs


class AccessRequestSerializer(serializers.ModelSerializer):
    trainer = serializers.SerializerMethodField()

    class Meta:
        model = AccessRequest
        fields = ["id", "trainer", "permissions", "reason", "status", "decided_at", "created_at"]
        read_only_fields = ["status", "decided_at"]

    def get_trainer(self, obj):
        u = obj.trainer.user
        return {"id": str(u.id), "full_name": u.full_name, "initials": u.initials, "avatar_color": u.avatar_color}

    def validate_permissions(self, v):
        bad = [k for k in v if k not in ALL_KEYS]
        if bad or not v:
            raise serializers.ValidationError("Pick at least one access to ask for.")
        return list(dict.fromkeys(v))


def permission_groups(perms):
    """Access tab layout: groups with each permission's label, hint and current value."""
    return [
        {"group": g, "items": [{"key": k, "label": label, "hint": hint, "on": bool(perms.get(k))}
                               for k, label, hint in items]}
        for g, items in GROUPS
    ]


def public_trainer_card(user, request=None):
    """'My trainer' in the client app — only what the trainer switched on in 'What clients see'."""
    tp = user.trainer_profile
    vis = {**VISIBILITY_DEFAULTS, **(tp.visibility or {})}
    card = {
        "id": str(user.id),
        "full_name": user.full_name,
        "initials": user.initials,
        "avatar_color": user.avatar_color,
        "avatar": request.build_absolute_uri(user.avatar.url) if (request and user.avatar) else None,
    }
    if vis.get("speciality"):
        card["speciality"] = tp.speciality
    if vis.get("experience") and tp.experience_since:
        card["experience_years"] = max(0, timezone.localdate().year - tp.experience_since)
    if vis.get("about"):
        card["about"] = tp.bio
        card["works_best_with"] = tp.works_best_with
    if vis.get("languages"):
        card["languages"] = tp.languages
    if vis.get("certificates"):
        docs = tp.documents.filter(kind=TrainerDocument.Kind.CERTIFICATE, verified_at__isnull=False,
                                   visibility=TrainerDocument.Visibility.ADMINS_CLIENTS)
        card["certificates"] = [{"name": d.name, "issuer": d.issuer, "issued_on": d.issued_on} for d in docs]
    if vis.get("social"):
        card["social"] = {k: getattr(tp, k) for k in ("instagram", "youtube", "page_link", "website")
                          if getattr(tp, k)}
    if vis.get("mobile"):
        card["phone"] = user.phone
    if vis.get("email"):
        card["email"] = user.email
    return card
