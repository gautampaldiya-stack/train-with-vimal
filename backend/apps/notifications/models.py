from django.conf import settings
from django.db import models

from apps.common.models import TimeStampedModel


class Channel(models.TextChoices):
    EMAIL = "email", "Email"
    PUSH = "push", "Push"
    WHATSAPP = "whatsapp", "WhatsApp"
    IN_APP = "in_app", "In-app"


ALL_CHANNELS = [c.value for c in Channel]


class DeviceToken(TimeStampedModel):
    """FCM registration token of one phone or browser (web push goes through FCM too)."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="device_tokens")
    token = models.CharField(max_length=512, unique=True)
    platform = models.CharField(max_length=10, choices=[("android", "Android"), ("ios", "iOS"), ("web", "Web")])
    session = models.ForeignKey(
        "accounts.UserSession", null=True, blank=True, on_delete=models.CASCADE, related_name="device_tokens"
    )
    last_used_at = models.DateTimeField(auto_now=True)


class Notification(TimeStampedModel):
    """In-app notification (bell panel, client Notifications tab). Also the anchor for
    push / email / WhatsApp deliveries of the same event."""

    recipient = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="notifications"
    )
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )
    event = models.CharField(max_length=40, db_index=True)  # checkin_reviewed, session_booked, ...
    title = models.CharField(max_length=140)
    body = models.TextField(blank=True, default="")
    data = models.JSONField(default=dict, blank=True)  # deep-link info: {"route": "/checkins/..", "id": ".."}
    read_at = models.DateTimeField(null=True, blank=True)
    in_app = models.BooleanField(default=True)  # false = push/email only, not listed in the bell

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["recipient", "-created_at"]),
            models.Index(fields=["recipient", "read_at"]),
        ]


class Delivery(TimeStampedModel):
    """One send on one channel. Feeds "96% delivered · 61% opened" and lets failures retry."""

    class Status(models.TextChoices):
        QUEUED = "queued"
        SENT = "sent"
        DELIVERED = "delivered"
        OPENED = "opened"
        FAILED = "failed"
        SKIPPED = "skipped"  # channel off, no address, or no device

    notification = models.ForeignKey(
        Notification, null=True, blank=True, on_delete=models.CASCADE, related_name="deliveries"
    )
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+")
    channel = models.CharField(max_length=10, choices=Channel.choices)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.QUEUED, db_index=True)
    template_key = models.CharField(max_length=60, blank=True, default="")
    automation_run = models.ForeignKey(
        "automations.AutomationRun", null=True, blank=True, on_delete=models.SET_NULL, related_name="deliveries"
    )
    subject = models.CharField(max_length=200, blank=True, default="")
    body = models.TextField(blank=True, default="")
    provider_id = models.CharField(max_length=200, blank=True, default="")
    error = models.TextField(blank=True, default="")
    attempts = models.PositiveSmallIntegerField(default=0)
    scheduled_for = models.DateTimeField(null=True, blank=True)
    sent_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [
            models.Index(fields=["channel", "status", "-created_at"]),
            models.Index(fields=["user", "-created_at"]),
        ]


class TemplateGroup(models.TextChoices):
    ACCESS = "access", "Access"
    COACHING = "coaching", "Coaching"
    PACKAGES = "packages", "Packages"


class MessageTemplate(TimeStampedModel):
    """Emails & alerts → Client messages. One row per message, text per channel:
    channels = {"email": {"on": true, "subject": "...", "body": "..."},
                "push": {"on": false, "title": "", "body": ""},
                "whatsapp": {"on": true, "body": "..."}, "in_app": {...}}"""

    key = models.SlugField(max_length=60, unique=True)
    name = models.CharField(max_length=80)
    group = models.CharField(max_length=10, choices=TemplateGroup.choices, default=TemplateGroup.COACHING)
    is_custom = models.BooleanField(default=False)
    channels = models.JSONField(default=dict)
    default_channels = models.JSONField(default=dict, blank=True)  # for "Reset to default"

    class Meta:
        ordering = ["group", "name"]

    def __str__(self):
        return self.name


class TeamAlertSetting(TimeStampedModel):
    """Emails & alerts → Team alerts. channels = {"email": true, "push": true, ...}."""

    class Event(models.TextChoices):
        NEW_CLIENT = "new_client", "New client"
        CHECKIN_SUBMITTED = "checkin_submitted", "Check-in submitted"
        PLAN_UPDATED = "plan_updated", "Plan updated"
        MISSED_WORKOUT = "missed_workout", "Missed workout"

    event = models.CharField(max_length=30, choices=Event.choices, unique=True)
    channels = models.JSONField(default=dict)


class NotificationSettings(models.Model):
    """Singleton: quiet hours + sender identity (Emails & alerts → Sender)."""

    quiet_hours_on = models.BooleanField(default=True)
    quiet_start = models.TimeField(default="22:00")
    quiet_end = models.TimeField(default="07:00")
    sender_name = models.CharField(max_length=80, default="Train With Vimal")
    reply_to_email = models.EmailField(blank=True, default="hello@trainwithvimal.com")
    whatsapp_number = models.CharField(max_length=20, blank=True, default="")
    updated_at = models.DateTimeField(auto_now=True)

    @classmethod
    def load(cls):
        obj, _ = cls.objects.get_or_create(pk=1)
        return obj


class ReminderPreference(models.Model):
    """Client More → Reminders (saved as they change)."""

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="reminder_prefs")
    workout = models.BooleanField(default=True)  # 1 hour before the session or planned workout
    meal = models.BooleanField(default=True)  # at each meal time
    water = models.BooleanField(default=True)  # every 2 hours when behind
    supps = models.BooleanField(default=True)  # supplements at their time of day
    habit = models.BooleanField(default=False)  # steps and sleep nudges in the evening
    checkin = models.BooleanField(default=True)
    trainer_reply = models.BooleanField(default=True)  # "Coach updates": replies and plan changes (push)
    progress = models.BooleanField(default=True)  # personal bests, streaks, milestones (push)
    quiet_on = models.BooleanField(default=True)  # the person's own quiet hours: pushes wait until they end
    quiet_from = models.TimeField(default="22:00")
    quiet_to = models.TimeField(default="07:00")
    workout_time = models.TimeField(default="07:00")  # used when a workout has no session time
    updated_at = models.DateTimeField(auto_now=True)

    # Board ClientMore "Reset to recommended": everything on but habit nudges, quiet 10 pm – 7 am.
    RECOMMENDED = dict(workout=True, meal=True, water=True, supps=True, habit=False, checkin=True, trainer_reply=True,
                       progress=True, quiet_on=True, quiet_from="22:00", quiet_to="07:00")


class StaffNotificationPreference(models.Model):
    """Trainer Me → Account → Notifications."""

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="staff_notification_prefs"
    )
    new_checkin = models.BooleanField(default=True)
    missed_workouts = models.BooleanField(default=True)
    new_client = models.BooleanField(default=True)
    session_changes = models.BooleanField(default=True)
    tasks = models.BooleanField(default=True)
    push = models.BooleanField(default=True)
    email = models.BooleanField(default=True)


class ReminderLog(models.Model):
    """De-duplicates scheduled reminders: one row per (user, kind, ref, day)."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+")
    kind = models.CharField(max_length=20)
    ref = models.CharField(max_length=60)
    day = models.DateField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["user", "kind", "ref", "day"], name="uniq_reminder_once")]


class GymNews(TimeStampedModel):
    """A notice from the admin to the team ("Gym news" in Trainer Me → Account → Notifications).
    Sent once when posted, to every trainer who has Gym news switched on (bell + push)."""

    author = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")
    title = models.CharField(max_length=120)
    body = models.TextField(blank=True, default="")
    sent_to = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["-created_at"]
        verbose_name_plural = "gym news"
