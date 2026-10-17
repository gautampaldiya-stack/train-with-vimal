"""Client profile → Logs tab (staff): summary line, Compare plans, coach comments. See `logs.py`."""
import uuid

from django.http import Http404
from rest_framework import serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.permissions import IsStaff

from . import logs
from .metrics import resolve_range
from .services import get_visible_client


def _client(user, pk):
    try:
        return get_visible_client(user, pk)
    except Exception:
        raise Http404


class ClientLogSummaryView(APIView):
    """GET clients/<id>/logs/summary/?range= → {from, to, workouts, meals, checkins}."""

    permission_classes = [IsStaff]

    def get(self, request, client_pk):
        client = _client(request.user, client_pk)
        start, end = resolve_range(request.query_params, client)
        return Response(logs.summary(client, start, end))


class ClientLogCompareView(APIView):
    """GET clients/<id>/logs/compare/ → A and B side by side. Each side is a workout plan
    (`?a=plan:<assignment>` or `?a=<assignment>`) or any dates (`?a_from=2026-09-01&a_to=2026-09-30`), so a
    client on their first plan can still compare two halves of it or the last 30 days with the 30 before."""

    permission_classes = [IsStaff]

    def get(self, request, client_pk):
        from django.utils.dateparse import parse_date

        from apps.training.models import ProgramAssignment

        client = _client(request.user, client_pk)
        q = request.query_params
        out = []
        for key in ("a", "b"):
            if q.get(f"{key}_from") or q.get(f"{key}_to"):
                try:
                    start, end = parse_date(q.get(f"{key}_from") or ""), parse_date(q.get(f"{key}_to") or "")
                except ValueError:
                    start = end = None
                if not start or not end or start > end or (end - start).days > 3660:
                    raise serializers.ValidationError({key: ["Pick a start and an end date."]})
                out.append((start, end))
                continue
            raw = q.get(key) or ""
            try:
                v = uuid.UUID(raw[5:] if raw.startswith("plan:") else raw)
            except ValueError:
                v = None
            pa = ProgramAssignment.objects.filter(client=client, id=v).select_related(
                "program", "custom_program").first() if v else None
            if pa is None:
                raise serializers.ValidationError({key: ["Pick a plan or dates."]})
            out.append(pa)
        return Response(logs.compare(client, *out))


class CommentSerializer(serializers.Serializer):
    about = serializers.ChoiceField(choices=["workout", "meals"])
    date = serializers.DateField(required=False, allow_null=True)
    text = serializers.CharField(max_length=2000)


class ClientLogCommentView(APIView):
    """POST clients/<id>/logs/comment/ {about: workout|meals, date, text}: the client gets it in the app."""

    permission_classes = [IsStaff]

    def post(self, request, client_pk):
        client = _client(request.user, client_pk)
        s = CommentSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        text = s.validated_data["text"].strip()
        if not text:
            raise serializers.ValidationError({"text": ["Write a comment first."]})
        logs.comment(client, actor=request.user, about=s.validated_data["about"],
                     day=s.validated_data.get("date"), text=text)
        return Response({"sent": True}, status=status.HTTP_201_CREATED)
