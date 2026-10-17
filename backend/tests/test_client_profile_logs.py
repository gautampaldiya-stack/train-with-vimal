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


def test_compare_works_with_one_plan_using_dates_and_plan_halves(trainer):
    riya = _riya()
    cur = ProgramAssignment.objects.filter(client=riya).order_by("-start_date").first()
    today = timezone.localdate()
    q = {"a_from": str(today - timedelta(days=59)), "a_to": str(today - timedelta(days=30)),
         "b_from": str(today - timedelta(days=29)), "b_to": str(today)}
    d = trainer.get(_url("logs/compare/"), q).json()
    assert d["a"]["from"] == q["a_from"] and d["b"]["to"] == q["b_to"]
    assert d["a"]["id"] is None and "workouts" in d["b"] and "4 weeks" in d["a"]["sub"]
    # a plan against a period: plan:<id> on one side, dates on the other
    d = trainer.get(_url("logs/compare/"), {"a": f"plan:{cur.id}", "b_from": str(today - timedelta(days=6)),
                                            "b_to": str(today)}).json()
    assert d["a"]["id"] == str(cur.id) and d["b"]["from"] == str(today - timedelta(days=6))
    bad = trainer.get(_url("logs/compare/"), {"a_from": str(today), "a_to": str(today - timedelta(days=3)),
                                              "b": str(cur.id)})
    assert bad.status_code == 400 and "a" in bad.json()["error"]["fields"]


def test_bodyweight_sets_count_towards_volume(trainer):
    from decimal import Decimal

    from apps.checkins.models import WeightLog
    from apps.training.models import Exercise, SetLog, WorkoutLog
    from apps.training.services import body_weights, set_volume

    riya = _riya()
    day = timezone.localdate() - timedelta(days=2)
    WeightLog.objects.filter(client=riya, date__gte=day - timedelta(days=3)).delete()
    WeightLog.objects.update_or_create(client=riya, date=day - timedelta(days=3), defaults={"weight_kg": Decimal("60.0")})
    WeightLog.objects.create(client=riya, date=day + timedelta(days=1), weight_kg=Decimal("70.0"))  # after: not used
    ex = Exercise.objects.filter(log_type="bodyweight_reps").first() or Exercise.objects.first()
    w = WorkoutLog.objects.create(client=riya, date=day, name="Core", status="completed", sets_done=3, sets_planned=3)
    SetLog.objects.bulk_create([
        SetLog(workout=w, exercise=ex, set_number=1, reps=10, is_bodyweight=True, done=True),
        SetLog(workout=w, exercise=ex, set_number=2, reps=10, weight_kg=Decimal("5"), is_bodyweight=True, done=True),
        SetLog(workout=w, exercise=ex, set_number=3, reps=10, is_bodyweight=True, is_warmup=True, done=True),
    ])
    assert body_weights(riya.id)(day) == 60.0
    s1, s2, s3 = SetLog.objects.filter(workout=w).order_by("set_number")
    assert set_volume(s1, 60) == 600 and set_volume(s2, 60) == 650 and set_volume(s3, 60) == 0
    one = trainer.get(_url(f"workouts/{w.id}/")).json()
    assert [s["volume"] for s in sorted(one["sets"], key=lambda s: s["set_number"])] == [600, 650, 0]
    rows = trainer.get(_url("workouts/"), {"range": "7d", "page_size": 50}).json()["results"]
    assert next(r for r in rows if r["id"] == str(w.id))["volume"] == 1250


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
