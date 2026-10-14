from django.urls import path

from . import views

urlpatterns = [
    path("gym/", views.PublicGymView.as_view(), name="gym-public"),
    path("settings/gym/", views.GymProfileView.as_view(), name="gym-profile"),
    path("settings/branding/", views.BrandingView.as_view(), name="branding"),
    path("settings/branding/apply/", views.BrandingApplyView.as_view(), name="branding-apply"),
    path("settings/branding/reset/", views.BrandingResetView.as_view(), name="branding-reset"),
    path("settings/branding/logo/", views.LogoView.as_view(), name="branding-logo"),
    path("settings/roles/", views.RoleMatrixView.as_view(), name="role-matrix"),
    path("settings/integrations/", views.IntegrationListView.as_view(), name="integrations"),
    path("settings/integrations/<str:kind>/<str:op>/", views.IntegrationActionView.as_view(), name="integration-action"),
]
