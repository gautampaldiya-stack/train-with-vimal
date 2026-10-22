from django.apps import AppConfig


class GymConfig(AppConfig):
    name = "apps.gym"

    def ready(self):
        from . import signals  # noqa: F401
