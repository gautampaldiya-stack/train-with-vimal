from django.conf import settings
from django.db.models.signals import pre_save
from django.dispatch import receiver


@receiver(pre_save, sender=settings.AUTH_USER_MODEL)
def new_client_defaults(sender, instance, **kwargs):
    """Settings → Regional & defaults and the branding theme: a new client starts with the gym's units, week
    start, timezone and theme. Only fields still on the model default are filled, so a value picked during
    sign-up wins. Clients change their own later in More → Units & preferences."""
    if not instance._state.adding or instance.role != "client":
        return
    from .models import GymSettings

    for field, value in GymSettings.load().client_defaults().items():
        if getattr(instance, field) == instance._meta.get_field(field).default:
            setattr(instance, field, value)
