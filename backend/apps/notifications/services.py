"""The one entry point for telling people things.

    notify(users, "checkin_reviewed", "Aman replied to your check-in", "Week 6: ...",
           data={"route": "/checkins/<id>"}, channels=["in_app", "push"])

- In-app rows are written at once and sent over WebSocket after commit (realtime).
- Push / email / WhatsApp go through Celery, respecting quiet hours (urgent=True skips them).
"""
from datetime import datetime, timedelta

from django.db import transaction
from django.utils import timezone

from .models import Channel, Delivery, MessageTemplate, Notification, NotificationSettings
from .rendering import context_for, render


# Client More → Notification settings: these switch off the push / email copy (the in-app row stays).
COACH_EVENTS = {"checkin_reviewed", "plan_assigned", "meal_plan_assigned", "meal_plan_updated", "trainer_changed",
                "content_shared", "form_request", "workout_plan_updated", "plan_ended", "plan_removed"}
PROGRESS_EVENTS = {"personal_best", "milestone"}


def muted_by_prefs(user, event):
    """True when the person switched this kind of message off (Coach updates / Progress and personal bests)."""
    p = getattr(user, "reminder_prefs", None) if getattr(user, "is_client", False) else None
    if p is None:
        return False
    return (event in COACH_EVENTS and not p.trainer_reply) or (event in PROGRESS_EVENTS and not p.progress)


def _window(now, start, end):
    t = now.time()
    quiet = (start <= t or t < end) if start > end else (start <= t < end)
    if not quiet:
        return False, None
    end_dt = timezone.make_aware(datetime.combine(now.date(), end))
    if end_dt <= now:
        end_dt += timedelta(days=1)
    return True, end_dt


def in_quiet_hours(now=None, user=None):
    """The gym's quiet hours, and the person's own (More → Notification settings), whichever ends later."""
    now = timezone.localtime(now)
    cfg = NotificationSettings.load()
    gym = _window(now, cfg.quiet_start, cfg.quiet_end) if cfg.quiet_hours_on else (False, None)
    p = getattr(user, "reminder_prefs", None) if user is not None else None
    own = _window(now, p.quiet_from, p.quiet_to) if p is not None and p.quiet_on else (False, None)
    ends = [e for q, e in (gym, own) if q]
    return (True, max(ends)) if ends else (False, None)


def _serialize(n):
    return {
        "id": str(n.id),
        "event": n.event,
        "title": n.title,
        "body": n.body,
        "data": n.data,
        "created_at": n.created_at.isoformat(),
        "read_at": None,
        "actor": str(n.actor_id) if n.actor_id else None,
        # Same names as the list rows, so the Notifications page can put a live row on top as it is.
        "actor_name": n.actor.full_name if n.actor_id else None,
        "actor_initials": n.actor.initials if n.actor_id else None,
        "actor_color": n.actor.avatar_color if n.actor_id else None,
    }


def notify(users, event, title, body="", *, data=None, channels=None, actor=None, urgent=False, in_app=True,
           email_subject=None):
    from . import tasks
    from .realtime import send_to_user

    if not isinstance(users, (list, tuple, set)) and not hasattr(users, "__iter__"):
        users = [users]
    channels = list(channels or [Channel.IN_APP, Channel.PUSH])
    created = []
    for user in users:
        if user is None:
            continue
        n = Notification.objects.create(
            recipient=user, actor=actor, event=event, title=title[:140], body=body, data=data or {},
            in_app=in_app and Channel.IN_APP in channels,
        )
        created.append(n)
        external = [c for c in channels if c != Channel.IN_APP]
        payload = _serialize(n)

        def _after_commit(n=n, external=external, payload=payload, uid=user.id):
            if n.in_app:
                send_to_user(uid, "notification", payload)
            if external:
                tasks.deliver_notification.delay(str(n.id), external, urgent, email_subject)

        transaction.on_commit(_after_commit)
    return created


def send_template(user, key, *, extra=None, channels=None, actor=None, data=None, urgent=False,
                  automation_run=None):
    """Send a Message template (Emails & alerts) to one person on its switched-on channels."""
    from . import tasks

    tpl = MessageTemplate.objects.filter(key=key).first()
    if tpl is None:
        return None
    ctx = context_for(user, extra)
    on = [c for c, cfg in tpl.channels.items() if cfg.get("on")]
    if channels:
        on = [c for c in on if c in channels]
    if not on:
        return None
    in_app_cfg = tpl.channels.get("in_app", {})
    push_cfg = tpl.channels.get("push", {})
    title = render(in_app_cfg.get("title") or push_cfg.get("title") or tpl.name, ctx)
    body = render(in_app_cfg.get("body") or push_cfg.get("body") or "", ctx)
    n = Notification.objects.create(
        recipient=user, actor=actor, event=f"tpl:{key}", title=title[:140], body=body, data=data or {},
        in_app=Channel.IN_APP in on,
    )
    rendered = {}
    for ch in on:
        if ch == Channel.IN_APP:
            continue
        cfg = tpl.channels.get(ch, {})
        rendered[ch] = {
            "subject": render(cfg.get("subject") or cfg.get("title") or "", ctx),
            "body": render(cfg.get("body") or "", ctx),
        }
    payload = _serialize(n)

    def _after():
        from .realtime import send_to_user

        if n.in_app:
            send_to_user(user.id, "notification", payload)
        if rendered:
            tasks.deliver_rendered.delay(
                str(n.id), rendered, key, urgent, str(automation_run.id) if automation_run else None
            )

    transaction.on_commit(_after)
    return n


def unread_count(user):
    return Notification.objects.filter(recipient=user, in_app=True, read_at__isnull=True).count()


def mark_delivery(delivery, status, provider_id="", error=""):
    delivery.status = status
    delivery.provider_id = provider_id or delivery.provider_id
    delivery.error = error
    if status in (Delivery.Status.SENT, Delivery.Status.DELIVERED):
        delivery.sent_at = timezone.now()
    delivery.save(update_fields=["status", "provider_id", "error", "sent_at", "attempts", "updated_at"])


def tell_clients(clients, event, title, body="", *, actor=None, route, daily_key=None):
    """The coach changed something in the client's plan (D-60): bell + push ("Coach updates" mutes the push).
    `daily_key`: at most once a day per client for it (the program builder saves as you type)."""
    from .reminders import once

    out = []
    today = timezone.localdate()
    for c in clients:
        if actor is not None and c.id == actor.id:
            continue
        if daily_key and not once(c, "coach_upd", daily_key, today):
            continue
        out += notify(c, event, title, body, actor=actor, data={"route": route})
    return out
