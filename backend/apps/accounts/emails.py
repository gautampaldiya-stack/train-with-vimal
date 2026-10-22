"""Transactional emails (verify, reset, login link). Sent right away, never held by quiet hours."""
from datetime import timedelta

from celery import shared_task
from django.conf import settings
from django.db import transaction
from django.utils import timezone

from apps.common.utils import dfmt

from apps.notifications.models import MessageTemplate, NotificationSettings
from apps.notifications.providers import send_email
from apps.notifications.rendering import context_for, render


@shared_task(bind=True, max_retries=5, default_retry_delay=30)
def send_email_task(self, to, subject, body):
    cfg = NotificationSettings.load()
    try:
        send_email(to, subject, body, reply_to=cfg.reply_to_email, sender_name=cfg.sender_name)
    except Exception as exc:
        raise self.retry(exc=exc)


def _queue(to, subject, body):
    transaction.on_commit(lambda: send_email_task.delay(to, subject, body))


def link(path, token):
    return f"{settings.FRONTEND_URL.rstrip('/')}/{path}?token={token}"


def send_verify_email(user, token, to=None):
    url = link("verify-email", token)
    _queue(
        to or user.email,
        f"Confirm your email for {settings.APP_NAME}",
        f"Hi {user.first_name},\n\nTap the link to confirm this email address:\n{url}\n\n"
        "The link works once, for 24 hours. If you did not ask for this, ignore this email.",
    )


def send_password_reset(user, token):
    url = link("reset-password", token)
    tpl = MessageTemplate.objects.filter(key="password-reset").first()
    ctx = context_for(user)
    if tpl and tpl.channels.get("email", {}).get("on"):
        subject = render(tpl.channels["email"].get("subject") or "Reset your password", ctx)
        body = render(tpl.channels["email"].get("body", ""), ctx)
    else:
        subject, body = "Reset your password", f"Hi {user.first_name},"
    if not tpl or not tpl.channels.get("email", {}).get("on"):
        body += "\n\nThe link works once, for 15 minutes. If you did not ask for this, you can ignore this email."
    _queue(user.email, subject, f"{body}\n\n{url}")


def send_login_link(user, token, template_key="client-invite"):
    url = link("start", token)
    tpl = MessageTemplate.objects.filter(key=template_key).first()
    valid = timezone.localdate() + timedelta(minutes=settings.TOKEN_TTL_MINUTES["login_link"])
    ctx = context_for(user, {"date": dfmt(valid, "%-d %b")})
    if tpl and tpl.channels.get("email", {}).get("on"):
        subject = render(tpl.channels["email"].get("subject"), ctx)
        body = render(tpl.channels["email"].get("body", ""), ctx)
    else:
        subject, body = f"Your {settings.APP_NAME} account", f"Hi {user.first_name},"
    if user.email:
        _queue(user.email, subject, f"{body}\n\n{url}")
    # The WhatsApp text of the invite (Emails & alerts → Client invite), when it is on and we have a number.
    wa = tpl.channels.get("whatsapp", {}) if tpl else {}
    from apps.gym.models import Integration

    if wa.get("on") and wa.get("body") and getattr(user, "phone", "") and Integration.is_on(Integration.Kind.WHATSAPP):
        text = f"{render(wa['body'], ctx)} {url}"
        transaction.on_commit(lambda: send_whatsapp_task.delay(user.phone, text))


@shared_task(bind=True, max_retries=5, default_retry_delay=30)
def send_whatsapp_task(self, to, body):
    from apps.notifications.providers import send_whatsapp

    try:
        send_whatsapp(to, body)
    except Exception as exc:
        raise self.retry(exc=exc)
