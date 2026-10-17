from django.urls import path
from rest_framework.routers import DefaultRouter

from . import me, views

router = DefaultRouter()
router.register("trainers", views.TrainerViewSet, basename="trainer")
router.register(r"trainers/(?P<trainer_pk>me|[0-9a-f-]+)/documents", views.TrainerDocumentViewSet,
                basename="trainer-document")
router.register("access-requests", views.AccessRequestViewSet, basename="access-request")

urlpatterns = [
    path("trainers/me/", views.TrainerMeView.as_view(), name="trainer-me"),
    path("trainers/me/visibility/", views.TrainerMeVisibilityView.as_view(), name="trainer-me-visibility"),
    path("trainers/me/activity/", me.MyActivityView.as_view(), name="trainer-me-activity"),
    path("trainers/me/devices/", me.MyDevicesView.as_view(), name="trainer-me-devices"),
    path("trainers/me/notifications/", me.MyNotificationsView.as_view(), name="trainer-me-notifications"),
    *router.urls,
]
