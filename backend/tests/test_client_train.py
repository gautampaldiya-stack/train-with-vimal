from datetime import timedelta

from django.utils import timezone

from apps.training.models import Exercise, SetLog, WorkoutLog

W = "/api/v1/me/workouts/"


def _monday():
    t = timezone.localdate()
    return t - timedelta(days=t.weekday())


def test_train_has_every_part(client_user):
    r = client_user.get(f"/api/v1/me/train/?date={_monday().isoformat()}")
    assert r.status_code == 200, r.content
    d = r.json()
    assert d["program"] and d["week"] and len(d["strip"]) == 7
    assert d["day"]["name"] == "Upper A" and d["day"]["minutes"] > 0 and d["day"]["note"]
    assert d["trainer"]["full_name"] == "Aman Verma" and d["bodyweight_kg"]
    assert d["exercises"] and all("sets_done" in e and "last_time" in e for e in d["exercises"])
    bench = next(e for e in d["exercises"] if e["exercise_full"]["name"] == "Barbell Bench Press")
    assert bench["exercise_full"]["how_to"] and bench["note"]


def test_train_is_client_only(trainer):
    assert trainer.get("/api/v1/me/train/").status_code == 403


def _start(c):
    WorkoutLog.objects.filter(client__email="riya@example.com", status="in_progress").delete()
    r = c.post(W, {"name": "Test workout"}, format="json")
    assert r.status_code == 201, r.content
    return r.json()["id"]


def test_state_save_is_safe_to_repeat(client_user):
    wid = _start(client_user)
    rdl = Exercise.objects.get(name="Romanian Deadlift", is_builtin=True)
    rows = [{"key": "a1", "exercise": str(rdl.id), "set_number": 1, "weight_kg": "62.5", "reps": 8, "done": True},
            {"key": "a2", "exercise": str(rdl.id), "set_number": 2, "weight_kg": "62.5", "reps": 8}]
    now = timezone.now().isoformat()
    for _ in range(2):  # the outbox may send the same save twice
        r = client_user.put(f"{W}{wid}/state/", {"started_at": now, "paused_at": None, "sets": rows}, format="json")
        assert r.status_code == 200, r.content
    assert SetLog.objects.filter(workout_id=wid).count() == 2
    d = r.json()
    first = next(s for s in d["sets"] if s["client_key"] == "a1")
    assert first["done"] and first["done_at"] and first["is_pr"]  # past best was 60 kg

    # a dropped set is deleted; a tick on the kept one stays
    r = client_user.put(f"{W}{wid}/state/", {"sets": rows[:1]}, format="json")
    assert [s["client_key"] for s in r.json()["sets"]] == ["a1"]

    live = client_user.get("/api/v1/me/train/").json()["in_progress"]
    assert live["id"] == wid and live["sets_done"] == 1 and live["sets_total"] == 1


def test_finish_reopen_and_feedback(client_user):
    wid = _start(client_user)
    plank = Exercise.objects.get(name="Plank", is_builtin=True)
    sets = [{"key": "p1", "exercise": str(plank.id), "set_number": 1, "seconds": 45, "done": True},
            {"key": "p2", "exercise": str(plank.id), "set_number": 2, "seconds": 45}]
    client_user.put(f"{W}{wid}/state/", {"sets": sets}, format="json")
    assert client_user.post(f"{W}{wid}/feedback/", {"effort": 7}, format="json").status_code == 404

    r = client_user.post(f"{W}{wid}/finish/", {"duration_seconds": 1500, "time_breakdown": {"active": 900, "rest": 600}},
                         format="json")
    assert r.status_code == 200 and r.json()["status"] == "completed"
    assert r.json()["sets_done"] == 1 and len(r.json()["sets"]) == 1  # the untouched set is dropped

    r = client_user.post(f"{W}{wid}/feedback/", {"effort": 7, "note": "Felt easy today"}, format="json")
    assert r.status_code == 200 and r.json()["effort"] == 7 and r.json()["note"] == "Felt easy today"

    r = client_user.post(f"{W}{wid}/reopen/")
    assert r.status_code == 200 and r.json()["status"] == "in_progress"
    started = timezone.datetime.fromisoformat(r.json()["started_at"])
    assert abs((timezone.now() - started).total_seconds() - 1500) < 30  # the timer goes on from 25:00

    # finishing again keeps the effort and note already sent
    r = client_user.post(f"{W}{wid}/finish/", {"duration_seconds": 1600}, format="json")
    assert r.json()["effort"] == 7 and r.json()["note"] == "Felt easy today"


def test_past_workouts_filter(client_user):
    d = client_user.get(W).json()
    assert d["count"] > 0 and d["since"]
    row = d["results"][0]
    assert {"exercises", "has_pr", "duration_seconds"} <= set(row)
    one = client_user.get(W, {"name": row["name"]}).json()
    assert one["count"] and all(r["name"] == row["name"] for r in one["results"])
    det = client_user.get(f"{W}{row['id']}/").json()
    assert det["sets"] and det["sets"][0]["exercise_name"]


def test_discard_after_log_more_keeps_the_workout(client_user):
    wid = _start(client_user)
    plank = Exercise.objects.get(name="Plank", is_builtin=True)
    one = {"key": "q1", "exercise": str(plank.id), "set_number": 1, "seconds": 45, "done": True}
    client_user.put(f"{W}{wid}/state/", {"sets": [one]}, format="json")
    client_user.post(f"{W}{wid}/finish/", {"duration_seconds": 1200}, format="json")
    client_user.post(f"{W}{wid}/feedback/", {"effort": 6}, format="json")

    r = client_user.post(f"{W}{wid}/reopen/")
    assert r.json()["reopened_at"]
    two = {**one, "key": "q2", "set_number": 2}
    client_user.put(f"{W}{wid}/state/", {"sets": [one, two]}, format="json")
    assert client_user.post(f"{W}{wid}/discard/").status_code == 204

    d = client_user.get(f"{W}{wid}/").json()
    assert d["status"] == "completed" and d["duration_seconds"] == 1200 and d["effort"] == 6
    assert [s["client_key"] for s in d["sets"]] == ["q1"] and d["reopened_at"] is None
