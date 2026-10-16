from django.db import transaction
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.activity.services import log as activity_log
from apps.common.permissions import IsAdmin

from .models import DEFAULT_ROLE_MATRIX, ROLE_PERMISSIONS, GymSettings, Integration, RoleMatrix
from .serializers import BrandingSerializer, GymProfileSerializer, IntegrationSerializer, LogoSerializer, RoleMatrixSerializer


class PublicGymView(APIView):
    """Gym name, contact and live branding. Public: the signed-out "Need help logging in?" sheet uses it too."""

    permission_classes = [AllowAny]
    allow_inactive_account = True

    def get(self, request):
        g = GymSettings.load()
        return Response({
            "name": g.name, "email": g.email, "phone": g.phone, "address": g.address, "instagram": g.instagram,
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

    def get(self, request):
        return Response(GymProfileSerializer(GymSettings.load()).data)

    def patch(self, request):
        s = GymProfileSerializer(GymSettings.load(), data=request.data, partial=True)
        s.is_valid(raise_exception=True)
        s.save()
        activity_log("updated the gym profile", "system", actor=request.user)
        return Response(s.data)


class BrandingView(APIView):
    """PATCH saves a draft ("Not applied yet"); POST apply makes it live for every client."""

    permission_classes = [IsAdmin]

    def get(self, request):
        return Response(BrandingSerializer(GymSettings.load(), context={"request": request}).data)

    def patch(self, request):
        g = GymSettings.load()
        s = BrandingSerializer(g, data=request.data, partial=True)
        s.is_valid(raise_exception=True)
        g.branding_draft = {**g.branding_draft, **s.validated_data}
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
    permission_classes = [IsAdmin]

    def post(self, request):
        g = GymSettings.load()
        g.branding_draft = {"accent_color": "#2563EB", "theme": "light"}
        g.save(update_fields=["branding_draft", "updated_at"])
        return Response(BrandingSerializer(g, context={"request": request}).data)


class LogoView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request):
        s = LogoSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        g = GymSettings.load()
        g.logo = s.validated_data["logo"]
        g.save(update_fields=["logo", "updated_at"])
        return Response(BrandingSerializer(g, context={"request": request}).data, status=status.HTTP_201_CREATED)

    def delete(self, request):
        g = GymSettings.load()
        g.logo.delete(save=False)
        g.logo = None
        g.save(update_fields=["logo", "updated_at"])
        return Response(status=status.HTTP_204_NO_CONTENT)


class RoleMatrixView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        m = RoleMatrix.load()
        return Response({
            "permissions": [{"key": k, "label": label} for k, label in ROLE_PERMISSIONS],
            "admin": {k: True for k, _ in ROLE_PERMISSIONS},
            **{**DEFAULT_ROLE_MATRIX, **m.matrix},
        })

    def put(self, request):
        s = RoleMatrixSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        m = RoleMatrix.load()
        m.matrix = {role: {**DEFAULT_ROLE_MATRIX[role], **s.validated_data[role]} for role in ("trainer", "client")}
        m.save()
        activity_log("saved role permissions", "system", actor=request.user)
        return self.get(request)


class IntegrationListView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        for kind in Integration.Kind.values:
            Integration.objects.get_or_create(kind=kind)
        return Response(IntegrationSerializer(Integration.objects.order_by("kind"), many=True).data)


class IntegrationActionView(APIView):
    """POST connect / disconnect / check. Real provider keys stay in .env; this records state."""

    permission_classes = [IsAdmin]

    @transaction.atomic
    def post(self, request, kind, op):
        integ, _ = Integration.objects.get_or_create(kind=kind)
        if op == "connect":
            integ.config = {**integ.config, **(request.data.get("config") or {})}
            integ.status = Integration.Status.PENDING if kind == "email_domain" else Integration.Status.CONNECTED
            integ.connected_at = timezone.now()
        elif op == "disconnect":
            integ.status = Integration.Status.NOT_CONNECTED
            integ.connected_at = None
        elif op == "check" and kind == "email_domain":
            integ.config = {**integ.config, "checked_at": timezone.now().isoformat()}
        else:
            return Response({"error": {"code": "bad_action", "message": "Unknown action."}}, status=400)
        integ.save()
        activity_log(f"{op}ed {integ.get_kind_display()}", "system", actor=request.user)
        return Response(IntegrationSerializer(integ).data)
