"""Tracker G (rest timers, 2026-11-16): per-exercise rest by set type, per-set rest, coach lock, actual rest."""
from django.utils import timezone

from apps.training import services
from apps.training.models import ClientExercisePref, Exercise, ProgramExercise, SetLog, WorkoutLog

W = "/api/v1/me/workouts/"
P = "/api/v1/me/exercise-prefs/"


def _start(c):
    WorkoutLog.objects.filter(client__email="riya@example.com", status="in_progress").delete()
    r = c.post(W, {"name": "Rest G"}, format="json")
    assert r.status_code == 201, r.content
    return r.json()["id"]


def _riya():
    from django.contrib.auth import get_user_model

    return get_user_model().objects.get(email="riya@example.com")


def _plan_exercise(user):
    pa, _, _, _ = services.today_plan(user, timezone.localdate())
    return ProgramExercise.objects.filter(day__week__program=pa.effective_program).select_related("exercise").first()


def test_client_sets_rest_timers_per_set_type(client_user):
    user = _riya()
    pe = _plan_exercise(user)
    ProgramExercise.objects.filter(exercise=pe.exercise).update(rest_locked=False)
    r = client_user.put(f"{P}{pe.exercise_id}/", {"rest_work": 150, "rest_warmup": 45, "rest_drop": 0}, format="json")
    assert r.status_code == 200, r.content
    assert r.json()["rest_work"] == 150 and r.json()["rest_drop"] == 0
    pref = ClientExercisePref.objects.get(client=user, exercise=pe.exercise)
    assert (pref.rest_work, pref.rest_warmup, pref.rest_drop) == (150, 45, 0)
    assert pref.focus_metric == "volume"  # untouched
    # focus metric alone keeps the rest timers
    client_user.put(f"{P}{pe.exercise_id}/", {"focus_metric": "reps"}, format="json")
    pref.refresh_from_db()
    assert pref.focus_metric == "reps" and pref.rest_work == 150
    # null = back to the plan's rest
    client_user.put(f"{P}{pe.exercise_id}/", {"rest_work": None}, format="json")
    pref.refresh_from_db()
    assert pref.rest_work is None and pref.rest_warmup == 45


def test_rest_values_are_checked(client_user):
    pe = _plan_exercise(_riya())
    for bad in ({"rest_work": -5}, {"rest_work": 901}, {"rest_warmup": "90"}, {}):
        r = client_user.put(f"{P}{pe.exercise_id}/", bad, format="json")
        assert r.status_code == 400, bad
        assert "error" in r.json()


def test_locked_rest_cannot_be_changed(client_user):
    user = _riya()
    pe = _plan_exercise(user)
    pe.rest_locked = True
    pe.save(update_fields=["rest_locked"])
    r = client_user.put(f"{P}{pe.exercise_id}/", {"rest_work": 30}, format="json")
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "rest_locked"
    # the focus metric can still change
    assert client_user.put(f"{P}{pe.exercise_id}/", {"focus_metric": "reps"}, format="json").status_code == 200


def test_train_page_sends_rest_by_set_type_and_lock(client_user):
    user = _riya()
    pa, pd, _, _ = services.today_plan(user, timezone.localdate())
    if pd is None or pd.is_rest or not pd.exercises.exists():
        return  # demo plan has a rest day today: nothing to show
    pe = pd.exercises.first()
    pe.rest_warmup_seconds, pe.rest_drop_seconds, pe.rest_locked = 30, 0, False
    pe.save()
    ClientExercisePref.objects.update_or_create(client=user, exercise=pe.exercise, defaults={"rest_work": 200})
    ex = next(e for e in client_user.get("/api/v1/me/train/").json()["exercises"] if e["id"] == pe.id)
    assert ex["rest_warmup_seconds"] == 30 and ex["rest_drop_seconds"] == 0 and ex["rest_locked"] is False
    assert ex["rest_pref"]["work"] == 200
    pe.rest_locked = True
    pe.save()
    ex = next(e for e in client_user.get("/api/v1/me/train/").json()["exercises"] if e["id"] == pe.id)
    assert ex["rest_pref"] is None  # locked: the coach's rest wins


def test_per_set_rest_and_actual_rest_are_saved(client_user):
    wid = _start(client_user)
    rdl = Exercise.objects.get(name="Romanian Deadlift", is_builtin=True)
    rows = [
        {"key": "a", "exercise": str(rdl.id), "set_number": 1, "weight_kg": "60", "reps": 8, "done": True,
         "rest_seconds": 75, "rest_planned": 75, "rest_actual": 63},
        {"key": "b", "exercise": str(rdl.id), "set_number": 2, "weight_kg": "60", "reps": 8, "done": True,
         "rest_planned": 120, "rest_actual": 120},
    ]
    r = client_user.put(f"{W}{wid}/state/", {"sets": rows}, format="json")
    assert r.status_code == 200, r.content
    by = {s["client_key"]: s for s in r.json()["sets"]}
    assert (by["a"]["rest_seconds"], by["a"]["rest_planned"], by["a"]["rest_actual"]) == (75, 75, 63)
    assert by["b"]["rest_seconds"] is None and by["b"]["rest_actual"] == 120
    bad = [{**rows[0], "rest_seconds": 901}]
    assert client_user.put(f"{W}{wid}/state/", {"sets": bad}, format="json").status_code == 400
    assert SetLog.objects.get(workout_id=wid, client_key="a").rest_actual == 63


def test_coach_rest_fields_save_with_the_plan(db):
    from apps.training.serializers import ProgramExerciseSerializer

    pe = ProgramExercise.objects.first()
    ser = ProgramExerciseSerializer(pe, data={"rest_warmup_seconds": 30, "rest_drop_seconds": 0, "rest_locked": True},
                                    partial=True)
    assert ser.is_valid(), ser.errors
    ser.save()
    pe.refresh_from_db()
    assert (pe.rest_warmup_seconds, pe.rest_drop_seconds, pe.rest_locked) == (30, 0, True)
