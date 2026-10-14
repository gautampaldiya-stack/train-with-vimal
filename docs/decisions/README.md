# Decisions

Newest at the bottom. Format: what, why, date.

| # | Decision | Why | Date |
|---|---|---|---|
| D-01 | Flutter for Android, iOS and web | One codebase, matches design system | 2026-10-14 |
| D-02 | Django + DRF + PostgreSQL + Celery/Redis + Channels | Strong validation, admin, heavy data, background jobs, realtime | 2026-10-14 |
| D-03 | Login with email **or** mobile, password always | Gautam's answer | 2026-10-14 |
| D-04 | Outbound: email + in-app + push + realtime now; WhatsApp/SMS later via `.env` | Keys not ready | 2026-10-14 |
| D-05 | No independent coaches / SaaS | Single gym product | 2026-10-14 |
| D-06 | Client Food tab = combined `ClientMealNutrition` page; old ClientFood/ClientNutrition not built; ClientFoodLog stays | Less duplication | 2026-10-14 |
| D-07 | Client logging is offline-first (outbox + `Idempotency-Key`, server accepts back-dated logs up to 7 days) | Bad network on the gym floor; logs must never be lost or doubled | 2026-10-14 |
| D-08 | Data stored in full detail, as the screens show (snapshots of names/macros on logs, set-level workout data) | Gautam: "data details me rakhna hai" | 2026-10-14 |
| D-09 | Tree editors save the whole tree, update rows by id | Logs stay linked when a plan changes; easy Undo | 2026-10-14 |
| D-10 | Questions that already have answers are hidden (`is_removed`), never deleted | Old submissions stay readable | 2026-10-14 |
| D-11 | Every screen responsive (phone, tablet, desktop) | Gautam's rule | 2026-10-14 |
| D-12 | Realtime: WebSocket while the app is open, FCM push when closed | Works on mobile and web | 2026-10-14 |
| D-13 | Branches `working` → `develop` → `main`; commits by Gautam only | Gautam's rule | 2026-10-14 |
