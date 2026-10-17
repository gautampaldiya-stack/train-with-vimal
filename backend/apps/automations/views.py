from datetime import timedelta

from django.db import transaction
from django.db.models import Count, Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import mixins, serializers, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from apps.activity.services import log as activity_log
from apps.common.mixins import SoftDeleteViewMixin
from apps.common.permissions import IsAdmin, IsStaff

from . import engine
from .models import TRIGGER_GROUPS, Automation, AutomationRun, Step, TrainerTask, Trigger
from .starters import STARTERS, TRIGGER_CONFIG, TRIGGER_TEXT

CHANNELS = {"email", "push", "whatsapp", "in_app"}


class StepSerializer(serializers.ModelSerializer):
    id = serializers.IntegerField(required=False)
    summary = serializers.SerializerMethodField()

    class Meta:
        model = Step
        fields = ["id", "kind", "config", "summary"]

    def get_summary(self, obj):
        return step_line(obj.kind, obj.config)

    def validate(self, attrs):
        k, c = attrs["kind"], attrs.get("config") or {}
        if not isinstance(c, dict):
            raise serializers.ValidationError({"config": ["Send the step settings."]})
        clean = {}
        if k == Step.Kind.WAIT:
            clean["days"] = max(0, min(90, int(c.get("days", 0) or 0)))
            clean["hours"] = max(0, min(72, int(c.get("hours", 0) or 0)))
        else:
            ch = [x for x in c.get("channels", []) if x in CHANNELS] if k in (Step.Kind.MESSAGE,
                                                                              Step.Kind.FORM) else []
            if k == Step.Kind.MESSAGE:
                clean = {"template": str(c.get("template", ""))[:60], "channels": ch}
            elif k == Step.Kind.FORM:
                clean = {"form": str(c.get("form") or "")[:40], "form_name": str(c.get("form_name", ""))[:120],
                         "channels": ch}
            elif k == Step.Kind.TASK:
                clean = {"title": str(c.get("title", "")).strip()[:160],
                         "assignee": "owner" if c.get("assignee") == "owner" else "trainer",
                         "due_days": max(0, min(30, int(c.get("due_days", 1) or 0)))}
        attrs["config"] = clean
        return attrs


def step_line(kind, c):
    """Plain line for the step card and the preview panel."""
    c = c or {}
    chans = " and ".join({"email": "Email", "push": "Push", "whatsapp": "WhatsApp", "in_app": "In-app"}[x]
                         for x in c.get("channels", []) if x in CHANNELS)
    if kind == "wait":
        d, h = c.get("days", 0), c.get("hours", 0)
        if d:
            return f"Wait {d} day{'s' if d != 1 else ''}"
        return f"Wait {h} hour{'s' if h != 1 else ''}"
    if kind == "message":
        from apps.notifications.models import MessageTemplate

        t = MessageTemplate.objects.filter(key=c.get("template")).values_list("name", flat=True).first()
        return f"Send the message '{t or c.get('template')}'" + (f" by {chans}" if chans else "")
    if kind == "form":
        name = c.get("form_name")
        if c.get("form"):
            from apps.checkins.models import Form

            name = Form.objects.filter(id=c["form"]).values_list("name", flat=True).first() or name
        return f"Send the form '{name}'" + (f" by {chans}" if chans else "")
    who = "the owner" if c.get("assignee") == "owner" else "the assigned trainer"
    return f"Task for {who}: {c.get('title', '')}"


def trigger_line(a):
    c = a.trigger_config or {}
    t = a.trigger
    days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    return {
        "client_approved": "When a new client is approved",
        "plan_starts": "When a plan starts",
        "plan_ends": f"{c.get('days_before', 3)} days before a plan ends",
        "package_ending": f"{c.get('days_before', 7)} days before a package ends",
        "birthday": f"On the client's birthday at {c.get('time', '09:00')}",
        "every_week": f"Every {days[int(c.get('weekday', 6))]} at {c.get('time', '09:00')}",
        "every_day": f"Every day at {c.get('time', '08:00')}",
        "on_date": f"On {c.get('date')} at {c.get('time', '09:00')}",
        "missed_checkin": f"When a check-in is not sent within {c.get('hours', 24)} hours",
        "missed_workouts": f"When {c.get('count', 2)} workouts are missed in a row",
        "no_activity": f"When the app is not opened for {c.get('days', 7)} days",
        "form_sent": "When a client sends the form",
        "workout_streak": f"After {c.get('days', 7)} workout days in a row",
        "goal_weight": "When weight reaches the goal",
        "weight_flat": f"When weight stays the same for {c.get('weeks', 3)} weeks",
    }.get(t, "Pick a trigger")


class AutomationSerializer(serializers.ModelSerializer):
    steps = StepSerializer(many=True, required=False)
    trigger_line = serializers.SerializerMethodField()
    counts = serializers.SerializerMethodField()

    class Meta:
        model = Automation
        fields = ["id", "name", "status", "trigger", "trigger_config", "trigger_line", "scope_package",
                  "scope_trainer", "stop_on_response", "starter", "steps", "counts", "updated_at", "created_at"]
        read_only_fields = ["status"]

    def get_trigger_line(self, obj):
        return trigger_line(obj)

    def get_counts(self, obj):
        return {"running": getattr(obj, "n_running", None), "finished": getattr(obj, "n_finished", None),
                "stopped": getattr(obj, "n_stopped", None)}

    def validate_name(self, v):
        v = " ".join(v.split())
        if len(v) < 2:
            raise serializers.ValidationError("Name the automation.")
        return v

    def validate_trigger_config(self, v):
        if not isinstance(v, dict):
            raise serializers.ValidationError("Send the trigger settings.")
        return {k: v[k] for k in v if k in ("days_before", "plan_type", "weekday", "time", "date", "hours", "count",
                                            "days", "form", "weeks")}

    def validate(self, attrs):
        t = attrs.get("trigger", self.instance.trigger if self.instance else "")
        cfg = attrs.get("trigger_config", self.instance.trigger_config if self.instance else {}) or {}
        spec = TRIGGER_CONFIG.get(t, {})
        for k, lim in spec.items():
            if isinstance(lim, tuple) and k in cfg:
                try:
                    v = int(cfg[k])
                except (TypeError, ValueError):
                    raise serializers.ValidationError({"trigger_config": [f"{k} must be a number."]})
                if not lim[0] <= v <= lim[1]:
                    raise serializers.ValidationError({"trigger_config": [f"{k} is {lim[0]} to {lim[1]}."]})
        if len(attrs.get("steps", [])) > 20:
            raise serializers.ValidationError({"steps": ["Up to 20 steps."]})
        return attrs

    def _save_steps(self, a, steps):
        keep = []
        for i, sd in enumerate(steps):
            s = a.steps.filter(id=sd.get("id")).first() if sd.get("id") else None
            s = s or Step(automation=a)
            s.kind, s.config, s.order = sd["kind"], sd["config"], i
            s.save()
            keep.append(s.id)
        a.steps.exclude(id__in=keep).delete()

    def create(self, validated):
        steps = validated.pop("steps", [])
        a = Automation.objects.create(**validated)
        self._save_steps(a, steps)
        return a

    def update(self, a, validated):
        steps = validated.pop("steps", None)
        for k, v in validated.items():
            setattr(a, k, v)
        a.save()
        if steps is not None:
            self._save_steps(a, steps)
        return a


class RunSerializer(serializers.ModelSerializer):
    client = serializers.SerializerMethodField()
    steps_total = serializers.SerializerMethodField()

    class Meta:
        model = AutomationRun
        fields = ["id", "client", "status", "step_index", "steps_total", "next_run_at", "last_message", "log",
                  "created_at", "finished_at"]

    def get_client(self, obj):
        u = obj.client
        return {"id": str(u.id), "full_name": u.full_name, "initials": u.initials, "avatar_color": u.avatar_color}

    def get_steps_total(self, obj):
        return obj.automation.steps.count()


class AutomationViewSet(SoftDeleteViewMixin, viewsets.ModelViewSet):
    """Automations are gym-wide: only the admin builds them."""

    serializer_class = AutomationSerializer
    permission_classes = [IsAdmin]
    pagination_class = None
    http_method_names = ["get", "post", "patch", "delete"]

    def get_queryset(self):
        return Automation.objects.annotate(
            n_running=Count("runs", filter=Q(runs__status__in=["running", "waiting"]), distinct=True),
            n_finished=Count("runs", filter=Q(runs__status="finished"), distinct=True),
            n_stopped=Count("runs", filter=Q(runs__status__in=["stopped", "failed"]), distinct=True),
        ).prefetch_related("steps")

    def perform_create(self, serializer):
        a = serializer.save(created_by=self.request.user, status=Automation.Status.DRAFT)
        activity_log("created an automation", "system", actor=self.request.user, target=a, target_label=a.name)

    def perform_update(self, serializer):
        a = serializer.save()
        if a.status == Automation.Status.ON and engine.problems(a):
            a.status = Automation.Status.DRAFT
            a.save(update_fields=["status"])

    def perform_destroy(self, instance):
        with transaction.atomic():
            instance.soft_delete()
            instance.runs.filter(status__in=["running", "waiting"]).update(
                status="stopped", last_message="Automation deleted", finished_at=timezone.now())

    @action(detail=False)
    def stats(self, request):
        from apps.notifications.models import Delivery

        month = timezone.localdate().replace(day=1)
        qs = Automation.objects.all()
        d = Delivery.objects.filter(automation_run__isnull=False, created_at__date__gte=month)
        total = d.count()
        delivered = d.filter(status__in=["delivered", "opened", "sent"]).count()
        opened = d.filter(status="opened").count()
        tasks = TrainerTask.objects.filter(automation_run__isnull=False)
        return Response({
            "on": qs.filter(status="on").count(), "total": qs.count(),
            "in_flow": AutomationRun.objects.filter(status__in=["running", "waiting"]).values("client")
            .distinct().count(),
            "messages_month": total,
            "delivered_pct": round(100 * delivered / total) if total else None,
            "opened_pct": round(100 * opened / total) if total else None,
            "tasks": tasks.count(), "tasks_open": tasks.filter(done_at__isnull=True).count(),
        })

    @action(detail=False)
    def catalog(self, request):
        """Triggers with group, line and the settings each needs; starters; channels."""
        return Response({
            "groups": TRIGGER_GROUPS,
            "triggers": [{"key": k, "label": label, "line": TRIGGER_TEXT[k],
                          "settings": {s: (list(v) if isinstance(v, tuple) else v)
                                       for s, v in TRIGGER_CONFIG.get(k, {}).items()}}
                         for k, label in Trigger.choices],
            "starters": [{**{k: v for k, v in s.items() if k != "steps"}, "step_count": len(s["steps"]),
                          "steps": [{**st, "summary": step_line(st["kind"], st["config"])} for st in s["steps"]]}
                         for s in STARTERS],
        })

    @action(detail=False, methods=["post"], url_path="from-starter")
    def from_starter(self, request):
        key = request.data.get("starter")
        if key == "blank":
            a = Automation.objects.create(name="New automation", created_by=request.user)
            return Response(AutomationSerializer(a).data, status=201)
        st = next((s for s in STARTERS if s["key"] == key), None)
        if st is None:
            raise serializers.ValidationError({"starter": ["Pick a starter or Blank."]})
        from apps.checkins.models import Form

        with transaction.atomic():
            a = Automation.objects.create(name=st["name"], trigger=st["trigger"], trigger_config=st["trigger_config"],
                                          stop_on_response=st["stop_on_response"], starter=key,
                                          created_by=request.user)
            for i, s in enumerate(st["steps"]):
                cfg = dict(s["config"])
                if s["kind"] == "form" and cfg.get("form_name"):
                    f = Form.objects.filter(name=cfg["form_name"]).exclude(status="client").first()
                    cfg["form"] = str(f.id) if f else ""
                Step.objects.create(automation=a, kind=s["kind"], config=cfg, order=i)
        return Response(AutomationSerializer(self.get_queryset().get(id=a.id)).data, status=201)

    @action(detail=True, methods=["post"], url_path="turn-on")
    def turn_on(self, request, pk=None):
        a = self.get_object()
        issues = engine.problems(a)
        if issues:
            return Response({"error": {"code": "not_ready", "message": f"Not ready to turn on — {issues[0]}",
                                       "fields": {"problems": issues}}}, status=400)
        a.status = Automation.Status.ON
        a.save(update_fields=["status", "updated_at"])
        activity_log("turned on an automation", "system", actor=request.user, target=a, target_label=a.name)
        return Response(AutomationSerializer(self.get_queryset().get(id=a.id)).data)

    @action(detail=True, methods=["post"], url_path="turn-off")
    def turn_off(self, request, pk=None):
        a = self.get_object()
        a.status = Automation.Status.OFF
        a.save(update_fields=["status", "updated_at"])
        return Response(AutomationSerializer(self.get_queryset().get(id=a.id)).data)

    @action(detail=True, methods=["post"], url_path="save-draft")
    def save_draft(self, request, pk=None):
        a = self.get_object()
        a.status = Automation.Status.DRAFT
        a.save(update_fields=["status", "updated_at"])
        return Response(AutomationSerializer(self.get_queryset().get(id=a.id)).data)

    @action(detail=True, methods=["post"])
    def duplicate(self, request, pk=None):
        src = self.get_object()
        with transaction.atomic():
            a = Automation.objects.create(name=f"{src.name} (copy)"[:100], trigger=src.trigger,
                                          trigger_config=src.trigger_config, scope_package=src.scope_package,
                                          scope_trainer=src.scope_trainer, stop_on_response=src.stop_on_response,
                                          created_by=request.user)
            Step.objects.bulk_create([Step(automation=a, kind=s.kind, config=s.config, order=s.order)
                                      for s in src.steps.all()])
        return Response(AutomationSerializer(self.get_queryset().get(id=a.id)).data, status=201)

    @action(detail=True)
    def runs(self, request, pk=None):
        a = self.get_object()
        qs = a.runs.select_related("client", "automation").order_by("-created_at")
        return Response({
            "started": qs.count(), "finished": qs.filter(status="finished").count(),
            "stopped": qs.filter(status__in=["stopped", "failed"]).count(),
            "rows": RunSerializer(qs[:100], many=True).data,
        })

    @action(detail=False)
    def packages(self, request):
        from apps.clients.models import ClientProfile

        return Response(sorted(set(ClientProfile.objects.exclude(package_name="")
                                   .values_list("package_name", flat=True))))


class TaskSerializer(serializers.ModelSerializer):
    client_detail = serializers.SerializerMethodField()

    class Meta:
        model = TrainerTask
        fields = ["id", "title", "detail", "client", "client_detail", "due_on", "done_at", "created_at"]
        read_only_fields = ["detail", "done_at"]

    def get_client_detail(self, obj):
        u = obj.client
        return {"id": str(u.id), "full_name": u.full_name, "initials": u.initials,
                "avatar_color": u.avatar_color} if u else None

    def validate_title(self, v):
        v = " ".join(v.split())
        if len(v) < 2:
            raise serializers.ValidationError("Write the task.")
        return v

    def validate_client(self, c):
        from apps.clients.services import visible_clients

        if c and not visible_clients(self.context["request"].user).filter(id=c.id).exists():
            raise serializers.ValidationError("Pick one of your clients.")
        return c


class TaskViewSet(mixins.ListModelMixin, mixins.CreateModelMixin, mixins.UpdateModelMixin,
                  mixins.DestroyModelMixin, viewsets.GenericViewSet):
    """Tasks card (dashboard): tick to finish, add by hand."""

    serializer_class = TaskSerializer
    permission_classes = [IsStaff]
    http_method_names = ["get", "post", "patch", "delete"]

    def get_queryset(self):
        qs = TrainerTask.objects.filter(assignee=self.request.user).select_related("client")
        if self.request.query_params.get("open") == "1":
            qs = qs.filter(done_at__isnull=True)
        return qs

    def perform_create(self, serializer):
        serializer.save(assignee=self.request.user, created_by=self.request.user,
                        due_on=serializer.validated_data.get("due_on") or timezone.localdate() + timedelta(days=1))

    @action(detail=True, methods=["post"])
    def done(self, request, pk=None):
        t = get_object_or_404(self.get_queryset(), pk=pk)
        t.done_at = None if request.data.get("done") is False else timezone.now()
        t.save(update_fields=["done_at", "updated_at"])
        return Response(TaskSerializer(t).data)
