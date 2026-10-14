"""One error shape for the whole API.

{"error": {"code": "validation_error", "message": "...", "fields": {"email": ["..."]}}}
"""
from django.core.exceptions import PermissionDenied as DjangoPermissionDenied
from django.http import Http404
from rest_framework import exceptions, status
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_handler


class Conflict(exceptions.APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "This clashes with something that already exists."
    default_code = "conflict"


def _flatten(detail):
    if isinstance(detail, dict):
        return {k: _flatten(v) for k, v in detail.items()}
    if isinstance(detail, list):
        return [_flatten(v) for v in detail]
    return str(detail)


def exception_handler(exc, context):
    if isinstance(exc, Http404):
        exc = exceptions.NotFound()
    elif isinstance(exc, DjangoPermissionDenied):
        exc = exceptions.PermissionDenied()

    response = drf_handler(exc, context)
    if response is None:
        return None

    code = getattr(exc, "default_code", "error")
    if isinstance(exc, exceptions.ValidationError):
        fields = _flatten(exc.detail)
        if isinstance(fields, list):
            fields = {"non_field_errors": fields}
        message = "Please check the highlighted fields."
        non_field = fields.get("non_field_errors") if isinstance(fields, dict) else None
        if non_field:
            message = non_field[0]
        body = {"error": {"code": "validation_error", "message": message, "fields": fields}}
    else:
        detail = exc.detail if hasattr(exc, "detail") else str(exc)
        body = {"error": {"code": getattr(detail, "code", code) or code, "message": str(detail)}}
        if isinstance(exc, exceptions.Throttled) and exc.wait:
            body["error"]["retry_after"] = int(exc.wait)
    return Response(body, status=response.status_code, headers=response.headers)
