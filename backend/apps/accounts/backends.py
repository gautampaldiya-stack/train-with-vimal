from django.contrib.auth.backends import ModelBackend
from django.db.models import Q

from apps.common.validators import normalize_phone

from .models import User


class EmailOrPhoneBackend(ModelBackend):
    """Log in with email or mobile number + password."""

    def authenticate(self, request, username=None, password=None, **kwargs):
        identifier = (username or kwargs.get("email") or kwargs.get("identifier") or "").strip()
        if not identifier or not password:
            return None
        if "@" in identifier:
            q = Q(email__iexact=identifier)
        else:
            q = Q(phone=normalize_phone(identifier))
        user = User.objects.filter(q).first()
        if user is None:
            User().set_password(password)  # same timing whether or not the user exists
            return None
        if user.check_password(password) and self.user_can_authenticate(user):
            return user
        return None
