from django.urls import path
from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("forms", views.FormViewSet, basename="form")
router.register("checkins", views.CheckinReviewViewSet, basename="checkin")
router.register("me/submissions", views.MySubmissionViewSet, basename="my-submission")
router.register("me/weights", views.MyWeightViewSet, basename="my-weight")
router.register("me/measurements", views.MyMeasurementViewSet, basename="my-measurement")

urlpatterns = [
    path("clients/<uuid:client_pk>/forms/", views.ClientFormsView.as_view(), name="client-forms"),
    path("clients/<uuid:client_pk>/progress/", views.ClientProgressView.as_view(), name="client-progress"),
    path("me/checkins/", views.MyCheckinsView.as_view(), name="my-checkins"),
    path("me/progress/", views.MyProgressView.as_view(), name="my-progress"),
    path("me/photos/", views.MyPhotoView.as_view(), name="my-photos"),
    *router.urls,
]
