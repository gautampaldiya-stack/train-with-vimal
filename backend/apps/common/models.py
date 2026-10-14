"""Base models every table builds on.

- UUID primary keys (safe to expose, no guessable ids).
- created_at / updated_at on every row, indexed for "newest first" lists.
- SoftDeleteModel for anything the design lets you Undo after delete.
"""
import uuid

from django.db import models
from django.utils import timezone


class TimeStampedModel(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    created_at = models.DateTimeField(default=timezone.now, db_index=True, editable=False)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True
        ordering = ["-created_at"]


class SoftDeleteQuerySet(models.QuerySet):
    def alive(self):
        return self.filter(deleted_at__isnull=True)

    def dead(self):
        return self.filter(deleted_at__isnull=False)


class AliveManager(models.Manager.from_queryset(SoftDeleteQuerySet)):
    def get_queryset(self):
        return super().get_queryset().filter(deleted_at__isnull=True)


class SoftDeleteModel(TimeStampedModel):
    """Rows are hidden, not removed, so the toast "Undo" can bring them back.

    A periodic task purges rows deleted more than `PURGE_AFTER_DAYS` ago.
    """

    deleted_at = models.DateTimeField(null=True, blank=True, db_index=True)

    objects = AliveManager()
    all_objects = models.Manager.from_queryset(SoftDeleteQuerySet)()

    class Meta:
        abstract = True

    def soft_delete(self):
        self.deleted_at = timezone.now()
        self.save(update_fields=["deleted_at", "updated_at"])

    def restore(self):
        self.deleted_at = None
        self.save(update_fields=["deleted_at", "updated_at"])


class IdempotencyRecord(models.Model):
    """First response to a write sent with an `Idempotency-Key` header.

    The app logs things offline and replays them when the network is back; a replay (or a retry after a
    timeout) gets this stored response instead of doing the write twice. Kept for 14 days.
    """

    key = models.CharField(max_length=80)
    user_id = models.UUIDField()
    method = models.CharField(max_length=8)
    path = models.CharField(max_length=300)
    status_code = models.PositiveSmallIntegerField()
    body = models.BinaryField()
    content_type = models.CharField(max_length=100, default="application/json")
    created_at = models.DateTimeField(default=timezone.now, db_index=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["user_id", "key"], name="uniq_idempotency_key")]
