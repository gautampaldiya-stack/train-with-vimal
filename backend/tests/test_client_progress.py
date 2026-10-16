from datetime import timedelta

from django.utils import timezone


def test_progress_page_has_goal_measurements_lifts_and_photos(client_user):
    r = client_user.get("/api/v1/me/progress/")
    assert r.status_code == 200, r.content
    d = r.json()
    assert d["start"]["kg"] == 72.0 and d["goal"]["kg"] == 62.0 and d["now"]["kg"]
    assert len(d["weights"]) > 3 and {"date", "kg"} <= set(d["weights"][0])
    assert len(d["measurements"]) >= 2 and d["measurements"][0]["waist"] == 84.0
    assert d["next_measure"]["date"] >= timezone.localdate().isoformat()
    assert d["lifts"] and {"best", "started", "ups", "series", "note"} <= set(d["lifts"][0])
    a = d["adherence"]
    assert a["program"] and len(a["weeks"]) == 6 and a["done"] <= a["planned"]
    sets = d["photo_sets"]
    assert sets[0]["label"] == "Start photos" and len(sets[0]["photos"]) == 3
    assert any(len(s["photos"]) == 2 for s in sets)  # week 2 has no Back photo


def test_log_weight_replaces_the_same_day(client_user):
    day = (timezone.localdate() - timedelta(days=1)).isoformat()
    client_user.post("/api/v1/me/weights/", {"date": day, "weight_kg": 70.2}, format="json")
    r = client_user.post("/api/v1/me/weights/", {"date": day, "weight_kg": 70.0}, format="json")
    assert r.status_code == 201
    ws = [w for w in client_user.get("/api/v1/me/progress/").json()["weights"] if w["date"] == day]
    assert len(ws) == 1 and ws[0]["kg"] == 70.0
    future = (timezone.localdate() + timedelta(days=1)).isoformat()
    assert client_user.post("/api/v1/me/weights/", {"date": future, "weight_kg": 70}, format="json").status_code == 400


def test_history_pages_days_and_filters_by_type(client_user):
    r = client_user.get("/api/v1/me/history/", {"range": "month", "limit": 5})
    assert r.status_code == 200, r.content
    d = r.json()
    assert d["summary"]["days"] == 30 and d["count"] > 5 and len(d["days"]) == 5
    dates = [x["date"] for x in d["days"]]
    assert dates == sorted(dates, reverse=True)
    more = client_user.get("/api/v1/me/history/", {"range": "month", "limit": 5, "offset": 5}).json()
    assert more["days"][0]["date"] < dates[-1]
    w = client_user.get("/api/v1/me/history/", {"range": "month", "type": "workout"}).json()
    assert w["days"] and all(e["type"] == "workout" for x in w["days"] for e in x["entries"])
    done = [e for x in w["days"] for e in x["entries"] if not e.get("missed")]
    assert done and done[0]["detail"]
    bad = client_user.get("/api/v1/me/history/", {"range": "year"})
    assert bad.status_code == 400 and "error" in bad.json()


def test_history_is_for_clients_only(trainer):
    assert trainer.get("/api/v1/me/history/").status_code == 403


def test_add_photo_as_data_url_then_replace_and_undo(client_user):
    import base64
    from io import BytesIO

    from PIL import Image
    buf = BytesIO()
    Image.new("RGB", (8, 8), (200, 220, 250)).save(buf, "JPEG")
    png = "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()
    r = client_user.post("/api/v1/me/photos/", {"pose": "side", "image": png}, format="json")
    assert r.status_code == 201, r.content
    first = r.json()
    again = client_user.post("/api/v1/me/photos/", {"pose": "side", "image": png}, format="json").json()
    assert not first["replaced"] and again["replaced"]
    today = timezone.localdate().isoformat()
    s = next(x for x in client_user.get("/api/v1/me/progress/").json()["photo_sets"] if x["date"] == today)
    assert [p["pose"] for p in s["photos"]].count("side") == 1
    assert client_user.delete(f"/api/v1/me/photos/?id={again['id']}").status_code == 204
    none = client_user.post("/api/v1/me/photos/", {"pose": "front"}, format="json")
    assert none.status_code == 400 and "image" in none.json()["error"]["fields"]
