from datetime import timedelta

from django.core.cache import cache
from django.db import transaction
from django.db.models import Count, Prefetch, Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from drf_spectacular.utils import extend_schema
from rest_framework import mixins, serializers, status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.activity.services import log as activity_log
from apps.clients.services import get_visible_client, visible_clients
from apps.common.mixins import SoftDeleteViewMixin
from apps.common.permissions import HasTrainerPermission, IsClient, IsStaff

from . import services
from .services import can_edit_program
from .models import (
    AssignmentStatus,
    Exercise,
    Program,
    ProgramAssignment,
    ProgramDay,
    ProgramExercise,
    SetLog,
    WorkoutLog,
)
from .serializers import (
    AssignmentSerializer,
    AssignSerializer,
    ExerciseMiniSerializer,
    ExerciseSerializer,
    FeedbackSerializer,
    FinishSerializer,
    ProgramCardSerializer,
    ProgramCreateSerializer,
    ProgramDetailSerializer,
    ProgramExerciseSerializer,
    SetLogSerializer,
    StateSerializer,
    StructureSerializer,
    WorkoutLogSerializer,
    WorkoutRowSerializer,
    facet_counts,
)


def _multi(params, key):
    raw = params.getlist(key) or []
    out = []
    for r in raw:
        out.extend([x for x in r.split(",") if x])
    return out


# ---------------------------------------------------------------- exercises
class ExerciseViewSet(SoftDeleteViewMixin, viewsets.ModelViewSet):
    serializer_class = ExerciseSerializer
    permission_classes = [IsStaff, HasTrainerPermission]
    required_permissions = {"create": "training.custom_exercises", "partial_update": "training.custom_exercises",
                            "update": "training.custom_exercises", "destroy": "training.custom_exercises",
                            "duplicate": "training.custom_exercises"}
    search_fields = ["name", "primary_muscle"]
    ordering_fields = ["name", "created_at", "updated_at", "n_programs"]
    ordering = ["name"]

    def get_queryset(self):
        qs = Exercise.objects.select_related("video").annotate(
            n_programs=Count("program_uses__day__week__program", distinct=True,
                             filter=Q(program_uses__day__week__program__is_master=True,
                                      program_uses__day__week__program__deleted_at__isnull=True)))
        return qs

    def filter_queryset(self, qs):
        qs = super().filter_queryset(qs)
        if self.action != "list":
            return qs
        return self._apply_facets(qs, self.request.query_params)

    @staticmethod
    def _apply_facets(qs, p, skip=None):
        if skip != "muscle" and _multi(p, "muscle"):
            qs = qs.filter(muscle_group__in=_multi(p, "muscle"))
        if skip != "equipment" and _multi(p, "equipment"):
            qs = qs.filter(equipment__in=_multi(p, "equipment"))
        if skip != "level" and _multi(p, "level"):
            qs = qs.filter(level__in=_multi(p, "level"))
        src = _multi(p, "source")
        if skip != "source" and src and len(src) == 1:
            qs = qs.filter(is_builtin=src[0] == "builtin")
        return qs

    @action(detail=False)
    def facets(self, request):
        """Filter panel counts + the page sub-line ('28 built-in · 0 custom by your team')."""
        base = Exercise.objects.all()
        q = request.query_params.get("search")
        if q:
            base = base.filter(name__icontains=q)
        data = facet_counts(base)
        data["builtin"] = Exercise.objects.filter(is_builtin=True).count()
        data["custom"] = Exercise.objects.filter(is_builtin=False).count()
        return Response(data)

    def perform_create(self, serializer):
        ex = serializer.save(created_by=self.request.user, is_builtin=False)
        activity_log("added an exercise", "plan", actor=self.request.user, target=ex, target_label=ex.name)

    def perform_destroy(self, instance):
        if instance.is_builtin:
            raise PermissionDenied("Built-in exercises can't be deleted.")
        instance.soft_delete()

    @action(detail=True, methods=["post"])
    def duplicate(self, request, pk=None):
        """'Duplicate to edit': an editable copy of a built-in exercise."""
        src = self.get_object()
        fields = {f.name: getattr(src, f.name) for f in Exercise._meta.concrete_fields
                  if f.name not in ("id", "created_at", "updated_at", "deleted_at", "is_builtin", "duplicated_from",
                                    "created_by", "name")}
        fields["video_id"] = fields.pop("video").id if fields.get("video") else None
        ex = Exercise.objects.create(name=f"{src.name} (copy)"[:120], duplicated_from=src, is_builtin=False,
                                     created_by=request.user, **fields)
        return Response(ExerciseSerializer(ex).data, status=status.HTTP_201_CREATED)

    @action(detail=True, url_path="used-in")
    def used_in(self, request, pk=None):
        """'Used in N programs': program, day name, workouts logged, clients."""
        ex = self.get_object()
        rows = (ProgramExercise.objects.filter(exercise=ex, day__week__program__is_master=True,
                                               day__week__program__deleted_at__isnull=True)
                .select_related("day__week__program"))
        progs = {}
        for pe in rows:
            p = pe.day.week.program
            item = progs.setdefault(p.id, {"id": str(p.id), "name": p.name, "days": set()})
            if pe.day.name:
                item["days"].add(pe.day.name)
        out = []
        for pid, item in progs.items():
            item["days"] = sorted(item["days"])
            item["clients"] = ProgramAssignment.objects.filter(program_id=pid, status="active").count()
            item["workouts"] = SetLog.objects.filter(exercise=ex, workout__assignment__program_id=pid,
                                                     workout__status="completed").values("workout").distinct().count()
            out.append(item)
        return Response(out)


# ---------------------------------------------------------------- programs
class ProgramViewSet(SoftDeleteViewMixin, viewsets.ModelViewSet):
    permission_classes = [IsStaff, HasTrainerPermission]
    search_fields = ["name", "goal_line"]
    ordering = ["-updated_at"]
    http_method_names = ["get", "post", "patch", "put", "delete"]

    def check_permissions(self, request):
        super().check_permissions(request)
        user = request.user
        if user.is_trainer and request.method not in ("GET", "HEAD", "OPTIONS"):
            tp = user.trainer_profile
            needed = {"create": "training.use_templates", "duplicate": "training.use_templates",
                      "assign": "training.programs_edit"}.get(self.action)
            if needed and not tp.has_perm(needed):
                raise PermissionDenied("Your access does not include this. Ask Vimal for more access.")

    def check_object_permissions(self, request, obj):
        """Changing a master plan (rename, days, archive, delete) needs `can_edit_program` (D-39)."""
        super().check_object_permissions(request, obj)
        if request.method not in ("GET", "HEAD", "OPTIONS") and self.action not in ("duplicate", "assign"):
            if not can_edit_program(request.user, obj):
                raise PermissionDenied("Only Vimal or a trainer with \"Edit gym templates\" can change this program. "
                                       "Duplicate it to make your own.")

    def get_serializer_context(self):
        return {**super().get_serializer_context(), "request": self.request}

    def _visible_assignments(self):
        """Trainers see only their own clients on the cards and in counts (golden rule)."""
        qs = ProgramAssignment.objects.filter(status="active")
        if self.request.user.is_trainer:
            qs = qs.filter(client__in=visible_clients(self.request.user))
        return qs

    def get_queryset(self):
        qs = Program.objects.filter(is_master=True)
        if self.action == "list":
            tab = self.request.query_params.get("tab", "active")
            qs = qs.filter(archived_at__isnull=tab != "archived")
            qs = qs.annotate(n_clients=Count("assignments", filter=Q(assignments__status="active"), distinct=True))
            qs = qs.prefetch_related(Prefetch("program_weeks__days", queryset=ProgramDay.objects.all()))
        elif self.action == "retrieve":
            qs = qs.annotate(n_clients=Count("assignments", filter=Q(assignments__status="active"), distinct=True))
            qs = qs.prefetch_related("program_weeks__days__exercises__exercise")
        return qs

    def get_serializer_class(self):
        if self.action == "create":
            return ProgramCreateSerializer
        if self.action == "retrieve":
            return ProgramDetailSerializer
        return ProgramCardSerializer

    def list(self, request, *args, **kwargs):
        qs = self.filter_queryset(self.get_queryset())
        page = self.paginate_queryset(qs)
        rows = page if page is not None else list(qs)
        ids = [p.id for p in rows]
        previews, counts = {}, {}
        for a in (self._visible_assignments().filter(program_id__in=ids)
                  .select_related("client").order_by("program_id", "-created_at")):
            counts[a.program_id] = counts.get(a.program_id, 0) + 1
            lst = previews.setdefault(a.program_id, [])
            if len(lst) < 3:
                lst.append(a.client)
        week1 = {}
        for d in ProgramDay.objects.filter(week__program_id__in=ids, week__number=1).select_related("week"):
            week1.setdefault(d.week.program_id, {})[d.weekday] = not d.is_rest
        for p in rows:
            p._preview_clients = previews.get(p.id, [])
            p._week1 = week1.get(p.id, {})
            p.n_clients = counts.get(p.id, 0)
        data = ProgramCardSerializer(rows, many=True, context=self.get_serializer_context()).data
        return self.get_paginated_response(data) if page is not None else Response(data)

    @action(detail=False)
    def counts(self, request):
        qs = Program.objects.filter(is_master=True)
        u = request.user
        can = lambda k: u.is_admin or (u.is_trainer and u.trainer_profile.has_perm(k))  # noqa: E731
        return Response({"active": qs.filter(archived_at__isnull=True).count(),
                         "archived": qs.filter(archived_at__isnull=False).count(),
                         # what the page offers this person (D-39): New program / Duplicate, Assign
                         "can": {"create": can("training.use_templates"), "assign": can("training.programs_edit"),
                                 "edit_all": can("training.edit_templates")}})

    def retrieve(self, request, *args, **kwargs):
        p = self.get_object()
        p.n_clients = self._visible_assignments().filter(program=p).count()
        return Response(ProgramDetailSerializer(p, context=self.get_serializer_context()).data)

    def create(self, request, *args, **kwargs):
        s = ProgramCreateSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        p = services.new_program(actor=request.user, **s.validated_data)
        activity_log("created a program", "plan", actor=request.user, target=p, target_label=p.name)
        return Response(ProgramDetailSerializer(p, context=self.get_serializer_context()).data,
                        status=status.HTTP_201_CREATED)

    def partial_update(self, request, *args, **kwargs):
        p = self.get_object()
        s = ProgramCreateSerializer(p, data=request.data, partial=True)
        s.is_valid(raise_exception=True)
        old = p.name
        s.save()
        if "name" in s.validated_data and old != p.name:
            activity_log("renamed a program", "plan", actor=request.user, target=p, target_label=p.name,
                         change=(old, p.name))
        return Response(ProgramCardSerializer(p, context=self.get_serializer_context()).data)

    def destroy(self, request, *args, **kwargs):
        p = self.get_object()
        ended = list(ProgramAssignment.objects.filter(program=p, status__in=["active", "up_next"])
                     .values_list("id", "status"))
        n = sum(1 for _, st in ended if st == "active")
        with transaction.atomic():
            p.soft_delete()
            ProgramAssignment.objects.filter(id__in=[i for i, _ in ended]).update(
                status=AssignmentStatus.ENDED, end_date=timezone.localdate())
        # Undo (restore) puts these clients back on the plan.
        cache.set(f"program-unassigned:{p.id}", [(str(i), st) for i, st in ended], 60 * 60)
        activity_log("deleted a program", "plan", actor=request.user, target=p, target_label=p.name,
                     meta={"unassigned": n})
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["post"])
    def restore(self, request, pk=None):
        """The delete toast's Undo: the program comes back and the clients it was taken from follow it again."""
        p = Program.all_objects.filter(pk=pk, is_master=True, deleted_at__isnull=False).first()
        if p is None:
            return Response({"error": {"code": "not_found", "message": "Nothing to restore."}}, status=404)
        self.check_object_permissions(request, p)
        ended = cache.get(f"program-unassigned:{p.id}") or []
        with transaction.atomic():
            p.restore()
            for aid, st in ended:
                ProgramAssignment.objects.filter(id=aid, program=p, status=AssignmentStatus.ENDED).update(
                    status=st, end_date=None)
        cache.delete(f"program-unassigned:{p.id}")
        p.n_clients = self._visible_assignments().filter(program=p).count()
        return Response(ProgramCardSerializer(p, context=self.get_serializer_context()).data)

    @action(detail=True, url_path="delete-preview")
    def delete_preview(self, request, pk=None):
        p = self.get_object()
        return Response({"clients": ProgramAssignment.objects.filter(program=p, status="active").count()})

    @action(detail=True, methods=["post"])
    def duplicate(self, request, pk=None):
        p = services.duplicate_program(self.get_object(), actor=request.user)
        return Response(ProgramCardSerializer(p, context=self.get_serializer_context()).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"])
    def archive(self, request, pk=None):
        p = self.get_object()
        p.archived_at = timezone.now()
        p.save(update_fields=["archived_at", "updated_at"])
        activity_log("archived a program", "plan", actor=request.user, target=p, target_label=p.name)
        return Response(ProgramCardSerializer(p, context=self.get_serializer_context()).data)

    @action(detail=True, methods=["post"])
    def unarchive(self, request, pk=None):
        p = self.get_object()
        p.archived_at = None
        p.save(update_fields=["archived_at", "updated_at"])
        return Response(ProgramCardSerializer(p, context=self.get_serializer_context()).data)

    @extend_schema(request=StructureSerializer)
    @action(detail=True, methods=["put"])
    def structure(self, request, pk=None):
        p = self.get_object()
        s = StructureSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        services.sync_structure(p, s.validated_data["weeks"])
        p = Program.objects.prefetch_related("program_weeks__days__exercises__exercise").get(id=p.id)
        return Response(ProgramDetailSerializer(p, context=self.get_serializer_context()).data)

    @action(detail=True, methods=["post"], url_path="copy-week")
    def copy_week(self, request, pk=None):
        p = self.get_object()
        try:
            n = int(request.data.get("week"))
        except (TypeError, ValueError):
            raise serializers.ValidationError({"week": ["Pick a week."]})
        if not p.program_weeks.filter(number=n).exists():
            raise serializers.ValidationError({"week": ["No such week."]})
        services.copy_week(p, n)
        p = Program.objects.prefetch_related("program_weeks__days__exercises__exercise").get(id=p.id)
        return Response(ProgramDetailSerializer(p, context=self.get_serializer_context()).data)

    @action(detail=True)
    def clients(self, request, pk=None):
        """Clients drawer: who follows this program, Master or Custom."""
        p = self.get_object()
        rows = (ProgramAssignment.objects.filter(program=p, status="active")
                .select_related("client", "client__client_profile__trainer"))
        visible = set(visible_clients(request.user).values_list("id", flat=True))
        return Response([{**AssignmentSerializer(a).data,
                          "goal": a.client.client_profile.get_goal_display(),
                          "trainer": a.client.client_profile.trainer.full_name
                          if a.client.client_profile.trainer else None}
                         for a in rows if a.client_id in visible])

    @extend_schema(request=AssignSerializer)
    @action(detail=True, methods=["post"])
    def assign(self, request, pk=None):
        """Assign drawer save: the followers become exactly the ticked clients."""
        p = self.get_object()
        s = AssignSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        if p.archived_at:
            raise serializers.ValidationError("Restore the program before assigning it.")
        added, removed = services.set_program_clients(p, s.validated_data["clients"], actor=request.user)
        return Response({"added": added, "removed": removed})

    @action(detail=False, url_path="assign-options")
    def assign_options(self, request):
        """Assign drawer list: every visible client with goal, trainer and current program."""
        current = {a.client_id: a.effective_program.name for a in
                   ProgramAssignment.objects.filter(status="active").select_related("program", "custom_program")}
        rows = visible_clients(request.user).filter(status__in=["active", "paused"]).select_related(
            "client_profile__trainer")
        return Response([{"id": str(u.id), "full_name": u.full_name, "initials": u.initials,
                          "avatar_color": u.avatar_color, "goal": u.client_profile.get_goal_display(),
                          "trainer": u.client_profile.trainer.full_name if u.client_profile.trainer else None,
                          "current_program": current.get(u.id)} for u in rows])


class ExercisePickerView(APIView):
    """Add exercise picker in the builder: muscle chips with counts + rows."""

    permission_classes = [IsStaff]

    def get(self, request):
        qs = Exercise.objects.all()
        q = request.query_params.get("search")
        if q:
            qs = qs.filter(name__icontains=q)
        counts = dict(qs.order_by().values_list("muscle_group").annotate(n=Count("id")))
        m = request.query_params.get("muscle")
        if m:
            qs = qs.filter(muscle_group=m)
        return Response({"counts": counts, "all": sum(counts.values()),
                         "results": ExerciseMiniSerializer(qs[:300], many=True).data})


# ---------------------------------------------------------------- client plans (staff)
class ClientProgramViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    """Client profile → Plans → Workout slot."""

    serializer_class = AssignmentSerializer
    permission_classes = [IsStaff, HasTrainerPermission]
    required_permission = None
    pagination_class = None

    def _client(self):
        try:
            return get_visible_client(self.request.user, self.kwargs["client_pk"])
        except Exception:
            from django.http import Http404

            raise Http404

    def check_permissions(self, request):
        super().check_permissions(request)
        if request.user.is_trainer and request.method not in ("GET", "HEAD", "OPTIONS"):
            if not request.user.trainer_profile.has_perm("training.programs_edit"):
                raise PermissionDenied("Your access does not include editing programs.")

    def get_queryset(self):
        return ProgramAssignment.objects.filter(client=self._client()).select_related(
            "program", "custom_program", "client", "assigned_by")

    def list(self, request, *args, **kwargs):
        qs = list(self.get_queryset())
        ser = lambda xs: AssignmentSerializer(xs, many=True).data  # noqa: E731
        return Response({
            "current": ser([a for a in qs if a.status == "active"]),
            "up_next": ser([a for a in qs if a.status == "up_next"]),
            "history": ser([a for a in qs if a.status == "ended"]),
        })

    @extend_schema(request=AssignSerializer)
    def create(self, request, client_pk=None):
        client = self._client()
        program = request.data.get("program")
        when = request.data.get("when", "now")
        if when not in ("now", "after_current"):
            raise serializers.ValidationError({"when": ["Pick when it starts."]})
        start = request.data.get("start_date")
        from django.utils.dateparse import parse_date

        a = services.assign_program(client, program, actor=request.user, when=when,
                                    start_date=parse_date(start) if start else None,
                                    notify_client=request.data.get("notify", True) is not False)
        return Response(AssignmentSerializer(a).data, status=status.HTTP_201_CREATED)

    def _get(self, pk):
        return get_object_or_404(self.get_queryset(), pk=pk)

    @action(detail=True, methods=["post"])
    def customise(self, request, client_pk=None, pk=None):
        """'Edit X for Riya' → returns the client's own copy to open in the builder."""
        a = self._get(pk)
        copy = services.customise_for_client(a, actor=request.user)
        copy = Program.objects.prefetch_related("program_weeks__days__exercises__exercise").get(id=copy.id)
        return Response(ProgramDetailSerializer(copy).data)

    @action(detail=True, methods=["get", "put"], url_path="custom-structure")
    def custom_structure(self, request, client_pk=None, pk=None):
        a = self._get(pk)
        if request.method == "PUT":
            copy = services.customise_for_client(a, actor=request.user)
            s = StructureSerializer(data=request.data)
            s.is_valid(raise_exception=True)
            services.sync_structure(copy, s.validated_data["weeks"])
        prog = a.custom_program or a.program
        prog = Program.objects.prefetch_related("program_weeks__days__exercises__exercise").get(id=prog.id)
        return Response(ProgramDetailSerializer(prog).data)

    @action(detail=True, methods=["post"], url_path="new-from")
    def new_from(self, request, client_pk=None, pk=None):
        """'New plan for Riya: copy of X' + optional 'Also save to the library as a new master plan'."""
        a = self._get(pk)
        name = (request.data.get("name") or f"{a.effective_program.name} (copy)").strip()[:120]
        also_master = bool(request.data.get("save_to_library"))
        # "Starts": after the current plan ends (Up next) or now (replaces it).
        when = request.data.get("when", "now")
        if when not in ("now", "after_current"):
            raise serializers.ValidationError({"when": ["Pick when it starts."]})
        with transaction.atomic():
            if also_master:
                if request.user.is_trainer and not request.user.trainer_profile.has_perm("training.use_templates"):
                    raise PermissionDenied("Ask Vimal to save new master plans.")
                master = services.duplicate_program(a.effective_program, actor=request.user, name=name)
                new_a = services.assign_program(a.client, master, actor=request.user, when=when)
            else:
                master = a.program
                copy = services.duplicate_program(a.effective_program, actor=request.user, name=name,
                                                  as_master=False, master=a.program)
                new_a = services.assign_program(a.client, master, actor=request.user, when=when)
                new_a.custom_program = copy
                new_a.save(update_fields=["custom_program"])
        return Response(AssignmentSerializer(new_a).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"], url_path="reset-to-master")
    def reset_to_master(self, request, client_pk=None, pk=None):
        a = services.reset_to_master(self._get(pk), actor=request.user)
        return Response(AssignmentSerializer(a).data)

    @action(detail=True, methods=["post"])
    def replace(self, request, client_pk=None, pk=None):
        a = self._get(pk)
        new = services.assign_program(a.client, request.data.get("program"), actor=request.user)
        return Response(AssignmentSerializer(new).data)

    @action(detail=True, methods=["post"])
    def end(self, request, client_pk=None, pk=None):
        a = self._get(pk)
        if a.status == "up_next":  # Up next taken off before it starts: nothing to keep in history
            if a.custom_program_id:
                a.custom_program.soft_delete()
            a.delete()
            return Response(status=status.HTTP_204_NO_CONTENT)
        services.end_assignment(a, actor=request.user)
        return Response(AssignmentSerializer(a).data)

    @action(detail=False)
    def compare(self, request, client_pk=None):
        """A/B view: two programs side by side (ids in ?a=&b=)."""
        visible_ids = set(Program.objects.filter(
            Q(is_master=True) | Q(assignments__client=self._client()) |
            Q(id__in=ProgramAssignment.objects.filter(client=self._client()).values("custom_program"))
        ).values_list("id", flat=True))
        out = []
        for key in ("a", "b"):
            pid = request.query_params.get(key)
            p = Program.objects.filter(id=pid, id__in=visible_ids).prefetch_related(
                "program_weeks__days__exercises__exercise").first() if pid else None
            if p is None:
                raise serializers.ValidationError({key: ["Pick a plan."]})
            out.append(ProgramDetailSerializer(p, context=self.get_serializer_context()).data)
        return Response({"a": out[0], "b": out[1]})


class ClientWorkoutLogViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """Client profile → Logs → Workouts (staff, read only)."""

    permission_classes = [IsStaff]

    def get_queryset(self):
        try:
            client = get_visible_client(self.request.user, self.kwargs["client_pk"])
        except Exception:
            from django.http import Http404

            raise Http404
        return WorkoutLog.objects.filter(client=client).exclude(status="discarded").prefetch_related("sets__exercise")

    def get_serializer_class(self):
        return WorkoutLogSerializer if self.action == "retrieve" else WorkoutRowSerializer

    def list(self, request, *args, **kwargs):
        """Workout log table: `?range=` (7d / 30d / 90d / 6m / start / plan:<id> / custom), `?page=`. Done and
        partly-done workouts, plus planned days that passed with nothing logged (status missed, no id)."""
        from apps.clients.logs import page_of
        from apps.clients.metrics import planned_workout_days, program_day_for, resolve_range

        from .services import body_weights, set_volume

        qs = self.get_queryset()  # 404 for a client this person may not see
        client = get_visible_client(request.user, self.kwargs["client_pk"])
        start, end = resolve_range(request.query_params, client)
        today = timezone.localdate()
        rows = []
        logs = list(qs.filter(date__range=(start, end)))
        body = body_weights(client.id)
        for w in logs:
            sets = [x for x in w.sets.all() if not x.is_warmup]
            done = w.status == "completed"
            rows.append({
                "id": str(w.id), "date": w.date, "name": w.name, "started_at": w.started_at,
                "status": ("partly" if w.sets_planned and w.sets_done < w.sets_planned else "done") if done
                else "in_progress",
                "sets_done": w.sets_done, "sets_planned": w.sets_planned,
                "volume": round(sum(set_volume(x, body(w.date)) for x in sets)), "duration_seconds": w.duration_seconds,
                "effort": w.effort, "exercises": len({x.exercise_id for x in sets if x.done}),
            })
        logged = {w.date for w in logs}
        for pa in ProgramAssignment.objects.filter(client=client, start_date__lte=end).filter(
                Q(end_date__isnull=True) | Q(end_date__gte=start)).select_related("program", "custom_program"):
            last = min(end, pa.end_date or end, today - timedelta(days=1))
            for d in planned_workout_days(pa, max(start, pa.start_date), last):
                if d in logged:
                    continue
                pd = program_day_for(pa, d)
                logged.add(d)
                rows.append({
                    "id": None, "date": d, "name": (pd.name if pd else "") or "Workout", "status": "missed",
                    "sets_done": 0, "sets_planned": 0, "volume": 0, "duration_seconds": 0, "effort": None,
                    "planned": [e.exercise.name for e in pd.exercises.select_related("exercise")] if pd else [],
                })
        rows.sort(key=lambda r: (r["date"], str(r.get("started_at") or "")), reverse=True)
        for r in rows:
            r.pop("started_at", None)
        return Response(page_of(rows, request.query_params))


# ---------------------------------------------------------------- client app
class MyTrainView(APIView):
    """Train tab: week strip, today's workout with targets, last time and PRs, the running workout."""

    permission_classes = [IsClient]

    def get(self, request):
        from django.utils.dateparse import parse_date

        from apps.activity.dashboard import _day_minutes, _person
        from apps.checkins.models import WeightLog
        from apps.scheduling.models import Session

        u = request.user
        day = parse_date(request.query_params.get("date") or "") or timezone.localdate()
        pa, pd, strip, week = services.today_plan(u, day)
        exercises, rows = [], []
        done_today = (WorkoutLog.objects.filter(client=u, date=day, status="completed")
                      .prefetch_related("sets").first())
        in_progress = (WorkoutLog.objects.filter(client=u, status="in_progress").prefetch_related("sets").first())
        here = in_progress if in_progress and in_progress.date == day else done_today
        if pd and not pd.is_rest:
            rows = list(pd.exercises.select_related("exercise", "exercise__video"))
            ids = [e.exercise_id for e in rows]
            last = services.last_performance(u, ids)
            prs = services.personal_bests(u, ids)
            for e in rows:
                d = ProgramExerciseSerializer(e).data
                d["exercise_full"] = ExerciseSerializer(e.exercise, context={"request": request}).data
                if e.override:
                    d["exercise_full"].update({k: v for k, v in e.override.items() if k in d["exercise_full"]})
                    if "video" in e.override:  # this program's own video / picture
                        from apps.content.library import media_of
                        from apps.content.models import ContentItem

                        own = ContentItem.objects.filter(id=e.override["video"]).first() if e.override["video"] else None
                        d["exercise_full"]["media"] = media_of(own, request)
                        d["exercise_full"]["video_title"] = own.title if own else None
                d["last_time"] = last.get(e.exercise_id)
                d["pr"] = prs.get(e.exercise_id)
                mine = [s for s in here.sets.all() if s.exercise_id == e.exercise_id] if here else []
                d["sets_done"] = sum(1 for s in mine if s.done and not s.is_warmup)
                exercises.append(d)
        start = timezone.make_aware(timezone.datetime.combine(day, timezone.datetime.min.time()))
        session = (Session.objects.filter(client=u, start__gte=start, start__lt=start + timedelta(days=1),
                                          status="booked").select_related("trainer").order_by("start").first())
        trainer = u.client_profile.trainer
        weigh = WeightLog.objects.filter(client=u).order_by("-date").first()
        live = None
        if in_progress:
            sets = [s for s in in_progress.sets.all() if not s.is_warmup]
            live = {"id": str(in_progress.id), "name": in_progress.name, "date": in_progress.date,
                    "started_at": in_progress.started_at, "paused_at": in_progress.paused_at,
                    "sets_done": sum(1 for s in sets if s.done), "sets_total": len(sets)}
        return Response({
            "date": day,
            "week": week,
            "weeks": pa.effective_program.weeks if pa else None,
            "program": pa.effective_program.name if pa else None,
            "strip": strip,
            "day": {"id": pd.id, "name": pd.name, "is_rest": pd.is_rest, "note": pd.rest_note,
                    "minutes": _day_minutes(rows)} if pd else None,
            "exercises": exercises,
            "completed_today": WorkoutRowSerializer(done_today).data if done_today else None,
            "in_progress": live,
            "trainer": _person(trainer) if trainer else None,
            "session": {"id": str(session.id), "start": session.start, "end": session.end,
                        "trainer": _person(session.trainer), "place": session.place, "is_call": session.is_call}
            if session else None,
            "bodyweight_kg": float(weigh.weight_kg) if weigh else None,
        })


class MyWorkoutViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """The logger. Start → tick sets → finish (or discard / restart / clear)."""

    permission_classes = [IsClient]

    def get_queryset(self):
        qs = WorkoutLog.objects.filter(client=self.request.user)
        if self.action == "list":
            qs = qs.filter(status="completed").prefetch_related("sets")
            name = (self.request.query_params.get("name") or "").strip()
            return qs.filter(name=name) if name else qs
        return qs.prefetch_related("sets__exercise")

    def list(self, request, *args, **kwargs):
        """Past workouts, newest first. `name` keeps one workout ("this workout only")."""
        res = super().list(request, *args, **kwargs)
        first = self.get_queryset().order_by("date").values_list("date", flat=True).first()
        if isinstance(res.data, dict):
            res.data["since"] = first
        return res

    def get_serializer_class(self):
        return WorkoutRowSerializer if self.action == "list" else WorkoutLogSerializer

    def create(self, request):
        """Start workout (returns the open one if a workout is already running)."""
        pd = None
        if request.data.get("program_day"):
            pa, today_pd, _, _ = services.today_plan(request.user)
            pd = get_object_or_404(ProgramDay, id=request.data["program_day"],
                                   week__program__in=[pa.effective_program] if pa else [])
        wl, created = services.start_workout(request.user, program_day=pd, name=request.data.get("name", ""))
        wl = self.get_queryset().get(id=wl.id)
        return Response(WorkoutLogSerializer(wl).data, status=201 if created else 200)

    def _open(self, pk):
        return get_object_or_404(WorkoutLog, id=pk, client=self.request.user, status="in_progress")

    @extend_schema(request=StateSerializer)
    @action(detail=True, methods=["put"], url_path="state")
    def state(self, request, pk=None):
        """Save the running workout as it is now (timer and every set). Safe to send again."""
        wl = self._open(pk)
        s = StateSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        new_best = services.save_state(wl, s.validated_data)
        data = WorkoutLogSerializer(self.get_queryset().get(id=wl.id)).data
        return Response({**data, "new_best": new_best})

    @action(detail=True, methods=["post"])
    def pause(self, request, pk=None):
        """The client left Train: the timer stops. Safe to send again."""
        wl = self._open(pk)
        if not wl.paused_at:
            # `at` = when the phone left Train (the request may arrive later from the outbox)
            at = parse_datetime(str(request.data.get("at") or ""))
            now = timezone.now()
            wl.paused_at = min(max(at, wl.started_at), now) if at and timezone.is_aware(at) else now
            wl.save(update_fields=["paused_at", "updated_at"])
        return Response(WorkoutLogSerializer(self.get_queryset().get(id=wl.id)).data)

    @action(detail=True, methods=["post"])
    def resume(self, request, pk=None):
        """Continue workout: the timer goes on from where it stopped."""
        wl = self._open(pk)
        if wl.paused_at:
            wl.started_at += timezone.now() - wl.paused_at
            wl.paused_at = None
            wl.save(update_fields=["started_at", "paused_at", "updated_at"])
        return Response(WorkoutLogSerializer(self.get_queryset().get(id=wl.id)).data)

    @action(detail=False, url_path="exercise-history")
    def exercise_history(self, request):
        """Logger → Past workouts: only this exercise, newest first, its sets in each workout."""
        ex = get_object_or_404(Exercise, id=request.query_params.get("exercise"))
        qs = (WorkoutLog.objects.filter(client=request.user, status="completed", sets__exercise=ex, sets__done=True)
              .distinct().order_by("-date", "-finished_at"))
        page = self.paginate_queryset(qs)
        ids = [w.id for w in page]
        sets = {}
        for st in (SetLog.objects.filter(workout_id__in=ids, exercise=ex, done=True)
                   .order_by("set_number")):
            sets.setdefault(st.workout_id, []).append(SetLogSerializer(st).data)
        rows = [{"id": str(w.id), "date": w.date, "name": w.name, "sets": sets.get(w.id, [])} for w in page]
        return self.get_paginated_response(rows)

    @action(detail=True, methods=["post"])
    def reopen(self, request, pk=None):
        """'Log more sets' after finishing: the same workout runs again, the timer goes on from its time."""
        wl = get_object_or_404(WorkoutLog, id=pk, client=request.user, status="completed")
        if WorkoutLog.objects.filter(client=request.user, status="in_progress").exclude(id=wl.id).exists():
            raise serializers.ValidationError({"workout": ["Finish the workout you are doing first."]})
        wl.status = WorkoutLog.Status.IN_PROGRESS
        wl.started_at = timezone.now() - timedelta(seconds=wl.duration_seconds)
        wl.finished_at = None
        wl.paused_at = None
        wl.reopened_at = timezone.now()
        wl.save(update_fields=["status", "started_at", "finished_at", "paused_at", "reopened_at", "updated_at"])
        return Response(WorkoutLogSerializer(self.get_queryset().get(id=wl.id)).data)

    @extend_schema(request=FeedbackSerializer)
    @action(detail=True, methods=["post"])
    def feedback(self, request, pk=None):
        """'Save and send to Aman': effort and the note, after the workout is saved."""
        wl = get_object_or_404(WorkoutLog, id=pk, client=request.user, status="completed")
        s = FeedbackSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        wl.effort = s.validated_data["effort"]
        wl.note = s.validated_data.get("note", "")
        wl.save(update_fields=["effort", "note", "updated_at"])
        trainer = request.user.client_profile.trainer
        if trainer:
            from apps.notifications.realtime import send_to_user

            transaction.on_commit(lambda: send_to_user(trainer.id, "client_activity", {
                "client": str(request.user.id), "kind": "workout_feedback", "workout": str(wl.id)}))
        return Response(WorkoutRowSerializer(wl).data)

    @action(detail=True, methods=["post"], url_path="sets")
    def add_set(self, request, pk=None):
        wl = self._open(pk)
        ex = get_object_or_404(Exercise, id=request.data.get("exercise"))
        n = (wl.sets.filter(exercise=ex).order_by("-set_number").values_list("set_number", flat=True).first() or 0)
        pe = wl.sets.filter(exercise=ex).values_list("program_exercise", flat=True).first()
        s = SetLog.objects.create(workout=wl, exercise=ex, set_number=n + 1, program_exercise_id=pe,
                                  is_bodyweight=bool(request.data.get("is_bodyweight")),
                                  is_warmup=bool(request.data.get("is_warmup")))
        return Response(SetLogSerializer(s).data, status=201)

    @action(detail=True, methods=["patch", "delete"], url_path=r"sets/(?P<set_id>\d+)")
    def set_detail(self, request, pk=None, set_id=None):
        wl = self._open(pk)
        s = get_object_or_404(SetLog, id=set_id, workout=wl)
        if request.method == "DELETE":
            data = SetLogSerializer(s).data  # returned so the app can Undo by re-adding
            s.delete()
            return Response(data)
        ser = SetLogSerializer(s, data=request.data, partial=True)
        ser.is_valid(raise_exception=True)
        done = ser.validated_data.pop("done", None)
        for f in ("program_exercise", "exercise", "set_number"):
            ser.validated_data.pop(f, None)
        ser.save()
        is_pr = False
        if done is not None:
            is_pr = services.mark_set(s, done=done)
        return Response({**SetLogSerializer(s).data, "new_best": is_pr})

    @action(detail=True, methods=["post"], url_path="restore-set")
    def restore_set(self, request, pk=None):
        """Undo of 'Delete set'."""
        wl = self._open(pk)
        ser = SetLogSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        s = ser.save(workout=wl)
        return Response(SetLogSerializer(s).data, status=201)

    @extend_schema(request=FinishSerializer)
    @action(detail=True, methods=["post"])
    def finish(self, request, pk=None):
        wl = self._open(pk)
        s = FinishSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        services.finish_workout(wl, **s.validated_data)
        return Response(WorkoutLogSerializer(self.get_queryset().get(id=wl.id)).data)

    @action(detail=True, methods=["post"])
    def discard(self, request, pk=None):
        """Nothing is saved. After "Log more sets" only the sets ticked since then go: the finished
        workout is kept as it was (same time, effort and note)."""
        wl = self._open(pk)
        if wl.reopened_at:
            at = wl.reopened_at
            wl.sets.exclude(done=True, done_at__lt=at).delete()
            wl.status = WorkoutLog.Status.COMPLETED
            wl.finished_at = at
            wl.started_at = at - timedelta(seconds=wl.duration_seconds)
            wl.paused_at = None
            wl.reopened_at = None
            wl.sets_done = wl.sets.filter(done=True, is_warmup=False).count()
            wl.save()
            return Response(status=204)
        wl.status = WorkoutLog.Status.DISCARDED
        wl.save(update_fields=["status"])
        wl.sets.all().delete()
        return Response(status=204)

    @action(detail=True, methods=["post"])
    def restart(self, request, pk=None):
        """Timer from 0:00. Returns the previous start so Undo can put it back."""
        wl = self._open(pk)
        prev = wl.started_at
        wl.started_at = timezone.now() if not request.data.get("started_at") else request.data["started_at"]
        wl.save(update_fields=["started_at"])
        return Response({"started_at": wl.started_at, "previous_started_at": prev})

    @action(detail=True, methods=["post"], url_path="clear-sets")
    def clear_sets(self, request, pk=None):
        """'Remove logged work': un-tick every set (Undo re-ticks the returned ids)."""
        wl = self._open(pk)
        ids = list(wl.sets.filter(done=True).values_list("id", flat=True))
        wl.sets.filter(id__in=ids).update(done=False, done_at=None, is_pr=False)
        return Response({"cleared": ids})

    @action(detail=False, methods=["post"])
    def sync(self, request):
        """A whole workout logged offline, sent when the network is back (send an Idempotency-Key)."""
        from apps.common.utils import sync_day, sync_time

        d = request.data
        sets = d.get("sets") or []
        if not isinstance(sets, list) or len(sets) > 200:
            raise serializers.ValidationError({"sets": ["Send up to 200 sets."]})
        day = sync_day(d.get("date"))
        pa, _, _, _ = services.today_plan(request.user, day)
        pd = None
        if d.get("program_day"):
            pd = ProgramDay.objects.filter(id=d["program_day"],
                                           week__program=pa.effective_program if pa else None).first()
        fin = FinishSerializer(data={k: d[k] for k in ("effort", "note", "duration_seconds", "time_breakdown")
                                     if k in d})
        fin.is_valid(raise_exception=True)
        with transaction.atomic():
            wl = WorkoutLog.objects.create(client=request.user, assignment=pa, program_day=pd,
                                           name=(d.get("name") or (pd.name if pd else "Workout"))[:80], date=day,
                                           started_at=sync_time(d.get("started_at")),
                                           sets_planned=sum(e.sets for e in pd.exercises.all()) if pd else 0)
            for row in sets:
                ser = SetLogSerializer(data=row)
                ser.is_valid(raise_exception=True)
                sl = ser.save(workout=wl)
                if row.get("done"):
                    sl.done_at = sync_time(row.get("done_at"))
                    sl.save(update_fields=["done_at"])
                    services.mark_set(sl, done=True)
            services.finish_workout(wl, **fin.validated_data)
            if d.get("finished_at"):
                wl.finished_at = sync_time(d["finished_at"])
                wl.save(update_fields=["finished_at"])
        return Response(WorkoutLogSerializer(self.get_queryset().get(id=wl.id)).data, status=201)

    @action(detail=True, methods=["post"], url_path="retick-sets")
    def retick_sets(self, request, pk=None):
        wl = self._open(pk)
        ids = [int(i) for i in request.data.get("ids", []) if str(i).isdigit()]
        wl.sets.filter(id__in=ids).update(done=True, done_at=timezone.now())
        return Response({"reticked": len(ids)})
