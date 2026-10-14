from django.contrib.auth import password_validation
from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from drf_spectacular.utils import extend_schema
from rest_framework import generics, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken

from apps.activity.services import log as activity_log
from apps.common.validators import normalize_phone

from . import emails
from .authentication import forget_session_cache
from .models import OneTimeToken, User, UserSession
from .serializers import (
    ForgotPasswordSerializer,
    LoginSerializer,
    MeUpdateSerializer,
    PasswordChangeSerializer,
    RefreshSerializer,
    SessionSerializer,
    SetPasswordSerializer,
    TokenSerializer,
    UserSerializer,
)
from .tokens import consume_one_time_token, issue_one_time_token, start_session

LINK_PROBLEMS = {
    "invalid": "This link is not valid. Check you opened the latest one.",
    "used": "This link was already used.",
    "expired": "This link has expired. Ask for a new one.",
}


def _link_error(problem):
    return Response({"error": {"code": f"link_{problem}", "message": LINK_PROBLEMS[problem]}},
                    status=status.HTTP_400_BAD_REQUEST)


class AuthThrottleMixin:
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "auth"


class LoginView(AuthThrottleMixin, APIView):
    permission_classes = [AllowAny]
    authentication_classes = []

    @extend_schema(request=LoginSerializer)
    def post(self, request):
        s = LoginSerializer(data=request.data, context={"request": request})
        s.is_valid(raise_exception=True)
        user = s.validated_data["user"]
        tokens = start_session(user, request, s.validated_data.get("device_name", ""),
                               s.validated_data.get("platform", ""))
        return Response({**tokens, "user": UserSerializer(user, context={"request": request}).data})


class RefreshView(APIView):
    """Rotates the refresh token. Fails if that device was logged out."""

    permission_classes = [AllowAny]
    authentication_classes = []

    @extend_schema(request=RefreshSerializer)
    def post(self, request):
        s = RefreshSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        try:
            old = RefreshToken(s.validated_data["refresh"])
        except TokenError:
            return Response({"error": {"code": "token_invalid", "message": "Please log in again."}}, status=401)
        sid = old.get("sid")
        session = UserSession.objects.filter(id=sid, revoked_at__isnull=True).select_related("user").first()
        if session is None or not session.user.is_active:
            return Response({"error": {"code": "session_revoked", "message": "Please log in again."}}, status=401)
        try:
            old.blacklist()
        except Exception:
            return Response({"error": {"code": "token_invalid", "message": "Please log in again."}}, status=401)
        new = RefreshToken.for_user(session.user)
        new["sid"] = sid
        new["role"] = session.user.role
        access = new.access_token
        access["sid"] = sid
        access["role"] = session.user.role
        session.last_active_at = timezone.now()
        session.save(update_fields=["last_active_at", "updated_at"])
        return Response({"access": str(access), "refresh": str(new)})


class LogoutView(APIView):
    allow_inactive_account = True

    def post(self, request):
        sid = request.auth.get("sid") if request.auth else None
        if sid:
            UserSession.objects.filter(id=sid, user=request.user).update(revoked_at=timezone.now())
            forget_session_cache([sid])
        token = request.data.get("refresh")
        if token:
            try:
                RefreshToken(token).blacklist()
            except TokenError:
                pass
        request.user.device_tokens.filter(session_id=sid).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class MeView(generics.RetrieveUpdateAPIView):
    allow_inactive_account = True

    def get_object(self):
        return self.request.user

    def get_serializer_class(self):
        return UserSerializer if self.request.method == "GET" else MeUpdateSerializer

    @transaction.atomic
    def perform_update(self, serializer):
        user = self.request.user
        new_email = serializer.validated_data.pop("email", None)
        serializer.save()
        if new_email and new_email != (user.email or ""):
            # Design: a new email is used only after its verification link is opened.
            user.pending_email = new_email
            user.save(update_fields=["pending_email"])
            token = issue_one_time_token(user, OneTimeToken.Purpose.EMAIL_VERIFY, email=new_email)
            emails.send_verify_email(user, token, to=new_email)

    def update(self, request, *args, **kwargs):
        super().update(request, *args, **kwargs)
        return Response(UserSerializer(request.user, context={"request": request}).data)


class PasswordChangeView(APIView):
    def post(self, request):
        s = PasswordChangeSerializer(data=request.data, context={"request": request})
        s.is_valid(raise_exception=True)
        user = request.user
        user.set_password(s.validated_data["new_password"])
        user.password_changed_at = timezone.now()
        user.save(update_fields=["password", "password_changed_at"])
        # Everyone else is logged out; this device stays.
        sid = request.auth.get("sid")
        others = list(user.sessions.filter(revoked_at__isnull=True).exclude(id=sid).values_list("id", flat=True))
        user.sessions.filter(id__in=others).update(revoked_at=timezone.now())
        forget_session_cache(others)
        activity_log("changed their password", "system", actor=user, client=user if user.is_client else None)
        return Response(status=status.HTTP_204_NO_CONTENT)


class ForgotPasswordView(APIView):
    """Always answers the same, so nobody can find out which emails have accounts."""

    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "otp"

    def post(self, request):
        s = ForgotPasswordSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        ident = s.validated_data["identifier"].strip()
        q = Q(email__iexact=ident) if "@" in ident else Q(phone=normalize_phone(ident))
        user = User.objects.filter(q, is_active=True).first()
        if user and user.email:
            token = issue_one_time_token(user, OneTimeToken.Purpose.PASSWORD_RESET)
            emails.send_password_reset(user, token)
        return Response({"detail": "If an account matches, we sent a reset link to its email."})


class CheckLinkView(APIView):
    """GET-like check used by Reset password / Login link / Verify email screens to show the
    right state (valid, expired, used) before the person types anything."""

    permission_classes = [AllowAny]
    authentication_classes = []
    purpose = None

    def post(self, request):
        s = TokenSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        row, problem = consume_one_time_token(s.validated_data["token"], self.purpose)
        if problem:
            return _link_error(problem)
        u = row.user
        return Response({"valid": True, "user": {"full_name": u.full_name, "email": u.email, "phone": u.phone}})


class ResetPasswordView(AuthThrottleMixin, APIView):
    permission_classes = [AllowAny]
    authentication_classes = []

    @transaction.atomic
    def post(self, request):
        s = SetPasswordSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        row, problem = consume_one_time_token(s.validated_data["token"], OneTimeToken.Purpose.PASSWORD_RESET)
        if problem:
            return _link_error(problem)
        user = row.user
        password_validation.validate_password(s.validated_data["password"], user)
        user.set_password(s.validated_data["password"])
        user.password_changed_at = timezone.now()
        user.save(update_fields=["password", "password_changed_at"])
        row.used_at = timezone.now()
        row.save(update_fields=["used_at"])
        ids = list(user.sessions.filter(revoked_at__isnull=True).values_list("id", flat=True))
        user.sessions.filter(id__in=ids).update(revoked_at=timezone.now())
        forget_session_cache(ids)
        return Response({"detail": "Password saved. Log in with your new password."})


class AcceptLoginLinkView(AuthThrottleMixin, APIView):
    """"Your coach added you": pick a password and you are in (no approval needed)."""

    permission_classes = [AllowAny]
    authentication_classes = []

    @transaction.atomic
    def post(self, request):
        s = SetPasswordSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        row, problem = consume_one_time_token(s.validated_data["token"], OneTimeToken.Purpose.LOGIN_LINK)
        if problem:
            return _link_error(problem)
        user = row.user
        password_validation.validate_password(s.validated_data["password"], user)
        user.set_password(s.validated_data["password"])
        user.password_changed_at = timezone.now()
        if user.email and not user.email_verified_at:
            user.email_verified_at = timezone.now()  # the link reached this inbox
        user.save(update_fields=["password", "password_changed_at", "email_verified_at"])
        row.used_at = timezone.now()
        row.save(update_fields=["used_at"])
        tokens = start_session(user, request)
        return Response({**tokens, "user": UserSerializer(user, context={"request": request}).data})


class VerifyEmailView(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []

    @transaction.atomic
    def post(self, request):
        s = TokenSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        row, problem = consume_one_time_token(s.validated_data["token"], OneTimeToken.Purpose.EMAIL_VERIFY)
        if problem:
            return _link_error(problem)
        user = row.user
        target = row.email or user.email
        if target and target != user.email:
            if User.objects.filter(email__iexact=target).exclude(id=user.id).exists():
                return Response({"error": {"code": "email_taken", "message": "Another account uses this email now."}},
                                status=400)
            user.email = target
        user.pending_email = ""
        user.email_verified_at = timezone.now()
        user.save(update_fields=["email", "pending_email", "email_verified_at"])
        row.used_at = timezone.now()
        row.save(update_fields=["used_at"])
        return Response({"detail": "Email confirmed.", "email": user.email})


class ResendVerifyEmailView(APIView):
    allow_inactive_account = True
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "otp"

    def post(self, request):
        user = request.user
        target = user.pending_email or user.email
        if not target:
            return Response({"error": {"code": "no_email", "message": "Add an email first."}}, status=400)
        if not user.pending_email and user.email_verified_at:
            return Response({"detail": "Your email is already confirmed."})
        token = issue_one_time_token(user, OneTimeToken.Purpose.EMAIL_VERIFY, email=target)
        emails.send_verify_email(user, token, to=target)
        return Response({"detail": f"We sent a new link to {target}."})


class ChangeEmailView(APIView):
    """Verify email screen → Change email: the old link stops working."""

    allow_inactive_account = True

    def post(self, request):
        s = MeUpdateSerializer(request.user, data={"email": request.data.get("email", "")}, partial=True)
        s.is_valid(raise_exception=True)
        user = request.user
        email = s.validated_data["email"]
        if user.email_verified_at:
            user.pending_email = email
            user.save(update_fields=["pending_email"])
        else:
            user.email = email
            user.save(update_fields=["email"])
        token = issue_one_time_token(user, OneTimeToken.Purpose.EMAIL_VERIFY, email=email)
        emails.send_verify_email(user, token, to=email)
        return Response(UserSerializer(user).data)


class CancelEmailChangeView(APIView):
    def post(self, request):
        user = request.user
        user.pending_email = ""
        user.save(update_fields=["pending_email"])
        OneTimeToken.objects.filter(user=user, purpose=OneTimeToken.Purpose.EMAIL_VERIFY, used_at__isnull=True).update(
            used_at=timezone.now())
        return Response(UserSerializer(user).data)


class SessionListView(generics.ListAPIView):
    serializer_class = SessionSerializer
    pagination_class = None

    def get_queryset(self):
        return self.request.user.sessions.filter(revoked_at__isnull=True)


class SessionLogoutView(APIView):
    def delete(self, request, pk):
        n = request.user.sessions.filter(id=pk, revoked_at__isnull=True).update(revoked_at=timezone.now())
        forget_session_cache([pk])
        request.user.device_tokens.filter(session_id=pk).delete()
        return Response(status=status.HTTP_204_NO_CONTENT if n else status.HTTP_404_NOT_FOUND)


class LogoutOthersView(APIView):
    def post(self, request):
        sid = request.auth.get("sid")
        ids = list(request.user.sessions.filter(revoked_at__isnull=True).exclude(id=sid).values_list("id", flat=True))
        request.user.sessions.filter(id__in=ids).update(revoked_at=timezone.now())
        request.user.device_tokens.filter(session_id__in=ids).delete()
        forget_session_cache(ids)
        return Response({"logged_out": len(ids)})


class DeleteAccountView(APIView):
    """Client More → Delete account. Data is removed after a 14-day grace period
    (the design shows "Cancel deletion" after asking)."""

    GRACE_DAYS = 14

    def post(self, request):
        if not request.user.is_client:
            return Response({"error": {"code": "not_allowed", "message": "Ask the admin to remove staff accounts."}},
                            status=403)
        request.user.deletion_requested_at = timezone.now()
        request.user.save(update_fields=["deletion_requested_at"])
        activity_log("asked to delete their account", "client", actor=request.user, client=request.user)
        return Response({"deletion_requested_at": request.user.deletion_requested_at, "grace_days": self.GRACE_DAYS})

    def delete(self, request):
        request.user.deletion_requested_at = None
        request.user.save(update_fields=["deletion_requested_at"])
        return Response(status=status.HTTP_204_NO_CONTENT)
