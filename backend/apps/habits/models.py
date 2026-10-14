from django.conf import settings
from django.contrib.postgres.fields import ArrayField
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.utils import timezone

from apps.common.models import SoftDeleteModel, TimeStampedModel


class Habit(SoftDeleteModel):
    class Kind(models.TextChoices):
        TICK = "tick", "Tick"
        COUNTER = "counter", "Counter"

    class Frequency(models.TextChoices):
        DAILY = "daily", "Daily"
        DAYS = "days", "Specific days"
        TIMES_WEEK = "times_week", "Times a week"

    ICONS = ["water", "steps", "sleep", "food", "timer", "sun", "habit"]

    name = models.CharField(max_length=80)
    kind = models.CharField(max_length=8, choices=Kind.choices, default=Kind.TICK)
    target = models.PositiveIntegerField(null=True, blank=True)  # counter target, e.g. 8000
    unit = models.CharField(max_length=20, blank=True, default="")  # glasses, steps, min
    frequency = models.CharField(max_length=10, choices=Frequency.choices, default=Frequency.DAILY)
    days = ArrayField(models.PositiveSmallIntegerField(validators=[MaxValueValidator(6)]), default=list, blank=True)
    times_per_week = models.PositiveSmallIntegerField(null=True, blank=True, validators=[MinValueValidator(1),
                                                                                         MaxValueValidator(7)])
    icon = models.CharField(max_length=10, default="habit")
    why = models.CharField(max_length=200, blank=True, default="")  # shown to the client
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")

    class Meta:
        ordering = ["name"]

    def is_due_on(self, day):
        if self.frequency == self.Frequency.DAYS:
            return day.weekday() in (self.days or [])
        return True


class HabitAssignment(TimeStampedModel):
    habit = models.ForeignKey(Habit, on_delete=models.CASCADE, related_name="assignments")
    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="habit_assignments")
    start_date = models.DateField(default=timezone.localdate)
    active = models.BooleanField(default=True, db_index=True)
    assigned_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")

    class Meta:
        constraints = [models.UniqueConstraint(fields=["habit", "client"], name="uniq_habit_client")]


class HabitLog(models.Model):
    habit = models.ForeignKey(Habit, on_delete=models.CASCADE, related_name="logs")
    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="habit_logs")
    date = models.DateField()
    value = models.PositiveIntegerField(default=0)  # steps, glasses, minutes slept
    done = models.BooleanField(default=False)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["habit", "client", "date"], name="uniq_habit_log")]
        indexes = [models.Index(fields=["client", "date"])]


class SupplementPlan(SoftDeleteModel):
    name = models.CharField(max_length=80)
    note = models.CharField(max_length=300, blank=True, default="")
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")

    class Meta:
        ordering = ["name"]


class Timing(models.TextChoices):
    BREAKFAST = "breakfast", "Breakfast"
    MORNING = "morning", "Morning"
    POST_WORKOUT = "post_workout", "Post-workout"
    ANY = "any", "Any time"
    NIGHT = "night", "Night"
    BEFORE_BED = "before_bed", "Before bed"


class SupplementItem(models.Model):
    plan = models.ForeignKey(SupplementPlan, on_delete=models.CASCADE, related_name="items")
    name = models.CharField(max_length=80)
    dose = models.CharField(max_length=60)  # "1 scoop · 30 g"
    how = models.CharField(max_length=120, blank=True, default="")  # "In water, with breakfast"
    timing = models.CharField(max_length=14, choices=Timing.choices, default=Timing.ANY)
    days = ArrayField(models.PositiveSmallIntegerField(), default=list, blank=True)  # empty = every day
    with_food = models.BooleanField(default=False)
    order = models.PositiveSmallIntegerField(default=0)

    class Meta:
        ordering = ["timing", "order"]


class SupplementAssignment(TimeStampedModel):
    plan = models.ForeignKey(SupplementPlan, on_delete=models.CASCADE, related_name="assignments")
    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
                               related_name="supplement_assignments")
    start_date = models.DateField(default=timezone.localdate)
    active = models.BooleanField(default=True, db_index=True)
    assigned_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")

    class Meta:
        constraints = [models.UniqueConstraint(fields=["plan", "client"], name="uniq_supp_client")]


class SupplementLog(models.Model):
    item = models.ForeignKey(SupplementItem, on_delete=models.CASCADE, related_name="logs")
    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="supplement_logs")
    date = models.DateField()
    taken_at = models.DateTimeField(default=timezone.now)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["item", "client", "date"], name="uniq_supp_log")]
        indexes = [models.Index(fields=["client", "date"])]


class SupplementStock(models.Model):
    """"11 scoops left at home" — the client's own count."""

    item = models.ForeignKey(SupplementItem, on_delete=models.CASCADE, related_name="stocks")
    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+")
    quantity = models.PositiveIntegerField(default=0)
    unit = models.CharField(max_length=20, default="scoops")

    class Meta:
        constraints = [models.UniqueConstraint(fields=["item", "client"], name="uniq_supp_stock")]
