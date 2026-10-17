import re
from datetime import datetime, time, timedelta

from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import Count, Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.utils.dateparse import parse_date, parse_datetime
from rest_framework import serializers, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import Role
from apps.activity.services import log as activity_log
from apps.clients.services import visible_clients
from apps.common.permissions import IsClient, IsStaff
from apps.notifications.services import notify

from .models import Availability, Session
from apps.common.utils import dfmt

User = get_user_model()


def person(u):
    return {"id": str(u.id), "full_name": u.full_name, "initials": u.initials, "avatar_color": u.avatar_color}


def plan_line(client):
    """Session panel "Plan": "Fat loss · week 6 of 12" (goal and the program week), "No plan yet" without one."""
    from apps.clients.metrics import active_program

    prof = getattr(client, "client_profile", None)
    goal = prof.get_goal_display() if prof and prof.goal else ""
    pa = active_program(client)
    if pa is None:
        return "No plan yet"
    p = pa.effective_program
    week = min((timezone.localdate() - pa.start_date).days // 7 + 1, p.weeks)
    return f"{goal or p.name} · week {week} of {p.weeks}"


_PHONE = re.compile(r"^\+?[0-9 ]{10,15}$")
_LINK = re.compile(r"^(https?://)?[\w-]+(\.[\w-]+)+(/\S*)?$", re.I)


class SessionSerializer(serializers.ModelSerializer):
    client_detail = serializers.SerializerMethodField()
    trainer_detail = serializers.SerializerMethodField()
    booked_by_name = serializers.CharField(source="booked_by.full_name", read_only=True, default=None)
    minutes = serializers.IntegerField(write_only=True, required=False, min_value=5, max_value=240)
    length = serializers.SerializerMethodField()
    client_plan = serializers.SerializerMethodField()
    tell_client = serializers.BooleanField(write_only=True, default=True)

    class Meta:
        model = Session
        fields = ["id", "kind", "client", "client_detail", "trainer", "trainer_detail", "title", "start", "end",
                  "minutes", "length", "is_call", "place", "call_link", "note", "status", "booked_by_name",
                  "client_plan", "tell_client", "created_at"]
        read_only_fields = ["status", "end"]
        extra_kwargs = {"trainer": {"required": False}}

    def get_client_detail(self, obj):
        return person(obj.client)

    def get_trainer_detail(self, obj):
        return person(obj.trainer)

    def get_length(self, obj):
        return int((obj.end - obj.start).total_seconds() // 60)

    def get_client_plan(self, obj):
        # One line per client per answer (a week lists the same client many times).
        cache = self.context.setdefault("_plans", {})
        if obj.client_id not in cache:
            cache[obj.client_id] = plan_line(obj.client)
        return cache[obj.client_id]

    def validate_call_link(self, v):
        v = (v or "").strip()
        if v and not (_PHONE.match(v) and len(re.sub(r"\D", "", v)) >= 10 or _LINK.match(v)):
            raise serializers.ValidationError("Enter a call link (meet.google.com/…) or a 10 digit number.")
        return v

    def validate(self, attrs):
        req = self.context["request"]
        user = req.user
        inst = self.instance
        client = attrs.get("client", inst.client if inst else None)
        if client is None or not visible_clients(user).filter(id=client.id).exists():
            raise serializers.ValidationError({"client": ["Pick one of your clients."]})
        trainer = attrs.get("trainer", inst.trainer if inst else None)
        if user.is_trainer:
            if not user.trainer_profile.has_perm("schedule.book_sessions"):
                raise PermissionDenied("Your access does not include booking sessions.")
            if trainer and trainer != user and not user.trainer_profile.has_perm("clients.view_all"):
                raise serializers.ValidationError({"trainer": ["You can book only your own sessions."]})
            trainer = trainer or user
        if trainer is None:
            trainer = client.client_profile.trainer
        if trainer is None or trainer.role not in (Role.TRAINER, Role.ADMIN):
            raise serializers.ValidationError({"trainer": ["Pick a trainer."]})
        attrs["trainer"] = trainer
        kind = attrs.get("kind", inst.kind if inst else Session.Kind.ONE_ON_ONE)
        start = attrs.get("start", inst.start if inst else None)
        minutes = attrs.pop("minutes", None) or (int((inst.end - inst.start).total_seconds() // 60) if inst and
                                                   "start" not in attrs else Session.DEFAULT_MINUTES[kind])
        if start is None:
            raise serializers.ValidationError({"start": ["Pick a day and time."]})
        if start.minute % 5:
            raise serializers.ValidationError({"start": ["Pick a time on 5 minutes."]})
        attrs["end"] = start + timedelta(minutes=minutes)
        if not inst and start < timezone.now() - timedelta(hours=12):
            raise serializers.ValidationError({"start": ["Pick a time from today on."]})
        clash = session_clash(trainer, start, attrs["end"], exclude=inst.id if inst else None)
        if clash:
            raise serializers.ValidationError({"start": [
                f"{trainer.first_name} already has {clash.client.full_name} at "
                f"{dfmt(timezone.localtime(clash.start), '%-I:%M')} – {dfmt(timezone.localtime(clash.end), '%-I:%M %p')}"]})
        return attrs


def session_clash(trainer, start, end, exclude=None):
    qs = Session.objects.filter(trainer=trainer, start__lt=end, end__gt=start).exclude(status="cancelled")
    if exclude:
        qs = qs.exclude(id=exclude)
    return qs.select_related("client").first()


def working_check(trainer, start, end):
    """'Outside Aman's working hours (6:30 am – 8 pm)' / 'day off'."""
    local_s, local_e = timezone.localtime(start), timezone.localtime(end)
    av = Availability.objects.filter(trainer=trainer, weekday=local_s.weekday()).first()
    # No row yet = the defaults My working hours shows (Mon–Sat 6:30 am – 8 pm, Sunday off).
    working = av.is_working if av else local_s.weekday() < 6
    start, end = (av.start, av.end) if av else (time(6, 30), time(20, 0))
    if not working:
        return "day_off", None
    if local_s.time() < start or local_e.time() > end or local_e.date() != local_s.date():
        return "outside", {"start": start, "end": end}
    return "ok", None


class SessionViewSet(viewsets.ModelViewSet):
    """Calendar (admin: all trainers; trainer: own sessions)."""

    serializer_class = SessionSerializer
    permission_classes = [IsStaff]
    pagination_class = None
    http_method_names = ["get", "post", "patch", "delete"]

    def get_queryset(self):
        u = self.request.user
        qs = Session.objects.select_related("client", "trainer", "booked_by").exclude(status="cancelled")
        if u.is_trainer and not u.trainer_profile.has_perm("clients.view_all"):
            qs = qs.filter(trainer=u)
        p = self.request.query_params
        if self.action in ("list", "stats"):
            start = parse_date(p.get("from") or "") or timezone.localdate() - timedelta(
                days=timezone.localdate().weekday())
            end = parse_date(p.get("to") or "") or start + timedelta(days=6)
            if (end - start).days > 62:
                raise serializers.ValidationError("Up to 2 months at a time.")
            tz = timezone.get_current_timezone()
            qs = qs.filter(start__gte=datetime.combine(start, time.min, tz),
                           start__lt=datetime.combine(end + timedelta(days=1), time.min, tz))
            if p.get("trainer"):
                qs = qs.filter(trainer_id=p["trainer"])
            if p.get("client"):
                qs = qs.filter(client_id=p["client"])
        return qs

    def perform_create(self, serializer):
        tell = serializer.validated_data.pop("tell_client", True)
        s = serializer.save(booked_by=self.request.user,
                            is_call=serializer.validated_data.get("is_call", False))
        activity_log("booked a session", "session", actor=self.request.user, target=s.client,
                     target_label=s.get_kind_display(), client=s.client, trainer=s.trainer)
        when = timezone.localtime(s.start)
        if tell:
            where = "on a call" if s.is_call else (s.place or "at the gym")
            notify(s.client, "session_booked", f"{s.get_kind_display()} with {s.trainer.first_name}",
                   f"{dfmt(when, '%a, %-d %b · %-I:%M %p')} · {where}", actor=self.request.user,
                   data={"route": f"/sessions/{s.id}"})
        if s.trainer != self.request.user:
            notify(s.trainer, "session_booked", f"New session with {s.client.full_name}",
                   f"{dfmt(when, '%a, %-d %b · %-I:%M %p')}", actor=self.request.user, data={"route": "/calendar"})

    def perform_update(self, serializer):
        old = serializer.instance.start
        tell = serializer.validated_data.pop("tell_client", True)
        s = serializer.save()
        if s.start != old:
            s.reminder_sent_at = None
            s.save(update_fields=["reminder_sent_at"])
            activity_log("moved a session", "session", actor=self.request.user, target=s.client,
                         target_label=s.get_kind_display(),
                         change=(f"{dfmt(timezone.localtime(old), '%a %-d %b %-I:%M %p')}",
                                 f"{dfmt(timezone.localtime(s.start), '%a %-d %b %-I:%M %p')}"),
                         client=s.client, trainer=s.trainer)
            if tell:
                notify(s.client, "session_moved", "Your session moved",
                       f"Now {dfmt(timezone.localtime(s.start), '%a, %-d %b · %-I:%M %p')}", actor=self.request.user,
                       data={"route": f"/sessions/{s.id}"})

    def destroy(self, request, *args, **kwargs):
        """Cancel session (kept with status cancelled, so Undo can bring it back)."""
        s = self.get_object()
        s.status = Session.Status.CANCELLED
        s.save(update_fields=["status", "updated_at"])
        tell = str(request.query_params.get("tell_client", "true")).lower() != "false"
        if tell:
            notify(s.client, "session_cancelled", "Session cancelled",
                   f"{s.get_kind_display()} on {dfmt(timezone.localtime(s.start), '%a, %-d %b · %-I:%M %p')} was cancelled.",
                   actor=request.user)
        activity_log("cancelled a session", "session", actor=request.user, target=s.client,
                     target_label=s.get_kind_display(), client=s.client, trainer=s.trainer)
        return Response({"id": str(s.id)})

    @action(detail=True, methods=["post"])
    def restore(self, request, pk=None):
        s = get_object_or_404(Session.objects.filter(status="cancelled"), pk=pk)
        if request.user.is_trainer and s.trainer != request.user:
            raise PermissionDenied()
        if session_clash(s.trainer, s.start, s.end, exclude=s.id):
            raise serializers.ValidationError("That time is taken now.")
        s.status = Session.Status.BOOKED
        s.save(update_fields=["status", "updated_at"])
        return Response(SessionSerializer(s, context={"request": request}).data)

    @action(detail=True, methods=["post"], url_path="status")
    def set_status(self, request, pk=None):
        s = self.get_object()
        new = request.data.get("status")
        if new not in ("booked", "done", "missed"):
            raise serializers.ValidationError({"status": ["Pick done, missed or booked."]})
        s.status = new
        s.save(update_fields=["status", "updated_at"])
        return Response(SessionSerializer(s, context={"request": request}).data)

    @action(detail=False)
    def check(self, request):
        """Live check under the form: free / clash / outside hours / day off."""
        p = request.query_params
        u = request.user
        if not p.get("trainer") or str(p.get("trainer")) == str(u.id):
            trainer = u
        elif u.is_trainer and not u.trainer_profile.has_perm("clients.view_all"):
            raise PermissionDenied("You can check only your own calendar.")
        else:
            trainer = get_object_or_404(User, id=p.get("trainer"), role__in=[Role.TRAINER, Role.ADMIN])
        start = parse_datetime(p.get("start") or "")
        if start is None:
            raise serializers.ValidationError({"start": ["Send start."]})
        if timezone.is_naive(start):
            start = timezone.make_aware(start)
        try:
            minutes = int(p.get("minutes", 60))
        except ValueError:
            minutes = 60
        end = start + timedelta(minutes=minutes)
        clash = session_clash(trainer, start, end, exclude=p.get("exclude"))
        if clash:
            return Response({"state": "clash", "with": clash.client.full_name, "start": clash.start, "end": clash.end})
        state, hours = working_check(trainer, start, end)
        return Response({"state": "free" if state == "ok" else state, "hours": hours})

    @action(detail=False)
    def stats(self, request):
        qs = self.filter_queryset(self.get_queryset())
        total = qs.count()
        done = qs.filter(status="done").count()
        calls = qs.filter(Q(is_call=True) | Q(kind__in=["quick_call", "program_review"])).count()
        busiest = qs.values("trainer__full_name").annotate(n=Count("id")).order_by("-n").first()
        by_trainer = list(qs.values("trainer_id", "trainer__full_name").annotate(n=Count("id")))
        return Response({"total": total, "done": done, "done_pct": round(100 * done / total) if total else 0,
                         "calls": calls, "busiest": busiest, "by_trainer": by_trainer})


class AvailabilityView(APIView):
    """Availability / My working hours drawer."""

    permission_classes = [IsStaff]

    def _trainer(self, request):
        tid = request.query_params.get("trainer") or request.data.get("trainer")
        if not tid or str(tid) == str(request.user.id):
            return request.user
        if not request.user.is_admin:
            raise PermissionDenied("You can change only your own working hours.")
        return get_object_or_404(User, id=tid, role__in=[Role.TRAINER, Role.ADMIN])

    def get(self, request):
        t = self._trainer(request)
        rows = {a.weekday: a for a in Availability.objects.filter(trainer=t)}
        days = [{"weekday": d, "is_working": rows[d].is_working if d in rows else d < 6,
                 "start": rows[d].start if d in rows else "06:30", "end": rows[d].end if d in rows else "20:00"}
                for d in range(7)]
        return Response({"trainer": str(t.id), "days": days,
                         "working_days": sum(1 for d in days if d["is_working"])})

    def put(self, request):
        t = self._trainer(request)
        if request.user.is_trainer and not request.user.trainer_profile.has_perm("schedule.own_calendar"):
            raise PermissionDenied("Your access does not include your calendar.")
        days = request.data.get("days")
        if not isinstance(days, list) or len(days) != 7:
            raise serializers.ValidationError({"days": ["Send all 7 days."]})
        with transaction.atomic():
            for d in days:
                wd = int(d.get("weekday", -1))
                if not 0 <= wd <= 6:
                    raise serializers.ValidationError({"days": ["Weekday is 0 to 6."]})
                st, en = d.get("start") or "06:30", d.get("end") or "20:00"
                if d.get("is_working") and st >= en:
                    raise serializers.ValidationError({"days": [f"Day {wd + 1}: end must be after start."]})
                Availability.objects.update_or_create(trainer=t, weekday=wd, defaults={
                    "is_working": bool(d.get("is_working")), "start": st, "end": en})
        return self.get(request)


class MySessionsView(APIView):
    """Client app: upcoming sessions (Home 'Session with', Coming up)."""

    permission_classes = [IsClient]

    def get(self, request):
        qs = (Session.objects.filter(client=request.user, start__gte=timezone.now() - timedelta(hours=2))
              .exclude(status="cancelled").select_related("trainer", "client").order_by("start")[:10])
        return Response(SessionSerializer(qs, many=True, context={"request": request}).data)
