from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.http import JsonResponse
from django.urls import include, path
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

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
