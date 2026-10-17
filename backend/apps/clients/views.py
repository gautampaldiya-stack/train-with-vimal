from datetime import timedelta

from django.conf import settings
from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import Count, Max, Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from drf_spectacular.utils import extend_schema
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from apps.accounts.models import AccountStatus, Role
from apps.accounts.tokens import start_session
from apps.activity.services import log as activity_log
from apps.common.export import csv_response
from apps.common.mixins import SoftDeleteViewMixin
from apps.common.permissions import HasTrainerPermission, IsClient, IsStaff
from apps.notifications.services import notify, send_template

from . import services
from .filters import ClientFilter
from .models import CLIENT_ONBOARDING_STEPS, ONBOARDING_STEPS, STAFF_STEP_FROM_CLIENT, Approval, ClientNote, ClientProfile, InfoRequest, InviteLink, SignupSource
from .serializers import (
    ApprovalDetailSerializer,
    ApprovalRowSerializer,
    ApproveSerializer,
    AskInfoSerializer,
    ChangeTrainerSerializer,
    ClientCreateSerializer,
    ClientDetailSerializer,
    ClientNoteSerializer,
    ClientRowSerializer,
    ClientUpdateSerializer,
    InviteLinkSerializer,
    JoinSerializer,
    MoveBackSerializer,
    OnboardingStepSerializer,
    RejectSerializer,
    RemindSerializer,
)

User = get_user_model()


class ClientViewSet(viewsets.ModelViewSet):
    """Clients (admin) and My clients (trainer). Trainers only ever see their own clients."""

    permission_classes = [IsStaff]
    filterset_class = ClientFilter
    search_fields = ["full_name", "email", "phone"]
    ordering_fields = ["full_name", "date_joined", "last_seen_at", "client_profile__adherence_7d"]
    ordering = ["full_name"]
    http_method_names = ["get", "post", "patch", "delete"]

    def get_queryset(self):
        qs = services.visible_clients(self.request.user).select_related("client_profile", "client_profile__trainer")
        if self.action in ("list", "export"):  # Next check-in column without a query per row
            qs = qs.annotate(last_weekly=Max("submissions__date", filter=Q(submissions__form_type="weekly")))
        return qs

    def get_serializer_class(self):
        if self.action == "create":
            return ClientCreateSerializer
        if self.action == "partial_update":
            return ClientUpdateSerializer
        if self.action == "retrieve":
            return ClientDetailSerializer
        return ClientRowSerializer

    def create(self, request, *args, **kwargs):
        s = ClientCreateSerializer(data=request.data, context={"request": request})
        s.is_valid(raise_exception=True)
        d = dict(s.validated_data)
        program_id = d.pop("program", None)
        mode = d.pop("mode")
        user, cp = services.create_client(actor=request.user, send_to_approvals=mode == "approvals", **d)
        if program_id:
            from apps.training.services import assign_program

            assign_program(user, program_id, actor=request.user, start_date=d.get("start_date"))
        return Response(ClientDetailSerializer(user, context={"request": request}).data,
                        status=status.HTTP_201_CREATED)

    def partial_update(self, request, *args, **kwargs):
        user = self.get_object()
        s = ClientUpdateSerializer(user, data=request.data, partial=True)
        s.is_valid(raise_exception=True)
        from .history import goal_snapshot, log_goal_changes

        before = goal_snapshot(user)
        s.save()
        activity_log("edited client details", "client", actor=request.user, target=user,
                     target_label=user.full_name, client=user)
        log_goal_changes(user, before, request.user)  # History → "Goal weight changed"
        return Response(ClientDetailSerializer(user, context={"request": request}).data)

    def destroy(self, request, *args, **kwargs):
        if not request.user.is_admin:
            return Response({"error": {"code": "forbidden", "message": "Only the admin can delete clients."}},
                            status=403)
        user = self.get_object()
        with transaction.atomic():
            cp = user.client_profile
            cp.removed_at = timezone.now()
            cp.save(update_fields=["removed_at"])
            user.is_active = False
            user.save(update_fields=["is_active"])
            user.sessions.filter(revoked_at__isnull=True).update(revoked_at=timezone.now())
        activity_log("deleted a client", "client", actor=request.user, target=user, target_label=user.full_name,
                     client=user)
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["post"])
    def restore(self, request, pk=None):
        cp = get_object_or_404(ClientProfile, user_id=pk, removed_at__isnull=False)
        if not request.user.is_admin:
            return Response(status=403)
        cp.removed_at = None
        cp.save(update_fields=["removed_at"])
        User.objects.filter(id=pk).update(is_active=True)
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=False)
    def counts(self, request):
        qs = self.get_queryset().order_by()
        agg = qs.aggregate(
            all=Count("id"),
            active=Count("id", filter=Q(status=AccountStatus.ACTIVE)),
            pending=Count("id", filter=Q(status=AccountStatus.PENDING)),
            paused=Count("id", filter=Q(status=AccountStatus.PAUSED)),
            at_risk=Count("id", filter=Q(status=AccountStatus.ACTIVE, client_profile__at_risk=True)),
            no_trainer=Count("id", filter=Q(client_profile__trainer__isnull=True)),
        )
        return Response(agg)

    @action(detail=False)
    def export(self, request):
        qs = self.filter_queryset(self.get_queryset())
        ids = [i for i in request.query_params.get("ids", "").split(",") if i]
        if ids:  # "Export selected" in My clients
            qs = qs.filter(id__in=ids)
        rows = (
            (u.full_name, u.email, u.phone, u.get_status_display(),
             u.client_profile.trainer.full_name if u.client_profile.trainer else "",
             u.client_profile.get_goal_display(), u.date_joined.date().isoformat(),
             u.last_seen_at.isoformat() if u.last_seen_at else "")
            for u in qs.iterator(chunk_size=1000)
        )
        return csv_response("clients", ["Name", "Email", "Phone", "Status", "Trainer", "Goal", "Joined",
                                        "Last active"], rows)

    @extend_schema(request=ChangeTrainerSerializer)
    @action(detail=True, methods=["post"], url_path="change-trainer")
    def change_trainer(self, request, pk=None):
        if not (request.user.is_admin or request.user.trainer_profile.has_perm("clients.view_all")):
            return Response({"error": {"code": "forbidden", "message": "Ask Vimal to change the trainer."}},
                            status=403)
        user = self.get_object()
        s = ChangeTrainerSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        cp = user.client_profile
        old = cp.trainer
        cp.trainer = s.validated_data["trainer"]
        cp.save(update_fields=["trainer", "updated_at"])
        activity_log("changed trainer", "client", actor=request.user, target=user, target_label=user.full_name,
                     change=(old.full_name if old else "No trainer", cp.trainer.full_name), client=user,
                     trainer=cp.trainer)
        if s.validated_data["tell_client"]:
            notify(user, "trainer_changed", f"{cp.trainer.full_name} is your trainer now", "", actor=request.user)
        if cp.trainer != request.user:
            notify(cp.trainer, "client_assigned", f"{user.full_name} is your client now", "",
                   data={"route": f"/clients/{user.id}"}, actor=request.user)
        return Response(ClientDetailSerializer(user, context={"request": request}).data)

    @action(detail=True, methods=["post"])
    def pause(self, request, pk=None):
        return self._set_status(request, AccountStatus.PAUSED, "paused")

    @action(detail=True, methods=["post"])
    def resume(self, request, pk=None):
        return self._set_status(request, AccountStatus.ACTIVE, "resumed")

    def _set_status(self, request, new_status, verb):
        if request.user.is_trainer and not request.user.trainer_profile.has_perm("clients.pause"):
            return Response({"error": {"code": "forbidden", "message": "Your access does not include pausing."}},
                            status=403)
        user = self.get_object()
        old = user.get_status_display()
        user.status = new_status
        user.save(update_fields=["status"])
        cp = user.client_profile
        cp.paused_at = timezone.now() if new_status == AccountStatus.PAUSED else None
        cp.save(update_fields=["paused_at"])
        activity_log(f"{verb} a client", "client", actor=request.user, target=user, target_label=user.full_name,
                     change=(old, user.get_status_display()), client=user)
        return Response(ClientDetailSerializer(user, context={"request": request}).data)

    @action(detail=True, methods=["post"])
    def remind(self, request, pk=None):
        user = self.get_object()
        s = RemindSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        self._remind(user, request.user, s.validated_data.get("message"))
        return Response({"reminded": 1})

    @action(detail=False, methods=["post"], url_path="remind-at-risk")
    def remind_at_risk(self, request):
        s = RemindSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        qs = self.get_queryset().filter(status=AccountStatus.ACTIVE, client_profile__at_risk=True)
        hours = s.validated_data["skip_recent_hours"]
        if hours:
            cutoff = timezone.now() - timezone.timedelta(hours=hours)
            qs = qs.exclude(client_profile__last_reminded_at__gte=cutoff)
        n = 0
        for u in qs[:500]:
            self._remind(u, request.user, s.validated_data.get("message"))
            n += 1
        return Response({"reminded": n})

    def _remind(self, user, actor, message=None):
        coach = user.client_profile.trainer or actor
        notify(user, "reminder", f"A nudge from {coach.first_name}",
               message or "A short workout or a logged meal today keeps you on track.",
               channels=["in_app", "push", "email"], actor=actor, data={"route": "/home"})
        ClientProfile.objects.filter(user=user).update(last_reminded_at=timezone.now())
        activity_log("sent a reminder", "client", actor=actor, target=user, target_label=user.full_name, client=user)

    @action(detail=True)
    def overview(self, request, pk=None):
        from .overview import client_overview

        return Response(client_overview(self.get_object(), request))

    @action(detail=True)
    def stats(self, request, pk=None):
        from .overview import client_stats

        return Response(client_stats(self.get_object()))

    @action(detail=True)
    def history(self, request, pk=None):
        """Client profile → History tab. ?months=4 (Show earlier months adds more) · ?export=csv for Export."""
        from .history import client_history, history_csv

        user = self.get_object()
        if request.query_params.get("export") == "csv":
            return history_csv(user)
        return Response(client_history(user, request.query_params))


class ClientNoteViewSet(SoftDeleteViewMixin, viewsets.ModelViewSet):
    """/clients/<client_id>/notes/ — staff-only notes."""

    serializer_class = ClientNoteSerializer
    permission_classes = [IsStaff]

    def _client(self):
        return services.get_visible_client(self.request.user, self.kwargs["client_pk"])

    def get_queryset(self):
        # Notes tab: flagged notes on top (the amber box), then newest first.
        return ClientNote.objects.filter(client=self._client()).select_related("author").order_by(
            "-is_flag", "-created_at")

    def restore_queryset(self):
        return ClientNote.all_objects.filter(client=self._client())

    def perform_create(self, serializer):
        client = self._client()
        serializer.save(client=client, author=self.request.user)
        activity_log("added a note", "client", actor=self.request.user, client=client, target_label=client.full_name)

    def perform_update(self, serializer):
        if serializer.instance.author_id != self.request.user.id and not self.request.user.is_admin:
            from rest_framework.exceptions import PermissionDenied

            raise PermissionDenied("Only the person who wrote a note can edit it.")
        serializer.save()

    def perform_destroy(self, instance):
        if instance.author_id != self.request.user.id and not self.request.user.is_admin:
            from rest_framework.exceptions import PermissionDenied

            raise PermissionDenied("Only the person who wrote a note can delete it.")
        instance.soft_delete()


# ---------------------------------------------------------------- invite links
class InviteLinkViewSet(SoftDeleteViewMixin, viewsets.ModelViewSet):
    serializer_class = InviteLinkSerializer
    permission_classes = [IsStaff]
    pagination_class = None

    def get_queryset(self):
        qs = InviteLink.objects.select_related("trainer").annotate(
            joined=Count("clients", distinct=True),
            waiting=Count("clients", filter=Q(clients__user__status=AccountStatus.PENDING), distinct=True),
        )
        user = self.request.user
        if user.is_trainer and not user.trainer_profile.has_perm("clients.view_all"):
            qs = qs.filter(trainer=user)
        return qs.order_by("-created_at")

    def perform_create(self, serializer):
        user = self.request.user
        trainer = serializer.validated_data.get("trainer") or user
        if user.is_trainer and not user.trainer_profile.has_perm("clients.view_all"):
            trainer = user
        code = serializer.validated_data.get("code") or services.make_link_code(trainer)
        serializer.save(trainer=trainer, code=code, created_by=user)

    @action(detail=False)
    def summary(self, request):
        links = list(self.get_queryset())
        on = [link for link in links if link.state == "on"]
        return Response({
            "links": len(links), "on": len(on), "joined": sum(link.joined for link in links),
            "waiting": sum(link.waiting for link in links),
        })

    @action(detail=False, url_path="suggest-code")
    def suggest_code(self, request):
        trainer = User.objects.filter(id=request.query_params.get("trainer")).first() or request.user
        return Response({"code": services.make_link_code(trainer)})


class JoinLinkView(APIView):
    """Public: GET shows the invite page, POST signs up."""

    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "auth"

    def _link(self, code):
        return InviteLink.objects.select_related("trainer", "trainer__trainer_profile").filter(
            code=code.upper()).first()

    def get(self, request, code):
        link = self._link(code)
        if link is None:
            return Response({"state": "invalid"}, status=404)
        t = link.trainer
        return Response({
            "state": link.state,
            "reason": link.end_reason,  # expired / full / off, null while the link works
            "code": link.code,
            "expires_at": link.expires_at,
            "max_uses": link.max_uses,
            "needs_approval": link.needs_approval,
            "gym": settings.APP_NAME,
            # "Ask Aman for a new link" opens WhatsApp to the coach who shared the link
            "trainer": {"full_name": t.full_name, "first_name": t.first_name, "initials": t.initials, "avatar_color": t.avatar_color,
                        "phone": t.phone or "",
                        "speciality": getattr(getattr(t, "trainer_profile", None), "speciality", [])},
        })

    @transaction.atomic
    def post(self, request, code):
        link = self._link(code)
        if link is None or link.end_reason:
            return Response({"error": {"code": f"link_{'invalid' if link is None else link.end_reason}",
                                       "message": "This invite link does not work any more."}}, status=400)
        s = JoinSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        source = {"web": SignupSource.WEB, "android": SignupSource.ANDROID, "ios": SignupSource.IOS}[d["platform"]]
        user, cp = services.create_client(
            actor=None, full_name=d["full_name"], email=d["email"], phone=d["phone"], password=d["password"],
            trainer=link.trainer, send_to_approvals=link.needs_approval, send_login_link=False, source=source,
            invite_link=link, invited_by=link.trainer,
        )
        if not link.needs_approval:
            notify(link.trainer, "client_joined", f"{user.full_name} joined from your link", "",
                   data={"route": f"/clients/{user.id}"})
        from apps.accounts.emails import send_verify_email
        from apps.accounts.models import OneTimeToken
        from apps.accounts.tokens import issue_one_time_token

        send_verify_email(user, issue_one_time_token(user, OneTimeToken.Purpose.EMAIL_VERIFY, email=user.email))
        activity_log("signed up from an invite link", "client", actor=user, target=user, client=user,
                     trainer=link.trainer, meta={"code": link.code})
        tokens = start_session(user, request, platform=d["platform"])
        from apps.accounts.serializers import UserSerializer

        return Response({**tokens, "user": UserSerializer(user).data, "needs_approval": link.needs_approval},
                        status=status.HTTP_201_CREATED)


# ---------------------------------------------------------------- approvals
class ApprovalViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """?tab=waiting|history plus filters from the design."""

    permission_classes = [IsStaff]

    def get_serializer_class(self):
        return ApprovalDetailSerializer if self.action == "retrieve" else ApprovalRowSerializer

    def get_queryset(self):
        user = self.request.user
        qs = Approval.objects.select_related("client", "client__client_profile", "client__client_profile__trainer",
                                             "invited_by", "decided_by", "assigned_trainer")
        if user.is_trainer:
            if not user.trainer_profile.has_perm("clients.approve_signups"):
                return qs.none()
            qs = qs.filter(invited_by=user)
        p = self.request.query_params
        tab = p.get("tab", "waiting")
        if tab == "history":
            qs = qs.exclude(status=Approval.Status.WAITING).order_by("-decided_at")
            if p.get("decision") in ("approved", "rejected"):
                qs = qs.filter(status=p["decision"])
            if p.get("decided_by"):
                qs = qs.filter(decided_by_id=p["decided_by"])
            if p.get("when") in ("7d", "30d"):
                days = 7 if p["when"] == "7d" else 30
                qs = qs.filter(decided_at__gte=timezone.now() - timezone.timedelta(days=days))
        else:
            qs = qs.filter(status=Approval.Status.WAITING).order_by("-moved_back", "created_at")
            if p.get("invited_by"):
                qs = qs.filter(invited_by_id=p["invited_by"])
            if p.get("waiting") in ("1d", "2d"):
                hours = 24 if p["waiting"] == "1d" else 48
                qs = qs.filter(created_at__lte=timezone.now() - timezone.timedelta(hours=hours))
            if p.get("signed_up_from"):
                qs = qs.filter(signed_up_from=p["signed_up_from"])
            if p.get("setup") == "done":
                qs = qs.filter(client__client_profile__onboarding_done__len=5)
            elif p.get("setup") == "not_finished":
                qs = qs.exclude(client__client_profile__onboarding_done__len=5)
            if p.get("health_note") == "yes":
                qs = qs.exclude(client__client_profile__health_notes="")
            elif p.get("health_note") == "no":
                qs = qs.filter(client__client_profile__health_notes="")
        return qs

    @action(detail=False)
    def counts(self, request):
        base = Approval.objects.all()
        if request.user.is_trainer:
            base = base.filter(invited_by=request.user)
        return Response({"waiting": base.filter(status="waiting").count(),
                         "history": base.exclude(status="waiting").count()})

    @action(detail=True)
    def trainers(self, request, pk=None):
        """Trainer list in the Review drawer with load and tags."""
        approval = self.get_object()
        load = services.trainer_load()
        goal = approval.client.client_profile.goal
        rows = []
        trainers = User.objects.filter(role__in=[Role.TRAINER, Role.ADMIN], status=AccountStatus.ACTIVE,
                                       trainer_profile__isnull=False).select_related("trainer_profile")
        for t in trainers:
            tp = t.trainer_profile
            n = load.get(t.id, 0)
            tag = "full" if n >= tp.max_clients else (
                "invited" if approval.invited_by_id == t.id else (
                    "good_fit" if goal and any(goal.replace("_", " ") in s.lower() for s in tp.speciality) else ""))
            rows.append({"id": t.id, "full_name": t.full_name, "initials": t.initials,
                         "avatar_color": t.avatar_color, "speciality": tp.speciality, "clients": n,
                         "max_clients": tp.max_clients, "tag": tag})
        with_space = sum(1 for r in rows if r["tag"] != "full")
        return Response({"with_space": with_space, "total": len(rows), "trainers": rows,
                         "default": approval.invited_by_id})

    def _waiting(self):
        a = self.get_object()
        if a.status != Approval.Status.WAITING:
            from rest_framework.exceptions import ValidationError

            raise ValidationError({"non_field_errors": ["This person was already decided."]})
        return a

    @action(detail=True, methods=["post"])
    def approve(self, request, pk=None):
        a = self._waiting()
        s = ApproveSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        services.approve(a, actor=request.user, **s.validated_data)
        return Response(ApprovalRowSerializer(a).data)

    @action(detail=True, methods=["post"])
    def reject(self, request, pk=None):
        a = self._waiting()
        s = RejectSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        services.reject(a, actor=request.user, **s.validated_data)
        return Response(ApprovalRowSerializer(a).data)

    @action(detail=True, methods=["post"], url_path="ask-info")
    def ask_info(self, request, pk=None):
        a = self._waiting()
        s = AskInfoSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        InfoRequest.objects.create(approval=a, sent_by=request.user, **s.validated_data)
        labels = {"setup": "Finish your profile setup", "health_form": "Fill the health form again",
                  "doctor_note": "Send a doctor note", "photo": "Add a profile photo",
                  "phone": "Check your phone number"}
        body = "\n".join(f"• {labels[i]}" for i in s.validated_data["items"])
        notify(a.client, "info_requested", "We need a few things from you", body,
               channels=s.validated_data["channels"], actor=request.user, data={"route": "/setup"})
        activity_log("asked a sign-up for more info", "client", actor=request.user, client=a.client,
                     target_label=a.client.full_name)
        return Response({"asked": len(s.validated_data["items"])})

    @action(detail=True, methods=["post"], url_path="move-back")
    def move_back(self, request, pk=None):
        a = self.get_object()
        if a.status == Approval.Status.WAITING:
            return Response({"error": {"code": "already_waiting", "message": "Already in Waiting."}}, status=400)
        s = MoveBackSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        services.move_back(a, actor=request.user, **s.validated_data)
        return Response(ApprovalRowSerializer(a).data)


# ---------------------------------------------------------------- client self
class MyOnboardingView(APIView):
    """Client Welcome / profile setup: 5 steps, each can be saved alone ("Finish later")."""

    permission_classes = [IsClient]
    allow_inactive_account = True

    def get(self, request):
        cp = request.user.client_profile
        return Response({"answers": cp.onboarding, "steps": CLIENT_ONBOARDING_STEPS, "done": cp.client_steps_done,
                         "progress": cp.onboarding_progress, "skipped_at": cp.onboarding_skipped_at,
                         "remind": (cp.onboarding or {}).get("_remind")})

    @transaction.atomic
    def post(self, request):
        s = OnboardingStepSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        cp = request.user.client_profile
        step, data = s.validated_data["step"], s.validated_data["data"]
        was_complete = len(cp.client_steps_done) == 5
        cp.onboarding = {**(cp.onboarding or {}), step: data}
        client_done = set(cp.client_steps_done)
        staff_done = set(cp.onboarding_done or [])
        for staff_key, needs in STAFF_STEP_FROM_CLIENT.items():
            if all(k in client_done for k in needs):
                staff_done.add(staff_key)
        cp.onboarding_done = [k for k in ONBOARDING_STEPS if k in staff_done]
        if step == "goal":
            cp.goal = data["goal"]
        if step == "about":
            cp.height_cm = data["height_cm"]
            cp.current_weight_kg = data["weight_kg"]
            cp.start_weight_kg = cp.start_weight_kg or data["weight_kg"]
            cp.target_weight_kg = data["target_weight_kg"]
        if step == "health" and data.get("notes"):
            cp.health_notes = str(data["notes"])[:2000]
        cp.save()
        if len(client_done) == 5 and not was_complete and cp.trainer:
            notify(cp.trainer, "setup_done", f"{request.user.full_name} finished profile setup",
                   "You can build their plan now.", data={"route": f"/clients/{request.user.id}"})
        return self.get(request)

    REMIND = {"tonight": (0, 20), "tomorrow": (1, 9), "3days": (3, 9)}

    def delete(self, request):
        """Finish setup later → Save & leave. `remind`: tonight (8 pm) / tomorrow (9 am) / 3days (9 am) / off."""
        choice = request.data.get("remind") or request.query_params.get("remind") or "tomorrow"
        if choice not in (*self.REMIND, "off"):
            raise ValidationError({"remind": ["Pick Tonight, Tomorrow, In 3 days or Off."]})
        cp = request.user.client_profile
        now = timezone.localtime()
        remind = {"choice": choice, "at": None, "sent": False}
        if choice != "off":
            days, hour = self.REMIND[choice]
            at = (now + timedelta(days=days)).replace(hour=hour, minute=0, second=0, microsecond=0)
            if at <= now:
                at += timedelta(days=1)
            remind["at"] = at.isoformat()
        cp.onboarding = {**(cp.onboarding or {}), "_remind": remind}
        cp.onboarding_skipped_at = timezone.now()
        cp.save(update_fields=["onboarding", "onboarding_skipped_at"])
        return Response({"remind": remind})


class MyTrainerView(APIView):
    """Client More → My trainer: only the fields the trainer switched on in What clients see."""

    permission_classes = [IsClient]

    def get(self, request):
        t = request.user.client_profile.trainer
        if t is None:
            return Response(None)
        from apps.trainers.serializers import public_trainer_card

        return Response(public_trainer_card(t, request))


class MyAccountView(APIView):
    """Client More tab: profile, coach card, plan rows, goal, reminders, deletion date, gym contact."""

    permission_classes = [IsClient]

    def get(self, request):
        from .account import account_page

        return Response(account_page(request.user, request))


class MyActivityView(APIView):
    """Client More → My activity: everything logged in the last 7 days, newest first, by day.
    ?kind=All|Training|Food|Check-ins|Habits|Account. Seven days is the whole list, so no paging."""

    permission_classes = [IsClient]
    KINDS = ("All", "Training", "Food", "Check-ins", "Habits", "Account")

    def get(self, request):
        from .account import my_activity

        kind = request.query_params.get("kind", "All")
        if kind not in self.KINDS:
            raise ValidationError({"kind": [f"Use one of: {', '.join(self.KINDS)}."]})
        return Response(my_activity(request.user, kind))


class MyDataExportView(APIView):
    """Client More → Privacy & data → Download my data: a ZIP is built in the background and the link
    is emailed (works for 7 days)."""

    permission_classes = [IsClient]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "data_export"

    def post(self, request):
        from .account import send_data_export

        if not request.user.email:
            raise ValidationError({"email": ["Add an email to your profile first."]})
        send_data_export.delay(str(request.user.id), request.build_absolute_uri("/"))
        activity_log("asked for a copy of their data", "client", actor=request.user, client=request.user)
        return Response({"email": request.user.email}, status=status.HTTP_202_ACCEPTED)


class MyProblemReportView(APIView):
    """Client More → Help & about → Report a problem. The admin gets it in the app and by email."""

    permission_classes = [IsClient]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "problem_report"

    def post(self, request):
        from apps.accounts.models import ProblemReport, User
        from apps.common.utils import data_url_file

        cat = request.data.get("category")
        text = " ".join(str(request.data.get("text") or "").split())
        errors = {}
        if cat not in ProblemReport.Category.values:
            errors["category"] = ["Pick what it is about."]
        if len(text) < 3:
            errors["text"] = ["Tell us what happened."]
        elif len(text) > 2000:
            errors["text"] = ["Keep it under 2,000 characters."]
        if errors:
            raise ValidationError(errors)
        shot = request.data.get("screenshot")
        r = ProblemReport.objects.create(
            user=request.user, category=cat, text=text, page=str(request.data.get("page") or "")[:120],
            app_version=str(request.data.get("app_version") or "")[:20],
            screenshot=data_url_file(shot, "screenshot", "screenshot") if shot else None)
        admin = User.objects.filter(role=Role.ADMIN).first()
        notify(admin, "problem_report", f"{request.user.full_name} reported a problem",
               f"{r.get_category_display()}: {text[:200]}", data={"route": "/settings", "report": str(r.id)},
               channels=["in_app", "email"], actor=request.user)
        return Response({"id": str(r.id)}, status=status.HTTP_201_CREATED)
