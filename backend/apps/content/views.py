from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import Count, Exists, OuterRef, Q
from django.shortcuts import get_object_or_404
from rest_framework import mixins, serializers, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response

from apps.activity.services import log as activity_log
from apps.clients.services import get_visible_client, visible_clients
from apps.common.mixins import SoftDeleteViewMixin
from apps.common.permissions import IsClient, IsStaff
from apps.common.validators import IMAGE_EXTENSIONS
from apps.notifications.services import notify

from .models import Category, ContentItem, ContentShare, ContentView

User = get_user_model()

LIMITS_MB = {"pdf": 25, "image": 10, "video": 500}
EXT = {"pdf": {"pdf"}, "image": set(IMAGE_EXTENSIONS), "video": {"mp4", "mov", "m4v", "webm"}}


class CategorySerializer(serializers.ModelSerializer):
    count = serializers.IntegerField(read_only=True, source="n", default=0)

    class Meta:
        model = Category
        fields = ["id", "name", "order", "count"]

    def validate_name(self, v):
        v = " ".join(v.split())
        if len(v) < 2:
            raise serializers.ValidationError("Enter a category name.")
        qs = Category.objects.filter(name__iexact=v)
        if self.instance:
            qs = qs.exclude(id=self.instance.id)
        if qs.exists():
            raise serializers.ValidationError("That category exists already.")
        return v


class ContentSerializer(serializers.ModelSerializer):
    category_name = serializers.CharField(source="category.name", read_only=True, default=None)
    added_by = serializers.CharField(source="created_by.full_name", read_only=True, default=None)
    shared_count = serializers.IntegerField(read_only=True, source="n_shares", default=0)
    file_url = serializers.SerializerMethodField()
    cover_url = serializers.SerializerMethodField()
    usage = serializers.SerializerMethodField()

    class Meta:
        model = ContentItem
        fields = ["id", "kind", "title", "category", "category_name", "description", "file", "file_url",
                  "youtube_url", "cover", "cover_url", "body", "read_minutes", "duration_seconds", "pages",
                  "file_size", "resolution", "share_everyone", "chapters", "outline", "shared_count", "added_by", "usage", "created_at",
                  "updated_at"]
        read_only_fields = ["file_size"]
        extra_kwargs = {"file": {"write_only": True, "required": False},
                        "cover": {"write_only": True, "required": False}}

    def _url(self, f):
        req = self.context.get("request")
        if not f:
            return None
        return req.build_absolute_uri(f.url) if req else f.url

    def get_file_url(self, obj):
        return self._url(obj.file)

    def get_cover_url(self, obj):
        return self._url(obj.cover)

    def get_usage(self, obj):
        n = getattr(obj, "n_exercises", None)
        return {"exercises": n if n is not None else obj.exercises.count()}

    def validate_title(self, v):
        v = " ".join(v.split())
        if len(v) < 2:
            raise serializers.ValidationError("Enter a name.")
        return v

    def validate_youtube_url(self, v):
        if v and not any(h in v for h in ("youtube.com/", "youtu.be/")):
            raise serializers.ValidationError("Paste a YouTube link, e.g. https://youtu.be/…")
        return v

    def validate_cover(self, f):
        if f and f.name.rsplit(".", 1)[-1].lower() not in IMAGE_EXTENSIONS:
            raise serializers.ValidationError("The cover must be a JPG, PNG or WebP image.")
        return f

    def validate(self, attrs):
        kind = attrs.get("kind", self.instance.kind if self.instance else None)
        f = attrs.get("file")
        if f:
            ext = f.name.rsplit(".", 1)[-1].lower()
            if kind in EXT and ext not in EXT[kind]:
                raise serializers.ValidationError({"file": [f"This file type is not allowed for {kind}."]})
            if kind in LIMITS_MB and f.size > LIMITS_MB[kind] * 1024 * 1024:
                raise serializers.ValidationError({"file": [f"Up to {LIMITS_MB[kind]} MB."]})
            attrs["file_size"] = f.size
        has_file = f or (self.instance and self.instance.file)
        if kind == "video" and not (has_file or attrs.get("youtube_url") or (self.instance and
                                                                               self.instance.youtube_url)):
            raise serializers.ValidationError({"file": ["Upload a video or paste a YouTube link."]})
        if kind in ("pdf", "image") and not has_file:
            raise serializers.ValidationError({"file": ["Upload the file."]})
        if kind == "article" and not (attrs.get("body") or (self.instance and self.instance.body)):
            raise serializers.ValidationError({"body": ["Write what clients read."]})
        return attrs


class ContentViewSet(SoftDeleteViewMixin, viewsets.ModelViewSet):
    serializer_class = ContentSerializer
    permission_classes = [IsStaff]
    parser_classes = [MultiPartParser, FormParser, JSONParser]
    search_fields = ["title", "description"]
    ordering = ["-created_at"]
    http_method_names = ["get", "post", "patch", "delete"]

    def check_permissions(self, request):
        super().check_permissions(request)
        u = request.user
        if u.is_trainer and request.method not in ("GET", "HEAD", "OPTIONS") and \
                not u.trainer_profile.has_perm("content.manage"):
            raise PermissionDenied("Your access does not include the content library.")

    def get_queryset(self):
        qs = ContentItem.objects.select_related("category", "created_by").annotate(
            n_shares=Count("shares", distinct=True), n_exercises=Count("exercises", distinct=True))
        p = self.request.query_params
        if p.get("kind"):
            qs = qs.filter(kind=p["kind"])
        if p.get("category"):
            qs = qs.filter(category_id=p["category"])
        return qs

    def perform_create(self, serializer):
        item = serializer.save(created_by=self.request.user)
        activity_log("added content", "content", actor=self.request.user, target=item, target_label=item.title)
        if item.share_everyone:
            self._announce(item, None)

    def _announce(self, item, clients):
        if clients is None:
            clients = list(User.objects.filter(role="client", status="active"))
        if clients:
            notify(clients, "content_shared", f"New in your library: {item.title}", item.description[:140],
                   actor=self.request.user, data={"route": f"/library/{item.id}"})

    @action(detail=True)
    def detail(self, request, pk=None):
        """Detail drawer: shared with, used in, stats."""
        item = self.get_object()
        shares = ContentShare.objects.filter(item=item).select_related("client")[:50]
        views = ContentView.objects.filter(item=item)
        opened = views.count()
        finished = views.filter(finished=True).count()
        from apps.training.models import Exercise, ProgramExercise

        used = [{"type": "exercise", "id": str(e.id), "name": e.name} for e in Exercise.objects.filter(video=item)]
        for pe in ProgramExercise.objects.filter(override__video=str(item.id)).select_related("day__week__program"):
            used.append({"type": "program", "id": str(pe.day.week.program_id), "name": pe.day.week.program.name})
        return Response({
            **ContentSerializer(item, context={"request": request}).data,
            "shared_with": {"everyone": item.share_everyone,
                            "clients": [{"id": str(s.client_id), "full_name": s.client.full_name,
                                         "initials": s.client.initials, "avatar_color": s.client.avatar_color}
                                        for s in shares]},
            "used_in": used,
            "stats": {"opened": opened, "finished": finished,
                      "finish_rate": round(100 * finished / opened) if opened else None},
        })

    @action(detail=True, methods=["get", "post"])
    def assign(self, request, pk=None):
        """Assign to clients drawer: Everyone toggle, or a client list."""
        item = self.get_object()
        visible = visible_clients(request.user).filter(status__in=["active", "paused"])
        if request.method == "GET":
            has = set(ContentShare.objects.filter(item=item).values_list("client_id", flat=True))
            return Response({"everyone": item.share_everyone,
                             "clients": [{"id": str(u.id), "full_name": u.full_name, "initials": u.initials,
                                          "avatar_color": u.avatar_color, "has_it": u.id in has} for u in visible]})
        everyone = bool(request.data.get("everyone"))
        ids = {str(i) for i in (request.data.get("clients") or [])}
        with transaction.atomic():
            was_everyone = item.share_everyone
            if everyone != was_everyone and not request.user.is_admin:
                raise PermissionDenied("Only Vimal shares content with everyone.")
            item.share_everyone = everyone
            item.save(update_fields=["share_everyone", "updated_at"])
            vis_ids = {str(i) for i in visible.values_list("id", flat=True)}
            current = {str(c) for c in ContentShare.objects.filter(item=item, client_id__in=vis_ids)
                       .values_list("client_id", flat=True)}
            add = [i for i in ids - current if i in vis_ids]
            rem = [i for i in current - ids if i in vis_ids]
            ContentShare.objects.bulk_create([ContentShare(item=item, client_id=i, shared_by=request.user)
                                              for i in add], ignore_conflicts=True)
            ContentShare.objects.filter(item=item, client_id__in=rem).delete()
        if everyone and not was_everyone:
            self._announce(item, None)
        elif add:
            self._announce(item, list(User.objects.filter(id__in=add)))
        return Response({"everyone": item.share_everyone, "added": len(add), "removed": len(rem)})


class CategoryViewSet(viewsets.ModelViewSet):
    serializer_class = CategorySerializer
    permission_classes = [IsStaff]
    pagination_class = None
    http_method_names = ["get", "post", "patch", "delete"]

    def get_queryset(self):
        return Category.objects.annotate(n=Count("items", filter=Q(items__deleted_at__isnull=True)))


class ClientContentView(mixins.ListModelMixin, viewsets.GenericViewSet):
    """Client profile → Content tab: share / unshare."""

    permission_classes = [IsStaff]
    serializer_class = ContentSerializer

    def _client(self):
        try:
            return get_visible_client(self.request.user, self.kwargs["client_pk"])
        except Exception:
            from django.http import Http404

            raise Http404

    def get_queryset(self):
        return ContentItem.objects.filter(shares__client=self._client()).select_related("category")

    def create(self, request, client_pk=None):
        client = self._client()
        item = get_object_or_404(ContentItem, id=request.data.get("item"))
        share, made = ContentShare.objects.get_or_create(
            item=item, client=client, defaults={"shared_by": request.user, "note": (request.data.get("note") or "")[:500]})
        if not made and "note" in request.data:  # sharing again changes the note
            share.note = (request.data.get("note") or "")[:500]
            share.save(update_fields=["note"])
        notify(client, "content_shared", f"New in your library: {item.title}", "", actor=request.user,
               data={"route": f"/library/{item.id}"})
        return Response(ContentSerializer(item, context={"request": request}).data, status=201)

    @action(detail=True, methods=["post"])
    def unshare(self, request, client_pk=None, pk=None):
        ContentShare.objects.filter(item_id=pk, client=self._client()).delete()
        return Response(status=204)


class MyLibraryViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """Client Library: shared with me, with everyone, or with my program / meal plan.
    `?kind=all|video|pdf|image|article|saved&q=` — rows, counts per filter, done / new totals, coach notes."""

    permission_classes = [IsClient]
    serializer_class = ContentSerializer

    def get_queryset(self):
        from .library import visible

        return visible(self.request.user)

    def list(self, request, *args, **kwargs):
        from .library import FILTERS, library

        kind = request.query_params.get("kind") or "all"
        if kind not in FILTERS:
            raise serializers.ValidationError({"kind": [f"Use one of: {', '.join(FILTERS)}."]})
        data = library(request.user, kind=kind, q=request.query_params.get("q", "")[:80], request=request)
        # One client's library is small (what the coach shared); the page size keeps a long one in check.
        limit = 60
        try:
            offset = max(0, int(request.query_params.get("offset", 0)))
        except ValueError:
            offset = 0
        rows = data.pop("results")
        data.update({"count": len(rows), "results": rows[offset:offset + limit],
                     "next_offset": offset + limit if offset + limit < len(rows) else None})
        return Response(data)

    def retrieve(self, request, pk=None):
        from .library import item_page

        item = get_object_or_404(self.get_queryset(), pk=pk)
        page = item_page(request.user, item, request)
        ContentView.objects.get_or_create(item=item, user=request.user)  # opened: no longer New
        return Response(page)

    @action(detail=True, methods=["post"])
    def progress(self, request, pk=None):
        """{"progress": 0-100} · {"saved": bool} · {"finished": bool} (Mark as done / Done · undo)."""
        item = get_object_or_404(self.get_queryset(), pk=pk)
        v, _ = ContentView.objects.get_or_create(item=item, user=request.user)
        if "progress" in request.data:
            try:
                v.progress = max(v.progress, min(100, int(request.data["progress"])))
            except (TypeError, ValueError):
                pass
        if "saved" in request.data:
            v.saved = bool(request.data["saved"])
        if "finished" in request.data:
            v.finished = bool(request.data["finished"])
        elif v.progress >= 95:
            v.finished = True
        v.save()
        return Response({"progress": v.progress, "finished": v.finished, "saved": v.saved})
