import logging

from celery import shared_task
from django.contrib.auth import get_user_model
from django.utils import timezone

from . import providers
from .models import Channel, DeviceToken, Delivery, Notification, NotificationSettings
from .services import in_quiet_hours, mark_delivery, muted_by_prefs

log = logging.getLogger("notifications")
MAX_ATTEMPTS = 5


def _channel_payloads(n, channels, email_subject=None):
    return {
        ch: {"subject": email_subject or n.title if ch == Channel.EMAIL else n.title, "body": n.body}
        for ch in channels
    }


@shared_task
def deliver_notification(notification_id, channels, urgent=False, email_subject=None):
    n = Notification.objects.select_related("recipient").filter(id=notification_id).first()
    if n is None:
        return
    _fan_out(n, _channel_payloads(n, channels, email_subject), "", urgent, None)


@shared_task
def deliver_rendered(notification_id, rendered, template_key, urgent=False, automation_run_id=None):
    n = Notification.objects.select_related("recipient").filter(id=notification_id).first()
    if n is None:
        return
    _fan_out(n, rendered, template_key, urgent, automation_run_id)


def _fan_out(n, rendered, template_key, urgent, automation_run_id):
    if muted_by_prefs(n.recipient, n.event):
        return  # Coach updates / Progress switched off: the in-app row is enough
    quiet, resume_at = (False, None) if urgent else in_quiet_hours(user=n.recipient)
    for channel, content in rendered.items():
        d = Delivery.objects.create(
            notification=n,
            user=n.recipient,
            channel=channel,
            template_key=template_key,
            automation_run_id=automation_run_id,
            subject=content.get("subject", "")[:200],
            body=content.get("body", ""),
            scheduled_for=resume_at if quiet else None,
        )
        if quiet:
            send_delivery.apply_async(args=[str(d.id)], eta=resume_at)
        else:
            send_delivery.delay(str(d.id))


@shared_task(bind=True, max_retries=MAX_ATTEMPTS, default_retry_delay=60)
def send_delivery(self, delivery_id):
    d = Delivery.objects.select_related("user", "notification").filter(id=delivery_id).first()
    if d is None or d.status not in (Delivery.Status.QUEUED,):
        return
    user = d.user
    d.attempts += 1
    try:
        if d.channel == Channel.EMAIL:
            if not user.email:
                return mark_delivery(d, Delivery.Status.SKIPPED, error="No email address")
            cfg = NotificationSettings.load()
            pid = providers.send_email(user.email, d.subject or d.notification.title, d.body,
                                       reply_to=cfg.reply_to_email, sender_name=cfg.sender_name)
            return mark_delivery(d, Delivery.Status.SENT, pid)
        if d.channel == Channel.WHATSAPP:
            if not user.phone:
                return mark_delivery(d, Delivery.Status.SKIPPED, error="No mobile number")
            from apps.gym.models import Integration

            if not Integration.is_on(Integration.Kind.WHATSAPP):
                return mark_delivery(d, Delivery.Status.SKIPPED, error="WhatsApp is disconnected in Settings")
            pid = providers.send_whatsapp(user.phone, d.body)
            return mark_delivery(d, Delivery.Status.SENT, pid)
        if d.channel == Channel.PUSH:
            tokens = list(DeviceToken.objects.filter(user=user))
            if not tokens:
                return mark_delivery(d, Delivery.Status.SKIPPED, error="No device")
            data = {"notification_id": str(d.notification_id), **(d.notification.data if d.notification else {})}
            sent = 0
            for t in tokens:
                try:
                    providers.send_push(t.token, d.subject or d.notification.title, d.body, data, t.platform)
                    sent += 1
                except providers.ProviderError as exc:
                    if exc.permanent:
                        t.delete()  # uninstalled app / expired browser subscription
                    else:
                        raise
            return mark_delivery(d, Delivery.Status.SENT if sent else Delivery.Status.SKIPPED)
    except providers.ProviderError as exc:
        if exc.permanent or self.request.retries >= MAX_ATTEMPTS:
            return mark_delivery(d, Delivery.Status.FAILED, error=str(exc))
        d.error = str(exc)
        d.save(update_fields=["attempts", "error", "updated_at"])
        raise self.retry(exc=exc, countdown=min(3600, 60 * 2 ** self.request.retries))


@shared_task
def purge_old_notifications(days=180):
    cutoff = timezone.now() - timezone.timedelta(days=days)
    Notification.objects.filter(created_at__lt=cutoff, read_at__isnull=False).delete()
    Delivery.objects.filter(created_at__lt=cutoff).delete()


def users_by_ids(ids):
    return get_user_model().objects.filter(id__in=ids)
