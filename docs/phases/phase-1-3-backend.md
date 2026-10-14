# Phases 1–3 · Backend — Done (2026-10-14)

## Phase 1 — Foundation
- [x] Custom User (email or mobile login), argon2, JWT with server sessions (`sid` claim), refresh rotation, logout one/all
- [x] Roles (admin, trainer, client), statuses, `visible_clients()` scoping, permission catalog
- [x] Error shape `{"error": {code, message, fields}}`, request ids, throttles
- [x] Gym settings, branding, role matrix, integrations
- [x] Notifications: in-app, realtime (Channels), push (FCM, console in dev), email templates, preferences

## Phase 2 — Modules
- [x] Team: trainers, access, visibility card, documents, access requests, deactivate with client move
- [x] Clients: profile, invite links, approvals, info requests, notes/flags, metrics (adherence, at-risk)
- [x] Training: exercises, programs (tree sync), assign, customise per client, workouts + sets with PRs
- [x] Nutrition: foods + units + swaps, Excel import/undo, meal plans (tree sync), publish, client day view, food log, water
- [x] Check-ins: forms + builder, submissions, review, weight, measurements, photos
- [x] Habits & supplements, content library, scheduling (clash check), automations engine, dashboards

## Phase 3 — Offline, jobs, data
- [x] `Idempotency-Key` middleware (replay, 409 on other path, 14-day purge)
- [x] Back-dated logs (`sync_day`/`sync_time`, 7 days), `/me/workouts/sync/`
- [x] Celery beat reminders and nightly jobs
- [x] `seed_defaults`, `seed_demo`
- [x] pytest suite (auth, scoping, offline sync)
- [x] Run without Docker/Redis for local testing
