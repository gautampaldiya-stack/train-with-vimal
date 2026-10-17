"""Trainer → Check-ins page (board TrainerCheckins): tabs, type chips, search, the review panel."""


def _rows(trainer, **q):
    return trainer.get("/api/v1/checkins/", {"page_size": 100, **q}).json()["results"]


def test_counts_give_type_chips_per_tab_and_match_the_list(trainer):
    c = trainer.get("/api/v1/checkins/counts/").json()
    for tab in ("to_review", "reviewed", "all"):
        k = c["kinds"][tab]
        assert k["all"] == c[tab] == len(_rows(trainer, tab=tab))
        assert k["weekly"] == len(_rows(trainer, tab=tab, kind="weekly"))
        assert k["daily"] == len(_rows(trainer, tab=tab, kind="daily"))
    assert c["oldest"]


def test_search_finds_a_client_by_name(trainer):
    rows = _rows(trainer, tab="all", search="riya")
    assert rows and all(r["client"]["full_name"] == "Riya Sharma" for r in rows)


def test_a_reviewed_check_in_still_opens(trainer):
    done = _rows(trainer, tab="reviewed")
    assert done
    r = trainer.get(f"/api/v1/checkins/{done[0]['id']}/")
    assert r.status_code == 200 and r.json()["reviewed"] is True


def test_review_panel_marks_better_and_worse(trainer):
    weekly = _rows(trainer, tab="all", kind="weekly")[0]
    rv = trainer.get(f"/api/v1/checkins/{weekly['id']}/").json()["review"]
    assert [k["label"] for k in rv["kpis"]] == ["Weight", "Change", "Workouts", "Meals on plan"]
    assert all(r["trend"] in ("", "up", "down") for r in rv["rows"] + rv["kpis"])


def test_daily_check_in_shows_that_day(trainer):
    daily = _rows(trainer, tab="all", kind="daily")[0]
    rv = trainer.get(f"/api/v1/checkins/{daily['id']}/").json()["review"]
    assert [k["label"] for k in rv["kpis"]] == ["Sleep", "Energy", "Workout", "Steps"]
    assert all("last" in r for r in rv["rows"])


def test_review_then_undo(trainer):
    row = _rows(trainer, tab="to_review")[0]
    before = trainer.get("/api/v1/checkins/counts/").json()["to_review"]
    r = trainer.post(f"/api/v1/checkins/{row['id']}/review/", {"reply": "Great week, keep going!"}, format="json")
    assert r.status_code == 200 and r.json()["reviewed"] is True and r.json()["reply"] == "Great week, keep going!"
    assert trainer.get("/api/v1/checkins/counts/").json()["to_review"] == before - 1
    assert trainer.post(f"/api/v1/checkins/{row['id']}/unreview/").json()["reviewed"] is False
    assert trainer.get("/api/v1/checkins/counts/").json()["to_review"] == before
