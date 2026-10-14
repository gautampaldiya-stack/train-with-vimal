"""Scheduled reminders (Celery beat). Each one is sent at most once per (person, kind, thing, day)
thanks to ReminderLog, so a slow or repeated beat never double-sends.

Times are local (settings.TIME_ZONE). Beat runs most of these every 15 minutes; each job looks at the
15-minute window that starts now.
"""
import logging
from datetime import datetime, timedelta

from celery import shared_task
from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.utils import timezone

from .models import ReminderLog, ReminderPreference, StaffNotificationPreference
from .services import notify, send_template

log = logging.getLogger("reminders")
User = get_user_model()
WINDOW = timedelta(minutes=15)


def once(user, kind, ref, day):
    """True the first time only."""
    try:
        with transaction.atomic():
            ReminderLog.objects.create(user=user, kind=kind, ref=str(ref)[:60], day=day)
        return True
    except IntegrityError:
        return False


def _prefs(user):
    p = getattr(user, "reminder_prefs", None)
    return p or ReminderPreference(user=user)


def _active_clients():
    return (User.objects.filter(role="client", status="active", is_active=True,
                                client_profile__removed_at__isnull=True)
            .select_related("client_profile", "reminder_prefs"))


def _local_now():
    return timezone.localtime()


# ---------------------------------------------------------------- workouts and sessions
@shared_task
def workout_reminders():
    """'1 hour before your session or planned workout'."""
    from apps.clients.metrics import active_program, program_day_for
    from apps.scheduling.models import Session

    now = timezone.now()
    sent = 0
    for s in Session.objects.filter(status="booked", reminder_sent_at__isnull=True,
                                    start__gte=now + timedelta(minutes=45), start__lt=now + timedelta(minutes=75)) \
            .select_related("client", "trainer"):
        if _prefs(s.client).workout:
            where = "on a call" if s.is_call else (s.place or "at the gym")
            notify(s.client, "session_reminder", f"{s.get_kind_display()} in 1 hour",
                   f"With {s.trainer.first_name} at {timezone.localtime(s.start):%-I:%M %p} · {where}",
                   data={"route": f"/sessions/{s.id}"})
            sent += 1
        s.reminder_sent_at = now
        s.save(update_fields=["reminder_sent_at"])
    local = _local_now()
    today = local.date()
    for c in _active_clients():
        p = _prefs(c)
        if not p.workout:
            continue
        at = timezone.make_aware(datetime.combine(today, p.workout_time)) - timedelta(hours=1)
        if not (at <= local < at + WINDOW):
            continue
        pd = program_day_for(active_program(c, today), today)
        if pd is None or pd.is_rest:
            continue
        if Session.objects.filter(client=c, start__date=today).exclude(status="cancelled").exists():
            continue  # the session reminder covers it
        if once(c, "workout", pd.id, today):
            notify(c, "workout_reminder", f"Today: {pd.name or 'your workout'}",
                   "Your workout is planned in an hour.", data={"route": "/train"})
            sent += 1
    return sent


# ---------------------------------------------------------------- meals
@shared_task
def meal_reminders():
    from apps.nutrition.models import MealDayState, MealPlanAssignment

    local = _local_now()
    today = local.date()
    sent = 0
    rows = (MealPlanAssignment.objects.filter(status="active", start_date__lte=today, client__status="active",
                                              plan__status="published")
            .select_related("client__reminder_prefs", "plan").prefetch_related("plan__meals"))
    for a in rows:
        if not _prefs(a.client).meal:
            continue
        for m in a.plan.meals.all():
            at = timezone.make_aware(datetime.combine(today, m.time))
            if not (at <= local < at + WINDOW):
                continue
            if MealDayState.objects.filter(client=a.client, date=today, meal=m, status__in=["logged", "skipped"]) \
                    .exists():
                continue
            if once(a.client, "meal", m.id, today):
                notify(a.client, "meal_reminder", f"{m.name} time", f"{m.kcal_target} kcal planned. Tap to log it.",
                       data={"route": "/food"})
                sent += 1
    return sent


# ---------------------------------------------------------------- check-ins
@shared_task
def checkin_reminders():
    """Weekly check-in due today (a week after the last one), at 9 am."""
    from apps.checkins.models import Submission

    local = _local_now()
    if not (local.hour == 9 and local.minute < 15):
        return 0
    today = local.date()
    sent = 0
    for c in _active_clients():
        if not _prefs(c).checkin:
            continue
        last = Submission.objects.filter(client=c, form_type="weekly").order_by("-date").first()
        start = c.client_profile.start_date or c.date_joined.date()
        due = (last.date + timedelta(days=7)) if last else start + timedelta(days=7)
        if due == today and once(c, "checkin", due, today):
            send_template(c, "checkin-reminder", data={"route": "/checkins"})
            sent += 1
    return sent


# ---------------------------------------------------------------- habits
@shared_task
def habit_reminders():
    """8 pm: habits due today and not done yet."""
    from apps.habits.models import HabitAssignment, HabitLog

    local = _local_now()
    if not (local.hour == 20 and local.minute < 15):
        return 0
    today = local.date()
    sent = 0
    for c in _active_clients():
        if not _prefs(c).habit:
            continue
        due = [a.habit for a in HabitAssignment.objects.filter(client=c, active=True).select_related("habit")
               if a.habit.is_due_on(today) and a.habit.frequency != "times_week"]
        done = set(HabitLog.objects.filter(client=c, date=today, done=True).values_list("habit_id", flat=True))
        left = [h for h in due if h.id not in done]
        if left and once(c, "habit", "evening", today):
            names = ", ".join(h.name for h in left[:2]) + (f" and {len(left) - 2} more" if len(left) > 2 else "")
            notify(c, "habit_reminder", "Habits left today", names, data={"route": "/habits"})
            sent += 1
    return sent


# ---------------------------------------------------------------- onboarding
@shared_task
def onboarding_reminders():
    """Setup not finished. The time the client picked in "Finish setup later?" wins;
    otherwise next day, 9 am (up to 3 days). "Off" stops both."""
    local = _local_now()
    sent = 0
    picked = _active_clients().filter(client_profile__onboarding__has_key="_remind")
    for c in picked:
        cp = c.client_profile
        r = cp.onboarding.get("_remind") or {}
        if r.get("sent") or not r.get("at") or len(cp.client_steps_done) >= 5:
            continue
        if datetime.fromisoformat(r["at"]) <= local:
            send_template(c, "onboarding-form-reminder", data={"route": "/welcome"})
            cp.onboarding["_remind"] = {**r, "sent": True}
            cp.save(update_fields=["onboarding"])
            sent += 1
    if not (local.hour == 9 and local.minute < 15):
        return sent
    today = local.date()
    for c in _active_clients().filter(date_joined__date__lt=today,
                                      date_joined__date__gte=today - timedelta(days=3)):
        cp = c.client_profile
        if len(cp.onboarding_done or []) >= 5 or (cp.onboarding or {}).get("_remind"):
            continue
        if once(c, "onboarding", "setup", today):
            send_template(c, "onboarding-form-reminder", data={"route": "/welcome"})
            sent += 1
    return sent


# ---------------------------------------------------------------- team
@shared_task
def document_expiry_reminders():
    """'Remind me before it expires' — 30 days before, on the Dashboard (and a notice)."""
    from apps.trainers.models import TrainerDocument

    today = timezone.localdate()
    admin = User.objects.filter(role="admin").first()
    sent = 0
    for d in TrainerDocument.objects.filter(remind_before_expiry=True, expires_on__isnull=False,
                                            expires_on__lte=today + timedelta(days=30),
                                            expires_on__gte=today).select_related("trainer__user"):
        if admin and once(admin, "doc_expiry", d.id, d.expires_on):
            days = (d.expires_on - today).days
            notify(admin, "document_expiring", f"{d.trainer.user.full_name}: {d.name} expires in {days} days",
                   "Ask for the new certificate.", data={"route": f"/trainers/{d.trainer.user_id}/documents"})
            sent += 1
    return sent


@shared_task
def nightly_client_stats():
    """Adherence + at-risk for every active client; tells the trainer about new at-risk clients."""
    from apps.clients.metrics import refresh_client_stats
    from apps.clients.models import ClientProfile

    n = 0
    newly = []
    for cp in ClientProfile.objects.filter(removed_at__isnull=True, user__status="active").select_related(
            "user", "trainer").iterator(chunk_size=200):
        try:
            if refresh_client_stats(cp):
                newly.append(cp)
        except Exception:
            log.exception("stats failed for %s", cp.user_id)
        n += 1
    for cp in newly:
        t = cp.trainer
        if t is None:
            continue
        pref = StaffNotificationPreference.objects.filter(user=t).first()
        if pref is None or pref.missed_workouts:
            notify(t, "client_at_risk", f"{cp.user.full_name} needs you", cp.at_risk_reason,
                   data={"route": f"/clients/{cp.user_id}"})
    return n


# ---------------------------------------------------------------- housekeeping
@shared_task
def roll_plans():
    from apps.training.services import roll_assignments

    return roll_assignments()


@shared_task
def auto_save_workouts():
    from apps.training.services import auto_save_stale_workouts

    return auto_save_stale_workouts()


@shared_task
def purge_deleted():
    """Soft-deleted rows and removed clients are kept 30 days for Undo / restore, then removed."""
    from django.apps import apps as django_apps

    from apps.clients.models import ClientProfile
    from apps.common.models import SoftDeleteModel

    cutoff = timezone.now() - timedelta(days=30)
    total = 0
    for model in django_apps.get_models():
        if issubclass(model, SoftDeleteModel) and not model._meta.abstract:
            try:
                n, _ = model.all_objects.filter(deleted_at__lt=cutoff).delete()
                total += n
            except Exception:  # protected rows (e.g. a food used in logs) stay soft-deleted
                log.info("kept protected rows of %s", model.__name__)
    for cp in ClientProfile.objects.filter(removed_at__lt=cutoff).select_related("user"):
        cp.user.delete()
        total += 1
    ReminderLog.objects.filter(day__lt=timezone.localdate() - timedelta(days=60)).delete()
    from apps.common.models import IdempotencyRecord

    IdempotencyRecord.objects.filter(created_at__lt=timezone.now() - timedelta(days=14)).delete()
    return total
