from apps.accounts.models import User
from apps.clients.models import ClientProfile


def _mine():
    aman = User.objects.get(email="aman@trainwithvimal.com")
    return {str(i) for i in ClientProfile.objects.filter(trainer=aman, removed_at__isnull=True).values_list("user_id", flat=True)}


def test_my_clients_rows_carry_every_column_of_the_board(trainer):
    r = trainer.get("/api/v1/clients/", {"page_size": 8})
    assert r.status_code == 200, r.content
    d = r.json()
    assert len(d["results"]) <= 8 and d["count"] == len(_mine())
    row = d["results"][0]
    for k in ("full_name", "email", "phone", "goal_label", "badge", "onboarding", "next_checkin", "last_active"):
        assert k in row
    assert {x["id"] for x in d["results"]} <= _mine()


def test_tab_counts_match_the_list(trainer):
    c = trainer.get("/api/v1/clients/counts/").json()
    for tab in ("all", "active", "pending", "paused", "at_risk"):
        assert trainer.get("/api/v1/clients/", {"tab": tab}).json()["count"] == c[tab]


def test_next_check_in_filters_agree_with_the_column(trainer):
    rows = trainer.get("/api/v1/clients/", {"page_size": 100}).json()["results"]
    overdue = {r["id"] for r in trainer.get("/api/v1/clients/", {"next_checkin": "overdue", "page_size": 100}).json()["results"]}
    assert overdue == {r["id"] for r in rows if r["next_checkin"] == "Overdue"}
    week = {r["id"] for r in trainer.get("/api/v1/clients/", {"next_checkin": "week", "page_size": 100}).json()["results"]}
    assert not week & overdue
    assert all(r["next_checkin"] not in ("Overdue", "Paused", "—") for r in rows if r["id"] in week)


def test_search_and_goal_filter(trainer):
    rows = trainer.get("/api/v1/clients/", {"search": "riya"}).json()["results"]
    assert [r["full_name"] for r in rows] == ["Riya Sharma"]
    fat = trainer.get("/api/v1/clients/", {"goal": "fat_loss", "page_size": 100}).json()["results"]
    assert fat and all(r["goal"] == "fat_loss" for r in fat)


def test_trainer_can_edit_their_clients_details(trainer):
    rid = trainer.get("/api/v1/clients/", {"search": "riya"}).json()["results"][0]["id"]
    r = trainer.patch(f"/api/v1/clients/{rid}/", {"city": "Pune"}, format="json")
    assert r.status_code == 200, r.content
    assert r.json()["profile"] is not None and User.objects.get(id=rid).city == "Pune"


def test_export_is_a_csv_of_the_filtered_list(trainer):
    r = trainer.get("/api/v1/clients/export/", {"tab": "active"})
    assert r.status_code == 200 and r["Content-Type"].startswith("text/csv")
    lines = b"".join(r.streaming_content if hasattr(r, "streaming_content") else [r.content]).decode().strip().splitlines()
    assert lines[0].startswith("Name,Email,Phone") and len(lines) - 1 == trainer.get("/api/v1/clients/counts/").json()["active"]


def test_export_selected_rows_only(trainer):
    rows = trainer.get("/api/v1/clients/", {"page_size": 2}).json()["results"]
    r = trainer.get("/api/v1/clients/export/", {"ids": ",".join(x["id"] for x in rows)})
    body = b"".join(r.streaming_content if hasattr(r, "streaming_content") else [r.content]).decode()
    assert len(body.strip().splitlines()) == 1 + len(rows)
