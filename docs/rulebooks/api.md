# Rulebook — API

- Base path `/api/v1/`. Docs at `/api/docs/` (drf-spectacular).
- Auth: `POST auth/login/` `{identifier, password}` → `{access, refresh, user}`. Send `Authorization: Bearer <access>`.
- Staff routes use resource names (`clients/`, `programs/`); client routes start with `me/` (`me/home/`, `me/food/`).
- Lists: `?page=`, `?page_size=` (max 100), `?search=`, `?ordering=`, plus filters per screen.
- Errors: `{"error": {"code": "validation_error", "message": "...", "fields": {"name": ["..."]}}}`.
- Wrong or foreign id → 404, not 403 (do not leak that it exists).
- Deletes are soft where the screen offers Undo; `POST .../restore/` brings it back.
- Writes from the client app: header `Idempotency-Key: <uuid>`; optional `date` / `logged_at` for offline logs.
- Realtime: `ws/notifications/?token=<access>`; events `notification`, `client_activity`, `badge`.
