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
from apps.checkins.queue import review_queue
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


def _names(names, more=0):
    """"Ishaan and Rohit", "Ishaan, Rohit and Pooja", "Ishaan, Rohit and 3 more"."""
    names = [n for n in names if n]
    if more:
        return f"{', '.join(names)} and {more} more"
    return names[0] if len(names) == 1 else f"{', '.join(names[:-1])} and {names[-1]}"


def _ago(t, now):
    d = (now - t).days
    return "today" if d < 1 else ("1 day" if d == 1 else f"{d} days")


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
        first = [a.client.first_name for a in waiting.select_related("client")[:2]]
        sub = f"{_names(first, max(n - 2, 0))} {'is' if n == 1 else 'are'} waiting · oldest {_ago(oldest, now)}"
        rows.append({"key": f"approvals:{n}:{oldest.date()}", "kind": "approvals", "since": oldest,
                     "title": f"{n} sign-up{'s' if n != 1 else ''} waiting", "sub": sub.replace("oldest today", "since today"),
                     "cta": "Review", "route": "/approvals"})
    late = Submission.objects.filter(reviewed_at__isnull=True, form_type="weekly",
                                     created_at__lt=now - timedelta(hours=48)).order_by("created_at")
    n = late.count()
    if n:
        per = late.values("client__client_profile__trainer__full_name").annotate(c=Count("id")).order_by("-c")
        sub = " · ".join(f"{r['client__client_profile__trainer__full_name'] or 'No trainer'} ({r['c']})" for r in per[:3])
        rows.append({"key": f"checkins48:{n}:{late.first().created_at.date()}", "kind": "checkins",
                     "since": late.first().created_at, "title": f"{n} check-in{'s' if n != 1 else ''} waiting over 48 hours",
                     "sub": sub, "cta": "Open", "route": "/checkins"})
    no_trainer = ClientProfile.objects.filter(trainer__isnull=True, removed_at__isnull=True,
                                              user__status=AccountStatus.ACTIVE)
    n = no_trainer.count()
    if n:
        first = no_trainer.order_by("created_at").first()
        rows.append({"key": f"notrainer:{n}", "kind": "clients", "since": first.created_at,
                     "title": f"{n} client{'s' if n != 1 else ''} need{'s' if n == 1 else ''} a trainer",
                     "sub": f"Joined {_ago(first.created_at, now)} ago · not assigned yet".replace("Joined today ago",
                                                                                                 "Joined today"),
                     "cta": "Assign", "route": "/clients?badge=no_trainer"})
    for t in trainers_queryset().filter(status=AccountStatus.ACTIVE, n_clients__gt=F("trainer_profile__max_clients")):
        rows.append({"key": f"over:{t.id}:{t.n_clients}", "kind": "trainers", "since": None,
                     "title": f"{t.full_name} is over capacity",
                     "sub": f"{t.n_clients} of {t.trainer_profile.max_clients} clients · move "
                            f"{t.n_clients - t.trainer_profile.max_clients} to another trainer",
                     "cta": "Rebalance", "route": f"/trainers/{t.id}"})
    ending = ProgramAssignment.objects.filter(status="active", end_date__range=(today, today + timedelta(days=7)))
    n = ending.count()
    if n:
        who = [a.client.full_name for a in ending.select_related("client")[:2]]
        rows.append({"key": f"ending:{today.isocalendar()[1]}:{n}", "kind": "programs", "since": None,
                     "title": f"{n} program{'s' if n != 1 else ''} end{'s' if n == 1 else ''} this week",
                     "sub": " · ".join(who + ([f"{n - 2} more"] if n > 2 else [])) + " · pick what comes next",
                     "cta": "Plan", "route": "/clients?plan=ending"})
    low = Submission.objects.filter(created_at__gte=now - timedelta(days=3), metrics__energy__lte=2) \
        .select_related("client__client_profile__trainer")[:3]
    for s in low:
        coach = getattr(getattr(s.client, "client_profile", None), "trainer", None)
        rows.append({"key": f"low:{s.id}", "kind": "clients", "since": s.created_at,
                     "title": f"{s.client.full_name} flagged low energy",
                     "sub": f"Energy {s.metrics.get('energy')}/5 in the {s.form_type} check-in"
                            + (f" · {coach.full_name}" if coach else ""),
                     "cta": "View", "route": f"/clients/{s.client_id}"})
    inactive = ClientProfile.objects.filter(removed_at__isnull=True, user__status=AccountStatus.ACTIVE,
                                            user__last_seen_at__lt=now - timedelta(days=7)).count()
    if inactive:
        rows.append({"key": f"inactive:{today}:{inactive}", "kind": "clients", "since": None,
                     "title": f"{inactive} client{'s' if inactive != 1 else ''} {'has' if inactive == 1 else 'have'} "
                              f"not logged in 7 days",
                     "sub": "Remind them or check with their trainer", "cta": "View",
                     "route": "/clients?badge=at_risk"})
    for r in AccessRequest.objects.filter(status="open").select_related("trainer__user"):
        rows.append({"key": f"access:{r.id}", "kind": "trainers", "since": r.created_at,
                     "title": f"{r.trainer.user.full_name} asked for more access",
                     "sub": "Approve it or say no on their profile", "cta": "Review",
                     "route": f"/trainers/{r.trainer.user_id}?tab=access"})
    for t in TrainerTask.objects.filter(assignee=user, done_at__isnull=True)[:5]:
        rows.append({"key": f"task:{t.id}", "kind": "clients", "since": t.created_at, "title": t.title,
                     "sub": "Task for you", "cta": "Open", "route": f"/clients/{t.client_id}" if t.client_id else "/"})
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
        to_review = review_queue(request.user)  # same list the trainers and the Check-ins page count
        onboarding_pending = [cp for cp in active.only("onboarding_done") if
                              len(cp.onboarding_done or []) < 5]
        no_meal = active.exclude(user__meal_plan_assignments__status="active").count()
        ending = ProgramAssignment.objects.filter(status="active",
                                                  end_date__range=(today, today + timedelta(days=7))).count()
        # Trainer performance "This week" / "This month": the clients' 7-day or 30-day adherence.
        month = request.query_params.get("period") == "month"
        a30 = dict(ClientProfile.objects.filter(user__status=AccountStatus.ACTIVE, removed_at__isnull=True,
                                                trainer__isnull=False).order_by().values("trainer")
                   .annotate(a=Avg("adherence_30d")).values_list("trainer", "a")) if month else {}
        perf = []
        for t in trainers:
            if t.status != AccountStatus.ACTIVE:
                continue
            st = trainer_stats(t)
            perf.append({**_person(t), "clients": t.n_clients, "max_clients": t.trainer_profile.max_clients,
                         "adherence": (lambda a: round(a) if a is not None else None)(
                             a30.get(t.id) if month else t.avg_adherence),
                         "reply_hours": st["reply_hours"]})
        perf.sort(key=lambda r: (r["adherence"] is None, r["adherence"] or 0))
        at_risk = active.filter(at_risk=True).select_related("user", "trainer").order_by("-updated_at")
        recent = ActivityEvent.objects.select_related("client").order_by("-created_at")[:5]
        actions = needs_action(request.user)
        from .trainer_home import notices

        nts = notices(request.user)
        local = timezone.localtime(now)
        n = len(actions)
        return Response({
            "greeting": _greeting(request.user),
            "date": today,
            "things_need_you": n,
            "subline": f"{local:%A}, {local.day} {local:%B} · "
                       + (f"{n} thing{'s' * (n != 1)} need{'s' * (n == 1)} you today" if n else "Nothing needs you today"),
            "notices": nts,
            "unread": sum(1 for x in nts if not x["read"]),
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
                "onboarding_pending": {"value": len(onboarding_pending), "forms_missing": sum(
                    1 for cp in onboarding_pending if "health" not in (cp.onboarding_done or []))},
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
    """Trainer dashboard: stats, Today, Clients who need you, Check-ins to review, This week, bell list."""

    permission_classes = [IsStaff]

    def get(self, request):
        from .trainer_home import trainer_home

        return Response(trainer_home(request.user))


class TrainerActivityView(APIView):
    """Next page of the dashboard's Activity card: `?before=<next>` from the previous page."""

    permission_classes = [IsStaff]

    def get(self, request):
        from .trainer_home import activity

        return Response(activity(request.user, before=request.query_params.get("before", "")))


# ---------------------------------------------------------------- client home
def _fmt_kg(v):
    return f"{v:g}" if v is not None else ""


def _ex_line(pe):
    """'4 × 6–8 · 42.5 kg' / '35 min · incline 10%' — the line under an exercise on Home."""
    reps = pe.reps or ""
    line = f"{pe.sets} × {reps}" if pe.exercise.log_type != "time" else f"{pe.sets} × {reps}"
    if pe.target_weight_kg:
        line += f" · {_fmt_kg(float(pe.target_weight_kg))} kg"
    return line


def _day_minutes(exercises):
    """Rough session length: each set about 45 s of work plus its rest, rounded to 5 minutes."""
    secs = sum(pe.sets * (45 + pe.rest_seconds) for pe in exercises)
    return max(10, int(round(secs / 60 / 5.0)) * 5) if exercises else 0


def home_week(client, today, pa):
    """Home week strip: Mon–Sun with each day's planned workout, so a tap shows that day."""
    from apps.clients.metrics import program_day_for
    from apps.training.models import WorkoutLog

    monday = today - timedelta(days=today.weekday())
    logs = {}
    for w in (WorkoutLog.objects.filter(client=client, date__range=(monday, monday + timedelta(days=6)))
              .exclude(status="discarded").prefetch_related("sets").order_by("date", "-started_at")):
        logs.setdefault(w.date, w)
    out = []
    for i in range(7):
        d = monday + timedelta(days=i)
        pd = program_day_for(pa, d)
        exs = list(pd.exercises.select_related("exercise").order_by("order")) if pd and not pd.is_rest else []
        w = logs.get(d)
        done_ex = len({s.program_exercise_id or s.exercise_id for s in w.sets.all() if s.done}) if w else 0
        completed = bool(w and w.status == WorkoutLog.Status.COMPLETED)
        cardio = bool(exs) and exs[0].exercise.muscle_group == "cardio"
        out.append({
            "date": d, "today": d == today, "is_rest": not exs, "name": pd.name if pd and exs else "",
            "rest_note": pd.rest_note if pd and pd.is_rest else "",
            "kind": "cardio" if cardio else "strength", "minutes": _day_minutes(exs),
            "exercises": [{"id": pe.id, "name": pe.exercise.name, "line": _ex_line(pe)} for pe in exs],
            "done": completed, "in_progress": bool(w) and not completed, "exercises_done": done_ex,
            "done_line": (f"Done · {round(w.duration_seconds / 60)} min · {min(done_ex, len(exs))} of {len(exs)} exercises"
                          if completed else ""),
        })
    return out


# Client Home cards that "Edit home" can order or remove (D-87). Habits, Supplements and Coming up stay fixed.
HOME_CARDS = ["workout", "checkin", "food", "progress", "adherence", "water", "rest_timer"]


def home_layout(cp):
    """The client's card order: their saved one (unknown ids dropped), else every card in the default order."""
    saved = [k for k in (cp.home_layout or []) if k in HOME_CARDS]
    return saved if cp.home_layout else list(HOME_CARDS)


def checkin_today(client, today):
    """Home Check-in card: today's daily check-in, pending or sent; None when there is no daily form."""
    from apps.checkins.models import Form, Question, Submission

    form = Form.objects.filter(type="daily", status="published").first()
    if not form:
        return None
    sub = Submission.objects.filter(client=client, form_type="daily", date=today).order_by("-created_at").first()
    return {"form": form.id, "status": "sent" if sub else "pending", "sent_at": sub.created_at if sub else None,
            "questions": Question.objects.filter(form=form, is_removed=False).count(), "due": "9:00 pm"}


def adherence_week(client, today):
    """Home Weekly adherence: daily check-ins sent Monday to today ("4 of 6 days")."""
    from apps.checkins.models import Submission

    monday = today - timedelta(days=today.weekday())
    done = (Submission.objects.filter(client=client, form_type="daily", date__range=(monday, today))
            .values("date").distinct().count())
    return {"done": done, "days": today.weekday() + 1}


def progress_summary(client):
    """Home Progress summary since the start: weight, body fat, best lift and muscle mass (only when measured).
    Same numbers as the Progress page (`progress_page`)."""
    from apps.checkins.models import Measurement
    from apps.checkins.progress import _lifts, progress_page_weights

    start, now = progress_page_weights(client)
    out = {"weight": None, "body_fat": None, "strength": None, "muscle": None}
    if now is not None:
        out["weight"] = {"now": now, "change": round(now - start, 1) if start is not None else None}
    ms = list(Measurement.objects.filter(client=client).order_by("date").values_list("values", flat=True))
    for key, name in (("body_fat", "body_fat"), ("muscle_mass", "muscle")):
        vals = [float(v[key]) for v in ms if v.get(key) is not None]
        if vals:
            out[name] = {"now": vals[-1], "change": round(vals[-1] - vals[0], 1)}
    lift = next(iter(_lifts(client, limit=1)), None)
    if lift:
        out["strength"] = {"name": lift["name"], "now": lift["best"]["kg"],
                           "change": round(lift["best"]["kg"] - lift["started"]["kg"], 1)}
    return out


class HomeLayoutView(APIView):
    """Edit home → Done: `PATCH me/home/layout/ {"layout": [...]}` saves the card order (an empty list = default)."""

    permission_classes = [IsClient]

    def patch(self, request):
        layout = request.data.get("layout")
        if not isinstance(layout, list) or any(not isinstance(k, str) for k in layout):
            raise serializers.ValidationError({"layout": ["Send the card ids as a list."]})
        bad = [k for k in layout if k not in HOME_CARDS]
        if bad:
            raise serializers.ValidationError({"layout": [f"Unknown card: {', '.join(bad)}."]})
        cp = request.user.client_profile
        cp.home_layout = list(dict.fromkeys(layout))
        cp.save(update_fields=["home_layout", "updated_at"])
        return Response({"layout": home_layout(cp)})


class ClientHomeView(APIView):
    permission_classes = [IsClient]

    def get(self, request):
        from apps.checkins.models import Form, Question, Submission
        from apps.habits.models import HabitAssignment
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
        later = {a.habit_id: a.start_date for a in HabitAssignment.objects.filter(client=u, active=True,
                                                                                     start_date__gt=today)}
        habits = [h for h in hab["habits"] if h["id"] not in later and str(h["id"]) not in map(str, later)]
        soon = [{"name": a.habit.name, "starts": a.start_date} for a in
                HabitAssignment.objects.filter(client=u, active=True, start_date__gt=today)
                .select_related("habit").order_by("start_date")]
        session = (Session.objects.filter(client=u, start__gte=now - timedelta(hours=1), status="booked")
                   .select_related("trainer").order_by("start").first())

        weekly = Form.objects.filter(type="weekly", status="published").first()
        last_weekly = Submission.objects.filter(client=u, form_type="weekly").order_by("-date").first()
        coming = []
        if session:
            mins = round((session.end - session.start).total_seconds() / 60)
            coming.append({"kind": "session", "title": f"Session with {session.trainer.first_name}",
                           "date": session.start, "place": session.place, "minutes": mins, "id": str(session.id)})
        if weekly:
            due = (last_weekly.date + timedelta(days=7)) if last_weekly else today
            qs = Question.objects.filter(form=weekly, is_removed=False)
            # Photos only in the weeks they are due ("photos every N weeks").
            from apps.checkins.services import photo_week

            photos = qs.filter(type="photo").count() if photo_week(u, max(due, today)) else 0
            coming.append({"kind": "checkin", "title": "Weekly check-in", "date": max(due, today),
                           "questions": qs.exclude(type="photo").count(), "photos": photos})
        if pa:
            prog = pa.effective_program
            ends = pa.end_date or (pa.start_date + timedelta(weeks=prog.weeks) - timedelta(days=1))
            coming.append({"kind": "plan_end", "title": f"{prog.name} ends", "date": ends})
        cp = u.client_profile
        notices = Notification.objects.filter(recipient=u, in_app=True).order_by("-created_at")[:5]
        reply = (Submission.objects.filter(client=u).exclude(reply="").filter(reviewed_at__isnull=False)
                 .select_related("reviewed_by").order_by("-reviewed_at").first())
        meals = [{"id": m["id"], "name": m["name"], "time": m["time"], "pill": m["pill"],
                  "opens_at": m.get("opens_at"),
                  "foods": ", ".join(x["name"] for x in m.get("items", [])), "kcal": m.get("kcal", 0),
                  **{k: round(sum(x[k] for x in m.get("items", [])), 1) for k in ("protein", "carbs", "fat")}}
                 for m in day["meals"]]
        return Response({
            "date": today,
            "week": week, "weeks": pa.effective_program.weeks if pa else None,
            "first_name": u.first_name, "initials": u.initials, "avatar_color": u.avatar_color,
            "goal": cp.get_goal_display() if cp.goal else "",
            "strip": home_week(u, today, pa),
            "workout": {"day": {"id": pd.id, "name": pd.name, "is_rest": pd.is_rest, "rest_note": pd.rest_note}
                        if pd else None, "exercises": exercises, "program": pa.effective_program.name if pa else None},
            "session": {"id": str(session.id), "kind": session.get_kind_display(), "start": session.start,
                        "end": session.end, "trainer": _person(session.trainer), "place": session.place,
                        "is_call": session.is_call, "call_link": session.call_link} if session else None,
            "water": day["water"],
            "next_meal": next_meal,
            "meals": meals,
            "macros_target": day["plan"],
            "eaten": day["macros"],
            "habits": habits,
            "habits_soon": soon,
            "supplements": hab["supplements"],
            "coming_up": coming,
            "notices": [{"id": str(n.id), "title": n.title, "body": n.body, "created_at": n.created_at,
                         "read": n.read_at is not None, "event": n.event, "data": n.data} for n in notices],
            "unread": Notification.objects.filter(recipient=u, in_app=True, read_at__isnull=True).count(),
            "trainer": _person(cp.trainer) if cp.trainer else None,
            "layout": home_layout(cp),
            "checkin_today": checkin_today(u, today),
            "adherence_week": adherence_week(u, today),
            "progress_summary": progress_summary(u),
            "trainer_note": {"by": _person(reply.reviewed_by) if reply.reviewed_by else None, "body": reply.reply,
                             "at": reply.reviewed_at} if reply else None,
        })
