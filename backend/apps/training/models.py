from django.conf import settings
from django.contrib.postgres.fields import ArrayField
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.utils import timezone

from apps.common.models import SoftDeleteModel, TimeStampedModel


class Muscle(models.TextChoices):
    CHEST = "chest", "Chest"
    BACK = "back", "Back"
    LEGS = "legs", "Legs"
    SHOULDERS = "shoulders", "Shoulders"
    ARMS = "arms", "Arms"
    CORE = "core", "Core"
    CARDIO = "cardio", "Cardio"


class Equipment(models.TextChoices):
    BARBELL = "barbell", "Barbell"
    DUMBBELL = "dumbbell", "Dumbbell"
    CABLE = "cable", "Cable"
    MACHINE = "machine", "Machine"
    BODYWEIGHT = "bodyweight", "Bodyweight"
    KETTLEBELL = "kettlebell", "Kettlebell"
    BAND = "band", "Band"
    OTHER = "other", "Other"


class Level(models.TextChoices):
    BEGINNER = "beginner", "Beginner"
    INTERMEDIATE = "intermediate", "Intermediate"
    ADVANCED = "advanced", "Advanced"


class LogType(models.TextChoices):
    WEIGHT_REPS = "weight_reps", "kg × reps"
    BODYWEIGHT_REPS = "bodyweight_reps", "Bodyweight reps"
    TIME = "time", "Time"
    DISTANCE = "distance", "Distance and time"


class Exercise(SoftDeleteModel):
    name = models.CharField(max_length=120, db_index=True)
    muscle_group = models.CharField(max_length=10, choices=Muscle.choices, db_index=True)
    primary_muscle = models.CharField(max_length=60, blank=True, default="")  # "Pectorals"
    also_works = models.JSONField(default=list, blank=True)  # [{"muscle": "Triceps", "level": "strong"}]
    equipment = models.CharField(max_length=12, choices=Equipment.choices, db_index=True)
    level = models.CharField(max_length=12, choices=Level.choices, default=Level.BEGINNER, db_index=True)
    is_builtin = models.BooleanField(default=False, db_index=True)
    video = models.ForeignKey("content.ContentItem", null=True, blank=True, on_delete=models.SET_NULL,
                              related_name="exercises")
    youtube_url = models.URLField(blank=True, default="")
    cover_at_seconds = models.PositiveIntegerField(default=0)
    # "Upload image" cover (board ExerciseAdd); when empty the library shows the video's frame / cover.
    cover_image = models.ImageField(upload_to="exercises/covers/", null=True, blank=True)
    # "Frame from the video": key of the chosen still (exercises/frames/<video>-<s>.jpg or yt/<id>/<n>), D-42.
    cover_frame = models.CharField(max_length=80, blank=True, default="")
    how_to = ArrayField(models.CharField(max_length=300), default=list, blank=True)
    form_cues = ArrayField(models.CharField(max_length=300), default=list, blank=True)
    log_type = models.CharField(max_length=16, choices=LogType.choices, default=LogType.WEIGHT_REPS)
    default_sets = models.PositiveSmallIntegerField(default=3, validators=[MinValueValidator(1), MaxValueValidator(12)])
    default_reps = models.CharField(max_length=20, default="8–10")
    default_rest_seconds = models.PositiveSmallIntegerField(default=90, validators=[MaxValueValidator(300)])
    default_rpe = models.PositiveSmallIntegerField(null=True, blank=True, validators=[MaxValueValidator(10)])
    default_tempo = models.CharField(max_length=12, blank=True, default="")
    duplicated_from = models.ForeignKey("self", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                                   related_name="+")

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name


class Program(SoftDeleteModel):
    """Master plan (is_master) or one client's custom copy (master points at the original)."""

    name = models.CharField(max_length=120)
    goal_line = models.CharField(max_length=120, blank=True, default="")  # "Fat loss · gym"
    weeks = models.PositiveSmallIntegerField(default=8, validators=[MinValueValidator(1), MaxValueValidator(52)])
    days_per_week = models.PositiveSmallIntegerField(default=4, validators=[MinValueValidator(1), MaxValueValidator(7)])
    # Who the plan suits: beginner / intermediate / advanced, or "any" (assign drawer filter and row line)
    level = models.CharField(max_length=12, choices=[*Level.choices, ("any", "Any level")], default="any",
                             db_index=True)
    archived_at = models.DateTimeField(null=True, blank=True, db_index=True)
    is_master = models.BooleanField(default=True, db_index=True)
    master = models.ForeignKey("self", null=True, blank=True, on_delete=models.SET_NULL, related_name="copies")
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                                   related_name="+")

    class Meta:
        ordering = ["-updated_at"]

    def __str__(self):
        return self.name


class ProgramWeek(models.Model):
    program = models.ForeignKey(Program, on_delete=models.CASCADE, related_name="program_weeks")
    number = models.PositiveSmallIntegerField()

    class Meta:
        ordering = ["number"]
        constraints = [models.UniqueConstraint(fields=["program", "number"], name="uniq_program_week")]


class ProgramDay(models.Model):
    week = models.ForeignKey(ProgramWeek, on_delete=models.CASCADE, related_name="days")
    weekday = models.PositiveSmallIntegerField(validators=[MaxValueValidator(6)])  # 0 = Monday
    name = models.CharField(max_length=60, blank=True, default="")  # "Upper A"
    is_rest = models.BooleanField(default=False)
    rest_note = models.CharField(max_length=200, blank=True, default="")  # "8k steps and 10 minutes of mobility"

    class Meta:
        ordering = ["weekday"]
        constraints = [models.UniqueConstraint(fields=["week", "weekday"], name="uniq_week_weekday")]

    @property
    def title(self):
        """What the client sees as today's workout: the coach's day name, or (left blank in the builder) the
        muscle groups it works, "Chest & Back", never an empty heading (Probid 2026-11-20)."""
        if self.name.strip():
            return self.name.strip()
        groups = []
        for pe in self.exercises.select_related("exercise").order_by("order"):
            g = pe.exercise.get_muscle_group_display()
            if g not in groups:
                groups.append(g)
        return " & ".join(groups[:2]) or "Workout"


class ProgramExercise(models.Model):
    day = models.ForeignKey(ProgramDay, on_delete=models.CASCADE, related_name="exercises")
    exercise = models.ForeignKey(Exercise, on_delete=models.PROTECT, related_name="program_uses")
    order = models.PositiveSmallIntegerField(default=0)
    superset_group = models.CharField(max_length=2, blank=True, default="")  # "A", "B"
    sets = models.PositiveSmallIntegerField(default=3, validators=[MinValueValidator(1), MaxValueValidator(12)])
    reps = models.CharField(max_length=20, default="8–10")  # "8–10", "AMRAP", "45 s"
    rpe = models.PositiveSmallIntegerField(null=True, blank=True, validators=[MaxValueValidator(10)])
    rest_seconds = models.PositiveSmallIntegerField(default=90, validators=[MaxValueValidator(300)])
    # rest after a warm-up / a drop set (null = same as rest_seconds); locked = the client cannot change rest (G44/G47)
    rest_warmup_seconds = models.PositiveSmallIntegerField(null=True, blank=True, validators=[MaxValueValidator(300)])
    rest_drop_seconds = models.PositiveSmallIntegerField(null=True, blank=True, validators=[MaxValueValidator(300)])
    rest_locked = models.BooleanField(default=False)
    tempo = models.CharField(max_length=12, blank=True, default="")
    target_weight_kg = models.DecimalField(max_digits=6, decimal_places=2, null=True, blank=True)
    # cardio: the heart-rate range the coach wants (beats per minute); the client logs the BPM they got
    bpm_min = models.PositiveSmallIntegerField(null=True, blank=True,
                                               validators=[MinValueValidator(30), MaxValueValidator(250)])
    bpm_max = models.PositiveSmallIntegerField(null=True, blank=True,
                                               validators=[MinValueValidator(30), MaxValueValidator(250)])
    note = models.CharField(max_length=200, blank=True, default="")
    # "Edit for this program": a per-program copy of name / video / steps / cues.
    override = models.JSONField(default=dict, blank=True)

    class Meta:
        ordering = ["order"]


class AssignmentStatus(models.TextChoices):
    UP_NEXT = "up_next", "Up next"
    ACTIVE = "active", "Active"
    ENDED = "ended", "Ended"


class ProgramAssignment(TimeStampedModel):
    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="program_assignments")
    program = models.ForeignKey(Program, on_delete=models.PROTECT, related_name="assignments")  # master
    custom_program = models.ForeignKey(Program, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    start_date = models.DateField(default=timezone.localdate)
    end_date = models.DateField(null=True, blank=True)
    status = models.CharField(max_length=10, choices=AssignmentStatus.choices, default=AssignmentStatus.ACTIVE,
                              db_index=True)
    assigned_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")
    # Why it stopped (Plan history badge): ended / replaced / unassigned; blank while it runs (D-43).
    end_reason = models.CharField(max_length=12, blank=True, default="")
    # The plan this one took over from: it comes back if this one is taken off the same day, unused.
    replaced = models.ForeignKey("self", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")

    class Meta:
        ordering = ["-start_date"]
        indexes = [models.Index(fields=["client", "status"])]

    @property
    def effective_program(self):
        return self.custom_program or self.program


class WorkoutLog(TimeStampedModel):
    """One workout the client did (or is doing) — the logger screen."""

    class Status(models.TextChoices):
        IN_PROGRESS = "in_progress", "In progress"
        COMPLETED = "completed", "Completed"
        DISCARDED = "discarded", "Discarded"

    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="workouts")
    assignment = models.ForeignKey(ProgramAssignment, null=True, blank=True, on_delete=models.SET_NULL,
                                   related_name="workouts")
    program_day = models.ForeignKey(ProgramDay, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    name = models.CharField(max_length=80, blank=True, default="")
    date = models.DateField(default=timezone.localdate, db_index=True)
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.IN_PROGRESS, db_index=True)
    started_at = models.DateTimeField(default=timezone.now)
    finished_at = models.DateTimeField(null=True, blank=True)
    duration_seconds = models.PositiveIntegerField(default=0)
    time_breakdown = models.JSONField(default=dict, blank=True)  # {"working": s, "rest": s, "between": s}
    effort = models.PositiveSmallIntegerField(null=True, blank=True, validators=[MinValueValidator(1),
                                                                                  MaxValueValidator(10)])
    note = models.TextField(blank=True, default="", max_length=2000)
    sets_done = models.PositiveSmallIntegerField(default=0)
    sets_planned = models.PositiveSmallIntegerField(default=0)
    auto_saved = models.BooleanField(default=False)  # saved at the last set after 3 hours
    paused_at = models.DateTimeField(null=True, blank=True)  # timer paused; resume moves started_at forward
    reopened_at = models.DateTimeField(null=True, blank=True)  # "Log more sets": Discard goes back to this point
    # Every time the workout was finished: [{"seconds": 720, "finished_at": iso, "ex": {"pe:12": 300}}]. The first
    # entry is the workout itself, each later one a "Log more sets" addition timed from 0:00.
    # duration_seconds = the sum, so 12 min + 4 min shows as 16 min with its parts.
    segments = models.JSONField(default=list, blank=True)

    class Meta:
        ordering = ["-date", "-started_at"]
        indexes = [models.Index(fields=["client", "-date"]), models.Index(fields=["client", "status"])]


class WorkoutEdit(models.Model):
    """One save of "Edit workout" on a finished workout (tracker H51-H56). The workout keeps the new values; this
    keeps what it was before, so every version can be looked back at, and the coach sees what changed."""

    workout = models.ForeignKey(WorkoutLog, on_delete=models.CASCADE, related_name="edits")
    number = models.PositiveSmallIntegerField()  # 1 = the first edit (version 2 of the workout)
    edited_at = models.DateTimeField(auto_now_add=True)
    by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    before = models.JSONField(default=dict, blank=True)  # the workout as it was (times and every set)
    changes = models.JSONField(default=list, blank=True)  # ["Start and end time", "Bench Press: 3 → 4 sets"]

    class Meta:
        ordering = ["number"]
        constraints = [models.UniqueConstraint(fields=["workout", "number"], name="one_edit_number_per_workout")]


class SetType(models.TextChoices):
    NORMAL = "normal", "Work set"
    WARMUP = "warmup", "Warm up"
    DROP = "drop", "Drop set"
    FAILURE = "failure", "Failure"


class SetLog(models.Model):
    workout = models.ForeignKey(WorkoutLog, on_delete=models.CASCADE, related_name="sets")
    program_exercise = models.ForeignKey(ProgramExercise, null=True, blank=True, on_delete=models.SET_NULL,
                                         related_name="+")
    exercise = models.ForeignKey(Exercise, on_delete=models.PROTECT, related_name="+")
    set_number = models.PositiveSmallIntegerField()
    weight_kg = models.DecimalField(max_digits=6, decimal_places=2, null=True, blank=True,
                                    validators=[MinValueValidator(0), MaxValueValidator(1000)])
    reps = models.PositiveSmallIntegerField(null=True, blank=True, validators=[MaxValueValidator(1000)])
    seconds = models.PositiveIntegerField(null=True, blank=True)
    # cardio: heart rate the client got (replaces the old km field)
    bpm = models.PositiveSmallIntegerField(null=True, blank=True,
                                           validators=[MinValueValidator(30), MaxValueValidator(250)])
    rpe = models.DecimalField(max_digits=3, decimal_places=1, null=True, blank=True,
                              validators=[MinValueValidator(1), MaxValueValidator(10)])
    # rest after this set: rest_seconds = the client's own timer for this set only (null = the exercise's rest for
    # its set type); rest_planned = what the timer was set to, rest_actual = what the client really rested (G45/G49)
    rest_seconds = models.PositiveSmallIntegerField(null=True, blank=True, validators=[MaxValueValidator(900)])
    rest_planned = models.PositiveSmallIntegerField(null=True, blank=True, validators=[MaxValueValidator(900)])
    rest_actual = models.PositiveIntegerField(null=True, blank=True)
    # set added in the app (maybe offline): the app's own id, so a repeated save does not add it twice
    client_key = models.CharField(max_length=40, blank=True, default="")
    is_bodyweight = models.BooleanField(default=False)
    is_warmup = models.BooleanField(default=False)  # always set_type == "warmup" (kept for every volume query)
    set_type = models.CharField(max_length=8, choices=SetType.choices, default=SetType.NORMAL)
    done = models.BooleanField(default=False)
    done_at = models.DateTimeField(null=True, blank=True)
    is_pr = models.BooleanField(default=False)

    class Meta:
        ordering = ["exercise_id", "set_number"]
        indexes = [models.Index(fields=["exercise", "done"])]

    def save(self, *args, **kwargs):
        # one truth for "warm-up": old callers set is_warmup, the logger sets set_type
        if self.is_warmup and self.set_type == SetType.NORMAL:
            self.set_type = SetType.WARMUP
        self.is_warmup = self.set_type == SetType.WARMUP
        uf = kwargs.get("update_fields")
        if uf is not None and ("is_warmup" in uf or "set_type" in uf):
            kwargs["update_fields"] = list({*uf, "is_warmup", "set_type"})
        super().save(*args, **kwargs)


class FocusMetric(models.TextChoices):
    VOLUME = "volume", "Total volume"
    VOLUME_UP = "volume_increase", "Volume increase"
    REPS = "reps", "Total reps"
    WEIGHT_REPS = "weight_reps", "Weight / reps"


class ClientExercisePref(models.Model):
    """What a client picked for one exercise in the logger: the number shown beside its ⋯ menu."""

    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="exercise_prefs")
    exercise = models.ForeignKey(Exercise, on_delete=models.CASCADE, related_name="+")
    focus_metric = models.CharField(max_length=16, choices=FocusMetric.choices, default=FocusMetric.VOLUME)
    # Rest timers the client set for this exercise (exercise ⋯ → Rest timers, G44); null = the plan's rest.
    rest_work = models.PositiveSmallIntegerField(null=True, blank=True, validators=[MaxValueValidator(900)])
    rest_warmup = models.PositiveSmallIntegerField(null=True, blank=True, validators=[MaxValueValidator(900)])
    rest_drop = models.PositiveSmallIntegerField(null=True, blank=True, validators=[MaxValueValidator(900)])
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["client", "exercise"], name="one_pref_per_client_exercise")]


class FormVideo(models.Model):
    """A short clip the client films of one set so the coach can check the form (workout log → "Form check video")."""

    workout = models.ForeignKey(WorkoutLog, on_delete=models.CASCADE, related_name="form_videos")
    exercise = models.ForeignKey(Exercise, on_delete=models.PROTECT, related_name="+")
    set_number = models.PositiveSmallIntegerField(null=True, blank=True)
    file = models.FileField(upload_to="form_videos/")
    file_size = models.PositiveBigIntegerField(default=0)
    duration_seconds = models.PositiveIntegerField(null=True, blank=True)
    note = models.CharField(max_length=300, blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at"]
