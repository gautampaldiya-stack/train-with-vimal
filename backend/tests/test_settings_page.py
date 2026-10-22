"""Admin → Settings (boards Settings / SettingsMobile, D-53): gym profile, regional defaults, branding,
roles & access, integrations."""
import io

import pytest
from PIL import Image

from apps.accounts.models import Role, User
from apps.gym import integrations
from apps.gym.models import GymSettings, Integration
from apps.notifications import providers
from apps.notifications.models import NotificationSettings


def test_profile_save_moves_last_saved_but_regional_does_not(admin):
    r = admin.get("/api/v1/settings/gym/").json()
    assert r["timezones"][0]["label"] == "Asia/Kolkata (IST)" and r["languages"] == [{"value": "en", "label": "English"}]
    assert admin.patch("/api/v1/settings/gym/", {"name": "   "}, format="json").status_code == 400
    assert admin.patch("/api/v1/settings/gym/", {"phone": "call me"}, format="json").status_code == 400
    r = admin.patch("/api/v1/settings/gym/", {"name": "Train  With Vimal", "address": "Bandra"}, format="json").json()
    assert r["name"] == "Train With Vimal" and r["profile_saved_at"]
    saved = r["profile_saved_at"]
    r = admin.patch("/api/v1/settings/gym/", {"default_units": "imperial", "week_start": "sun"}, format="json").json()
    assert r["default_units"] == "imperial" and r["profile_saved_at"] == saved


def test_new_client_starts_with_gym_defaults(db):
    g = GymSettings.load()
    g.default_units, g.week_start, g.theme = "imperial", "sun", "dark"
    g.save()
    u = User.objects.create_user(email="new@example.com", password="Demo@1234", role=Role.CLIENT, full_name="New")
    assert (u.unit_weight, u.unit_length, u.unit_water, u.week_start, u.theme) == ("lb", "in", "oz", "sun", "dark")
    t = User.objects.create_user(email="coach@example.com", password="Demo@1234", role=Role.TRAINER, full_name="Coach")
    assert t.unit_weight == "kg"  # staff keep their own


def test_branding_draft_apply_and_reset(admin):
    url = "/api/v1/settings/branding/"
    assert admin.patch(url, {"accent_color": "red"}, format="json").status_code == 400
    r = admin.patch(url, {"accent_color": "#0d9488", "theme": "dark"}, format="json").json()
    assert r["applied"] is False and r["branding_draft"] == {"accent_color": "#0D9488", "theme": "dark"}
    r = admin.patch(url, {"accent_color": "#2563EB", "theme": "light"}, format="json").json()
    assert r["applied"] is True  # back to the live values: nothing to apply
    admin.patch(url, {"accent_color": "#0D9488"}, format="json")
    r = admin.post(url + "apply/").json()
    assert r["applied"] and r["accent_color"] == "#0D9488"
    assert admin.get("/api/v1/gym/").json()["accent_color"] == "#0D9488"
    r = admin.post(url + "reset/").json()
    assert r["accent_color"] == "#2563EB" and r["theme"] == "light" and r["applied"]


def _png(size):
    buf = io.BytesIO()
    Image.new("RGB", (size, size), "#2563EB").save(buf, "PNG")
    buf.seek(0)
    buf.name = "logo-trainwithvimal.png"
    return buf


def test_logo_upload_checks_size_and_remove(admin, settings, tmp_path):
    settings.MEDIA_ROOT = tmp_path
    url = "/api/v1/settings/branding/logo/"
    r = admin.post(url, {"logo": _png(200)}, format="multipart")
    assert r.status_code == 400 and "200 x 200" in r.json()["error"]["fields"]["logo"][0]
    r = admin.post(url, {"logo": _png(512)}, format="multipart")
    assert r.status_code == 201, r.content
    assert r.json()["logo_px"] == "512 x 512" and r.json()["logo_name"].startswith("logo-trainwithvimal")
    bad = io.BytesIO(b'<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"></svg>')
    bad.name = "x.svg"
    assert admin.post(url, {"logo": bad}, format="multipart").status_code == 400
    assert admin.delete(url).status_code == 204
    assert admin.get("/api/v1/settings/branding/").json()["logo"] is None


def test_roles_keep_locked_cells_and_count_people(admin):
    url = "/api/v1/settings/roles/"
    r = admin.get(url).json()
    assert r["counts"]["trainer"] >= 1 and r["counts"]["client"] >= 1
    assert "add_trainers" in r["locked"]["trainer"] and "checkins" in r["locked"]["client"]
    body = {"trainer": {**r["trainer"], "add_trainers": True, "manage_content": False},
            "client": {**r["client"], "view_all_clients": True}}
    r = admin.put(url, body, format="json").json()
    assert r["trainer"]["manage_content"] is False
    assert r["trainer"]["add_trainers"] is False and r["client"]["view_all_clients"] is False


def test_roles_page_is_admin_only(trainer):
    assert trainer.get("/api/v1/settings/roles/").status_code == 403


def test_integrations_cards_and_whatsapp_disconnect(admin, monkeypatch):
    rows = admin.get("/api/v1/settings/integrations/").json()
    assert [r["kind"] for r in rows] == ["whatsapp", "email_domain", "health"]
    wa = rows[0]
    assert wa["status"] == "connected" and wa["used"][2] == {"label": "Invite links", "path": "/approvals"}
    assert rows[1]["meta"] == "Sending from the platform address for now"
    assert rows[2]["meta"] == "Not set up"
    url = "/api/v1/settings/integrations/whatsapp/"
    assert admin.post(url + "save/", {"config": {"number": "abc"}}, format="json").status_code == 400
    r = admin.post(url + "save/", {"config": {"number": "+91 90000  11111"}}, format="json").json()
    assert r["meta"] == "+91 90000 11111" and NotificationSettings.load().whatsapp_number == "+91 90000 11111"
    assert admin.post(url + "disconnect/").json()["status"] == "not_connected"
    assert Integration.is_on("whatsapp") is False
    assert admin.post(url + "undo/", {"status": "connected"}, format="json").json()["status"] == "connected"


def test_health_connect_saves_types(admin):
    url = "/api/v1/settings/integrations/health/"
    assert admin.post(url + "connect/", {"config": {"types": {"steps": False}}}, format="json").status_code == 400
    r = admin.post(url + "connect/", {"config": {"types": {"steps": True, "sleep": False, "hr": True,
                                                            "workouts": False}}}, format="json").json()
    assert r["status"] == "connected" and r["config"]["types"]["hr"] is True and r["meta"] == "No clients linked yet"


@pytest.mark.parametrize("found,status", [({"SPF", "DKIM"}, "pending"), ({"SPF", "DKIM", "DMARC"}, "connected")])
def test_email_domain_dns_check(admin, monkeypatch, found, status):
    answers = {"gymdomain.in": "v=spf1 include:_spf.example.com ~all", "twv._domainkey.gymdomain.in": "v=DKIM1; p=abc",
               "_dmarc.gymdomain.in": "v=DMARC1; p=none"}
    labels = {"gymdomain.in": "SPF", "twv._domainkey.gymdomain.in": "DKIM", "_dmarc.gymdomain.in": "DMARC"}
    monkeypatch.setattr(integrations, "_txt", lambda name: [answers[name]] if labels[name] in found else [])
    url = "/api/v1/settings/integrations/email_domain/"
    r = admin.post(url + "save/", {"config": {"domain": "https://www.GymDomain.in/"}}, format="json").json()
    assert r["config"]["domain"] == "gymdomain.in" and r["status"] == status
    assert [x["ok"] for x in r["config"]["records"]] == [True, True, status == "connected"]
    assert Integration.from_email() == ("hello@gymdomain.in" if status == "connected" else None)


def test_verified_domain_is_the_from_address(db, monkeypatch, mailoutbox):
    Integration.objects.filter(kind="email_domain").update(status="connected", config={"domain": "gymdomain.in"})
    providers.send_email("a@example.com", "Hi", "Body", sender_name="Train With Vimal")
    assert mailoutbox[-1].from_email == "Train With Vimal <hello@gymdomain.in>"
