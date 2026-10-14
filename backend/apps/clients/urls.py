from django.urls import path
from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("clients", views.ClientViewSet, basename="client")
router.register(r"clients/(?P<client_pk>[0-9a-f-]+)/notes", views.ClientNoteViewSet, basename="client-note")
router.register("invite-links", views.InviteLinkViewSet, basename="invite-link")
router.register("approvals", views.ApprovalViewSet, basename="approval")

urlpatterns = [
    path("join/<str:code>/", views.JoinLinkView.as_view(), name="join-link"),
    path("me/onboarding/", views.MyOnboardingView.as_view(), name="my-onboarding"),
    path("me/trainer/", views.MyTrainerView.as_view(), name="my-trainer"),
    *router.urls,
]
