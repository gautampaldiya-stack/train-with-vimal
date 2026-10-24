"""Staff Notifications page (D-59): the list rows carry the actor's initials and colour, `unread/` gives the
total for the sub line, and the live socket row has the same names as a list row."""
from apps.accounts.models import User
from apps.notifications.models import Notification
from apps.notifications.services import _serialize, notify

N = "/api/v1/notifications/"


def _aman():
    return User.objects.get(email="aman@trainwithvimal.com")


def test_rows_have_actor_initials_and_colour(trainer):
    aman = _aman()
    riya = User.objects.filter(role="client").first()
    notify(aman, "checkin_submitted", "Riya sent her check-in", "Week 4", data={"route": "/checkins"}, actor=riya)
    row = trainer.get(N, {"page_size": 5}).json()["results"][0]
    assert row["title"] == "Riya sent her check-in"
    assert row["actor_initials"] == riya.initials
    assert row["actor_color"] == riya.avatar_color
    assert row["data"]["route"] == "/checkins"


def test_unread_gives_count_and_total(trainer):
    aman = _aman()
    Notification.objects.filter(recipient=aman).delete()
    for i in range(3):
        notify(aman, "reminder", f"Note {i}")
    first = Notification.objects.filter(recipient=aman).first()
    trainer.post(f"{N}{first.id}/read/")
    assert trainer.get(N + "unread/").json() == {"count": 2, "total": 3}
    assert len(trainer.get(N, {"unread": 1}).json()["results"]) == 2


def test_read_unread_delete_and_read_all(trainer):
    aman = _aman()
    Notification.objects.filter(recipient=aman).delete()
    notify(aman, "reminder", "One")
    notify(aman, "reminder", "Two")
    n = Notification.objects.filter(recipient=aman, title="One").get()
    assert trainer.post(f"{N}{n.id}/read/").json()["read_at"]
    assert trainer.post(f"{N}{n.id}/unread_one/").json()["read_at"] is None
    assert trainer.delete(f"{N}{n.id}/").status_code == 204
    assert trainer.post(N + "read_all/").json() == {"updated": 1}
    assert trainer.get(N + "unread/").json() == {"count": 0, "total": 1}


def test_only_own_notifications(trainer, admin):
    owner = User.objects.get(role="admin")
    notify(owner, "reminder", "For the admin only")
    n = Notification.objects.filter(recipient=owner, title="For the admin only").get()
    assert all(r["title"] != "For the admin only" for r in trainer.get(N, {"page_size": 50}).json()["results"])
    assert trainer.post(f"{N}{n.id}/read/").status_code == 404
    assert trainer.delete(f"{N}{n.id}/").status_code == 404


def test_live_payload_matches_a_list_row(trainer):
    aman = _aman()
    riya = User.objects.filter(role="client").first()
    notify(aman, "checkin_submitted", "Live one", actor=riya)
    n = Notification.objects.filter(recipient=aman, title="Live one").get()
    p = _serialize(n)
    assert (p["actor_name"], p["actor_initials"], p["actor_color"]) == (riya.full_name, riya.initials, riya.avatar_color)
    assert _serialize(Notification(recipient=aman, title="x", event="reminder"))["actor_initials"] is None
