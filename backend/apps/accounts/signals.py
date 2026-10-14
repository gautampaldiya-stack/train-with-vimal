from django.db.models.signals import pre_save
from django.dispatch import receiver

from .models import User


@receiver(pre_save, sender=User)
def normalise_contact(sender, instance, **kwargs):
    instance.clean()
