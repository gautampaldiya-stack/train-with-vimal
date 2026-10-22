from django.urls import path
from rest_framework.routers import DefaultRouter

from . import client_forms, views

router = DefaultRouter()
router.register("forms", views.FormViewSet, basename="form")
router.register("checkins", views.CheckinReviewViewSet, basename="checkin")
router.register("me/submissions", views.MySubmissionViewSet, basename="my-submission")
router.register("me/weights", views.MyWeightViewSet, basename="my-weight")
router.register("me/measurements", views.MyMeasurementViewSet, basename="my-measurement")

urlpatterns = [
    path("clients/<uuid:client_pk>/forms/", client_forms.ClientFormsView.as_view(), name="client-forms"),
    path("clients/<uuid:client_pk>/forms/duplicate/", client_forms.ClientFormDuplicateView.as_view(),
         name="client-form-duplicate"),
    path("clients/<uuid:client_pk>/forms/<str:key>/", client_forms.ClientFormView.as_view(), name="client-form"),
    path("clients/<uuid:client_pk>/forms/<str:key>/questions/", client_forms.ClientFormQuestionsView.as_view(),
         name="client-form-questions"),
    path("clients/<uuid:client_pk>/forms/<str:key>/<str:act>/", client_forms.ClientFormView.as_view(),
         name="client-form-action"),
    path("clients/<uuid:client_pk>/progress/", views.ClientProgressView.as_view(), name="client-progress"),
    path("clients/<uuid:client_pk>/checkins/", views.ClientCheckinLogView.as_view(), name="client-checkin-log"),
    path("me/checkins/", views.MyCheckinsView.as_view(), name="my-checkins"),
    path("me/forms/<uuid:pk>/", views.MyFormView.as_view(), name="my-form"),
    path("me/progress/", views.MyProgressView.as_view(), name="my-progress"),
    path("me/history/", views.MyHistoryView.as_view(), name="my-history"),
    path("me/photos/", views.MyPhotoView.as_view(), name="my-photos"),
    *router.urls,
]
