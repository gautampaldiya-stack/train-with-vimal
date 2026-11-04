import base64
from datetime import date, timedelta

import pytest
from django.utils import timezone

from apps.checkins.models import Form, PhotoSet, Submission
from apps.clients.models import ClientProfile

# 1x1 transparent PNG
PNG = "data:image/png;base64," + base64.b64encode(bytes.fromhex(
    "89504e470d0a1a0a0000000d4948445200000001000000010806000000"
    "1f15c4890000000d49444154789c6360000002000154a24f5d0000000049454e44ae426082")).decode()



@pytest.fixture
def photo_week():
    """The demo's last photo set is last week; with photos every week this week asks for them too."""
    ClientProfile.objects.filter(user__email="riya@example.com").update(photo_every_weeks=1)


@pytest.fixture
def photo_week_open(photo_week):
    """photo_week, with the weekly check-in due (and open) today so it can be sent on any weekday."""
    _open_weekly()
    # With the check-in moved to today, a set from the last few days would make this an off week.
    PhotoSet.objects.filter(client__email="riya@example.com", submission__isnull=True,
                            date__gt=timezone.localdate() - timedelta(days=7)).delete()


def _open_weekly():
    """The weekly check-in is sent only while its window is open (E23): due today for these tests."""
    from apps.accounts.models import User
    from apps.checkins import schedule
    from apps.checkins.models import FormSchedule

    riya = User.objects.get(email="riya@example.com")
    if not schedule.current(riya)["open"]:
        FormSchedule.objects.create(client=riya, form=Form.objects.filter(type="weekly").first(), repeat="week",
                                    weekday=timezone.localdate().weekday(), time="18:00")

def _page(c, **params):
    r = c.get("/api/v1/me/checkins/", params)
    assert r.status_code == 200, r.content
    return r.json()


def _qid(form, text):
    return str(next(q["id"] for q in form["questions"] if q["text"] == text))


def test_checkins_page_has_the_board_numbers(client_user, photo_week):
    d = _page(client_user)
    assert d["coach"]["first_name"] == "Aman"
    assert d["program"]["week"] == d["weekly"]["week"]
    assert d["stats"] == {"streak": 2, "weekly_on_time": 5, "weekly_due": 6, "last_change_kg": -0.6}
    w = d["weekly"]
    assert [q["chip"] for q in w["form"]["questions"]] == ["Weight", "Your week", "Meal plan", "3 photos", "Notes"]
    assert "Aman" in w["form"]["questions"][2]["help_text"]
    due = timezone.localtime(timezone.datetime.fromisoformat(w["due_at"]))
    assert due.weekday() == 6 and due.hour == 18 and w["sent"] is None
    assert d["daily"]["sent"] is None and d["daily"]["steps"] is not None
    kinds = [(r["kind"], r["week_number"]) for r in d["history"]]
    assert ("missed", 4) in kinds and kinds[0] == ("sent", 6)
    first = d["history"][0]
    assert first["metrics"]["weight"] == 68.9 and first["change_kg"] == -0.6
    assert {"workouts_done", "workouts_planned", "meals_pct"} <= set(first)
    after_gap = next(r for r in d["history"] if r["week_number"] == 5)
    assert after_gap["change_weeks"] == 2 and after_gap["reply"]


def test_daily_history_pages_and_shows_missed_days(client_user):
    d = _page(client_user, tab="daily")
    assert len(d["history"]) == 20 and d["has_more"]
    missed = [r for r in d["history"] if r["kind"] == "missed"]
    assert missed and missed[0]["reminder"] == "9:00 pm"
    assert any(r.get("reply") for r in d["history"])
    t = d["history_total"]
    assert t["all"] > 20 and t["sent"] + t["missed"] == t["all"] and t["missed"] >= len(missed)
    older = _page(client_user, tab="daily", before=d["next_before"])
    assert all(date.fromisoformat(r["date"]) < date.fromisoformat(d["next_before"]) for r in older["history"])
    assert client_user.get("/api/v1/me/checkins/", {"tab": "monthly"}).status_code == 400


def test_send_daily_then_edit(client_user):
    d = _page(client_user)
    f = d["daily"]["form"]
    answers = {_qid(f, "Morning weight"): 68.3, _qid(f, "Sleep last night"): "6.5 h", _qid(f, "Energy"): 4,
               _qid(f, "Mood"): 4, _qid(f, "Hunger"): 3}
    r = client_user.post("/api/v1/me/submissions/", {"form": f["id"], "answers": answers}, format="json")
    assert r.status_code == 400 and "error" in r.json()  # soreness is required
    answers[_qid(f, "Soreness")] = 5
    r = client_user.post("/api/v1/me/submissions/", {"form": f["id"], "answers": answers, "note": "Slept late",
                                                     "logged_at": (timezone.now() - timedelta(minutes=30)).isoformat()},
                         format="json", HTTP_IDEMPOTENCY_KEY="ck-daily-1")
    assert r.status_code == 201, r.content
    body = r.json()
    assert body["metrics"]["sleep_hours"] == 6.5 and body["metrics"]["note"] == "Slept late"
    assert body["streak"] == 3
    d = _page(client_user)
    assert d["daily"]["sent"]["id"] == body["id"] and d["stats"]["streak"] == 3
    answers[_qid(f, "Energy")] = 2
    r = client_user.patch(f"/api/v1/me/submissions/{body['id']}/", {"answers": answers}, format="json")
    assert r.status_code == 200 and r.json()["metrics"]["energy"] == 2 and r.json()["edited_at"]
    assert r.json()["metrics"]["note"] == "Slept late"  # the note stays when only answers change
    assert client_user.delete(f"/api/v1/me/submissions/{body['id']}/").status_code == 204  # Undo on the toast
    assert _page(client_user)["daily"]["sent"] is None


def test_undo_is_refused_once_the_coach_has_it(client_user):
    sub = Submission.objects.filter(client__email="riya@example.com", reviewed_at__isnull=False).first()
    r = client_user.delete(f"/api/v1/me/submissions/{sub.id}/")
    assert r.status_code == 400 and Submission.objects.filter(id=sub.id).exists()


def test_send_weekly_with_photos(client_user, photo_week_open):
    d = _page(client_user)
    f = d["weekly"]["form"]
    answers = {_qid(f, "Body weight (kg)"): 68.2, _qid(f, "How was your week?"): 4,
               _qid(f, "Did you follow the meal plan?"): "Yes, all week"}
    photos = {_qid(f, "Progress photos this week?"): {"front": PNG, "back": PNG}}
    r = client_user.post("/api/v1/me/submissions/", {"form": f["id"], "answers": answers, "photos": photos},
                         format="json", HTTP_IDEMPOTENCY_KEY="ck-weekly-1")
    assert r.status_code == 201, r.content
    sub = r.json()
    assert sub["photo_count"] == 2 and sorted(p["pose"] for p in sub["photos"]) == ["back", "front"]
    assert PhotoSet.objects.filter(submission_id=sub["id"]).exists()
    d = _page(client_user)
    assert d["weekly"]["sent"]["id"] == sub["id"] and d["history"][0]["photo_count"] == 2
    sent = d["weekly"]["sent"]  # every answer and photo, for the "sent" summary
    assert sent["answers"][_qid(f, "How was your week?")] == 4
    assert [p["label"] for p in sent["photos"]] == ["Front", "Back"] and sent["photos"][0]["image"].startswith("http")
    bad = {_qid(f, "Progress photos this week?"): ["not a photo"]}
    r = client_user.post("/api/v1/me/submissions/", {"form": f["id"], "answers": answers, "photos": bad},
                         format="json")
    assert r.status_code == 400


def test_board_questions_replace_the_first_template(db):
    weekly = Form.objects.get(name="Weekly check-in")
    texts = [q.text for q in weekly.questions.filter(is_removed=False)]
    assert texts[:3] == ["Body weight (kg)", "How was your week?", "Did you follow the meal plan?"]
    assert Submission.objects.filter(form=weekly).exists()


def test_checkins_page_is_client_only(trainer):
    assert trainer.get("/api/v1/me/checkins/").status_code == 403


def test_photo_question_asks_for_named_photos(client_user, photo_week_open):
    from apps.checkins.models import Question

    d = _page(client_user)
    f = d["weekly"]["form"]
    q = Question.objects.get(id=_qid(f, "Progress photos this week?"))
    q.options = ["Meal", "Label"]
    q.save()
    f = _page(client_user)["weekly"]["form"]
    assert next(x for x in f["questions"] if x["id"] == q.id)["chip"] == "2 photos"
    answers = {_qid(f, "Body weight (kg)"): 68.2, _qid(f, "How was your week?"): 4,
               _qid(f, "Did you follow the meal plan?"): "Yes, all week"}
    r = client_user.post("/api/v1/me/submissions/", {"form": f["id"], "answers": answers,
                                                     "photos": {str(q.id): {"front": PNG}}}, format="json")
    assert r.status_code == 400  # not a photo this question asks for
    r = client_user.post("/api/v1/me/submissions/", {"form": f["id"], "answers": answers,
                                                     "photos": {str(q.id): {"label": PNG, "meal": PNG}}}, format="json")
    assert r.status_code == 201, r.content
    assert [p["label"] for p in r.json()["photos"]] == ["Meal", "Label"]
    assert not PhotoSet.objects.get(submission_id=r.json()["id"]).photos.exists()  # not front / side / back


def test_daily_sent_has_its_answers_for_edit(client_user):
    d = _page(client_user, tab="daily")
    f = d["daily"]["form"]
    if d["daily"]["sent"]:
        client_user.delete(f"/api/v1/me/submissions/{d['daily']['sent']['id']}/")
    answers = {}
    for q in f["questions"]:
        if q["metric"] == "weight":
            answers[str(q["id"])] = 68.0
        elif q["type"] == "scale":
            answers[str(q["id"])] = 3
        elif q["options"]:
            answers[str(q["id"])] = q["options"][0]
    # the card's day: yesterday while it is still open (E27), else today
    r = client_user.post("/api/v1/me/submissions/", {"form": f["id"], "answers": answers, "date": d["daily"]["date"]},
                         format="json")
    assert r.status_code == 201, r.content
    page = _page(client_user, tab="daily")
    # sent for yesterday, the card moves on to today; the answers are on the sent check-in
    sent = page["daily"]["sent"] if page["daily"]["date"] == d["daily"]["date"] else \
        client_user.get(f"/api/v1/me/submissions/{r.json()['id']}/").json()
    if "answers" in sent and isinstance(sent["answers"], list):
        sent = {"answers": {str(a["question"]): a["value"] for a in sent["answers"] if a.get("value") is not None}}
    assert sent["answers"] == {k: v for k, v in answers.items()}


def _daily_answers(f):
    return {_qid(f, "Morning weight"): 68.3, _qid(f, "Sleep last night"): "6.5 h", _qid(f, "Energy"): 4,
            _qid(f, "Mood"): 4, _qid(f, "Hunger"): 3, _qid(f, "Soreness"): 2}


def test_daily_checkin_rings_the_coach_bell_only(client_user, django_capture_on_commit_callbacks):
    """Daily check-in → the trainer's bell (in-app, live toast), no push / email, not the admin. Undo removes it."""
    from apps.notifications.models import Delivery, Notification

    f = _page(client_user)["daily"]["form"]
    with django_capture_on_commit_callbacks(execute=True):
        r = client_user.post("/api/v1/me/submissions/", {"form": f["id"], "answers": _daily_answers(f)}, format="json")
    assert r.status_code == 201, r.content
    sid = r.json()["id"]
    n = Notification.objects.get(event="checkin_submitted", data__submission=sid)
    assert n.recipient.email == "aman@trainwithvimal.com" and n.in_app
    assert n.title == "Riya Sharma sent their daily check-in" and "Weight 68.3 kg" in n.body
    assert n.data["route"] == f"/checkins/{sid}"
    assert not Delivery.objects.filter(notification=n).exists()
    assert Notification.objects.filter(data__submission=sid).count() == 1  # not the admin
    assert client_user.delete(f"/api/v1/me/submissions/{sid}/").status_code == 204
    assert not Notification.objects.filter(data__submission=sid).exists()


def test_daily_checkin_bell_follows_the_new_checkin_switch(client_user, trainer):
    from apps.notifications.models import Notification

    trainer.put("/api/v1/trainers/me/notifications/", {"new_checkin": False}, format="json")
    f = _page(client_user)["daily"]["form"]
    r = client_user.post("/api/v1/me/submissions/", {"form": f["id"], "answers": _daily_answers(f)}, format="json")
    assert r.status_code == 201
    assert not Notification.objects.filter(data__submission=r.json()["id"]).exists()


def test_review_with_a_reply_tells_the_client(trainer):
    from apps.notifications.models import Notification

    subs = Submission.objects.filter(client__email="riya@example.com", reviewed_at__isnull=True)
    a, b = subs[0], subs[1]
    before = Notification.objects.filter(recipient__email="riya@example.com").count()
    assert trainer.post(f"/api/v1/checkins/{a.id}/review/", {"reply": "Good job"}, format="json").status_code == 200
    n = Notification.objects.filter(recipient__email="riya@example.com").order_by("-created_at").first()
    assert n.title == "Coach Aman Verma replied" and n.in_app and n.data["route"] == f"/checkins/{a.id}"
    # Mark reviewed with no reply: nothing to read, so no notification.
    assert trainer.post(f"/api/v1/checkins/{b.id}/review/", {}, format="json").status_code == 200
    assert Notification.objects.filter(recipient__email="riya@example.com").count() == before + 1


def test_form_answers_show_the_photos_to_the_coach(client_user, admin, photo_week_open):
    """Phase 2: the admin's form answers listed photo answers as the word "Photo"; now they carry the pictures."""
    from apps.accounts.models import User
    from apps.checkins.models import Question

    f = _page(client_user)["weekly"]["form"]
    q = Question.objects.get(id=_qid(f, "Progress photos this week?"))
    answers = {_qid(f, "Body weight (kg)"): 68.2, _qid(f, "How was your week?"): 4,
               _qid(f, "Did you follow the meal plan?"): "Yes, all week"}
    r = client_user.post("/api/v1/me/submissions/", {"form": f["id"], "answers": answers,
                                                     "photos": {str(q.id): {"front": PNG, "side": PNG, "back": PNG}}},
                         format="json")
    assert r.status_code == 201, r.content
    riya = User.objects.get(email="riya@example.com")
    d = admin.get(f"/api/v1/clients/{riya.id}/forms/sub:{r.json()['id']}/").json()
    assert [p["label"] for p in d["photos"]] == ["Front", "Side", "Back"]
    assert all("/media/answers/" in p["url"] for p in d["photos"])
    assert sum(1 for x in d["sections"][0]["rows"] if x.get("photo")) == 3


def test_sent_form_shows_its_photos_to_the_client(client_user, admin):
    """Phase 2: the client's filled form said "Sent" for each photo; now it has the pictures."""
    from apps.accounts.models import User
    from apps.checkins.models import Form, FormRequest, Question

    riya = User.objects.get(email="riya@example.com")
    f = Form.objects.create(name="Photo form", type="survey", status="published")
    q = Question.objects.create(form=f, order=1, text="Your photos", type="photo", options=["Front", "Side", "Back"])
    req = FormRequest.objects.create(form=f, client=riya)
    r = client_user.post("/api/v1/me/submissions/", {"request": str(req.id), "answers": {},
                                                     "photos": {str(q.id): {"front": PNG, "side": PNG, "back": PNG}}},
                         format="json")
    assert r.status_code == 201, r.content
    d = client_user.get(f"/api/v1/me/forms/{req.id}/").json()
    assert [p["label"] for p in d["submission"]["photos"]] == ["Front", "Side", "Back"]
    assert all("/media/answers/" in p["image"] for p in d["submission"]["photos"])


def test_daily_form_does_not_swap_when_another_published_form_is_edited(client_user, admin):
    """E30: two published daily forms; the builder's autosave on the older one must not make it the live one."""
    from apps.checkins.library import live_form, save_builder
    from apps.checkins.models import Form, Question

    old = live_form("daily")
    new = Form.objects.create(name="Evening check-in", type="daily", status="published")
    Question.objects.create(form=new, order=0, text="Steps today", type="number")
    assert live_form("daily").id == new.id
    save_builder(old, [{"id": q.id, "text": q.text, "type": q.type} for q in old.questions.all()])  # autosave
    d = client_user.get("/api/v1/me/checkins/").json()
    assert d["daily"]["form"]["id"] == str(new.id)
    assert [q["text"] for q in d["daily"]["form"]["questions"]] == ["Steps today"]


def test_daily_accepts_multiple_choice_and_other(client_user):
    """E30: a multiple choice (list) and an "Other: …" answer go through on the daily check-in."""
    from apps.checkins.library import live_form
    from apps.checkins.models import Question

    f = live_form("daily")
    m = Question.objects.create(form=f, order=20, text="Ate today", type="multiple", options=["Eggs", "Rice"],
                                allow_other=True)
    s = Question.objects.create(form=f, order=21, text="Trained", type="single", options=["Gym", "Home"],
                                allow_other=True)
    d = client_user.get("/api/v1/me/checkins/").json()["daily"]["form"]
    answers = {}
    for q in d["questions"]:
        if q["type"] == "number":
            answers[str(q["id"])] = 70.2
        elif q["type"] == "scale":
            answers[str(q["id"])] = 3
        elif q["type"] in ("single", "dropdown") and q["options"]:
            answers[str(q["id"])] = q["options"][0]
    answers[str(m.id)] = ["Eggs", "Other: Paneer"]
    answers[str(s.id)] = "Other: Walk"
    r = client_user.post("/api/v1/me/submissions/", {"form": d["id"], "answers": answers}, format="json")
    assert r.status_code == 201, r.content


def test_weekly_opens_on_its_schedule_day_for_three_days(client_user):
    """E23: the weekly check-in comes from the client's schedule, opens on its day and stays open 2 more days."""
    from datetime import timedelta

    from django.utils import timezone

    from apps.accounts.models import User
    from apps.checkins import schedule
    from apps.checkins.models import Form, FormSchedule

    riya = User.objects.get(email="riya@example.com")
    today = timezone.localdate()
    weekly = Form.objects.filter(type="weekly").first()
    # due tomorrow: locked today
    FormSchedule.objects.create(client=riya, form=weekly, repeat="week", weekday=(today.weekday() + 1) % 7, time="09:00")
    cur = schedule.current(riya, today)
    assert cur["due"] == today + timedelta(days=1) and not cur["open"]
    d = client_user.get("/api/v1/me/checkins/").json()["weekly"]
    assert d["open"] is False
    r = client_user.post("/api/v1/me/submissions/", {"form": d["form"]["id"], "answers": {}}, format="json")
    assert r.status_code == 400 and "opens on" in r.json()["error"]["message"]
    # two days after the due day it is still open, the day after that it is not
    assert schedule.current(riya, today + timedelta(days=3))["open"]
    nxt = schedule.current(riya, today + timedelta(days=4))
    assert not nxt["open"] and nxt["due"] == today + timedelta(days=8)


def test_daily_is_open_today_and_tomorrow_only(client_user):
    """E27: a day's daily check-in can be sent that day or the next, not later."""
    from datetime import timedelta

    from django.utils import timezone

    f = client_user.get("/api/v1/me/checkins/").json()["daily"]["form"]
    today = timezone.localdate()
    old = client_user.post("/api/v1/me/submissions/", {"form": f["id"], "answers": {},
                                                       "date": (today - timedelta(days=2)).isoformat()}, format="json")
    assert old.status_code == 400


def test_daily_strip_picks_a_day_and_older_days_are_view_only(client_user):
    """E36 / E37 (Probid 2026-11-04): a week strip like Food; today and yesterday can be filled or edited,
    older days only viewed."""
    today = timezone.localdate()
    d = _page(client_user)["daily"]
    assert len(d["strip"]) == 14 and d["editable"] is True
    assert {x["date"] for x in d["strip"]} >= {str(today), str(today - timedelta(days=1))}

    old = today - timedelta(days=3)
    o = _page(client_user, day=str(old))["daily"]
    assert o["date"] == str(old) and o["editable"] is False and o["is_yesterday"] is False
    y = _page(client_user, day=str(today - timedelta(days=1)))["daily"]
    assert y["editable"] is True and y["is_yesterday"] is True
    assert _page(client_user, day=str(today + timedelta(days=2)))["daily"]["date"] == str(today)  # no future


def test_an_old_daily_check_in_cannot_be_edited(client_user):
    riya = Submission.objects.filter(client__email="riya@example.com").first().client
    f = Form.objects.filter(type="daily").first()
    today = timezone.localdate()
    old = Submission.objects.create(client=riya, form=f, form_type="daily", date=today - timedelta(days=3))
    r = client_user.patch(f"/api/v1/me/submissions/{old.id}/", {"answers": {}}, format="json")
    assert r.status_code == 400


def test_form_description_shows_on_the_client_card(client_user, admin):
    """Probid 2026-11-04: the builder's Description shows on the client's Daily / Weekly card; empty = nothing."""
    from apps.checkins.library import live_form

    f = live_form("daily")
    r = admin.patch(f"/api/v1/forms/{f.id}/", {"description": "  Two minutes,   every morning. "}, format="json")
    assert r.status_code == 200, r.content
    assert r.json()["description"] == "Two minutes, every morning."
    assert _page(client_user)["daily"]["form"]["description"] == "Two minutes, every morning."
    admin.patch(f"/api/v1/forms/{f.id}/", {"description": ""}, format="json")
    assert _page(client_user)["daily"]["form"]["description"] == ""


def test_check_ins_and_home_open_on_today_even_with_yesterday_unsent(client_user):
    """Probid 2026-11-04: the daily check-in shows today by default (Check-ins page and Home); yesterday only
    when it is picked on the strip."""
    today = timezone.localdate()
    Submission.objects.filter(client__email="riya@example.com", form_type="daily",
                              date=today - timedelta(days=1)).delete()
    d = _page(client_user)["daily"]
    assert d["date"] == str(today) and d["is_yesterday"] is False
    assert _page(client_user, day=str(today))["daily"]["date"] == str(today)
    home = client_user.get("/api/v1/me/home/").json()["checkin_today"]
    assert home["date"] == str(today) and home["is_yesterday"] is False
