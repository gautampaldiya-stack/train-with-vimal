"""Pushes events to every open app/web tab of a user over WebSocket (group `user_<id>`)."""
import logging

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

log = logging.getLogger("notifications")


def group_name(user_id):
    return f"user_{user_id}"


def send_to_user(user_id, event_type, payload):
    layer = get_channel_layer()
    if layer is None:
        return
    try:
        async_to_sync(layer.group_send)(
            group_name(user_id), {"type": "app.event", "event": event_type, "payload": payload}
        )
    except Exception:  # realtime is best effort; push/in-app still carry it
        log.exception("realtime send failed for %s", user_id)
