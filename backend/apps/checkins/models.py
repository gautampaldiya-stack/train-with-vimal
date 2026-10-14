import uuid

from django.conf import settings
from django.contrib.postgres.fields import ArrayField
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.utils import timezone

from apps.common.models import SoftDeleteModel, TimeStampedModel


class FormType(models.TextChoices):
    ONBOARDING = "onboarding", "Onboarding questionnaire"
    WEEKLY = "weekly", "Weekly check-in"
    DAILY = "daily", "Daily check-in"
    SURVEY = "survey", "Survey / feedback"
    WAIVER = "waiver", "Waiver / consent"


class Form(SoftDeleteModel):
    class Status(models.TextChoices):
        DRAFT = "draft", "Draft"
        PUBLISHED = "published", "Published"
        ARCHIVED = "archived", "Archived"

    name = models.CharField(max_length=120)
    type = models.CharField(max_length=12, choices=FormType.choices, db_index=True)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.DRAFT, db_index=True)
    is_parq = models.BooleanField(default=False)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")

    class Meta:
        ordering = ["-updated_at"]

    def __str__(self):
        return self.name


class QuestionType(models.TextChoices):
    SHORT = "short", "Short answer"
    LONG = "long", "Long answer"
    NUMBER = "number", "Number"
    SINGLE = "single", "Single choice"
    MULTIPLE = "multiple", "Multiple choice"
    DROPDOWN = "dropdown", "Dropdown"
    SCALE = "scale", "Scale 1–5"
    YES_NO = "yes_no", "Yes / No"
    PHOTO = "photo", "Photo upload"


CHOICE_TYPES = {QuestionType.SINGLE, QuestionType.MULTIPLE, QuestionType.DROPDOWN}


class Question(models.Model):
    form = models.ForeignKey(Form, on_delete=models.CASCADE, related_name="questions")
    order = models.PositiveSmallIntegerField(default=0)
    text = models.CharField(max_length=300)
    type = models.CharField(max_length=10, choices=QuestionType.choices)
    options = ArrayField(models.CharField(max_length=120), default=list, blank=True)
    scale_labels = ArrayField(models.CharField(max_length=30), default=list, blank=True)  # "Very low" … "Great"
    allow_other = models.BooleanField(default=False)
    help_text = models.CharField(max_length=200, blank=True, default="")
    required = models.BooleanField(default=False)
    # Maps an answer to a tracked metric: weight, sleep_hours, energy, mood, hunger, soreness, waist…
    metric = models.CharField(max_length=20, blank=True, default="")
    # Deleted from the builder but already answered: hidden from the form, old answers stay readable.
    is_removed = models.BooleanField(default=False)

    class Meta:
        ordering = ["order"]


class FormRequest(TimeStampedModel):
    """A form sent to a client (by hand, or by an automation). Client profile → Forms tab."""

    form = models.ForeignKey(Form, on_delete=models.CASCADE, related_name="requests")
    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="form_requests")
    sent_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                                related_name="+")
    automation_run = models.ForeignKey("automations.AutomationRun", null=True, blank=True,
                                       on_delete=models.SET_NULL, related_name="+")
    due_at = models.DateTimeField(null=True, blank=True)
    filled_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=["client", "filled_at"])]


class Submission(TimeStampedModel):
    """A filled form. Weekly and daily check-ins are submissions too."""

    form = models.ForeignKey(Form, on_delete=models.PROTECT, related_name="submissions")
    form_type = models.CharField(max_length=12, choices=FormType.choices, db_index=True)
    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="submissions")
    request = models.ForeignKey(FormRequest, null=True, blank=True, on_delete=models.SET_NULL,
                                related_name="submissions")
    date = models.DateField(default=timezone.localdate)
    week_number = models.PositiveSmallIntegerField(null=True, blank=True)
    metrics = models.JSONField(default=dict, blank=True)  # {"weight": 71.6, "energy": 3, ...}
    reviewed_at = models.DateTimeField(null=True, blank=True, db_index=True)
    reviewed_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                                    related_name="+")
    reply = models.TextField(blank=True, default="", max_length=2000)
    edited_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["client", "form_type", "-date"]),
            models.Index(fields=["form_type", "reviewed_at"]),
        ]


def answer_photo_path(instance, filename):
    ext = filename.rsplit(".", 1)[-1].lower()
    return f"answers/{instance.submission.client_id}/{uuid.uuid4().hex}.{ext}"


class Answer(models.Model):
    submission = models.ForeignKey(Submission, on_delete=models.CASCADE, related_name="answers")
    question = models.ForeignKey(Question, on_delete=models.PROTECT, related_name="+")
    value = models.JSONField(null=True, blank=True)  # str | number | list | bool
    photo = models.ImageField(upload_to=answer_photo_path, null=True, blank=True)


class WeightLog(models.Model):
    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="weights")
    date = models.DateField()
    weight_kg = models.DecimalField(max_digits=5, decimal_places=1,
                                    validators=[MinValueValidator(20), MaxValueValidator(400)])
    source = models.CharField(max_length=12, default="manual")  # manual | checkin
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-date"]
        constraints = [models.UniqueConstraint(fields=["client", "date"], name="uniq_weight_day")]


class Measurement(models.Model):
    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="measurements")
    date = models.DateField()
    waist_cm = models.DecimalField(max_digits=5, decimal_places=1, null=True, blank=True)
    hips_cm = models.DecimalField(max_digits=5, decimal_places=1, null=True, blank=True)
    chest_cm = models.DecimalField(max_digits=5, decimal_places=1, null=True, blank=True)
    arm_cm = models.DecimalField(max_digits=5, decimal_places=1, null=True, blank=True)
    body_fat_pct = models.DecimalField(max_digits=4, decimal_places=1, null=True, blank=True,
                                       validators=[MaxValueValidator(70)])
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-date"]
        constraints = [models.UniqueConstraint(fields=["client", "date"], name="uniq_measure_day")]


class PhotoSet(TimeStampedModel):
    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="photo_sets")
    label = models.CharField(max_length=60)  # "Start photos", "Week 2 check-in"
    date = models.DateField(default=timezone.localdate)
    weight_kg = models.DecimalField(max_digits=5, decimal_places=1, null=True, blank=True)
    submission = models.ForeignKey(Submission, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")

    class Meta:
        ordering = ["-date"]


def progress_photo_path(instance, filename):
    ext = filename.rsplit(".", 1)[-1].lower()
    return f"progress/{instance.photo_set.client_id}/{uuid.uuid4().hex}.{ext}"


class ProgressPhoto(models.Model):
    class Pose(models.TextChoices):
        FRONT = "front", "Front"
        SIDE = "side", "Side"
        BACK = "back", "Back"

    photo_set = models.ForeignKey(PhotoSet, on_delete=models.CASCADE, related_name="photos")
    pose = models.CharField(max_length=5, choices=Pose.choices)
    image = models.ImageField(upload_to=progress_photo_path)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["photo_set", "pose"], name="uniq_pose_per_set")]
