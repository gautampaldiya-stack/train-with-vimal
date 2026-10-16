from django.db import models

from apps.common.validators import validate_file_size


class GymSettings(models.Model):
    """Singleton: Settings → Gym profile, Regional & defaults, Branding."""

    name = models.CharField(max_length=100, default="Train With Vimal")
    email = models.EmailField(blank=True, default="hello@trainwithvimal.com")
    phone = models.CharField(max_length=20, blank=True, default="")
    address = models.CharField(max_length=300, blank=True, default="")
    instagram = models.CharField(max_length=100, blank=True, default="")
    # Client About page (ClientAbout board): tagline, website, support hours and the head coach card.
    tagline = models.CharField(max_length=120, blank=True, default="Online coaching for weight gain and muscle gain")
    website = models.CharField(max_length=200, blank=True, default="trainwithvimal.com")
    whatsapp = models.CharField(max_length=20, blank=True, default="")  # blank = same as phone
    support_hours = models.CharField(max_length=60, blank=True, default="Mon–Sat, 9 am – 9 pm")
    coach_role = models.CharField(max_length=60, blank=True, default="Head coach · Online")
    coach_intro = models.CharField(max_length=300, blank=True, default=(
        "Vimal coaches people online to gain weight and build muscle, with plans that fit home food and a busy day."))
    coach_stats = models.JSONField(default=list, blank=True)  # [["10+", "Years coaching"], ...]
    timezone = models.CharField(max_length=40, default="Asia/Kolkata")
    language = models.CharField(max_length=10, default="en")

    logo = models.ImageField(upload_to="branding/", null=True, blank=True, validators=[validate_file_size(5)])
    accent_color = models.CharField(max_length=7, default="#2563EB")
    theme = models.CharField(max_length=10, choices=[("light", "Light"), ("dark", "Dark"), ("system", "Match phone")],
                             default="light")
    branding_applied_at = models.DateTimeField(null=True, blank=True)
    branding_draft = models.JSONField(default=dict, blank=True)  # edits not applied yet

    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name_plural = "Gym settings"

    @classmethod
    def load(cls):
        obj, _ = cls.objects.get_or_create(pk=1)
        return obj


# Settings → Roles & permissions matrix. Admin is always on and locked.
ROLE_PERMISSIONS = [
    ("view_all_clients", "View all clients"),
    ("view_assigned_clients", "View assigned clients"),
    ("assign_clients", "Assign / reassign clients"),
    ("create_plans", "Create programs & meal plans"),
    ("checkins", "Daily + weekly check-ins"),
    ("manage_content", "Manage content library"),
    ("schedule_sessions", "Schedule sessions"),
    ("add_trainers", "Add trainers"),
    ("automations_settings", "Automations & settings"),
]

DEFAULT_ROLE_MATRIX = {
    "trainer": {
        "view_all_clients": False, "view_assigned_clients": True, "assign_clients": False, "create_plans": True,
        "checkins": True, "manage_content": True, "schedule_sessions": True, "add_trainers": False,
        "automations_settings": False,
    },
    "client": {
        "view_all_clients": False, "view_assigned_clients": False, "assign_clients": False, "create_plans": False,
        "checkins": True, "manage_content": False, "schedule_sessions": False, "add_trainers": False,
        "automations_settings": False,
    },
}


class RoleMatrix(models.Model):
    """Singleton holding the trainer and client columns of the permission matrix."""

    matrix = models.JSONField(default=dict)
    updated_at = models.DateTimeField(auto_now=True)

    @classmethod
    def load(cls):
        obj, created = cls.objects.get_or_create(pk=1, defaults={"matrix": DEFAULT_ROLE_MATRIX})
        return obj


class Integration(models.Model):
    class Kind(models.TextChoices):
        WHATSAPP = "whatsapp", "WhatsApp"
        EMAIL_DOMAIN = "email_domain", "Email domain"
        HEALTH = "health", "Health app"

    class Status(models.TextChoices):
        NOT_CONNECTED = "not_connected", "Not connected"
        PENDING = "pending", "Waiting"
        CONNECTED = "connected", "Connected"

    kind = models.CharField(max_length=20, choices=Kind.choices, unique=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.NOT_CONNECTED)
    config = models.JSONField(default=dict, blank=True)  # never secrets: those live in .env
    connected_at = models.DateTimeField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)
