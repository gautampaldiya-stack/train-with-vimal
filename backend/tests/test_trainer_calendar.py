"""Trainer Calendar (boards TrainerCalendar / TrainerCalendarMobile): week list, stats, live check, book / move /
cancel + Undo, status, working hours. A trainer sees and books only their own sessions and clients."""
from datetime import datetime, time, timedelta

from django.utils import timezone

from apps.accounts.models import Role, User
from apps.clients.models import ClientProfile
from apps.scheduling.models import Availability, Session


def _aman():
    return User.objects.get(email="aman@trainwithvimal.com")


def _my_client():
    return ClientProfile.objects.filter(trainer=_aman(), removed_at__isnull=True).first().user


def _other_client():
    return ClientProfile.objects.exclude(trainer=_aman()).filter(removed_at__isnull=True, trainer__isnull=False).first()


def _at(days, hh, mm=0):
    d = timezone.localdate() + timedelta(days=days)
    return timezone.make_aware(datetime.combine(d, time(hh, mm)))


def _week():
    mon = timezone.localdate() - timedelta(days=timezone.localdate().weekday())
    return {"from": mon.isoformat(), "to": (mon + timedelta(days=6)).isoformat()}


def _free_day():
    """A day next week with nothing booked for Aman (tests book there)."""
    for days in range(8, 30):
        if not Session.objects.filter(trainer=_aman(), start__date=timezone.localdate() + timedelta(days=days)).exists():
            return days
    raise AssertionError("no free day")


def test_week_list_has_the_panel_fields_and_only_my_sessions(trainer):
    aman = _aman()
    r = trainer.get("/api/v1/sessions/", {**_week(), "trainer": str(aman.id)})
    assert r.status_code == 200, r.content
    rows = r.json()
    assert rows, "seed has sessions this week"
    for s in rows:
        assert s["trainer"] == str(aman.id)
        assert s["status"] != "cancelled"
        assert s["length"] == int((datetime.fromisoformat(s["end"]) - datetime.fromisoformat(s["start"])).total_seconds() // 60)
        assert s["client_plan"] and s["booked_by_name"] is not None
    assert all(r["client_plan"] == "No plan yet" or " · week " in r["client_plan"] for r in rows)


def test_stats_count_only_the_asked_week(trainer):
    aman = _aman()
    wk = {**_week(), "trainer": str(aman.id)}
    rows = trainer.get("/api/v1/sessions/", wk).json()
    st = trainer.get("/api/v1/sessions/stats/", wk).json()
    assert st["total"] == len(rows)
    assert st["done"] == sum(1 for r in rows if r["status"] == "done")
    far = trainer.get("/api/v1/sessions/stats/", {"from": "2020-01-06", "to": "2020-01-12"}).json()
    assert far["total"] == 0


def test_book_check_move_cancel_and_undo(trainer):
    aman, riya = _aman(), _my_client()
    day = _free_day()
    start = _at(day, 9)
    # free
    chk = trainer.get("/api/v1/sessions/check/", {"start": start.isoformat(), "minutes": 60}).json()
    assert chk["state"] in ("free", "outside", "day_off")
    r = trainer.post("/api/v1/sessions/", {"client": str(riya.id), "kind": "one_on_one", "start": start.isoformat(),
                                           "minutes": 60, "place": "Andheri gym floor", "note": "Check the knee",
                                           "tell_client": False}, format="json")
    assert r.status_code == 201, r.content
    sid = r.json()["id"]
    assert r.json()["trainer"] == str(aman.id) and r.json()["length"] == 60
    # clash now
    chk = trainer.get("/api/v1/sessions/check/", {"start": _at(day, 9, 30).isoformat(), "minutes": 15}).json()
    assert chk["state"] == "clash" and chk["with"] == riya.full_name
    # ... but not with itself when moving it
    chk = trainer.get("/api/v1/sessions/check/", {"start": _at(day, 9, 30).isoformat(), "minutes": 60, "exclude": sid}).json()
    assert chk["state"] != "clash"
    # a second booking on top is refused with the one error shape
    r = trainer.post("/api/v1/sessions/", {"client": str(riya.id), "kind": "quick_call", "start": _at(day, 9, 15).isoformat(),
                                           "minutes": 15, "is_call": True}, format="json")
    assert r.status_code == 400 and "start" in r.json()["error"]["fields"]
    # move
    r = trainer.patch(f"/api/v1/sessions/{sid}/", {"start": _at(day, 11).isoformat(), "minutes": 60, "tell_client": False},
                      format="json")
    assert r.status_code == 200, r.content
    assert timezone.localtime(Session.objects.get(id=sid).start).hour == 11
    # done / not done
    assert trainer.post(f"/api/v1/sessions/{sid}/status/", {"status": "done"}, format="json").json()["status"] == "done"
    assert trainer.post(f"/api/v1/sessions/{sid}/status/", {"status": "booked"}, format="json").json()["status"] == "booked"
    # cancel + undo
    assert trainer.delete(f"/api/v1/sessions/{sid}/?tell_client=false").status_code == 200
    assert Session.objects.get(id=sid).status == "cancelled"
    assert trainer.post(f"/api/v1/sessions/{sid}/restore/").status_code == 200
    assert Session.objects.get(id=sid).status == "booked"
    Session.objects.filter(id=sid).delete()


def test_call_link_takes_a_link_or_a_number(trainer):
    riya = _my_client()
    day = _free_day()
    base = {"client": str(riya.id), "kind": "quick_call", "minutes": 15, "is_call": True, "tell_client": False}
    bad = trainer.post("/api/v1/sessions/", {**base, "start": _at(day, 7).isoformat(), "call_link": "not a link"}, format="json")
    assert bad.status_code == 400 and "call_link" in bad.json()["error"]["fields"]
    ids = []
    for i, link in enumerate(["meet.google.com/abc-defg-hij", "9820155432"]):
        r = trainer.post("/api/v1/sessions/", {**base, "start": _at(day, 8 + i).isoformat(), "call_link": link}, format="json")
        assert r.status_code == 201, r.content
        ids.append(r.json()["id"])
    Session.objects.filter(id__in=ids).delete()


def test_trainer_cannot_book_or_check_someone_elses(trainer):
    other = _other_client()
    if other is None:
        return
    r = trainer.post("/api/v1/sessions/", {"client": str(other.user_id), "start": _at(_free_day(), 10).isoformat(),
                                           "minutes": 60}, format="json")
    assert r.status_code == 400 and "client" in r.json()["error"]["fields"]
    r = trainer.get("/api/v1/sessions/check/", {"trainer": str(other.trainer_id), "start": _at(3, 10).isoformat()})
    assert r.status_code == 403


def test_working_hours_round_trip_and_outside_warning(trainer):
    aman = _aman()
    before = list(Availability.objects.filter(trainer=aman).values("weekday", "is_working", "start", "end"))
    days = [{"weekday": d, "is_working": d < 6, "start": "06:30", "end": "21:00" if d == 4 else "20:00"} for d in range(7)]
    r = trainer.put("/api/v1/availability/", {"days": days}, format="json")
    assert r.status_code == 200, r.content
    assert r.json()["working_days"] == 6 and r.json()["days"][4]["end"].startswith("21:00")
    bad = trainer.put("/api/v1/availability/", {"days": [{**d, "end": "05:00"} if d["weekday"] == 0 else d for d in days]},
                      format="json")
    assert bad.status_code == 400 and "error" in bad.json()
    # next Sunday is a day off
    sunday = (6 - timezone.localdate().weekday()) % 7 or 7
    chk = trainer.get("/api/v1/sessions/check/", {"start": _at(sunday + 7, 10).isoformat(), "minutes": 60}).json()
    assert chk["state"] in ("day_off", "clash")
    Availability.objects.filter(trainer=aman).delete()
    for b in before:
        Availability.objects.create(trainer=aman, **b)


def test_clients_cannot_use_the_calendar(client_user):
    assert client_user.get("/api/v1/sessions/").status_code == 403
    assert client_user.get("/api/v1/availability/").status_code == 403
    assert Role.CLIENT
