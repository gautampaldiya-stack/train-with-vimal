"""`Idempotency-Key` support for offline sync and retries.

Writes (POST / PUT / PATCH / DELETE) under /api/ that carry the header are answered once; the same key
from the same user gets the stored answer again. Only 2xx answers are stored, so a failed write can be
retried with the same key. A key reused for a different path is refused (409) — a bug in the app.
"""
import re

from django.db import IntegrityError
from django.http import HttpResponse, JsonResponse

from .models import IdempotencyRecord

KEY_RE = re.compile(r"^[A-Za-z0-9_\-:.]{8,80}$")
WRITE_METHODS = {"POST", "PUT", "PATCH", "DELETE"}


def _user_id(request):
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    try:
        from rest_framework_simplejwt.tokens import AccessToken

        return AccessToken(header[7:]).get("uid")
    except Exception:
        return None


class IdempotencyMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        key = request.headers.get("Idempotency-Key")
        if not key or request.method not in WRITE_METHODS or not request.path.startswith("/api/"):
            return self.get_response(request)
        if not KEY_RE.match(key):
            return JsonResponse({"error": {"code": "bad_idempotency_key",
                                           "message": "Idempotency-Key must be 8–80 letters, digits or - _ : ."}},
                                status=400)
        uid = _user_id(request)
        if uid is None:  # login, join link… : no user to scope the key to
            return self.get_response(request)
        rec = IdempotencyRecord.objects.filter(user_id=uid, key=key).first()
        if rec is not None:
            if rec.path != request.path or rec.method != request.method:
                return JsonResponse({"error": {"code": "idempotency_key_reused",
                                               "message": "This Idempotency-Key was used for another request."}},
                                    status=409)
            resp = HttpResponse(bytes(rec.body), status=rec.status_code, content_type=rec.content_type)
            resp["Idempotent-Replay"] = "true"
            return resp
        response = self.get_response(request)
        if 200 <= response.status_code < 300 and not getattr(response, "streaming", False):
            try:
                IdempotencyRecord.objects.create(
                    key=key, user_id=uid, method=request.method, path=request.path[:300],
                    status_code=response.status_code, body=bytes(response.content),
                    content_type=response.get("Content-Type", "application/json")[:100])
            except IntegrityError:  # two copies raced; the first one won
                pass
        return response
