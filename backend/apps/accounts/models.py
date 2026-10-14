import uuid

from django.contrib.auth.base_user import AbstractBaseUser, BaseUserManager
from django.contrib.auth.models import PermissionsMixin
from django.db import models
from django.db.models.functions import Lower
from django.utils import timezone as dj_tz

from apps.common.models import TimeStampedModel
from apps.common.utils import avatar_color, initials
from apps.common.validators import IMAGE_EXTENSIONS, normalize_phone


class Role(models.TextChoices):
    ADMIN = "admin", "Admin"
    TRAINER = "trainer", "Trainer"
    CLIENT = "client", "Client"


class AccountStatus(models.TextChoices):
    PENDING = "pending", "Pending approval"  # signed up from a link, waiting in Approvals
    ACTIVE = "active", "Active"
    PAUSED = "paused", "Paused"
    REJECTED = "rejected", "Rejected"
    DEACTIVATED = "deactivated", "Deactivated"  # trainer turned off by admin


class Gender(models.TextChoices):
    FEMALE = "female", "Female"
    MALE = "male", "Male"
    OTHER = "other", "Other"
    UNSPECIFIED = "", "Prefer not to say"


class UserManager(BaseUserManager):
    use_in_migrations = True

    def _create(self, email, password, **extra):
        email = self.normalize_email(email).lower() if email else None
        if extra.get("phone"):
            extra["phone"] = normalize_phone(extra["phone"])
        user = self.model(email=email, **extra)
        if password:
            user.set_password(password)
        else:
            user.set_unusable_password()
        user.full_clean(exclude=["password"])
        user.save(using=self._db)
        return user

    def create_user(self, email=None, password=None, **extra):
        extra.setdefault("role", Role.CLIENT)
        return self._create(email, password, **extra)

    def create_superuser(self, email, password, **extra):
        extra.update(role=Role.ADMIN, is_superuser=True, is_django_staff=True, status=AccountStatus.ACTIVE)
        extra.setdefault("full_name", "Admin")
        return self._create(email, password, **extra)

    def get_by_natural_key(self, username):
        return self.get(**{f"{self.model.USERNAME_FIELD}__iexact": username})


def avatar_path(instance, filename):
    ext = filename.rsplit(".", 1)[-1].lower()
    return f"avatars/{instance.id}/{uuid.uuid4().hex}.{ext}"


class User(AbstractBaseUser, PermissionsMixin):
    """One login for everyone. Email and mobile are each unique across ALL roles
    (business rule: one person never has two accounts with the same email or mobile)."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email = models.EmailField(max_length=254, null=True, blank=True)
    phone = models.CharField(max_length=16, null=True, blank=True)
    full_name = models.CharField(max_length=120)
    role = models.CharField(max_length=10, choices=Role.choices, db_index=True)
    status = models.CharField(
        max_length=12, choices=AccountStatus.choices, default=AccountStatus.ACTIVE, db_index=True
    )

    gender = models.CharField(max_length=10, choices=Gender.choices, blank=True, default="")
    date_of_birth = models.DateField(null=True, blank=True)
    city = models.CharField(max_length=80, blank=True, default="")
    avatar = models.ImageField(upload_to=avatar_path, null=True, blank=True)

    email_verified_at = models.DateTimeField(null=True, blank=True)
    pending_email = models.EmailField(blank=True, default="")  # email change waits for verification
    password_changed_at = models.DateTimeField(null=True, blank=True)
    last_seen_at = models.DateTimeField(null=True, blank=True)
    deletion_requested_at = models.DateTimeField(null=True, blank=True)

    # Client "Units" settings (trainer still sees their own units).
    unit_weight = models.CharField(max_length=2, choices=[("kg", "kg"), ("lb", "lb")], default="kg")
    unit_length = models.CharField(max_length=2, choices=[("cm", "cm"), ("in", "in")], default="cm")
    unit_water = models.CharField(max_length=2, choices=[("l", "L"), ("oz", "oz")], default="l")
    timezone = models.CharField(max_length=40, default="Asia/Kolkata")

    is_active = models.BooleanField(default=True)  # Django-level kill switch
    is_django_staff = models.BooleanField(default=False)  # may open /django-admin/
    date_joined = models.DateTimeField(default=dj_tz.now, db_index=True)

    objects = UserManager()

    USERNAME_FIELD = "email"
    EMAIL_FIELD = "email"
    REQUIRED_FIELDS = []

    class Meta:
        ordering = ["full_name"]
        constraints = [
            models.UniqueConstraint(Lower("email"), name="uniq_user_email_ci"),
            models.UniqueConstraint(fields=["phone"], name="uniq_user_phone"),
            models.UniqueConstraint(
                fields=["role"], condition=models.Q(role="admin"), name="only_one_admin"
            ),
            models.CheckConstraint(
                condition=models.Q(email__isnull=False) | models.Q(phone__isnull=False),
                name="user_has_email_or_phone",
            ),
        ]
        indexes = [models.Index(fields=["role", "status"])]

    def __str__(self):
        return self.full_name or self.email or self.phone or str(self.id)

    def clean(self):
        if self.email:
            self.email = self.email.strip().lower()
        if self.phone:
            self.phone = normalize_phone(self.phone)
        else:
            self.phone = None
        if not self.email:
            self.email = None

    # --- role helpers
    @property
    def is_admin(self):
        return self.role == Role.ADMIN

    @property
    def is_trainer(self):
        return self.role == Role.TRAINER

    @property
    def is_client(self):
        return self.role == Role.CLIENT

    @property
    def is_staff_member(self):
        return self.role in (Role.ADMIN, Role.TRAINER)

    @property
    def is_staff(self):  # Django admin site
        return self.is_django_staff

    @property
    def first_name(self):
        return (self.full_name or "").split(" ")[0]

    @property
    def initials(self):
        return initials(self.full_name)

    @property
    def avatar_color(self):
        return avatar_color(self.full_name)

    @property
    def can_use_app(self):
        return self.is_active and self.status == AccountStatus.ACTIVE


ALLOWED_AVATAR_EXT = IMAGE_EXTENSIONS


class UserSession(TimeStampedModel):
    """One row per logged-in device ("Where you are logged in")."""

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="sessions")
    device_name = models.CharField(max_length=120, blank=True, default="")  # "Pixel 7", "Chrome on Windows"
    platform = models.CharField(max_length=20, blank=True, default="")  # android / ios / web
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    city = models.CharField(max_length=80, blank=True, default="")
    user_agent = models.CharField(max_length=300, blank=True, default="")
    last_active_at = models.DateTimeField(default=dj_tz.now)
    revoked_at = models.DateTimeField(null=True, blank=True, db_index=True)

    class Meta:
        ordering = ["-last_active_at"]
        indexes = [models.Index(fields=["user", "revoked_at"])]

    @property
    def is_active(self):
        return self.revoked_at is None

    def revoke(self):
        if not self.revoked_at:
            self.revoked_at = dj_tz.now()
            self.save(update_fields=["revoked_at", "updated_at"])


class OneTimeToken(TimeStampedModel):
    """Email verification, password reset and coach-made login links.
    Only the SHA-256 of the token is stored; links are single use and expire."""

    class Purpose(models.TextChoices):
        EMAIL_VERIFY = "email_verify"
        PASSWORD_RESET = "password_reset"
        LOGIN_LINK = "login_link"  # "Your coach added you" -> set password

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="one_time_tokens")
    purpose = models.CharField(max_length=20, choices=Purpose.choices)
    token_hash = models.CharField(max_length=64, unique=True)
    email = models.EmailField(blank=True, default="")  # which address a verify link was for
    expires_at = models.DateTimeField()
    used_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=["user", "purpose", "used_at"])]

    @property
    def is_valid(self):
        return self.used_at is None and self.expires_at > dj_tz.now()
