from rest_framework import serializers

from .models import ActivityEvent


class ActivityEventSerializer(serializers.ModelSerializer):
    actor_initials = serializers.SerializerMethodField()
    actor_avatar_color = serializers.SerializerMethodField()
    client_name = serializers.CharField(source="client.full_name", default=None)

    class Meta:
        model = ActivityEvent
        fields = [
            "id",
            "created_at",
            "actor",
            "actor_type",
            "actor_label",
            "actor_initials",
            "actor_avatar_color",
            "source",
            "kind",
            "verb",
            "target_type",
            "target_id",
            "target_label",
            "change_from",
            "change_to",
            "client",
            "client_name",
            "trainer",
            "meta",
        ]

    def get_actor_initials(self, obj):
        from apps.common.utils import initials

        return initials(obj.actor_label)

    def get_actor_avatar_color(self, obj):
        from apps.common.utils import avatar_color

        return avatar_color(obj.actor_label)
