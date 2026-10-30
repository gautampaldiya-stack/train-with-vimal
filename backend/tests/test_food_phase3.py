"""Phase 3: a planned food's own state (eaten / skipped / not logged yet), skipped stays skipped, totals from the
logged entries, portions, up to 4 photos a meal, and the kcal-vs-macros check."""
import logging

from django.utils import timezone

from apps.common.calc import nutrition_totals
from apps.nutrition.models import FoodLogEntry

from .test_client_food import PNG, _day


def _today():
    return timezone.localdate().isoformat()


def _meal(c, n=2):
    """Today's first meal with at least [n] foods that nothing has touched yet."""
    return next(m for m in _day(c)["meals"] if len(m["items"]) >= n and m["pill"] not in ("logged", "skipped"))


def _act(c, meal, op, **body):
    r = c.post(f"/api/v1/me/food/meals/{meal['id']}/{op}/", {"date": _today(), **body}, format="json")
    assert r.status_code == 200, r.content
    return r.json(), next(m for m in r.json()["meals"] if m["id"] == meal["id"])


def _eaten_kcal(c, meal):
    rows = FoodLogEntry.objects.filter(client__email="riya@example.com", date=_today(), meal_id=meal["id"])
    return nutrition_totals(rows)["kcal"]


def test_skipped_meal_stays_skipped_until_she_logs_it(client_user):
    meal = _meal(client_user)
    _, m = _act(client_user, meal, "skip")
    assert m["pill"] == "skipped" and {i["state"] for i in m["items"]} == {"skipped"}
    assert m["eaten"]["kcal"] == 0
    # opening the day again later changes nothing
    m = next(x for x in _day(client_user)["meals"] if x["id"] == meal["id"])
    assert m["pill"] == "skipped" and m["eaten"]["kcal"] == 0
    # only her own tap logs it: every food eaten, the full planned kcal
    _, m = _act(client_user, meal, "eat")
    assert m["pill"] == "logged" and {i["state"] for i in m["items"]} == {"eaten"}
    assert m["eaten"]["kcal"] == m["kcal"]


def test_each_food_has_its_own_state_and_totals_follow(client_user):
    meal = _meal(client_user)
    a, b = meal["items"][0], meal["items"][1]
    _, m = _act(client_user, meal, "item", item=a["item"], action="eat")
    assert [i["state"] for i in m["items"]][:2] == ["eaten", ""]
    assert m["pill"] != "logged"  # one food is still not logged
    assert round(_eaten_kcal(client_user, meal)) == a["kcal"]
    _, m = _act(client_user, meal, "item", item=b["item"], action="skip")
    assert [i["state"] for i in m["items"]][:2] == ["eaten", "skipped"]
    assert round(_eaten_kcal(client_user, meal)) == a["kcal"]  # a skipped food adds nothing
    # Mark as eaten: the foods not skipped are eaten, the skipped one stays out
    day, m = _act(client_user, meal, "eat")
    assert m["pill"] == "logged" and m["items"][1]["state"] == "skipped"
    rest = sum(i["kcal"] for i in m["items"]) - b["kcal"]
    assert abs(m["eaten"]["kcal"] - rest) <= 1  # rounded once from the unrounded entries
    # undo: back to "not logged yet", nothing counted
    _, m = _act(client_user, meal, "unlog")
    assert {i["state"] for i in m["items"]} == {""} and m["eaten"]["kcal"] == 0


def test_portion_change_keeps_the_states_and_updates_the_numbers(client_user):
    meal = _meal(client_user)
    a = meal["items"][0]
    _act(client_user, meal, "item", item=a["item"], action="eat")
    before = _eaten_kcal(client_user, meal)
    _, m = _act(client_user, meal, "portions", portions={str(a["item"]): a["planned_quantity"] * 2})
    assert m["items"][0]["state"] == "eaten" and m["items"][0]["edited"] is True
    assert abs(_eaten_kcal(client_user, meal) - 2 * before) < 0.01  # double portion = double kcal
    # Set to default: the planned portion again
    _, m = _act(client_user, meal, "portions", portions={})
    assert m["items"][0]["edited"] is False
    assert abs(_eaten_kcal(client_user, meal) - before) < 0.01


def test_deleted_entry_leaves_the_day_total(client_user):
    meal = _meal(client_user, n=1)
    day, _ = _act(client_user, meal, "eat")
    total = day["macros"]["kcal"]
    row = next(x for x in day["log"] if x["meal"] == meal["id"])
    assert client_user.delete(f"/api/v1/me/food-log/{row['id']}/").status_code == 200
    assert abs(_day(client_user)["macros"]["kcal"] - (total - row["kcal"])) <= 1
    m = next(x for x in _day(client_user)["meals"] if x["id"] == meal["id"])
    deleted = next(i for i in m["items"] if i["food"] == row["food"])
    assert deleted["state"] == ""  # that food is "not logged yet" again, not still "eaten"


def test_up_to_four_photos_a_meal(client_user):
    meal = _meal(client_user, n=1)
    _act(client_user, meal, "eat", photo=PNG)
    for _ in range(3):
        _, m = _act(client_user, meal, "photo_add", photo=PNG)
    assert len(m["photos"]) == 4 and all(p.startswith("http") for p in m["photos"])
    r = client_user.post(f"/api/v1/me/food/meals/{meal['id']}/photo_add/", {"date": _today(), "photo": PNG},
                         format="json")
    assert r.status_code == 400  # a fifth one
    _, m = _act(client_user, meal, "unlog")
    assert m["photos"] == []


def test_kcal_that_does_not_match_the_macros_is_logged(client_user, caplog):
    with caplog.at_level(logging.WARNING, logger="apps.nutrition.services"):
        r = client_user.post("/api/v1/me/food-log/", {"meal_name": "Snack", "name": "Odd bar", "kcal": 500,
                                                       "protein": 10, "carbs": 20, "fat": 5}, format="json")
    assert r.status_code == 201, r.content
    assert "Odd bar" in caplog.text and "165 kcal from 4P+4C+9F" in caplog.text  # 40 + 80 + 45 = 165


def test_day_target_is_what_the_plan_assigns(client_user):
    """Probid 2026-10-30: the target is the day's planned foods added up, so eating all of them leaves nothing."""
    d = _day(client_user)
    planned = sum(m["assigned"]["kcal"] for m in d["meals"])
    assert abs(d["plan"]["kcal"] - planned) <= len(d["meals"])  # each meal rounded once
    assert d["ring"]["target"] == d["plan"]["kcal"]
    for m in d["meals"]:
        _act(client_user, m, "eat")
    d = _day(client_user)
    off_plan = sum(e["kcal"] for e in d["log"] if e["source"] != "plan")
    assert abs(d["ring"]["eaten"] - off_plan - d["ring"]["target"]) <= len(d["meals"])


def test_assigned_stays_the_planned_amount_after_a_portion_change(client_user):
    meal = _meal(client_user, n=1)
    a = meal["items"][0]
    before = meal["assigned"]["kcal"]
    _, m = _act(client_user, meal, "portions", portions={str(a["item"]): a["planned_quantity"] * 2})
    assert m["assigned"]["kcal"] == before and m["kcal"] > before  # "ate X of 259": the of stays what was assigned


def test_a_meal_cannot_be_logged_before_it_opens(client_user, settings):
    """Probid 2026-10-30: nothing before the meal's time; it opens 30 minutes before."""
    from datetime import datetime, timedelta

    from django.utils import timezone

    from apps.nutrition.models import Meal

    settings.MEAL_OPEN_BEFORE_MINUTES = 30
    meal = _meal(client_user, n=1)
    later = (timezone.localtime() + timedelta(hours=2)).time().replace(second=0, microsecond=0)
    if later < timezone.localtime().time():  # past midnight: no "later today" to test with
        return
    Meal.objects.filter(id=meal["id"]).update(time=later)
    r = client_user.post(f"/api/v1/me/food/meals/{meal['id']}/eat/", {"date": _today()}, format="json")
    assert r.status_code == 400 and "opens at" in str(r.json()).lower()
    m = next(x for x in _day(client_user)["meals"] if x["id"] == meal["id"])
    opens = datetime.fromisoformat(m["opens_at"].replace("Z", "+00:00"))
    assert abs((timezone.localtime(opens) - (timezone.localtime() + timedelta(hours=2) - timedelta(minutes=30))).total_seconds()) < 120
    Meal.objects.filter(id=meal["id"]).update(time=(timezone.localtime() + timedelta(minutes=20)).time())
    if (timezone.localtime() + timedelta(minutes=20)).date() == timezone.localdate():
        _act(client_user, meal, "eat")  # 20 minutes before: open
