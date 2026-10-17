"""Client profile → header stats and Overview tab, built in one request."""
from datetime import timedelta

from django.utils import timezone

from . import metrics
from .models import ClientNote


def _f(v):
    return float(v) if v is not None else None


def client_stats(user):
    """The 4 stat cards: adherence, current weight, workouts (30 days), check-ins."""
    from apps.checkins.models import Submission, WeightLog

    cp = user.client_profile
    today = timezone.localdate()
    last = WeightLog.objects.filter(client=user).order_by("-date").first()
    current = _f(last.weight_kg) if last else _f(cp.current_weight_kg)
    start_w = _f(cp.start_weight_kg)
    c30 = metrics.counts_between(user, today - timedelta(days=29), today)
    weekly = Submission.objects.filter(client=user, form_type="weekly")
    waiting = weekly.filter(reviewed_at__isnull=True).order_by("-created_at").first()
    return {
        "adherence": cp.adherence_7d,
        "adherence_change": (cp.adherence_7d - cp.adherence_30d)
        if cp.adherence_7d is not None and cp.adherence_30d is not None else None,
        "weight": current,
        "weight_change": round(current - start_w, 1) if current is not None and start_w is not None else None,
        "target_weight": _f(cp.target_weight_kg),
        "workouts_done": c30["workouts_done"],
        "workouts_planned": c30["workouts_planned"],
        "checkins_sent": weekly.count(),
        "checkins_reviewed": weekly.filter(reviewed_at__isnull=False).count(),
        "checkin_waiting": {"week": waiting.week_number, "id": str(waiting.id)} if waiting else None,
    }


def current_plans(user):
    from apps.habits.models import HabitAssignment, SupplementAssignment
    from apps.training.models import AssignmentStatus, ProgramAssignment

    today = timezone.localdate()
    out = {}
    pa = metrics.active_program(user)
    if pa:
        p = pa.effective_program
        week = (today - pa.start_date).days // 7 + 1
        out["workout"] = {"id": str(pa.id), "name": p.name, "week": min(week, p.weeks), "weeks": p.weeks,
                          "edited": pa.custom_program_id is not None, "program": str(p.id),
                          "master": str(pa.program_id), "start_date": pa.start_date}
    up_next = ProgramAssignment.objects.filter(client=user, status=AssignmentStatus.UP_NEXT).first()
    if up_next:
        out["workout_up_next"] = {"id": str(up_next.id), "name": up_next.program.name,
                                  "start_date": up_next.start_date}
    mp = metrics.active_meal_plan(user)
    if mp:
        out["meal_plan"] = {"id": str(mp.id), "name": mp.plan.name, "kcal": mp.plan.kcal_target,
                            "meals": mp.plan.meals.count(), "diet": mp.plan.get_diet_display(),
                            "edited": bool(mp.version_note), "plan": str(mp.plan_id)}
    sa = SupplementAssignment.objects.filter(client=user, active=True).select_related("plan").first()
    if sa:
        items = list(sa.plan.items.values_list("name", flat=True))
        out["supplements"] = {"id": str(sa.id), "name": sa.plan.name, "count": len(items), "items": items}
    habits = list(HabitAssignment.objects.filter(client=user, active=True).select_related("habit"))
    if habits:
        out["habits"] = {"count": len(habits), "items": [h.habit.name for h in habits]}
    return out


def client_overview(user, request):
    from apps.checkins.models import Form, FormRequest
    from apps.scheduling.models import Session

    from .onboarding import about_items

    cp = user.client_profile
    start, end = metrics.resolve_range(request.query_params, user)
    series = metrics.weight_series(user, start, end)
    change = round(series[-1]["kg"] - series[0]["kg"], 1) if len(series) >= 2 else None
    current = series[-1]["kg"] if series else _f(cp.current_weight_kg)
    to_goal = round(current - float(cp.target_weight_kg), 1) if current and cp.target_weight_kg else None
    note = ClientNote.objects.filter(client=user).select_related("author").first()
    nxt = (Session.objects.filter(client=user, start__gte=timezone.now(), status="booked")
           .select_related("trainer").order_by("start").first())
    weekly_form = Form.objects.filter(type="weekly", status="published").first()
    last_request = FormRequest.objects.filter(client=user).order_by("-created_at").first()
    t = cp.trainer
    return {
        "about": {
            "goal": cp.get_goal_display() if cp.goal else "",
            "target_weight": _f(cp.target_weight_kg),
            "height_cm": _f(cp.height_cm),
            "start_weight": _f(cp.start_weight_kg),
            "trainer": {"id": str(t.id), "full_name": t.full_name, "initials": t.initials,
                        "avatar_color": t.avatar_color} if t else None,
            "joined": user.date_joined.date(),
            "start_date": cp.start_date,
            "onboarding": cp.onboarding,
            "health_notes": cp.health_notes,
            # The About card: onboarding answers as the coach reads them (Edit profile changes them).
            "items": about_items(user),
            "package": {"name": cp.package_name, "ends_on": cp.package_ends_on} if cp.package_name else None,
        },
        "weight_trend": {"range": {"from": start, "to": end}, "points": series, "change": change,
                         "to_goal": to_goal, "goal": _f(cp.target_weight_kg)},
        "last_7_days": metrics.last_7_days(user),
        "latest_note": {"id": str(note.id), "body": note.body, "created_at": note.created_at,
                        "author": note.author.full_name if note.author else "",
                        "author_initials": note.author.initials if note.author else ""} if note else None,
        "needs_attention": metrics.needs_attention(user),
        "coaching": {
            "next_session": {"id": str(nxt.id), "kind": nxt.get_kind_display(), "start": nxt.start,
                             "trainer": nxt.trainer.full_name} if nxt else None,
        },
        "current_plans": current_plans(user),
        "checkins_schedule": {
            "weekly_form": weekly_form.name if weekly_form else None,
            "last_form_sent": {"form": last_request.form.name, "at": last_request.created_at,
                               "filled": bool(last_request.filled_at)} if last_request else None,
            **checkins_schedule(user),
        },
    }


def checkins_schedule(user):
    """Overview → "Check-ins and schedule": daily (reminder time, sent this week), weekly (Sunday; waiting for
    review / sent / due), measurements and photos (every N weeks, D-24). Same rules as the client's Check-ins page."""
    from apps.checkins.client_page import DAILY_REMINDER
    from apps.checkins.models import Measurement, PhotoSet, Submission
    from apps.checkins.services import measure_entry, next_measure_due, next_photos_due

    today = timezone.localdate()
    monday = today - timedelta(days=today.weekday())
    sunday = monday + timedelta(days=6)
    subs = Submission.objects.filter(client=user)
    daily = subs.filter(form_type="daily", date__range=(monday, today)).values("date").distinct().count()
    waiting = subs.filter(form_type="weekly", reviewed_at__isnull=True).order_by("-created_at").first()
    this_week = subs.filter(form_type="weekly", date__range=(monday, sunday)).exists()
    n = user.client_profile.photo_every_weeks or 1
    last_m = Measurement.objects.filter(client=user).order_by("-date").values_list("date", flat=True).first()
    last_p = (PhotoSet.objects.filter(client=user, photos__isnull=False).order_by("-date")
              .values_list("date", flat=True).first())
    return {
        "daily": {"time": DAILY_REMINDER, "sent": daily, "days": today.weekday() + 1},
        "weekly": {"next": sunday + timedelta(days=7) if this_week else sunday, "sent_this_week": this_week,
                   "waiting_week": waiting.week_number if waiting else None,
                   "waiting_id": str(waiting.id) if waiting else None},
        "measurements": {"every_weeks": n, "last": last_m, "next": next_measure_due(user, today),
                         "due": measure_entry(user, today) is None},
        "photos": {"every_weeks": n, "last": last_p, "next": next_photos_due(user, today)},
    }
