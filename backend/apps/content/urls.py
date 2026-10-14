from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("content", views.ContentViewSet, basename="content")
router.register("content-categories", views.CategoryViewSet, basename="content-category")
router.register(r"clients/(?P<client_pk>[0-9a-f-]+)/content", views.ClientContentView, basename="client-content")
router.register("me/library", views.MyLibraryViewSet, basename="my-library")

urlpatterns = router.urls
