"""Trainer → My profile (boards TrainerMe / TrainerMeMobile): the extra pieces the page needs on top of
`trainers/me/` — My activity (with logins), Where you are logged in, Notifications."""
import re
from datetime import timedelta

from django.db.models import Q
from django.utils import timezone
from rest_framework import serializers
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.permissions import IsStaff
from apps.common.utils import dfmt

from .models import AccessRequest
from .permissions_catalog import GROUPS

RANGES = {"today": 0, "7d": 7, "30d": 30, "3m": 92}
# Board chips → activity kinds. "login" rows come from the user's sessions (each login is one).
KINDS = ("checkin", "plan", "client", "login")
LABELS = {k: label for _, items in GROUPS for k, label, _ in items}


# ---------------------------------------------------------------- devices
def device_label(s):
    """'Android app · Pixel 7', 'Chrome on Windows', 'Safari on iPad'."""
    ua = s.user_agent or ""
    if s.platform in ("android", "ios"):
        app = "Android app" if s.platform == "android" else "iPhone app"
        name = s.device_name if s.device_name and s.device_name.lower() not in ("android", "ios") else ""
        return f"{app} · {name}" if name else app
    browser = ("Edge" if "Edg/" in ua else "Firefox" if "Firefox/" in ua else "Chrome" if "Chrome/" in ua
               else "Safari" if "Safari/" in ua else "")
    os_ = ("iPad" if "iPad" in ua else "iPhone" if "iPhone" in ua else "Android" if "Android" in ua
           else "Windows" if "Windows" in ua else "Mac" if "Mac OS" in ua else "Linux" if "Linux" in ua else "")
    if browser and os_:
        return f"{browser} on {os_}"
    return browser or s.device_name or "Web browser"


def is_phone(s):
    return s.platform in ("android", "ios") or bool(re.search(r"iPhone|Android.*Mobile", s.user_agent or ""))


def when_text(dt, now=None):
    """'active now', 'today, 9:40 am', 'yesterday, 6:10 pm', 'Sat 3 Oct', '3 Oct 2025'."""
    now = now or timezone.now()
    local, today = timezone.localtime(dt), timezone.localdate(now)
    t = dfmt(local, "%-I:%M %p").lower()
    days = (today - local.date()).days
    if days == 0:
        return f"today, {t}"
    if days == 1:
        return f"yesterday, {t}"
    if days < 7:
        return dfmt(local, "%a %-d %b")
    return dfmt(local, "%-d %b") if local.year == today.year else dfmt(local, "%-d %b %Y")


def last_login(user):
    s = user.sessions.order_by("-created_at").first()
    if s is None:
        return None
    return {"at": s.created_at, "text": when_text(s.created_at), "device": device_label(s)}


class MyDevicesView(APIView):
    """Account → Where you are logged in: this device first, then the rest by last use; 5 a page."""

    permission_classes = [IsStaff]
    PAGE = 5

    def get(self, request):
        sid = str((request.auth or {}).get("sid", ""))
        qs = request.user.sessions.filter(revoked_at__isnull=True).order_by("-last_active_at")
        try:
            page = max(1, int(request.query_params.get("page", 1)))
        except ValueError:
            page = 1
        rows = list(qs.exclude(id=sid)[(page - 1) * self.PAGE: page * self.PAGE]) if sid else \
            list(qs[(page - 1) * self.PAGE: page * self.PAGE])
        me = qs.filter(id=sid).first() if sid and page == 1 else None
        now = timezone.now()

        def row(s, this):
            recent = now - s.last_active_at < timedelta(minutes=5)
            where = s.city or ""
            seen = "active now" if this or recent else when_text(s.last_active_at, now)
            return {"id": str(s.id), "label": device_label(s), "sub": f"{where} · {seen}" if where else seen[:1].upper() + seen[1:],
                    "this_device": this, "phone": is_phone(s)}

        total = qs.count()
        others = total - (1 if sid and qs.filter(id=sid).exists() else 0)
        return Response({
            "count": total,
            "others": others,
            "results": ([row(me, True)] if me else []) + [row(s, False) for s in rows],
            "has_more": page * self.PAGE < others,
        })


# ---------------------------------------------------------------- activity
def _range_start(value):
    if value not in RANGES:
        return None
    now = timezone.localtime()
    if value == "today":
        return now.replace(hour=0, minute=0, second=0, microsecond=0)
    return now - timedelta(days=RANGES[value])


class MyActivityView(APIView):
    """My activity: what this trainer did in the app, newest first, plus a "Logged in" row per login.
    ?range=today|7d|30d|3m|all &kind=checkin|plan|client|login &offset=&limit= (8 a page on the board)."""

    permission_classes = [IsStaff]

    def get(self, request):
        from apps.activity.models import ActivityEvent

        user = request.user
        p = request.query_params
        start = _range_start(p.get("range", "7d"))
        kind = p.get("kind", "")
        try:
            offset = max(0, int(p.get("offset", 0)))
            limit = min(50, max(1, int(p.get("limit", 8))))
        except ValueError:
            return Response({"error": {"code": "invalid", "message": "offset and limit are numbers."}}, status=400)
        events = ActivityEvent.objects.filter(actor=user).select_related("client")
        logins = user.sessions.all()
        if start:
            events = events.filter(created_at__gte=start)
            logins = logins.filter(created_at__gte=start)
        counts = {k: events.filter(kind=k).count() for k in KINDS if k != "login"}
        counts["login"] = logins.count()
        counts["all"] = events.count() + counts["login"]
        if kind == "login":
            events = events.none()
        elif kind in KINDS:
            logins = logins.none()
            events = events.filter(kind=kind)
        # Merge the two newest-first streams; only offset+limit rows of each are read.
        want = offset + limit
        merged = [("e", e.created_at, e) for e in events.order_by("-created_at")[:want]]
        merged += [("l", s.created_at, s) for s in logins.order_by("-created_at")[:want]]
        merged.sort(key=lambda r: r[1], reverse=True)
        total = counts[kind] if kind in KINDS else counts["all"]
        rows = []
        for typ, at, obj in merged[offset:want]:
            if typ == "l":
                rows.append({"id": f"login-{obj.id}", "kind": "login", "created_at": at, "verb": "Logged in",
                             "who": "", "note": device_label(obj), "change_from": "", "change_to": "",
                             "source": f"{user.first_name} · {device_label(obj)}"})
                continue
            verb = obj.verb[:1].upper() + obj.verb[1:]
            who = obj.client.full_name if obj.client_id and obj.client else ""
            if who and who.lower() in verb.lower():
                who = ""
            note = (obj.meta or {}).get("note") or ""
            if not note and obj.target_label and obj.target_label != who and obj.target_label.lower() not in verb.lower():
                note = obj.target_label
            rows.append({"id": str(obj.id), "kind": obj.kind, "created_at": at, "verb": verb, "who": who,
                         "note": note, "change_from": obj.change_from, "change_to": obj.change_to,
                         "source": f"{user.first_name} · {(obj.source or 'Web').split('·')[-1].strip()}"})
        # Rows per local day (day headers "Today · 2") under the same range and kind.
        days = {}
        if rows:
            tz = timezone.get_current_timezone()
            lo = timezone.localtime(rows[-1]["created_at"]).replace(hour=0, minute=0, second=0, microsecond=0)
            hi = timezone.localtime(rows[0]["created_at"]).replace(hour=23, minute=59, second=59)
            from django.db.models.functions import TruncDate
            from django.db.models import Count

            for qs in (events, logins):
                for r in (qs.filter(created_at__range=(lo, hi)).annotate(d=TruncDate("created_at", tzinfo=tz))
                          .values("d").annotate(n=Count("id"))):
                    days[str(r["d"])] = days.get(str(r["d"]), 0) + r["n"]
        return Response({"results": rows, "count": total, "counts": counts, "days": days,
                         "has_more": offset + len(rows) < total})


# ---------------------------------------------------------------- notifications
class NotificationsSerializer(serializers.Serializer):
    new_checkin = serializers.BooleanField(required=False)
    missed_workouts = serializers.BooleanField(required=False)
    new_client = serializers.BooleanField(required=False)
    session_reminders = serializers.BooleanField(required=False)
    daily_summary = serializers.BooleanField(required=False)
    gym_news = serializers.BooleanField(required=False)


# Board toggle → StaffNotificationPreference field (the senders read these); the last two live on the profile.
PREF_FIELDS = {"new_checkin": "new_checkin", "missed_workouts": "missed_workouts", "new_client": "new_client",
               "session_reminders": "session_changes"}
from apps.notifications.staff import NOTIFY_DEFAULTS as EXTRA_DEFAULTS  # noqa: E402  (one place for the defaults)


class MyNotificationsView(APIView):
    """Account → Notifications ("Push to your phone and email")."""

    permission_classes = [IsStaff]

    def _data(self, user):
        from apps.notifications.models import StaffNotificationPreference

        pref = StaffNotificationPreference.objects.get_or_create(user=user)[0]
        extra = {**EXTRA_DEFAULTS, **(user.trainer_profile.notify or {})}
        return {**{k: getattr(pref, f) for k, f in PREF_FIELDS.items()}, **{k: bool(extra[k]) for k in EXTRA_DEFAULTS}}

    def get(self, request):
        return Response(self._data(request.user))

    def put(self, request):
        from apps.notifications.models import StaffNotificationPreference

        s = NotificationsSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        pref = StaffNotificationPreference.objects.get_or_create(user=request.user)[0]
        changed = [f for k, f in PREF_FIELDS.items() if k in d]
        for k, f in PREF_FIELDS.items():
            if k in d:
                setattr(pref, f, d[k])
        if changed:
            pref.save(update_fields=changed)
        extra = {k: d[k] for k in EXTRA_DEFAULTS if k in d}
        if extra:
            tp = request.user.trainer_profile
            tp.notify = {**(tp.notify or {}), **extra}
            tp.save(update_fields=["notify", "updated_at"])
        return Response(self._data(request.user))

    patch = put


# ---------------------------------------------------------------- page extras
def me_extras(user):
    """Header line, This week, Clients who need you and the open access request for `trainers/me/`."""
    from apps.activity.trainer_home import _hours, _reply_hours, clients_who_need_you, this_week
    from apps.checkins.models import Submission

    now = timezone.now()
    week = this_week(user, now)
    today = timezone.localdate(now)
    monday = today - timedelta(days=today.weekday())
    start = timezone.datetime.combine(monday, timezone.datetime.min.time(), timezone.get_current_timezone())
    reply = _reply_hours(Submission.objects.filter(reviewed_by=user, reviewed_at__gte=start))
    # Stat card "Avg reply time": same 30 days and same words as the dashboard card.
    mine30 = _reply_hours(Submission.objects.filter(reviewed_by=user, reviewed_at__gte=now - timedelta(days=30)))
    team30 = _reply_hours(Submission.objects.filter(reviewed_at__gte=now - timedelta(days=30)))
    rows = {r["label"]: r["value"] for r in week["rows"]}
    attn = clients_who_need_you(user, now)
    tone = {"log": ("At risk", "bad"), "miss": ("At risk", "bad"), "end": ("Plan ends", "warn"),
            "low": ("Feeling low", "warn")}
    req = AccessRequest.objects.filter(trainer__user=user, status=AccessRequest.Status.OPEN).order_by("-created_at").first()
    return {
        "last_login": last_login(user),
        "reply": {"value": _hours(mine30), "team": f"Team average {_hours(team30)}" if team30 is not None else ""},
        "week": {"range": week["range"], "rows": [
            {"label": "Check-ins reviewed", "value": rows.get("Check-ins reviewed", "0")},
            {"label": "Avg reply time", "value": _hours(reply)},
            {"label": "Plans changed", "value": rows.get("Plans changed", "0")},
            {"label": "Sessions held", "value": rows.get("Sessions held", "0")},
        ]},
        "attention": [{**r, "badge": tone[r["kind"]][0], "tone": tone[r["kind"]][1]} for r in attn[:3]],
        "attention_total": len(attn),
        "asked": {"id": str(req.id), "labels": [LABELS.get(k, k) for k in req.permissions], "at": req.created_at}
        if req else None,
    }

