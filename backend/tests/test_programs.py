"""Programs page and Program builder (boards Programs / ProgramBuilder), as Vimal and as a trainer (D-39):
cards show only the trainer's own clients, a trainer changes only programs they made (or all with "Edit gym
templates"), Assign never takes a plan away from another trainer's clients, and Delete → Undo brings the
clients back."""
from apps.accounts.models import User
from apps.training.models import Program, ProgramAssignment

P = "/api/v1/programs/"


def _fat_loss():
    return Program.objects.get(name="Fat loss · 8 weeks", is_master=True)


def test_cards_tabs_and_what_each_role_may_do(admin, trainer):
    c = admin.get(P + "counts/").json()
    assert c["active"] >= 5 and c["archived"] >= 1
    assert c["can"] == {"create": True, "assign": True, "edit_all": True}
    t = trainer.get(P + "counts/").json()
    assert t["can"]["create"] is True and t["can"]["edit_all"] is False
    rows = admin.get(P, {"tab": "archived"}).json()
    rows = rows.get("results", rows)
    assert all(r["archived"] for r in rows) and any(r["name"] == "Shoulder-safe Upper Body" for r in rows)
    card = next(r for r in (lambda x: x.get("results", x))(trainer.get(P).json()) if r["name"] == "Fat loss · 8 weeks")
    assert len(card["week_pattern"]) == 7 and card["can_edit"] is False


def test_trainer_cards_count_only_their_clients(admin, trainer):
    p = _fat_loss()
    aman = User.objects.get(email="aman@trainwithvimal.com")
    mine = ProgramAssignment.objects.filter(program=p, status="active", client__client_profile__trainer=aman).count()
    rows = trainer.get(P).json()
    card = next(r for r in rows.get("results", rows) if r["id"] == str(p.id))
    assert card["client_count"] == mine
    ids = {c["id"] for c in card["clients"]}
    assert all(User.objects.get(id=i).client_profile.trainer_id == aman.id for i in ids)
    assert trainer.get(f"{P}{p.id}/").json()["client_count"] == mine
    all_rows = admin.get(P).json()
    assert next(r for r in all_rows.get("results", all_rows) if r["id"] == str(p.id))["client_count"] >= mine


def test_trainer_cannot_change_vimals_program_but_can_duplicate_it(trainer):
    p = _fat_loss()
    assert trainer.patch(f"{P}{p.id}/", {"name": "Mine now"}, format="json").status_code == 403
    assert trainer.post(f"{P}{p.id}/archive/").status_code == 403
    assert trainer.delete(f"{P}{p.id}/").status_code == 403
    r = trainer.post(f"{P}{p.id}/duplicate/")
    assert r.status_code == 201, r.content
    copy = r.json()
    assert copy["name"] == "Fat loss · 8 weeks (copy)" and copy["client_count"] == 0 and copy["can_edit"] is True
    assert trainer.patch(f"{P}{copy['id']}/", {"name": "Aman fat loss"}, format="json").status_code == 200
    assert trainer.delete(f"{P}{copy['id']}/").status_code == 204


def test_trainer_builds_a_program_they_created(trainer):
    r = trainer.post(P, {"name": "Aman Upper Lower", "weeks": 2, "days_per_week": 3}, format="json")
    assert r.status_code == 201, r.content
    d = r.json()
    assert d["can_edit"] is True and len(d["program_weeks"]) == 2
    weeks = d["program_weeks"]
    from apps.training.models import Exercise

    ex = Exercise.objects.get(name="Barbell Bench Press")
    weeks[0]["days"][0]["name"] = "Upper A"
    weeks[0]["days"][0]["rest_note"] = "Warm up first."
    weeks[0]["days"][0]["exercises"] = [{"exercise": str(ex.id), "sets": 4, "reps": "6–8", "rest_seconds": 120,
                                         "override": {"name": "Paused bench"}}]
    r = trainer.put(f"{P}{d['id']}/structure/", {"weeks": weeks}, format="json")
    assert r.status_code == 200, r.content
    day = r.json()["program_weeks"][0]["days"][0]
    assert day["name"] == "Upper A" and day["exercises"][0]["edited"] is True
    r = trainer.post(f"{P}{d['id']}/copy-week/", {"week": 2}, format="json")
    assert r.status_code == 200 and r.json()["weeks"] == 3
    assert trainer.post(f"{P}{d['id']}/archive/").json()["archived"] is True
    assert trainer.delete(f"{P}{d['id']}/").status_code == 204


def test_trainer_assign_keeps_other_trainers_clients(admin, trainer):
    p = _fat_loss()
    aman = User.objects.get(email="aman@trainwithvimal.com")
    others = set(ProgramAssignment.objects.filter(program=p, status="active").exclude(
        client__client_profile__trainer=aman).values_list("client_id", flat=True))
    assert others, "demo data has other trainers' clients on this plan"
    r = trainer.post(f"{P}{p.id}/assign/", {"clients": []}, format="json")
    assert r.status_code == 200, r.content
    still = set(ProgramAssignment.objects.filter(program=p, status="active").values_list("client_id", flat=True))
    assert others <= still
    # put Aman's clients back for the other tests
    mine = list(ProgramAssignment.objects.filter(program=p, status="ended", client__client_profile__trainer=aman)
                .values_list("client_id", flat=True).distinct())
    admin.post(f"{P}{p.id}/assign/", {"clients": [str(x) for x in still | set(mine)]}, format="json")


def test_delete_then_undo_puts_the_clients_back(admin):
    r = admin.post(P, {"name": "Short block", "weeks": 1, "days_per_week": 2}, format="json")
    pid = r.json()["id"]
    riya = User.objects.get(email="riya@example.com")
    rows = admin.get(P + "assign-options/").json()
    assert any(x["id"] == str(riya.id) for x in rows)
    before = ProgramAssignment.objects.filter(client=riya, status="active").first()
    assert admin.post(f"{P}{pid}/assign/", {"clients": [str(riya.id)]}, format="json").json()["added"] == 1
    assert admin.get(f"{P}{pid}/delete-preview/").json()["clients"] == 1
    assert admin.delete(f"{P}{pid}/").status_code == 204
    assert not ProgramAssignment.objects.filter(program_id=pid, status="active").exists()
    r = admin.post(f"{P}{pid}/restore/")
    assert r.status_code == 200, r.content
    assert ProgramAssignment.objects.filter(program_id=pid, client=riya, status="active").exists()
    # tidy up: Riya goes back to her own plan
    ProgramAssignment.objects.filter(program_id=pid).delete()
    if before:
        ProgramAssignment.objects.filter(id=before.id).update(status="active", end_date=None)
    Program.all_objects.filter(id=pid).delete()
