from rest_framework.permissions import BasePermission

from .models import AccountStatus


class IsActiveAccount(BasePermission):
    """Default for every endpoint: a pending / paused / rejected account can only reach
    the views that set `allow_inactive_account = True` (me, status, logout)."""

    message = "Your account is not active yet."

    def has_permission(self, request, view):
        user = request.user
        if not (user and user.is_authenticated):
            return False
        if getattr(view, "allow_inactive_account", False):
            return True
        if user.status == AccountStatus.ACTIVE and user.is_active:
            return True
        self.message = {
            AccountStatus.PENDING: "Your account is waiting for approval.",
            AccountStatus.PAUSED: "Your account is paused. Talk to your coach.",
            AccountStatus.REJECTED: "Your sign-up was not approved.",
            AccountStatus.DEACTIVATED: "Your account was turned off by the gym.",
        }.get(user.status, self.message)
        return False
