"""Client profile → History tab (clients/<id>/history/) and Activity tab (activity/?client=<id>)."""
from datetime import timedelta

from django.utils import timezone

from apps.accounts.models import User
from tests.conftest import login


def _riya():
    return User.objects.get(email="riya@example.com")


def _body(r):
    return b"".join(r.streaming_content if hasattr(r, "streaming_content") else [r.content]).decode()


def test_history_has_every_part_of_the_board(trainer):
    r = trainer.get(f"/api/v1/clients/{_riya().id}/history/")
    assert r.status_code == 200, r.content
    d = r.json()
    s = d["summary"]
    for k in ("joined", "duration", "start_weight", "current_weight", "weight_change", "workouts_done",
              "workouts_planned", "best_streak", "checkins_sent", "checkins_expected", "checkins_missed"):
        assert k in s
    assert s["workouts_done"] <= s["workouts_planned"] and s["checkins_sent"] <= s["checkins_expected"]
    assert [row["label"] for row in d["timeline"]["rows"]] == ["Trainer", "Workout", "Meal plan", "Supplements",
                                                               "Habits"]
    trainer_bars = d["timeline"]["rows"][0]["bars"]
    assert trainer_bars[-1]["label"] == "Aman Verma" and trainer_bars[-1]["status"] == "cur"
    assert all(b["status"] in ("cur", "done", "old", "next") and b["tip"] for row in d["timeline"]["rows"]
               for b in row["bars"])
    assert d["timeline"]["from"] <= d["timeline"]["today"] <= d["timeline"]["to"]
    assert 1 <= len(d["months"]) <= 4 and d["more"] == (d["total_months"] > 4)
    for m in d["months"]:
        assert m["label"] and m["items"]
        assert all(i["group"] in ("plans", "miles", "checks", "health", "acct") and i["title"] and i["who"]
                   for i in m["items"])
    assert [a["label"] for a in d["about"]] == ["Joined", "Came from", "Goal", "Goal weight", "Target date",
                                                "Trainer"]
    assert d["health"] and d["health"][-1]["title"] == "Food"
    # Joined is the oldest line of the journey.
    every = trainer.get(f"/api/v1/clients/{_riya().id}/history/", {"months": 99}).json()
    assert every["months"][-1]["items"][-1]["title"] == "Joined Train With Vimal"


def test_history_milestones_and_chips(trainer):
    rid = _riya().id
    every = trainer.get(f"/api/v1/clients/{rid}/history/", {"months": 99}).json()
    items = [i for m in every["months"] for i in m["items"]]
    # Riya started at 72 kg and is under 69 kg in the demo: the whole kilos lost are milestones.
    assert any(i["title"] == "Lost 2 kg since joining" and i["badge"] == "Milestone" for i in items)
    assert any(i["title"].startswith("Started ") and i["badge"] == "Workout" for i in items)
    for g in ("plans", "miles", "checks", "acct"):
        only = trainer.get(f"/api/v1/clients/{rid}/history/", {"group": g, "months": 99}).json()
        got = [i for m in only["months"] for i in m["items"]]
        assert got and all(i["group"] == g for i in got)
        assert len(got) == len([i for i in items if i["group"] == g])


def test_goal_weight_change_shows_in_history(trainer, django_capture_on_commit_callbacks):
    rid = _riya().id
    with django_capture_on_commit_callbacks(execute=True):
        r = trainer.patch(f"/api/v1/clients/{rid}/", {"target_weight_kg": "60"}, format="json")
        assert r.status_code == 200, r.content
    d = trainer.get(f"/api/v1/clients/{rid}/history/", {"group": "miles"}).json()
    assert any(i["title"] == "Goal weight changed" and i["detail"] == "62 kg became 60 kg." and i["badge"] == "Goal"
               for i in d["months"][0]["items"])
    gw = next(a["value"] for a in d["about"] if a["label"] == "Goal weight")
    assert gw.startswith("60 kg · was 62 kg until ")


def test_history_is_only_for_own_clients(trainer):
    other = User.objects.get(email="ananya@example.com")  # Neha's client
    assert trainer.get(f"/api/v1/clients/{other.id}/history/").status_code == 404


def test_history_export_is_a_csv_of_the_journey(trainer):
    r = trainer.get(f"/api/v1/clients/{_riya().id}/history/", {"export": "csv"})
    assert r.status_code == 200 and r["Content-Type"].startswith("text/csv")
    lines = _body(r).strip().splitlines()
    assert lines[0] == "Month,Date,Type,What,Details,Who"
    assert any("Joined Train With Vimal" in ln for ln in lines[1:])


def test_client_activity_feed_and_counts_for_trainer(trainer):
    rid = str(_riya().id)
    r = trainer.get("/api/v1/activity/", {"client": rid, "range": "all", "page_size": 8})
    assert r.status_code == 200, r.content
    rows = r.json()["results"]
    assert rows and len(rows) <= 8 and all(x["client"] == rid for x in rows)
    c = trainer.get("/api/v1/activity/counts/", {"client": rid, "range": "all", "kind": "workout"}).json()
    for k in ("workout", "meal", "checkin", "body", "plan", "content", "all"):
        assert k in c
    assert c["all"] == sum(v for k, v in c.items() if k != "all")
    only = trainer.get("/api/v1/activity/", {"client": rid, "range": "all", "kind": "checkin", "page_size": 100})
    assert len(only.json()["results"]) == min(c["checkin"], 100)
    today = trainer.get("/api/v1/activity/counts/", {"client": rid, "range": "today"}).json()
    assert today["all"] <= c["all"] and "days" not in today
    days = trainer.get("/api/v1/activity/counts/", {"client": rid, "range": "all", "kind": "checkin",
                                                    "by_day": 1}).json()["days"]
    assert sum(days.values()) == c["checkin"]


def test_trainer_sees_rows_about_their_client_from_before_they_took_over(trainer, admin):
    from apps.activity.models import ActivityEvent

    riya = _riya()
    neha = User.objects.get(email="neha@trainwithvimal.com")
    ActivityEvent.objects.create(actor=riya, actor_label=riya.full_name, kind="workout", verb="finished a workout",
                                 client=riya, trainer=neha, target_label="Old plan day")
    rows = trainer.get("/api/v1/activity/", {"client": str(riya.id), "range": "all", "page_size": 100}).json()
    assert any(x["target_label"] == "Old plan day" for x in rows["results"])
    # …but not about someone else's client.
    other = User.objects.get(email="ananya@example.com")
    ActivityEvent.objects.create(actor=other, actor_label=other.full_name, kind="meal", verb="logged lunch",
                                 client=other, trainer=neha)
    rows = trainer.get("/api/v1/activity/", {"client": str(other.id), "range": "all", "page_size": 100}).json()
    assert all(x["client"] != str(other.id) or x["actor"] == str(User.objects.get(
        email="aman@trainwithvimal.com").id) for x in rows["results"])


def test_weigh_in_and_measurements_show_as_body_rows(client_user, trainer, django_capture_on_commit_callbacks):
    from apps.checkins.models import Measurement, WeightLog

    today = timezone.localdate()
    # A first weigh-in of the day (the demo data may already have one for today, which would make it an edit).
    WeightLog.objects.filter(client=_riya(), date=today).delete()
    Measurement.objects.filter(client=_riya(), date=today).delete()
    with django_capture_on_commit_callbacks(execute=True):
        client_user.post("/api/v1/me/weights/", {"date": today.isoformat(), "weight_kg": 67.9}, format="json")
        client_user.post("/api/v1/me/measurements/", {"date": today.isoformat(), "values": {"waist": 79}},
                         format="json")
    rows = trainer.get("/api/v1/activity/", {"client": str(_riya().id), "kind": "body", "range": "today"}).json()
    verbs = [x["verb"] for x in rows["results"]]
    assert "logged body weight" in verbs and "added measurements" in verbs
    w = next(x for x in rows["results"] if x["verb"] == "logged body weight")
    assert w["change_to"] == "67.9 kg" or w["target_label"] == "67.9 kg"
    m = next(x for x in rows["results"] if x["verb"] == "added measurements")
    assert "Waist 79 cm" in m["meta"]["note"]


def test_past_day_weigh_in_is_a_body_row_too(client_user, trainer, django_capture_on_commit_callbacks):
    day = timezone.localdate() - timedelta(days=2)
    with django_capture_on_commit_callbacks(execute=True):
        client_user.post("/api/v1/me/weights/", {"date": day.isoformat(), "weight_kg": 68.2}, format="json")
    rows = trainer.get("/api/v1/activity/", {"client": str(_riya().id), "kind": "body", "range": "today"}).json()
    assert any(x["verb"].startswith(("added their weight", "changed their weight")) for x in rows["results"])


def test_other_trainer_cannot_read_history(db):
    neha = login("neha@trainwithvimal.com")
    assert neha.get(f"/api/v1/clients/{_riya().id}/history/").status_code == 404
