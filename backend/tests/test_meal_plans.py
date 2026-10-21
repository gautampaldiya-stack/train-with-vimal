"""Nutrition & foods → Meal plans and the Meal plan builder (boards Nutrition / MealPlanBuilder), as Vimal and as a
trainer: the same rules as programs (D-39, D-43) — a trainer changes only plans they made (or all with "Edit gym
templates"), sees and changes only their own clients, Delete → Undo brings the clients back, and Assign + Undo on
the same day leaves no Plan history."""
from apps.accounts.models import User
from apps.nutrition.models import MealPlan, MealPlanAssignment

M = "/api/v1/meal-plans/"


def _gym_plan():
    return MealPlan.objects.get(name="Veg fat loss · 1,800", is_master=True)


def test_counts_say_what_each_role_may_do(admin, trainer):
    c = admin.get(M + "counts/").json()
    assert c["all"] >= 1 and c["foods"] >= 40
    assert c["can"] == {"create": True, "assign": True, "foods": True, "edit_all": True}
    t = trainer.get(M + "counts/").json()["can"]
    assert t["create"] is True and t["edit_all"] is False


def test_trainer_sees_own_clients_and_edits_only_own_plans(admin, trainer):
    p = _gym_plan()
    aman = User.objects.get(email="aman@trainwithvimal.com")
    mine = MealPlanAssignment.objects.filter(plan=p, status="active", client__client_profile__trainer=aman).count()
    row = trainer.get(f"{M}{p.id}/").json()
    assert row["client_count"] == mine and row["can_edit"] is False and row["owner"]["kind"] == "gym"
    assert admin.get(f"{M}{p.id}/").json()["client_count"] > mine
    assert trainer.patch(f"{M}{p.id}/", {"name": "Mine"}, format="json").status_code == 403
    assert trainer.put(f"{M}{p.id}/structure/", {"meals": []}, format="json").status_code == 403
    own = trainer.post(M, {"name": "Aman cut", "diet": "veg", "kcal_target": 2000}, format="json").json()
    assert own["can_edit"] is True and own["owner"]["kind"] == "you" and len(own["meals"]) == 4
    assert trainer.patch(f"{M}{own['id']}/", {"kcal_target": 2100}, format="json").status_code == 200
    assert trainer.delete(f"{M}{own['id']}/").status_code == 204


def test_trainer_assign_keeps_other_trainers_clients(admin, trainer):
    p = _gym_plan()
    others = set(MealPlanAssignment.objects.filter(plan=p, status="active")
                 .exclude(client__client_profile__trainer__email="aman@trainwithvimal.com")
                 .values_list("client_id", flat=True))
    mine = [str(c["id"]) for c in trainer.get(f"{M}{p.id}/clients/").json()]
    assert others and mine
    r = trainer.post(f"{M}{p.id}/assign/", {"clients": mine[1:]}, format="json").json()
    assert r["removed"] == 1
    still = set(MealPlanAssignment.objects.filter(plan=p, status="active").values_list("client_id", flat=True))
    assert others <= still
    # put the client back (a real unassign: the plan ran before today, so it moved to history as Unassigned)
    gone = MealPlanAssignment.objects.filter(plan=p, client_id=mine[0]).order_by("-updated_at").first()
    assert gone.status == "ended" and gone.end_reason == "unassigned"
    MealPlanAssignment.objects.filter(id=gone.id).update(status="active", end_reason="", end_date=None)


def test_assign_then_undo_leaves_no_history(admin):
    riya = User.objects.get(email="riya@example.com")
    before = MealPlanAssignment.objects.filter(client=riya, status="active").first()
    new = admin.post(M, {"name": "Undo plan", "diet": "veg", "kcal_target": 1800}, format="json").json()
    assert admin.post(f"{M}{new['id']}/assign/", {"clients": [str(riya.id)]}, format="json").json()["added"] == 1
    if before:
        before.refresh_from_db()
        assert before.status == "ended" and before.end_reason == "replaced"
    assert admin.post(f"{M}{new['id']}/assign/", {"clients": []}, format="json").json()["removed"] == 1
    assert not MealPlanAssignment.objects.filter(plan_id=new["id"]).exists()
    if before:
        before.refresh_from_db()
        assert before.status == "active" and before.end_reason == ""
    admin.delete(f"{M}{new['id']}/")


def test_delete_then_undo_puts_the_clients_back(admin):
    riya = User.objects.get(email="riya@example.com")
    before = MealPlanAssignment.objects.filter(client=riya, status="active").first()
    new = admin.post(M, {"name": "Short plan", "diet": "veg", "kcal_target": 1800}, format="json").json()
    admin.post(f"{M}{new['id']}/assign/", {"clients": [str(riya.id)]}, format="json")
    assert admin.get(f"{M}{new['id']}/delete-preview/").json()["clients"] == 1
    assert admin.delete(f"{M}{new['id']}/").status_code == 204
    assert not MealPlanAssignment.objects.filter(plan_id=new["id"], status="active").exists()
    r = admin.post(f"{M}{new['id']}/restore/")
    assert r.status_code == 200, r.content
    assert r.json()["client_count"] == 1
    # tidy up: Riya goes back to her own plan
    MealPlanAssignment.objects.filter(plan_id=new["id"]).delete()
    if before:
        MealPlanAssignment.objects.filter(id=before.id).update(status="active", end_reason="", end_date=None)


def test_cards_list_meal_names_and_foods_say_where_they_are_used(admin):
    card = next(c for c in admin.get(M).json()["results"] if c["name"] == "Veg fat loss · 1,800")
    assert card["meal_names"] and all(isinstance(n, str) for n in card["meal_names"])
    foods = admin.get("/api/v1/foods/", {"search": "paneer"}).json()["results"]
    used = [f for f in foods if f["used_in"]]
    assert used and used[0]["used_tip"][0].startswith(used[0]["used_in"][0] + " · ")


def test_builtin_food_cannot_be_deleted_but_team_food_can(admin):
    from apps.nutrition.models import Food
    b = Food.objects.filter(source="builtin").first()
    r = admin.delete(f"/api/v1/foods/{b.id}/")
    assert r.status_code == 403 and "Duplicate" in r.json()["error"]["message"]
    new = admin.post("/api/v1/foods/", {"name": "Test thali", "diet": "veg", "group": "other", "kcal": 120,
                                        "protein": 4, "carbs": 18, "fat": 3, "source_note": "Pack label"},
                     format="json")
    assert new.status_code == 201, new.content
    assert new.json()["source_note"] == "Pack label"
    assert admin.delete(f"/api/v1/foods/{new.json()['id']}/").status_code == 204


def test_assign_options_list_only_the_trainers_clients_with_their_plan(admin, trainer):
    rows = trainer.get(M + "assign-options/").json()
    aman = User.objects.get(email="aman@trainwithvimal.com")
    assert rows and all(User.objects.get(id=r["id"]).client_profile.trainer_id == aman.id for r in rows)
    on = [r for r in rows if r["plan"]]
    assert on and on[0]["plan_name"]
    assert len(admin.get(M + "assign-options/").json()) >= len(rows)
