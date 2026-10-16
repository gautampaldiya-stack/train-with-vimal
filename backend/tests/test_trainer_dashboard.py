from datetime import timedelta

from django.utils import timezone

from apps.accounts.models import User
from apps.activity.trainer_home import trainer_home
from apps.clients.models import ClientProfile
from apps.scheduling.models import Session


def _mine():
    aman = User.objects.get(email="aman@trainwithvimal.com")
    return aman, {str(i) for i in ClientProfile.objects.filter(trainer=aman).values_list("user_id", flat=True)}


def test_dashboard_has_every_card_of_the_board(trainer):
    r = trainer.get("/api/v1/dashboard/trainer/")
    assert r.status_code == 200, r.content
    d = r.json()
    assert d["greeting"].endswith(", Aman") and " clients · " in d["subline"]
    assert [s["key"] for s in d["stats"]] == ["clients", "checkins", "workouts", "reply"]
    assert [s["time"] for s in d["today"]] == sorted(s["time"] for s in d["today"])
    order = ["log", "miss", "end", "low"]
    assert [order.index(n["kind"]) for n in d["need"]] == sorted(order.index(n["kind"]) for n in d["need"])
    assert {n["action"] for n in d["need"]} <= {"remind", "plan", "open"}
    assert d["checkins"] and all(c["line"] and c["tone"] in ("bad", "warn", "neu") for c in d["checkins"])
    assert [r["label"] for r in d["week"]["rows"]] == ["Sessions held", "Check-ins reviewed", "Plans changed", "New clients"]


def test_dashboard_only_shows_the_trainers_own_clients(trainer):
    _, mine = _mine()
    d = trainer.get("/api/v1/dashboard/trainer/").json()
    seen = {s["client"]["id"] for s in d["today"]} | {n["id"] for n in d["need"]} | {c["client"]["id"] for c in d["checkins"]}
    assert seen and seen <= mine


def test_clients_cannot_open_the_trainer_dashboard(client_user):
    assert client_user.get("/api/v1/dashboard/trainer/").status_code == 403


def test_next_session_says_how_long_until_it_starts(db):
    aman, _ = _mine()
    cp = ClientProfile.objects.filter(trainer=aman).select_related("user").first()
    start = timezone.localtime() + timedelta(days=1)
    start = start.replace(hour=10, minute=0, second=0, microsecond=0)
    Session.objects.create(trainer=aman, client=cp.user, start=start, end=start + timedelta(minutes=60), title="Test")
    d = trainer_home(aman, now=start - timedelta(minutes=40))
    nxt = [s for s in d["today"] if s["next"]]
    assert len(nxt) == 1 and nxt[0]["time"] == "10:00" and nxt[0]["in"] == "In 40 min"


def test_checkin_detail_carries_the_review_view(trainer):
    d = trainer.get("/api/v1/dashboard/trainer/").json()
    sub = trainer.get(f"/api/v1/checkins/{d['checkins'][0]['id']}/").json()
    rv = sub["review"]
    assert [k["label"] for k in rv["kpis"]] == ["Weight", "Change", "Workouts", "Meals on plan"]
    assert rv["rows"] and rv["line"] == d["checkins"][0]["line"]


def test_each_client_shows_once_in_who_needs_you(trainer):
    ids = [n["id"] for n in trainer.get("/api/v1/dashboard/trainer/").json()["need"]]
    assert len(ids) == len(set(ids))


def test_check_in_and_client_numbers_agree_for_trainer_and_admin(trainer, admin):
    """Dashboard, Check-ins page, My profile and the admin's Trainers table count the same check-ins and clients."""
    d = trainer.get("/api/v1/dashboard/trainer/").json()
    page = trainer.get("/api/v1/checkins/counts/").json()
    me = trainer.get("/api/v1/trainers/me/").json()
    row = next(t for t in admin.get("/api/v1/trainers/").json()["results"] if t["full_name"] == "Aman Verma")
    assert d["checkins_total"] == page["to_review"] == me["checkins_to_review"] == row["checkins_to_review"]
    assert d["stats"][1]["value"] == str(d["checkins_total"])
    assert d["stats"][0]["value"].split(" / ")[0] == str(me["clients"]) == str(row["clients"])


def test_feeling_low_uses_the_latest_check_in(trainer):
    # Riya had one low day earlier but her latest check-ins are 4 / 5, so she is not "Feeling low".
    d = trainer.get("/api/v1/dashboard/trainer/").json()
    assert not any(n["name"] == "Riya Sharma" and n["kind"] == "low" for n in d["need"])


def test_activity_card_shows_only_the_trainers_clients_and_pages(trainer):
    _, mine = _mine()
    d = trainer.get("/api/v1/dashboard/trainer/").json()["activity"]
    assert d["rows"] and len(d["rows"]) <= 10
    assert all(r["client"] in mine or r["me"] or not r["client"] for r in d["rows"])
    seen = [r["id"] for r in d["rows"]]
    while d["next"]:
        d = trainer.get("/api/v1/dashboard/trainer/activity/", {"before": d["next"]}).json()
        assert all(r["client"] in mine or r["me"] or not r["client"] for r in d["rows"])
        seen += [r["id"] for r in d["rows"]]
    assert len(seen) == len(set(seen))  # pages never repeat a row


def test_activity_card_shows_what_a_client_just_did(trainer, django_capture_on_commit_callbacks):
    from apps.activity.services import log

    aman, _ = _mine()
    cp = ClientProfile.objects.filter(trainer=aman).select_related("user").first()
    other = ClientProfile.objects.exclude(trainer=aman).select_related("user").first()
    with django_capture_on_commit_callbacks(execute=True):  # the log is written after commit
        log("finished a workout", "workout", actor=cp.user, target_label="Push day", client=cp.user)
        log("finished a workout", "workout", actor=other.user, target_label="Leg day", client=other.user)
    rows = trainer.get("/api/v1/dashboard/trainer/").json()["activity"]["rows"]
    top = rows[0]
    assert (top["who"], top["what"], top["detail"], top["tone"]) == (cp.user.full_name, "finished a workout", "Push day", "cl")
    assert not any(r["client"] == str(other.user_id) for r in rows)


def test_clients_cannot_read_trainer_activity(client_user):
    assert client_user.get("/api/v1/dashboard/trainer/activity/").status_code == 403
