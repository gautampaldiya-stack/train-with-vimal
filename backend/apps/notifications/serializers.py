import re

from rest_framework import serializers

from .defaults import CUSTOM_WHEN, SENT_BY, TEAM_ALERT_NOTES, WHEN

from .models import (
    ALL_CHANNELS,
    DeviceToken,
    GymNews,
    MessageTemplate,
    Notification,
    NotificationSettings,
    ReminderPreference,
    StaffNotificationPreference,
    TeamAlertSetting,
)

CH_LABEL = {"email": "Email", "push": "Push", "whatsapp": "WhatsApp", "in_app": "In-app"}
CHANNEL_LIMITS = {"push": 120, "whatsapp": 1000, "email": 2000, "in_app": 500}
SUBJECT_LIMIT = 50


def used_in_map():
    """Where it is used: {template key: [{"id", "name", "line"}]}, from the Send message steps of every
    automation (board lines "Step 3 · Push and WhatsApp" and "Steps 1 and 3")."""
    from apps.automations.models import Automation

    out = {}
    for a in Automation.objects.prefetch_related("steps").order_by("created_at"):
        hits = {}
        for i, st in enumerate(a.steps.all(), 1):
            if st.kind == "message" and (st.config or {}).get("template"):
                hits.setdefault(st.config["template"], []).append((i, st.config.get("channels") or []))
        for key, rows in hits.items():
            if len(rows) == 1:
                i, chans = rows[0]
                names = " and ".join(CH_LABEL[c] for c in chans if c in CH_LABEL)
                line = f"Step {i}" + (f" · {names}" if names else "")
            else:
                nums = [str(i) for i, _ in rows]
                line = "Steps " + ", ".join(nums[:-1]) + " and " + nums[-1]
            out.setdefault(key, []).append({"id": str(a.id), "name": a.name, "status": a.status, "line": line})
    return out


class NotificationSerializer(serializers.ModelSerializer):
    actor_name = serializers.CharField(source="actor.full_name", default=None)
    actor_initials = serializers.CharField(source="actor.initials", default=None)
    actor_color = serializers.CharField(source="actor.avatar_color", default=None)

    class Meta:
        model = Notification
        fields = ["id", "event", "title", "body", "data", "read_at", "created_at", "actor", "actor_name",
                  "actor_initials", "actor_color"]
        read_only_fields = fields


class DeviceTokenSerializer(serializers.ModelSerializer):
    class Meta:
        model = DeviceToken
        fields = ["token", "platform"]

    def validate_token(self, value):
        if len(value) < 20:
            raise serializers.ValidationError("This is not a valid device token.")
        return value


class ReminderPreferenceSerializer(serializers.ModelSerializer):
    class Meta:
        model = ReminderPreference
        exclude = ["user"]


class StaffNotificationPreferenceSerializer(serializers.ModelSerializer):
    class Meta:
        model = StaffNotificationPreference
        exclude = ["user", "id"]


class ChannelTextSerializer(serializers.Serializer):
    on = serializers.BooleanField()
    subject = serializers.CharField(required=False, allow_blank=True, max_length=SUBJECT_LIMIT)
    title = serializers.CharField(required=False, allow_blank=True, max_length=SUBJECT_LIMIT)
    body = serializers.CharField(required=False, allow_blank=True)


class MessageTemplateSerializer(serializers.ModelSerializer):
    channels = serializers.DictField(child=ChannelTextSerializer())
    when = serializers.SerializerMethodField()
    sent_by = serializers.SerializerMethodField()
    used_in = serializers.SerializerMethodField()

    class Meta:
        model = MessageTemplate
        fields = ["id", "key", "name", "group", "is_custom", "channels", "when", "sent_by", "used_in", "updated_at"]
        read_only_fields = ["id", "key", "is_custom", "updated_at"]

    def get_when(self, obj):
        return CUSTOM_WHEN if obj.is_custom else WHEN.get(obj.key, CUSTOM_WHEN)

    def get_sent_by(self, obj):
        return "" if obj.is_custom else SENT_BY.get(obj.key, "")

    def get_used_in(self, obj):
        used = self.context.get("used_in")
        if used is None:
            used = used_in_map()
        return used.get(obj.key, [])

    def validate_channels(self, value):
        unknown = set(value) - set(ALL_CHANNELS)
        if unknown:
            raise serializers.ValidationError(f"Unknown channel: {', '.join(sorted(unknown))}.")
        if not any(cfg.get("on") for cfg in value.values()):
            raise serializers.ValidationError("A template needs at least one channel.")
        for ch, cfg in value.items():
            limit = CHANNEL_LIMITS[ch]
            if len(cfg.get("body", "")) > limit:
                raise serializers.ValidationError(f"{ch}: the message can be at most {limit} characters.")
            if cfg.get("on") and not cfg.get("body", "").strip():
                raise serializers.ValidationError(f"{ch}: write the text, or turn this channel off.")
            if ch == "email" and cfg.get("on") and not cfg.get("subject", "").strip():
                raise serializers.ValidationError("email: add a subject.")
        return value


class NewTemplateSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=80)
    group = serializers.ChoiceField(choices=["access", "coaching", "packages"])
    channels = serializers.ListField(child=serializers.ChoiceField(choices=ALL_CHANNELS), allow_empty=False,
                                     error_messages={"empty": "Pick a channel. A template needs at least one."})
    # Undo after "Delete template": the deleted text comes back as it was, under its old key when free.
    texts = serializers.DictField(child=ChannelTextSerializer(), required=False)
    key = serializers.SlugField(max_length=60, required=False)

    def validate_name(self, v):
        v = v.strip()
        if not v:
            raise serializers.ValidationError("Give the template a name.")
        return v


class TeamAlertSettingSerializer(serializers.ModelSerializer):
    label = serializers.CharField(source="get_event_display", read_only=True)
    description = serializers.SerializerMethodField()

    class Meta:
        model = TeamAlertSetting
        fields = ["id", "event", "label", "description", "channels"]
        read_only_fields = ["id", "event", "label", "description"]

    def get_description(self, obj):
        return TEAM_ALERT_NOTES.get(obj.event, "")

    def validate_channels(self, value):
        unknown = set(value) - set(ALL_CHANNELS)
        if unknown:
            raise serializers.ValidationError(f"Unknown channel: {', '.join(sorted(unknown))}.")
        return {c: bool(value.get(c)) for c in ALL_CHANNELS}


class NotificationSettingsSerializer(serializers.ModelSerializer):
    class Meta:
        model = NotificationSettings
        exclude = ["id"]
        extra_kwargs = {"sender_name": {"error_messages": {"blank": "Add the name clients see."}}}

    def validate_sender_name(self, v):
        v = v.strip()
        if not v:
            raise serializers.ValidationError("Add the name clients see.")
        return v

    def validate_whatsapp_number(self, v):
        v = " ".join(v.split())
        if v and not re.fullmatch(r"\+?[0-9 ]{8,18}", v):
            raise serializers.ValidationError("Use digits, like +91 98200 12345.")
        return v


class GymNewsSerializer(serializers.ModelSerializer):
    author_name = serializers.CharField(source="author.full_name", default=None, read_only=True)

    class Meta:
        model = GymNews
        fields = ["id", "title", "body", "sent_to", "author_name", "created_at"]
        read_only_fields = ["id", "sent_to", "author_name", "created_at"]

    def validate_title(self, v):
        v = v.strip()
        if not v:
            raise serializers.ValidationError("Write a title.")
        return v

    def validate_body(self, v):
        if len(v) > 2000:
            raise serializers.ValidationError("Keep it under 2,000 characters.")
        return v.strip()
