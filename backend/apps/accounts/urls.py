from django.urls import path

from . import views
from .models import OneTimeToken

urlpatterns = [
    path("auth/login/", views.LoginView.as_view(), name="login"),
    path("auth/refresh/", views.RefreshView.as_view(), name="token-refresh"),
    path("auth/logout/", views.LogoutView.as_view(), name="logout"),
    path("auth/me/", views.MeView.as_view(), name="me"),
    path("auth/password/change/", views.PasswordChangeView.as_view(), name="password-change"),
    path("auth/password/forgot/", views.ForgotPasswordView.as_view(), name="password-forgot"),
    path("auth/password/reset/check/",
         views.CheckLinkView.as_view(purpose=OneTimeToken.Purpose.PASSWORD_RESET), name="password-reset-check"),
    path("auth/password/reset/", views.ResetPasswordView.as_view(), name="password-reset"),
    path("auth/login-link/check/",
         views.CheckLinkView.as_view(purpose=OneTimeToken.Purpose.LOGIN_LINK), name="login-link-check"),
    path("auth/login-link/accept/", views.AcceptLoginLinkView.as_view(), name="login-link-accept"),
    path("auth/login-link/not-me/", views.LoginLinkNotMeView.as_view(), name="login-link-not-me"),
    path("auth/email/verify/", views.VerifyEmailView.as_view(), name="email-verify"),
    path("auth/email/resend/", views.ResendVerifyEmailView.as_view(), name="email-resend"),
    path("auth/email/change/", views.ChangeEmailView.as_view(), name="email-change"),
    path("auth/email/cancel-change/", views.CancelEmailChangeView.as_view(), name="email-cancel-change"),
    path("auth/sessions/", views.SessionListView.as_view(), name="sessions"),
    path("auth/sessions/logout-others/", views.LogoutOthersView.as_view(), name="sessions-logout-others"),
    path("auth/sessions/<uuid:pk>/", views.SessionLogoutView.as_view(), name="session-logout"),
    path("auth/account/delete/", views.DeleteAccountView.as_view(), name="account-delete"),
]
