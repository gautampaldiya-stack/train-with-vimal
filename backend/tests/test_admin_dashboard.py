def test_admin_dashboard_has_every_card_of_the_board(admin):
    r = admin.get("/api/v1/dashboard/admin/")
    assert r.status_code == 200, r.content
    d = r.json()
    assert d["greeting"].startswith("Good ")
    assert set(d["stats"]) == {"active_clients", "pending_approvals", "checkin_rate", "adherence"}
    assert set(d["glance"]) == {"clients", "trainers", "checkins_to_review", "onboarding_pending",
                                "nutrition_pending", "programs_ending"}
    assert d["needs_action"] and all(n["title"] and n["sub"] and n["cta"] and n["route"].startswith("/")
                                     for n in d["needs_action"])
    assert {"rows", "count", "reminded_last_24h"} <= set(d["at_risk"])


def test_needs_action_titles_are_plural_aware(admin):
    for n in admin.get("/api/v1/dashboard/admin/").json()["needs_action"]:
        assert not n["title"].startswith("1 ") or "s waiting" not in n["title"]


def test_trainer_performance_this_month(admin):
    week = admin.get("/api/v1/dashboard/admin/").json()["trainer_performance"]
    month = admin.get("/api/v1/dashboard/admin/?period=month").json()["trainer_performance"]
    assert {t["id"] for t in week} == {t["id"] for t in month}
    assert [t["adherence"] for t in month] == sorted(t["adherence"] for t in month)


def test_dismissed_rows_stay_hidden(admin):
    row = admin.get("/api/v1/dashboard/admin/").json()["needs_action"][0]
    assert admin.post("/api/v1/dashboard/dismiss/", {"key": row["key"]}, format="json").status_code in (200, 201, 204)
    keys = [n["key"] for n in admin.get("/api/v1/dashboard/admin/").json()["needs_action"]]
    assert row["key"] not in keys


def test_trainers_cannot_open_the_admin_dashboard(trainer):
    assert trainer.get("/api/v1/dashboard/admin/").status_code == 403
