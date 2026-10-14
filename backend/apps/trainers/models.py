import uuid

from django.conf import settings
from django.contrib.postgres.fields import ArrayField
from django.db import models
from django.utils import timezone

from apps.common.models import TimeStampedModel
from apps.common.validators import DOCUMENT_EXTENSIONS, validate_file_size

from .permissions_catalog import (
    ALL_CLIENTS_PRESET,
    ASSIGNED_PRESET,
    MATRIX_CEILING,
    MATRIX_GRANT,
    VISIBILITY_DEFAULTS,
)


class AccessMode(models.TextChoices):
    ASSIGNED = "assigned", "Assigned clients"
    ALL = "all", "All clients"
    CUSTOM = "custom", "Custom"


def _visibility_default():
    return dict(VISIBILITY_DEFAULTS)


class TrainerProfile(TimeStampedModel):
    """A trainer (Vimal, the owner, also has one so he can coach his own clients)."""

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="trainer_profile")
    speciality = ArrayField(models.CharField(max_length=40), default=list, blank=True)
    max_clients = models.PositiveSmallIntegerField(default=30)
    bio = models.TextField(blank=True, default="", max_length=1500)
    experience_since = models.PositiveSmallIntegerField(null=True, blank=True)  # year
    mode = models.CharField(max_length=20, default="gym_online",
                            choices=[("gym", "Gym"), ("online", "Online"), ("gym_online", "Gym and online")])
    languages = ArrayField(models.CharField(max_length=30), default=list, blank=True)
    works_best_with = models.CharField(max_length=200, blank=True, default="")
    instagram = models.CharField(max_length=120, blank=True, default="")
    youtube = models.CharField(max_length=200, blank=True, default="")
    page_link = models.CharField(max_length=200, blank=True, default="")
    website = models.URLField(blank=True, default="")
    joining_date = models.DateField(default=timezone.localdate)
    access_mode = models.CharField(max_length=10, choices=AccessMode.choices, default=AccessMode.ASSIGNED)
    permissions = models.JSONField(default=dict, blank=True)  # used when access_mode == custom
    visibility = models.JSONField(default=_visibility_default, blank=True)
    is_owner = models.BooleanField(default=False)

    class Meta:
        ordering = ["user__full_name"]

    def __str__(self):
        return self.user.full_name

    # ---------------------------------------------------------------- access
    def effective_permissions(self):
        if self.user.is_admin:
            return {k: True for k in ASSIGNED_PRESET}
        if self.access_mode == AccessMode.ALL:
            perms = dict(ALL_CLIENTS_PRESET)
        elif self.access_mode == AccessMode.CUSTOM:
            perms = {**ASSIGNED_PRESET, **{k: bool(v) for k, v in self.permissions.items() if k in ASSIGNED_PRESET}}
        else:
            perms = dict(ASSIGNED_PRESET)
        from apps.gym.models import DEFAULT_ROLE_MATRIX, RoleMatrix

        matrix = {**DEFAULT_ROLE_MATRIX["trainer"], **RoleMatrix.load().matrix.get("trainer", {})}
        for key, col in MATRIX_CEILING.items():
            if not matrix.get(col, True):
                perms[key] = False
        for key, col in MATRIX_GRANT.items():
            if matrix.get(col):
                perms[key] = True
        return perms

    def has_perm(self, key):
        return bool(self.effective_permissions().get(key))

    # ---------------------------------------------------------------- load
    @property
    def active_client_count(self):
        if hasattr(self, "_client_count"):
            return self._client_count
        return self.user.coached_clients.filter(user__status="active").count()

    @property
    def is_full(self):
        return self.active_client_count >= self.max_clients


def document_path(instance, filename):
    ext = filename.rsplit(".", 1)[-1].lower()
    return f"trainer-docs/{instance.trainer_id}/{uuid.uuid4().hex}.{ext}"


class TrainerDocument(TimeStampedModel):
    class Kind(models.TextChoices):
        CERTIFICATE = "certificate", "Certificate"
        ID_PROOF = "id_proof", "ID proof"
        CONTRACT = "contract", "Contract"

    class Visibility(models.TextChoices):
        ADMINS = "admins", "Admins only"
        ADMINS_CLIENTS = "admins_clients", "Admins and clients"

    trainer = models.ForeignKey(TrainerProfile, on_delete=models.CASCADE, related_name="documents")
    kind = models.CharField(max_length=12, choices=Kind.choices)
    name = models.CharField(max_length=120)
    issuer = models.CharField(max_length=120, blank=True, default="")
    issued_on = models.DateField(null=True, blank=True)  # month precision, day = 1
    expires_on = models.DateField(null=True, blank=True)  # null = no end
    visibility = models.CharField(max_length=16, choices=Visibility.choices, default=Visibility.ADMINS_CLIENTS)
    remind_before_expiry = models.BooleanField(default=True)
    file = models.FileField(upload_to=document_path, validators=[validate_file_size(25)])
    verified_at = models.DateTimeField(null=True, blank=True)
    verified_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                                    related_name="+")
    signed = models.BooleanField(default=False)  # contracts

    class Meta:
        ordering = ["kind", "name"]

    ALLOWED_EXT = DOCUMENT_EXTENSIONS

    @property
    def status(self):
        if self.kind == self.Kind.CONTRACT and self.signed:
            return "signed"
        if self.expires_on and self.expires_on < timezone.localdate():
            return "expired"
        if self.expires_on and (self.expires_on - timezone.localdate()).days <= 60:
            return "expires_soon"
        return "verified" if self.verified_at else "not_checked"


class AccessRequest(TimeStampedModel):
    """Trainer Me → "Ask for more access"."""

    class Status(models.TextChoices):
        OPEN = "open", "Waiting"
        APPROVED = "approved", "Approved"
        DECLINED = "declined", "Declined"

    trainer = models.ForeignKey(TrainerProfile, on_delete=models.CASCADE, related_name="access_requests")
    permissions = ArrayField(models.CharField(max_length=40))
    reason = models.TextField(blank=True, default="", max_length=1000)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.OPEN, db_index=True)
    decided_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                                   related_name="+")
    decided_at = models.DateTimeField(null=True, blank=True)
