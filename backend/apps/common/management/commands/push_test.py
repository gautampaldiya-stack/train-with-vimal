"""Send one test push to a person's phones / browsers right now and print what FCM said (D-80).

    docker compose exec api python manage.py push_test riya@example.com

Shows: the push provider, how many devices the person has (one row per signed-in phone / browser that allowed
notifications), and the result for each. No device = the app never saved a token (see deploy/README.md → Push).
"""
from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError

from apps.notifications import providers
from apps.notifications.models import DeviceToken


class Command(BaseCommand):
    help = "Send a test push to everyone signed in with this email and print FCM's answer."

    def add_arguments(self, parser):
        parser.add_argument("email")
        parser.add_argument("--route", default="/", help="Page the tap opens, e.g. /habits")

    def handle(self, email, route, **_):
        user = get_user_model().objects.filter(email__iexact=email).first()
        if user is None:
            raise CommandError(f"No account with {email}")
        self.stdout.write(f"Provider: {settings.PUSH_PROVIDER} · project: {providers.fcm_project_id() or '-'} "
                          "(must be FB_PROJECT_ID of the app's firebase.json)")
        tokens = list(DeviceToken.objects.filter(user=user))
        if not tokens:
            self.stdout.write(self.style.WARNING(
                "No devices saved. The app saves one after sign in when push is set up in the build "
                "(firebase.json) and the person allows notifications."))
            return
        for t in tokens:
            try:
                pid = providers.send_push(t.token, "Test notification", "Push works on this device.",
                                          {"route": route}, t.platform)
                self.stdout.write(self.style.SUCCESS(f"{t.platform}: sent ({pid})"))
            except providers.ProviderError as exc:
                self.stdout.write(self.style.ERROR(f"{t.platform}: {exc}"))
                if exc.permanent:
                    t.delete()
                    self.stdout.write("  token removed (FCM no longer knows it); open the app again to save a new one")
