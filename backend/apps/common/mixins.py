from django.db import transaction
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.response import Response


class SoftDeleteViewMixin:
    """DELETE hides the row; POST {id}/restore/ brings it back (the toast Undo)."""

    def perform_destroy(self, instance):
        instance.soft_delete()

    def restore_queryset(self):
        """Rows Undo may bring back; nested views narrow it to their parent (e.g. one client's notes)."""
        return self.get_queryset().model.all_objects.all()

    @action(detail=True, methods=["post"])
    def restore(self, request, pk=None, **kwargs):
        obj = self.restore_queryset().filter(pk=pk, deleted_at__isnull=False).first()
        if obj is None:
            return Response({"error": {"code": "not_found", "message": "Nothing to restore."}}, status=404)
        self.check_object_permissions(request, obj)
        obj.restore()
        return Response(self.get_serializer(obj).data, status=status.HTTP_200_OK)


class AtomicMixin:
    @transaction.atomic
    def dispatch(self, request, *args, **kwargs):
        return super().dispatch(request, *args, **kwargs)
