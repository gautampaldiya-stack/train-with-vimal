"""Admin dashboard, trainer dashboard and client Home — one request each."""
from datetime import timedelta

from django.contrib.auth import get_user_model
from django.db.models import Avg, Count, F, Q
from django.utils import timezone
from rest_framework import serializers
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import AccountStatus, Role
from apps.common.permissions import IsAdmin, IsClient, IsStaff

from .models import ActivityEvent, DismissedItem
from .serializers import ActivityEventSerializer

User = get_user_model()


def _person(u):
    return {"id": str(u.id), "full_name": u.full_name, "initials": u.initials, "avatar_color": u.avatar_color}


def _greeting(user):
    h = timezone.localtime().hour
    part = "morning" if h < 12 else ("afternoon" if h < 17 else "evening")
    return f"Good {part}, {user.first_name}"


def _delta(a, b):
    return None if a is None or b is None else round(a - b)


# ---------------------------------------------------------------- admin
def needs_action(user):
    from apps.automations.models import TrainerTask
    from apps.checkins.models import Submission
    from apps.clients.models import Approval, ClientProfile
    from apps.trainers.models import AccessRequest
    from apps.trainers.views import trainers_queryset
    from apps.training.models import ProgramAssignment

    now = timezone.now()
    today = timezone.localdate()
    rows = []
    waiting = Approval.objects.filter(status="waiting").order_by("created_at")
    n = waiting.count()
    if n:
        oldest = waiting.first().created_at
        rows.append({"key": f"approvals:{n}:{oldest.date()}", "kind": "approvals", "since": oldest,
                     "title": f"{n} sign-ups waiting", "cta": "Review", "route": "/approvals"})
    late = Submission.objects.filter(reviewed_at__isnull=True, form_type="weekly",
                                     created_at__lt=now - timedelta(hours=48)).order_by("created_at")
    n = late.count()
    if n:
        rows.append({"key": f"checkins48:{n}:{late.first().created_at.date()}", "kind": "checkins",
                     "since": late.first().created_at, "title": f"{n} check-ins waiting over 48 hours",
                     "cta": "Open", "route": "/checkins"})
    no_trainer = ClientProfile.objects.filter(trainer__isnull=True, removed_at__isnull=True,
                                              user__status=AccountStatus.ACTIVE)
    n = no_trainer.count()
    if n:
        rows.append({"key": f"notrainer:{n}", "kind": "clients", "since": no_trainer.order_by("created_at")
                     .first().created_at, "title": f"{n} clients need a trainer", "cta": "Assign",
                     "route": "/clients?badge=no_trainer"})
    for t in trainers_queryset().filter(status=AccountStatus.ACTIVE, n_clients__gt=F("trainer_profile__max_clients")):
        rows.append({"key": f"over:{t.id}:{t.n_clients}", "kind": "trainers", "since": None,
                     "title": f"{t.full_name} is over capacity ({t.n_clients} of {t.trainer_profile.max_clients})",
                     "cta": "Rebalance", "route": f"/trainers/{t.id}"})
    ending = ProgramAssignment.objects.filter(status="active", end_date__range=(today, today + timedelta(days=7)))
    n = ending.count()
    if n:
        rows.append({"key": f"ending:{today.isocalendar()[1]}:{n}", "kind": "programs", "since": None,
                     "title": f"{n} programs end this week", "cta": "Plan", "route": "/clients?plan=ending"})
    low = Submission.objects.filter(created_at__gte=now - timedelta(days=3), metrics__energy__lte=2) \
        .select_related("client")[:3]
    for s in low:
        rows.append({"key": f"low:{s.id}", "kind": "clients", "since": s.created_at,
                     "title": f"{s.client.full_name} flagged low energy", "cta": "View",
                     "route": f"/clients/{s.client_id}"})
    inactive = ClientProfile.objects.filter(removed_at__isnull=True, user__status=AccountStatus.ACTIVE,
                                            user__last_seen_at__lt=now - timedelta(days=7)).count()
    if inactive:
        rows.append({"key": f"inactive:{today}:{inactive}", "kind": "clients", "since": None,
                     "title": f"{inactive} clients have not logged in 7 days", "cta": "View",
                     "route": "/clients?badge=at_risk"})
    for r in AccessRequest.objects.filter(status="open").select_related("trainer__user"):
        rows.append({"key": f"access:{r.id}", "kind": "trainers", "since": r.created_at,
                     "title": f"{r.trainer.user.full_name} asked for more access", "cta": "Review",
                     "route": f"/trainers/{r.trainer.user_id}/access"})
    for t in TrainerTask.objects.filter(assignee=user, done_at__isnull=True)[:5]:
        rows.append({"key": f"task:{t.id}", "kind": "clients", "since": t.created_at, "title": t.title,
                     "cta": "Open", "route": f"/clients/{t.client_id}" if t.client_id else "/"})
    dismissed = set(DismissedItem.objects.filter(user=user).values_list("key", flat=True))
    rows = [r for r in rows if r["key"] not in dismissed]
    rows.sort(key=lambda r: (r["since"] is None, r["since"] or now))
    return rows


class AdminDashboardView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        from apps.checkins.models import Submission
        from apps.clients.models import Approval, ClientProfile
        from apps.nutrition.models import MealPlanAssignment
        from apps.trainers.views import trainer_stats, trainers_queryset
        from apps.training.models import ProgramAssignment

        now = timezone.now()
        today = timezone.localdate()
        month_start = today.replace(day=1)
        clients = ClientProfile.objects.filter(removed_at__isnull=True)
        active = clients.filter(user__status=AccountStatus.ACTIVE)
        n_active = active.count()
        waiting = Approval.objects.filter(status="waiting").order_by("created_at")
        sent_7 = Submission.objects.filter(form_type="weekly", created_at__gte=now - timedelta(days=7)) \
            .values("client").distinct().count()
        sent_14 = Submission.objects.filter(form_type="weekly", created_at__range=(now - timedelta(days=14),
                                                                                   now - timedelta(days=7))) \
            .values("client").distinct().count()
        rate = round(100 * sent_7 / n_active) if n_active else None
        rate_prev = round(100 * sent_14 / n_active) if n_active else None
        adh = active.aggregate(a7=Avg("adherence_7d"), a30=Avg("adherence_30d"))
        trainers = list(trainers_queryset())
        to_review = Submission.objects.filter(reviewed_at__isnull=True, form_type__in=["weekly", "daily"])
        onboarding_pending = [cp for cp in active.only("onboarding_done") if
                              len(cp.onboarding_done or []) < 5]
        no_meal = active.exclude(user__meal_plan_assignments__status="active").count()
        ending = ProgramAssignment.objects.filter(status="active",
                                                  end_date__range=(today, today + timedelta(days=7))).count()
        perf = []
        for t in trainers:
            if t.status != AccountStatus.ACTIVE:
                continue
            st = trainer_stats(t)
            perf.append({**_person(t), "clients": t.n_clients, "max_clients": t.trainer_profile.max_clients,
                         "adherence": round(t.avg_adherence) if t.avg_adherence is not None else None,
                         "reply_hours": st["reply_hours"]})
        perf.sort(key=lambda r: (r["adherence"] is None, r["adherence"] or 0))
        at_risk = active.filter(at_risk=True).select_related("user", "trainer").order_by("-updated_at")
        recent = ActivityEvent.objects.select_related("client").order_by("-created_at")[:5]
        actions = needs_action(request.user)
        return Response({
            "greeting": _greeting(request.user),
            "date": today,
            "things_need_you": len(actions),
            "stats": {
                "active_clients": {"value": n_active, "new_this_month": clients.filter(
                    user__date_joined__date__gte=month_start).count()},
                "pending_approvals": {"value": waiting.count(),
                                      "oldest_at": waiting.first().created_at if waiting.exists() else None},
                "checkin_rate": {"value": rate, "delta": _delta(rate, rate_prev)},
                "adherence": {"value": round(adh["a7"]) if adh["a7"] is not None else None,
                              "delta": _delta(adh["a7"], adh["a30"])},
            },
            "glance": {
                "clients": {"value": clients.count(), "active": n_active,
                            "paused": clients.filter(user__status=AccountStatus.PAUSED).count()},
                "trainers": {"value": len(trainers), "over_capacity": sum(
                    1 for t in trainers if t.n_clients > t.trainer_profile.max_clients)},
                "checkins_to_review": {"value": to_review.count(), "over_48h": to_review.filter(
                    created_at__lt=now - timedelta(hours=48)).count()},
                "onboarding_pending": {"value": len(onboarding_pending)},
                "nutrition_pending": {"value": no_meal},
                "programs_ending": {"value": ending},
            },
            "needs_action": actions,
            "trainer_performance": perf,
            "at_risk": {
                "count": at_risk.count(),
                "rows": [{**_person(cp.user), "reason": cp.at_risk_reason,
                          "trainer": cp.trainer.full_name if cp.trainer else None,
                          "reminded_at": cp.last_reminded_at} for cp in at_risk[:20]],
                "reminded_last_24h": at_risk.filter(last_reminded_at__gte=now - timedelta(hours=24)).count(),
            },
            "recent_activity": ActivityEventSerializer(recent, many=True).data,
        })


class DismissView(APIView):
    """× on a Needs action row."""

    permission_classes = [IsStaff]

    def post(self, request):
        key = str(request.data.get("key") or "")[:120]
        if not key:
            raise serializers.ValidationError({"key": ["Send the row key."]})
        DismissedItem.objects.get_or_create(user=request.user, key=key)
        return Response(status=204)


# ---------------------------------------------------------------- trainer
class TrainerDashboardView(APIView):
    permission_classes = [IsStaff]

    def get(self, request):
        from apps.automations.models import TrainerTask
        from apps.checkins.models import Submission
        from apps.checkins.serializers import SubmissionRowSerializer
        from apps.clients.models import ClientProfile
        from apps.notifications.models import Notification
        from apps.scheduling.models import Session
        from apps.scheduling.views import SessionSerializer
        from apps.trainers.views import trainer_stats
        from apps.training.models import ProgramAssignment

        u = request.user
        now = timezone.now()
        today = timezone.localdate()
        stats = trainer_stats(u)
        pending = Submission.objects.filter(client__client_profile__trainer=u, reviewed_at__isnull=True,
                                            form_type__in=["weekly", "daily"]).select_related("client", "form")
        tz = timezone.get_current_timezone()
        day_start = timezone.datetime.combine(today, timezone.datetime.min.time(), tz)
        sessions_today = Session.objects.filter(trainer=u, start__gte=day_start,
                                                start__lt=day_start + timedelta(days=1)).exclude(
            status="cancelled").select_related("client", "trainer")
        monday = today - timedelta(days=today.weekday())
        week = Session.objects.filter(trainer=u, start__gte=timezone.datetime.combine(monday,
                                                                                      timezone.datetime.min.time(), tz),
                                      start__lt=timezone.datetime.combine(monday + timedelta(days=7),
                                                                          timezone.datetime.min.time(), tz)) \
            .exclude(status="cancelled").select_related("client", "trainer")
        mine = ClientProfile.objects.filter(trainer=u, removed_at__isnull=True,
                                            user__status=AccountStatus.ACTIVE).select_related("user")
        need = []
        ending_ids = set(ProgramAssignment.objects.filter(
            client__client_profile__trainer=u, status="active",
            end_date__range=(today, today + timedelta(days=7))).values_list("client_id", flat=True))
        low_ids = set(Submission.objects.filter(client__client_profile__trainer=u,
                                                created_at__gte=now - timedelta(days=4))
                      .filter(Q(metrics__energy__lte=2) | Q(metrics__mood__lte=2)).values_list("client_id", flat=True))
        for cp in mine:
            seen = cp.user.last_seen_at
            if seen and seen < now - timedelta(days=7):
                need.append({**_person(cp.user), "kind": "not_logging",
                             "reason": f"No workout or meal logged in {(now - seen).days} days",
                             "reminded_at": cp.last_reminded_at})
            elif cp.at_risk and "Missed" in cp.at_risk_reason:
                need.append({**_person(cp.user), "kind": "missed_workouts", "reason": cp.at_risk_reason,
                             "reminded_at": cp.last_reminded_at})
            if cp.user_id in ending_ids:
                need.append({**_person(cp.user), "kind": "plan_ending", "reason": "Plan ends this week",
                             "reminded_at": None})
            if cp.user_id in low_ids:
                need.append({**_person(cp.user), "kind": "feeling_low", "reason": "Low energy or mood in check-in",
                             "reminded_at": None})
        notices = Notification.objects.filter(recipient=u, in_app=True).order_by("-created_at")[:6]
        return Response({
            "greeting": _greeting(u),
            "stats": {**stats, "over_48h": pending.filter(form_type="weekly",
                                                          created_at__lt=now - timedelta(hours=48)).count()},
            "today": SessionSerializer(sessions_today, many=True, context={"request": request}).data,
            "clients_who_need_you": need,
            "checkins_to_review": SubmissionRowSerializer(pending.order_by("created_at")[:10], many=True).data,
            "tasks": [{"id": str(t.id), "title": t.title, "detail": t.detail, "due_on": t.due_on,
                       "done": t.done_at is not None, "client": _person(t.client) if t.client else None}
                      for t in TrainerTask.objects.filter(assignee=u).filter(
                          Q(done_at__isnull=True) | Q(done_at__gte=now - timedelta(days=1)))
                      .select_related("client")[:20]],
            "this_week": SessionSerializer(week, many=True, context={"request": request}).data,
            "notices": [{"id": str(n.id), "title": n.title, "body": n.body, "created_at": n.created_at,
                         "read": n.read_at is not None, "data": n.data} for n in notices],
        })


# ---------------------------------------------------------------- client home
class ClientHomeView(APIView):
    permission_classes = [IsClient]

    def get(self, request):
        from apps.habits.views import habits_day
        from apps.notifications.models import Notification
        from apps.nutrition import services as food
        from apps.scheduling.models import Session
        from apps.training.serializers import ProgramExerciseSerializer
        from apps.training.services import today_plan

        u = request.user
        today = timezone.localdate()
        now = timezone.now()
        pa, pd, strip, week = today_plan(u, today)
        exercises = []
        if pd and not pd.is_rest:
            exercises = ProgramExerciseSerializer(pd.exercises.select_related("exercise"), many=True).data
        day = food.day_view(u, today)
        next_meal = next((m for m in day["meals"] if m["pill"] in ("next", "to_log")), None)
        hab = habits_day(u, today)
        session = (Session.objects.filter(client=u, start__gte=now - timedelta(hours=1), status="booked")
                   .select_related("trainer").order_by("start").first())
        from apps.checkins.models import Form, Submission

        weekly = Form.objects.filter(type="weekly", status="published").first()
        last_weekly = Submission.objects.filter(client=u, form_type="weekly").order_by("-date").first()
        coming = []
        if weekly:
            due = (last_weekly.date + timedelta(days=7)) if last_weekly else today
            coming.append({"kind": "checkin", "title": "Weekly check-in", "date": max(due, today)})
        if session:
            coming.append({"kind": "session", "title": f"{session.get_kind_display()} with "
                                                       f"{session.trainer.first_name}", "date": session.start})
        if pa:
            coming.append({"kind": "plan_week", "title": f"Week {min(week + 1, pa.effective_program.weeks)} of "
                                                         f"{pa.effective_program.name}",
                           "date": today + timedelta(days=7 - today.weekday())})
        cp = u.client_profile
        notices = Notification.objects.filter(recipient=u, in_app=True).order_by("-created_at")[:5]
        return Response({
            "date": today,
            "week": week, "weeks": pa.effective_program.weeks if pa else None,
            "first_name": u.first_name, "initials": u.initials, "avatar_color": u.avatar_color,
            "workout": {"day": {"id": pd.id, "name": pd.name, "is_rest": pd.is_rest, "rest_note": pd.rest_note}
                        if pd else None, "exercises": exercises, "program": pa.effective_program.name if pa else None},
            "session": {"id": str(session.id), "kind": session.get_kind_display(), "start": session.start,
                        "end": session.end, "trainer": _person(session.trainer), "place": session.place,
                        "is_call": session.is_call, "call_link": session.call_link} if session else None,
            "water": day["water"],
            "next_meal": next_meal,
            "macros_target": day["plan"],
            "eaten": day["macros"],
            "habits": hab["habits"],
            "supplements": hab["supplements"],
            "coming_up": coming,
            "notices": [{"id": str(n.id), "title": n.title, "body": n.body, "created_at": n.created_at,
                         "read": n.read_at is not None, "data": n.data} for n in notices],
            "trainer": _person(cp.trainer) if cp.trainer else None,
        })
