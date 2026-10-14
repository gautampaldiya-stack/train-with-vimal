from datetime import timedelta

import django_filters
from django.contrib.auth import get_user_model
from django.db.models import Q
from django.utils import timezone

from apps.accounts.models import AccountStatus

User = get_user_model()


class ClientFilter(django_filters.FilterSet):
    tab = django_filters.CharFilter(method="filter_tab")  # all | active | pending | paused | at_risk | no_trainer
    trainer = django_filters.CharFilter(method="filter_trainer")  # uuid | none
    goal = django_filters.CharFilter(field_name="client_profile__goal")
    onboarding = django_filters.CharFilter(method="filter_onboarding")  # done | not_started | in_progress
    joined = django_filters.CharFilter(method="filter_joined")  # 30d | year
    next_checkin = django_filters.CharFilter(method="filter_next_checkin")  # overdue

    class Meta:
        model = User
        fields = []

    def filter_tab(self, qs, name, v):
        if v == "active":
            return qs.filter(status=AccountStatus.ACTIVE)
        if v in ("pending", "paused"):
            return qs.filter(status=v)
        if v == "at_risk":
            return qs.filter(status=AccountStatus.ACTIVE, client_profile__at_risk=True)
        if v == "no_trainer":
            return qs.filter(client_profile__trainer__isnull=True)
        return qs

    def filter_trainer(self, qs, name, v):
        if v == "none":
            return qs.filter(client_profile__trainer__isnull=True)
        return qs.filter(client_profile__trainer_id=v)

    def filter_onboarding(self, qs, name, v):
        if v == "done":
            return qs.filter(client_profile__onboarding_done__contains=["account", "basics", "goal_body", "health",
                                                                        "food"])
        if v == "not_started":
            return qs.filter(Q(client_profile__onboarding_done=[]) | Q(client_profile__onboarding_done=["account"]))
        if v == "in_progress":
            return qs.exclude(client_profile__onboarding_done__contains=["account", "basics", "goal_body", "health",
                                                                         "food"]).exclude(
                Q(client_profile__onboarding_done=[]) | Q(client_profile__onboarding_done=["account"]))
        return qs

    def filter_joined(self, qs, name, v):
        now = timezone.now()
        if v == "30d":
            return qs.filter(date_joined__gte=now - timedelta(days=30))
        if v == "year":
            return qs.filter(date_joined__year=now.year)
        return qs

    def filter_next_checkin(self, qs, name, v):
        if v == "overdue":
            from apps.checkins.models import Submission

            week_ago = timezone.localdate() - timedelta(days=8)
            recent = Submission.objects.filter(form_type="weekly", date__gte=week_ago).values("client_id")
            return qs.exclude(id__in=recent)
        return qs
