from django.urls import path
from rest_framework.routers import DefaultRouter

from . import dashboard
from .views import ActivityViewSet

router = DefaultRouter()
router.register("activity", ActivityViewSet, basename="activity")

urlpatterns = [
    path("dashboard/admin/", dashboard.AdminDashboardView.as_view(), name="dashboard-admin"),
    path("dashboard/trainer/", dashboard.TrainerDashboardView.as_view(), name="dashboard-trainer"),
    path("dashboard/trainer/activity/", dashboard.TrainerActivityView.as_view(), name="dashboard-trainer-activity"),
    path("dashboard/dismiss/", dashboard.DismissView.as_view(), name="dashboard-dismiss"),
    path("me/home/", dashboard.ClientHomeView.as_view(), name="my-home"),
    *router.urls,
]
