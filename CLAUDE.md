# Train With Vimal — notes for Claude Code

Read this first, then `docs/memory/README.md` (project memory) and `docs/phases/CURRENT.md` (what is in progress, what is next) before changing anything.

## What this is
A coaching app for one gym (owner: Vimal). Three roles: **Admin** (Vimal, exactly one), **Trainer**, **Client**.
Targets: Android, iOS and web, every screen responsive (phone, tablet, desktop).

- `backend/` — Django 5 + DRF API, PostgreSQL, Celery + Redis (reminders, automations), Channels (realtime).
- `app/` — Flutter app (Riverpod, go_router, dio). One codebase for all three roles.
- `design/screens/` — the design canvas: 104 `*.dc.html` boards + `twv.css` tokens. **The UI must match these
  boards exactly**: every page, button, modal, bottom sheet, dropdown, empty state and toast text.
  Open them with `design/screens/serve.bat` (Windows) or `python design/screens/serve.py`.
  Online copy of the canvas: https://claude.ai/artifact/NKNGUZt9ZJMVXwiKXbfhiK
- `docs/` — the plan. Keep it updated with every piece of work (rule from Gautam).

## Where to read
| Need | File |
|---|---|
| What every screen and button does | `docs/screens/behaviour.md` |
| Which boards are built / missing | `docs/screens/status.md` (rules: `docs/rulebooks/definition-of-done.md`) |
| Colours, type, components | `docs/design.md` |
| Every API endpoint, every table | `docs/architecture/api-endpoints.md`, `docs/architecture/data-model.md` |
| Product scope and roles | `docs/prd/README.md` |
| How the system is built | `docs/architecture/README.md` |
| Why things are the way they are | `docs/decisions/README.md` |
| Rules for code, API, UI | `docs/rules/README.md`, `docs/rulebooks/` |
| What is done / next | `docs/phases/README.md` |
| Decisions and answers from Gautam | `docs/memory/README.md` |
| Change log | `docs/changes.md` |

## Git rules (from Gautam — follow exactly)
- Branches: `working` = all daily work. Merge `working` → `develop` when Gautam wants to test (staging).
  `main` = production, only at the end.
- Commit in meaningful chunks, not every tiny change.
- Author **and** committer = `Gautam <gautampaldiya@gmail.com>`:
  `git -c user.name=Gautam -c user.email=gautampaldiya@gmail.com commit ...`
- **No Claude / Anthropic name anywhere in commits** — no `Co-Authored-By`, no session links.
- Never commit `backend/.env`, keys, or Firebase service-account files.

## Run it
See `README.md`. Short version: `docker compose up --build`, then
`docker compose exec api python manage.py seed_defaults` and `seed_demo`.

## Ground rules
- A flow is done only when every page its buttons, links and emails open is built too. Track each board in
  `docs/screens/status.md`; mark Done only after a browser check on phone and desktop. Name what is not built.
- UI is same-to-same as the canvas. No hard-coded colours outside the theme tokens. Every button does something.
- Client app: clients **log**, they never change their plan.
- Client logging works **offline**: writes go to a local outbox with an `Idempotency-Key` and sync later.
- Every list that can grow is paginated; trainers only ever see their own clients (`visible_clients`).
- Errors use one shape: `{"error": {"code", "message", "fields"}}`.
