"""Admin → Emails & alerts (boards Emails / EmailsMobile, D-52): message list and editor data, team alerts,
quiet hours, the daily digest and the sender."""
from datetime import datetime

from django.utils import timezone

from apps.accounts.models import User
from apps.notifications.models import MessageTemplate, Notification, NotificationSettings, TeamAlertSetting
from apps.notifications.staff import send_digests, team_alert

URL = "/api/v1/message-templates/"


def test_list_reads_like_the_board(admin):
    rows = admin.get(URL).json()
    keys = [t["key"] for t in rows]
    assert keys[:3] == ["client-invite", "welcome", "password-reset"]  # board order, not A to Z
    t = {r["key"]: r for r in rows}
    assert t["trainer-invite"]["group"] == "team"
    assert t["checkin-reminder"]["when"] == "When a check-in is due or was missed"
    assert t["welcome"]["sent_by"] == "Sent by the app when you approve someone in Approvals"
    assert t["welcome"]["channels"]["push"]["title"] == "Welcome aboard, {{first_name}}"
    used = {u["name"]: u["line"] for u in t["renewal-reminder"]["used_in"]}
    assert used == {"Renewal reminder": "Steps 1 and 3"}
    assert t["onboarding-form-reminder"]["used_in"][0]["line"] == "Step 3 · WhatsApp"


def test_new_template_then_undo_its_delete(admin):
    r = admin.post(URL, {"name": "Workout streak", "group": "coaching", "channels": ["push", "whatsapp"]}, format="json")
    assert r.status_code == 201, r.content
    t = r.json()
    assert t["is_custom"] and t["when"] == "By an automation you pick" and t["used_in"] == []
    chans = t["channels"]
    chans["push"].update(title="On a roll", body="7 workouts in a row, {{first_name}}!")
    chans["whatsapp"]["body"] = "Hi {{first_name}}, 7 in a row. Keep it going!"
    assert admin.patch(URL + f"{t['id']}/", {"channels": chans}, format="json").status_code == 200
    assert admin.delete(URL + f"{t['id']}/").status_code == 204
    # Undo: the same key and words come back
    r = admin.post(URL, {"key": t["key"], "name": t["name"], "group": "coaching", "channels": ["push", "whatsapp"],
                         "texts": chans}, format="json")
    assert r.status_code == 201, r.content
    back = r.json()
    assert back["key"] == t["key"] and back["channels"]["push"]["body"] == "7 workouts in a row, {{first_name}}!"


def test_built_in_cannot_be_deleted_and_needs_text_on_its_channels(admin):
    w = MessageTemplate.objects.get(key="welcome")
    assert admin.delete(URL + f"{w.id}/").status_code == 400
    chans = dict(w.channels)
    chans["email"] = {**chans["email"], "subject": ""}
    r = admin.patch(URL + f"{w.id}/", {"channels": chans}, format="json")
    assert r.status_code == 400


def test_team_alerts_in_board_order_and_enable_all(admin):
    rows = admin.get("/api/v1/team-alerts/").json()
    assert [r["label"] for r in rows] == ["New client", "Check-in submitted", "Plan updated", "Missed workout"]
    assert rows[3]["description"] == "2+ workouts skipped in a row"
    r = admin.patch(f"/api/v1/team-alerts/{rows[2]['id']}/", {"channels": {"push": True}}, format="json")
    assert r.json()["channels"] == {"email": False, "push": True, "whatsapp": False, "in_app": False}
    rows = admin.post("/api/v1/team-alerts/enable-all/").json()
    assert all(all(r["channels"].values()) for r in rows)


def test_team_alert_goes_to_owner_and_trainer_on_picked_channels(db):
    riya = User.objects.get(email="riya@example.com")
    trainer = riya.client_profile.trainer
    vimal = User.objects.get(email="vimal@trainwithvimal.com")
    TeamAlertSetting.objects.filter(event="plan_updated").update(
        channels={"email": False, "push": False, "whatsapp": False, "in_app": True})
    sent = team_alert("plan_updated", riya, "Plan changed", notify_event="plan_updated", actor=trainer)
    assert {n.recipient_id for n in sent} == {vimal.id}  # never the person who did it
    sent = team_alert("plan_updated", riya, "Plan changed", notify_event="plan_updated", actor=vimal)
    assert {n.recipient_id for n in sent} == {trainer.id}
    TeamAlertSetting.objects.filter(event="plan_updated").update(channels={"in_app": False})
    before = Notification.objects.count()
    assert team_alert("plan_updated", riya, "Plan changed", notify_event="plan_updated") == []
    assert Notification.objects.count() == before


def test_digest_follows_off_daily_weekly(db):
    s = NotificationSettings.load()
    tuesday = timezone.make_aware(datetime(2026, 10, 20, 8, 0))
    monday = timezone.make_aware(datetime(2026, 10, 19, 8, 0))
    s.digest = "off"
    s.save()
    assert send_digests(tuesday) == []
    s.digest = "weekly"
    s.save()
    assert send_digests(tuesday) == []
    sent = send_digests(monday)
    assert sent and all(not n.in_app for n in sent)
    assert sent[0].title == "Your weekly digest" and "Check-ins to review:" in sent[0].body


def test_sender_settings_validate(admin):
    url = "/api/v1/settings/notifications/"
    assert admin.patch(url, {"sender_name": "  "}, format="json").status_code == 400
    assert admin.patch(url, {"whatsapp_number": "call me"}, format="json").status_code == 400
    r = admin.patch(url, {"whatsapp_number": "+91 98200  12345", "digest": "weekly"}, format="json")
    assert r.status_code == 200 and r.json()["whatsapp_number"] == "+91 98200 12345" and r.json()["digest"] == "weekly"
