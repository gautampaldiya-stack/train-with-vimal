from django.db.models.signals import post_save
from django.dispatch import receiver

from apps.accounts.models import User

from .services import ensure_admin_trainer_profile


@receiver(post_save, sender=User)
def admin_gets_trainer_profile(sender, instance, **kwargs):
    ensure_admin_trainer_profile(instance)
