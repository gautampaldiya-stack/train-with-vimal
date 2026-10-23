"""Media view with HTTP Range support (dev, and a single VPS with SERVE_MEDIA=True), so a browser can seek in a Library video (Django's own
`static.serve` always sends the whole file, and Chrome then restarts the video on every seek).
Production serves media from S3, which handles Range itself."""

import mimetypes
import re

from django.http import FileResponse, Http404, HttpResponse
from django.utils._os import safe_join
from django.views.static import serve

_RANGE = re.compile(r"bytes=(\d*)-(\d*)$")


def serve_media(request, path, document_root=None):
    m = _RANGE.match(request.headers.get("Range", "").strip())
    if not m:
        return serve(request, path, document_root=document_root)
    try:
        full = safe_join(str(document_root), path)
        f = open(full, "rb")  # noqa: SIM115 - FileResponse closes it
    except (OSError, ValueError):
        raise Http404 from None
    size = f.seek(0, 2)
    start, end = m.groups()
    if start:
        first, last = int(start), min(int(end) if end else size - 1, size - 1)
    else:
        first, last = max(size - int(end or 0), 0), size - 1
    if first > last or first >= size:
        f.close()
        r = HttpResponse(status=416)
        r["Content-Range"] = f"bytes */{size}"
        return r
    f.seek(first)
    r = FileResponse(_Part(f, last - first + 1), status=206, content_type=mimetypes.guess_type(full)[0] or "application/octet-stream")
    r["Content-Length"] = str(last - first + 1)
    r["Content-Range"] = f"bytes {first}-{last}/{size}"
    r["Accept-Ranges"] = "bytes"
    return r


class _Part:
    """Reads at most n bytes of an open file."""

    def __init__(self, f, n):
        self.f, self.left = f, n

    def read(self, size=-1):
        if self.left <= 0:
            return b""
        size = self.left if size < 0 else min(size, self.left)
        data = self.f.read(size)
        self.left -= len(data)
        return data

    def close(self):
        self.f.close()
