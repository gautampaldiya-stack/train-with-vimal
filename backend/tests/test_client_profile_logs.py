"""Trainer → Client profile → Logs and Progress tabs (boards TrainerClientProfile / …Mobile)."""
from datetime import timedelta

from django.utils import timezone

from apps.accounts.models import User
from apps.notifications.models import Notification
from apps.training.models import ProgramAssignment


def _riya():
    return User.objects.get(email="riya@example.com")


def _url(path):
    return f"/api/v1/clients/{_riya().id}/{path}"


def test_log_summary_counts_the_range(trainer):
    d = trainer.get(_url("logs/summary/"), {"range": "30d"}).json()
    for k in ("from", "to", "workouts", "meals", "checkins"):
        assert k in d
    week = trainer.get(_url("logs/summary/"), {"range": "7d"}).json()
    assert week["workouts"] <= d["workouts"] and week["meals"] <= d["meals"]


def test_workout_log_pages_and_shows_missed_days(trainer):
    d = trainer.get(_url("workouts/"), {"range": "30d", "page_size": 5}).json()
    assert d["page_size"] == 5 and len(d["results"]) <= 5 and d["count"] >= len(d["results"])
    rows = trainer.get(_url("workouts/"), {"range": "30d", "page_size": 50}).json()["results"]
    assert {r["status"] for r in rows} <= {"done", "partly", "missed", "in_progress"}
    assert [r["date"] for r in rows] == sorted((r["date"] for r in rows), reverse=True)
    done = next(r for r in rows if r["id"])
    one = trainer.get(_url(f"workouts/{done['id']}/")).json()
    assert one["sets"] and "volume" in one["sets"][0]
    for r in rows:
        if r["status"] == "missed":
            assert r["id"] is None and "planned" in r


def test_meal_log_rows_have_targets_and_status(trainer):
    d = trainer.get(_url("food/"), {"range": "30d"}).json()
    assert d["target"]["kcal"] and d["results"]
    r = d["results"][0]
    for k in ("date", "kcal", "protein", "carbs", "fat", "meals_logged", "meals", "status"):
        assert k in r
    day = trainer.get(_url("food/"), {"date": r["date"]}).json()
    assert "meals" in day and "log" in day


def test_daily_and_weekly_checkin_logs_include_missing_ones(trainer):
    daily = trainer.get(_url("checkins/"), {"kind": "daily", "range": "30d"}).json()
    assert "week" in daily and daily["results"]
    assert all(set(r) >= {"date", "sleep", "energy", "mood", "hunger", "steps", "note"} for r in daily["results"])
    weekly = trainer.get(_url("checkins/"), {"kind": "weekly", "range": "90d"}).json()["results"]
    assert weekly and {r["status"] for r in weekly} <= {"to_review", "reviewed", "missed"}
    sent = next(r for r in weekly if r["id"])
    assert "photos" in sent and trainer.get(f"/api/v1/checkins/{sent['id']}/").status_code == 200
    assert trainer.get(_url("checkins/"), {"kind": "monthly"}).status_code == 400


def test_habit_and_supplement_logs(trainer):
    for kind in ("habits", "supps"):
        d = trainer.get(_url("habits/"), {"kind": kind, "range": "7d"}).json()
        assert d["count"] <= 7 and "columns" in d
        for r in d["results"]:
            assert set(r["cells"]) == {c["id"] for c in d["columns"]}
            assert r["done"] == sum(1 for i in r["items"] if i["done"])


def test_progress_has_personal_bests_and_measures(trainer):
    d = trainer.get(_url("progress/")).json()
    for k in ("weights", "measurements", "photo_sets", "goal", "start", "measures", "lifts"):
        assert k in d
    for lift in d["lifts"]:
        assert lift["best"]["kg"] >= lift["start"]["kg"] or lift["best"]["reps"] >= lift["start"]["reps"]


def test_compare_two_plans(trainer):
    riya = _riya()
    cur = ProgramAssignment.objects.filter(client=riya).order_by("-start_date").first()
    old = ProgramAssignment.objects.create(client=riya, program=cur.program, status="ended",
                                           start_date=cur.start_date - timedelta(days=60),
                                           end_date=cur.start_date - timedelta(days=1))
    d = trainer.get(_url("logs/compare/"), {"a": str(old.id), "b": str(cur.id)}).json()
    for side in ("a", "b"):
        for k in ("name", "sub", "workouts", "meals", "checkins", "habits", "supps", "body"):
            assert k in d[side]
    assert d["a"]["to"] < d["b"]["from"] or d["a"]["to"] == str(cur.start_date - timedelta(days=1))
    assert trainer.get(_url("logs/compare/"), {"a": "nope", "b": str(cur.id)}).status_code == 400


def test_comment_reaches_the_client(trainer):
    riya = _riya()
    before = Notification.objects.filter(recipient=riya).count()
    r = trainer.post(_url("logs/comment/"), {"about": "workout", "date": str(timezone.localdate()),
                                             "text": "Nice squat depth"}, format="json")
    assert r.status_code == 201, r.content
    assert Notification.objects.filter(recipient=riya).count() == before + 1
    assert trainer.post(_url("logs/comment/"), {"about": "workout", "text": "  "}, format="json").status_code == 400


def test_other_trainers_client_logs_are_hidden(trainer):
    other = User.objects.filter(role="client").exclude(client_profile__trainer__email="aman@trainwithvimal.com").first()
    if other is None:
        return
    for path in ("logs/summary/", "workouts/", "food/", "checkins/", "habits/", "progress/"):
        assert trainer.get(f"/api/v1/clients/{other.id}/{path}").status_code == 404
