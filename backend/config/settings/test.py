from .base import *  # noqa: F401,F403

DEBUG = False
PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]
CELERY_TASK_ALWAYS_EAGER = True
CELERY_TASK_EAGER_PROPAGATES = True
CACHES = {"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}}
CHANNEL_LAYERS = {"default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}}
EMAIL_BACKEND = "django.core.mail.backends.locmem.EmailBackend"
REST_FRAMEWORK = {**REST_FRAMEWORK, "DEFAULT_THROTTLE_CLASSES": []}  # noqa: F405
STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.InMemoryStorage"},
    "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
}
REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"] = {  # noqa: F405
    **REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"], "auth": "1000/min", "otp": "1000/min"}  # noqa: F405
