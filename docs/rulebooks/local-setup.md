# Rulebook — Running locally

Full steps: `../../README.md`.

- **No Docker, no Redis (Windows, Git Bash):** Python 3.12+ and PostgreSQL 16. Set `REDIS_URL=` (empty) in `backend/.env`;
  cache and realtime run in memory and background jobs run straight away. Scheduled reminders need Redis + Celery.
- **With Docker:** `docker compose up --build`, then `seed_demo`.
- Demo data: `python manage.py seed_demo` (password `Demo@1234`).
- Tests: `cd backend && pytest`.
- Flutter: `cd app && flutter run -d chrome --dart-define=API_URL=http://localhost:8000`.
