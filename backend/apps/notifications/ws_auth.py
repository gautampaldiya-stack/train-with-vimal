"""WebSocket auth: the app connects to  ws(s)://host/ws/notifications/?token=<access JWT>.
Browsers cannot set headers on WebSocket, so the short-lived access token rides in the query."""
from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from channels.middleware import BaseMiddleware
from django.contrib.auth.models import AnonymousUser


@database_sync_to_async
def _user_for(token):
    from rest_framework_simplejwt.exceptions import InvalidToken, TokenError

    from apps.accounts.authentication import SessionJWTAuthentication

    auth = SessionJWTAuthentication()
    try:
        validated = auth.get_validated_token(token)
        user = auth.get_user(validated)
    except (InvalidToken, TokenError, Exception):
        return AnonymousUser()
    return user if user.can_use_app else AnonymousUser()


class JWTQueryAuthMiddleware(BaseMiddleware):
    async def __call__(self, scope, receive, send):
        query = parse_qs(scope.get("query_string", b"").decode())
        token = (query.get("token") or [None])[0]
        scope["user"] = await _user_for(token) if token else AnonymousUser()
        return await super().__call__(scope, receive, send)
