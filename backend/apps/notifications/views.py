from django.db.models import Case, Count, Q, Value, When
from django.utils import timezone
from django.utils.text import slugify
from rest_framework import generics, mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import SAFE_METHODS, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.pagination import TimelineCursorPagination
from apps.common.permissions import HasTrainerPermission, IsAdmin, IsStaff

from .defaults import TEMPLATES, default_channels_for
from .models import (
    ALL_CHANNELS,
    Delivery,
    DeviceToken,
    GymNews,
    MessageTemplate,
    Notification,
    NotificationSettings,
    ReminderPreference,
    StaffNotificationPreference,
    TeamAlertSetting,
)
from .realtime import send_to_user
from .rendering import VARIABLES, context_for, render
from .serializers import (
    DeviceTokenSerializer,
    GymNewsSerializer,
    MessageTemplateSerializer,
    NewTemplateSerializer,
    NotificationSerializer,
    NotificationSettingsSerializer,
    ReminderPreferenceSerializer,
    StaffNotificationPreferenceSerializer,
    TeamAlertSettingSerializer,
    used_in_map,
)
from .services import unread_count


class NotificationViewSet(mixins.ListModelMixin, mixins.DestroyModelMixin, viewsets.GenericViewSet):
    """Bell panel / Notifications page. ?unread=1 for the Unread tab."""

    serializer_class = NotificationSerializer
    pagination_class = TimelineCursorPagination
    allow_inactive_account = True  # a pending client still sees "account approved" etc.

    def get_queryset(self):
        qs = Notification.objects.filter(recipient=self.request.user, in_app=True).select_related("actor")
        if self.request.query_params.get("unread") in ("1", "true"):
            qs = qs.filter(read_at__isnull=True)
        return qs

    def _push_unread(self):
        send_to_user(self.request.user.id, "unread", {"count": unread_count(self.request.user)})

    @action(detail=False)
    def unread(self, request):
        return Response({"count": unread_count(request.user)})

    @action(detail=True, methods=["post"])
    def read(self, request, pk=None):
        n = self.get_object()
        n.read_at = n.read_at or timezone.now()
        n.save(update_fields=["read_at", "updated_at"])
        self._push_unread()
        return Response(self.get_serializer(n).data)

    @action(detail=True, methods=["post"])
    def unread_one(self, request, pk=None):
        n = self.get_object()
        n.read_at = None
        n.save(update_fields=["read_at", "updated_at"])
        self._push_unread()
        return Response(self.get_serializer(n).data)

    @action(detail=False, methods=["post"])
    def read_all(self, request):
        updated = self.get_queryset().filter(read_at__isnull=True).update(read_at=timezone.now())
        self._push_unread()
        return Response({"updated": updated})

    def perform_destroy(self, instance):
        instance.delete()
        self._push_unread()


class DeviceTokenView(APIView):
    """POST registers this phone/browser for push. DELETE (with token) removes it on logout."""

    allow_inactive_account = True

    def post(self, request):
        s = DeviceTokenSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        sid = request.auth.get("sid") if request.auth else None
        DeviceToken.objects.update_or_create(
            token=s.validated_data["token"],
            defaults={"user": request.user, "platform": s.validated_data["platform"], "session_id": sid},
        )
        return Response(status=status.HTTP_204_NO_CONTENT)

    def delete(self, request):
        DeviceToken.objects.filter(user=request.user, token=request.data.get("token", "")).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class ReminderPreferenceView(generics.RetrieveUpdateAPIView):
    serializer_class = ReminderPreferenceSerializer

    def get_object(self):
        return ReminderPreference.objects.get_or_create(user=self.request.user)[0]

    def post(self, request):
        """Reset to recommended."""
        obj = self.get_object()
        for k, v in ReminderPreference.RECOMMENDED.items():
            setattr(obj, k, v)
        obj.save()
        obj.refresh_from_db()
        return Response(self.get_serializer(obj).data)


class StaffNotificationPreferenceView(generics.RetrieveUpdateAPIView):
    serializer_class = StaffNotificationPreferenceSerializer
    permission_classes = [IsStaff]

    def get_object(self):
        return StaffNotificationPreference.objects.get_or_create(user=self.request.user)[0]


class MessageTemplateViewSet(viewsets.ModelViewSet):
    """Emails & alerts → Client messages (admin only). A trainer who may build automations can read the list
    to pick a message for a Send message step."""

    serializer_class = MessageTemplateSerializer
    permission_classes = [IsAdmin]
    required_permission = "automations.manage"

    def get_permissions(self):
        if self.request.method in SAFE_METHODS:
            return [HasTrainerPermission()]
        return super().get_permissions()
    pagination_class = None

    def get_queryset(self):
        """Built-in messages in the board's order, then custom ones oldest first."""
        order = Case(*[When(key=k, then=Value(i)) for i, (k, *_r) in enumerate(TEMPLATES)], default=Value(len(TEMPLATES)))
        return MessageTemplate.objects.order_by(order, "created_at")

    def get_serializer_context(self):
        ctx = super().get_serializer_context()
        ctx["used_in"] = used_in_map()
        return ctx

    def create(self, request, *args, **kwargs):
        s = NewTemplateSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        base = d.get("key") or slugify(d["name"])[:50] or "template"
        key, i = base, 2
        while MessageTemplate.objects.filter(key=key).exists():
            key, i = f"{base}-{i}", i + 1
        texts = d.get("texts") or {}
        channels = {
            ch: {"subject": "", "title": "", "body": "", **texts.get(ch, {}), "on": ch in d["channels"]}
            for ch in ("email", "push", "whatsapp", "in_app")
        }
        tpl = MessageTemplate.objects.create(
            key=key, name=d["name"], group=d["group"], is_custom=True,
            channels=channels, default_channels=channels,
        )
        return Response(self.get_serializer(tpl).data, status=status.HTTP_201_CREATED)

    def perform_update(self, serializer):
        serializer.save()

    def destroy(self, request, *args, **kwargs):
        tpl = self.get_object()
        if not tpl.is_custom:
            return Response({"error": {"code": "built_in", "message": "Built-in messages cannot be deleted."}},
                            status=status.HTTP_400_BAD_REQUEST)
        tpl.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["post"])
    def reset(self, request, pk=None):
        tpl = self.get_object()
        tpl.channels = tpl.default_channels or default_channels_for(tpl.key) or tpl.channels
        tpl.save(update_fields=["channels", "updated_at"])
        return Response(self.get_serializer(tpl).data)

    @action(detail=True, methods=["get"])
    def preview(self, request, pk=None):
        """Filled in for a sample client (design: "How Sana, a sample client, would see it")."""
        tpl = self.get_object()
        ctx = context_for(request.user, {"first_name": "Sana", "coach_name": "Aman Verma",
                                         "package_name": "Quarterly Transformation"})
        return Response({
            ch: {k: render(v, ctx) if isinstance(v, str) else v for k, v in cfg.items()}
            for ch, cfg in tpl.channels.items()
        })

    @action(detail=False)
    def variables(self, request):
        return Response(VARIABLES)

    @action(detail=False)
    def stats(self, request):
        """This month: messages sent, % delivered, % opened (Automations stat card)."""
        start = timezone.localdate().replace(day=1)
        qs = Delivery.objects.filter(created_at__date__gte=start).exclude(status=Delivery.Status.SKIPPED)
        agg = qs.aggregate(
            total=Count("id"),
            delivered=Count("id", filter=Q(status__in=["sent", "delivered", "opened"])),
            opened=Count("id", filter=Q(status="opened")),
        )
        total = agg["total"] or 0
        return Response({
            "sent": total,
            "delivered_pct": round(100 * agg["delivered"] / total) if total else 0,
            "opened_pct": round(100 * agg["opened"] / total) if total else 0,
        })


class TeamAlertSettingViewSet(mixins.ListModelMixin, mixins.UpdateModelMixin, viewsets.GenericViewSet):
    """Emails & alerts → Team alerts: which channels each team alert goes out on."""

    serializer_class = TeamAlertSettingSerializer
    permission_classes = [IsAdmin]
    pagination_class = None

    def get_queryset(self):
        order = {e: i for i, e in enumerate(TeamAlertSetting.Event.values)}
        return sorted(TeamAlertSetting.objects.all(), key=lambda r: order.get(r.event, 99))

    def get_object(self):
        obj = generics.get_object_or_404(TeamAlertSetting.objects.all(), pk=self.kwargs["pk"])
        self.check_object_permissions(self.request, obj)
        return obj

    @action(detail=False, methods=["post"], url_path="enable-all")
    def enable_all(self, request):
        TeamAlertSetting.objects.update(channels={c: True for c in ALL_CHANNELS})
        return Response(self.get_serializer(self.get_queryset(), many=True).data)


class NotificationSettingsView(generics.RetrieveUpdateAPIView):
    """Quiet hours, daily digest and sender identity."""

    serializer_class = NotificationSettingsSerializer
    permission_classes = [IsAdmin]

    def get_object(self):
        return NotificationSettings.load()


class GymNewsViewSet(mixins.ListModelMixin, mixins.CreateModelMixin, viewsets.GenericViewSet):
    """Admin → Gym news: post a notice to the team. Each trainer with Gym news on gets it in the bell (and push).
    The admin screen comes with the admin screens; this is the API it will use."""

    serializer_class = GymNewsSerializer
    permission_classes = [IsAdmin]

    def get_queryset(self):
        return GymNews.objects.select_related("author")

    def perform_create(self, serializer):
        from .staff import send_gym_news

        send_gym_news(serializer.save(author=self.request.user))
