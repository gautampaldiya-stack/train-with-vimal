"""PDF pages as pictures, so the app shows the real pages the same way on Android, iOS and web (no PDF reader
needed in the app). Pages are drawn once with pdfium and kept next to the media: content/pages/<item id>/<n>.png."""

import logging
from io import BytesIO

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage

log = logging.getLogger(__name__)

WIDTH = 1100  # px: sharp on a desktop dialog, light enough for a phone
MAX_PAGES = 60


def _name(item, n):
    return f"content/pages/{item.id}/{n}.png"


def page_images(item, request=None):
    """URLs of every page picture (drawn on first use). [] when the item has no PDF file or it cannot be read."""
    if item.kind != "pdf" or not item.file:
        return []
    count = item.pages or 0
    names = [_name(item, n) for n in range(1, min(count, MAX_PAGES) + 1)]
    if not count or not default_storage.exists(names[-1]):
        names = _draw(item)
    url = request.build_absolute_uri if request else (lambda u: u)
    return [url(default_storage.url(n)) for n in names]


def _draw(item):
    try:
        import pypdfium2 as pdfium
    except ImportError:  # pragma: no cover - listed in requirements
        return []
    try:
        with item.file.open("rb") as fh:
            pdf = pdfium.PdfDocument(fh.read())
    except Exception:  # noqa: BLE001 - a broken upload must not break the Library
        log.warning("could not read PDF for content %s", item.id)
        return []
    names = []
    try:
        total = len(pdf)
        for i in range(min(total, MAX_PAGES)):
            page = pdf[i]
            img = page.render(scale=WIDTH / page.get_width()).to_pil()
            buf = BytesIO()
            img.convert("RGB").save(buf, "PNG", optimize=True)
            name = _name(item, i + 1)
            if default_storage.exists(name):
                default_storage.delete(name)
            names.append(default_storage.save(name, ContentFile(buf.getvalue())))
    finally:
        pdf.close()
    if item.pages != total:
        type(item).objects.filter(id=item.id).update(pages=total)
        item.pages = total
    return names
