from django.urls import path
from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("trainers", views.TrainerViewSet, basename="trainer")
router.register(r"trainers/(?P<trainer_pk>me|[0-9a-f-]+)/documents", views.TrainerDocumentViewSet,
                basename="trainer-document")
router.register("access-requests", views.AccessRequestViewSet, basename="access-request")

urlpatterns = [
    path("trainers/me/", views.TrainerMeView.as_view(), name="trainer-me"),
    path("trainers/me/visibility/", views.TrainerMeVisibilityView.as_view(), name="trainer-me-visibility"),
    *router.urls,
]
