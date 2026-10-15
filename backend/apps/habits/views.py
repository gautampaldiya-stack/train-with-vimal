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
from .serializers import QUICK_ADD, HabitSerializer, SupplementPlanSerializer


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
    if added:
        from django.contrib.auth import get_user_model

        clients = list(get_user_model().objects.filter(id__in=added))
        notify(clients, "plan_assigned", f"New in your plan: {label}", "", actor=actor, data={"route": "/habits"})
    return len(added), len(removed)


def _assign_options(request, model, field, obj):
    on = set(model.objects.filter(**{field: obj}, active=True).values_list("client_id", flat=True))
    rows = visible_clients(request.user).filter(status__in=["active", "paused"]).select_related(
        "client_profile__trainer")
    return [{"id": str(u.id), "full_name": u.full_name, "initials": u.initials, "avatar_color": u.avatar_color,
             "goal": u.client_profile.get_goal_display(), "on_it": u.id in on} for u in rows]


class _StaffWrite:
    def check_permissions(self, request):
        super().check_permissions(request)
        u = request.user
        if u.is_trainer and request.method not in ("GET", "HEAD", "OPTIONS"):
            if self.action == "assign":
                key = self.assign_permission
            else:
                key = "training.edit_templates"
            if not u.trainer_profile.has_perm(key):
                raise PermissionDenied("Your access does not include this. Ask Vimal for more access.")


class HabitViewSet(_StaffWrite, SoftDeleteViewMixin, viewsets.ModelViewSet):
    serializer_class = HabitSerializer
    permission_classes = [IsStaff]
    assign_permission = "nutrition.meal_plans"
    search_fields = ["name"]
    pagination_class = None
    http_method_names = ["get", "post", "patch", "delete"]

    def get_queryset(self):
        return Habit.objects.annotate(n_clients=Count("assignments", filter=Q(assignments__active=True)))

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
        return SupplementPlan.objects.annotate(
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
        h = a.habit
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
            **HabitSerializer(h).data, "assignment": a.id,
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
        due = [a.habit for a in assigns if a.habit.is_due_on(d) and d >= a.start_date]
        done = sum(1 for h in due if done_on(h, d))
        strip.append({"date": d, "today": d == today, "future": d > today,
                      "state": "none" if d > today or not due else ("done" if done == len(due) else
                                                                    ("today" if d == today else "missed"))})
    days = []
    for d in week:
        due = [a.habit for a in assigns if a.habit.is_due_on(d) and d >= a.start_date]
        n = sum(1 for h in due if done_on(h, d))
        days.append({"date": d, "today": d == today, "future": d > today,
                     "state": "coming" if d > today else "none" if not due else "done" if n == len(due)
                     else "today" if d == today else "part" if n else "missed"})
    supps = []
    s_done = s_due = 0
    for sa in SupplementAssignment.objects.filter(client=client, active=True).select_related("plan",
                                                                                              "assigned_by"):
        took = {(lg.item_id, lg.date): lg for lg in SupplementLog.objects.filter(
            client=client, item__plan=sa.plan, date__range=(min(start, ws), max(day, week[-1])))}
        stocks = {s.item_id: s for s in SupplementStock.objects.filter(client=client, item__plan=sa.plan)}
        for it in sa.plan.items.all():
            is_due = lambda d: d >= sa.start_date and (not it.days or d.weekday() in it.days)  # noqa: E731
            due = not it.days or day.weekday() in it.days
            lg = took.get((it.id, day))
            if day < sa.start_date:
                pill = f"Starts {sa.start_date:%a, %-d %b}"
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
        day = parse_date(request.query_params.get("date") or "") or timezone.localdate()
        return Response(habits_day(client, day))


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
        h = a.habit
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


class MySupplementView(APIView):
    """POST take / untake (Undo), PATCH stock."""

    permission_classes = [IsClient]

    def _item(self, request, item_id):
        return get_object_or_404(SupplementItem, id=item_id, plan__assignments__client=request.user,
                                 plan__assignments__active=True)

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
        st, _ = SupplementStock.objects.update_or_create(
            item=it, client=request.user,
            defaults={"quantity": q, "unit": (request.data.get("unit") or "scoops")[:20]})
        return Response({"quantity": st.quantity, "unit": st.unit})
