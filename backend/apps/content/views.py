import re
import uuid

from django.contrib.auth import get_user_model
from django.core.files import File
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.db import transaction
from django.db.models import Count, Exists, OuterRef, Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
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

# A share the client really has: not removed for her, not an "Everyone" settings row.
LIVE = Q(hidden=False) & ~Q(source=ContentShare.Source.EVERYONE)
LIVE_SHARE = Q(shares__hidden=False) & ~Q(shares__source=ContentShare.Source.EVERYONE)

LIMITS_MB = {"pdf": 25, "image": 10, "video": 500}
EXT = {"pdf": {"pdf"}, "image": set(IMAGE_EXTENSIONS), "video": {"mp4", "mov", "m4v", "webm"}}
STAGE_DIR = "content/staging"
STAGE_RE = re.compile(r"^[0-9a-f-]{36}\.(mp4|mov|m4v|webm)$")


def storage_limit():
    from django.conf import settings

    return getattr(settings, "CONTENT_STORAGE_GB", 20) * 1024 ** 3


def storage_used(exclude=None):
    from django.db.models import Sum

    qs = ContentItem.objects.all()
    if exclude is not None:
        qs = qs.exclude(id=exclude.id)
    return qs.aggregate(s=Sum("file_size"))["s"] or 0


def check_room(size, exclude=None):
    """Uploads stop once the gym's content storage is full (Gautam, 22 Oct)."""
    if storage_used(exclude) + size > storage_limit():
        gb = storage_limit() // 1024 ** 3
        raise serializers.ValidationError({"file": [f"Content storage is full ({gb} GB). Delete old videos or files first."]})


def uses_of(item):
    """Where an item is used: exercises that show it and programs whose exercise has it as its own video."""
    from apps.training.models import Exercise, ProgramExercise

    used = [{"type": "exercise", "id": str(e.id), "name": e.name} for e in Exercise.objects.filter(video=item)]
    seen = set()
    for pe in ProgramExercise.objects.filter(override__video=str(item.id)).select_related("day__week__program"):
        p = pe.day.week.program
        if p.id not in seen:
            seen.add(p.id)
            used.append({"type": "program", "id": str(p.id), "name": p.name})
    return used


def _fill_media(item):
    """After an upload: a video's length and size (1080p), a PDF's page count."""
    if not item.file:
        return
    if item.kind == "video":
        from apps.training.frames import probe

        secs, res = probe(item)
        ContentItem.objects.filter(id=item.id).update(duration_seconds=secs, resolution=res)
        item.duration_seconds, item.resolution = secs, res
    elif item.kind == "pdf":
        from .pdf_pages import count_pages

        n = count_pages(item)
        ContentItem.objects.filter(id=item.id).update(pages=n)
        item.pages = n


def staged_frames(name, sid, request=None):
    """Four stills of a staged video, keyed like a saved one's (exercises/frames/<id>-<sec>.jpg)."""
    from apps.training.frames import FRAME_DIR, _grab, clock, ffmpeg_exe, frame_times, key_url, probe_source

    exe = ffmpeg_exe()
    try:
        source = default_storage.path(name)
    except NotImplementedError:
        source = default_storage.url(name)
    secs = probe_source(exe, source)[0] if exe else None
    out = []
    for at in frame_times(secs):
        key = f"{FRAME_DIR}/{sid}-{at}.jpg"
        data = _grab(exe, source, at) if exe else None
        if data:
            default_storage.save(key, ContentFile(data))
        out.append({"key": key, "at": at, "label": clock(at), "url": key_url(key, request) if data else None})
    return out


def _take_staged(item, up):
    """Move a staged video onto the item (same file, its real place under content/)."""
    path = f"{STAGE_DIR}/{up}"
    with default_storage.open(path, "rb") as fh:
        item.file.save(up, File(fh), save=False)
    default_storage.delete(path)
    # The frames were keyed by the staged id: give them the item's id, like a saved video's frames.
    from apps.training.frames import FRAME_DIR, frame_times, probe

    sid = up.split(".")[0]
    for at in frame_times(probe(item)[0]):  # same length → same times as the staged frames
        old = f"{FRAME_DIR}/{sid}-{at}.jpg"
        if not default_storage.exists(old):
            continue
        new = f"{FRAME_DIR}/{item.id}-{at}.jpg"
        if not default_storage.exists(new):
            with default_storage.open(old, "rb") as fh:
                default_storage.save(new, fh)
        default_storage.delete(old)
        if item.frame == old:
            item.frame = new
    ContentItem.objects.filter(id=item.id).update(file=item.file.name, frame=item.frame)


def _sweep_staged():
    """Staged videos nobody saved within a day."""
    from datetime import timedelta

    try:
        _, names = default_storage.listdir(STAGE_DIR)
    except (FileNotFoundError, NotImplementedError, OSError):
        return
    cutoff = timezone.now() - timedelta(days=1)
    for n in names:
        try:
            if default_storage.get_modified_time(f"{STAGE_DIR}/{n}") < cutoff:
                default_storage.delete(f"{STAGE_DIR}/{n}")
        except (NotImplementedError, OSError):
            pass


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
    thumb_url = serializers.SerializerMethodField()
    usage = serializers.SerializerMethodField()
    length_label = serializers.SerializerMethodField()
    uses = serializers.SerializerMethodField()
    who = serializers.SerializerMethodField()
    file_name = serializers.SerializerMethodField()
    # A video sent ahead with `content/stage/` (so its frames can be picked before saving): its staged name.
    upload = serializers.CharField(write_only=True, required=False, allow_blank=True)

    class Meta:
        model = ContentItem
        fields = ["id", "kind", "title", "category", "category_name", "description", "file", "file_url",
                  "youtube_url", "link_url", "cover", "cover_url", "thumb_url", "body", "read_minutes", "duration_seconds", "pages",
                  "file_size", "resolution", "share_everyone", "chapters", "outline", "shared_count", "added_by", "usage", "created_at",
                  "updated_at", "frame", "length_label", "uses", "who", "file_name", "upload"]
        read_only_fields = ["file_size"]
        extra_kwargs = {"file": {"write_only": True, "required": False},
                        "cover": {"write_only": True, "required": False},
                        "read_minutes": {"min_value": 1, "max_value": 120}}

    def _url(self, f):
        req = self.context.get("request")
        if not f:
            return None
        return req.build_absolute_uri(f.url) if req else f.url

    def get_file_url(self, obj):
        return self._url(obj.file)

    def get_cover_url(self, obj):
        return self._url(obj.cover)

    def get_thumb_url(self, obj):
        """Picture for a list tile: the cover, else a video's first frame, else the YouTube still, else none."""
        from apps.training.frames import first_frame
        from apps.training.serializers import youtube_thumb

        from apps.training.frames import key_url

        if obj.cover:
            return self._url(obj.cover)
        if obj.frame:
            return key_url(obj.frame, self.context.get("request"))
        if obj.kind == "video" and obj.file:
            return first_frame(obj, self.context.get("request"))
        return youtube_thumb(obj.youtube_url) if obj.youtube_url else None

    def get_usage(self, obj):
        n = getattr(obj, "n_exercises", None)
        return {"exercises": n if n is not None else obj.exercises.count()}

    def get_length_label(self, obj):
        from .library import length_label

        return length_label(obj)

    def get_uses(self, obj):
        return uses_of(obj)

    def get_who(self, obj):
        """The card's footer: Everyone / the one client / N clients / Not assigned."""
        if obj.share_everyone:
            return "Everyone"
        n = getattr(obj, "n_shares", None)
        n = n if n is not None else ContentShare.objects.filter(item=obj).filter(LIVE).count()
        if n == 1:
            s = ContentShare.objects.filter(item=obj).filter(LIVE).select_related("client").first()
            return s.client.full_name if s else "1 client"
        return f"{n} clients" if n else "Not assigned"

    def get_file_name(self, obj):
        from .library import _file_name

        return _file_name(obj)

    def validate_title(self, v):
        v = " ".join(v.split())
        if len(v) < 2:
            raise serializers.ValidationError("Enter a name.")
        return v

    def validate_frame(self, v):
        from apps.training.frames import KEY_RE

        if v and not KEY_RE.match(v):
            raise serializers.ValidationError("Pick one of the frames.")
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
            check_room(f.size, self.instance)
            attrs["file_size"] = f.size
        up = attrs.pop("upload", "")
        if up and not f:
            if kind != "video" or not STAGE_RE.match(up) or not default_storage.exists(f"{STAGE_DIR}/{up}"):
                raise serializers.ValidationError({"file": ["The upload has expired. Upload the video again."]})
            size = default_storage.size(f"{STAGE_DIR}/{up}")
            check_room(size, self.instance)
            attrs["_staged"], attrs["file_size"] = up, size
            f = True
        has_file = f or (self.instance and self.instance.file)
        if kind == "video" and not (has_file or attrs.get("youtube_url") or (self.instance and
                                                                               self.instance.youtube_url)):
            raise serializers.ValidationError({"file": ["Upload a video or paste a YouTube link."]})
        if kind in ("pdf", "image") and not has_file:
            raise serializers.ValidationError({"file": ["Upload the file."]})
        if kind == "link" and not (attrs.get("link_url") or (self.instance and self.instance.link_url)):
            raise serializers.ValidationError({"link_url": ["Paste the link, e.g. https://…"]})
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
            n_shares=Count("shares", distinct=True, filter=LIVE_SHARE), n_exercises=Count("exercises", distinct=True))
        p = self.request.query_params
        if p.get("kind"):
            qs = qs.filter(kind=p["kind"])
        if p.get("category"):
            qs = qs.filter(category_id=p["category"])
        return qs

    @action(detail=False, methods=["post"])
    def stage(self, request):
        """New video, before Save: keep the file and give back its frames, so the cover can be picked right away.
        Save then sends `upload` (the staged name) instead of the file. Staged files not saved within a day go."""
        f = request.FILES.get("file")
        ext = (f.name.rsplit(".", 1)[-1].lower() if f else "")
        if not f or ext not in EXT["video"]:
            raise serializers.ValidationError({"file": ["Upload an MP4 or MOV video."]})
        if f.size > LIMITS_MB["video"] * 1024 * 1024:
            raise serializers.ValidationError({"file": [f"Up to {LIMITS_MB['video']} MB."]})
        check_room(f.size)
        _sweep_staged()
        sid = str(uuid.uuid4())
        name = default_storage.save(f"{STAGE_DIR}/{sid}.{ext}", f)
        return Response({"upload": name.rsplit("/", 1)[-1], "frames": staged_frames(name, sid, request)}, status=201)

    @action(detail=False)
    def summary(self, request):
        """Content library page: item count, storage used of the gym's allowance, and what this person may do
        (`manage` = add / edit / delete / assign, `everyone` = share with every client, Vimal only)."""
        u = request.user
        return Response({"total": ContentItem.objects.count(),
                         "storage": {"used": storage_used(), "limit": storage_limit()},
                         "can": {"manage": u.is_admin or (u.is_trainer and u.trainer_profile.has_perm("content.manage")),
                                 "everyone": u.is_admin}})

    def perform_update(self, serializer):
        staged = serializer.validated_data.pop("_staged", None)
        item = serializer.save()
        if staged:
            _take_staged(item, staged)
        if "file" in serializer.validated_data or staged:
            _fill_media(item)

    def perform_create(self, serializer):
        staged = serializer.validated_data.pop("_staged", None)
        item = serializer.save(created_by=self.request.user)
        if staged:
            _take_staged(item, staged)
        _fill_media(item)
        activity_log("added content", "content", actor=self.request.user, target=item, target_label=item.title)
        if item.share_everyone:
            self._announce(item, None)

    def _announce(self, item, clients):
        if clients is None:
            clients = list(User.objects.filter(role="client", status="active"))
        if clients:
            notify(clients, "content_shared", f"New in your library: {item.title}", item.description[:140],
                   actor=self.request.user, data={"route": f"/library/{item.id}"})

    @action(detail=True, url_path="detail")
    def full(self, request, pk=None):
        """Detail drawer: shared with, used in, stats. (Not named `detail`: DRF sets `self.detail` on the view.)"""
        item = self.get_object()
        shares = ContentShare.objects.filter(item=item).filter(LIVE).select_related("client")[:50]
        views = ContentView.objects.filter(item=item)
        opened = views.count()
        finished = views.filter(finished=True).count()
        used = uses_of(item)
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
            has = set(ContentShare.objects.filter(item=item).filter(LIVE).values_list("client_id", flat=True))
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
            current = {str(c) for c in ContentShare.objects.filter(item=item, client_id__in=vis_ids).filter(LIVE)
                       .values_list("client_id", flat=True)}
            add = [i for i in ids - current if i in vis_ids]
            rem = [i for i in current - ids if i in vis_ids]
            # a row kept from "Remove for <client>" or an Everyone setting becomes a fresh share
            ContentShare.objects.filter(item=item, client_id__in=add).update(
                hidden=False, source=ContentShare.Source.COACH, shared_by=request.user, expires_on=None)
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
        return Category.objects.annotate(n=Count("items", filter=Q(items__deleted_at__isnull=True))).order_by("order", "name")


class ClientContentView(viewsets.GenericViewSet):
    """Client profile → Content tab: what she sees and why (`?why=all|assigned|plan|everyone&q=&page=`), Assign
    content (`POST {items, until, date, note, tell}`), and per row Remove / Hide for her (`unshare`, Undo =
    `restore`), Remind her to open it (`remind`) and Change how long (`until`). The drawer's library list is
    `library/?kind=all|video|guide&q=&offset=`."""

    permission_classes = [IsStaff]
    serializer_class = ContentSerializer
    lookup_value_regex = "[0-9a-f-]+"

    def _client(self):
        try:
            return get_visible_client(self.request.user, self.kwargs["client_pk"])
        except Exception:
            from django.http import Http404

            raise Http404

    def get_queryset(self):
        from .library import visible

        return visible(self._client())

    def list(self, request, client_pk=None):
        from .client_tab import WHY, plan_end, rows

        client = self._client()
        p = request.query_params
        why = p.get("why") or "all"
        if why not in ("all", *WHY):
            raise serializers.ValidationError({"why": ["Use all, assigned, plan or everyone."]})
        every = rows(client, request)
        q = (p.get("q") or "").strip().lower()[:80]
        shown = [r for r in every if (why == "all" or r["why"] == why) and (not q or q in r["title"].lower())]
        try:
            size = max(1, min(100, int(p.get("page_size", 25))))
            page = max(1, int(p.get("page", 1)))
        except ValueError:
            size, page = 25, 1
        return Response({
            "count": len(shown), "page": page, "page_size": size,
            "counts": {"all": len(every), **{w: sum(r["why"] == w for r in every) for w in WHY}},
            "plan": plan_end(client),
            "results": shown[(page - 1) * size:page * size],
        })

    @action(detail=False)
    def library(self, request, client_pk=None):
        from .client_tab import PICK_KINDS, library_page

        kind = request.query_params.get("kind") or "all"
        if kind not in PICK_KINDS:
            raise serializers.ValidationError({"kind": ["Use all, video or guide."]})
        try:
            offset = max(0, int(request.query_params.get("offset", 0)))
        except ValueError:
            offset = 0
        return Response(library_page(self._client(), kind=kind, q=request.query_params.get("q", ""),
                                     offset=offset, request=request))

    def create(self, request, client_pk=None):
        """Assign content: one item (`item`) or several (`items`). What she has already is left as it is,
        except that sharing again changes the note and how long."""
        from .client_tab import expires_from

        client = self._client()
        ids = request.data.get("items") or ([request.data["item"]] if request.data.get("item") else [])
        items = list(ContentItem.objects.filter(id__in=[str(i) for i in ids][:50]))
        if not items:
            raise serializers.ValidationError({"items": ["Pick at least one item."]})
        ends = expires_from(request.data, client) if "until" in request.data else None
        note = (request.data.get("note") or "")[:500]
        added = []
        with transaction.atomic():
            for item in items:
                share = ContentShare.objects.filter(item=item, client=client).first()
                if share is None:
                    share = ContentShare.objects.create(item=item, client=client, shared_by=request.user, note=note,
                                                        expires_on=ends)
                    added.append(item)
                    continue
                if share.hidden or share.source == ContentShare.Source.EVERYONE:
                    share.hidden, share.source, share.shared_by = False, ContentShare.Source.COACH, request.user
                    added.append(item)
                if "note" in request.data:
                    share.note = note
                if "until" in request.data:
                    share.expires_on = ends
                share.save()
        if added and request.data.get("tell", True) not in (False, "false", "0"):
            title = (f"New in your library: {added[0].title}" if len(added) == 1
                     else f"{len(added)} new items in your library")
            notify(client, "content_shared", title, note[:140], actor=request.user,
                   data={"route": f"/library/{added[0].id}" if len(added) == 1 else "/library"})
        if added:
            activity_log(f"shared {len(added)} item{'s' if len(added) != 1 else ''}", "content",
                         actor=request.user, client=client, target_label=added[0].title)
        return Response({"added": len(added), "items": [str(i.id) for i in added]}, status=201)

    def _share(self, pk, client):
        item = get_object_or_404(ContentItem, id=pk)
        share = ContentShare.objects.filter(item=item, client=client).first()
        return item, share

    @action(detail=True, methods=["post"])
    def unshare(self, request, client_pk=None, pk=None):
        """Remove for her (assigned) / Hide for her (from a plan or everyone). The row is kept for Undo."""
        client = self._client()
        item, share = self._share(pk, client)
        if share is None:
            if not item.share_everyone:
                return Response(status=204)
            share = ContentShare(item=item, client=client, source=ContentShare.Source.EVERYONE)
        share.hidden = True
        share.save()
        return Response(status=204)

    @action(detail=True, methods=["post"])
    def restore(self, request, client_pk=None, pk=None):
        """Undo of Remove / Hide."""
        client = self._client()
        item, share = self._share(pk, client)
        if share is None or not share.hidden:
            return Response({"error": {"code": "not_found", "message": "Nothing to restore."}}, status=404)
        if share.source == ContentShare.Source.EVERYONE and not share.expires_on and not share.reminded_at:
            share.delete()
        else:
            share.hidden = False
            share.save(update_fields=["hidden"])
        return Response(status=204)

    @action(detail=True, methods=["post"])
    def remind(self, request, client_pk=None, pk=None):
        """Remind her to open it: a push with the title."""
        client = self._client()
        item, share = self._share(pk, client)
        if not self.get_queryset().filter(id=item.id).exists():
            raise serializers.ValidationError(f"{client.full_name} does not have this item now.")
        if share is None:
            share = ContentShare(item=item, client=client, source=ContentShare.Source.EVERYONE)
        share.reminded_at = timezone.now()
        share.save()
        coach = request.user.first_name or "Your coach"
        notify(client, "content_reminder", f"{coach} asked you to open: {item.title}", item.description[:140],
               actor=request.user, data={"route": f"/library/{item.id}"})
        return Response({"reminded_at": share.reminded_at})

    @action(detail=True, methods=["post"])
    def until(self, request, client_pk=None, pk=None):
        """Change how long she keeps it: {"until": "always" | "plan" | "date", "date"}."""
        from .client_tab import expires_from, until_label

        client = self._client()
        item, share = self._share(pk, client)
        if not self.get_queryset().filter(id=item.id).exists():
            raise serializers.ValidationError(f"{client.full_name} does not have this item now.")
        if share is None:
            share = ContentShare(item=item, client=client, source=ContentShare.Source.EVERYONE)
        share.expires_on = expires_from(request.data, client)
        share.save()
        return Response({"until": share.expires_on, "until_label": until_label(share)})


class MyLibraryViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """Client Library: shared with me, with everyone, or with my program / meal plan.
    `?kind=all|video|pdf|image|article|link|saved&q=` — rows, counts per filter, done / new totals, coach notes."""

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
        _, first = ContentView.objects.get_or_create(item=item, user=request.user)  # opened: no longer New
        if first:
            verb = {"video": "watched a video", "pdf": "opened a PDF", "image": "opened an image"}.get(
                item.kind, "read an article")
            activity_log(verb, "content", actor=request.user, client=request.user, target=item,
                         target_label=item.title)
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
