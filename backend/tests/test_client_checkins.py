import base64
from datetime import date, timedelta

from django.utils import timezone

from apps.checkins.models import Form, PhotoSet, Submission

# 1x1 transparent PNG
PNG = "data:image/png;base64," + base64.b64encode(bytes.fromhex(
    "89504e470d0a1a0a0000000d4948445200000001000000010806000000"
    "1f15c4890000000d49444154789c6360000002000154a24f5d0000000049454e44ae426082")).decode()


def _page(c, **params):
    r = c.get("/api/v1/me/checkins/", params)
    assert r.status_code == 200, r.content
    return r.json()


def _qid(form, text):
    return str(next(q["id"] for q in form["questions"] if q["text"] == text))


def test_checkins_page_has_the_board_numbers(client_user):
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


def test_send_weekly_with_photos(client_user):
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


def test_photo_question_asks_for_named_photos(client_user):
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
    r = client_user.post("/api/v1/me/submissions/", {"form": f["id"], "answers": answers}, format="json")
    assert r.status_code == 201, r.content
    sent = _page(client_user, tab="daily")["daily"]["sent"]
    assert sent["answers"] == {k: v for k, v in answers.items()}
