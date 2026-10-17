from django.core.exceptions import ValidationError as DjangoValidationError
from django.db.models import Count, Q
from rest_framework import mixins, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from apps.common.pagination import TimelineCursorPagination
from apps.common.permissions import IsStaff

from .filters import ActivityFilter
from .models import ActivityEvent, Kind
from .serializers import ActivityEventSerializer


class ActivityViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    """GET /activity/?range=7d&kind=plan&who=team&person=<id>

    Admin sees everything. A trainer sees rows about their own clients and their own actions.
    """

    serializer_class = ActivityEventSerializer
    permission_classes = [IsStaff]
    pagination_class = TimelineCursorPagination
    filterset_class = ActivityFilter

    def get_queryset(self):
        qs = ActivityEvent.objects.select_related("client")
        user = self.request.user
        if user.is_trainer and not user.trainer_profile.has_perm("clients.view_all"):
            mine = Q(trainer=user) | Q(actor=user)
            client = self.request.query_params.get("client")
            if client:
                # Client profile → Activity: a trainer sees everything about their own client, also rows from
                # before they took the client over (those carry the old trainer).
                from apps.clients.services import visible_clients

                try:
                    if visible_clients(user).filter(id=client).exists():
                        mine = Q(client_id=client)
                except (ValueError, DjangoValidationError):
                    pass
            qs = qs.filter(mine)
        return qs

    @action(detail=False)
    def counts(self, request):
        """Counts per kind for the kind chips, under the same filters."""
        qs = self.filter_queryset(self.get_queryset().order_by())
        rows = qs.values("kind").annotate(n=Count("id"))
        data = {k: 0 for k, _ in Kind.choices}
        for r in rows:
            data[r["kind"]] = r["n"]
        data["all"] = sum(data.values())
        if request.query_params.get("by_day"):
            # Client profile → Activity day headers ("Today · 3"): rows per local day under every filter, kind too.
            from django.db.models.functions import TruncDate
            from django.utils import timezone

            kind = request.query_params.get("kind")
            dq = qs.filter(kind=kind) if kind else qs
            rows = (dq.annotate(d=TruncDate("created_at", tzinfo=timezone.get_current_timezone()))
                    .values("d").annotate(n=Count("id")))
            data["days"] = {str(r["d"]): r["n"] for r in rows}
        return Response(data)

    @action(detail=False)
    def export(self, request):
        from apps.common.export import csv_response

        qs = self.filter_queryset(self.get_queryset()).order_by("-created_at")
        rows = (
            (e.created_at.isoformat(), e.actor_label, e.source, e.get_kind_display(), e.verb, e.target_label,
             e.change_from, e.change_to)
            for e in qs.iterator(chunk_size=2000)
        )
        return csv_response("activity", ["When", "Who", "Source", "Kind", "What", "On", "From", "To"], rows)

    def filter_queryset(self, queryset):
        kind = self.request.query_params.get("kind")
        qs = super().filter_queryset(queryset)
        if self.action == "counts" and kind:
            # chips show counts for every kind, so ignore the kind filter here
            params = self.request.query_params.copy()
            params.pop("kind")
            qs = ActivityFilter(params, queryset=queryset, request=self.request).qs
        return qs

