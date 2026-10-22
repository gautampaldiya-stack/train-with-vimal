"""Admin → Trainers, Trainer profile, Calendar (all trainers) and Activity log (D-48)."""
from apps.accounts.models import User


def _aman():
    return User.objects.get(email="aman@trainwithvimal.com")


def test_trainers_summary_has_adherence_change(admin):
    d = admin.get("/api/v1/trainers/summary/").json()
    assert "adherence_change" in d
    assert {"counts", "spots", "checkins_to_review"} <= set(d)


def test_trainer_profile_sends_access_presets(admin):
    d = admin.get(f"/api/v1/trainers/{_aman().id}/").json()
    assert set(d["access_presets"]) == {"assigned", "all"}
    assert d["access_presets"]["assigned"] != d["access_presets"]["all"]


def test_trainer_profile_clients_and_activity(admin):
    aman = _aman()
    r = admin.get(f"/api/v1/trainers/{aman.id}/clients/")
    assert r.status_code == 200, r.content
    rows = r.json()["results"]
    assert rows and all(c["id"] for c in rows)
    first = rows[0]["full_name"].split()[0]
    hit = admin.get(f"/api/v1/trainers/{aman.id}/clients/", {"search": first}).json()["results"]
    assert any(c["full_name"].startswith(first) for c in hit)
    assert admin.get(f"/api/v1/trainers/{aman.id}/activity/").status_code == 200


def test_trainer_cannot_open_another_trainers_clients(trainer):
    other = User.objects.filter(role="trainer").exclude(email="aman@trainwithvimal.com").first()
    assert trainer.get(f"/api/v1/trainers/{other.id}/clients/").status_code in (403, 404)


def test_activity_log_search_and_counts(admin):
    rows = admin.get("/api/v1/activity/", {"range": "all", "page_size": 5}).json()["results"]
    assert rows
    who = rows[0]["actor_label"] or rows[0]["target_label"]
    hit = admin.get("/api/v1/activity/", {"range": "all", "search": who}).json()["results"]
    assert hit and all(who.lower() in " ".join([h["actor_label"], h["target_label"], h["verb"], h["client_name"] or ""]).lower()
                       for h in hit)
    assert admin.get("/api/v1/activity/", {"range": "all", "search": "zzz-nothing-zzz"}).json()["results"] == []
    counts = admin.get("/api/v1/activity/counts/", {"range": "all", "kind": "plan", "by_day": 1}).json()
    assert counts["all"] >= counts["plan"] and isinstance(counts["days"], dict)


def test_admin_calendar_all_trainers_and_availability(admin):
    s = admin.get("/api/v1/sessions/stats/").json()
    assert "busiest" in s and isinstance(s["by_trainer"], list)
    aman = _aman()
    av = admin.get("/api/v1/availability/", {"trainer": aman.id}).json()
    assert len(av["days"]) == 7
    days = av["days"]
    r = admin.put("/api/v1/availability/", {"trainer": str(aman.id), "days": days}, format="json")
    assert r.status_code == 200, r.content
