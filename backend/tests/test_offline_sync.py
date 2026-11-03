from datetime import timedelta

from django.utils import timezone

from apps.nutrition.models import Food, FoodLogEntry


def _payload(day):
    food = Food.objects.get(name="Banana", source="builtin")
    return {"meal_name": "Snack", "food": str(food.id), "quantity": 1, "date": day.isoformat()}


def test_same_idempotency_key_logs_once(client_user):
    day = timezone.localdate()
    body = _payload(day)
    before = FoodLogEntry.objects.filter(client__email="riya@example.com").count()
    r1 = client_user.post("/api/v1/me/food-log/", body, format="json", HTTP_IDEMPOTENCY_KEY="k-banana-1")
    r2 = client_user.post("/api/v1/me/food-log/", body, format="json", HTTP_IDEMPOTENCY_KEY="k-banana-1")
    assert r1.status_code == r2.status_code == 201
    assert r2.headers.get("Idempotent-Replay")
    assert r1.json()["id"] == r2.json()["id"]
    assert FoodLogEntry.objects.filter(client__email="riya@example.com").count() == before + 1


def test_offline_log_keeps_its_own_day(client_user):
    day = timezone.localdate() - timedelta(days=2)
    r = client_user.post("/api/v1/me/food-log/", _payload(day), format="json", HTTP_IDEMPOTENCY_KEY="k-old-day")
    assert r.status_code == 201
    assert FoodLogEntry.objects.get(id=r.json()["id"]).date == day


def test_key_reused_on_other_path_is_409(client_user):
    client_user.post("/api/v1/me/food-log/", _payload(timezone.localdate()), format="json",
                     HTTP_IDEMPOTENCY_KEY="k-shared")
    r = client_user.post("/api/v1/me/food-log/water/", {"ml": 250}, format="json", HTTP_IDEMPOTENCY_KEY="k-shared")
    assert r.status_code == 409
