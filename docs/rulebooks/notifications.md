# Rulebook — Notifications

- Always go through `apps.notifications.notify(...)` — it saves the in-app row, sends realtime (WebSocket), then push (FCM) and email per the user's preferences.
- Message text lives in templates (`notifications/defaults.py`), editable on Emails & alerts.
- Reminders run from Celery beat every 15 minutes in the user's local time; `ReminderLog.once()` stops repeats.
- Firebase is used only for push. Keys go in `backend/.env` (`PUSH_PROVIDER=fcm`, `FCM_PROJECT_ID`, `FCM_SERVICE_ACCOUNT_FILE`).
