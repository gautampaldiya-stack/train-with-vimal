from apps.accounts.models import User
from apps.content.models import ContentItem, ContentShare, ContentView


def test_library_rows_counts_notes_and_new_first(client_user):
    r = client_user.get("/api/v1/me/library/")
    assert r.status_code == 200, r.content
    d = r.json()
    assert d["total"] == 9 and d["counts"] == {"all": 9, "video": 2, "pdf": 3, "image": 1, "article": 2, "link": 1,
                                               "saved": 1}
    assert d["done"] == 3 and d["new"] == 3 and d["coach_first"] == "Aman"
    assert [x["new"] for x in d["results"][:3]] == [True, True, True] and not d["results"][3]["new"]
    box = next(x for x in d["results"] if x["title"] == "Box squat: how to")
    assert box["source"].startswith("Assigned by Aman · ") and box["length"] == "3:05" and box["note"]
    assert {n["title"] for n in d["notes"]} >= {"Box squat: how to", "Macro cheat sheet"}
    leg = next(x for x in d["results"] if x["title"] == "How to warm up for leg day")
    assert leg["source"] == "From Fat loss · 8 weeks" and leg["done"]


def test_library_filters_and_search(client_user):
    assert client_user.get("/api/v1/me/library/", {"kind": "saved"}).json()["count"] == 1
    assert client_user.get("/api/v1/me/library/", {"kind": "pdf"}).json()["count"] == 3
    q = client_user.get("/api/v1/me/library/", {"q": "squat"}).json()
    assert {x["title"] for x in q["results"]} >= {"Box squat: how to"} and q["count"] < 8
    assert client_user.get("/api/v1/me/library/", {"kind": "nope"}).status_code == 400
    link = client_user.get("/api/v1/me/library/", {"kind": "link"}).json()["results"]
    assert len(link) == 1 and link[0]["length"] == "healthline.com"


def test_opening_an_item_marks_it_read_and_has_its_parts(client_user):
    eat = ContentItem.objects.get(title="Eating out on a fat loss plan")
    d = client_user.get(f"/api/v1/me/library/{eat.id}/").json()
    assert d["new"] is True and len(d["outline"]) == 6 and d["file_url"].endswith(".pdf") and d["note"]
    assert client_user.get(f"/api/v1/me/library/{eat.id}/").json()["new"] is False
    box = ContentItem.objects.get(title="Box squat: how to")
    v = client_user.get(f"/api/v1/me/library/{box.id}/").json()
    assert v["chapters"][1] == [48, "Sitting back"] and v["duration"] == 185


def test_save_and_mark_done_and_undo(client_user):
    riya = User.objects.get(email="riya@example.com")
    upa = ContentItem.objects.get(title="Upper A walkthrough")
    url = f"/api/v1/me/library/{upa.id}/progress/"
    assert client_user.post(url, {"finished": True}, format="json").json()["finished"] is True
    assert client_user.post(url, {"finished": False}, format="json").json()["finished"] is False
    client_user.post(url, {"saved": True}, format="json")
    assert ContentView.objects.get(user=riya, item=upa).saved


def test_others_items_stay_hidden(client_user):
    aman = User.objects.get(email="aman@trainwithvimal.com")
    other = User.objects.get(email="isha@example.com")
    item = ContentItem.objects.create(kind="article", title="Only for Isha", body="x", created_by=aman)
    ContentShare.objects.create(item=item, client=other, shared_by=aman)
    assert client_user.get(f"/api/v1/me/library/{item.id}/").status_code == 404
    assert all(x["title"] != "Only for Isha" for x in client_user.get("/api/v1/me/library/").json()["results"])


def test_coach_shares_with_a_note(trainer):
    riya = User.objects.get(email="riya@example.com")
    item = ContentItem.objects.create(kind="article", title="Sleep tips", body="Sleep 7 hours.",
                                      created_by=User.objects.get(email="aman@trainwithvimal.com"))
    r = trainer.post(f"/api/v1/clients/{riya.id}/content/", {"item": str(item.id), "note": "Read before bed"},
                     format="json")
    assert r.status_code == 201, r.content
    assert ContentShare.objects.get(item=item, client=riya).note == "Read before bed"


def test_note_names_its_writer_and_file_name_follows_the_title(client_user):
    d = client_user.get("/api/v1/me/library/").json()
    assert d["coach_initials"] == "AV"
    snack = next(x for x in d["results"] if x["title"] == "10 veg snacks under 200 kcal")
    assert snack["note_by"] == "Aman" and snack["note_initials"] == "AV"
    eat = ContentItem.objects.get(title="Eating out on a fat loss plan")
    assert client_user.get(f"/api/v1/me/library/{eat.id}/").json()["file_name"] == "eating-out-on-a-fat-loss-plan.pdf"


def test_dev_media_answers_range_requests(tmp_path, settings, client):
    from apps.common.media import serve_media
    from django.test import RequestFactory
    (tmp_path / "v.bin").write_bytes(bytes(range(200)))
    r = serve_media(RequestFactory().get("/media/v.bin", HTTP_RANGE="bytes=10-19"), "v.bin", document_root=tmp_path)
    assert r.status_code == 206 and r["Content-Range"] == "bytes 10-19/200"
    assert b"".join(r.streaming_content) == bytes(range(10, 20))
    assert serve_media(RequestFactory().get("/media/v.bin", HTTP_RANGE="bytes=300-"), "v.bin", document_root=tmp_path).status_code == 416


def test_pdf_detail_has_page_pictures(client_user):
    eat = ContentItem.objects.get(title="Eating out on a fat loss plan")
    pics = client_user.get(f"/api/v1/me/library/{eat.id}/").json()["page_images"]
    assert len(pics) == 6 and pics[0].endswith("/1.png")


def test_link_detail_and_staff_link_needs_a_url(admin):
    item = ContentItem.objects.get(title="Protein sources for vegetarians")
    assert item.kind == "link" and item.link_url.startswith("https://")
    r = admin.post("/api/v1/content/", {"kind": "link", "title": "Sleep guide"}, format="json")
    assert r.status_code == 400 and "link_url" in r.json()["error"]["fields"]
    r = admin.post("/api/v1/content/", {"kind": "link", "title": "Sleep guide", "link_url": "https://example.com/sleep"},
                   format="json")
    assert r.status_code == 201, r.content


def test_exercise_returns_its_media(db):
    from apps.training.models import Exercise
    from apps.training.serializers import ExerciseSerializer

    pic = ExerciseSerializer(Exercise.objects.get(name="Romanian Deadlift", is_builtin=True)).data
    assert pic["media"]["kind"] == "image" and pic["media"]["url"].endswith(".png") and pic["thumb"] == pic["media"]["url"]
    assert ExerciseSerializer(Exercise.objects.get(name="Dead Bug", is_builtin=True)).data["media"] is None
    lp = ExerciseSerializer(Exercise.objects.get(name="Leg Press", is_builtin=True)).data
    assert lp["media"]["kind"] == "video" and lp["media"]["url"].endswith(".mp4")
    lunge = Exercise.objects.get(name="Walking Lunge", is_builtin=True)
    assert lunge.youtube_url.startswith("https://www.youtube.com/") and lunge.video is None


def test_library_video_with_only_a_youtube_link_plays_as_youtube(db):
    from apps.content.library import media_of

    item = ContentItem.objects.create(kind="video", title="Lunge demo", youtube_url="https://youtu.be/YYWhkctnP2o")
    m = media_of(item)
    assert m["kind"] == "youtube" and m["url"] == "https://youtu.be/YYWhkctnP2o"
    item.youtube_url = ""
    assert media_of(item) is None


def test_demo_videos_ship_with_the_code(client_user):
    # Seeding needs no ffmpeg: the shared videos have real files.
    for title in ("Box squat: how to", "Upper A walkthrough"):
        assert ContentItem.objects.get(title=title).file.name.endswith(".mp4")
