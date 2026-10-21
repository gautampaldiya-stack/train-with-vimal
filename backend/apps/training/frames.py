"""Cover frames for an exercise (board ExerciseAdd → Cover image → "Frame from the video").

An uploaded library video: four stills grabbed with ffmpeg (10 %, 30 %, 55 % and 80 % into the video, or a few
seconds in when the length is unknown), saved once under media/exercises/frames/ and reused. A YouTube link: the four
stills YouTube makes for every video (the cover and three auto frames). The chosen frame is stored on the exercise as
`cover_frame` (its key) and becomes the exercise's picture everywhere (D-42).
"""
import os
import re
import shutil
import subprocess
import tempfile
from contextlib import contextmanager

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage

FRAME_DIR = "exercises/frames"
KEY_RE = re.compile(r"^(exercises/frames/[0-9a-f-]{36}-\d{1,5}\.jpg|yt/[A-Za-z0-9_-]{11}/(hq|1|2|3))$")
YT_FRAMES = [("hq", "hqdefault", "Cover"), ("1", "1", "¼"), ("2", "2", "½"), ("3", "3", "¾")]


def clock(s):
    return f"{s // 60}:{s % 60:02d}"


def ffmpeg_exe():
    """The system ffmpeg, else the one bundled with imageio-ffmpeg (pip), else None (frames then stay tinted tiles)."""
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    try:
        import imageio_ffmpeg

        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:  # noqa: BLE001 — not installed / no binary for this platform
        return None


def frame_times(duration):
    if not duration:
        return [1, 4, 8, 12]
    times = sorted({max(0, min(duration - 1, round(duration * p))) for p in (0.1, 0.3, 0.55, 0.8)})
    return times or [0]


def _grab(exe, source, at):
    """One JPEG still `at` seconds into the video (480 px wide), or None."""
    try:
        r = subprocess.run(  # noqa: S603 — fixed arguments, the source is our own media file
            [exe, "-v", "error", "-ss", str(at), "-i", source, "-frames:v", "1", "-vf", "scale=480:-2", "-q:v", "4",
             "-f", "image2", "-c:v", "mjpeg", "-"],
            capture_output=True, timeout=20, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout if r.returncode == 0 and r.stdout else None


def key_url(key, request=None):
    """Picture URL for a stored frame key (None when the key is not one of ours)."""
    if not key or not KEY_RE.match(key):
        return None
    if key.startswith("yt/"):
        _, vid, n = key.split("/")
        name = dict((k, f) for k, f, _ in YT_FRAMES)[n]
        return f"https://img.youtube.com/vi/{vid}/{name}.jpg"
    url = default_storage.url(key)
    return request.build_absolute_uri(url) if request else url


def video_frames(item, request=None):
    """Frames of an uploaded library video: [{key, at, label, url}] (url None when ffmpeg could not grab it)."""
    out = []
    exe = ffmpeg_exe()
    with _source(item) as source:
        for at in frame_times(item.duration_seconds):
            key = f"{FRAME_DIR}/{item.id}-{at}.jpg"
            if not default_storage.exists(key) and exe and source:
                data = _grab(exe, source, at)
                if data:
                    default_storage.save(key, ContentFile(data))
            has = default_storage.exists(key)
            out.append({"key": key, "at": at, "label": clock(at), "url": key_url(key, request) if has else None})
    return out


@contextmanager
def _source(item):
    """Something ffmpeg can read: the file on disk, the storage URL (S3), or a temporary copy (other storages)."""
    if not item.file:
        yield None
        return
    try:
        path = item.file.path
    except NotImplementedError:
        path = None
    if path and os.path.exists(path):
        yield path
        return
    url = item.file.url
    if url.startswith("http"):
        yield url
        return
    with tempfile.NamedTemporaryFile(suffix=os.path.splitext(item.file.name)[1]) as tmp:
        with item.file.open("rb") as fh:
            shutil.copyfileobj(fh, tmp)
        tmp.flush()
        yield tmp.name


def youtube_frames(vid):
    return [{"key": f"yt/{vid}/{k}", "at": None, "label": label, "url": f"https://img.youtube.com/vi/{vid}/{f}.jpg"}
            for k, f, label in YT_FRAMES]
