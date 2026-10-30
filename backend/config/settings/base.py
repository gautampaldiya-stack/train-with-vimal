"""Base settings shared by every environment.

Every secret and host-specific value comes from the environment (see `.env.example`).
"""
from datetime import timedelta
from pathlib import Path

import environ
from celery.schedules import crontab

BASE_DIR = Path(__file__).resolve().parent.parent.parent

env = environ.Env(
    DEBUG=(bool, False),
    ALLOWED_HOSTS=(list, ["localhost", "127.0.0.1"]),
    CORS_ALLOWED_ORIGINS=(list, []),
    CSRF_TRUSTED_ORIGINS=(list, []),
)
environ.Env.read_env(BASE_DIR / ".env")

SECRET_KEY = env("SECRET_KEY")
DEBUG = env("DEBUG")
ALLOWED_HOSTS = env("ALLOWED_HOSTS")

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "django.contrib.postgres",
    # third party
    "rest_framework",
    "rest_framework_simplejwt.token_blacklist",
    "django_filters",
    "corsheaders",
    "drf_spectacular",
    "django_celery_beat",
    "channels",
    # project
    "apps.common",
    "apps.accounts",
    "apps.gym",
    "apps.trainers",
    "apps.clients",
    "apps.training",
    "apps.nutrition",
    "apps.habits",
    "apps.checkins",
    "apps.content",
    "apps.scheduling",
    "apps.automations",
    "apps.notifications",
    "apps.activity",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "apps.common.middleware.RequestContextMiddleware",
    "apps.common.idempotency.IdempotencyMiddleware",
]

ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [BASE_DIR / "templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

DATABASES = {"default": env.db("DATABASE_URL", default="postgres://twv:twv@localhost:5432/twv")}
DATABASES["default"]["CONN_MAX_AGE"] = env.int("DB_CONN_MAX_AGE", default=60)
DATABASES["default"]["CONN_HEALTH_CHECKS"] = True
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

AUTH_USER_MODEL = "accounts.User"
SILENCED_SYSTEM_CHECKS = ["auth.W004"]  # email is unique case-insensitively via a DB constraint
AUTHENTICATION_BACKENDS = ["apps.accounts.backends.EmailOrPhoneBackend"]

PASSWORD_HASHERS = [
    "django.contrib.auth.hashers.Argon2PasswordHasher",
    "django.contrib.auth.hashers.PBKDF2PasswordHasher",
]
AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator", "OPTIONS": {"min_length": 8}},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = env("TIME_ZONE", default="Asia/Kolkata")
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
MEDIA_URL = "media/"
MEDIA_ROOT = Path(env("MEDIA_ROOT", default=str(BASE_DIR / "media")))
# A single VPS without S3 serves uploads itself (deploy/README.md); with S3 leave it off.
SERVE_MEDIA = env.bool("SERVE_MEDIA", default=False)

# A planned meal of today can be logged, skipped or changed from this many minutes before its time (Probid 2026-10-30).
MEAL_OPEN_BEFORE_MINUTES = env.int("MEAL_OPEN_BEFORE_MINUTES", default=30)
STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage"},
}

# Upload limits (design: PDF 25 MB, image 10 MB; video handled separately).
DATA_UPLOAD_MAX_MEMORY_SIZE = 10 * 1024 * 1024
FILE_UPLOAD_MAX_MEMORY_SIZE = 10 * 1024 * 1024
MAX_IMAGE_UPLOAD_MB = 10
MAX_PDF_UPLOAD_MB = 25
MAX_VIDEO_UPLOAD_MB = env.int("MAX_VIDEO_UPLOAD_MB", default=500)

# ---------------------------------------------------------------- DRF
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": ["apps.accounts.authentication.SessionJWTAuthentication"],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticated",
        "apps.accounts.permissions.IsActiveAccount",
    ],
    "DEFAULT_FILTER_BACKENDS": [
        "django_filters.rest_framework.DjangoFilterBackend",
        "rest_framework.filters.SearchFilter",
        "rest_framework.filters.OrderingFilter",
    ],
    "DEFAULT_PAGINATION_CLASS": "apps.common.pagination.DefaultPagination",
    "PAGE_SIZE": 25,
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    "EXCEPTION_HANDLER": "apps.common.exceptions.exception_handler",
    "DEFAULT_THROTTLE_CLASSES": [
        "rest_framework.throttling.AnonRateThrottle",
        "rest_framework.throttling.UserRateThrottle",
    ],
    "DEFAULT_THROTTLE_RATES": {
        "anon": env("THROTTLE_ANON", default="60/min"),
        "user": env("THROTTLE_USER", default="600/min"),
        "auth": env("THROTTLE_AUTH", default="10/min"),
        "otp": env("THROTTLE_OTP", default="5/hour"),
        "data_export": "5/day",
        "problem_report": "20/day",
    },
    "DATETIME_FORMAT": "iso-8601",
    "COERCE_DECIMAL_TO_STRING": False,
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=env.int("JWT_ACCESS_MINUTES", default=15)),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=env.int("JWT_REFRESH_DAYS", default=30)),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": True,
    "UPDATE_LAST_LOGIN": True,
    "AUTH_HEADER_TYPES": ("Bearer",),
    "USER_ID_FIELD": "id",
    "USER_ID_CLAIM": "uid",
}

SPECTACULAR_SETTINGS = {
    "TITLE": "Train With Vimal API",
    "DESCRIPTION": "Backend for the Train With Vimal coaching app (admin, trainer, client).",
    "VERSION": "1.0.0",
    "SERVE_INCLUDE_SCHEMA": False,
    "COMPONENT_SPLIT_REQUEST": True,
    "SCHEMA_PATH_PREFIX": r"/api/v1",
}

CORS_ALLOWED_ORIGINS = env("CORS_ALLOWED_ORIGINS")
CORS_ALLOW_CREDENTIALS = False
from corsheaders.defaults import default_headers  # noqa: E402

CORS_ALLOW_HEADERS = (*default_headers, "idempotency-key", "x-client")
CORS_EXPOSE_HEADERS = ["Idempotent-Replay", "Content-Disposition"]
CSRF_TRUSTED_ORIGINS = env("CSRF_TRUSTED_ORIGINS")

# ---------------------------------------------------------------- Security
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = "same-origin"
X_FRAME_OPTIONS = "DENY"
SESSION_COOKIE_HTTPONLY = True

# ---------------------------------------------------------------- Cache / Celery
REDIS_URL = env("REDIS_URL", default="redis://localhost:6379/0")
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.redis.RedisCache",
        "LOCATION": REDIS_URL,
        "TIMEOUT": 300,
    }
}
CHANNEL_LAYERS = {
    "default": {
        "BACKEND": "channels_redis.core.RedisChannelLayer",
        "CONFIG": {"hosts": [env("CHANNELS_REDIS_URL", default="redis://localhost:6379/2")]},
    }
}
CELERY_BROKER_URL = env("CELERY_BROKER_URL", default=REDIS_URL)
CELERY_RESULT_BACKEND = env("CELERY_RESULT_BACKEND", default=REDIS_URL)

# No Redis on this machine (REDIS_URL left empty in .env): run everything in one process.
# Cache and realtime stay in memory, background jobs run straight away, scheduled reminders do not run.
if not REDIS_URL:
    CACHES = {"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}}
    CHANNEL_LAYERS = {"default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}}
    CELERY_BROKER_URL, CELERY_RESULT_BACKEND = "memory://", "cache+memory://"
CELERY_TIMEZONE = TIME_ZONE
CELERY_TASK_ACKS_LATE = True
CELERY_WORKER_PREFETCH_MULTIPLIER = 1
CELERY_TASK_TIME_LIMIT = 300
CELERY_TASK_SOFT_TIME_LIMIT = 240
CELERY_BEAT_SCHEDULER = "django_celery_beat.schedulers:DatabaseScheduler"
CELERY_TASK_ALWAYS_EAGER = env.bool("CELERY_TASK_ALWAYS_EAGER", default=not REDIS_URL)
CELERY_IMPORTS = ["apps.notifications.reminders", "apps.clients.account"]

_R = "apps.notifications.reminders."
CELERY_BEAT_SCHEDULE = {
    # automations
    "automations-due-runs": {"task": "apps.automations.tasks.process_due_runs", "schedule": 60.0},
    "automations-poll": {"task": "apps.automations.tasks.poll_triggers", "schedule": crontab(minute="*/15")},
    # client reminders (each checks its own 15-minute window)
    "workout-reminders": {"task": _R + "workout_reminders", "schedule": crontab(minute="*/15")},
    "meal-reminders": {"task": _R + "meal_reminders", "schedule": crontab(minute="*/15")},
    "checkin-reminders": {"task": _R + "checkin_reminders", "schedule": crontab(minute=0, hour=9)},
    "habit-reminders": {"task": _R + "habit_reminders", "schedule": crontab(minute=0, hour=20)},
    "water-reminders": {"task": _R + "water_reminders", "schedule": crontab(minute=0, hour="10-20/2")},
    "supplement-reminders": {"task": _R + "supplement_reminders", "schedule": crontab(minute=0, hour="8,12,21,22")},
    "purge-data-exports": {"task": "apps.clients.account.purge_data_exports", "schedule": crontab(minute=45, hour=3)},
    "onboarding-reminders": {"task": _R + "onboarding_reminders", "schedule": crontab(minute=0, hour=9)},
    "scheduled-forms": {"task": "apps.checkins.tasks.send_scheduled_forms", "schedule": crontab(minute="*/15")},
    # team + housekeeping
    "document-expiry": {"task": _R + "document_expiry_reminders", "schedule": crontab(minute=30, hour=8)},
    "daily-summaries": {"task": _R + "daily_summaries", "schedule": crontab(minute=0, hour=8)},
    "coach-daily-notices": {"task": _R + "coach_daily_notices", "schedule": crontab(minute=0, hour=9)},
    "staff-digests": {"task": _R + "staff_digests", "schedule": crontab(minute=0, hour=8)},
    "email-domain-check": {"task": "apps.gym.tasks.email_domain_check", "schedule": crontab(minute=20)},
    "nightly-client-stats": {"task": _R + "nightly_client_stats", "schedule": crontab(minute=30, hour=2)},
    "roll-plans": {"task": _R + "roll_plans", "schedule": crontab(minute=5, hour=0)},
    "auto-save-workouts": {"task": _R + "auto_save_workouts", "schedule": crontab(minute="*/15")},
    "purge-deleted": {"task": _R + "purge_deleted", "schedule": crontab(minute=0, hour=3)},
    "purge-notifications": {"task": "apps.notifications.tasks.purge_old_notifications",
                            "schedule": crontab(minute=15, hour=3)},
}

# ---------------------------------------------------------------- App settings
APP_NAME = "Train With Vimal"
FRONTEND_URL = env("FRONTEND_URL", default="http://localhost:5173")
# Invite links live on the same site as the app (live: https://twv.prowavetech.in/join/<code>).
INVITE_BASE_URL = env("INVITE_BASE_URL", default=FRONTEND_URL.rstrip("/") + "/join")
EMAIL_BACKEND = env("EMAIL_BACKEND", default="django.core.mail.backends.console.EmailBackend")
EMAIL_HOST = env("EMAIL_HOST", default="")
EMAIL_PORT = env.int("EMAIL_PORT", default=587)
EMAIL_HOST_USER = env("EMAIL_HOST_USER", default="")
EMAIL_HOST_PASSWORD = env("EMAIL_HOST_PASSWORD", default="")
EMAIL_USE_TLS = env.bool("EMAIL_USE_TLS", default=True)
DEFAULT_FROM_EMAIL = env("DEFAULT_FROM_EMAIL", default="Train With Vimal <hello@trainwithvimal.com>")

# Channel providers: "console" logs instead of sending (dev); real providers need keys.
PUSH_PROVIDER = env("PUSH_PROVIDER", default="console")  # console | fcm
FCM_PROJECT_ID = env("FCM_PROJECT_ID", default="")
FCM_SERVICE_ACCOUNT_FILE = env("FCM_SERVICE_ACCOUNT_FILE", default="")
WHATSAPP_PROVIDER = env("WHATSAPP_PROVIDER", default="console")  # console | meta
WHATSAPP_PHONE_NUMBER_ID = env("WHATSAPP_PHONE_NUMBER_ID", default="")
WHATSAPP_ACCESS_TOKEN = env("WHATSAPP_ACCESS_TOKEN", default="")

# How long one-time links work, in minutes (copy on the boards: verify 24 h, reset 15 min, login link 7 days).
TOKEN_TTL_MINUTES = {
    "email_verify": 24 * 60,
    "password_reset": 15,
    "login_link": 7 * 24 * 60,
}

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {"plain": {"format": "%(asctime)s %(levelname)s %(name)s %(message)s"}},
    "handlers": {"console": {"class": "logging.StreamHandler", "formatter": "plain"}},
    "root": {"handlers": ["console"], "level": env("LOG_LEVEL", default="INFO")},
    "loggers": {"django.db.backends": {"level": "WARNING"}},
}
