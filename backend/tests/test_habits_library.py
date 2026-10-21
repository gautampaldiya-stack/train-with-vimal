"""Library → Habits & supplements (boards `Habits` / `HabitsMobile`): counts and what the page offers, New habit,
Save with limits, Duplicate, Delete + Undo, Assign; supplement plans with Pre-workout items and quick add."""
from apps.habits.models import Habit, HabitAssignment


def test_counts_and_can(admin, trainer):
    d = admin.get("/api/v1/habits/counts/").json()
    assert d["habits"] == Habit.objects.count() and d["supplements"] >= 1
    assert d["can"] == {"edit": True, "assign_habits": True, "assign_supplements": True}
    assert set(trainer.get("/api/v1/habits/counts/").json()["can"]) == {"edit", "assign_habits", "assign_supplements"}


def test_habit_new_save_duplicate_delete(admin):
    r = admin.post("/api/v1/habits/", {"name": "  Walk   after dinner ", "kind": "tick", "icon": "steps"}, format="json")
    assert r.status_code == 201, r.content
    h = r.json()
    assert h["name"] == "Walk after dinner" and h["frequency_label"] == "Daily" and h["client_count"] == 0
    url = f"/api/v1/habits/{h['id']}/"
    # a counter needs a target, and the target has a ceiling
    assert admin.patch(url, {"kind": "counter"}, format="json").status_code == 400
    r = admin.patch(url, {"kind": "counter", "target": 1_000_000, "unit": "steps"}, format="json")
    assert r.status_code == 400 and "target" in r.json()["error"]["fields"]
    r = admin.patch(url, {"kind": "counter", "target": 3000, "unit": "steps", "frequency": "days", "days": [4, 0, 2]},
                    format="json")
    assert r.status_code == 200 and r.json()["frequency_label"] == "Mon, Wed, Fri"
    r = admin.patch(url, {"frequency": "times_week", "times_per_week": 8}, format="json")
    assert r.status_code == 400
    dup = admin.post(url + "duplicate/").json()
    assert dup["name"] == "Walk after dinner (copy)" and dup["target"] == 3000
    assert admin.delete(url).status_code == 204
    assert all(x["id"] != h["id"] for x in admin.get("/api/v1/habits/").json())
    assert admin.post(url + "restore/").status_code == 200
    assert any(x["id"] == h["id"] for x in admin.get("/api/v1/habits/").json())


def test_habit_assign(trainer):
    h = Habit.objects.create(name="Morning walk")
    url = f"/api/v1/habits/{h.id}/assign/"
    rows = trainer.get(url).json()
    assert rows and not any(r["on_it"] for r in rows)
    ids = [r["id"] for r in rows[:2]]
    assert trainer.post(url, {"clients": ids}, format="json").json() == {"added": 2, "removed": 0}
    assert {r["id"] for r in trainer.get(url).json() if r["on_it"]} == set(ids)
    assert trainer.post(url, {"clients": ids[:1]}, format="json").json() == {"added": 0, "removed": 1}
    assert HabitAssignment.objects.filter(habit=h, active=True).count() == 1


def test_supplement_plan_with_pre_workout(admin):
    q = admin.get("/api/v1/supplement-plans/quick-add/").json()
    assert any(x["name"] == "Vitamin D3" for x in q)
    r = admin.post("/api/v1/supplement-plans/", {"name": "Recovery stack", "items": [
        {"name": "Caffeine", "dose": "100 mg", "timing": "pre_workout", "days": [], "with_food": False},
        {"name": "Glutamine", "dose": "5 g", "timing": "post_workout", "days": [5, 1, 1], "with_food": True}]},
        format="json")
    assert r.status_code == 201, r.content
    p = r.json()
    assert {i["timing"] for i in p["items"]} == {"pre_workout", "post_workout"}
    assert next(i for i in p["items"] if i["name"] == "Glutamine")["days"] == [1, 5]
    items = [{**i} for i in p["items"] if i["name"] == "Caffeine"]
    r = admin.patch(f"/api/v1/supplement-plans/{p['id']}/", {"note": "Before training only.", "items": items},
                    format="json")
    assert r.status_code == 200 and [i["name"] for i in r.json()["items"]] == ["Caffeine"]
    assert r.json()["note"] == "Before training only."
