"""Client profile → Plans → Supplements → Edit for X: the client's own copy of the supplement plan, Reset to
master; the library lists only masters; the client app reads the copy."""
from apps.clients.models import ClientProfile
from apps.habits.models import SupplementAssignment, SupplementLog, SupplementPlan
from django.utils import timezone

from .conftest import login


def _two_clients(trainer):
    ids = [c["id"] for c in trainer.get("/api/v1/clients/", {"page_size": 50}).json()["results"]]
    riya = trainer.get("/api/v1/clients/", {"search": "riya"}).json()["results"][0]["id"]
    other = next(i for i in ids if i != riya)
    return riya, other


def _on_same_master(trainer):
    riya, other = _two_clients(trainer)
    master = SupplementPlan.objects.filter(is_master=True, items__isnull=False).distinct().first()
    rows = {}
    for cid in (riya, other):
        r = trainer.post(f"/api/v1/clients/{cid}/supplement-plans/", {"plan": str(master.id), "when": "now"},
                         format="json")
        assert r.status_code == 201, r.content
        rows[cid] = next(a for a in r.json()["current"] if a["plan"] == str(master.id))
    return master, riya, other, rows


def _items(row):
    return [{k: i[k] for k in ("id", "name", "dose", "how", "timing", "days", "with_food")} for i in row["items"]]


def test_first_edit_makes_a_copy_only_for_that_client(trainer, client_user):
    master, riya, other, rows = _on_same_master(trainer)
    before = sorted((i.name, i.dose) for i in master.items.all())
    row = rows[riya]
    assert row["custom"] is False and row["copy"] is None
    # Riya ticked the first supplement today: the tick moves to her copy.
    first = row["items"][0]
    r = client_user.post(f"/api/v1/me/supplements/{first['id']}/", {"taken": True}, format="json")
    assert r.status_code == 200, r.content

    items = _items(row)
    items[0]["dose"] = "2 tablets"
    items.append({"name": "Creatine", "dose": "5 g", "how": "In water", "timing": "post_workout", "days": [],
                  "with_food": False})
    r = trainer.put(f"/api/v1/clients/{riya}/supplement-plans/{row['id']}/items/", {"items": items}, format="json")
    assert r.status_code == 200, r.content
    d = r.json()
    assert d["custom"] is True and d["copy"] and d["plan"] == str(master.id)
    assert d["items"][0]["dose"] == "2 tablets" or any(i["dose"] == "2 tablets" for i in d["items"])
    assert any(i["name"] == "Creatine" for i in d["items"])

    # The master and the other client stay the same.
    assert sorted((i.name, i.dose) for i in master.items.all()) == before
    o = next(a for a in trainer.get(f"/api/v1/clients/{other}/supplement-plans/").json()["current"]
             if a["id"] == rows[other]["id"])
    assert o["custom"] is False and sorted((i["name"], i["dose"]) for i in o["items"]) == before

    # The copy is not in the library.
    lib = trainer.get("/api/v1/supplement-plans/").json()
    assert str(d["copy"]) not in {str(p["id"]) for p in lib}

    # The client app and the tick read the copy.
    a = SupplementAssignment.objects.get(id=row["id"])
    copy_ids = set(a.custom_plan.items.values_list("id", flat=True))
    assert SupplementLog.objects.filter(client_id=riya, date=timezone.localdate(), item_id__in=copy_ids).exists()
    day = client_user.get("/api/v1/me/habits/").json()
    names = {s["name"] for s in day["supplements"]}
    assert "Creatine" in names
    assert {s["id"] for s in day["supplements"] if s["name"] == "Creatine"} <= copy_ids
    # A master item can no longer be ticked by Riya.
    assert client_user.post(f"/api/v1/me/supplements/{first['id']}/", {"taken": True},
                            format="json").status_code == 404

    # Second save edits the same copy (no new copy).
    items2 = _items(d)
    items2 = [i for i in items2 if i["name"] != "Creatine"]
    r = trainer.put(f"/api/v1/clients/{riya}/supplement-plans/{row['id']}/items/", {"items": items2}, format="json")
    assert r.status_code == 200 and r.json()["copy"] == d["copy"]
    assert not any(i["name"] == "Creatine" for i in r.json()["items"])


def test_reset_to_master(trainer):
    master, riya, _, rows = _on_same_master(trainer)
    row = rows[riya]
    items = _items(row)
    items[0]["dose"] = "3 tablets"
    url = f"/api/v1/clients/{riya}/supplement-plans/{row['id']}/"
    assert trainer.put(f"{url}items/", {"items": items}, format="json").status_code == 200
    r = trainer.post(f"{url}reset/")
    assert r.status_code == 200, r.content
    d = r.json()
    assert d["custom"] is False and d["copy"] is None
    assert sorted(i["id"] for i in d["items"]) == sorted(master.items.values_list("id", flat=True))


def test_bad_items_are_refused(trainer):
    _, riya, _, rows = _on_same_master(trainer)
    items = _items(rows[riya])
    items[0]["days"] = [9]
    r = trainer.put(f"/api/v1/clients/{riya}/supplement-plans/{rows[riya]['id']}/items/", {"items": items},
                    format="json")
    assert r.status_code == 400
    assert SupplementAssignment.objects.get(id=rows[riya]["id"]).custom_plan_id is None


def test_trainer_cannot_touch_other_trainers_clients(trainer):
    other = ClientProfile.objects.exclude(trainer__email="aman@trainwithvimal.com").first()
    assert other is not None
    master = SupplementPlan.objects.filter(is_master=True).first()
    a, _ = SupplementAssignment.objects.get_or_create(plan=master, client=other.user)
    base = f"/api/v1/clients/{other.user_id}/supplement-plans/{a.id}/"
    assert trainer.put(f"{base}items/", {"items": []}, format="json").status_code == 404
    assert trainer.post(f"{base}reset/").status_code == 404
    a.refresh_from_db()
    assert a.custom_plan_id is None


def test_client_cannot_edit(client_user):
    riya_user = login("riya@example.com")
    a = SupplementAssignment.objects.filter(client__email="riya@example.com", active=True).first()
    if a is None:
        return
    r = riya_user.put(f"/api/v1/clients/{a.client_id}/supplement-plans/{a.id}/items/", {"items": []}, format="json")
    assert r.status_code in (403, 404)


def test_stock_at_home_is_saved_for_the_client(trainer):
    _, riya, _, rows = _on_same_master(trainer)
    items = _items(rows[riya])
    items[0]["stock"] = {"quantity": 12, "unit": "scoops"}
    r = trainer.put(f"/api/v1/clients/{riya}/supplement-plans/{rows[riya]['id']}/items/", {"items": items},
                    format="json")
    assert r.status_code == 200, r.content
    first = next(i for i in r.json()["items"] if i["name"] == items[0]["name"])
    assert first["stock"] == {"quantity": 12, "unit": "scoops"}


def test_running_out_of_stock_is_counted_in_compare(trainer, client_user, django_capture_on_commit_callbacks):
    from datetime import timedelta

    master, riya, other, rows = _on_same_master(trainer)
    first = rows[riya]["items"][0]
    url = f"/api/v1/me/supplements/{first['id']}/"
    with django_capture_on_commit_callbacks(execute=True):
        assert client_user.patch(url, {"quantity": 1, "unit": "scoops"}, format="json").status_code == 200
        r = client_user.post(url, {"taken": True}, format="json")  # last scoop → ran out
        assert r.json()["stock"]["quantity"] == 0
        client_user.patch(url, {"quantity": 5}, format="json")
        client_user.patch(url, {"quantity": 0}, format="json")  # says none left → ran out again
    today = timezone.localdate()
    q = {"a_from": str(today - timedelta(days=20)), "a_to": str(today - timedelta(days=10)),
         "b_from": str(today - timedelta(days=9)), "b_to": str(today)}
    d = trainer.get(f"/api/v1/clients/{riya}/logs/compare/", q).json()
    assert d["b"]["supps"]["ran_out"] == 2 and d["a"]["supps"]["ran_out"] == 0
