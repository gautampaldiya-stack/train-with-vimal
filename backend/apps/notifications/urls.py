from django.urls import path
from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("notifications", views.NotificationViewSet, basename="notification")
router.register("message-templates", views.MessageTemplateViewSet, basename="message-template")
router.register("team-alerts", views.TeamAlertSettingViewSet, basename="team-alert")
router.register("gym-news", views.GymNewsViewSet, basename="gym-news")

urlpatterns = [
    path("devices/", views.DeviceTokenView.as_view(), name="device-token"),
    path("me/reminders/", views.ReminderPreferenceView.as_view(), name="reminder-prefs"),
    path("me/staff-notifications/", views.StaffNotificationPreferenceView.as_view(), name="staff-notification-prefs"),
    path("settings/notifications/", views.NotificationSettingsView.as_view(), name="notification-settings"),
    *router.urls,
]
