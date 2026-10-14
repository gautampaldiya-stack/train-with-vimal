"""Keeps the current request around so activity/audit rows can record who and from where."""
import threading

_local = threading.local()


def get_current_request():
    return getattr(_local, "request", None)


def client_source(request) -> str:
    """Maps the X-Client header the app sends to the labels the Activity log shows."""
    if request is None:
        return "System"
    header = (request.headers.get("X-Client") or "").lower()
    return {
        "android": "Android app",
        "ios": "iPhone app",
        "web": "Web",
    }.get(header, "Web")


class RequestContextMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        _local.request = request
        try:
            return self.get_response(request)
        finally:
            _local.request = None
