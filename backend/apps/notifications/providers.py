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
    from apps.gym.models import Integration

    from_email = settings.DEFAULT_FROM_EMAIL
    own = Integration.from_email()  # Settings → Integrations: verified own domain
    if own:
        from_email = f"{sender_name or from_email.split('<', 1)[0].strip() or 'Train With Vimal'} <{own}>"
    elif sender_name and "<" in from_email:
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


def fcm_project_id():
    """FCM_PROJECT_ID, else the project of the server key file (D-80). It must be the app's Firebase project
    (FB_PROJECT_ID in firebase.json), or FCM refuses every push."""
    if settings.FCM_PROJECT_ID:
        return settings.FCM_PROJECT_ID
    try:
        with open(settings.FCM_SERVICE_ACCOUNT_FILE) as f:
            return json.load(f).get("project_id", "")
    except (OSError, ValueError):
        return ""


def send_push(device_token, title, body, data=None, platform="android"):
    if settings.PUSH_PROVIDER == "console":
        log.info("PUSH -> %s… | %s | %s | %s", device_token[:12], title, body, json.dumps(data or {}))
        return f"console-{int(time.time() * 1000)}"
    project = fcm_project_id()
    if not project:
        raise ProviderError("FCM project unknown: set FCM_PROJECT_ID or FCM_SERVICE_ACCOUNT_FILE in .env")
    url = f"https://fcm.googleapis.com/v1/projects/{project}/messages:send"
    data = {k: str(v) for k, v in (data or {}).items()}
    webpush = {"headers": {"Urgency": "high"}}
    route = data.get("route", "")
    if route.startswith("/") and settings.FRONTEND_URL.startswith("https://"):
        # The browser opens this page when the notification is tapped (same site as the app).
        webpush["fcm_options"] = {"link": settings.FRONTEND_URL.rstrip("/") + route}
    message = {
        "token": device_token,
        "notification": {"title": title, "body": body},
        "data": data,
        # No channel_id (D-80): the app makes no "default" channel, so Android uses Firebase's own channel.
        "android": {"priority": "high"},
        "apns": {"payload": {"aps": {"sound": "default"}}},
        "webpush": webpush,
    }
    resp = httpx.post(
        url, json={"message": message}, headers={"Authorization": f"Bearer {_fcm_access_token()}"}, timeout=10
    )
    if resp.status_code == 200:
        return resp.json().get("name", "")
    raise ProviderError(f"FCM {resp.status_code}: {resp.text[:300]}",
                        permanent=token_is_dead(resp.status_code, resp.text))


def token_is_dead(status, text):
    """Only a token FCM no longer knows is dropped (app removed, browser subscription gone). A plain INVALID_ARGUMENT
    is usually a bad message, and dropping the token for it silently stopped every later push (D-80)."""
    if status == 404 or "UNREGISTERED" in text:
        return True
    return status == 400 and "registration token" in text.lower()


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
