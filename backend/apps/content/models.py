import uuid

from django.conf import settings
from django.db import models

from apps.common.models import SoftDeleteModel, TimeStampedModel


class Category(TimeStampedModel):
    name = models.CharField(max_length=60, unique=True)
    order = models.PositiveSmallIntegerField(default=0)

    class Meta:
        ordering = ["order", "name"]
        verbose_name_plural = "categories"


def content_path(instance, filename):
    ext = filename.rsplit(".", 1)[-1].lower()
    return f"content/{instance.kind}/{uuid.uuid4().hex}.{ext}"


class ContentItem(SoftDeleteModel):
    class Kind(models.TextChoices):
        VIDEO = "video", "Video"
        ARTICLE = "article", "Article"
        PDF = "pdf", "PDF"
        IMAGE = "image", "Image"

    kind = models.CharField(max_length=8, choices=Kind.choices, db_index=True)
    title = models.CharField(max_length=140)
    category = models.ForeignKey(Category, null=True, blank=True, on_delete=models.SET_NULL, related_name="items")
    description = models.CharField(max_length=300, blank=True, default="")
    file = models.FileField(upload_to=content_path, null=True, blank=True)
    youtube_url = models.URLField(blank=True, default="")
    cover = models.ImageField(upload_to="content/covers/", null=True, blank=True)
    body = models.TextField(blank=True, default="", max_length=50000)  # article
    read_minutes = models.PositiveSmallIntegerField(null=True, blank=True)
    duration_seconds = models.PositiveIntegerField(null=True, blank=True)
    pages = models.PositiveSmallIntegerField(null=True, blank=True)
    file_size = models.PositiveBigIntegerField(null=True, blank=True)
    resolution = models.CharField(max_length=20, blank=True, default="")
    share_everyone = models.BooleanField(default=False)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return self.title


class ContentShare(models.Model):
    item = models.ForeignKey(ContentItem, on_delete=models.CASCADE, related_name="shares")
    client = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="shared_content")
    shared_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["item", "client"], name="uniq_content_share")]


class ContentView(models.Model):
    """Opened / finished stats, and the client's "New" / "Done" / "Saved" pills."""

    item = models.ForeignKey(ContentItem, on_delete=models.CASCADE, related_name="views")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+")
    opened_at = models.DateTimeField(auto_now_add=True)
    finished = models.BooleanField(default=False)
    saved = models.BooleanField(default=False)
    progress = models.PositiveSmallIntegerField(default=0)  # percent

    class Meta:
        constraints = [models.UniqueConstraint(fields=["item", "user"], name="uniq_content_view")]
