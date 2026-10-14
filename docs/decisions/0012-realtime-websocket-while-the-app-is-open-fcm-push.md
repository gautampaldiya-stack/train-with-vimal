# D-12 · Realtime: WebSocket while the app is open, FCM push when closed

- **Date:** 2026-10-14
- **Status:** Accepted

## Decision
While the app is open, notifications arrive over WebSocket. When it is closed, Firebase Cloud Messaging (FCM) delivers push on Android, iOS and web. Firebase is used only for push.

## Why
Works on mobile and web.
