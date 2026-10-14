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


def in_quiet_hours(now=None):
    cfg = NotificationSettings.load()
    if not cfg.quiet_hours_on:
        return False, None
    now = timezone.localtime(now)
    t = now.time()
    start, end = cfg.quiet_start, cfg.quiet_end
    quiet = (start <= t or t < end) if start > end else (start <= t < end)
    if not quiet:
        return False, None
    end_dt = timezone.make_aware(datetime.combine(now.date(), end))
    if end_dt <= now:
        end_dt += timedelta(days=1)
    return True, end_dt


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
