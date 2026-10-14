from django.conf import settings
from django.db import models

from apps.common.models import TimeStampedModel


class Kind(models.TextChoices):
    CHECKIN = "checkin", "Check-in"
    PLAN = "plan", "Plan"
    WORKOUT = "workout", "Workout"
    MEAL = "meal", "Meal"
    BODY = "body", "Body"
    CLIENT = "client", "Client"
    CONTENT = "content", "Content"
    SESSION = "session", "Session"
    TEAM = "team", "Team"
    SYSTEM = "system", "System"


class ActorType(models.TextChoices):
    TEAM = "team", "Team"
    CLIENT = "client", "Client"
    AUTOMATION = "automation", "Automation"
    SYSTEM = "system", "System"


class ActivityEvent(TimeStampedModel):
    """One timeline for the whole product: Activity log, trainer profile Activity tab,
    client profile History/Activity tabs and the dashboard "Recent activity" card.

    Append-only and very large over time, so every list reads through an index and
    is paged by cursor.
    """

    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )
    actor_type = models.CharField(max_length=12, choices=ActorType.choices, default=ActorType.TEAM)
    actor_label = models.CharField(max_length=120, blank=True, default="")  # "Vimal", "Client onboarding"
    source = models.CharField(max_length=60, blank=True, default="")  # "Admin · Web", "Client · Android app"
    kind = models.CharField(max_length=10, choices=Kind.choices, db_index=True)
    verb = models.CharField(max_length=200)  # "changed rest on Bench press"
    target_type = models.CharField(max_length=40, blank=True, default="")
    target_id = models.CharField(max_length=40, blank=True, default="")
    target_label = models.CharField(max_length=200, blank=True, default="")
    change_from = models.CharField(max_length=120, blank=True, default="")
    change_to = models.CharField(max_length=120, blank=True, default="")
    client = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.CASCADE, related_name="+"
    )
    trainer = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )
    meta = models.JSONField(default=dict, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["kind", "-created_at"]),
            models.Index(fields=["client", "-created_at"]),
            models.Index(fields=["trainer", "-created_at"]),
            models.Index(fields=["actor", "-created_at"]),
            models.Index(fields=["actor_type", "-created_at"]),
        ]

    def __str__(self):
        return f"{self.actor_label} {self.verb}"


class DismissedItem(models.Model):
    """Dashboard 'Needs action' rows a person closed with ×. Key is stable per row (e.g. 'approvals:5')."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+")
    key = models.CharField(max_length=120)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["user", "key"], name="uniq_dismissed_item")]
