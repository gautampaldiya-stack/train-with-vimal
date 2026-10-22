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
        # One client's own copy (Client profile → Forms: "Edit … for Riya" / "Duplicate and edit"). Never in the
        # forms library and never sent to anyone else; `master` is the library form it came from.
        CLIENT = "client", "Client copy"

    name = models.CharField(max_length=120)
    type = models.CharField(max_length=12, choices=FormType.choices, db_index=True)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.DRAFT, db_index=True)
    is_parq = models.BooleanField(default=False)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")
    client = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.CASCADE,
                               related_name="own_forms")
    master = models.ForeignKey("self", null=True, blank=True, on_delete=models.SET_NULL, related_name="copies")
    # A client's weekly check-in copy with this off = "Stop sending" (her app shows no weekly check-in).
    sending = models.BooleanField(default=True)
    # Builder changes to a published form wait here until Publish (D-50): clients keep getting the live questions.
    # A list of question dicts (QuestionSerializer shape, `id` kept for questions that already exist); None = no draft.
    draft_questions = models.JSONField(null=True, blank=True)

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
    # Onboarding questionnaire: the client profile field this question fills (apps.clients.onboarding.FIELDS keys,
    # e.g. "surgeries"). Blank = an extra question; its answer is kept with the onboarding answers.
    profile_key = models.CharField(max_length=40, blank=True, default="")
    # Deleted from the builder but already answered: hidden from the form, old answers stay readable.
    is_removed = models.BooleanField(default=False)
    # On a client's copy: the master question it was copied from ("Added for Riya" / "Was: required").
    copied_from = models.ForeignKey("self", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")

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
    # "Remind her if she does not answer": one reminder 24 h after sending; "Remind again" by hand.
    auto_remind = models.BooleanField(default=False)
    reminded_at = models.DateTimeField(null=True, blank=True)
    schedule = models.ForeignKey("FormSchedule", null=True, blank=True, on_delete=models.SET_NULL,
                                 related_name="requests")

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
    private = models.BooleanField(default=False)  # sent while "Share progress photos with Aman" was off


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


# Body measurements a coach can ask for (key, label, unit). Weight is not here: it has its own weigh-ins.
MEASURES = [
    ("neck", "Neck", "cm"), ("chest", "Chest", "cm"), ("abdomen", "Abdomen (navel)", "cm"), ("waist", "Waist", "cm"),
    ("hips", "Hips", "cm"), ("bicep_l", "Left bicep", "cm"), ("bicep_r", "Right bicep", "cm"),
    ("thigh_l", "Left thigh", "cm"), ("thigh_r", "Right thigh", "cm"), ("calf_l", "Left calf", "cm"),
    ("calf_r", "Right calf", "cm"), ("body_fat", "Body fat", "%"),
]
MEASURE_KEYS = [k for k, _, _ in MEASURES]
# What a client tracks until the coach picks (ClientProfile.measure_keys).
DEFAULT_MEASURES = ["waist", "hips", "chest", "bicep_l", "bicep_r", "body_fat"]


class Measurement(models.Model):
    """One day's body measurements: {key: number} for the keys in MEASURES (cm, body fat in %)."""

    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="measurements")
    date = models.DateField()
    values = models.JSONField(default=dict, blank=True)
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
    private = models.BooleanField(default=False)  # added while "Share progress photos with Aman" was off
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["photo_set", "pose"], name="uniq_pose_per_set")]


class FormSchedule(TimeStampedModel):
    """Send a form to one client later or again and again (Client profile → Send a form → When). The beat task
    `send_scheduled_forms` sends each one when `next_at` comes."""

    class Repeat(models.TextChoices):
        ONCE = "once", "Once"
        WEEK = "week", "Every week"
        MONTH = "month", "Every month"

    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="form_schedules")
    form = models.ForeignKey(Form, on_delete=models.CASCADE, related_name="schedules")
    repeat = models.CharField(max_length=6, choices=Repeat.choices, default=Repeat.ONCE)
    weekday = models.PositiveSmallIntegerField(default=6)  # 0 = Monday … 6 = Sunday
    month_day = models.PositiveSmallIntegerField(default=1)
    time = models.TimeField(default="18:00")
    until = models.DateField(null=True, blank=True)
    channels = models.JSONField(default=list, blank=True)
    answer_days = models.PositiveSmallIntegerField(default=2)
    auto_remind = models.BooleanField(default=True)
    next_at = models.DateTimeField(null=True, blank=True, db_index=True)
    active = models.BooleanField(default=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")
