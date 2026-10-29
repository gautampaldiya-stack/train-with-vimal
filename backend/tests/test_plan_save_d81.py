"""D-81 (Probid 2026-10-29, "Could not save the plan"): an exercise added for one client in the plan editor goes up
with `"id": null`. That answered 400 "This field may not be null." for every week it was copied to; now a null id is
a new row, and the rows that had ids keep them (logs stay linked)."""
from apps.accounts.models import User
from apps.training.models import AssignmentStatus, Exercise, ProgramAssignment


def _tree(prog):
    return [{
        "id": w.id, "number": w.number,
        "days": [{
            "id": d.id, "weekday": d.weekday, "name": d.name, "is_rest": d.is_rest, "rest_note": d.rest_note,
            "exercises": [{"id": e.id, "exercise": str(e.exercise_id), "order": e.order, "sets": e.sets, "reps": e.reps}
                          for e in d.exercises.all()],
        } for d in w.days.all()],
    } for w in prog.program_weeks.all()]


def test_exercise_added_for_the_client_saves_with_null_id(trainer):
    riya = User.objects.get(email="riya@example.com")
    a = ProgramAssignment.objects.filter(client=riya, status=AssignmentStatus.ACTIVE).first()
    url = f"/api/v1/clients/{riya.id}/programs/{a.id}/custom-structure/"
    assert trainer.post(url.replace("custom-structure", "customise")).status_code == 200  # the client's own copy
    a.refresh_from_db()
    copy = a.custom_program or a.program
    weeks = _tree(copy)
    day = next(d for d in weeks[0]["days"] if not d["is_rest"])
    kept = [e["id"] for e in day["exercises"]]
    squat = Exercise.objects.exclude(id__in=[e["exercise"] for e in day["exercises"]]).first()
    new_row = {"id": None, "exercise": str(squat.id), "order": len(kept), "sets": 4, "reps": "5-6",
               "rest_seconds": 150, "rpe": 8, "tempo": "3-1-1"}
    for w in weeks:  # "changes carry to the later weeks": the same new row in every week
        for d in w["days"]:
            if d["weekday"] == day["weekday"]:
                d["exercises"].append(dict(new_row))
    r = trainer.put(url, {"weeks": weeks}, format="json")
    assert r.status_code == 200, r.content
    body = r.json()
    saved = next(d for d in body["program_weeks"][0]["days"] if d["weekday"] == day["weekday"])
    ids = [e["id"] for e in saved["exercises"]]
    assert ids[:len(kept)] == kept  # old rows keep their ids
    assert saved["exercises"][-1]["exercise"] == str(squat.id) and saved["exercises"][-1]["id"]
    assert saved["exercises"][-1]["reps"] == "5-6"


def test_new_week_and_day_with_null_id_save(trainer):
    riya = User.objects.get(email="riya@example.com")
    a = ProgramAssignment.objects.filter(client=riya, status=AssignmentStatus.ACTIVE).first()
    url = f"/api/v1/clients/{riya.id}/programs/{a.id}/custom-structure/"
    trainer.post(url.replace("custom-structure", "customise"))
    a.refresh_from_db()
    weeks = _tree(a.custom_program or a.program)
    weeks.append({"id": None, "number": len(weeks) + 1,
                  "days": [{"id": None, "weekday": 0, "name": "Extra", "is_rest": False, "rest_note": "",
                            "exercises": []}]})
    r = trainer.put(url, {"weeks": weeks}, format="json")
    assert r.status_code == 200, r.content
    assert len(r.json()["program_weeks"]) == len(weeks)
