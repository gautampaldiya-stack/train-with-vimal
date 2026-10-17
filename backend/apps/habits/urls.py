from django.urls import path
from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("habits", views.HabitViewSet, basename="habit")
router.register("supplement-plans", views.SupplementPlanViewSet, basename="supplement-plan")
router.register(r"clients/(?P<client_pk>[0-9a-f-]+)/supplement-plans", views.ClientSupplementPlansViewSet,
                basename="client-supplement-plan")
router.register(r"clients/(?P<client_pk>[0-9a-f-]+)/habit-plan", views.ClientHabitPlansViewSet,
                basename="client-habit-plan")

urlpatterns = [
    path("clients/<uuid:client_pk>/habits/", views.ClientHabitsView.as_view(), name="client-habits"),
    path("me/habits/", views.MyHabitsView.as_view(), name="my-habits"),
    path("me/habits/<uuid:habit_id>/log/", views.MyHabitLogView.as_view(), name="my-habit-log"),
    path("me/supplements/<int:item_id>/", views.MySupplementView.as_view(), name="my-supplement"),
    *router.urls,
]
