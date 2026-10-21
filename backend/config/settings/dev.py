from .base import *  # noqa: F401,F403
from .base import env

DEBUG = env.bool("DEBUG", default=True)
CORS_ALLOW_ALL_ORIGINS = env.bool("CORS_ALLOW_ALL_ORIGINS", default=True)

# A phone on the same wifi calls the laptop by its IP (http://192.168.x.x:8000). In development any host name is
# accepted so that works without editing ALLOWED_HOSTS; set ALLOW_ANY_HOST=False to use the list from .env.
if DEBUG and env.bool("ALLOW_ANY_HOST", default=True):
    ALLOWED_HOSTS = ["*"]
