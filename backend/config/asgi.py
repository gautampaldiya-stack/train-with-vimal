"""ASGI entry: HTTP goes to Django, WebSocket goes to the realtime notification consumer."""
import os

from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")
django_asgi_app = get_asgi_application()

from channels.routing import ProtocolTypeRouter, URLRouter  # noqa: E402
from channels.security.websocket import AllowedHostsOriginValidator  # noqa: E402

from apps.notifications.routing import websocket_urlpatterns  # noqa: E402
from apps.notifications.ws_auth import JWTQueryAuthMiddleware  # noqa: E402

application = ProtocolTypeRouter(
    {
        "http": django_asgi_app,
        "websocket": AllowedHostsOriginValidator(JWTQueryAuthMiddleware(URLRouter(websocket_urlpatterns))),
    }
)
