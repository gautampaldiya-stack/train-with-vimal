from rest_framework import serializers


class UserMiniSerializer(serializers.Serializer):
    """The `who` cell used everywhere: avatar + name."""

    id = serializers.UUIDField()
    full_name = serializers.CharField()
    initials = serializers.CharField()
    avatar_color = serializers.CharField()
    avatar = serializers.ImageField(allow_null=True)
    role = serializers.CharField()


class BulkIdsSerializer(serializers.Serializer):
    ids = serializers.ListField(child=serializers.UUIDField(), allow_empty=False, max_length=500)
