from django.conf import settings
from django.core.validators import MaxValueValidator
from django.db import models

from apps.common.models import TimeStampedModel


class Availability(models.Model):
    """Working hours per trainer per weekday (Availability / My working hours drawer)."""

    trainer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="availability")
    weekday = models.PositiveSmallIntegerField(validators=[MaxValueValidator(6)])
    is_working = models.BooleanField(default=True)
    start = models.TimeField(default="06:30")
    end = models.TimeField(default="20:00")

    class Meta:
        ordering = ["weekday"]
        constraints = [models.UniqueConstraint(fields=["trainer", "weekday"], name="uniq_trainer_weekday")]


class Session(TimeStampedModel):
    class Kind(models.TextChoices):
        ONE_ON_ONE = "one_on_one", "1:1 session"
        QUICK_CALL = "quick_call", "Quick call"
        PROGRAM_REVIEW = "program_review", "Program review"

    DEFAULT_MINUTES = {"one_on_one": 60, "quick_call": 15, "program_review": 30}

    class Status(models.TextChoices):
        BOOKED = "booked", "Booked"
        DONE = "done", "Done"
        MISSED = "missed", "Missed"
        CANCELLED = "cancelled", "Cancelled"

    kind = models.CharField(max_length=16, choices=Kind.choices, default=Kind.ONE_ON_ONE)
    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="client_sessions")
    trainer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="trainer_sessions")
    title = models.CharField(max_length=80, blank=True, default="")  # "Push A"
    start = models.DateTimeField(db_index=True)
    end = models.DateTimeField()
    is_call = models.BooleanField(default=False)
    place = models.CharField(max_length=120, blank=True, default="")
    call_link = models.CharField(max_length=200, blank=True, default="")  # meet link or a phone number
    note = models.CharField(max_length=300, blank=True, default="")
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.BOOKED, db_index=True)
    booked_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")
    reminder_sent_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["start"]
        indexes = [
            models.Index(fields=["trainer", "start"]),
            models.Index(fields=["client", "start"]),
        ]
        constraints = [models.CheckConstraint(condition=models.Q(end__gt=models.F("start")), name="session_end_after_start")]
