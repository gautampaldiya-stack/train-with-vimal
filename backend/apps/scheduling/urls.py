from django.urls import path
from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("sessions", views.SessionViewSet, basename="session")

urlpatterns = [
    path("availability/", views.AvailabilityView.as_view(), name="availability"),
    path("me/sessions/", views.MySessionsView.as_view(), name="my-sessions"),
    *router.urls,
]
