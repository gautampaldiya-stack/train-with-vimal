"""D-60: the coach hears about their client — personal best, goal weight, a missed workout, a plan that ends soon.
Bell (in-app) for all; push only for goal weight and plan end. Never the admin."""
from datetime import timedelta
from decimal import Decimal

from django.utils import timezone

from apps.accounts.models import User
from apps.clients.metrics import active_program, program_day_for
from apps.clients.models import ClientProfile
from apps.notifications import reminders
from apps.notifications.models import Notification, StaffNotificationPreference
from apps.training.models import AssignmentStatus, Exercise, ProgramAssignment, WorkoutLog

W = "/api/v1/me/workouts/"


def _riya():
    return User.objects.get(email="riya@example.com")


def _aman_rows(event):
    return Notification.objects.filter(recipient__email="aman@trainwithvimal.com", event=event)


def test_personal_best_tells_the_coach(client_user):
    WorkoutLog.objects.filter(client__email="riya@example.com", status="in_progress").delete()
    wid = client_user.post(W, {"name": "Test workout"}, format="json").json()["id"]
    rdl = Exercise.objects.get(name="Romanian Deadlift", is_builtin=True)
    sets = [{"key": "a1", "exercise": str(rdl.id), "set_number": 1, "weight_kg": "62.5", "reps": 8, "done": True}]
    client_user.put(f"{W}{wid}/state/", {"sets": sets}, format="json")
    assert client_user.post(f"{W}{wid}/finish/", {"duration_seconds": 900}, format="json").status_code == 200
    n = _aman_rows("client_personal_best").get()
    assert n.title == "Riya hit a new personal best" and n.body == "Romanian Deadlift 62.5 kg × 8"
    assert n.in_app and n.actor.email == "riya@example.com"
    assert not Notification.objects.filter(recipient__role="admin", event="client_personal_best").exists()


def test_goal_weight_tells_the_coach_once(client_user):
    ClientProfile.objects.filter(user__email="riya@example.com").update(target_weight_kg=Decimal("69"),
                                                                         start_weight_kg=Decimal("74"))
    page = client_user.get("/api/v1/me/checkins/").json()
    f = page["daily"]["form"]

    def qid(text):
        return str(next(q["id"] for q in f["questions"] if q["text"] == text))

    answers = {qid("Morning weight"): 68.5, qid("Sleep last night"): "7 h", qid("Energy"): 4, qid("Mood"): 4,
               qid("Hunger"): 3, qid("Soreness"): 2}
    r = client_user.post("/api/v1/me/submissions/", {"form": f["id"], "answers": answers}, format="json")
    assert r.status_code == 201, r.content
    n = _aman_rows("client_goal_reached").get()
    assert n.title == "Riya Sharma reached their goal weight" and n.body == "68.5 kg (goal 69 kg)"
    assert n.data["route"] == f"/clients/{_riya().id}"
    client_user.patch(f"/api/v1/me/submissions/{r.json()['id']}/", {"answers": answers}, format="json")
    assert _aman_rows("client_goal_reached").count() == 1


def _planned_day_before(client, today):
    """A day before `today` that has a planned workout (walk back up to two weeks)."""
    for i in range(1, 15):
        d = today - timedelta(days=i)
        pd = program_day_for(active_program(client, d), d)
        if pd is not None and not pd.is_rest:
            return d
    raise AssertionError("no planned day")


def test_missed_workout_and_plan_end(db):
    riya = _riya()
    today = timezone.localdate()
    missed = _planned_day_before(riya, today)
    WorkoutLog.objects.filter(client=riya, date=missed).delete()
    a = ProgramAssignment.objects.filter(client=riya, status=AssignmentStatus.ACTIVE).first()
    a.end_date = today + timedelta(days=3)
    a.save(update_fields=["end_date"])

    run_day = missed + timedelta(days=1)
    reminders.coach_daily_notices(today=run_day)
    n = _aman_rows("client_missed_workout").get(actor=riya)
    assert n.title == "Riya missed yesterday’s workout" and n.data["route"] == f"/clients/{riya.id}?tab=logs"
    ends = _aman_rows("client_plan_ending").filter(title__startswith="Riya’s plan ends").get()
    assert "pick what comes next" in ends.body

    # Again the same day: nothing new. Switched off: no missed-workout line.
    reminders.coach_daily_notices(today=run_day)
    assert _aman_rows("client_missed_workout").filter(actor=riya).count() == 1 and _aman_rows("client_plan_ending").filter(
        title__startswith="Riya").count() == 1
    # Riya is Aman's client, so the admin hears nothing about her (the admin's own clients do reach the admin, D-57).
    assert not Notification.objects.filter(recipient__role="admin", event__startswith="client_missed",
                                           actor=riya).exists()


def test_missed_workout_respects_the_switch(db):
    riya = _riya()
    aman = User.objects.get(email="aman@trainwithvimal.com")
    StaffNotificationPreference.objects.update_or_create(user=aman, defaults={"missed_workouts": False})
    missed = _planned_day_before(riya, timezone.localdate())
    WorkoutLog.objects.filter(client=riya, date=missed).delete()
    reminders.coach_daily_notices(today=missed + timedelta(days=1))
    assert not _aman_rows("client_missed_workout").filter(actor=riya).exists()


# ---------------------------------------------------------------- coach → client, and admin news
def _riya_rows(event):
    return Notification.objects.filter(recipient__email="riya@example.com", event=event)


def test_builder_save_tells_the_clients_once_a_day(admin):
    riya = _riya()
    a = ProgramAssignment.objects.filter(client=riya, status=AssignmentStatus.ACTIVE).first()
    prog = a.custom_program or a.program
    url = (f"/api/v1/clients/{riya.id}/programs/{a.id}/custom-structure/" if a.custom_program
           else f"/api/v1/programs/{prog.id}/structure/")
    detail = admin.get(url) if a.custom_program else admin.get(f"/api/v1/programs/{prog.id}/")
    weeks = detail.json()["program_weeks"]
    for _ in range(2):
        r = admin.put(url, {"weeks": weeks}, format="json")
        assert r.status_code == 200, r.content[:300]
    n = _riya_rows("workout_plan_updated").get()
    assert n.title == "Vimal updated your workout plan" and n.data["route"] == "/train"


def test_ending_plans_and_removing_habits_tells_the_client(trainer):
    from apps.habits.models import Habit

    riya = _riya()
    a = ProgramAssignment.objects.filter(client=riya, status=AssignmentStatus.ACTIVE).first()
    assert trainer.post(f"/api/v1/clients/{riya.id}/programs/{a.id}/end/").status_code == 200
    assert _riya_rows("plan_ended").get().title == "Your workout plan has ended"

    h = Habit.objects.create(name="Evening stretch")
    url = f"/api/v1/habits/{h.id}/assign/"
    trainer.post(url, {"clients": [str(riya.id)]}, format="json")
    trainer.post(url, {"clients": []}, format="json")
    assert _riya_rows("plan_removed").get().title == "Removed from your plan: Evening stretch"


def test_account_deletion_tells_coach_and_admin(client_user):
    assert client_user.post("/api/v1/auth/account/delete/").status_code == 200
    rows = Notification.objects.filter(event="client_deletion")
    assert {n.recipient.email for n in rows} >= {"aman@trainwithvimal.com"}
    assert rows.filter(recipient__role="admin").exists()


def test_invite_accepted_tells_the_team(db):
    from rest_framework.test import APIClient

    from apps.accounts.models import OneTimeToken
    from apps.accounts.tokens import issue_one_time_token

    sana = User.objects.get(email="sana@example.com")
    User.objects.filter(id=sana.id).update(last_login=None)
    raw = issue_one_time_token(sana, OneTimeToken.Purpose.LOGIN_LINK)
    r = APIClient().post("/api/v1/auth/login-link/accept/", {"token": raw, "password": "Strong@Pass9", "confirm_password": "Strong@Pass9"}, format="json")
    assert r.status_code == 200, r.content
    rows = Notification.objects.filter(event="client_joined", actor=sana)
    assert rows.filter(recipient__role="admin").exists() and rows.count() >= 1
