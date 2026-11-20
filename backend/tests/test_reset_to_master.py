"""Probid 2026-11-20: Plans → Reset to master answered 500 on the first tap and worked on the second."""
from apps.accounts.models import User
from apps.training.models import AssignmentStatus, ProgramAssignment


def test_reset_to_master_works_first_time(trainer):
    riya = User.objects.get(email="riya@example.com")
    a = ProgramAssignment.objects.filter(client=riya, status=AssignmentStatus.ACTIVE).first()
    base = f"/api/v1/clients/{riya.id}/programs/{a.id}/"
    assert trainer.post(base + "customise/").status_code == 200
    r = trainer.post(base + "reset-to-master/")
    assert r.status_code == 200, r.content
    a.refresh_from_db()
    assert a.custom_program_id is None


def test_unnamed_plan_day_shows_its_muscle_groups(trainer):
    """Probid 2026-11-20: Train / Home showed no workout name when the coach left the day name blank."""
    from apps.training.models import ProgramDay

    pd = ProgramDay.objects.filter(is_rest=False, exercises__isnull=False).first()
    pd.name = ""
    pd.save(update_fields=["name"])
    groups = {pe.exercise.get_muscle_group_display() for pe in pd.exercises.all()}
    assert pd.title and pd.title != "Workout"
    assert set(pd.title.split(" & ")) <= groups
    pd.name = "Upper A"
    assert pd.title == "Upper A"
