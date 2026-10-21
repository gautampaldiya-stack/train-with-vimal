"""Exercise library, Exercise details and Add exercise (boards ExerciseLibrary / ExerciseDetail / ExerciseAdd):
built-in exercises never change (Duplicate to edit), custom ones need "Add custom exercises", the cover image
upload, "also works" notes, Used in N programs counting only the trainer's own clients, and Add to program."""
import io

from PIL import Image
from django.core.files.uploadedfile import SimpleUploadedFile

from apps.accounts.models import User
from apps.training.models import Exercise, Program, ProgramAssignment, ProgramExercise

E = "/api/v1/exercises/"


def _bench():
    return Exercise.objects.get(name="Barbell Bench Press", is_builtin=True)


def _png(name="cover.png"):
    buf = io.BytesIO()
    Image.new("RGB", (8, 8), "#2563EB").save(buf, "PNG")
    return SimpleUploadedFile(name, buf.getvalue(), content_type="image/png")


def test_facets_and_can_flags(admin, trainer):
    f = admin.get(E + "facets/").json()
    assert f["builtin"] >= 28 and f["can"] == {"create": True}
    assert any(m["value"] == "chest" and m["count"] >= 5 for m in f["muscle"])
    assert trainer.get(E + "facets/").json()["can"]["create"] is True
    row = trainer.get(f"{E}{_bench().id}/").json()
    assert row["can_edit"] is False and row["source"] == "builtin"
    assert all("note" in a for a in row["also_works"])


def test_list_filters_and_sort(trainer):
    r = trainer.get(E, {"muscle": "chest,back", "level": "beginner", "ordering": "-n_programs"}).json()
    rows = r["results"]
    assert rows and all(x["muscle_group"] in ("chest", "back") and x["level"] == "beginner" for x in rows)
    assert [x["programs"] for x in rows] == sorted([x["programs"] for x in rows], reverse=True)


def test_builtin_is_read_only_duplicate_makes_an_editable_copy(trainer):
    b = _bench()
    assert trainer.patch(f"{E}{b.id}/", {"name": "Mine"}, format="json").status_code == 400
    assert trainer.delete(f"{E}{b.id}/").status_code == 403
    r = trainer.post(f"{E}{b.id}/duplicate/")
    assert r.status_code == 201, r.content
    c = r.json()
    assert c["name"] == "Barbell Bench Press (copy)" and c["can_edit"] is True and c["source"] == "custom"
    r = trainer.patch(f"{E}{c['id']}/", {"name": "Paused Bench", "also_works": [
        {"muscle": "Triceps", "level": "strong", "note": "  Lock out  at the top "}]}, format="json")
    assert r.status_code == 200, r.content
    assert r.json()["also_works"] == [{"muscle": "Triceps", "level": "strong", "note": "Lock out at the top"}]
    bad = trainer.patch(f"{E}{c['id']}/", {"also_works": [{"muscle": "Core"}, {"muscle": "core"}]}, format="json")
    assert bad.status_code == 400
    assert trainer.delete(f"{E}{c['id']}/").status_code == 204
    assert trainer.post(f"{E}{c['id']}/restore/").status_code == 200


def test_create_with_steps_and_cover_upload(admin):
    r = admin.post(E, {"name": "  Landmine   Press ", "muscle_group": "shoulders", "equipment": "barbell",
                       "level": "intermediate", "log_type": "weight_reps", "default_sets": 3, "default_reps": "8–12",
                       "default_rest_seconds": 90, "how_to": ["Set up half-kneeling.", " ", "Press up."],
                       "form_cues": ["Ribs down."], "also_works": [{"muscle": "Triceps", "level": "strong"}]},
                   format="json")
    assert r.status_code == 201, r.content
    ex = r.json()
    assert ex["name"] == "Landmine Press" and ex["how_to"] == ["Set up half-kneeling.", "Press up."]
    assert ex["thumb"] is None
    up = admin.post(f"{E}{ex['id']}/cover/", {"file": _png()}, format="multipart")
    assert up.status_code == 200, up.content
    assert up.json()["cover_image"] and up.json()["thumb"] == up.json()["cover_image"]
    txt = SimpleUploadedFile("x.png", b"not an image", content_type="image/png")
    assert admin.post(f"{E}{ex['id']}/cover/", {"file": txt}, format="multipart").status_code == 400
    assert admin.delete(f"{E}{ex['id']}/cover/").json()["cover_image"] is None
    assert admin.post(f"{E}{_bench().id}/cover/", {"file": _png()}, format="multipart").status_code == 403
    Exercise.all_objects.filter(id=ex["id"]).delete()


def test_used_in_counts_only_the_trainers_clients(admin, trainer):
    b = _bench()
    aman = User.objects.get(email="aman@trainwithvimal.com")
    mine = trainer.get(f"{E}{b.id}/used-in/").json()
    every = admin.get(f"{E}{b.id}/used-in/").json()
    assert mine and len(mine) == len(every)
    for row in mine:
        assert row["clients"] == ProgramAssignment.objects.filter(
            program_id=row["id"], status="active", client__client_profile__trainer=aman).count()
    assert sum(r["clients"] for r in every) >= sum(r["clients"] for r in mine)


def test_add_to_program_every_week(trainer):
    r = trainer.post("/api/v1/programs/", {"name": "Aman Test Block", "weeks": 3, "days_per_week": 2}, format="json")
    pid = r.json()["id"]
    b = _bench()
    r = trainer.post(f"/api/v1/programs/{pid}/add-exercise/", {"exercise": str(b.id), "weekday": 1}, format="json")
    assert r.status_code == 200, r.content and r.json()["weeks"] == 3
    rows = ProgramExercise.objects.filter(day__week__program_id=pid, day__weekday=1, exercise=b)
    assert rows.count() == 3 and all(x.sets == b.default_sets and x.reps == b.default_reps for x in rows)
    # the same day again adds no double; Used in names the day so the modal can mark it
    r = trainer.post(f"/api/v1/programs/{pid}/add-exercise/", {"exercise": str(b.id), "weekday": 1}, format="json")
    assert r.status_code == 400 and r.json()["error"]["fields"]["weekday"]
    assert rows.count() == 3
    used = {u["id"]: u for u in trainer.get(f"{E}{b.id}/used-in/").json()}
    assert used[pid]["weekdays"] == [1]
    # a rest day (weekday 5) is refused, and so is someone else's program
    assert trainer.post(f"/api/v1/programs/{pid}/add-exercise/", {"exercise": str(b.id), "weekday": 5},
                        format="json").status_code == 400
    vimal = Program.objects.get(name="Fat loss · 8 weeks", is_master=True)
    assert trainer.post(f"/api/v1/programs/{vimal.id}/add-exercise/", {"exercise": str(b.id), "weekday": 0},
                        format="json").status_code == 403
    Program.all_objects.filter(id=pid).delete()


def test_youtube_info_checks_the_link(trainer):
    assert trainer.get(E + "youtube-info/", {"url": "https://example.com/x"}).status_code == 400


def test_cover_frames_from_youtube_and_saved_on_the_exercise(trainer):
    """D-42: the "Frame from the video" tiles are real stills; the chosen key becomes the exercise's picture."""
    assert trainer.get(E + "frames/", {"url": "https://example.com/x"}).status_code == 400
    assert trainer.get(E + "frames/", {"video": "nope"}).status_code == 404
    r = trainer.get(E + "frames/", {"url": "https://youtu.be/dQw4w9WgXcQ"})
    assert r.status_code == 200, r.content
    fr = r.json()["frames"]
    assert [f["key"] for f in fr] == [f"yt/dQw4w9WgXcQ/{k}" for k in ("hq", "1", "2", "3")]
    assert fr[1]["url"] == "https://img.youtube.com/vi/dQw4w9WgXcQ/1.jpg"
    c = trainer.post(f"{E}{_bench().id}/duplicate/").json()
    bad = trainer.patch(f"{E}{c['id']}/", {"cover_frame": "../../etc/passwd"}, format="json")
    assert bad.status_code == 400 and "cover_frame" in bad.json()["error"]["fields"]
    ok = trainer.patch(f"{E}{c['id']}/", {"cover_frame": fr[2]["key"]}, format="json")
    assert ok.status_code == 200, ok.content
    assert ok.json()["cover_frame"] == fr[2]["key"] and ok.json()["thumb"] == fr[2]["url"]


def test_cover_frames_grabbed_from_an_uploaded_video(trainer, tmp_path):
    import subprocess

    import pytest
    from django.core.files import File

    from apps.content.models import ContentItem
    from apps.training.frames import ffmpeg_exe

    exe = ffmpeg_exe()
    if not exe:
        pytest.skip("no ffmpeg")
    src = tmp_path / "clip.mp4"
    subprocess.run([exe, "-v", "error", "-f", "lavfi", "-i", "testsrc=size=160x120:rate=10", "-t", "3",
                    "-pix_fmt", "yuv420p", str(src)], check=True, timeout=60)
    item = ContentItem(kind="video", title="Clip", duration_seconds=3)
    with open(src, "rb") as fh:
        item.file.save("clip.mp4", File(fh), save=False)
    item.save()
    from apps.training.frames import _grab
    fr = trainer.get(E + "frames/", {"video": str(item.id)}).json()["frames"]
    assert fr and all(f["url"] and f["key"].startswith("exercises/frames/") for f in fr)
    assert [f["label"] for f in fr][0] == "0:00"
    from django.core.files.storage import default_storage

    for f in fr:
        default_storage.delete(f["key"])
    item.file.delete(save=False)
