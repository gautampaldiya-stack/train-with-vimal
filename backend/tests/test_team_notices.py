"""Trainer Me → Account → Notifications: Daily summary (8 am, the Dashboard's numbers) and Gym news (admin posts,
trainers with the toggle on get it in the bell and by push)."""
from datetime import datetime
from unittest import mock

from django.utils import timezone

from apps.accounts.models import User
from apps.notifications import reminders
from apps.notifications.models import Delivery, GymNews, Notification, StaffNotificationPreference
from apps.notifications.staff import daily_summary_counts

ME = "/api/v1/trainers/me/"


def _at(hour, minute=0):
    return timezone.make_aware(datetime.combine(timezone.localdate(), datetime.min.time())).replace(hour=hour,
                                                                                                 minute=minute)


def _run_daily(hour=8, minute=2):
    with mock.patch.object(reminders, "_local_now", return_value=_at(hour, minute)):
        return reminders.daily_summaries()


def test_daily_summary_respects_the_toggle_and_matches_the_dashboard(trainer, django_capture_on_commit_callbacks):
    aman = User.objects.get(email="aman@trainwithvimal.com")
    trainer.put(ME + "notifications/", {"daily_summary": False}, format="json")
    assert _run_daily() == 0
    assert not Notification.objects.filter(recipient=aman, event="daily_summary").exists()

    trainer.put(ME + "notifications/", {"daily_summary": True}, format="json")
    assert _run_daily(hour=7) == 0  # only in the 8 am window
    with django_capture_on_commit_callbacks(execute=True):
        assert _run_daily() >= 1
    n = Notification.objects.get(recipient=aman, event="daily_summary")
    dash = trainer.get("/api/v1/dashboard/trainer/").json()
    c = daily_summary_counts(aman)
    assert len(c["sessions"]) == len(dash["today"])
    assert c["checkins"] == dash["checkins_total"] and c["need"] == len(dash["need"])
    s = len(dash["today"])
    assert n.title.startswith(f"Today: {s or 'no'} session{'s' * (s != 1)}, {c['checkins'] or 'no'} check-in")
    assert n.data["route"] == "/dashboard" and n.in_app
    # bell + push + email (the board: "Email at 8:00 am with your day")
    assert set(Delivery.objects.filter(notification=n).values_list("channel", flat=True)) <= {"push", "email"}
    # once a day, however often beat runs
    assert _run_daily(minute=10) == 0
    assert Notification.objects.filter(recipient=aman, event="daily_summary").count() == 1
    # it shows in the trainer's bell
    assert any(x["event"] == "daily_summary" for x in trainer.get("/api/v1/notifications/").json()["results"])


def test_daily_summary_skips_push_and_email_when_switched_off(trainer, django_capture_on_commit_callbacks):
    aman = User.objects.get(email="aman@trainwithvimal.com")
    trainer.put(ME + "notifications/", {"daily_summary": True}, format="json")
    StaffNotificationPreference.objects.update_or_create(user=aman, defaults={"push": False, "email": False})
    with django_capture_on_commit_callbacks(execute=True):
        _run_daily()
    n = Notification.objects.get(recipient=aman, event="daily_summary")
    assert not Delivery.objects.filter(notification=n).exists()


def test_gym_news_admin_only_and_goes_to_trainers_with_it_on(admin, trainer, client_user):
    aman = User.objects.get(email="aman@trainwithvimal.com")
    assert trainer.post("/api/v1/gym-news/", {"title": "Hi"}, format="json").status_code == 403
    assert client_user.post("/api/v1/gym-news/", {"title": "Hi"}, format="json").status_code == 403
    r = admin.post("/api/v1/gym-news/", {"title": "  "}, format="json")
    assert r.status_code == 400 and "title" in r.json()["error"]["fields"]

    r = admin.post("/api/v1/gym-news/", {"title": "Gym closed on Sunday", "body": "Floor cleaning."}, format="json")
    assert r.status_code == 201, r.content
    d = r.json()
    assert d["sent_to"] >= 1 and d["author_name"]
    n = Notification.objects.get(recipient=aman, event="gym_news")
    assert n.title == "Gym closed on Sunday" and n.body == "Floor cleaning."
    assert not Notification.objects.filter(recipient__role="admin", event="gym_news").exists()  # not to the poster
    assert not Notification.objects.filter(recipient__role="client", event="gym_news").exists()

    trainer.put(ME + "notifications/", {"gym_news": False}, format="json")
    admin.post("/api/v1/gym-news/", {"title": "Second notice"}, format="json")
    assert not Notification.objects.filter(recipient=aman, title="Second notice").exists()
    lst = admin.get("/api/v1/gym-news/").json()
    assert lst["count"] == GymNews.objects.count() and lst["results"][0]["title"] == "Second notice"
    assert trainer.get("/api/v1/gym-news/").status_code == 403
