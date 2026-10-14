from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("automations", views.AutomationViewSet, basename="automation")
router.register("tasks", views.TaskViewSet, basename="task")

urlpatterns = router.urls
