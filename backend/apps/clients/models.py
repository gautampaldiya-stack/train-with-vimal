from django.conf import settings
from django.db import models
from django.utils import timezone

from apps.common.models import SoftDeleteModel, TimeStampedModel


class Goal(models.TextChoices):
    FAT_LOSS = "fat_loss", "Fat loss"
    MUSCLE_GAIN = "muscle_gain", "Muscle gain"
    STRENGTH = "strength", "Strength"
    RECOMP = "recomp", "Recomp"
    GENERAL = "general", "General fitness"
    EVENT = "event", "Event prep"


class SignupSource(models.TextChoices):
    WEB = "web", "Web"
    ANDROID = "android", "Android app"
    IOS = "ios", "iPhone app"
    ADDED = "added", "Added by the team"


ONBOARDING_STEPS = ["account", "basics", "goal_body", "health", "food"]
# What the client app asks (ClientLogin / ClientWelcome boards), in order. Staff boards show ONBOARDING_STEPS;
# STAFF_STEP_FROM_CLIENT says which client steps complete each staff step.
CLIENT_ONBOARDING_STEPS = ["goal", "about", "schedule", "health", "food"]
STAFF_STEP_FROM_CLIENT = {
    "basics": ("about", "schedule"),
    "goal_body": ("goal", "about"),
    "health": ("health",),
    "food": ("food",),
}
ONBOARDING_LABELS = {
    "account": ("Account made", "Email and phone checked"),
    "basics": ("Basic details", "Name, age, city"),
    "goal_body": ("Goal and body", ""),
    "health": ("Health and PAR-Q", "7 health questions"),
    "food": ("Food preferences", ""),
}


class ClientProfile(TimeStampedModel):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="client_profile")
    trainer = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="coached_clients",
        limit_choices_to={"role__in": ["admin", "trainer"]},
    )
    goal = models.CharField(max_length=12, choices=Goal.choices, blank=True, default="")
    height_cm = models.DecimalField(max_digits=5, decimal_places=1, null=True, blank=True)
    start_weight_kg = models.DecimalField(max_digits=5, decimal_places=1, null=True, blank=True)
    current_weight_kg = models.DecimalField(max_digits=5, decimal_places=1, null=True, blank=True)
    target_weight_kg = models.DecimalField(max_digits=5, decimal_places=1, null=True, blank=True)
    health_notes = models.TextField(blank=True, default="", max_length=2000)
    start_date = models.DateField(null=True, blank=True)  # day 1 of workout and meal plans
    package_name = models.CharField(max_length=80, blank=True, default="")
    package_ends_on = models.DateField(null=True, blank=True)

    onboarding = models.JSONField(default=dict, blank=True)  # answers of the 5 setup steps
    onboarding_done = models.JSONField(default=list, blank=True)  # step keys finished
    onboarding_skipped_at = models.DateTimeField(null=True, blank=True)
    ask_parq = models.BooleanField(default=True)
    # Body measurements the coach asks this client for (keys of checkins.MEASURES); empty = the default set.
    measure_keys = models.JSONField(default=list, blank=True)
    # Progress photos come with the weekly check-in every N weeks (the coach picks; trainer screens later).
    photo_every_weeks = models.PositiveSmallIntegerField(default=2)

    signup_source = models.CharField(max_length=10, choices=SignupSource.choices, default=SignupSource.ADDED)
    invite_link = models.ForeignKey("InviteLink", null=True, blank=True, on_delete=models.SET_NULL,
                                    related_name="clients")
    invited_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                                   related_name="+")
    paused_at = models.DateTimeField(null=True, blank=True)
    removed_at = models.DateTimeField(null=True, blank=True, db_index=True)  # "Delete client" (kept 30 days)

    # Denormalised numbers kept fresh by a nightly task, so dashboards on thousands of
    # clients never compute adherence row by row.
    adherence_7d = models.PositiveSmallIntegerField(null=True, blank=True)
    adherence_30d = models.PositiveSmallIntegerField(null=True, blank=True)
    at_risk = models.BooleanField(default=False, db_index=True)
    at_risk_reason = models.CharField(max_length=200, blank=True, default="")
    last_reminded_at = models.DateTimeField(null=True, blank=True)
    stats_updated_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [
            models.Index(fields=["trainer", "at_risk"]),
            models.Index(fields=["goal"]),
        ]

    def __str__(self):
        return self.user.full_name

    @property
    def onboarding_progress(self):
        done = [s for s in ONBOARDING_STEPS if s in (self.onboarding_done or [])]
        return {"done": len(done), "total": len(ONBOARDING_STEPS), "steps": done}

    @property
    def client_steps_done(self):
        answers = self.onboarding or {}
        return [k for k in CLIENT_ONBOARDING_STEPS if k in answers]

    @property
    def has_health_note(self):
        conditions = (self.onboarding or {}).get("health", {}).get("conditions") or []
        return bool(self.health_notes.strip()) or any(c and c != "none" for c in conditions)


class InviteLink(SoftDeleteModel):
    """trainwithvimal.app/join/<code> — sign-up links shared by the team."""

    code = models.CharField(max_length=24, unique=True)
    trainer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="invite_links")
    label = models.CharField(max_length=80, blank=True, default="")  # "Instagram · October", only staff sees
    expires_at = models.DateTimeField(null=True, blank=True)
    max_uses = models.PositiveIntegerField(null=True, blank=True)  # null = no limit
    needs_approval = models.BooleanField(default=True)
    is_on = models.BooleanField(default=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")

    @property
    def end_reason(self):
        """Why the link no longer makes accounts: "expired", "full", "off", or None while it works."""
        if self.expires_at and self.expires_at <= timezone.now():
            return "expired"
        if self.max_uses is not None and self.clients.count() >= self.max_uses:
            return "full"
        return None if self.is_on else "off"

    @property
    def state(self):
        reason = self.end_reason
        return "on" if reason is None else ("off" if reason == "off" else "ended")


class Approval(TimeStampedModel):
    """A sign-up waiting in Approvals, and its decision (History tab)."""

    class Status(models.TextChoices):
        WAITING = "waiting", "Waiting"
        APPROVED = "approved", "Approved"
        REJECTED = "rejected", "Rejected"

    class RejectReason(models.TextChoices):
        NOT_FIT = "not_fit", "Not a fit for our coaching"
        HAS_ACCOUNT = "has_account", "Already has an account"
        FAKE = "fake", "Wrong or fake details"
        NO_TRAINER = "no_trainer", "No trainer free right now"
        OTHER = "other", "Something else"

    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="approvals")
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.WAITING, db_index=True)
    invited_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                                   related_name="+")
    signed_up_from = models.CharField(max_length=10, choices=SignupSource.choices, default=SignupSource.WEB)
    decided_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                                   related_name="+")
    decided_at = models.DateTimeField(null=True, blank=True, db_index=True)
    assigned_trainer = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                                         related_name="+")
    reject_reason = models.CharField(max_length=12, choices=RejectReason.choices, blank=True, default="")
    message = models.TextField(blank=True, default="", max_length=2000)
    moved_back = models.BooleanField(default=False)

    class Meta:
        ordering = ["created_at"]  # oldest first, like the design
        indexes = [models.Index(fields=["status", "created_at"])]


class InfoRequest(TimeStampedModel):
    """Approvals → "Ask for info"."""

    approval = models.ForeignKey(Approval, on_delete=models.CASCADE, related_name="info_requests")
    items = models.JSONField(default=list)  # ["setup", "health_form", "doctor_note", "photo", "phone"]
    channels = models.JSONField(default=list)  # ["email", "in_app", ...]
    sent_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")


class ClientNote(SoftDeleteModel):
    """Trainer's private notes on a client. Clients never see these."""

    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="staff_notes")
    author = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")
    body = models.TextField(max_length=5000)
    is_flag = models.BooleanField(default=False)  # shows in "Needs attention" (e.g. knee pain)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["client", "-created_at"])]
