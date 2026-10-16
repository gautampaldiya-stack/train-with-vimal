from datetime import datetime, time, timedelta

from django.core import mail
from django.utils import timezone

from apps.accounts.models import ProblemReport, User
from apps.checkins.models import PhotoSet
from apps.checkins.services import next_photos_due, photo_week
from apps.notifications.models import Notification
from apps.notifications.services import in_quiet_hours, muted_by_prefs

PNG = ("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5E"
       "rkJggg==")


def test_account_page_has_profile_coach_plan_goal_and_settings(client_user):
    r = client_user.get("/api/v1/me/account/")
    assert r.status_code == 200, r.content
    d = r.json()
    assert d["profile"]["name"] == "Riya Sharma" and d["profile"]["initials"] == "RS"
    assert d["coach"]["first_name"] == "Aman"
    assert d["checkin"]["weekday"] == 6 and d["checkin"]["next"] >= timezone.localdate().isoformat()
    assert d["program"]["weeks"] and d["program"]["week"] <= d["program"]["weeks"]
    assert d["goal"]["title"] == "lose fat" and d["goal"]["goal_kg"] == 62.0 and 0 <= d["goal"]["pct"] <= 100
    assert d["stats"]["lost_kg"] > 0 and d["stats"]["checkins_sent"] >= 1
    assert set(d["reminders"]) >= {"workout", "water", "supps", "progress", "quiet_on", "quiet_from"}
    assert d["deletion_on"] is None and d["gym"]["name"]


def test_account_page_is_for_clients_only(trainer):
    assert trainer.get("/api/v1/me/account/").status_code == 403


def test_activity_lists_last_7_days_by_day_and_filters(client_user):
    client_user.post("/api/v1/me/weights/", {"date": timezone.localdate().isoformat(), "weight_kg": 67.9},
                     format="json")
    d = client_user.get("/api/v1/me/activity/").json()
    assert d["count"] >= 1 and d["days"][0]["date"] == timezone.localdate().isoformat()
    item = next(i for i in d["days"][0]["items"] if i["title"] == "Logged weight")
    assert item["k"] == "Check-ins" and item["link"] == "/progress" and item["rows"][0] == ["Weight", "67.9 kg"]
    only = client_user.get("/api/v1/me/activity/", {"kind": "Training"}).json()
    assert all(i["k"] == "Training" for day in only["days"] for i in day["items"])
    assert client_user.get("/api/v1/me/activity/", {"kind": "Nope"}).status_code == 400


def test_profile_edit_shows_in_my_activity_and_new_email_waits(client_user, django_capture_on_commit_callbacks):
    with django_capture_on_commit_callbacks(execute=True):
        r = client_user.patch("/api/v1/auth/me/", {"city": "Thane", "email": "riya.new@example.com",
                                                   "phone": "98190 55621"}, format="json")
    assert r.status_code == 200, r.content
    me = r.json()
    assert me["city"] == "Thane" and me["phone"] == "+919819055621"
    assert me["email"] == "riya@example.com" and me["pending_email"] == "riya.new@example.com"
    acc = client_user.get("/api/v1/me/activity/", {"kind": "Account"}).json()
    item = acc["days"][0]["items"][0]
    assert item["title"] == "You updated your profile" and "City" in item["sub"]
    assert ["City", "Delhi → Thane"] in item["rows"]


def test_mobile_number_must_be_free(client_user):
    aman = User.objects.get(email="aman@trainwithvimal.com")
    r = client_user.patch("/api/v1/auth/me/", {"phone": aman.phone}, format="json")
    assert r.status_code == 400 and "phone" in r.json()["error"]["fields"]


def test_units_and_privacy_are_saved(client_user, django_capture_on_commit_callbacks):
    with django_capture_on_commit_callbacks(execute=True):
        r = client_user.patch("/api/v1/auth/me/", {"unit_weight": "lb", "week_start": "sun", "theme": "system",
                                                   "share_photos": False}, format="json")
    assert r.status_code == 200, r.content
    me = r.json()
    assert (me["unit_weight"], me["week_start"], me["theme"], me["share_photos"]) == ("lb", "sun", "system", False)
    acc = client_user.get("/api/v1/me/activity/", {"kind": "Account"}).json()
    assert acc["days"][0]["items"][0]["title"] == "You changed your preferences"


def test_photos_added_while_sharing_is_off_stay_hidden_from_the_coach(client_user, trainer):
    riya = User.objects.get(email="riya@example.com")
    client_user.patch("/api/v1/auth/me/", {"share_photos": False}, format="json")
    r = client_user.post("/api/v1/me/photos/", {"pose": "front", "image": PNG}, format="json")
    assert r.status_code == 201, r.content
    mine = client_user.get("/api/v1/me/progress/").json()["photo_sets"]
    assert any(s["date"] == timezone.localdate().isoformat() for s in mine)
    staff = trainer.get(f"/api/v1/clients/{riya.id}/progress/").json()["photo_sets"]
    assert all(s["date"] != timezone.localdate().isoformat() for s in staff)


def test_reminder_settings_and_reset_to_recommended(client_user):
    r = client_user.patch("/api/v1/me/reminders/", {"water": False, "quiet_from": "23:00:00"}, format="json")
    assert r.status_code == 200 and r.json()["water"] is False and r.json()["quiet_from"] == "23:00:00"
    d = client_user.post("/api/v1/me/reminders/").json()
    assert d["water"] is True and d["habit"] is False and d["quiet_from"] == "22:00:00"


def test_own_quiet_hours_and_muted_coach_updates(client_user):
    client_user.patch("/api/v1/me/reminders/", {"quiet_on": True, "quiet_from": "22:00:00", "quiet_to": "07:00:00",
                                                "trainer_reply": False}, format="json")
    riya = User.objects.select_related("reminder_prefs").get(email="riya@example.com")
    night = timezone.make_aware(datetime.combine(timezone.localdate(), time(23, 30)))
    quiet, ends = in_quiet_hours(night, user=riya)
    assert quiet and timezone.localtime(ends).time() == time(7, 0)
    assert muted_by_prefs(riya, "checkin_reviewed") and not muted_by_prefs(riya, "session_booked")


def test_data_export_emails_a_link(client_user, settings):
    settings.CELERY_TASK_ALWAYS_EAGER = True
    settings.MEDIA_ROOT = "/tmp/twv-test-media"
    r = client_user.post("/api/v1/me/data-export/")
    assert r.status_code == 202 and r.json()["email"] == "riya@example.com"
    assert mail.outbox and "exports/" in mail.outbox[-1].body and ".zip" in mail.outbox[-1].body


def test_report_a_problem_reaches_the_admin(client_user):
    r = client_user.post("/api/v1/me/report/", {"category": "broken", "text": "Water did not save",
                                                "screenshot": PNG, "page": "/more"}, format="json")
    assert r.status_code == 201, r.content
    rep = ProblemReport.objects.get(id=r.json()["id"])
    assert rep.screenshot and rep.category == "broken"
    assert Notification.objects.filter(event="problem_report", recipient__role="admin").exists()
    bad = client_user.post("/api/v1/me/report/", {"category": "x", "text": ""}, format="json")
    assert bad.status_code == 400 and {"category", "text"} <= set(bad.json()["error"]["fields"])


def test_photos_come_every_n_weeks_with_the_weekly_checkin(client_user):
    riya = User.objects.get(email="riya@example.com")
    today = timezone.localdate()
    monday = today - timedelta(days=today.weekday())
    PhotoSet.objects.filter(client=riya, date__gte=monday - timedelta(days=7)).delete()
    last = PhotoSet.objects.filter(client=riya, photos__isnull=False).order_by("-date").first()
    # The demo's last set is older than 2 weeks, so this week asks for photos.
    assert last.date < monday - timedelta(days=7) and photo_week(riya, today)
    last.date = monday - timedelta(days=3)  # last week's Friday
    last.save()
    assert not photo_week(riya, today) and photo_week(riya, today + timedelta(days=7))
    assert next_photos_due(riya, today) == monday + timedelta(days=13)
    form = client_user.get("/api/v1/me/checkins/").json()["weekly"]["form"]
    assert all(q["type"] != "photo" for q in form["questions"])
    riya.client_profile.photo_every_weeks = 1
    riya.client_profile.save()
    assert photo_week(riya, today)


def test_past_day_and_edited_measurements_leave_a_line(client_user, django_capture_on_commit_callbacks):
    today = timezone.localdate()
    past = today - timedelta(days=3)
    url = "/api/v1/me/measurements/"
    with django_capture_on_commit_callbacks(execute=True):
        client_user.post(url, {"date": today.isoformat(), "values": {"chest": 91}}, format="json")
        assert client_user.get("/api/v1/me/activity/", {"kind": "Check-ins"}).json()["days"][0]["items"][0][
            "title"] != "You changed measurements"
        client_user.post(url, {"date": past.isoformat(), "values": {"chest": 92, "waist": 80}}, format="json")
        client_user.post(url, {"date": past.isoformat(), "values": {"chest": 91.5}}, format="json")
    items = [i for d in client_user.get("/api/v1/me/activity/", {"kind": "Check-ins"}).json()["days"]
             if d["date"] == today.isoformat() for i in d["items"]]
    on = past.strftime("%a, ") + str(past.day) + past.strftime(" %b")
    edit = next(i for i in items if i["title"] == f"You changed measurements for {on}")
    assert ["Chest", "92 → 91.5 cm"] in edit["rows"] and edit["link"] == "/progress"
    added = next(i for i in items if i["title"] == f"You added measurements for {on}")
    assert ["Waist", "80 cm"] in added["rows"]
    # Today's plain log adds no extra line.
    assert not any(i["title"].startswith("You added measurements for") and on not in i["title"] for i in items)


def test_changing_a_weigh_in_leaves_a_line(client_user, django_capture_on_commit_callbacks):
    day = timezone.localdate() - timedelta(days=1)
    with django_capture_on_commit_callbacks(execute=True):
        client_user.post("/api/v1/me/weights/", {"date": day.isoformat(), "weight_kg": 68.0}, format="json")
        client_user.post("/api/v1/me/weights/", {"date": day.isoformat(), "weight_kg": 67.6}, format="json")
    acc = client_user.get("/api/v1/me/activity/", {"kind": "Check-ins"}).json()
    titles = [i["title"] for d in acc["days"] for i in d["items"]]
    assert any(t.startswith("You changed your weight for") for t in titles)


def test_photo_week_checkin_asks_measurements_and_saves_them_to_progress(client_user):
    from apps.checkins.models import Measurement

    riya = User.objects.get(email="riya@example.com")
    riya.client_profile.photo_every_weeks = 1
    riya.client_profile.save()
    today = timezone.localdate()
    from apps.checkins.models import Submission
    Submission.objects.filter(client=riya, form_type="weekly", date__gte=today - timedelta(days=today.weekday())).delete()
    # The demo's entry from this period makes the step go away (one entry per period); start without it.
    Measurement.objects.filter(client=riya, date__gte=today - timedelta(days=today.weekday() + 7)).delete()
    form = client_user.get("/api/v1/me/checkins/").json()["weekly"]["form"]
    mq = next(q for q in form["questions"] if q["type"] == "measures")
    keys = [m["key"] for m in mq["measures"]]
    assert mq["id"] == -1 and "waist" in keys and not mq["required"]
    assert next(m for m in mq["measures"] if m["key"] == "waist")["last"] is not None
    i = [q["type"] for q in form["questions"]]
    assert i.index("measures") == i.index("photo") - 1
    answers = {str(q["id"]): 68.0 for q in form["questions"] if q["metric"] == "weight"}
    for q in form["questions"]:
        if q["required"] and str(q["id"]) not in answers:
            answers[str(q["id"])] = q["options"][0] if q["options"] else 4
    bad = client_user.post("/api/v1/me/submissions/", {"form": form["id"], "answers": {**answers, "-1": {"waist": 5}}},
                           format="json")
    assert bad.status_code == 400 and "-1" in bad.json()["error"]["fields"]
    r = client_user.post("/api/v1/me/submissions/", {"form": form["id"], "answers": {**answers, "-1": {"waist": 79,
                                                                                                    "hips": ""}}},
                         format="json")
    assert r.status_code == 201, r.content
    assert Measurement.objects.get(client=riya, date=today).values["waist"] == 79.0


def test_height_is_editable_and_logged(client_user, django_capture_on_commit_callbacks):
    with django_capture_on_commit_callbacks(execute=True):
        r = client_user.patch("/api/v1/auth/me/", {"height_cm": "165"}, format="json")
    assert r.status_code == 200, r.content
    assert client_user.get("/api/v1/me/account/").json()["profile"]["height_cm"] == 165.0
    item = client_user.get("/api/v1/me/activity/", {"kind": "Account"}).json()["days"][0]["items"][0]
    assert ["Height", "162 cm → 165 cm"] in item["rows"]
    assert client_user.patch("/api/v1/auth/me/", {"height_cm": 20}, format="json").status_code == 400


def test_account_has_daily_checkin_state(client_user):
    d = client_user.get("/api/v1/me/account/").json()["daily"]
    assert d["reminder"] == "9:00 pm" and isinstance(d["sent_today"], bool)


def test_history_lists_measurements_with_weigh_ins(client_user):
    today = timezone.localdate()
    client_user.post("/api/v1/me/measurements/", {"date": today.isoformat(), "values": {"waist": 79, "bicep_l": 28}},
                     format="json")
    d = client_user.get("/api/v1/me/history/", {"type": "weight"}).json()
    e = next(e for e in d["days"][0]["entries"] if e["title"].startswith("Measurements"))
    assert e["type"] == "weight" and any(r[0] == "Waist" for r in e["detail"])


def test_measurements_are_one_entry_per_period(client_user):
    from apps.checkins.models import Measurement

    riya = User.objects.get(email="riya@example.com")
    today = timezone.localdate()
    Measurement.objects.filter(client=riya, date__gte=today - timedelta(days=30)).delete()
    url = "/api/v1/me/measurements/"
    # No entry in this period: the log makes one for today.
    assert client_user.post(url, {"date": today.isoformat(), "values": {"waist": 80}}, format="json").status_code == 201
    p = client_user.get("/api/v1/me/progress/").json()
    assert p["measure_entry"]["date"] == today.isoformat()
    # Logging again in the same period changes that entry; no second row.
    client_user.post(url, {"date": today.isoformat(), "values": {"hips": 99}}, format="json")
    rows = Measurement.objects.filter(client=riya, date__gte=today - timedelta(days=30))
    assert rows.count() == 1 and rows[0].values == {"waist": 80.0, "hips": 99.0}
    monday = today - timedelta(days=today.weekday())
    assert p["next_measure"]["date"] == (monday + timedelta(days=6 + 14)).isoformat()
