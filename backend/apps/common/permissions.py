"""Role checks. Object-level scoping (a trainer only sees their own clients) lives in
each view's get_queryset, so a wrong id returns 404 instead of leaking that it exists."""
from rest_framework.permissions import SAFE_METHODS, BasePermission


class IsAdmin(BasePermission):
    message = "Only the gym admin can do this."

    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated and request.user.is_admin)


class IsTrainer(BasePermission):
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated and request.user.is_trainer)


class IsClient(BasePermission):
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated and request.user.is_client)


class IsStaff(BasePermission):
    """Admin or trainer."""

    message = "Only the gym team can do this."

    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated and request.user.is_staff_member)


class IsStaffOrReadOnly(BasePermission):
    def has_permission(self, request, view):
        if not (request.user and request.user.is_authenticated):
            return False
        return request.method in SAFE_METHODS or request.user.is_staff_member


class HasTrainerPermission(BasePermission):
    """Admin always passes. A trainer passes only if their access includes `required_permission`
    (set on the view, or per action via `required_permissions = {"create": "programs.edit"}`)."""

    message = "Your access does not include this. Ask Vimal for more access."

    def has_permission(self, request, view):
        user = request.user
        if not (user and user.is_authenticated):
            return False
        if user.is_admin:
            return True
        if not user.is_trainer:
            return False
        perms = getattr(view, "required_permissions", {}) or {}
        needed = perms.get(getattr(view, "action", None)) or perms.get(request.method) or getattr(
            view, "required_permission", None
        )
        if needed is None:
            return True
        return user.trainer_profile.has_perm(needed)
