import re

from django.conf import settings
from django.contrib import admin
from django.http import JsonResponse
from django.urls import include, path, re_path
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView


def health(request):
    return JsonResponse({"ok": True})


api = [
    path("", include("apps.accounts.urls")),
    path("", include("apps.gym.urls")),
    path("", include("apps.trainers.urls")),
    path("", include("apps.clients.urls")),
    path("", include("apps.training.urls")),
    path("", include("apps.nutrition.urls")),
    path("", include("apps.habits.urls")),
    path("", include("apps.checkins.urls")),
    path("", include("apps.content.urls")),
    path("", include("apps.scheduling.urls")),
    path("", include("apps.automations.urls")),
    path("", include("apps.notifications.urls")),
    path("", include("apps.activity.urls")),
]

urlpatterns = [
    path("health/", health),
    path("django-admin/", admin.site.urls),
    path("api/v1/", include(api)),
    path("api/schema/", SpectacularAPIView.as_view(), name="schema"),
    path("api/docs/", SpectacularSwaggerView.as_view(url_name="schema"), name="api-docs"),
]

# Media from the server disk: in dev, and on a single VPS without S3 (SERVE_MEDIA=True in .env).
if settings.DEBUG or settings.SERVE_MEDIA:
    from apps.common.media import serve_media

    # `static()` adds nothing when DEBUG is off, so the route is written out here.
    urlpatterns += [re_path(r"^%s(?P<path>.*)$" % re.escape(settings.MEDIA_URL.lstrip("/")), serve_media,
                            {"document_root": settings.MEDIA_ROOT})]
