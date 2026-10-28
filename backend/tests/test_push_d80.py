"""D-80 (Probid 2026-10-28, "mere notification aane chaiye"): the push send path. A device saved again moves to the
person logged in now, only dead tokens are dropped, one bad device does not stop the others, the FCM project comes
from the key file when .env has none, and `manage.py push_test` shows each device."""
import json
from io import StringIO
from unittest import mock

import pytest
from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.test import override_settings

from apps.notifications import providers, tasks
from apps.notifications.models import Channel, Delivery, DeviceToken
from apps.notifications.services import notify


User = get_user_model()
DEV = "/api/v1/devices/"
TOKEN = "phone-token-" + "x" * 40


def test_same_device_saved_twice_and_then_by_another_user(client_user, trainer):
    DeviceToken.objects.filter(token=TOKEN).delete()
    assert client_user.post(DEV, {"token": TOKEN, "platform": "android"}, format="json").status_code == 204
    # every app start saves it again: this answered 400 "Please check the highlighted fields" before
    assert client_user.post(DEV, {"token": TOKEN, "platform": "android"}, format="json").status_code == 204
    assert DeviceToken.objects.get(token=TOKEN).user.email == "riya@example.com"
    # Riya logs out without the app reaching the server, Aman logs in on the same phone: pushes now go to Aman
    assert trainer.post(DEV, {"token": TOKEN, "platform": "android"}, format="json").status_code == 204
    assert DeviceToken.objects.filter(token=TOKEN).count() == 1
    assert DeviceToken.objects.get(token=TOKEN).user.email == "aman@trainwithvimal.com"
    assert trainer.delete(DEV, {"token": TOKEN}, format="json").status_code == 204
    assert not DeviceToken.objects.filter(token=TOKEN).exists()


def test_short_token_is_refused(client_user):
    r = client_user.post(DEV, {"token": "abc", "platform": "web"}, format="json")
    assert r.status_code == 400
    assert r.json()["error"]["fields"]["token"]


def test_only_unknown_tokens_are_dropped():
    assert providers.token_is_dead(404, '{"error": {"details": [{"errorCode": "UNREGISTERED"}]}}')
    assert providers.token_is_dead(400, "The registration token is not a valid FCM registration token")
    # a bad message used to delete the token too, so every later push to that phone was lost
    assert not providers.token_is_dead(400, '{"error": {"status": "INVALID_ARGUMENT", "message": "Invalid JSON"}}')
    assert not providers.token_is_dead(500, "INTERNAL")


@override_settings(PUSH_PROVIDER="fcm", FCM_PROJECT_ID="", FRONTEND_URL="https://twv.example.com")
def test_fcm_message_uses_key_file_project_and_opens_the_page(tmp_path):
    key = tmp_path / "sa.json"
    key.write_text(json.dumps({"project_id": "train-with-vimal-8a8fd"}))
    resp = mock.Mock(status_code=200)
    resp.json.return_value = {"name": "projects/train-with-vimal-8a8fd/messages/1"}
    with override_settings(FCM_SERVICE_ACCOUNT_FILE=str(key)), \
            mock.patch.object(providers, "_fcm_access_token", return_value="tok"), \
            mock.patch.object(providers.httpx, "post", return_value=resp) as post:
        pid = providers.send_push("abc", "Hi", "There", {"route": "/habits", "n": 1}, "web")
    assert pid.endswith("/messages/1")
    assert post.call_args.args[0] == \
        "https://fcm.googleapis.com/v1/projects/train-with-vimal-8a8fd/messages:send"
    msg = post.call_args.kwargs["json"]["message"]
    assert msg["webpush"]["fcm_options"]["link"] == "https://twv.example.com/habits"
    assert "notification" not in msg["android"]  # no "default" channel the app never made
    assert msg["data"] == {"route": "/habits", "n": "1"}


@override_settings(PUSH_PROVIDER="fcm", FCM_PROJECT_ID="", FCM_SERVICE_ACCOUNT_FILE="/nope.json")
def test_no_project_is_a_clear_error():
    with pytest.raises(providers.ProviderError, match="FCM project unknown"):
        providers.send_push("abc", "Hi", "There")


def _delivery(user):
    n = notify(user, "reminder", "Drink water", "2 glasses left", channels=[Channel.IN_APP])[0]
    return Delivery.objects.create(notification=n, user=user, channel=Channel.PUSH, subject=n.title, body=n.body)


@pytest.mark.django_db
def test_one_bad_device_does_not_stop_the_others():
    riya = User.objects.get(email="riya@example.com")
    DeviceToken.objects.filter(user=riya).delete()
    for name in ("dead", "flaky", "good"):
        DeviceToken.objects.create(user=riya, token=name + "-" + "t" * 30, platform="android")
    calls = []

    def fake(token, *a, **kw):
        calls.append(token.split("-")[0])
        if token.startswith("dead"):
            raise providers.ProviderError("FCM 404: UNREGISTERED", permanent=True)
        if token.startswith("flaky"):
            raise providers.ProviderError("FCM 503: try later")
        return "ok"

    d = _delivery(riya)
    with mock.patch.object(providers, "send_push", side_effect=fake):
        tasks.send_delivery.apply(args=[str(d.id)])
    assert sorted(calls) == ["dead", "flaky", "good"]
    d.refresh_from_db()
    assert d.status == Delivery.Status.SENT
    assert not DeviceToken.objects.filter(user=riya, token__startswith="dead").exists()
    assert DeviceToken.objects.filter(user=riya, token__startswith="flaky").exists()


@pytest.mark.django_db
def test_push_test_command_reports_each_device():
    riya = User.objects.get(email="riya@example.com")
    DeviceToken.objects.filter(user=riya).delete()
    out = StringIO()
    call_command("push_test", "riya@example.com", stdout=out)
    assert "No devices saved" in out.getvalue()
    DeviceToken.objects.create(user=riya, token="t" * 40, platform="android")
    out = StringIO()
    call_command("push_test", "riya@example.com", stdout=out)
    assert "android: sent" in out.getvalue()




@override_settings(PUSH_PROVIDER="fcm", FCM_PROJECT_ID="train-with-vimal-8a8fd")
def test_google_services_json_as_server_key_says_so(tmp_path):
    from django.core.cache import cache

    cache.delete("fcm-access-token")
    key = tmp_path / "sa.json"
    key.write_text(json.dumps({"project_info": {"project_id": "train-with-vimal-8a8fd"}, "client": []}))
    with override_settings(FCM_SERVICE_ACCOUNT_FILE=str(key)), \
            pytest.raises(providers.ProviderError, match="Generate new private key"):
        providers.send_push("abc", "Hi", "There")
