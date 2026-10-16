"""The one "check-ins to review" list. The trainer dashboard, the Check-ins page, its counts, the nav badge and
the admin's Trainers table all count from here, so the numbers agree everywhere."""
from django.db.models import Q

from apps.clients.services import visible_clients

REVIEW_TYPES = ["weekly", "daily", "survey"]


def allowed_types(user):
    """Form types this person may open. A trainer needs the daily / weekly check-in permission for those."""
    if not getattr(user, "is_trainer", False):
        return None
    tp = user.trainer_profile
    return [t for t, key in (("daily", "checkins.daily"), ("weekly", "checkins.weekly")) if tp.has_perm(key)] + [
        "survey", "onboarding", "waiver"]


def staff_submissions(user):
    from .models import Submission

    qs = Submission.objects.filter(client__in=visible_clients(user))
    types = allowed_types(user)
    return qs.filter(form_type__in=types) if types is not None else qs


def review_queue(user):
    """Waiting for a reply: weekly, daily and monthly check-ins nobody has reviewed yet."""
    return staff_submissions(user).filter(reviewed_at__isnull=True, form_type__in=REVIEW_TYPES)


# Same rule for the admin's Trainers table, counted per coach.
WAITING = Q(coached_clients__user__submissions__reviewed_at__isnull=True,
            coached_clients__user__submissions__form_type__in=REVIEW_TYPES,
            coached_clients__removed_at__isnull=True)
