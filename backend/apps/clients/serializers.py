import re
from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError as DjangoValidationError
from django.utils import timezone
from rest_framework import serializers

from apps.accounts.models import AccountStatus, Gender, Role
from apps.accounts.serializers import PhoneField, email_or_phone_taken

from .models import CLIENT_ONBOARDING_STEPS, ONBOARDING_LABELS, ONBOARDING_STEPS, Approval, ClientNote, ClientProfile, Goal, InviteLink

User = get_user_model()


def badge_for(user):
    """Status badge in the Clients table."""
    cp = user.client_profile
    if user.status == AccountStatus.ACTIVE:
        if cp.at_risk:
            return "at_risk"
        if cp.trainer_id is None:
            return "no_trainer"
    return user.status


class PersonMiniSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    full_name = serializers.CharField()
    initials = serializers.CharField()
    avatar_color = serializers.CharField()


def next_checkin(user, today=None):
    """The table's "Next check-in": weekly check-ins are due every Sunday. "Paused" / "—" (pending), "Overdue"
    when nothing came in the last 8 days (same rule as the Overdue filter), "Today" on a Sunday still due, else
    the Sunday it is due. Uses `last_weekly` when the list annotated it (one query for the page)."""
    from datetime import timedelta

    from apps.common.utils import dfmt

    if user.status == AccountStatus.PAUSED:
        return "Paused"
    if user.status != AccountStatus.ACTIVE:
        return "—"
    today = today or timezone.localdate()
    last = getattr(user, "last_weekly", "unset")
    if last == "unset":
        last = (user.submissions.filter(form_type="weekly").order_by("-date").values_list("date", flat=True).first())
    cp = user.client_profile
    started = cp.start_date or timezone.localdate(user.date_joined)
    sunday = today + timedelta(days=6 - today.weekday())
    if (last is None or last < today - timedelta(days=8)) and started <= today - timedelta(days=8):
        return "Overdue"
    if last is not None and last >= sunday - timedelta(days=6):  # this week's is in
        sunday += timedelta(days=7)
    elif sunday == today:
        return "Today"
    return dfmt(sunday, "%a, %-d %b")


def ago(dt, now=None):
    """"2 h ago", "1 d ago", "just now" ("—" when never)."""
    if not dt:
        return "—"
    secs = ((now or timezone.now()) - dt).total_seconds()
    if secs < 60 * 5:
        return "just now"
    if secs < 3600:
        return f"{int(secs // 60)} min ago"
    if secs < 86400:
        return f"{int(secs // 3600)} h ago"
    return f"{int(secs // 86400)} d ago"


class ClientRowSerializer(serializers.ModelSerializer):
    """One row of the Clients / My clients table."""

    goal_label = serializers.CharField(source="client_profile.get_goal_display")
    next_checkin = serializers.SerializerMethodField()
    last_active = serializers.SerializerMethodField()

    badge = serializers.SerializerMethodField()
    trainer = serializers.SerializerMethodField()
    onboarding = serializers.SerializerMethodField()
    goal = serializers.CharField(source="client_profile.goal")
    adherence_7d = serializers.IntegerField(source="client_profile.adherence_7d")
    at_risk_reason = serializers.CharField(source="client_profile.at_risk_reason")

    class Meta:
        model = User
        fields = ["id", "full_name", "email", "phone", "initials", "avatar_color", "avatar", "status", "badge", "gender",
                  "trainer", "onboarding", "goal", "goal_label", "adherence_7d", "at_risk_reason", "date_joined",
                  "last_seen_at", "last_active", "next_checkin"]

    def get_next_checkin(self, obj):
        return next_checkin(obj)

    def get_last_active(self, obj):
        return ago(obj.last_seen_at)

    def get_badge(self, obj):
        return badge_for(obj)

    def get_trainer(self, obj):
        t = obj.client_profile.trainer
        return PersonMiniSerializer(t).data if t else None

    def get_onboarding(self, obj):
        return obj.client_profile.onboarding_progress


class ClientProfileSerializer(serializers.ModelSerializer):
    onboarding_progress = serializers.DictField(read_only=True)
    has_health_note = serializers.BooleanField(read_only=True)

    class Meta:
        model = ClientProfile
        exclude = ["id", "user", "invite_link", "invited_by", "created_at", "removed_at"]
        read_only_fields = ["adherence_7d", "adherence_30d", "at_risk", "at_risk_reason", "stats_updated_at",
                            "last_reminded_at", "paused_at", "signup_source", "onboarding_done",
                            "onboarding_skipped_at", "updated_at", "trainer"]


class ClientDetailSerializer(ClientRowSerializer):
    profile = ClientProfileSerializer(source="client_profile")
    age = serializers.SerializerMethodField()
    options = serializers.SerializerMethodField()

    class Meta(ClientRowSerializer.Meta):
        fields = ClientRowSerializer.Meta.fields + ["date_of_birth", "age", "city", "profile", "options"]

    def get_age(self, obj):
        from .onboarding import age

        return age(obj)

    def get_options(self, obj):
        """Choices of the onboarding fields, for the Edit profile selects."""
        from .onboarding import edit_options

        return edit_options()


class ClientCreateSerializer(serializers.Serializer):
    """Add client drawer. Only name and mobile are needed."""

    full_name = serializers.CharField(max_length=120)
    phone = PhoneField(max_length=20)
    email = serializers.EmailField(required=False, allow_blank=True)
    gender = serializers.ChoiceField(choices=Gender.choices, required=False, allow_blank=True)
    date_of_birth = serializers.DateField(required=False, allow_null=True)
    city = serializers.CharField(max_length=80, required=False, allow_blank=True)
    goal = serializers.ChoiceField(choices=Goal.choices, required=False, allow_blank=True)
    current_weight_kg = serializers.DecimalField(max_digits=5, decimal_places=1, required=False, allow_null=True,
                                                 min_value=20, max_value=400)
    height_cm = serializers.DecimalField(max_digits=5, decimal_places=1, required=False, allow_null=True,
                                         min_value=80, max_value=250)
    target_weight_kg = serializers.DecimalField(max_digits=5, decimal_places=1, required=False, allow_null=True,
                                                min_value=20, max_value=400)
    health_notes = serializers.CharField(required=False, allow_blank=True, max_length=2000)
    trainer = serializers.PrimaryKeyRelatedField(queryset=User.objects.filter(role__in=[Role.TRAINER, Role.ADMIN]),
                                                 required=False, allow_null=True)
    program = serializers.UUIDField(required=False, allow_null=True)
    meal_plan = serializers.UUIDField(required=False, allow_null=True)
    start_date = serializers.DateField(required=False, allow_null=True)
    send_login_link = serializers.BooleanField(default=True)
    ask_parq = serializers.BooleanField(default=True)
    mode = serializers.ChoiceField(choices=["active", "approvals"], default="active")

    def validate_full_name(self, v):
        v = " ".join(v.split())
        if len(v) < 2:
            raise serializers.ValidationError("Enter the full name.")
        return v

    def validate(self, attrs):
        email = (attrs.get("email") or "").strip().lower() or None
        attrs["email"] = email
        clash = email_or_phone_taken(email=email, phone=attrs.get("phone"))
        if clash == "phone":
            raise serializers.ValidationError({"phone": ["A client or sign-up already uses this number."]})
        if clash == "email":
            raise serializers.ValidationError({"email": ["Someone already uses this email."]})
        user = self.context["request"].user
        if user.is_trainer and not user.trainer_profile.has_perm("clients.view_all"):
            attrs["trainer"] = user  # a trainer adds clients for themselves
        return attrs


class ClientUpdateSerializer(serializers.Serializer):
    full_name = serializers.CharField(max_length=120, required=False)
    phone = PhoneField(max_length=20, required=False)
    email = serializers.EmailField(required=False, allow_blank=True)
    gender = serializers.ChoiceField(choices=Gender.choices, required=False, allow_blank=True)
    date_of_birth = serializers.DateField(required=False, allow_null=True)
    city = serializers.CharField(max_length=80, required=False, allow_blank=True)
    goal = serializers.ChoiceField(choices=Goal.choices, required=False, allow_blank=True)
    height_cm = serializers.DecimalField(max_digits=5, decimal_places=1, required=False, allow_null=True,
                                         min_value=80, max_value=250)
    start_weight_kg = serializers.DecimalField(max_digits=5, decimal_places=1, required=False, allow_null=True,
                                               min_value=20, max_value=400)
    target_weight_kg = serializers.DecimalField(max_digits=5, decimal_places=1, required=False, allow_null=True,
                                                min_value=20, max_value=400)
    current_weight_kg = serializers.DecimalField(max_digits=5, decimal_places=1, required=False, allow_null=True,
                                                min_value=20, max_value=400)
    target_date = serializers.DateField(required=False, allow_null=True)
    health_notes = serializers.CharField(required=False, allow_blank=True, max_length=2000)
    start_date = serializers.DateField(required=False, allow_null=True)
    package_name = serializers.CharField(required=False, allow_blank=True, max_length=80)
    package_ends_on = serializers.DateField(required=False, allow_null=True)
    # Admin only (board ClientProfile → Edit profile → Sign-in): a new password; empty keeps the old one.
    password = serializers.CharField(required=False, allow_blank=True, trim_whitespace=False, write_only=True)

    def get_fields(self):
        """Plus every onboarding answer the coach can change in Edit profile (apps.clients.onboarding)."""
        from .onboarding import update_fields

        return {**super().get_fields(), **update_fields()}

    def validate(self, attrs):
        inst = self.instance
        clash = email_or_phone_taken(email=attrs.get("email") or None, phone=attrs.get("phone"), exclude_id=inst.id)
        if clash == "phone":
            raise serializers.ValidationError({"phone": ["Another account uses this number."]})
        if clash == "email":
            raise serializers.ValidationError({"email": ["Another account uses this email."]})
        pw = attrs.pop("password", "")
        if pw:
            from django.contrib.auth import password_validation

            if len(pw) < 8:
                raise serializers.ValidationError({"password": ["Use at least 8 characters."]})
            try:
                password_validation.validate_password(pw, inst)
            except DjangoValidationError as e:
                raise serializers.ValidationError({"password": list(e.messages)})
            attrs["_password"] = pw
        return attrs

    USER_FIELDS = {"full_name", "phone", "email", "gender", "date_of_birth", "city"}

    def update(self, instance, data):
        cp = instance.client_profile
        pw = data.pop("_password", None)
        if pw:
            instance.set_password(pw)
        for k, v in data.items():
            if k in self.USER_FIELDS:
                setattr(instance, k, v or None if k in ("email", "phone") else v)
            else:
                setattr(cp, k, v)
        instance.save()
        cp.save()
        return instance


class ChangeTrainerSerializer(serializers.Serializer):
    """Change trainer drawer (board ClientProfile): pick a trainer, what happens when she moves, a note."""

    trainer = serializers.PrimaryKeyRelatedField(queryset=User.objects.filter(role__in=[Role.TRAINER, Role.ADMIN],
                                                                              status=AccountStatus.ACTIVE))
    tell_client = serializers.BooleanField(default=True)
    # On: check-ins waiting for review go to the new trainer's queue. Off: they are marked as seen, so the new
    # trainer starts fresh.
    move_checkins = serializers.BooleanField(default=True)
    tell_old = serializers.BooleanField(default=False)
    note = serializers.CharField(required=False, allow_blank=True, max_length=2000)

    def validate_trainer(self, t):
        tp = getattr(t, "trainer_profile", None)
        if tp is None:
            raise serializers.ValidationError("Pick a trainer.")
        if tp.is_full:
            raise serializers.ValidationError(f"{t.full_name} is full. Pick a trainer with space.")
        return t


class RemindSerializer(serializers.Serializer):
    skip_recent_hours = serializers.IntegerField(default=24, min_value=0, max_value=168)
    message = serializers.CharField(required=False, allow_blank=True, max_length=300)


class ClientNoteSerializer(serializers.ModelSerializer):
    author = PersonMiniSerializer(read_only=True)

    class Meta:
        model = ClientNote
        fields = ["id", "body", "is_flag", "author", "created_at", "updated_at"]
        read_only_fields = ["id", "author", "created_at", "updated_at"]


# ---------------------------------------------------------------- invite links
class InviteLinkSerializer(serializers.ModelSerializer):
    trainer = PersonMiniSerializer(read_only=True)
    trainer_id = serializers.PrimaryKeyRelatedField(
        source="trainer", queryset=User.objects.filter(role__in=[Role.TRAINER, Role.ADMIN]), write_only=True,
        required=False,
    )
    url = serializers.SerializerMethodField()
    state = serializers.CharField(read_only=True)
    joined = serializers.IntegerField(read_only=True)
    waiting = serializers.IntegerField(read_only=True)

    class Meta:
        model = InviteLink
        fields = ["id", "code", "url", "trainer", "trainer_id", "label", "expires_at", "max_uses", "needs_approval",
                  "is_on", "state", "joined", "waiting", "created_at"]
        read_only_fields = ["id", "url", "state", "joined", "waiting", "created_at"]
        extra_kwargs = {"code": {"required": False}}

    def get_url(self, obj):
        from django.conf import settings

        return f"{settings.INVITE_BASE_URL.rstrip('/')}/{obj.code}"

    def validate_code(self, v):
        v = v.strip().upper()
        import re

        if not re.fullmatch(r"[A-Z0-9-]{4,24}", v):
            raise serializers.ValidationError("Use 4–24 letters, numbers or dashes.")
        qs = InviteLink.all_objects.filter(code=v)
        if self.instance:
            qs = qs.exclude(id=self.instance.id)
        if qs.exists():
            raise serializers.ValidationError("This code is taken. Try another.")
        return v

    def validate_expires_at(self, v):
        if v and v <= timezone.now():
            raise serializers.ValidationError("Pick a date in the future.")
        return v


class JoinSerializer(serializers.Serializer):
    """Sign-up form on the invite link page."""

    full_name = serializers.CharField(max_length=120)
    email = serializers.EmailField()
    phone = PhoneField(max_length=20)
    password = serializers.CharField(trim_whitespace=False)
    platform = serializers.ChoiceField(choices=["web", "android", "ios"], default="web")
    accept_terms = serializers.BooleanField()

    def validate_accept_terms(self, v):
        if not v:
            raise serializers.ValidationError("Please accept the terms of use and privacy policy.")
        return v

    def validate(self, attrs):
        from django.contrib.auth import password_validation

        attrs["email"] = attrs["email"].strip().lower()
        clash = email_or_phone_taken(email=attrs["email"], phone=attrs["phone"])
        if clash:
            raise serializers.ValidationError(
                {clash: ["An account already uses this. Log in instead, or ask the gym team for help."]}
            )
        password_validation.validate_password(attrs["password"], User(full_name=attrs["full_name"],
                                                                      email=attrs["email"]))
        return attrs


# ---------------------------------------------------------------- approvals
class ApprovalRowSerializer(serializers.ModelSerializer):
    client = ClientRowSerializer(read_only=True)
    signed_up_from_label = serializers.CharField(source="get_signed_up_from_display", read_only=True)
    setup_done = serializers.SerializerMethodField()
    invited_by = PersonMiniSerializer(read_only=True)
    decided_by = PersonMiniSerializer(read_only=True)
    assigned_trainer = PersonMiniSerializer(read_only=True)
    has_health_note = serializers.BooleanField(source="client.client_profile.has_health_note", read_only=True)
    waiting_hours = serializers.SerializerMethodField()
    reject_reason_label = serializers.CharField(source="get_reject_reason_display", read_only=True)

    class Meta:
        model = Approval
        fields = ["id", "client", "status", "invited_by", "signed_up_from", "signed_up_from_label", "setup_done",
                  "has_health_note", "waiting_hours",
                  "decided_by", "decided_at", "assigned_trainer", "reject_reason", "reject_reason_label", "message",
                  "moved_back", "created_at"]

    def get_waiting_hours(self, obj):
        return int((timezone.now() - obj.created_at).total_seconds() // 3600)

    def get_setup_done(self, obj):
        done = set(obj.client.client_profile.onboarding_done or [])
        return sum(1 for k in ONBOARDING_STEPS if k in done)


class ApprovalDetailSerializer(ApprovalRowSerializer):
    steps = serializers.SerializerMethodField()
    onboarding = serializers.JSONField(source="client.client_profile.onboarding", read_only=True)
    health_notes = serializers.CharField(source="client.client_profile.health_notes", read_only=True)
    answers = serializers.SerializerMethodField()
    invite_code = serializers.SerializerMethodField()

    class Meta(ApprovalRowSerializer.Meta):
        fields = ApprovalRowSerializer.Meta.fields + ["steps", "onboarding", "health_notes", "answers", "invite_code"]

    def get_answers(self, obj):
        from .onboarding import signup_summary

        return signup_summary(obj.client)

    def get_invite_code(self, obj):
        link = obj.client.client_profile.invite_link
        return link.code if link else ""

    def get_steps(self, obj):
        done = set(obj.client.client_profile.onboarding_done or [])
        return [{"key": k, "label": ONBOARDING_LABELS[k][0], "hint": ONBOARDING_LABELS[k][1], "done": k in done}
                for k in ONBOARDING_STEPS]


class ApproveSerializer(serializers.Serializer):
    trainer = serializers.PrimaryKeyRelatedField(queryset=User.objects.filter(role__in=[Role.TRAINER, Role.ADMIN],
                                                                              status=AccountStatus.ACTIVE))
    tell_client = serializers.BooleanField(default=True)
    ask_finish_setup = serializers.BooleanField(default=True)

    def validate_trainer(self, t):
        tp = getattr(t, "trainer_profile", None)
        if tp is None:
            raise serializers.ValidationError("Pick a trainer.")
        if tp.is_full:
            raise serializers.ValidationError(f"{t.full_name} is full. Pick a trainer with space.")
        return t


class RejectSerializer(serializers.Serializer):
    reason = serializers.ChoiceField(choices=Approval.RejectReason.choices)
    message = serializers.CharField(required=False, allow_blank=True, max_length=2000)
    tell_client = serializers.BooleanField(default=True)

    def validate(self, attrs):
        if attrs["reason"] == "other" and not attrs.get("message", "").strip():
            raise serializers.ValidationError({"message": ["Write the reason in the message."]})
        return attrs


class AskInfoSerializer(serializers.Serializer):
    message = serializers.CharField(required=False, allow_blank=True, max_length=2000)
    items = serializers.ListField(
        child=serializers.ChoiceField(choices=["setup", "health_form", "doctor_note", "photo", "phone"]),
        allow_empty=False, error_messages={"empty": "Pick at least one thing to ask for."},
    )
    channels = serializers.ListField(child=serializers.ChoiceField(choices=["email", "push", "in_app", "whatsapp"]),
                                     allow_empty=False, error_messages={"empty": "Pick at least one channel."})


class MoveBackSerializer(serializers.Serializer):
    tell_client = serializers.BooleanField(default=False)


# ---------------------------------------------------------------- client self onboarding
class OnboardingStepSerializer(serializers.Serializer):
    """One step of the client's profile setup (the gym's coaching form, D-36). `step` is a client step; the fields
    of each step and their rules are in apps.clients.onboarding.FIELDS. Errors come back per field key."""

    step = serializers.ChoiceField(choices=CLIENT_ONBOARDING_STEPS)
    data = serializers.DictField()

    def validate(self, attrs):
        from .onboarding import check_step

        clean, errors = check_step(attrs["step"], attrs["data"], self.context["request"].user)
        if errors:
            raise serializers.ValidationError(errors)
        attrs["clean"] = clean
        return attrs
