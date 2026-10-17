"""Trainer → My profile (boards TrainerMe / TrainerMeMobile): the page data, edit my details, What clients see,
documents, Ask for more access, My activity (with logins), devices, notifications. Numbers match the dashboard."""
from django.core.files.uploadedfile import SimpleUploadedFile

from apps.accounts.models import User
from apps.trainers.models import AccessRequest

ME = "/api/v1/trainers/me/"


def test_me_page_numbers_match_the_dashboard(trainer):
    r = trainer.get(ME)
    assert r.status_code == 200, r.content
    d = r.json()
    for k in ("stats", "access_groups", "week", "attention", "attention_total", "last_login", "asked", "profile"):
        assert k in d, k
    dash = trainer.get("/api/v1/dashboard/trainer/").json()
    # D-30: one check-in queue and one client count everywhere.
    assert d["stats"]["clients"] == d["clients"]
    ds = {x["key"]: x for x in dash["stats"]}
    assert ds["checkins"]["value"] == str(d["stats"]["checkins_to_review"])
    assert ds["clients"]["value"] == f'{d["stats"]["clients"]} / {d["stats"]["max_clients"]}'
    assert ds["reply"]["value"] == d["reply"]["value"]
    week = {r["label"]: r["value"] for r in d["week"]["rows"]}
    dweek = {r["label"]: r["value"] for r in dash["week"]["rows"]}
    for k in ("Check-ins reviewed", "Plans changed", "Sessions held"):
        assert week[k] == dweek[k]
    assert d["week"]["range"] == dash["week"]["range"]
    assert len(d["attention"]) <= 3 and d["attention_total"] >= len(d["attention"])
    # the admin table shows the same check-in count for Aman
    aman = User.objects.get(email="aman@trainwithvimal.com")
    assert d["checkins_to_review"] == d["stats"]["checkins_to_review"]
    assert d["id"] == str(aman.id)


def test_edit_my_details_validates_and_keeps_admin_fields(trainer):
    r = trainer.patch(ME, {"full_name": "Aman Verma", "phone": "12345", "email": "aman@trainwithvimal.com"},
                      format="json")
    assert r.status_code == 400 and "phone" in r.json()["error"]["fields"]
    r = trainer.patch(ME, {"experience_since": 2999}, format="json")
    assert r.status_code == 400 and "experience_since" in r.json()["error"]["fields"]
    r = trainer.patch(ME, {"speciality": "Strength, Fat loss, strength", "languages": "Hindi, English",
                           "experience_since": 2020, "mode": "gym_online", "works_best_with": "Beginners",
                           "bio": "Short bio", "instagram": "@aman.lifts", "website": "https://amanlifts.in",
                           "city": "Mumbai", "gender": "male", "date_of_birth": "1994-02-14",
                           "max_clients": 300, "access_mode": "all"}, format="json")
    assert r.status_code == 200, r.content
    d = r.json()
    assert d["speciality"] == ["Strength", "Fat loss"]
    assert d["profile"]["experience_since"] == 2020 and d["city"] == "Mumbai"
    assert d["max_clients"] != 300 and d["access_mode"] != "all"  # set by the admin only


def test_what_clients_see_round_trip(trainer):
    r = trainer.put(ME + "visibility/", {"mobile": True, "photo_name": False, "email": False}, format="json")
    assert r.status_code == 200, r.content
    v = r.json()
    assert v["visibility"]["mobile"] is True and v["visibility"]["photo_name"] is True
    assert "phone" in v["preview"] and "email" not in v["preview"]
    assert trainer.put(ME + "visibility/", {"nope": True}, format="json").status_code == 400
    trainer.put(ME + "visibility/", {"mobile": False}, format="json")


def test_documents_upload_view_replace_delete(trainer):
    f = SimpleUploadedFile("cert.pdf", b"%PDF-1.4 test", content_type="application/pdf")
    r = trainer.post(ME + "documents/", {"kind": "certificate", "name": "Kettlebell Level 1", "issuer": "StrongFirst",
                                          "issued_on": "2024-05-01", "expires_on": "2026-05-01",
                                          "visibility": "admins_clients", "file": f}, format="multipart")
    assert r.status_code == 201, r.content
    doc = r.json()
    assert doc["status"] in ("not_checked", "expired", "expires_soon")
    bad = trainer.post(ME + "documents/", {"kind": "certificate", "name": "X", "issued_on": "2024-05-01",
                                            "expires_on": "2023-01-01",
                                            "file": SimpleUploadedFile("a.pdf", b"%PDF", content_type="application/pdf")},
                       format="multipart")
    assert bad.status_code == 400 and "expires_on" in bad.json()["error"]["fields"]
    exe = trainer.post(ME + "documents/", {"kind": "certificate", "name": "X",
                                            "file": SimpleUploadedFile("a.exe", b"MZ", content_type="application/octet-stream")},
                       format="multipart")
    assert exe.status_code == 400
    assert trainer.post(f"{ME}documents/{doc['id']}/verify/").status_code == 403
    assert any(x["id"] == doc["id"] for x in trainer.get(ME + "documents/").json())
    assert trainer.delete(f"{ME}documents/{doc['id']}/").status_code == 204


def test_ask_for_more_access_shows_on_the_page(trainer):
    AccessRequest.objects.filter(trainer__user__email="aman@trainwithvimal.com").delete()
    assert trainer.post("/api/v1/access-requests/", {"permissions": []}, format="json").status_code == 400
    r = trainer.post("/api/v1/access-requests/", {"permissions": ["clients.view_all"], "reason": "Sundays"},
                     format="json")
    assert r.status_code == 201, r.content
    asked = trainer.get(ME).json()["asked"]
    assert asked["labels"] == ["View all clients"]


def test_my_activity_pages_and_counts(trainer):
    r = trainer.get(ME + "activity/", {"range": "all", "limit": 3})
    assert r.status_code == 200, r.content
    d = r.json()
    assert set(d["counts"]) >= {"all", "checkin", "plan", "client", "login"}
    assert d["count"] == d["counts"]["all"] and len(d["results"]) <= 3
    assert d["counts"]["login"] >= 1  # the test client logged in
    if d["has_more"]:
        nxt = trainer.get(ME + "activity/", {"range": "all", "limit": 3, "offset": 3}).json()["results"]
        assert {x["id"] for x in nxt}.isdisjoint({x["id"] for x in d["results"]})
    logins = trainer.get(ME + "activity/", {"range": "all", "kind": "login"}).json()
    assert all(x["kind"] == "login" and x["verb"] == "Logged in" for x in logins["results"])
    assert trainer.get(ME + "activity/", {"offset": "x"}).status_code == 400


def test_devices_and_notifications(trainer):
    d = trainer.get(ME + "devices/").json()
    assert d["results"] and d["results"][0]["this_device"] is True
    assert len(d["results"]) <= 6
    n = trainer.get(ME + "notifications/").json()
    assert set(n) == {"new_checkin", "missed_workouts", "new_client", "session_reminders", "daily_summary", "gym_news"}
    r = trainer.put(ME + "notifications/", {"daily_summary": True, "new_checkin": False}, format="json")
    assert r.status_code == 200 and r.json()["daily_summary"] is True and r.json()["new_checkin"] is False
    from apps.notifications.models import StaffNotificationPreference

    assert StaffNotificationPreference.objects.get(user__email="aman@trainwithvimal.com").new_checkin is False
    assert trainer.put(ME + "notifications/", {"gym_news": "maybe"}, format="json").status_code == 400


def test_clients_cannot_open_trainer_me(client_user):
    assert client_user.get(ME).status_code == 403
    assert client_user.get(ME + "activity/").status_code == 403


def test_admin_table_adherence_matches_my_profile(admin, trainer):
    me = trainer.get(ME).json()
    rows = admin.get("/api/v1/trainers/", {"page_size": 100}).json()
    rows = rows.get("results", rows)
    row = next(r for r in rows if r["id"] == me["id"])
    assert row["adherence"] == me["stats"]["adherence"]
    assert row["clients"] == me["stats"]["clients"]
    assert row["checkins_to_review"] == me["stats"]["checkins_to_review"]
