from rest_framework import serializers

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

CHANNEL_LIMITS = {"push": 120, "whatsapp": 1000, "email": 2000, "in_app": 500}
SUBJECT_LIMIT = 50


class NotificationSerializer(serializers.ModelSerializer):
    actor_name = serializers.CharField(source="actor.full_name", default=None)
    actor_initials = serializers.CharField(source="actor.initials", default=None)

    class Meta:
        model = Notification
        fields = ["id", "event", "title", "body", "data", "read_at", "created_at", "actor", "actor_name",
                  "actor_initials"]
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

    class Meta:
        model = MessageTemplate
        fields = ["id", "key", "name", "group", "is_custom", "channels", "updated_at"]
        read_only_fields = ["id", "key", "is_custom", "updated_at"]

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


class TeamAlertSettingSerializer(serializers.ModelSerializer):
    label = serializers.CharField(source="get_event_display", read_only=True)

    class Meta:
        model = TeamAlertSetting
        fields = ["id", "event", "label", "channels"]
        read_only_fields = ["id", "event", "label"]


class NotificationSettingsSerializer(serializers.ModelSerializer):
    class Meta:
        model = NotificationSettings
        exclude = ["id"]


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
