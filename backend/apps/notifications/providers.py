"""Channel senders. `console` (default in dev) only logs; real providers need keys in .env.

Each send returns a provider message id or raises ProviderError.
"""
import json
import logging
import time

import httpx
from django.conf import settings
from django.core.cache import cache
from django.core.mail import EmailMultiAlternatives

log = logging.getLogger("notifications")


class ProviderError(Exception):
    def __init__(self, message, permanent=False):
        super().__init__(message)
        self.permanent = permanent  # bad token / number: do not retry


# ------------------------------------------------------------------ email
def send_email(to, subject, body, reply_to=None, sender_name=None):
    from_email = settings.DEFAULT_FROM_EMAIL
    if sender_name and "<" in from_email:
        from_email = f"{sender_name} <{from_email.split('<', 1)[1]}"
    msg = EmailMultiAlternatives(
        subject=subject, body=body, from_email=from_email, to=[to], reply_to=[reply_to] if reply_to else None
    )
    try:
        msg.send(fail_silently=False)
    except Exception as exc:  # SMTP errors
        raise ProviderError(str(exc)) from exc
    return ""


# ------------------------------------------------------------------ push (FCM HTTP v1)
def _fcm_access_token():
    token = cache.get("fcm-access-token")
    if token:
        return token
    try:
        from google.auth.transport.requests import Request
        from google.oauth2 import service_account
    except ImportError as exc:  # pragma: no cover
        raise ProviderError("google-auth is not installed; pip install google-auth") from exc
    creds = service_account.Credentials.from_service_account_file(
        settings.FCM_SERVICE_ACCOUNT_FILE, scopes=["https://www.googleapis.com/auth/firebase.messaging"]
    )
    creds.refresh(Request())
    cache.set("fcm-access-token", creds.token, 50 * 60)
    return creds.token


def send_push(device_token, title, body, data=None, platform="android"):
    if settings.PUSH_PROVIDER == "console":
        log.info("PUSH -> %s… | %s | %s | %s", device_token[:12], title, body, json.dumps(data or {}))
        return f"console-{int(time.time() * 1000)}"
    url = f"https://fcm.googleapis.com/v1/projects/{settings.FCM_PROJECT_ID}/messages:send"
    message = {
        "token": device_token,
        "notification": {"title": title, "body": body},
        "data": {k: str(v) for k, v in (data or {}).items()},
        "android": {"priority": "high", "notification": {"channel_id": "default"}},
        "apns": {"payload": {"aps": {"sound": "default"}}},
        "webpush": {"headers": {"Urgency": "high"}},
    }
    resp = httpx.post(
        url, json={"message": message}, headers={"Authorization": f"Bearer {_fcm_access_token()}"}, timeout=10
    )
    if resp.status_code == 200:
        return resp.json().get("name", "")
    permanent = resp.status_code in (400, 404) and ("UNREGISTERED" in resp.text or "INVALID_ARGUMENT" in resp.text)
    raise ProviderError(f"FCM {resp.status_code}: {resp.text[:300]}", permanent=permanent)


# ------------------------------------------------------------------ WhatsApp (Meta Cloud API)
def send_whatsapp(phone, body):
    if settings.WHATSAPP_PROVIDER == "console":
        log.info("WHATSAPP -> %s | %s", phone, body)
        return f"console-{int(time.time() * 1000)}"
    url = f"https://graph.facebook.com/v20.0/{settings.WHATSAPP_PHONE_NUMBER_ID}/messages"
    payload = {
        "messaging_product": "whatsapp",
        "to": phone.lstrip("+"),
        "type": "text",
        "text": {"preview_url": False, "body": body[:4096]},
    }
    resp = httpx.post(
        url, json=payload, headers={"Authorization": f"Bearer {settings.WHATSAPP_ACCESS_TOKEN}"}, timeout=10
    )
    if resp.status_code == 200:
        return (resp.json().get("messages") or [{}])[0].get("id", "")
    raise ProviderError(f"WhatsApp {resp.status_code}: {resp.text[:300]}", permanent=resp.status_code == 400)
