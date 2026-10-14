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


# DRF's own field codes. Anything else (e.g. "invalid_login", "locked") is a code we raised on purpose
# and the app can switch on it.
_GENERIC = {
    "invalid", "required", "blank", "null", "max_length", "min_length", "max_value", "min_value", "invalid_choice",
    "does_not_exist", "unique", "not_a_list", "empty", "incorrect_type", "max_digits", "max_decimal_places",
    "max_whole_digits", "date", "datetime", "not_a_dict", "max_string_length", "make_aware", "overflow",
    "no_name", "invalid_image", "unique_set",
}


def _named_code(codes):
    if isinstance(codes, dict):
        order = ["non_field_errors", *[k for k in codes if k != "non_field_errors"]]
        for k in order:
            if k in codes:
                c = _named_code(codes[k])
                if c:
                    return c
    elif isinstance(codes, list):
        for c in codes:
            c = _named_code(c)
            if c:
                return c
    elif isinstance(codes, str) and codes not in _GENERIC:
        return codes
    return None


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
        body = {"error": {"code": _named_code(exc.get_codes()) or "validation_error", "message": message,
                          "fields": fields}}
    else:
        detail = exc.detail if hasattr(exc, "detail") else str(exc)
        body = {"error": {"code": getattr(detail, "code", code) or code, "message": str(detail)}}
        if isinstance(exc, exceptions.Throttled) and exc.wait:
            body["error"]["retry_after"] = int(exc.wait)
    return Response(body, status=response.status_code, headers=response.headers)
