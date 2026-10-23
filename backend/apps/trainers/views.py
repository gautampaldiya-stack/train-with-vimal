from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import Avg, Count, F, OuterRef, Q, Subquery
from django.shortcuts import get_object_or_404
from django.utils import timezone
from drf_spectacular.utils import extend_schema
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import AccountStatus, OneTimeToken, Role
from apps.accounts.tokens import issue_one_time_token
from apps.activity.services import log as activity_log
from apps.checkins.models import Submission
from apps.checkins.queue import WAITING, review_queue
from apps.clients.models import ClientProfile
from apps.common.export import csv_response
from apps.common.permissions import IsAdmin, IsStaff, IsTrainer
from apps.notifications.services import notify

from .models import AccessMode, AccessRequest, TrainerDocument, TrainerProfile
from .permissions_catalog import ALL_CLIENTS_PRESET, ALL_KEYS, ASSIGNED_PRESET
from .serializers import (
    AccessRequestSerializer,
    AccessSerializer,
    AssignClientsSerializer,
    DocumentSerializer,
    MoveClientsSerializer,
    TrainerDetailSerializer,
    TrainerRowSerializer,
    TrainerWriteSerializer,
    VisibilitySerializer,
    permission_groups,
    public_trainer_card,
)

User = get_user_model()

ACTIVE_CLIENT = Q(coached_clients__user__status=AccountStatus.ACTIVE, coached_clients__removed_at__isnull=True)


def trainers_queryset():
    """Every coach (trainers + Vimal), annotated with the numbers the table shows, in one query."""
    return (
        User.objects.filter(role__in=[Role.TRAINER, Role.ADMIN], trainer_profile__isnull=False)
        .select_related("trainer_profile")
        .annotate(
            n_clients=Count("coached_clients", filter=ACTIVE_CLIENT, distinct=True),
            # A subquery: averaging over the same join as the check-in count would weigh each client by their
            # number of waiting check-ins (the table then disagreed with the profile card, D-30).
            avg_adherence=Subquery(
                ClientProfile.objects.filter(trainer=OuterRef("pk"), user__status=AccountStatus.ACTIVE,
                                             removed_at__isnull=True)
                .order_by().values("trainer").annotate(a=Avg("adherence_7d")).values("a")[:1]),
            n_review=Count(
                "coached_clients__user__submissions",
                filter=WAITING,
                distinct=True,
            ),
        )
    )


def _deny(message, code="forbidden", http=403):
    return Response({"error": {"code": code, "message": message}}, status=http)


def move_clients(*, actor, source, to, client_ids=None, tell_clients=True):
    """Move clients from `source` to one trainer, or share them between trainers with space ("share")."""
    qs = ClientProfile.objects.filter(trainer=source, removed_at__isnull=True).select_related("user")
    if client_ids:
        qs = qs.filter(user_id__in=client_ids)
    profiles = list(qs)
    if not profiles:
        return []
    if to == "share":
        pool = [u for u in trainers_queryset().filter(status=AccountStatus.ACTIVE).exclude(id=source.id)
                if u.n_clients < u.trainer_profile.max_clients]
        free = {u.id: u.trainer_profile.max_clients - u.n_clients for u in pool}
        if sum(free.values()) < len(profiles):
            raise ValueError("Not enough free spots. Raise someone's max clients or move fewer clients.")
        targets = []
        for _ in profiles:
            best = max(pool, key=lambda u: free[u.id])
            free[best.id] -= 1
            targets.append(best)
    else:
        target = User.objects.filter(id=to, role__in=[Role.TRAINER, Role.ADMIN], status=AccountStatus.ACTIVE,
                                     trainer_profile__isnull=False).first()
        if target is None or target.id == source.id:
            raise ValueError("Pick an active trainer.")
        targets = [target] * len(profiles)
    moved = []
    with transaction.atomic():
        for cp, target in zip(profiles, targets):
            cp.trainer = target
            cp.save(update_fields=["trainer", "updated_at"])
            moved.append((cp.user, target))
            activity_log("changed trainer", "client", actor=actor, target=cp.user, target_label=cp.user.full_name,
                         change=(source.full_name, target.full_name), client=cp.user, trainer=target)
    by_target = {}
    for client, target in moved:
        by_target.setdefault(target, []).append(client)
        if tell_clients:
            notify(client, "trainer_changed", f"{target.full_name} is your trainer now", "", actor=actor)
    for target, clients in by_target.items():
        if target != actor:
            names = ", ".join(c.full_name for c in clients[:3]) + (f" and {len(clients) - 3} more"
                                                                    if len(clients) > 3 else "")
            notify(target, "client_assigned", f"New clients: {names}", "", actor=actor, data={"route": "/clients"})
    return moved


def send_reset_link(user):
    from apps.accounts.emails import send_password_reset

    token = issue_one_time_token(user, OneTimeToken.Purpose.PASSWORD_RESET)
    if user.email:
        send_password_reset(user, token)


class TrainerViewSet(viewsets.ModelViewSet):
    """Admin → Trainers. Trainers can read the team list (for "Move to another trainer")."""

    filterset_fields = []
    search_fields = ["full_name", "email", "phone"]
    ordering_fields = ["full_name", "n_clients", "avg_adherence", "n_review", "trainer_profile__joining_date"]
    ordering = ["-trainer_profile__is_owner", "full_name"]
    # PUT is for the access and visibility actions only (a full replace of a trainer is not offered).
    http_method_names = ["get", "post", "put", "patch"]

    def update(self, request, *args, **kwargs):
        if not kwargs.get("partial"):
            return Response({"error": {"code": "method_not_allowed", "message": 'Method "PUT" not allowed.', "fields": {}}},
                            status=405)
        return super().update(request, *args, **kwargs)

    def get_permissions(self):
        if self.action in ("list", "retrieve", "options_for_move"):
            return [IsStaff()]
        return [IsAdmin()]

    def filter_queryset(self, queryset):
        # The list's search and filters are for the list only: on a trainer (profile tabs) `?search=` and
        # `?status=` belong to that tab and must not hide the trainer itself.
        if self.detail:
            return queryset
        return super().filter_queryset(queryset)

    def get_queryset(self):
        qs = trainers_queryset()
        p = self.request.query_params
        if self.detail:
            return qs
        tab = p.get("tab")
        if tab == "active":
            qs = qs.filter(status=AccountStatus.ACTIVE)
        elif tab == "inactive":
            qs = qs.exclude(status=AccountStatus.ACTIVE)
        elif tab == "full":
            qs = qs.filter(n_clients__gte=F("trainer_profile__max_clients"))
        if p.get("access") in AccessMode.values:
            qs = qs.filter(trainer_profile__access_mode=p["access"])
        if p.get("space") == "has_space":
            qs = qs.filter(n_clients__lt=F("trainer_profile__max_clients"))
        elif p.get("space") == "full":
            qs = qs.filter(n_clients__gte=F("trainer_profile__max_clients"))
        if p.get("speciality"):
            qs = qs.filter(trainer_profile__speciality__icontains=p["speciality"])
        if p.get("checkins") == "to_review":
            qs = qs.filter(n_review__gt=0)
        elif p.get("checkins") == "reviewed":
            qs = qs.filter(n_review=0)
        return qs

    def get_serializer_class(self):
        if self.action == "retrieve":
            return TrainerDetailSerializer
        if self.action in ("create", "partial_update"):
            return TrainerWriteSerializer
        return TrainerRowSerializer

    def retrieve(self, request, *args, **kwargs):
        """Trainer profile page (admin): the same shape as `trainers/me/` (stats, access groups, This week,
        Clients who need him, last login), so the page reuses the My profile code (D-48)."""
        user = self.get_object()
        data = TrainerDetailSerializer(user, context={"request": request}).data
        if request.user.is_admin:
            from .me import me_extras

            data["stats"] = trainer_stats(user)
            data["access_groups"] = permission_groups(user.trainer_profile.effective_permissions())
            # Access tab: which level a set of switches is (Assigned clients / All clients / else Custom).
            data["access_presets"] = {"assigned": ASSIGNED_PRESET, "all": ALL_CLIENTS_PRESET}
            data.update(me_extras(user))
        return Response(data)

    # ------------------------------------------------------------ list extras
    @action(detail=False)
    def summary(self, request):
        """Header sub-line, tab counts and the 4 stat cards."""
        rows = list(trainers_queryset())
        active = [u for u in rows if u.status == AccountStatus.ACTIVE]
        spots_total = sum(u.trainer_profile.max_clients for u in active)
        used = sum(u.n_clients for u in active)
        most = max(active, key=lambda u: u.n_review, default=None)
        adh = [u.avg_adherence for u in active if u.avg_adherence is not None]
        # "+2% vs last week": the clients' 7-day against their 30-day adherence, like the dashboard card.
        both = ClientProfile.objects.filter(trainer__in=[u.id for u in active], removed_at__isnull=True,
                                            user__status=AccountStatus.ACTIVE).aggregate(
            a7=Avg("adherence_7d"), a30=Avg("adherence_30d"))
        return Response({
            "counts": {
                "all": len(rows), "active": len(active), "inactive": len(rows) - len(active),
                "full": sum(1 for u in active if u.n_clients >= u.trainer_profile.max_clients),
            },
            "clients": used,
            "spots": {"used": used, "total": spots_total, "free": max(spots_total - used, 0)},
            "checkins_to_review": {"total": sum(u.n_review for u in active),
                                   "most": {"name": most.first_name, "n": most.n_review}
                                   if most and most.n_review else None},
            "adherence": round(sum(adh) / len(adh)) if adh else None,
            "adherence_change": round(both["a7"] - both["a30"])
            if both["a7"] is not None and both["a30"] is not None else None,
        })

    @action(detail=False, url_path="with-space")
    def options_for_move(self, request):
        """Trainer picker in Move / Assign drawers: who has free spots."""
        data = [
            {"id": str(u.id), "full_name": u.full_name, "initials": u.initials, "avatar_color": u.avatar_color,
             "clients": u.n_clients, "max_clients": u.trainer_profile.max_clients,
             "free": max(u.trainer_profile.max_clients - u.n_clients, 0)}
            for u in trainers_queryset().filter(status=AccountStatus.ACTIVE)
        ]
        return Response(data)

    @action(detail=False)
    def export(self, request):
        qs = self.filter_queryset(self.get_queryset())
        rows = ((u.full_name, u.email, u.phone, ", ".join(u.trainer_profile.speciality), u.n_clients,
                 u.trainer_profile.max_clients, u.n_review,
                 round(u.avg_adherence) if u.avg_adherence is not None else "",
                 u.trainer_profile.get_access_mode_display(), u.get_status_display(),
                 u.trainer_profile.joining_date.isoformat()) for u in qs)
        return csv_response("trainers", ["Name", "Email", "Phone", "Speciality", "Clients", "Max clients",
                                         "Check-ins to review", "Adherence %", "Access", "Status", "Joined"], rows)

    # ------------------------------------------------------------ create / edit
    def create(self, request, *args, **kwargs):
        s = TrainerWriteSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = dict(s.validated_data)
        send_invite = d.pop("send_invite")
        d.pop("send_password_reset", None)
        profile = {k: d.pop(k) for k in TrainerWriteSerializer.PROFILE_FIELDS if k in d}
        with transaction.atomic():
            user = User.objects.create_user(role=Role.TRAINER, status=AccountStatus.ACTIVE, **d)
            TrainerProfile.objects.create(user=user, **profile)
        if send_invite:
            from apps.accounts.emails import send_login_link

            token = issue_one_time_token(user, OneTimeToken.Purpose.LOGIN_LINK)
            send_login_link(user, token, template_key="trainer-invite")
        activity_log("added a trainer", "team", actor=request.user, target=user, target_label=user.full_name,
                     trainer=user)
        user = trainers_queryset().get(id=user.id)
        return Response(TrainerDetailSerializer(user, context={"request": request}).data,
                        status=status.HTTP_201_CREATED)

    def partial_update(self, request, *args, **kwargs):
        user = self.get_object()
        s = TrainerWriteSerializer(user, data=request.data, partial=True)
        s.is_valid(raise_exception=True)
        d = dict(s.validated_data)
        d.pop("send_invite", None)
        reset = d.pop("send_password_reset", False)
        d.pop("access_mode", None)  # access is changed on the Access tab
        tp = user.trainer_profile
        with transaction.atomic():
            for k in TrainerWriteSerializer.PROFILE_FIELDS:
                if k in d:
                    setattr(tp, k, d.pop(k))
            tp.save()
            for k, v in d.items():
                setattr(user, k, v)
            user.save()
        if reset:
            send_reset_link(user)
        activity_log("edited trainer details", "team", actor=request.user, target=user,
                     target_label=user.full_name, trainer=user)
        return Response(TrainerDetailSerializer(self.get_queryset().get(id=user.id),
                                                context={"request": request}).data)

    # ------------------------------------------------------------ status
    @action(detail=True, url_path="deactivate-preview")
    def deactivate_preview(self, request, pk=None):
        """'What happens' text in the Deactivate modal."""
        user = self.get_object()
        others = [
            {"id": str(u.id), "full_name": u.full_name,
             "free": max(u.trainer_profile.max_clients - u.n_clients, 0)}
            for u in trainers_queryset().filter(status=AccountStatus.ACTIVE).exclude(id=user.id)
            if u.n_clients < u.trainer_profile.max_clients
        ]
        return Response({"clients": user.n_clients, "trainers_with_space": others})

    @action(detail=True, methods=["post"])
    def deactivate(self, request, pk=None):
        user = self.get_object()
        if user.is_admin or user.trainer_profile.is_owner:
            return _deny("The owner cannot be deactivated.")
        move_to = request.data.get("move_to")  # optional: "share" or a trainer id
        if move_to:
            try:
                move_clients(actor=request.user, source=user, to=move_to, tell_clients=True)
            except ValueError as e:
                return _deny(str(e), code="invalid", http=400)
        user.status = AccountStatus.DEACTIVATED
        user.save(update_fields=["status"])
        user.sessions.filter(revoked_at__isnull=True).update(revoked_at=timezone.now())
        activity_log("deactivated a trainer", "team", actor=request.user, target=user, target_label=user.full_name,
                     change=("Active", "Inactive"), trainer=user)
        return Response(TrainerRowSerializer(self.get_queryset().get(id=user.id)).data)

    @action(detail=True, methods=["post"])
    def reactivate(self, request, pk=None):
        user = self.get_object()
        user.status = AccountStatus.ACTIVE
        user.save(update_fields=["status"])
        activity_log("reactivated a trainer", "team", actor=request.user, target=user, target_label=user.full_name,
                     change=("Inactive", "Active"), trainer=user)
        return Response(TrainerRowSerializer(self.get_queryset().get(id=user.id)).data)

    @action(detail=True, methods=["post"], url_path="password-reset")
    def password_reset(self, request, pk=None):
        user = self.get_object()
        send_reset_link(user)
        activity_log("sent a password reset link", "team", actor=request.user, target=user,
                     target_label=user.full_name, trainer=user)
        return Response({"sent": True})

    # ------------------------------------------------------------ clients
    @extend_schema(request=MoveClientsSerializer)
    @action(detail=True, methods=["post"], url_path="move-clients")
    def move_clients(self, request, pk=None):
        user = self.get_object()
        s = MoveClientsSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        try:
            moved = move_clients(actor=request.user, source=user, to=s.validated_data["to"],
                                 client_ids=s.validated_data.get("clients"),
                                 tell_clients=s.validated_data["tell_clients"])
        except ValueError as e:
            return _deny(str(e), code="invalid", http=400)
        return Response({"moved": len(moved)})

    @action(detail=True, url_path="assignable-clients")
    def assignable_clients(self, request, pk=None):
        """Assign clients drawer: clients with no trainer first, then other trainers' clients."""
        user = self.get_object()
        load = {u.id: u for u in trainers_queryset()}
        qs = (ClientProfile.objects.filter(removed_at__isnull=True, user__status__in=[AccountStatus.ACTIVE,
                                                                                         AccountStatus.PAUSED])
              .exclude(trainer=user).select_related("user", "trainer")
              .order_by(F("trainer").asc(nulls_first=True), "user__full_name"))
        q = request.query_params.get("search")
        if q:
            qs = qs.filter(user__full_name__icontains=q)
        out = []
        for cp in qs[:200]:
            t = load.get(cp.trainer_id)
            out.append({
                "id": str(cp.user_id), "full_name": cp.user.full_name, "initials": cp.user.initials,
                "avatar_color": cp.user.avatar_color, "goal": cp.goal,
                "from": None if t is None else {"id": str(t.id), "full_name": t.full_name,
                                                "full": t.n_clients >= t.trainer_profile.max_clients},
            })
        return Response(out)

    @extend_schema(request=AssignClientsSerializer)
    @action(detail=True, methods=["post"], url_path="assign-clients")
    def assign_clients(self, request, pk=None):
        user = self.get_object()
        s = AssignClientsSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        free = user.trainer_profile.max_clients - user.n_clients
        if len(d["clients"]) > free:
            return _deny(f"{user.first_name} has {max(free, 0)} free spots. Raise max clients first.",
                         code="trainer_full", http=400)
        profiles = list(ClientProfile.objects.filter(user_id__in=d["clients"], removed_at__isnull=True)
                        .select_related("user", "trainer"))
        with transaction.atomic():
            for cp in profiles:
                old = cp.trainer
                cp.trainer = user
                cp.save(update_fields=["trainer", "updated_at"])
                activity_log("changed trainer", "client", actor=request.user, target=cp.user,
                             target_label=cp.user.full_name,
                             change=(old.full_name if old else "No trainer", user.full_name), client=cp.user,
                             trainer=user, meta={"keep_plans": d["keep_plans"]})
                if not d["keep_plans"]:
                    from apps.training.models import AssignmentStatus, ProgramAssignment

                    ProgramAssignment.objects.filter(client=cp.user, status=AssignmentStatus.ACTIVE).update(
                        status=AssignmentStatus.ENDED, end_date=timezone.localdate())
        if d["tell_clients"]:
            notify([cp.user for cp in profiles], "trainer_changed", f"{user.full_name} is your trainer now", "",
                   actor=request.user)
        if profiles and user != request.user:
            notify(user, "client_assigned", f"{len(profiles)} new clients for you", "", actor=request.user,
                   data={"route": "/clients"})
        return Response({"assigned": len(profiles)})

    # ------------------------------------------------------------ access
    @action(detail=True, methods=["get", "put"])
    def access(self, request, pk=None):
        user = self.get_object()
        tp = user.trainer_profile
        if request.method == "PUT":
            s = AccessSerializer(data=request.data)
            s.is_valid(raise_exception=True)
            old = tp.get_access_mode_display()
            tp.access_mode = s.validated_data["access_mode"]
            if tp.access_mode == AccessMode.CUSTOM:
                tp.permissions = {k: bool(v) for k, v in s.validated_data.get("permissions", {}).items()}
            else:
                tp.permissions = {}
            tp.save(update_fields=["access_mode", "permissions", "updated_at"])
            activity_log("changed access", "team", actor=request.user, target=user, target_label=user.full_name,
                         change=(old, tp.get_access_mode_display()), trainer=user)
            notify(user, "access_changed", "Your access was updated", "Open Me → My access to see what changed.",
                   actor=request.user, data={"route": "/me/access"})
        perms = tp.effective_permissions()
        return Response({"access_mode": tp.access_mode, "groups": permission_groups(perms),
                         "on": sum(1 for v in perms.values() if v), "total": len(ALL_KEYS)})

    @action(detail=True, methods=["get", "put"])
    def visibility(self, request, pk=None):
        user = self.get_object()
        return _visibility(request, user)

    @action(detail=True)
    def stats(self, request, pk=None):
        return Response(trainer_stats(self.get_object()))

    @action(detail=True)
    def activity(self, request, pk=None):
        """Trainer profile → Activity tab: what this trainer did (same rows as My activity)."""
        from .me import activity_response

        return activity_response(self.get_object(), request)

    @action(detail=True)
    def clients(self, request, pk=None):
        """Trainer profile → Clients tab: his clients with program, adherence, last check-in, status and since.
        ?search= &status=active|at_risk|paused|pending &goal= &page= (20 a page), most recent first."""
        from apps.checkins.models import Submission
        from apps.clients.serializers import badge_for
        from apps.common.utils import dfmt
        from apps.training.models import AssignmentStatus, ProgramAssignment

        user = self.get_object()
        p = request.query_params
        qs = (User.objects.filter(client_profile__trainer=user, client_profile__removed_at__isnull=True,
                                  status__in=[AccountStatus.ACTIVE, AccountStatus.PAUSED, AccountStatus.PENDING])
              .select_related("client_profile")
              .order_by(F("client_profile__trainer_since").desc(nulls_last=True), "-date_joined"))
        if p.get("search"):
            q = p["search"].strip()
            qs = qs.filter(Q(full_name__icontains=q) | Q(email__icontains=q) | Q(phone__icontains=q))
        if p.get("goal"):
            qs = qs.filter(client_profile__goal=p["goal"])
        st = p.get("status")
        if st == "at_risk":
            qs = qs.filter(status=AccountStatus.ACTIVE, client_profile__at_risk=True)
        elif st == "active":
            qs = qs.filter(status=AccountStatus.ACTIVE, client_profile__at_risk=False)
        elif st in ("paused", "pending"):
            qs = qs.filter(status=st)
        total = qs.count()
        try:
            page = max(1, int(p.get("page", 1)))
            size = min(50, max(1, int(p.get("page_size", 20))))
        except ValueError:
            page, size = 1, 20
        rows = list(qs[(page - 1) * size: page * size])
        ids = [u.id for u in rows]
        plans = {}
        for a in (ProgramAssignment.objects.filter(client_id__in=ids, status=AssignmentStatus.ACTIVE)
                  .select_related("program", "custom_program").order_by("client_id", "-start_date")):
            plans.setdefault(a.client_id, a)
        last = {}
        for c, at in (Submission.objects.filter(client_id__in=ids).order_by("client_id", "-created_at")
                      .values_list("client_id", "created_at")):
            last.setdefault(c, at)
        today = timezone.localdate()

        def program(u):
            a = plans.get(u.id)
            if a is None:
                return "Not started"
            name = a.effective_program.name
            if u.status == AccountStatus.PAUSED:
                return f"{name} · paused"
            if a.start_date > today:
                return f"{name} · starts {dfmt(a.start_date, '%-d %b')}"
            return f"{name} · wk {(today - a.start_date).days // 7 + 1}"

        def checkin(u):
            at = last.get(u.id)
            if at is None:
                return "—"
            local = timezone.localtime(at)
            days = (today - local.date()).days
            if days == 0:
                return "Today, " + dfmt(local, "%-I:%M %p").lower()
            if days == 1:
                return "Yesterday"
            if days < 7:
                return f"{days} days ago"
            if days < 14:
                return "1 week ago"
            if days < 60:
                return f"{days // 7} weeks ago"
            return dfmt(local, "%-d %b %Y")

        out = []
        for u in rows:
            cp = u.client_profile
            since = cp.trainer_since or u.date_joined
            out.append({
                "id": str(u.id), "full_name": u.full_name, "initials": u.initials, "avatar_color": u.avatar_color,
                "avatar": u.avatar.url if getattr(u, "avatar", None) else None,
                "goal_label": cp.get_goal_display() if cp.goal else "", "program": program(u),
                "adherence": cp.adherence_7d if u.status == AccountStatus.ACTIVE else None,
                "last_checkin": checkin(u), "badge": badge_for(u), "since": since,
            })
        return Response({"count": total, "results": out})


def _visibility(request, user):
    tp = user.trainer_profile
    if request.method == "PUT":
        s = VisibilitySerializer(data=request.data)
        s.is_valid(raise_exception=True)
        tp.visibility = {**tp.visibility, **s.validated_data}
        tp.save(update_fields=["visibility", "updated_at"])
        from apps.notifications.realtime import send_to_user

        # "Changes here show up in the client app right away."
        for cid in user.coached_clients.values_list("user_id", flat=True):
            transaction.on_commit(lambda cid=cid: send_to_user(cid, "trainer_card_changed", {}))
    return Response({"visibility": tp.visibility, "preview": public_trainer_card(user, request)})


def trainer_stats(user):
    """The 4 stat cards on Trainer profile / Me."""
    tp = user.trainer_profile
    clients = ClientProfile.objects.filter(trainer=user, removed_at__isnull=True, user__status=AccountStatus.ACTIVE)
    n = clients.count()
    pending = review_queue(user).order_by("created_at")
    oldest = pending.first()
    adh = clients.aggregate(a=Avg("adherence_7d"))["a"]
    now = timezone.now()
    month_ago = clients.aggregate(a=Avg("adherence_30d"))["a"]
    reviewed = Submission.objects.filter(reviewed_by=user, reviewed_at__gte=now - timezone.timedelta(days=30))
    hours = [(s.reviewed_at - s.created_at).total_seconds() / 3600 for s in reviewed.only("reviewed_at",
                                                                                         "created_at")[:500]]
    team = Submission.objects.filter(reviewed_at__gte=now - timezone.timedelta(days=30))
    team_hours = [(s.reviewed_at - s.created_at).total_seconds() / 3600 for s in team.only("reviewed_at",
                                                                                          "created_at")[:2000]]
    return {
        "clients": n, "max_clients": tp.max_clients, "free": max(tp.max_clients - n, 0),
        "checkins_to_review": pending.count(),
        "oldest_checkin_at": oldest.created_at if oldest else None,
        "adherence": round(adh) if adh is not None else None,
        "adherence_change": round(adh - month_ago) if adh is not None and month_ago is not None else None,
        "reply_hours": round(sum(hours) / len(hours)) if hours else None,
        "team_reply_hours": round(sum(team_hours) / len(team_hours)) if team_hours else None,
    }


class TrainerDocumentViewSet(viewsets.ModelViewSet):
    """Documents tab. Admin manages any trainer's documents; a trainer uploads and sees their own
    (/trainers/me/documents/), but only the admin can mark them verified."""

    serializer_class = DocumentSerializer
    permission_classes = [IsStaff]
    parser_classes = [MultiPartParser, FormParser]
    pagination_class = None
    http_method_names = ["get", "post", "patch", "delete"]

    def _trainer(self):
        pk = self.kwargs["trainer_pk"]
        user = self.request.user
        if pk == "me":
            return get_object_or_404(TrainerProfile, user=user)
        if not user.is_admin:
            if str(user.id) != pk:
                from django.http import Http404

                raise Http404
        return get_object_or_404(TrainerProfile, user_id=pk)

    def get_queryset(self):
        return TrainerDocument.objects.filter(trainer=self._trainer()).select_related("verified_by")

    def perform_create(self, serializer):
        tp = self._trainer()
        doc = serializer.save(trainer=tp)
        activity_log("uploaded a document", "team", actor=self.request.user, target=tp.user,
                     target_label=doc.name, trainer=tp.user)
        if not self.request.user.is_admin:
            admin = User.objects.filter(role=Role.ADMIN).first()
            notify(admin, "trainer_document", f"{tp.user.full_name} uploaded {doc.name}", "Check it and mark it verified.",
                   actor=self.request.user, data={"route": f"/trainers/{tp.user_id}?tab=documents"})

    def perform_update(self, serializer):
        doc = serializer.save()
        if "file" in serializer.validated_data:  # Replace file -> needs checking again
            doc.verified_at = None
            doc.verified_by = None
            doc.save(update_fields=["verified_at", "verified_by"])

    def perform_destroy(self, instance):
        instance.file.delete(save=False)
        instance.delete()

    @action(detail=True, methods=["post"])
    def verify(self, request, trainer_pk=None, pk=None):
        if not request.user.is_admin:
            return _deny("Only Vimal can mark documents verified.")
        doc = self.get_object()
        doc.verified_at = timezone.now()
        doc.verified_by = request.user
        if doc.kind == TrainerDocument.Kind.CONTRACT:
            doc.signed = True
        doc.save(update_fields=["verified_at", "verified_by", "signed", "updated_at"])
        activity_log("verified a document", "team", actor=request.user, target=doc.trainer.user,
                     target_label=doc.name, trainer=doc.trainer.user)
        return Response(self.get_serializer(doc).data)


class AccessRequestViewSet(mixins.ListModelMixin, mixins.CreateModelMixin, viewsets.GenericViewSet):
    """Trainer → Ask for more access. Admin approves or declines."""

    serializer_class = AccessRequestSerializer
    permission_classes = [IsStaff]

    def get_queryset(self):
        qs = AccessRequest.objects.select_related("trainer__user").order_by("-created_at")
        if self.request.user.is_admin:
            st = self.request.query_params.get("status")
            return qs.filter(status=st) if st else qs
        return qs.filter(trainer__user=self.request.user)

    def perform_create(self, serializer):
        user = self.request.user
        if not user.is_trainer:
            from rest_framework.exceptions import PermissionDenied

            raise PermissionDenied("Only trainers ask for access.")
        req = serializer.save(trainer=user.trainer_profile)
        admin = User.objects.filter(role=Role.ADMIN).first()
        notify(admin, "access_request", f"{user.full_name} asked for more access", req.reason[:140],
               actor=user, data={"route": f"/trainers/{user.id}?tab=access", "request": str(req.id)})
        activity_log("asked for more access", "team", actor=user, target=user, target_label=user.full_name,
                     trainer=user)

    def _decide(self, request, pk, approve):
        if not request.user.is_admin:
            return _deny("Only Vimal decides access requests.")
        req = get_object_or_404(AccessRequest, pk=pk, status=AccessRequest.Status.OPEN)
        tp = req.trainer
        with transaction.atomic():
            if approve:
                perms = tp.effective_permissions()
                perms.update({k: True for k in req.permissions})
                tp.access_mode = AccessMode.CUSTOM
                tp.permissions = perms
                tp.save(update_fields=["access_mode", "permissions", "updated_at"])
            req.status = AccessRequest.Status.APPROVED if approve else AccessRequest.Status.DECLINED
            req.decided_by = request.user
            req.decided_at = timezone.now()
            req.save()
        notify(tp.user, "access_request_decided",
               "Vimal gave you more access" if approve else "Vimal declined your access request",
               "", actor=request.user, data={"route": "/me/access"})
        return Response(self.get_serializer(req).data)

    @action(detail=True, methods=["post"])
    def approve(self, request, pk=None):
        return self._decide(request, pk, True)

    @action(detail=True, methods=["post"])
    def decline(self, request, pk=None):
        return self._decide(request, pk, False)


class TrainerMeView(APIView):
    """Trainer → Me: own profile, stats, read-only access, visibility."""

    permission_classes = [IsStaff]

    def get(self, request):
        user = trainers_queryset().get(id=request.user.id)
        data = TrainerDetailSerializer(user, context={"request": request}).data
        data["stats"] = trainer_stats(user)
        data["access_groups"] = permission_groups(user.trainer_profile.effective_permissions())
        from .me import me_extras

        data.update(me_extras(user))
        return Response(data)

    def patch(self, request):
        user = request.user
        allowed = {k: v for k, v in request.data.items() if k not in ("access_mode", "max_clients", "joining_date",
                                                                       "send_invite", "send_password_reset")}
        s = TrainerWriteSerializer(user, data=allowed, partial=True)
        s.is_valid(raise_exception=True)
        d = dict(s.validated_data)
        for k in ("send_invite", "send_password_reset"):
            d.pop(k, None)
        tp = user.trainer_profile
        with transaction.atomic():
            for k in TrainerWriteSerializer.PROFILE_FIELDS:
                if k in d:
                    setattr(tp, k, d.pop(k))
            tp.save()
            if "email" in d and d["email"] != user.email:
                d.pop("email")  # email changes go through /auth/email/change/ (verification)
            for k, v in d.items():
                setattr(user, k, v)
            user.save()
        return self.get(request)


class TrainerMeVisibilityView(APIView):
    permission_classes = [IsStaff]

    def get(self, request):
        return _visibility(request, request.user)

    def put(self, request):
        return _visibility(request, request.user)
