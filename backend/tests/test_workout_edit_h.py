"""Tracker H (Probid 18 Nov): edit a finished workout (versions, recalculation, coach sees it) and log yesterday's
missed workout afterwards."""
from datetime import timedelta

from django.utils import timezone

from apps.training.models import Exercise, WorkoutEdit, WorkoutLog

W = "/api/v1/me/workouts/"


def _finished(c, rows):
    WorkoutLog.objects.filter(client__email="riya@example.com", status="in_progress").delete()
    r = c.post(W, {"name": "Edit H"}, format="json")
    wid = r.json()["id"]
    r = c.put(f"{W}{wid}/state/", {"sets": rows}, format="json")
    assert r.status_code == 200, r.content
    r = c.post(f"{W}{wid}/finish/", {"duration_seconds": 1800}, format="json")
    assert r.status_code == 200, r.content
    return r.json()


def _rdl():
    return str(Exercise.objects.get(name="Romanian Deadlift", is_builtin=True).id)


def test_edit_sets_and_time_makes_a_version(client_user):
    e = _rdl()
    w = _finished(client_user, [
        {"key": "a", "exercise": e, "set_number": 1, "weight_kg": "60", "reps": 8, "done": True},
        {"key": "b", "exercise": e, "set_number": 2, "weight_kg": "60", "reps": 8, "done": True},
    ])
    end = timezone.now() - timedelta(minutes=5)
    start = end - timedelta(minutes=50)
    sets = [{"id": s["id"], "exercise": e, "set_number": s["set_number"], "weight_kg": "65", "reps": 8}
            for s in w["sets"]]
    sets.append({"key": "new", "exercise": e, "set_number": 3, "weight_kg": "50", "reps": 10, "set_type": "drop",
                 "rest_seconds": 60})
    r = client_user.put(f"{W}{w['id']}/edit/", {"started_at": start.isoformat(), "finished_at": end.isoformat(),
                                               "sets": sets}, format="json")
    assert r.status_code == 200, r.content
    d = r.json()
    assert d["duration_seconds"] == 3000 and d["sets_done"] == 3
    assert {float(s["weight_kg"]) for s in d["sets"]} == {65.0, 50.0}
    # 65×8 + 65×8 + 50×10: volume worked out again from the new values
    assert sum(s["volume"] for s in d["sets"]) == 520 + 520 + 500
    new = next(s for s in d["sets"] if s["set_number"] == 3)
    assert new["set_type"] == "drop" and new["rest_seconds"] == 60
    assert d["edits"][0]["number"] == 1
    assert "Start and end time" in d["edits"][0]["changes"]
    assert any("2 → 3 sets" in c for c in d["edits"][0]["changes"])
    # the old values are kept as the earlier version
    ed = WorkoutEdit.objects.get(workout_id=w["id"])
    assert {float(s["weight_kg"]) for s in ed.before["sets"]} == {60.0}
    # the history row says it was edited
    rows = client_user.get(W).json()["results"]
    assert next(x for x in rows if x["id"] == w["id"])["edited"] == 1


def test_edit_without_time_change_keeps_the_time(client_user):
    e = _rdl()
    w = _finished(client_user, [{"key": "a", "exercise": e, "set_number": 1, "weight_kg": "60", "reps": 8,
                                 "done": True}])
    wl = WorkoutLog.objects.get(id=w["id"])
    start = wl.finished_at - timedelta(seconds=wl.duration_seconds)
    r = client_user.put(f"{W}{w['id']}/edit/", {
        "started_at": start.isoformat(), "finished_at": wl.finished_at.isoformat(),
        "sets": [{"id": w["sets"][0]["id"], "exercise": e, "set_number": 1, "weight_kg": "60", "reps": 9}]},
        format="json")
    assert r.status_code == 200, r.content
    assert r.json()["duration_seconds"] == 1800
    assert r.json()["edits"][0]["changes"] == ["Romanian Deadlift: sets changed"]


def test_bad_times_and_open_workouts_are_refused(client_user):
    e = _rdl()
    w = _finished(client_user, [{"key": "a", "exercise": e, "set_number": 1, "weight_kg": "60", "reps": 8,
                                 "done": True}])
    now = timezone.now()
    for start, end in ((now - timedelta(minutes=10), now - timedelta(minutes=20)),
                       (now - timedelta(minutes=10), now + timedelta(hours=1))):
        r = client_user.put(f"{W}{w['id']}/edit/", {"started_at": start.isoformat(), "finished_at": end.isoformat(),
                                                   "sets": []}, format="json")
        assert r.status_code == 400 and "error" in r.json()
    live = client_user.post(W, {"name": "Running"}, format="json").json()["id"]
    r = client_user.put(f"{W}{live}/edit/", {"started_at": (now - timedelta(hours=1)).isoformat(),
                                            "finished_at": now.isoformat(), "sets": []}, format="json")
    assert r.status_code == 404


def test_log_yesterday_only(client_user):
    e = _rdl()
    y = timezone.localdate() - timedelta(days=1)
    start = timezone.make_aware(timezone.datetime(y.year, y.month, y.day, 18, 0))
    body = {"date": y.isoformat(), "name": "Missed", "started_at": start.isoformat(),
            "finished_at": (start + timedelta(minutes=40)).isoformat(),
            "sets": [{"key": "p1", "exercise": e, "set_number": 1, "weight_kg": "40", "reps": 10}]}
    r = client_user.post(f"{W}past/", body, format="json")
    assert r.status_code == 201, r.content
    d = r.json()
    assert d["status"] == "completed" and d["date"] == y.isoformat() and d["duration_seconds"] == 2400
    assert d["sets_done"] == 1
    # older days can not be logged afterwards
    old = y - timedelta(days=1)
    r = client_user.post(f"{W}past/", {**body, "date": old.isoformat()}, format="json")
    assert r.status_code == 400
    # the start must be on that day
    r = client_user.post(f"{W}past/", {**body, "name": "Again", "started_at": timezone.now().isoformat()},
                         format="json")
    assert r.status_code == 400


def test_coach_sees_the_edit(client_user, trainer):
    e = _rdl()
    w = _finished(client_user, [{"key": "a", "exercise": e, "set_number": 1, "weight_kg": "60", "reps": 8,
                                 "done": True}])
    wl = WorkoutLog.objects.get(id=w["id"])
    client_user.put(f"{W}{w['id']}/edit/", {
        "started_at": (wl.finished_at - timedelta(seconds=wl.duration_seconds)).isoformat(),
        "finished_at": wl.finished_at.isoformat(), "sets": []}, format="json")
    r = trainer.get(f"/api/v1/clients/{wl.client_id}/workouts/{wl.id}/")
    assert r.status_code == 200, r.content
    assert r.json()["edits"][0]["changes"] == ["Romanian Deadlift: removed"]


def test_older_workouts_can_not_be_edited(client_user):
    e = _rdl()
    w = _finished(client_user, [{"key": "a", "exercise": e, "set_number": 1, "weight_kg": "60", "reps": 8,
                                 "done": True}])
    old = timezone.localdate() - timedelta(days=3)
    WorkoutLog.objects.filter(id=w["id"]).update(date=old)
    start = timezone.make_aware(timezone.datetime(old.year, old.month, old.day, 18, 0))
    r = client_user.put(f"{W}{w['id']}/edit/", {"started_at": start.isoformat(),
                                               "finished_at": (start + timedelta(minutes=30)).isoformat(),
                                               "sets": []}, format="json")
    assert r.status_code == 400


def test_edit_page_gets_previous_and_history_card(client_user):
    e = _rdl()
    _finished(client_user, [{"key": "a", "exercise": e, "set_number": 1, "weight_kg": "50", "reps": 8, "done": True}])
    w = _finished(client_user, [{"key": "b", "exercise": e, "set_number": 1, "weight_kg": "60", "reps": 6, "done": True}])
    r = client_user.get(f"{W}{w['id']}/edit/")
    assert r.status_code == 200, r.content
    d = r.json()
    assert d["workout"]["id"] == w["id"]
    # PREVIOUS = the workout before this one, never itself
    assert float(d["previous"][e][0]["weight_kg"]) == 50.0
    row = next(x for x in client_user.get(W).json()["results"] if x["id"] == w["id"])
    assert row["summary"] == [{"name": "Romanian Deadlift", "sets": 1, "best": "60 kg × 6"}]
    assert row["volume"] == 360 and row["started_at"]
