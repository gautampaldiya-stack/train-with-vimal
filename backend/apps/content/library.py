"""Client Library (boards ClientLibrary / ClientLibraryWeb): what the coach shared with this client, shared with
everyone, or that came with the program or meal plan. Each row knows its coach note, where it came from, and the
client's New / Done / Saved state."""

from django.db.models import Q
from django.utils import timezone
from django.utils.text import slugify

from apps.common.utils import dfmt

from .models import ContentItem, ContentShare, ContentView
from .pdf_pages import page_images

KIND_LABEL = {"video": "Video", "pdf": "PDF", "image": "Image", "article": "Article", "link": "Link"}
FILTERS = ("all", "video", "pdf", "image", "article", "link", "saved")


def _clock(sec):
    sec = int(sec or 0)
    return f"{sec // 60}:{sec % 60:02d}"


def length_label(item):
    """3:05 · 6 pages · PNG · 4 min read."""
    if item.kind == "video":
        return _clock(item.duration_seconds) if item.duration_seconds else "Video"
    if item.kind == "pdf":
        n = item.pages or len(item.outline or [])
        return f"{n} page{'s' if n != 1 else ''}" if n else "PDF"
    if item.kind == "image":
        name = item.file.name if item.file else ""
        return name.rsplit(".", 1)[-1].upper() if "." in name else "Image"
    if item.kind == "link":
        return link_site(item.link_url)
    if item.read_minutes:
        return f"{item.read_minutes} min read"
    words = len((item.body or "").split())
    return f"{max(1, round(words / 200))} min read"


def link_site(url):
    """https://www.healthline.com/nutrition/... → healthline.com."""
    from urllib.parse import urlparse

    host = urlparse(url or "").netloc.lower()
    return host[4:] if host.startswith("www.") else (host or "Link")


def youtube_id(url):
    import re

    m = re.search(r"(?:youtu\.be/|v=|/shorts/|/embed/)([A-Za-z0-9_-]{11})", url or "")
    return m.group(1) if m else ""


def _first(user):
    return (user.first_name or user.full_name.split(" ")[0]) if user else ""


def _initials(user):
    parts = (user.full_name if user else "").split()
    return "".join(w[0] for w in parts[:2]).upper()


def source_line(item, share):
    """Assigned by Aman · 28 Sep · From Fat Loss Phase 1 · From your meal plan · For all clients · 12 Jan."""
    if share is None or share.source == ContentShare.Source.EVERYONE:
        return f"For all clients · {dfmt(timezone.localtime(item.created_at), '%-d %b')}"
    if share.source == ContentShare.Source.PROGRAM:
        return f"From {share.source_label}" if share.source_label else "From your program"
    if share.source == ContentShare.Source.MEAL_PLAN:
        return f"From {share.source_label}" if share.source_label else "From your meal plan"
    who = _first(share.shared_by) or "your coach"
    return f"Assigned by {who} · {dfmt(timezone.localtime(share.created_at), '%-d %b')}"


def visible(client):
    """Shared with everyone or with her, minus what the coach removed / hid for her and what ran out
    ("How long she keeps it")."""
    gone = ContentShare.objects.filter(client=client).filter(
        Q(hidden=True) | Q(expires_on__lt=timezone.localdate())).values("item_id")
    return (ContentItem.objects.filter(Q(share_everyone=True) | Q(shares__client=client, shares__hidden=False))
            .exclude(id__in=gone).distinct())


def _row(item, share, view):
    return {
        "id": str(item.id), "kind": item.kind, "title": item.title, "description": item.description,
        "length": length_label(item), "by": item.created_by.full_name if item.created_by else "Train With Vimal",
        "source": source_line(item, share), "note": share.note if share else "",
        "note_by": _first(share.shared_by) if share and share.note else "",
        "note_initials": _initials(share.shared_by) if share and share.note else "",
        "new": view is None, "done": bool(view and view.finished), "saved": bool(view and view.saved),
        "progress": view.progress if view else 0,
        "shared_at": share.created_at if share else item.created_at,
    }


def library(client, *, kind="all", q="", request=None):
    """All rows for this client (unread first, then newest), the filter counts and the coach's notes."""
    items = list(visible(client).select_related("created_by"))
    shares = {s.item_id: s for s in ContentShare.objects.filter(client=client).select_related("shared_by")}
    views = {v.item_id: v for v in ContentView.objects.filter(user=client)}
    rows = [_row(i, shares.get(i.id), views.get(i.id)) for i in items]
    rows.sort(key=lambda r: r["shared_at"], reverse=True)
    rows.sort(key=lambda r: not r["new"])  # stable: new ones first

    def in_kind(r, k):
        return k == "all" or (r["saved"] if k == "saved" else r["kind"] == k)

    text = {str(i.id): f"{i.title} {i.description} {i.body} {i.link_url}".lower() for i in items}
    q = (q or "").strip().lower()
    shown = [r for r in rows if in_kind(r, kind) and (not q or q in text[r["id"]] + " " + r["note"].lower())]
    coach = client.client_profile.trainer if hasattr(client, "client_profile") else None
    return {
        "coach_first": _first(coach) or "your coach", "coach_initials": _initials(coach) or "TV",
        "total": len(rows), "done": sum(r["done"] for r in rows), "new": sum(r["new"] for r in rows),
        "counts": {k: sum(in_kind(r, k) for r in rows) for k in FILTERS},
        "notes": [{"id": r["id"], "title": r["title"], "note": r["note"]} for r in rows if r["note"]],
        "results": shown,
    }


def _file_name(item):
    """eating-out-on-a-fat-loss-plan.pdf: the title, not the stored uuid name."""
    if not item.file:
        return ""
    ext = item.file.name.rsplit(".", 1)[-1].lower() if "." in item.file.name else ""
    return f"{slugify(item.title) or 'file'}.{ext}" if ext else slugify(item.title)


def item_page(client, item, request=None):
    """One item for its sheet: the row plus body, chapters, page outline and the file."""
    share = ContentShare.objects.filter(client=client, item=item).select_related("shared_by").first()
    view = ContentView.objects.filter(user=client, item=item).first()
    url = request.build_absolute_uri(item.file.url) if (item.file and request) else (item.file.url if item.file else "")
    return {**_row(item, share, view), "body": [p.strip() for p in (item.body or "").split("\n\n") if p.strip()],
            "chapters": item.chapters or [], "outline": item.outline or [], "file_url": url,
            "file_name": _file_name(item),
            "youtube_url": item.youtube_url, "duration": item.duration_seconds or 0,
            "youtube_thumb": (f"https://img.youtube.com/vi/{youtube_id(item.youtube_url)}/hqdefault.jpg"
                              if youtube_id(item.youtube_url) else ""),
            "link_url": item.link_url, "link_site": link_site(item.link_url) if item.link_url else "",
            "kind_label": KIND_LABEL.get(item.kind, item.kind), "page_images": page_images(item, request)}


def media_of(item, request=None):
    """An exercise's video or picture for the guide: kind (video / image / youtube), URL, title, length."""
    if item is None or item.kind not in ("video", "image"):
        return None
    if not item.file:  # a library video that is only a YouTube link
        return ({"id": str(item.id), "kind": "youtube", "url": item.youtube_url, "title": item.title, "cover": "",
                 "duration": item.duration_seconds or 0} if item.youtube_url else None)
    url = request.build_absolute_uri(item.file.url) if request else item.file.url
    cover = (request.build_absolute_uri(item.cover.url) if request else item.cover.url) if item.cover else ""
    if not cover and item.kind == "video":
        from apps.training.frames import first_frame

        cover = first_frame(item, request) or ""
    return {"id": str(item.id), "kind": item.kind, "url": url, "title": item.title, "cover": cover,
            "duration": item.duration_seconds or 0}
