"""Client profile → Content tab (boards TrainerClientProfile / …Mobile): everything the client sees in the Library
of her app and why — assigned to her, from her plans, or shared with everyone — with who added it, whether she
opened it, how long she keeps it, and the coach's note. Same rules as the client's Library (`library.visible`)."""

from datetime import timedelta

from django.db.models import Q
from django.utils import timezone

from apps.common.utils import dfmt

from .library import KIND_LABEL, length_label, visible, youtube_id
from .models import ContentItem, ContentShare, ContentView

WHY = ("assigned", "plan", "everyone")
# Assign content drawer chips: All · Videos · Guides (everything to read or look at).
PICK_KINDS = {"all": None, "video": ["video"], "guide": ["article", "pdf", "image", "link"]}


def first_name(user):
    return (user.first_name or user.full_name.split(" ")[0]) if user else ""


def why_of(share):
    if share is not None and not share.hidden:
        if share.source in (ContentShare.Source.PROGRAM, ContentShare.Source.MEAL_PLAN):
            return "plan"
        if share.source == ContentShare.Source.COACH:
            return "assigned"
    return "everyone"


def plan_label(share):
    """"Fat loss · 8 weeks" · "meal plan" (the client app says "your meal plan")."""
    label = (share.source_label or "").strip()
    if label.lower().startswith("your "):
        label = label[5:]
    if not label:
        label = "her program" if share.source == ContentShare.Source.PROGRAM else "her meal plan"
    return label


def why_label(why, share, first):
    if why == "assigned":
        return f"Assigned to {first}"
    if why == "plan":
        return f"From {plan_label(share)}"
    return "Everyone"


def until_label(share):
    if share is not None and share.expires_on:
        return f"Until {dfmt(share.expires_on, '%a, %-d %b')}"
    if share is not None and why_of(share) == "plan":
        return f"While on {plan_label(share)}"
    return "Always"


def _url(request, f):
    if not f:
        return ""
    return request.build_absolute_uri(f.url) if request else f.url


def _text(item):
    """"What Riya reads": the description, else the start of the article."""
    if item.description:
        return item.description
    first = next((p.strip() for p in (item.body or "").split("\n\n") if p.strip()), "")
    return first[:400]


def row(item, share, view, first, request=None):
    why = why_of(share)
    real = share is not None and share.source != ContentShare.Source.EVERYONE
    by = share.shared_by if real and share.shared_by else item.created_by
    return {
        "id": str(item.id), "kind": item.kind, "kind_label": KIND_LABEL.get(item.kind, item.kind.title()),
        "title": item.title, "length": length_label(item), "text": _text(item),
        "why": why, "why_label": why_label(why, share, first),
        "added_by": by.full_name if by else "Train With Vimal",
        "added_at": share.created_at if real else item.created_at,
        "until": share.expires_on if share else None, "until_label": until_label(share),
        "note": share.note if real else "",
        "opened_at": view.opened_at if view else None, "progress": view.progress if view else 0,
        "finished": bool(view and view.finished), "reminded_at": share.reminded_at if share else None,
        "duration": item.duration_seconds or 0, "pages": item.pages or 0,
        "cover_url": _url(request, item.cover), "image_url": _url(request, item.file) if item.kind == "image" else "",
        "youtube_thumb": (f"https://img.youtube.com/vi/{youtube_id(item.youtube_url)}/hqdefault.jpg"
                          if youtube_id(item.youtube_url) else ""),
    }


def rows(client, request=None):
    items = list(visible(client).select_related("created_by"))
    shares = {s.item_id: s for s in ContentShare.objects.filter(client=client).select_related("shared_by")}
    views = {v.item_id: v for v in ContentView.objects.filter(user=client)}
    first = first_name(client)
    out = [row(i, shares.get(i.id), views.get(i.id), first, request) for i in items]
    out.sort(key=lambda r: r["added_at"], reverse=True)
    return out


def plan_end(client):
    """"Until Fat Loss Phase 1 ends": the current program and its last day, or None."""
    from apps.clients.metrics import active_program

    pa = active_program(client)
    if pa is None:
        return None
    end = pa.end_date
    if end is None and pa.effective_program.weeks:
        end = pa.start_date + timedelta(days=7 * pa.effective_program.weeks - 1)
    return {"name": pa.effective_program.name, "ends": end} if end else None


def library_page(client, *, kind="all", q="", offset=0, limit=20, request=None):
    """Assign content drawer: the library to pick from, with "Already has it" on what she sees now."""
    qs = ContentItem.objects.all().order_by("-created_at")
    if PICK_KINDS.get(kind):
        qs = qs.filter(kind__in=PICK_KINDS[kind])
    q = (q or "").strip()[:80]
    if q:
        qs = qs.filter(Q(title__icontains=q) | Q(description__icontains=q))
    has = set(visible(client).values_list("id", flat=True))
    total = qs.count()
    page = list(qs[offset:offset + limit])
    return {
        "count": total, "next_offset": offset + limit if offset + limit < total else None,
        "plan": plan_end(client),
        "results": [{"id": str(i.id), "kind": i.kind, "kind_label": KIND_LABEL.get(i.kind, i.kind.title()),
                     "title": i.title, "description": i.description, "length": length_label(i),
                     "has": i.id in has} for i in page],
    }


def expires_from(data, client):
    """{"until": "always" | "plan" | "date", "date": "YYYY-MM-DD"} → the last day (None = always)."""
    from django.utils.dateparse import parse_date
    from rest_framework.exceptions import ValidationError

    until = data.get("until") or "always"
    if until == "always":
        return None
    if until == "plan":
        p = plan_end(client)
        if p is None:
            raise ValidationError({"until": ["She has no current plan. Pick Always or a date."]})
        return p["ends"]
    if until == "date":
        d = parse_date(str(data.get("date") or ""))
        if d is None:
            raise ValidationError({"date": ["Pick the last day."]})
        if d < timezone.localdate():
            raise ValidationError({"date": ["Pick today or a later day."]})
        return d
    raise ValidationError({"until": ["Use always, plan or date."]})
