from django.db import transaction
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.activity.services import log as activity_log
from apps.common.permissions import IsAdmin

from . import integrations
from .models import DEFAULT_ROLE_MATRIX, LOCKED_CELLS, ROLE_PERMISSIONS, GymSettings, Integration, RoleMatrix
from .serializers import (LANGUAGES, BrandingSerializer, GymProfileSerializer, IntegrationConfigSerializer,
                          IntegrationSerializer, LogoSerializer, RoleMatrixSerializer)

# Fields of the Gym profile card; saving one of them moves "Last saved".
PROFILE_FIELDS = {"name", "email", "phone", "address", "instagram", "website", "youtube", "facebook"}
# Timezone select on Regional & defaults (board: "Asia/Kolkata (IST)").
TIMEZONES = [
    ("Asia/Kolkata", "Asia/Kolkata (IST)"), ("Asia/Dubai", "Asia/Dubai (GST)"), ("Asia/Singapore", "Asia/Singapore (SGT)"),
    ("Europe/London", "Europe/London (UK)"), ("America/New_York", "America/New_York (ET)"),
    ("America/Los_Angeles", "America/Los_Angeles (PT)"), ("Australia/Sydney", "Australia/Sydney (AET)"),
]


class PublicGymView(APIView):
    """Gym name, contact and live branding. Public: the signed-out "Need help logging in?" sheet uses it too."""

    permission_classes = [AllowAny]
    allow_inactive_account = True

    def get(self, request):
        g = GymSettings.load()
        return Response({
            "name": g.name, "email": g.email, "phone": g.phone, "address": g.address, "instagram": g.instagram,
            "youtube": g.youtube, "facebook": g.facebook,
            "logo": request.build_absolute_uri(g.logo.url) if g.logo else None,
            "accent_color": g.accent_color, "theme": g.theme, "timezone": g.timezone,
            "tagline": g.tagline, "website": g.website, "whatsapp": g.whatsapp or g.phone, "hours": g.support_hours,
            "coach": _head_coach(g, request),
        })


def _head_coach(g, request):
    """The About page's coach card: the admin's name and photo plus the gym's words about them."""
    from apps.accounts.models import User

    admin = User.objects.filter(role="admin", is_active=True).order_by("date_joined").first()
    name = (admin.first_name or admin.get_full_name() or "Vimal") if admin else "Vimal"
    photo = getattr(admin, "avatar", None) if admin else None
    return {"name": name, "role": g.coach_role, "intro": g.coach_intro,
            "photo": request.build_absolute_uri(photo.url) if photo else None,
            "stats": [{"value": v, "label": lbl} for v, lbl in (g.coach_stats or [])]}


class GymProfileView(APIView):
    permission_classes = [IsAdmin]

    def _out(self, g):
        return {**GymProfileSerializer(g).data, "timezones": [{"value": v, "label": lbl} for v, lbl in TIMEZONES],
                "languages": [{"value": v, "label": lbl} for v, lbl in LANGUAGES.items()]}

    def get(self, request):
        return Response(self._out(GymSettings.load()))

    def patch(self, request):
        g = GymSettings.load()
        s = GymProfileSerializer(g, data=request.data, partial=True)
        s.is_valid(raise_exception=True)
        profile = bool(PROFILE_FIELDS & set(s.validated_data))
        g = s.save(**({"profile_saved_at": timezone.now()} if profile else {}))
        activity_log("updated the gym profile" if profile else "changed the regional defaults", "system",
                     actor=request.user)
        return Response(self._out(g))


class BrandingView(APIView):
    """PATCH saves a draft ("Not applied yet"); POST apply makes it live for every client."""

    permission_classes = [IsAdmin]

    def get(self, request):
        return Response(BrandingSerializer(GymSettings.load(), context={"request": request}).data)

    def patch(self, request):
        g = GymSettings.load()
        s = BrandingSerializer(g, data=request.data, partial=True)
        s.is_valid(raise_exception=True)
        draft = {**g.branding_draft, **s.validated_data}
        # Picking the live value again is not a change: the footer goes back to "Applied".
        g.branding_draft = {k: v for k, v in draft.items() if getattr(g, k) != v}
        g.save(update_fields=["branding_draft", "updated_at"])
        return Response(BrandingSerializer(g, context={"request": request}).data)


class BrandingApplyView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request):
        g = GymSettings.load()
        for k, v in g.branding_draft.items():
            setattr(g, k, v)
        g.branding_draft = {}
        g.branding_applied_at = timezone.now()
        g.save()
        activity_log("applied new branding", "system", actor=request.user)
        return Response(BrandingSerializer(g, context={"request": request}).data)


class BrandingResetView(APIView):
    """Reset: blue and the light theme, live at once (board toast "Branding reset · Blue and light theme")."""

    permission_classes = [IsAdmin]

    def post(self, request):
        g = GymSettings.load()
        g.accent_color, g.theme, g.branding_draft = "#2563EB", "light", {}
        g.branding_applied_at = timezone.now()
        g.save()
        activity_log("reset the branding", "system", actor=request.user)
        return Response(BrandingSerializer(g, context={"request": request}).data)


class LogoView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request):
        s = LogoSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        g = GymSettings.load()
        if g.logo:
            g.logo.delete(save=False)
        g.logo = s.validated_data["logo"]
        g.save(update_fields=["logo", "updated_at"])
        activity_log("uploaded a new logo", "system", actor=request.user)
        return Response(BrandingSerializer(g, context={"request": request}).data, status=status.HTTP_201_CREATED)

    def delete(self, request):
        g = GymSettings.load()
        g.logo.delete(save=False)
        g.logo = None
        g.save(update_fields=["logo", "updated_at"])
        activity_log("removed the logo", "system", actor=request.user)
        return Response(status=status.HTTP_204_NO_CONTENT)


class RoleMatrixView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        from apps.accounts.models import AccountStatus, Role, User

        m = RoleMatrix.load()
        cols = {role: {**DEFAULT_ROLE_MATRIX[role], **m.matrix.get(role, {}), **LOCKED_CELLS[role]}
                for role in ("trainer", "client")}
        return Response({
            "permissions": [{"key": k, "label": label} for k, label in ROLE_PERMISSIONS],
            "admin": {k: True for k, _ in ROLE_PERMISSIONS},
            **cols,
            "defaults": {role: {**DEFAULT_ROLE_MATRIX[role]} for role in ("trainer", "client")},
            "locked": {role: sorted(LOCKED_CELLS[role]) for role in ("trainer", "client")},
            "counts": {
                "trainer": User.objects.filter(role=Role.TRAINER, is_active=True, status=AccountStatus.ACTIVE).count(),
                "client": User.objects.filter(role=Role.CLIENT, is_active=True, status=AccountStatus.ACTIVE,
                                              client_profile__removed_at__isnull=True).count(),
            },
        })

    def put(self, request):
        s = RoleMatrixSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        m = RoleMatrix.load()
        m.matrix = {role: {**DEFAULT_ROLE_MATRIX[role], **s.validated_data[role], **LOCKED_CELLS[role]}
                    for role in ("trainer", "client")}
        m.save()
        activity_log("saved role permissions", "system", actor=request.user)
        return self.get(request)


class IntegrationListView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        return Response(integrations.listing())


class IntegrationActionView(APIView):
    """POST connect / save / check / disconnect / undo. Provider keys stay in .env; this decides whether the
    app sends through WhatsApp, which address emails come from, and which health data clients may share."""

    permission_classes = [IsAdmin]

    @transaction.atomic
    def post(self, request, kind, op):
        if kind not in Integration.Kind.values or op not in ("connect", "save", "check", "disconnect", "undo"):
            return Response({"error": {"code": "bad_action", "message": "Unknown action.", "fields": {}}}, status=400)
        integ, _ = Integration.objects.select_for_update().get_or_create(kind=kind)
        if op in ("connect", "save"):
            s = IntegrationConfigSerializer(data=request.data.get("config") or {})
            s.is_valid(raise_exception=True)
            integrations.apply_config(integ, s.validated_data)
            if op == "connect" or integ.status == Integration.Status.NOT_CONNECTED:
                integ.status = Integration.Status.PENDING if kind == "email_domain" else Integration.Status.CONNECTED
                integ.connected_at = timezone.now()
            if kind == "email_domain":
                integrations.check_domain(integ)
        elif op == "check":
            if kind != "email_domain" or integ.status == Integration.Status.NOT_CONNECTED:
                return Response({"error": {"code": "bad_action", "message": "Nothing to check.", "fields": {}}},
                                status=400)
            integrations.check_domain(integ)
        elif op == "disconnect":
            integ.status = Integration.Status.NOT_CONNECTED
            integ.connected_at = None
        else:  # undo a disconnect: back to how it was
            was = request.data.get("status")
            if was not in (Integration.Status.CONNECTED, Integration.Status.PENDING):
                return Response({"error": {"code": "bad_action", "message": "Nothing to undo.", "fields": {}}},
                                status=400)
            integ.status, integ.connected_at = was, timezone.now()
        integ.save()
        verb = {"connect": "connected", "save": "updated", "check": "checked", "disconnect": "disconnected",
                "undo": "reconnected"}[op]
        activity_log(f"{verb} {integrations.NAMES[kind]}", "system", actor=request.user)
        return Response(integrations.listing(kind))
