from django.urls import path
from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("exercises", views.ExerciseViewSet, basename="exercise")
router.register("programs", views.ProgramViewSet, basename="program")
router.register(r"clients/(?P<client_pk>[0-9a-f-]+)/programs", views.ClientProgramViewSet,
                basename="client-program")
router.register(r"clients/(?P<client_pk>[0-9a-f-]+)/workouts", views.ClientWorkoutLogViewSet,
                basename="client-workout")
router.register("me/workouts", views.MyWorkoutViewSet, basename="my-workout")

urlpatterns = [
    path("exercise-picker/", views.ExercisePickerView.as_view(), name="exercise-picker"),
    path("me/train/", views.MyTrainView.as_view(), name="my-train"),
    *router.urls,
]
