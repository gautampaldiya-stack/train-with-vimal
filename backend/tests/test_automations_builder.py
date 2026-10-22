"""Admin → Automations list and the Automation builder (boards Automations / AutomationNew / AutomationBuilder, D-51)."""
from datetime import timedelta

from django.utils import timezone

from apps.accounts.models import User
from apps.automations import engine
from apps.automations.models import Automation, AutomationRun

URL = "/api/v1/automations/"


def _rows(admin):
    return {a["name"]: a for a in admin.get(URL).json()}


def test_list_reads_like_the_board(admin):
    rows = _rows(admin)
    assert list(rows)[:2] == ["Client onboarding", "Weekly check-in"]  # creation order
    w = rows["Weekly check-in"]
    assert w["trigger_line"] == "Every Sunday at 9 am"
    assert w["scope_package"] == "3 months · Gym" and w["scope_trainer_name"] == ""
    onb = rows["Client onboarding"]
    assert onb["counts"] == {"running": 1, "finished": 2, "stopped": 1}
    assert onb["steps"][0]["summary"] == "Send the form “New client questionnaire” by Push and Email"
    assert onb["steps"][2]["summary"] == "Send “Onboarding form reminder” by WhatsApp"
    assert onb["steps"][4]["summary"].startswith("Task for the assigned trainer: ")
    assert rows["Missed workouts nudge"]["trigger_line"] == "When 3 workouts in a row are missed"
    s = admin.get(URL + "stats/").json()
    assert s["on"] == 2 and s["total"] == 5 and s["in_flow"] == 2


def test_starters_carry_their_trigger_line(admin):
    cat = admin.get(URL + "catalog/").json()
    st = {s["key"]: s for s in cat["starters"]}
    assert st["renewal"]["trigger_line"] == "7 days before a package ends" and st["renewal"]["step_count"] == 5
    plan_ends = next(t for t in cat["triggers"] if t["key"] == "plan_ends")
    assert plan_ends["settings"] == {"days_before": [0, 14, 3], "time": "09:00"}


def test_builder_saves_turns_on_and_scopes_a_trainer(admin):
    aman = User.objects.get(email="aman@trainwithvimal.com")
    body = {"name": "Streak cheer", "trigger": "workout_streak", "trigger_config": {"days": 10},
            "scope_package": "", "scope_trainer": str(aman.id), "stop_on_response": False,
            "steps": [{"kind": "message", "config": {"template": "coach-feedback", "channels": ["push"]}}]}
    r = admin.post(URL, body, format="json")
    assert r.status_code == 201, r.content
    a = r.json()
    assert a["status"] == "draft" and a["scope_trainer_name"] == aman.full_name
    assert a["trigger_line"] == "After 10 workout days in a row"
    assert admin.post(URL + f"{a['id']}/turn-on/").json()["status"] == "on"
    # a client cannot be the trainer it is for
    riya = User.objects.get(email="riya@example.com")
    r = admin.patch(URL + f"{a['id']}/", {"scope_trainer": str(riya.id)}, format="json")
    assert r.status_code == 400


def test_turn_on_lists_what_is_missing(admin):
    a = admin.post(URL, {"name": "Half done", "trigger": "", "steps": [{"kind": "wait", "config": {"days": 1}}]},
                   format="json").json()
    r = admin.post(URL + f"{a['id']}/turn-on/")
    assert r.status_code == 400
    probs = r.json()["error"]["fields"]["problems"]
    assert "Pick a trigger." in probs and any("last step is a wait" in p for p in probs)


def test_last_30_days_skips_older_runs(admin):
    a = Automation.objects.get(name="Client onboarding")
    old = AutomationRun.objects.filter(automation=a).first()
    AutomationRun.objects.filter(id=old.id).update(created_at=timezone.now() - timedelta(days=40))
    r = admin.get(URL + f"{a.id}/runs/").json()
    assert r["started"] == 3 and len(r["rows"]) == 3


def test_package_ending_waits_for_its_time(db):
    a = Automation.objects.get(name="Renewal reminder")
    a.trigger_config = {"days_before": 7, "time": "18:00"}
    a.save()
    morning = timezone.localtime().replace(hour=9, minute=5)
    assert list(engine.candidates(a, morning)) == []
