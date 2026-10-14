from datetime import timedelta

import django_filters
from django.utils import timezone

from .models import ActivityEvent

RANGES = {"today": 0, "7d": 7, "30d": 30, "3m": 92}


class ActivityFilter(django_filters.FilterSet):
    range = django_filters.CharFilter(method="filter_range")  # today | 7d | 30d | 3m | all
    who = django_filters.CharFilter(method="filter_who")  # team | clients | automations
    person = django_filters.UUIDFilter(field_name="actor_id")
    kind = django_filters.CharFilter(field_name="kind")
    client = django_filters.UUIDFilter(field_name="client_id")
    trainer = django_filters.UUIDFilter(field_name="trainer_id")
    since = django_filters.DateTimeFilter(field_name="created_at", lookup_expr="gte")
    until = django_filters.DateTimeFilter(field_name="created_at", lookup_expr="lte")

    class Meta:
        model = ActivityEvent
        fields = []

    def filter_range(self, qs, name, value):
        if value not in RANGES:
            return qs
        now = timezone.localtime()
        if value == "today":
            start = now.replace(hour=0, minute=0, second=0, microsecond=0)
        else:
            start = now - timedelta(days=RANGES[value])
        return qs.filter(created_at__gte=start)

    def filter_who(self, qs, name, value):
        mapping = {"team": "team", "clients": "client", "automations": "automation"}
        return qs.filter(actor_type=mapping[value]) if value in mapping else qs
