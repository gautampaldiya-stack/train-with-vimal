from django.apps import AppConfig


class TrainersConfig(AppConfig):
    name = "apps.trainers"

    def ready(self):
        from . import signals  # noqa: F401  (connects admin profile signal)
