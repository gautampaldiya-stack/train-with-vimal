from datetime import timedelta

from django.db import transaction
from django.db.models import Count, Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.utils.dateparse import parse_date
from rest_framework import serializers, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.activity.services import log as activity_log
from apps.clients.services import get_visible_client, visible_clients
from apps.common.mixins import SoftDeleteViewMixin
from apps.common.permissions import IsClient, IsStaff
from apps.notifications.services import notify

from .models import (
    Habit,
    HabitAssignment,
    HabitLog,
    SupplementAssignment,
    SupplementItem,
    SupplementLog,
    SupplementPlan,
    SupplementStock,
)
from .serializers import QUICK_ADD, HabitSerializer, SupplementItemSerializer, SupplementPlanSerializer
from apps.common.utils import dfmt


def _set_clients(model, field, obj, ids, actor, label):
    """Assign drawer save for habits and supplement plans: followers become exactly `ids`."""
    visible = {str(i) for i in visible_clients(actor).values_list("id", flat=True)}
    ids = {i for i in map(str, ids)}
    current = {str(c) for c in model.objects.filter(**{field: obj}, active=True).values_list("client_id", flat=True)}
    added = [i for i in ids - current if i in visible]
    removed = [i for i in current - ids if i in visible]
    with transaction.atomic():
        for cid in added:
            row, created = model.objects.get_or_create(**{field: obj}, client_id=cid,
                                                       defaults={"assigned_by": actor})
            if not created:
                row.active = True
                row.start_date = timezone.localdate()
                row.save(update_fields=["active", "start_date", "updated_at"])
        model.objects.filter(**{field: obj}, client_id__in=removed).update(active=False)
    from django.contrib.auth import get_user_model

    if added:
        clients = list(get_user_model().objects.filter(id__in=added))
        notify(clients, "plan_assigned", f"New in your plan: {label}", "", actor=actor, data={"route": "/habits"})
        verb = "added a habit" if model is HabitAssignment else "assigned supplements"
        for c in clients:
            activity_log(verb, "plan", actor=actor, target=c, target_label=label, client=c)
    for c in get_user_model().objects.filter(id__in=removed) if removed else []:
        activity_log("removed a habit" if model is HabitAssignment else "removed supplements", "plan", actor=actor,
                     target=c, target_label=label, client=c)
    return len(added), len(removed)


def _assign_options(request, model, field, obj):
    on = set(model.objects.filter(**{field: obj}, active=True).values_list("client_id", flat=True))
    rows = visible_clients(request.user).filter(status__in=["active", "paused"]).select_related(
        "client_profile__trainer")
    return [{"id": str(u.id), "full_name": u.full_name, "initials": u.initials, "avatar_color": u.avatar_color,
             "goal": u.client_profile.get_goal_display(), "on_it": u.id in on} for u in rows]


class _StaffWrite:
    """Who may change the library (D-45, like programs in D-39): a trainer with the tab's access makes new
    habits / plans, duplicates any, and changes or deletes the ones they made; "Edit gym templates" changes all."""

    def check_permissions(self, request):
        super().check_permissions(request)
        u = request.user
        if u.is_trainer and request.method not in ("GET", "HEAD", "OPTIONS"):
            if not u.trainer_profile.has_perm(self.assign_permission):
                raise PermissionDenied("Your access does not include this. Ask Vimal for more access.")

    def check_object_permissions(self, request, obj):
        super().check_object_permissions(request, obj)
        u = request.user
        if u.is_trainer and request.method not in ("GET", "HEAD", "OPTIONS") and self.action not in ("assign", "duplicate"):
            if obj.created_by_id != u.id and not u.trainer_profile.has_perm("training.edit_templates"):
                raise PermissionDenied("Only Vimal or a trainer with \"Edit gym templates\" can change this. "
                                       "Duplicate it to make your own.")


class HabitViewSet(_StaffWrite, SoftDeleteViewMixin, viewsets.ModelViewSet):
    serializer_class = HabitSerializer
    permission_classes = [IsStaff]
    assign_permission = "nutrition.meal_plans"
    search_fields = ["name"]
    pagination_class = None
    http_method_names = ["get", "post", "patch", "delete"]

    def get_queryset(self):
        return Habit.objects.annotate(n_clients=Count("assignments", filter=Q(assignments__active=True)))

    @action(detail=False)
    def counts(self, request):
        """Tab counts and what the page offers this person: edit (New habit / plan, Save, Duplicate, Delete) and
        Assign, per tab (D-39)."""
        u = request.user
        can = lambda k: u.is_admin or (u.is_trainer and u.trainer_profile.has_perm(k))  # noqa: E731
        return Response({"habits": Habit.objects.count(), "supplements": SupplementPlan.objects.filter(is_master=True).count(),
                         "can": {"edit": can("training.edit_templates"), "assign_habits": can(HabitViewSet.assign_permission),
                                 "assign_supplements": can(SupplementPlanViewSet.assign_permission),
                                 "create_habits": can(HabitViewSet.assign_permission),
                                 "create_supplements": can(SupplementPlanViewSet.assign_permission)}})

    def perform_create(self, serializer):
        h = serializer.save(created_by=self.request.user)
        activity_log("created a habit", "plan", actor=self.request.user, target=h, target_label=h.name)

    def perform_update(self, serializer):
        h = serializer.save()
        # "Saved changes reach everyone on it" — live refresh for clients on it
        from apps.notifications.realtime import send_to_user

        for cid in h.assignments.filter(active=True).values_list("client_id", flat=True):
            transaction.on_commit(lambda cid=cid: send_to_user(cid, "plan_changed", {"kind": "habit"}))

    @action(detail=True, methods=["post"])
    def duplicate(self, request, pk=None):
        src = self.get_object()
        h = Habit.objects.create(name=f"{src.name} (copy)"[:80], kind=src.kind, target=src.target, unit=src.unit,
                                 frequency=src.frequency, days=src.days, times_per_week=src.times_per_week,
                                 icon=src.icon, why=src.why, created_by=request.user)
        return Response(HabitSerializer(h).data, status=201)

    @action(detail=True, methods=["get", "post"])
    def assign(self, request, pk=None):
        h = self.get_object()
        if request.method == "GET":
            return Response(_assign_options(request, HabitAssignment, "habit", h))
        added, removed = _set_clients(HabitAssignment, "habit", h, request.data.get("clients") or [],
                                      request.user, h.name)
        return Response({"added": added, "removed": removed})


class SupplementPlanViewSet(_StaffWrite, SoftDeleteViewMixin, viewsets.ModelViewSet):
    serializer_class = SupplementPlanSerializer
    permission_classes = [IsStaff]
    assign_permission = "nutrition.supplements"
    pagination_class = None
    http_method_names = ["get", "post", "patch", "delete"]

    def get_queryset(self):
        return SupplementPlan.objects.filter(is_master=True).annotate(  # client copies never show in the library
            n_clients=Count("assignments", filter=Q(assignments__active=True))).prefetch_related("items")

    def perform_create(self, serializer):
        serializer.save(created_by=self.request.user)

    @action(detail=False, url_path="quick-add")
    def quick_add(self, request):
        return Response(QUICK_ADD)

    @action(detail=True, methods=["post"])
    def duplicate(self, request, pk=None):
        src = self.get_object()
        with transaction.atomic():
            p = SupplementPlan.objects.create(name=f"{src.name} (copy)"[:80], note=src.note, created_by=request.user)
            SupplementItem.objects.bulk_create([
                SupplementItem(plan=p, name=i.name, dose=i.dose, how=i.how, timing=i.timing, days=i.days,
                               with_food=i.with_food, order=i.order) for i in src.items.all()])
        return Response(SupplementPlanSerializer(self.get_queryset().get(id=p.id)).data, status=201)

    @action(detail=True, methods=["get", "post"])
    def assign(self, request, pk=None):
        p = self.get_object()
        if request.method == "GET":
            return Response(_assign_options(request, SupplementAssignment, "plan", p))
        added, removed = _set_clients(SupplementAssignment, "plan", p, request.data.get("clients") or [],
                                      request.user, p.name)
        return Response({"added": added, "removed": removed})


# ---------------------------------------------------------------- one client's supplements and habits
class _ClientSlot(viewsets.ViewSet):
    """Client profile → Plans → Supplements / Habits slot: current, Up next (starts later) and history;
    assign for one client; end one. `when`: `next` (runs next to the current ones), `now` (replaces them),
    `date` (starts on `start_date`, up to 3 months ahead)."""

    permission_classes = [IsStaff]
    model = None
    field = ""
    write_permission = ""

    def _client(self):
        try:
            return get_visible_client(self.request.user, self.kwargs["client_pk"])
        except Exception:
            from django.http import Http404

            raise Http404

    def _check_write(self, request):
        if request.user.is_trainer and not request.user.trainer_profile.has_perm(self.write_permission):
            raise PermissionDenied("Your access does not include this. Ask Vimal for more access.")

    def _start(self, request):
        today = timezone.localdate()
        when = request.data.get("when") or "next"
        if when not in ("next", "now", "date"):
            raise serializers.ValidationError({"when": ["Pick when it starts."]})
        if when != "date":
            return when, today
        start = parse_date(str(request.data.get("start_date") or ""))
        if not start or start < today or start > today + timedelta(days=92):
            raise serializers.ValidationError({"start_date": ["Pick a date from today up to 3 months ahead."]})
        return when, start

    def _rows(self, client):
        today = timezone.localdate()
        rows = list(self.model.objects.filter(client=client).select_related(self.field, "assigned_by")
                    .order_by("-start_date", "-created_at"))
        return {"current": [self.row(a) for a in rows if a.active and a.start_date <= today],
                "up_next": [self.row(a) for a in rows if a.active and a.start_date > today],
                "history": [self.row(a) for a in rows if not a.active]}

    def list(self, request, client_pk=None):
        return Response(self._rows(self._client()))

    def _assign(self, request, client, objs, label):
        when, start = self._start(request)
        with transaction.atomic():
            if when == "now":
                self.model.objects.filter(client=client, active=True).exclude(**{f"{self.field}__in": objs}) \
                    .update(active=False, updated_at=timezone.now())
            for o in objs:
                row, created = self.model.objects.get_or_create(**{self.field: o}, client=client,
                                                                defaults={"assigned_by": request.user,
                                                                          "start_date": start})
                if not created:
                    row.active, row.start_date, row.assigned_by = True, start, request.user
                    row.save(update_fields=["active", "start_date", "assigned_by", "updated_at"])
        activity_log(f"assigned {label}", "plan", actor=request.user, target=client,
                     target_label=", ".join(getattr(o, "name", "") for o in objs), client=client)
        if request.data.get("notify", True) is not False:
            notify(client, "plan_assigned", f"New in your plan: {objs[0].name}" if len(objs) == 1
                   else f"{len(objs)} new habits in your plan", "", actor=request.user, data={"route": "/habits"})
        return Response(self._rows(client), status=201)

    @action(detail=True, methods=["post"])
    def end(self, request, client_pk=None, pk=None):
        self._check_write(request)
        client = self._client()
        a = get_object_or_404(self.model.objects.select_related(self.field), id=pk, client=client, active=True)
        if a.start_date > timezone.localdate():  # not started yet: nothing to keep in history
            a.delete()
            return Response(self._rows(client))
        a.active = False
        a.save(update_fields=["active", "updated_at"])
        activity_log("ended a plan", "plan", actor=request.user, target=client,
                     target_label=getattr(a, self.field).name, client=client)
        return Response(self._rows(client))


class ClientSupplementPlansViewSet(_ClientSlot):
    model = SupplementAssignment
    field = "plan"
    write_permission = "nutrition.supplements"

    @staticmethod
    def row(a):
        """`plan` is the master's id; `items` what the client takes (their copy, else the master)."""
        p = a.followed
        stocks = {s.item_id: s for s in SupplementStock.objects.filter(client=a.client, item__plan=p)}
        return {"id": a.id, "plan": a.plan_id, "plan_name": p.name, "note": p.note, "start_date": a.start_date,
                "custom": a.custom_plan_id is not None, "copy": a.custom_plan_id, "master_name": a.plan.name,
                "ended_on": a.updated_at.date() if not a.active else None, "active": a.active,
                "assigned_by": a.assigned_by.full_name if a.assigned_by else None,
                "items": [{"id": i.id, "name": i.name, "dose": i.dose, "how": i.how, "timing": i.timing,
                           "timing_label": i.get_timing_display(), "days": i.days, "with_food": i.with_food,
                           "stock": {"quantity": stocks[i.id].quantity, "unit": stocks[i.id].unit}
                           if i.id in stocks else None} for i in p.items.all()]}

    def create(self, request, client_pk=None):
        self._check_write(request)
        client = self._client()
        plan = SupplementPlan.objects.filter(id=request.data.get("plan"), is_master=True).first()
        if plan is None:
            raise serializers.ValidationError({"plan": ["Pick a supplement plan."]})
        return self._assign(request, client, [plan], "a supplement plan")

    def _mine(self, pk):
        return get_object_or_404(SupplementAssignment.objects.select_related("plan", "custom_plan", "client"),
                                 id=pk, client=self._client(), active=True)

    @action(detail=True, methods=["put"])
    def items(self, request, client_pk=None, pk=None):
        """Supplements → Edit for X → Save {items: [{id?, name, dose, how, timing, days, with_food}]}. The first
        save makes the client's own copy of the plan; the master and other clients stay the same. Item ids are
        those of the plan the client follows now (the master's on the first save)."""
        self._check_write(request)
        a = self._mine(pk)
        s = SupplementItemSerializer(data=request.data.get("items"), many=True)
        s.is_valid(raise_exception=True)
        with transaction.atomic():
            copy, ids = _supp_copy(a, actor=request.user)
            items = [{**d, "id": ids.get(d.get("id"), d.get("id"))} for d in s.validated_data]
            SupplementPlanSerializer()._save_items(copy, items)
            # "Stock at home" per row: {quantity, unit}; null clears it. Rows without the key keep theirs.
            for it, raw in zip(copy.items.order_by("order"), request.data.get("items") or []):
                if not isinstance(raw, dict) or "stock" not in raw:
                    continue
                st = raw.get("stock")
                if st in (None, "") or st.get("quantity") in (None, ""):
                    SupplementStock.objects.filter(client=a.client, item=it).delete()
                    continue
                try:
                    q = int(st.get("quantity"))
                except (TypeError, ValueError):
                    q = -1
                if not 0 <= q <= 10000:
                    raise serializers.ValidationError({"stock": [f"Check the stock of {it.name}."]})
                SupplementStock.objects.update_or_create(item=it, client=a.client, defaults={
                    "quantity": q, "unit": (str(st.get("unit") or "") or "tablets")[:20]})
        activity_log("changed supplements for one client", "plan", actor=request.user, target=a.client,
                     target_label=a.plan.name, client=a.client)
        from apps.notifications.realtime import send_to_user

        transaction.on_commit(lambda: send_to_user(a.client_id, "plan_changed", {"kind": "supplement"}))
        a.refresh_from_db()
        return Response(self.row(a))

    @action(detail=True, methods=["post"])
    def reset(self, request, client_pk=None, pk=None):
        """Reset to master: the client takes the master plan again. Ticks and stock move back to the master's
        supplement of the same name."""
        self._check_write(request)
        a = self._mine(pk)
        if a.custom_plan_id:
            with transaction.atomic():
                by_name = {i.name.strip().lower(): i.id for i in a.plan.items.all()}
                _move_supp_rows(a.client, {i.id: by_name[i.name.strip().lower()] for i in a.custom_plan.items.all()
                                           if i.name.strip().lower() in by_name})
                a.custom_plan = None
                a.save(update_fields=["custom_plan", "updated_at"])
            activity_log("reset supplements to the master", "plan", actor=request.user, target=a.client,
                         target_label=a.plan.name, client=a.client)
        return Response(self.row(a))


def _move_supp_rows(client, ids):
    """Moves this client's ticks and stock from one plan's supplements to another's ({old item id: new})."""
    for old, new in ids.items():
        taken = set(SupplementLog.objects.filter(client=client, item_id=new).values_list("date", flat=True))
        SupplementLog.objects.filter(client=client, item_id=old).exclude(date__in=taken).update(item_id=new)
        if not SupplementStock.objects.filter(client=client, item_id=new).exists():
            SupplementStock.objects.filter(client=client, item_id=old).update(item_id=new)


def _supp_copy(a, *, actor):
    """The client's own copy of their supplement plan, made on the first edit. Returns (copy, {master item id:
    copy item id}); the map is empty when the copy already exists."""
    if a.custom_plan_id:
        return a.custom_plan, {}
    src = a.plan
    copy = SupplementPlan.objects.create(name=src.name, note=src.note, is_master=False, master=src,
                                         created_by=actor)
    ids = {}
    for i in src.items.all():
        ids[i.id] = SupplementItem.objects.create(plan=copy, name=i.name, dose=i.dose, how=i.how, timing=i.timing,
                                                  days=i.days, with_food=i.with_food, order=i.order).id
    _move_supp_rows(a.client, ids)
    a.custom_plan = copy
    a.save(update_fields=["custom_plan", "updated_at"])
    return copy, ids


class ClientHabitPlansViewSet(_ClientSlot):
    model = HabitAssignment
    field = "habit"
    write_permission = "nutrition.meal_plans"

    @staticmethod
    def row(a):
        """`habit` is the habit as this client has it; `library` the library habit when it differs."""
        return {"id": a.id, "habit": HabitSerializer(a.eff).data, "start_date": a.start_date, "active": a.active,
                "ended_on": a.updated_at.date() if not a.active else None,
                "assigned_by": a.assigned_by.full_name if a.assigned_by else None,
                "custom": a.custom, "library": HabitSerializer(a.habit).data if a.custom else None,
                "note": a.note}

    def partial_update(self, request, client_pk=None, pk=None):
        """Edit habits → Edit: this client's target, how often and note. Same as the library = cleared."""
        self._check_write(request)
        client = self._client()
        a = get_object_or_404(HabitAssignment.objects.select_related("habit"), id=pk, client=client, active=True)
        h, d = a.habit, request.data
        if "target" in d and h.kind == Habit.Kind.COUNTER:
            try:
                t = int(d["target"]) if d["target"] not in (None, "") else None
            except (TypeError, ValueError):
                raise serializers.ValidationError({"target": ["Enter a number."]})
            if t is not None and not 1 <= t <= 200000:
                raise serializers.ValidationError({"target": ["Enter a target from 1 to 200,000."]})
            a.target = None if t in (None, h.target) else t
        if "frequency" in d:
            f = d.get("frequency") or ""
            if f and f not in Habit.Frequency.values:
                raise serializers.ValidationError({"frequency": ["Pick how often."]})
            days = sorted({int(x) for x in (d.get("days") or []) if str(x).isdigit() and int(x) <= 6})
            n = d.get("times_per_week")
            if f == Habit.Frequency.DAYS and not days:
                raise serializers.ValidationError({"days": ["Pick at least one day."]})
            if f == Habit.Frequency.TIMES_WEEK:
                try:
                    n = int(n)
                except (TypeError, ValueError):
                    n = 0
                if not 1 <= n <= 7:
                    raise serializers.ValidationError({"times_per_week": ["1 to 7 times a week."]})
            else:
                n = None
            if f != Habit.Frequency.DAYS:
                days = []
            same = f == h.frequency and days == sorted(h.days or []) and n == h.times_per_week
            a.frequency, a.days, a.times_per_week = ("", [], None) if not f or same else (f, days, n)
        if "note" in d:
            note = " ".join(str(d.get("note") or "").split())
            if len(note) > 200:
                raise serializers.ValidationError({"note": ["Keep it under 200 characters."]})
            a.note = "" if note == h.why else note
        a.save(update_fields=["target", "frequency", "days", "times_per_week", "note", "updated_at"])
        activity_log("changed a habit for one client", "plan", actor=request.user, target=client,
                     target_label=h.name, client=client)
        return Response(self._rows(client))

    def create(self, request, client_pk=None):
        self._check_write(request)
        client = self._client()
        ids = request.data.get("habits")
        habits = list(Habit.objects.filter(id__in=ids)) if isinstance(ids, list) and ids else []
        if not habits:
            raise serializers.ValidationError({"habits": ["Pick at least one habit."]})
        return self._assign(request, client, habits, "habits")


# ---------------------------------------------------------------- shared day view
def _streaks(client, habit, today):
    days = set(HabitLog.objects.filter(client=client, habit=habit, done=True).values_list("date", flat=True))
    best = cur = 0
    run = 0
    if days:
        d, end = min(days), today
        while d <= end:
            if d in days:
                run += 1
                best = max(best, run)
            elif habit.is_due_on(d):
                run = 0
            d += timedelta(days=1)
    d = today if today in days else today - timedelta(days=1)
    while d in days or (not habit.is_due_on(d) and d >= today - timedelta(days=366)):
        if d in days:
            cur += 1
        d -= timedelta(days=1)
    return cur, best


# Supplement groups on the Habits page: name, line, default reminder time ("Morning · With breakfast · 8:00 am").
SUPP_GROUPS = {
    "breakfast": ("morning", "Morning", "With breakfast · 8:00 am"),
    "morning": ("morning", "Morning", "With breakfast · 8:00 am"),
    "post_workout": ("training", "After training", "After your workout"),
    "any": ("any", "Any time", "When it suits you"),
    "night": ("night", "Night", "Before bed · 10:30 pm"),
    "before_bed": ("night", "Night", "Before bed · 10:30 pm"),
}
SHORT = {"steps": "Steps", "water": "Water", "sleep": "Sleep"}


def _cell(ok, d, today, active):
    """One day of the week grid: done / missed / today (not yet) / coming / off (not due, not started)."""
    if not active:
        return "off"
    if ok:
        return "done"
    if d > today:
        return "coming"
    return "today" if d == today else "missed"


def habits_day(client, day):
    today = timezone.localdate()
    start = day - timedelta(days=6)
    strip_start = today - timedelta(days=6)
    ws = day - timedelta(days=day.weekday())  # Monday of the picked day's week
    week = [ws + timedelta(days=i) for i in range(7)]
    assigns = list(HabitAssignment.objects.filter(client=client, active=True).select_related("habit", "assigned_by"))
    lo, hi = min(start, strip_start, ws), max(day, today + timedelta(days=2), week[-1])
    logs = {(l.habit_id, l.date): l for l in HabitLog.objects.filter(client=client, date__range=(lo, hi))}
    done_on = lambda h, d: bool((lg := logs.get((h.id, d))) and lg.done)  # noqa: E731
    habits = []
    h_done = h_due = 0
    best = (None, 0)
    for a in assigns:
        h = a.eff
        log = logs.get((h.id, day))
        cur, top = _streaks(client, h, today)
        due_on = lambda d: d >= a.start_date and h.is_due_on(d)  # noqa: E731
        cells = [_cell(done_on(h, d), d, today, due_on(d)) for d in week]
        for d in week:
            if d < today and due_on(d):
                h_due += 1
                h_done += done_on(h, d)
            elif d == today and done_on(h, d):
                h_due += 1
                h_done += 1
        if cur > best[1]:
            best = (SHORT.get(h.icon, h.name), cur)
        habits.append({
            **HabitSerializer(h).data, "assignment": a.id, "custom": a.custom,
            "value": log.value if log else 0, "logged": log is not None, "done": bool(log and log.done),
            "due": h.is_due_on(day), "starts_on": a.start_date if a.start_date > today else None,
            "since": a.start_date, "set_by": a.assigned_by.full_name if a.assigned_by else None,
            "streak": cur, "best_streak": top,
            "last_7": [{"date": start + timedelta(days=i), "done": done_on(h, start + timedelta(days=i)),
                        "value": (lg.value if (lg := logs.get((h.id, start + timedelta(days=i)))) else None)}
                       for i in range(7)],
            "week": cells, "week_done": cells.count("done"),
            "week_due": sum(1 for d in week if d <= today and due_on(d)),
        })
    strip = []
    for i in range(9):
        d = strip_start + timedelta(days=i)
        due = [a.eff for a in assigns if a.eff.is_due_on(d) and d >= a.start_date]
        done = sum(1 for h in due if done_on(h, d))
        strip.append({"date": d, "today": d == today, "future": d > today,
                      "state": "none" if d > today or not due else ("done" if done == len(due) else
                                                                    ("today" if d == today else "missed"))})
    days = []
    for d in week:
        due = [a.eff for a in assigns if a.eff.is_due_on(d) and d >= a.start_date]
        n = sum(1 for h in due if done_on(h, d))
        days.append({"date": d, "today": d == today, "future": d > today,
                     "state": "coming" if d > today else "none" if not due else "done" if n == len(due)
                     else "today" if d == today else "part" if n else "missed"})
    supps = []
    s_done = s_due = 0
    for sa in SupplementAssignment.objects.filter(client=client, active=True).select_related("plan", "custom_plan",
                                                                                              "assigned_by"):
        took = {(lg.item_id, lg.date): lg for lg in SupplementLog.objects.filter(
            client=client, item__plan=sa.followed, date__range=(min(start, ws), max(day, week[-1])))}
        stocks = {s.item_id: s for s in SupplementStock.objects.filter(client=client, item__plan=sa.followed)}
        for it in sa.followed.items.all():
            is_due = lambda d: d >= sa.start_date and (not it.days or d.weekday() in it.days)  # noqa: E731
            due = not it.days or day.weekday() in it.days
            lg = took.get((it.id, day))
            if day < sa.start_date:
                pill = f"Starts {dfmt(sa.start_date, '%a, %-d %b')}"
            elif lg:
                pill = "taken"
            elif not due:
                pill = "not_today"
            elif day < today:
                pill = "missed"
            else:
                pill = "upcoming"
            for d in week:
                if (d < today and is_due(d)) or (d == today and (it.id, d) in took):
                    s_due += 1
                    s_done += (it.id, d) in took
            st = stocks.get(it.id)
            g = SUPP_GROUPS.get(it.timing, SUPP_GROUPS["any"])
            supps.append({"id": it.id, "plan": sa.plan.name, "plan_since": sa.start_date,
                          "by": sa.assigned_by.full_name if sa.assigned_by else None, "name": it.name,
                          "dose": it.dose, "how": it.how, "timing": it.timing, "with_food": it.with_food,
                          "group": g[0], "group_name": g[1], "group_line": g[2],
                          "due": due, "taken": bool(lg), "taken_at": lg.taken_at if lg else None, "pill": pill,
                          "stock": {"quantity": st.quantity, "unit": st.unit} if st else None,
                          "last_7": [(it.id, start + timedelta(days=i)) in took for i in range(7)],
                          "week": [_cell((it.id, d) in took, d, today, is_due(d)) for d in week]})
    return {"date": day, "strip": strip, "habits": habits, "supplements": supps,
            "week": {"start": ws, "end": week[-1], "days": days,
                     "habits_done": h_done, "habits_due": h_due, "supps_taken": s_done, "supps_due": s_due,
                     "best_streak": {"name": best[0], "days": best[1]} if best[0] else None}}


class ClientHabitsView(APIView):
    """Client profile → Logs → Habits / Supplements (staff, read only)."""

    permission_classes = [IsStaff]

    def get(self, request, client_pk):
        try:
            client = get_visible_client(request.user, client_pk)
        except Exception:
            from django.http import Http404

            raise Http404
        kind = request.query_params.get("kind")
        if kind in ("habits", "supps"):
            return Response(staff_log(client, kind, request.query_params))
        day = parse_date(request.query_params.get("date") or "") or timezone.localdate()
        return Response(habits_day(client, day))


def _clock(t):
    return dfmt(timezone.localtime(t), "%-I:%M %p").lower() if t else ""


def staff_log(client, kind, params):
    """Client profile → Logs → Habits / Supplements: one column per habit (or supplement), one row per day of
    the range, newest first. Each cell is true (done), false (not done) or null (not due that day); each row
    also carries the drawer's list (name, what was logged, when it was ticked)."""
    from apps.clients.logs import days_desc, page_of
    from apps.clients.metrics import resolve_range

    start, end = resolve_range(params, client)
    days = days_desc(start, end, client)
    today = timezone.localdate()
    cols = []  # (key, name, sub(log), due(d), done(d), when(d))
    if kind == "habits":
        assigns = list(HabitAssignment.objects.filter(client=client, active=True).select_related("habit")
                       .order_by("created_at"))
        logs = {(lg.habit_id, lg.date): lg for lg in HabitLog.objects.filter(
            client=client, date__range=(start, end), habit__in=[a.habit for a in assigns])}
        for a in assigns:
            h = a.eff

            def sub(lg, h=h):
                if lg is None or not lg.value:
                    return ""
                if h.unit.strip().lower() == "min" and lg.value >= 60:
                    return f"{lg.value // 60} h {lg.value % 60} min" if lg.value % 60 else f"{lg.value // 60} h"
                return f"{lg.value:,} {h.unit}".strip()

            cols.append((str(h.id), h.name,
                         lambda d, h=h, a=a: d >= a.start_date and h.is_due_on(d),
                         lambda d, h=h: logs.get((h.id, d)),
                         lambda lg: bool(lg and lg.done), sub, lambda lg: _clock(lg.updated_at) if lg else ""))
    else:
        for sa in (SupplementAssignment.objects.filter(client=client, active=True)
                   .select_related("plan", "custom_plan").order_by("created_at")):
            took = {(lg.item_id, lg.date): lg for lg in SupplementLog.objects.filter(
                client=client, item__plan=sa.followed, date__range=(start, end))}
            for it in sa.followed.items.all():
                line = " · ".join(x for x in (it.dose, it.get_timing_display().lower() if it.timing != "any" else "")
                                  if x)
                cols.append((str(it.id), it.name,
                             lambda d, it=it, sa=sa: d >= sa.start_date and (not it.days or d.weekday() in it.days),
                             lambda d, it=it, took=took: took.get((it.id, d)),
                             lambda lg: lg is not None, lambda lg, line=line: line,
                             lambda lg: _clock(lg.taken_at) if lg else ""))
    rows = []
    for d in days:
        cells, items = {}, []
        for key, name, due, get, ok, sub, when in cols:
            lg = get(d)
            if not due(d) and not ok(lg):
                cells[key] = None
                continue
            cells[key] = ok(lg)
            items.append({"id": key, "name": name, "sub": sub(lg), "done": ok(lg),
                          "when": when(lg) if ok(lg) else ("Not yet" if d == today else "Not ticked")})
        rows.append({"date": d, "cells": cells, "done": sum(1 for i in items if i["done"]), "due": len(items),
                     "items": items})
    out = page_of(rows, params)
    out["columns"] = [{"id": c[0], "name": c[1]} for c in cols]
    return out


# ---------------------------------------------------------------- client app
class MyHabitsView(APIView):
    """Habits & supplements page (?date=): the day, its Mon–Sun week grid (`week`), start dates, supplement groups."""

    permission_classes = [IsClient]

    def get(self, request):
        day = parse_date(request.query_params.get("date") or "") or timezone.localdate()
        return Response(habits_day(request.user, day))


class MyHabitLogView(APIView):
    """POST {value} for a counter (steps / glasses / minutes) or {done} for a tick."""

    permission_classes = [IsClient]

    def post(self, request, habit_id):
        a = get_object_or_404(HabitAssignment, habit_id=habit_id, client=request.user, active=True)
        h = a.eff  # this client's target
        day = parse_date(request.data.get("date") or "") or timezone.localdate()
        today = timezone.localdate()
        if day > today or day < today - timedelta(days=7):
            raise serializers.ValidationError("You can log today or the last 7 days.")
        log, _ = HabitLog.objects.get_or_create(habit=h, client=request.user, date=day)
        if h.kind == Habit.Kind.COUNTER:
            try:
                if "add" in request.data:
                    log.value = max(0, log.value + int(request.data["add"]))
                else:
                    log.value = max(0, int(request.data.get("value", 0)))
            except (TypeError, ValueError):
                raise serializers.ValidationError({"value": ["Enter a number."]})
            if log.value > 200000:
                raise serializers.ValidationError({"value": ["That number is too big."]})
            log.done = bool(h.target) and log.value >= h.target
        else:
            log.done = bool(request.data.get("done", True))
            if "value" in request.data:
                try:
                    log.value = max(0, int(request.data["value"]))
                except (TypeError, ValueError):
                    pass
        log.save()
        if log.done:
            from apps.automations.engine import response_received

            transaction.on_commit(lambda: response_received(request.user))
        return Response({"value": log.value, "done": log.done, "target": h.target})


def _ran_out(client, item):
    """Stock history: every time a supplement runs out at home (Compare plans → "Ran out of stock")."""
    activity_log("ran out of", "plan", actor=client, target_label=item.name, client=client,
                 meta={"history": "stock_out", "item": item.name})


class MySupplementView(APIView):
    """POST take / untake (Undo), PATCH stock."""

    permission_classes = [IsClient]

    def _item(self, request, item_id):
        # Only a supplement of a plan the client takes now: their own copy, else the master.
        plans = [a.custom_plan_id or a.plan_id
                 for a in SupplementAssignment.objects.filter(client=request.user, active=True)]
        return get_object_or_404(SupplementItem, id=item_id, plan_id__in=plans)

    def post(self, request, item_id):
        it = self._item(request, item_id)
        day = parse_date(request.data.get("date") or "") or timezone.localdate()
        today = timezone.localdate()
        if day > today or day < today - timedelta(days=7):
            raise serializers.ValidationError("You can log today or the last 7 days.")
        stock = SupplementStock.objects.filter(item=it, client=request.user).first()
        if request.data.get("taken", True):
            _, created = SupplementLog.objects.get_or_create(item=it, client=request.user, date=day)
            if created and stock and stock.quantity > 0:
                stock.quantity -= 1
                stock.save(update_fields=["quantity"])
                if stock.quantity == 0:
                    _ran_out(request.user, it)
        else:
            deleted, _ = SupplementLog.objects.filter(item=it, client=request.user, date=day).delete()
            if deleted and stock:
                stock.quantity += 1
                stock.save(update_fields=["quantity"])
        return Response({"taken": bool(request.data.get("taken", True)),
                         "stock": {"quantity": stock.quantity, "unit": stock.unit} if stock else None})

    def patch(self, request, item_id):
        it = self._item(request, item_id)
        try:
            q = int(request.data.get("quantity"))
        except (TypeError, ValueError):
            raise serializers.ValidationError({"quantity": ["Enter a number."]})
        if not 0 <= q <= 10000:
            raise serializers.ValidationError({"quantity": ["Check this number."]})
        had = SupplementStock.objects.filter(item=it, client=request.user).values_list("quantity", flat=True).first()
        st, _ = SupplementStock.objects.update_or_create(
            item=it, client=request.user,
            defaults={"quantity": q, "unit": (request.data.get("unit") or "scoops")[:20]})
        if q == 0 and had:
            _ran_out(request.user, it)
        return Response({"quantity": st.quantity, "unit": st.unit})
