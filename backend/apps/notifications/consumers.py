import json

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncJsonWebsocketConsumer

from .realtime import group_name


class NotificationConsumer(AsyncJsonWebsocketConsumer):
    """Realtime events for one signed-in user.

    Server → app:  {"event": "notification", "payload": {...}}   new bell item / toast
                   {"event": "unread", "payload": {"count": 3}}
                   {"event": "<other>", "payload": {...}}        e.g. checkin_submitted, approval_waiting
    App → server:  {"action": "ping"}  → {"event": "pong"}
    """

    async def connect(self):
        user = self.scope.get("user")
        if not user or not user.is_authenticated:
            await self.close(code=4401)
            return
        self.group = group_name(user.id)
        await self.channel_layer.group_add(self.group, self.channel_name)
        await self.accept()
        await self.send_json({"event": "unread", "payload": {"count": await self._unread(user)}})

    async def disconnect(self, code):
        if hasattr(self, "group"):
            await self.channel_layer.group_discard(self.group, self.channel_name)

    async def receive_json(self, content, **kwargs):
        if content.get("action") == "ping":
            await self.send_json({"event": "pong"})

    async def app_event(self, message):
        await self.send(text_data=json.dumps({"event": message["event"], "payload": message["payload"]}))

    @database_sync_to_async
    def _unread(self, user):
        from .services import unread_count

        return unread_count(user)
