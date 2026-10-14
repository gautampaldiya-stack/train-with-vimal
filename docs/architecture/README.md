# Architecture

More detail: [api-endpoints.md](api-endpoints.md) (every endpoint) · [data-model.md](data-model.md) (every table and field).
Both are generated: `cd backend && PYTHONPATH=. python scripts/gen_docs.py`.

```
Flutter app (Android / iOS / web)
   │  HTTPS JSON  /api/v1/...        WebSocket /ws/notifications/?token=<access>
   ▼                                  ▼
Django 5 + DRF (uvicorn, ASGI) ── Channels ── Redis
   │                                  ▲
   ├── PostgreSQL (all data)          │ group_send
   └── Celery worker + beat ──────────┘  reminders, automations, nightly stats, FCM push, email
```

## Backend apps (`backend/apps/`)
| App | Owns |
|---|---|
| accounts | User (email/mobile login), sessions, one-time tokens (reset, invite, verify) |
| gym | Gym settings, branding, role matrix, integrations |
| trainers | Trainer profile, access, visibility card, documents, access requests |
| clients | Client profile, invite links, approvals, notes, metrics (adherence, at-risk) |
| training | Exercises, programs (week/day/exercise tree), assignments, workout + set logs |
| nutrition | Foods + units + swaps, meal plans (meal/option/item tree), day state, food log, water, Excel import |
| checkins | Forms + questions, submissions, review, weight, measurements, photos |
| habits | Habits, supplement plans, logs |
| content | Library items, categories, shares, views |
| scheduling | Sessions, availability |
| automations | Automations, steps, runs (engine), trainer tasks |
| notifications | Notifications, templates, preferences, devices (FCM), reminders (Celery beat) |
| activity | Activity log, dashboards |
| common | Base models (UUID, soft delete), error handler, idempotency, pagination, utils, seeds |

## Key patterns
- **Base models**: `TimeStampedModel` (UUID pk), `SoftDeleteModel` (`deleted_at`, `restore()` for Undo). Tree rows use int ids.
- **Scoping**: `visible_clients(user)` is the only way to reach client data. Wrong or foreign id → 404.
- **Permissions**: `IsAdmin`, `IsClient`, `HasTrainerPermission` + `required_permissions` (keys in `trainers/permissions_catalog`).
- **Tree editors** (program, meal plan, form questions, supplement items, automation steps): one PUT sends the whole tree;
  rows with an id are updated in place so logs stay linked. Undo = PUT the previous tree.
- **Errors**: always `{"error": {"code", "message", "fields"}}`.
- **Idempotency**: `Idempotency-Key` header on any write → first 2xx response stored per user+key and replayed
  (`Idempotent-Replay: true`). Same key on another path → 409. Kept 14 days.
- **Offline dates**: `sync_day` / `sync_time` accept a client's own date/time up to 7 days back.
- **Realtime**: `notify()` writes a Notification, pushes it to the user's Channels group, and sends FCM if they are offline.
- **Automations**: events call `fire_event`; polled triggers every 15 min; wait steps park a run with `next_run_at`;
  `process_due_runs` every minute; dedupe constraint stops double starts.
- **Reminders**: Celery beat every 15 min, user's local time, `ReminderLog.once()` stops repeats.

## Flutter app (`app/`)
Riverpod + go_router + dio. `lib/core` (theme tokens from `twv.css`, api client, outbox, realtime), `lib/features/<area>`,
one router with role-based shells: sidebar on desktop, rail on tablet, bottom nav on phone.
Offline: reads cached locally; writes go to an outbox (with `Idempotency-Key` + local timestamp) and replay on reconnect.
