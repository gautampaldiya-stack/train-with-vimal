from datetime import date

from django.utils import timezone

from apps.habits.models import HabitLog
from apps.nutrition.models import WaterLog


def _home(c):
    r = c.get("/api/v1/me/home/")
    assert r.status_code == 200, r.content
    return r.json()


def test_home_has_every_card(client_user):
    d = _home(client_user)
    assert d["first_name"] == "Riya" and d["goal"] == "Fat loss"
    assert len(d["strip"]) == 7
    days = [date.fromisoformat(x["date"]) for x in d["strip"]]
    assert days[0].weekday() == 0 and sum(x["today"] for x in d["strip"]) == 1
    for x in d["strip"]:
        assert x["is_rest"] == (not x["exercises"])
        if x["done"]:
            assert x["done_line"].startswith("Done · ")
    assert [m["name"] for m in d["meals"]] == ["Breakfast", "Lunch", "Snack", "Dinner"]
    assert all(m["foods"] and m["kcal"] > 0 for m in d["meals"])
    assert {s["name"] for s in d["supplements"]} == {"Whey protein", "Vitamin D3", "Magnesium"}
    assert d["habits_soon"][0]["name"] == "No sugary drinks"
    assert "No sugary drinks" not in [h["name"] for h in d["habits"]]
    kinds = [c["kind"] for c in d["coming_up"]]
    assert kinds == ["session", "checkin", "plan_end"]
    assert d["coming_up"][0]["place"] == "Gym floor" and d["coming_up"][1]["questions"] > 0
    assert d["unread"] == sum(not n["read"] for n in d["notices"])
    assert d["trainer_note"]["by"]["full_name"] == "Aman Verma" and d["trainer_note"]["body"]


def test_home_is_client_only(trainer):
    assert trainer.get("/api/v1/me/home/").status_code == 403


def test_water_moves_the_water_habit(client_user):
    today = timezone.localdate()
    HabitLog.objects.filter(client__email="riya@example.com", date=today).delete()
    WaterLog.objects.filter(client__email="riya@example.com", date=today).delete()
    r = client_user.post("/api/v1/me/food-log/water/", {"ml": 750, "date": today.isoformat()}, format="json")
    assert r.status_code in (200, 201), r.content
    water = next(h for h in _home(client_user)["habits"] if h["icon"] == "water")
    assert water["value"] == 3 and not water["done"]
    for ml in (2000, 250):
        client_user.post("/api/v1/me/food-log/water/", {"ml": ml, "date": today.isoformat()}, format="json")
    water = next(h for h in _home(client_user)["habits"] if h["icon"] == "water")
    assert water["value"] == 12 and water["done"]
    client_user.post("/api/v1/me/food-log/water/", {"ml": -250, "date": today.isoformat()}, format="json")
    log = HabitLog.objects.get(client__email="riya@example.com", date=today, habit__icon="water")
    assert log.value == 11 and not log.done


def test_mark_all_read_clears_the_bell(client_user):
    assert client_user.post("/api/v1/notifications/read_all/").status_code == 200
    assert _home(client_user)["unread"] == 0


def test_habits_page_week_grid(client_user):
    r = client_user.get("/api/v1/me/habits/")
    assert r.status_code == 200, r.content
    d = r.json()
    wk = d["week"]
    days = [date.fromisoformat(x["date"]) for x in wk["days"]]
    assert len(days) == 7 and days[0].weekday() == 0 and sum(x["today"] for x in wk["days"]) == 1
    assert wk["habits_due"] >= wk["habits_done"] and wk["supps_due"] >= wk["supps_taken"]
    for h in d["habits"]:
        assert len(h["week"]) == 7 and set(h["week"]) <= {"done", "missed", "today", "coming", "off"}
        assert h["week_done"] == h["week"].count("done") and len(h["last_7"]) == 7
    sugar = next(h for h in d["habits"] if h["name"] == "No sugary drinks")
    assert sugar["starts_on"] and set(sugar["week"]) == {"off"}  # starts next Monday
    whey = next(s for s in d["supplements"] if s["name"] == "Whey protein")
    assert whey["group"] == "training" and whey["taken_at"] and whey["stock"]["unit"] == "scoops"
    assert len(whey["week"]) == 7 and len(whey["last_7"]) == 7
    # an earlier week opens with ?date=
    past = date.fromisoformat(wk["start"]).toordinal() - 7
    r = client_user.get("/api/v1/me/habits/", {"date": date.fromordinal(past).isoformat()})
    assert date.fromisoformat(r.json()["week"]["start"]).toordinal() == past


def test_home_layout_saves_and_refuses_unknown_cards(client_user):
    assert _home(client_user)["layout"][:3] == ["workout", "checkin", "food"]
    r = client_user.patch("/api/v1/me/home/layout/", {"layout": ["food", "workout", "food"]}, format="json")
    assert r.status_code == 200 and r.json()["layout"] == ["food", "workout"]
    assert _home(client_user)["layout"] == ["food", "workout"]
    r = client_user.patch("/api/v1/me/home/layout/", {"layout": ["food", "bananas"]}, format="json")
    assert r.status_code == 400 and "layout" in r.json()["error"]["fields"]
    client_user.patch("/api/v1/me/home/layout/", {"layout": []}, format="json")
    assert "water" in _home(client_user)["layout"]


def test_home_adherence_counts_daily_checkins_this_week(client_user):
    from datetime import timedelta

    from apps.accounts.models import User
    from apps.checkins.models import Form, Submission

    riya = User.objects.get(email="riya@example.com")
    today = timezone.localdate()
    monday = today - timedelta(days=today.weekday())
    form = Form.objects.filter(type="daily", status="published").first()
    Submission.objects.filter(client=riya, form_type="daily", date__gte=monday).delete()
    for i in range(today.weekday() + 1):
        if i != 1:
            Submission.objects.create(form=form, form_type="daily", client=riya, date=monday + timedelta(days=i))
    d = _home(client_user)
    assert d["adherence_week"] == {"done": today.weekday() + (0 if today.weekday() >= 1 else 1), "days": today.weekday() + 1}
    assert d["checkin_today"]["status"] == "sent" and d["checkin_today"]["form"] == str(form.id)


def test_home_progress_summary_matches_the_progress_page(client_user):
    p = client_user.get("/api/v1/me/progress/").json()
    s = _home(client_user)["progress_summary"]
    assert s["weight"]["now"] == p["now"]["kg"]
    assert s["weight"]["change"] == round(p["now"]["kg"] - p["start"]["kg"], 1)
    if p["lifts"]:
        assert s["strength"]["now"] == max(l["best"]["kg"] for l in p["lifts"][:1])
