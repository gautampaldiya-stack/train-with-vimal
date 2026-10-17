from django.urls import path
from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("foods", views.FoodViewSet, basename="food")
router.register("meal-plans", views.MealPlanViewSet, basename="meal-plan")
router.register("me/food-log", views.MyFoodLogViewSet, basename="my-food-log")
router.register("me/foods", views.MyFoodSearchViewSet, basename="my-foods")
router.register(r"clients/(?P<client_pk>[0-9a-f-]+)/meal-plans", views.ClientMealPlanViewSet, basename="client-meal-plan")

urlpatterns = [
    path("food-picker/", views.FoodPickerView.as_view(), name="food-picker"),
    path("clients/<uuid:client_pk>/food/", views.ClientFoodLogView.as_view(), name="client-food"),
    path("me/food/", views.MyFoodView.as_view(), name="my-food"),
    path("me/food/meals/<int:meal_id>/<str:op>/", views.MyMealActionView.as_view(), name="my-meal-action"),
    path("me/food/items/<int:item_id>/swaps/", views.MySwapOptionsView.as_view(), name="my-swap-options"),
    *router.urls,
]
