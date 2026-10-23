from django.conf import settings
from django.db import models

from apps.common.models import SoftDeleteModel, TimeStampedModel


class Trigger(models.TextChoices):
    CLIENT_APPROVED = "client_approved", "New client approved"
    PLAN_STARTS = "plan_starts", "Plan starts"
    PLAN_ENDS = "plan_ends", "Plan ends"
    PACKAGE_ENDING = "package_ending", "Package ending"
    BIRTHDAY = "birthday", "Client birthday"
    EVERY_WEEK = "every_week", "Every week"
    EVERY_DAY = "every_day", "Every day"
    ON_DATE = "on_date", "On a date"
    MISSED_CHECKIN = "missed_checkin", "Missed check-in"
    MISSED_WORKOUTS = "missed_workouts", "Missed workouts"
    NO_ACTIVITY = "no_activity", "No app activity"
    FORM_SENT = "form_sent", "Form sent in"
    WORKOUT_STREAK = "workout_streak", "Workout streak"
    GOAL_WEIGHT = "goal_weight", "Goal weight reached"
    WEIGHT_FLAT = "weight_flat", "Weight not changing"


# Packages are not used for now (Gautam 2026-10-23): the "Package ending" trigger, the Package filter and the
# Renewal reminder starter are hidden and never run. Remove a key here to bring it back.
HIDDEN_TRIGGERS = {"package_ending"}

TRIGGER_GROUPS = {
    "client": ["client_approved", "plan_starts", "plan_ends", "birthday"],  # "package_ending" hidden
    "schedule": ["every_week", "every_day", "on_date"],
    "activity": ["missed_checkin", "missed_workouts", "no_activity", "form_sent", "workout_streak"],
    "progress": ["goal_weight", "weight_flat"],
}

# Event triggers fire from the code that makes the event happen; the rest are polled.
EVENT_TRIGGERS = {"client_approved", "plan_starts", "form_sent", "goal_weight"}


class Automation(SoftDeleteModel):
    class Status(models.TextChoices):
        ON = "on", "On"
        OFF = "off", "Off"
        DRAFT = "draft", "Draft"

    name = models.CharField(max_length=100)
    status = models.CharField(max_length=6, choices=Status.choices, default=Status.DRAFT, db_index=True)
    trigger = models.CharField(max_length=20, choices=Trigger.choices, blank=True, default="", db_index=True)
    trigger_config = models.JSONField(default=dict, blank=True)
    scope_package = models.CharField(max_length=80, blank=True, default="")  # "" = any package
    scope_trainer = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                                      related_name="+")
    stop_on_response = models.BooleanField(default=True)
    starter = models.CharField(max_length=40, blank=True, default="")
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name


class Step(models.Model):
    class Kind(models.TextChoices):
        WAIT = "wait", "Wait"
        MESSAGE = "message", "Send message"
        FORM = "form", "Send form"
        TASK = "task", "Assign task"

    automation = models.ForeignKey(Automation, on_delete=models.CASCADE, related_name="steps")
    order = models.PositiveSmallIntegerField(default=0)
    kind = models.CharField(max_length=8, choices=Kind.choices)
    # wait: {"days": 1, "hours": 0} · message: {"template": key, "channels": [...]}
    # form: {"form": id, "channels": [...]} · task: {"title": "...", "assignee": "trainer|owner", "due_days": 1}
    config = models.JSONField(default=dict)

    class Meta:
        ordering = ["order"]


class AutomationRun(TimeStampedModel):
    """One client going through one automation."""

    class Status(models.TextChoices):
        RUNNING = "running", "Running"
        WAITING = "waiting", "Waiting"
        FINISHED = "finished", "Finished"
        STOPPED = "stopped", "Stopped early"
        FAILED = "failed", "Failed"

    automation = models.ForeignKey(Automation, on_delete=models.CASCADE, related_name="runs")
    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="automation_runs")
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.RUNNING, db_index=True)
    step_index = models.PositiveSmallIntegerField(default=0)
    next_run_at = models.DateTimeField(null=True, blank=True, db_index=True)
    dedupe_key = models.CharField(max_length=80)  # stops the same trigger starting twice
    finished_at = models.DateTimeField(null=True, blank=True)
    last_message = models.CharField(max_length=200, blank=True, default="")  # "Sent the form · stopped at step 1"
    log = models.JSONField(default=list, blank=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [models.UniqueConstraint(fields=["automation", "client", "dedupe_key"], name="uniq_run_once")]
        indexes = [models.Index(fields=["status", "next_run_at"])]


class TrainerTask(TimeStampedModel):
    """Tasks card on the trainer dashboard (from automations or added by hand)."""

    assignee = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="tasks")
    client = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.CASCADE,
                               related_name="+")
    title = models.CharField(max_length=160)
    detail = models.CharField(max_length=200, blank=True, default="")  # "From automation · Inactive for 7 days"
    automation_run = models.ForeignKey(AutomationRun, null=True, blank=True, on_delete=models.SET_NULL,
                                       related_name="tasks")
    due_on = models.DateField(null=True, blank=True)
    done_at = models.DateTimeField(null=True, blank=True, db_index=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                                   related_name="+")

    class Meta:
        ordering = ["done_at", "due_on", "-created_at"]
        indexes = [models.Index(fields=["assignee", "done_at"])]
