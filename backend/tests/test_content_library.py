"""Library → Content (boards `Content` / `ContentMobile`): the page summary and what it offers, card fields (length,
who has it, where it is used), the cover frame, and Assign with Everyone limited to Vimal."""
from apps.content.models import ContentItem
from apps.training.models import Exercise


def test_summary_and_can(admin, trainer):
    d = admin.get("/api/v1/content/summary/").json()
    assert d["total"] == ContentItem.objects.count()
    assert d["storage"]["limit"] == 20 * 1024 ** 3 and d["storage"]["used"] >= 0
    assert d["can"] == {"manage": True, "everyone": True}
    assert trainer.get("/api/v1/content/summary/").json()["can"]["everyone"] is False


def test_card_fields_who_and_uses(admin):
    r = admin.post("/api/v1/content/", {"kind": "article", "title": "  Sleep   basics ", "body": "word " * 450},
                   format="json")
    assert r.status_code == 201, r.content
    c = r.json()
    assert c["title"] == "Sleep basics" and c["length_label"] == "2 min read"
    assert c["who"] == "Not assigned" and c["uses"] == []
    url = f"/api/v1/content/{c['id']}/"
    clients = admin.get(url + "assign/").json()["clients"]
    admin.post(url + "assign/", {"clients": [clients[0]["id"]]}, format="json")
    assert admin.get(url).json()["who"] == clients[0]["full_name"]
    admin.post(url + "assign/", {"clients": [x["id"] for x in clients[:3]]}, format="json")
    assert admin.get(url).json()["who"] == "3 clients"
    assert admin.post(url + "assign/", {"everyone": True}, format="json").json()["everyone"] is True
    assert admin.get(url).json()["who"] == "Everyone"
    ex = Exercise.objects.first()
    ex.video_id = c["id"]
    ex.save(update_fields=["video"])
    d = admin.get(url + "detail/").json()
    assert {"type": "exercise", "id": str(ex.id), "name": ex.name} in d["uses"]
    assert d["used_in"] == d["uses"]


def test_frame_must_be_a_real_key(admin):
    item = ContentItem.objects.create(kind="video", title="Squat demo", youtube_url="https://youtu.be/abcdefghijk")
    url = f"/api/v1/content/{item.id}/"
    r = admin.patch(url, {"frame": "../../etc/passwd"}, format="json")
    assert r.status_code == 400 and "frame" in r.json()["error"]["fields"]


def test_everyone_is_admin_only(trainer):
    item = ContentItem.objects.create(kind="article", title="Protein", body="Eat protein.")
    url = f"/api/v1/content/{item.id}/assign/"
    if not trainer.get("/api/v1/content/summary/").json()["can"]["manage"]:
        assert trainer.post(url, {"everyone": True}, format="json").status_code == 403
        return
    assert trainer.post(url, {"everyone": True}, format="json").status_code == 403


def test_new_video_staged_so_its_frame_can_be_picked_before_save(admin):
    from django.core.files.uploadedfile import SimpleUploadedFile

    r = admin.post("/api/v1/content/stage/", {"file": SimpleUploadedFile("squat.mp4", b"\x00" * 2048, "video/mp4")},
                   format="multipart")
    assert r.status_code == 201, r.content
    d = r.json()
    assert d["upload"].endswith(".mp4") and len(d["frames"]) == 4
    key = d["frames"][1]["key"]
    r = admin.post("/api/v1/content/", {"kind": "video", "title": "Squat", "upload": d["upload"], "frame": key},
                   format="json")
    assert r.status_code == 201, r.content
    item = ContentItem.objects.get(id=r.json()["id"])
    assert item.file and item.file_size == 2048
    # an upload that is not (or no longer) staged
    r = admin.post("/api/v1/content/", {"kind": "video", "title": "Again", "upload": d["upload"]}, format="json")
    assert r.status_code == 400 and "expired" in r.json()["error"]["fields"]["file"][0]


def test_uploads_stop_when_storage_is_full(admin, settings):
    from django.core.files.uploadedfile import SimpleUploadedFile

    settings.CONTENT_STORAGE_GB = 0
    r = admin.post("/api/v1/content/", {"kind": "pdf", "title": "Guide",
                                        "file": SimpleUploadedFile("g.pdf", b"%PDF-1.4 x", "application/pdf")},
                   format="multipart")
    assert r.status_code == 400 and "storage is full" in r.json()["error"]["fields"]["file"][0]
    r = admin.post("/api/v1/content/stage/", {"file": SimpleUploadedFile("a.mp4", b"\x00" * 10, "video/mp4")},
                   format="multipart")
    assert r.status_code == 400
