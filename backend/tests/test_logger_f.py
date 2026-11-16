"""Tracker F (new Strong-style logger, 2026-11-16): set types, RPE, cardio BPM, focus metric, added-set segments."""
from apps.training.models import ClientExercisePref, Exercise, ProgramExercise, SetLog, WorkoutLog

W = "/api/v1/me/workouts/"


def _start(c):
    WorkoutLog.objects.filter(client__email="riya@example.com", status="in_progress").delete()
    r = c.post(W, {"name": "Logger F"}, format="json")
    assert r.status_code == 201, r.content
    return r.json()["id"]


def test_set_types_rpe_and_volume(client_user):
    wid = _start(client_user)
    rdl = Exercise.objects.get(name="Romanian Deadlift", is_builtin=True)
    e = str(rdl.id)
    rows = [
        {"key": "w", "exercise": e, "set_number": 1, "weight_kg": "20", "reps": 10, "set_type": "warmup", "done": True},
        {"key": "n", "exercise": e, "set_number": 2, "weight_kg": "60", "reps": 8, "rpe": "8.5", "done": True},
        {"key": "d", "exercise": e, "set_number": 3, "weight_kg": "40", "reps": 12, "set_type": "drop", "done": True},
        {"key": "f", "exercise": e, "set_number": 4, "weight_kg": "60", "reps": 5, "set_type": "failure", "done": True},
    ]
    r = client_user.put(f"{W}{wid}/state/", {"sets": rows}, format="json")
    assert r.status_code == 200, r.content
    by = {s["client_key"]: s for s in r.json()["sets"]}
    assert by["w"]["set_type"] == "warmup" and by["w"]["is_warmup"] is True
    assert by["d"]["set_type"] == "drop" and by["d"]["is_warmup"] is False
    assert float(by["n"]["rpe"]) == 8.5
    # warm-up never counts; drop and failure sets count like work sets: 60×8 + 40×12 + 60×5 = 1260
    assert by["w"]["volume"] == 0 and sum(s["volume"] for s in by.values()) == 480 + 480 + 300


def test_old_app_is_warmup_still_works(client_user):
    wid = _start(client_user)
    rdl = Exercise.objects.get(name="Romanian Deadlift", is_builtin=True)
    rows = [{"key": "o", "exercise": str(rdl.id), "set_number": 1, "weight_kg": "20", "reps": 5, "is_warmup": True}]
    r = client_user.put(f"{W}{wid}/state/", {"sets": rows}, format="json")
    assert r.json()["sets"][0]["set_type"] == "warmup"
    s = SetLog.objects.get(workout_id=wid)
    s.is_warmup = True
    s.set_type = "normal"
    s.save()
    s.refresh_from_db()
    assert s.set_type == "warmup" and s.is_warmup


def test_bad_values_are_refused(client_user):
    wid = _start(client_user)
    rdl = Exercise.objects.get(name="Romanian Deadlift", is_builtin=True)
    for bad in ({"set_type": "superset"}, {"rpe": "11"}, {"bpm": 20}, {"bpm": 300}):
        row = {"key": "x", "exercise": str(rdl.id), "set_number": 1, **bad}
        r = client_user.put(f"{W}{wid}/state/", {"sets": [row]}, format="json")
        assert r.status_code == 400, bad
        assert "error" in r.json()


def test_cardio_bpm_and_coach_range(client_user, trainer):
    pe = ProgramExercise.objects.filter(exercise__log_type="distance").select_related("day__week__program").first()
    if pe is None:  # demo plan without cardio: give one exercise a cardio slot
        pe = ProgramExercise.objects.select_related("day__week__program").first()
        pe.exercise.log_type = "distance"
        pe.exercise.save(update_fields=["log_type"])
    pe.bpm_min, pe.bpm_max = 120, 140
    pe.save(update_fields=["bpm_min", "bpm_max"])
    wid = _start(client_user)
    row = {"key": "c", "exercise": str(pe.exercise_id), "set_number": 1, "seconds": 1200, "bpm": 132, "done": True}
    WorkoutLog.objects.filter(id=wid).update(program_day=pe.day)
    row["program_exercise"] = pe.id
    r = client_user.put(f"{W}{wid}/state/", {"sets": [row]}, format="json")
    s = r.json()["sets"][0]
    assert s["bpm"] == 132 and s["bpm_target"] == [120, 140] and s["volume"] == 0  # cardio never adds volume


def test_bpm_range_must_be_in_order(db):
    from apps.training.serializers import ProgramExerciseSerializer

    pe = ProgramExercise.objects.first()
    ser = ProgramExerciseSerializer(pe, data={"bpm_min": 150, "bpm_max": 120}, partial=True)
    assert not ser.is_valid() and "bpm_max" in ser.errors


def test_focus_metric_saved_per_exercise(client_user, trainer):
    rdl = Exercise.objects.get(name="Romanian Deadlift", is_builtin=True)
    url = f"/api/v1/me/exercise-prefs/{rdl.id}/"
    assert client_user.put(url, {"focus_metric": "nope"}, format="json").status_code == 400
    for _ in range(2):  # safe to send again
        r = client_user.put(url, {"focus_metric": "reps"}, format="json")
        assert r.status_code == 200 and r.json()["focus_metric"] == "reps"
    assert ClientExercisePref.objects.filter(exercise=rdl).count() == 1
    assert trainer.put(url, {"focus_metric": "reps"}, format="json").status_code == 403


def test_train_gives_focus_metric_and_last_performed(client_user):
    d = client_user.get("/api/v1/me/train/").json()
    assert "last_performed" in d
    for e in d["exercises"]:
        assert e["focus_metric"] in {"volume", "volume_increase", "reps", "weight_reps"}
        for s in e["last_time"] or []:
            assert {"type", "rpe", "bpm", "date"} <= set(s)


def test_segments_add_up_after_log_more(client_user):
    wid = _start(client_user)
    plank = Exercise.objects.get(name="Plank", is_builtin=True)
    one = {"key": "s1", "exercise": str(plank.id), "set_number": 1, "seconds": 45, "done": True}
    client_user.put(f"{W}{wid}/state/", {"sets": [one]}, format="json")
    client_user.post(f"{W}{wid}/finish/", {"duration_seconds": 720, "time_breakdown": {"active": 600, "rest": 120,
                                                                                         "pe:1": 300}}, format="json")
    client_user.post(f"{W}{wid}/reopen/")
    two = {**one, "key": "s2", "set_number": 2}
    client_user.put(f"{W}{wid}/state/", {"sets": [one, two]}, format="json")
    r = client_user.post(f"{W}{wid}/finish/", {"duration_seconds": 240, "time_breakdown": {"active": 200, "rest": 40,
                                                                                             "pe:1": 120}}, format="json")
    d = r.json()
    assert d["duration_seconds"] == 960  # 12 min + 4 min = 16 min
    assert [s["seconds"] for s in d["segments"]] == [720, 240]
    assert d["time_breakdown"]["pe:1"] == 420 and d["time_breakdown"]["rest"] == 160
    row = next(x for x in client_user.get(W).json()["results"] if x["id"] == wid)
    assert row["duration_seconds"] == 960


def test_another_clients_workout_is_hidden(client_user, db):
    from apps.accounts.models import User

    other = User.objects.filter(role="client").exclude(email="riya@example.com").first()
    if other is None:
        return
    w = WorkoutLog.objects.create(client=other, name="Not mine")
    assert client_user.put(f"{W}{w.id}/state/", {"sets": []}, format="json").status_code == 404
