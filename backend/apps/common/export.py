"""Streaming CSV export, so "Export" on a 100k-row table never loads it all in memory."""
import csv

from django.http import StreamingHttpResponse
from django.utils import timezone


class _Echo:
    def write(self, value):
        return value


def _safe(value):
    # Stop spreadsheet formula injection (=, +, -, @ at the start of a cell).
    text = "" if value is None else str(value)
    if text[:1] in ("=", "+", "-", "@", "\t", "\r"):
        return "'" + text
    return text


def csv_response(filename, header, rows):
    writer = csv.writer(_Echo())

    def stream():
        yield writer.writerow(header)
        for row in rows:
            yield writer.writerow([_safe(v) for v in row])

    stamp = timezone.localdate().isoformat()
    resp = StreamingHttpResponse(stream(), content_type="text/csv")
    resp["Content-Disposition"] = f'attachment; filename="{filename}-{stamp}.csv"'
    return resp
