# Train With Vimal

Coaching app for Vimal's gym — admin, trainer and client apps on Android, iOS and web, with a Django backend.

## Folders
- `backend/` — Django API, Celery jobs, realtime (WebSocket)
- `app/` — Flutter app
- `design/screens/` — design canvas (source of truth for the UI)
- `docs/` — PRD, architecture, decisions, rules, phases, memory, screen behaviour

## Run the backend

### With Docker (easiest)
```bash
cp backend/.env.example backend/.env       # then set SECRET_KEY
docker compose up --build
docker compose exec api python manage.py seed_defaults   # built-in exercises, foods, forms, templates…
docker compose exec api python manage.py seed_demo       # demo team + clients from the design
```
API: http://localhost:8000/api/v1/ · API docs: http://localhost:8000/api/docs/ · WebSocket: ws://localhost:8000/ws/notifications/?token=<access>

### Without Docker (Windows, Git Bash)
Needs Python 3.12+ and PostgreSQL 16 (Windows installer from postgresql.org; remember the `postgres` password).
Redis is optional: leave `REDIS_URL` empty and the API runs in one process (realtime works while the app is open;
scheduled reminders need Redis + Celery later).

1. Make the database once (SQL Shell "psql" from the Start menu, log in as `postgres`):
   ```sql
   CREATE USER twv WITH PASSWORD 'twv' CREATEDB;
   CREATE DATABASE twv OWNER twv;
   ```
2. In Git Bash, from the repo folder:
   ```bash
   cd backend
   python -m venv .venv
   source .venv/Scripts/activate
   pip install -r requirements-dev.txt
   cp .env.example .env
   sed -i 's#^REDIS_URL=.*#REDIS_URL=#' .env      # run without Redis
   python manage.py migrate
   python manage.py seed_demo                      # also runs seed_defaults
   uvicorn config.asgi:application --reload        # API + WebSocket on :8000
   ```
3. Open http://localhost:8000/api/docs/ . Next time only: `cd backend && source .venv/Scripts/activate && uvicorn config.asgi:application --reload`.

With Redis (Mac/Linux, or later on Windows): keep `REDIS_URL` set and run `celery -A config worker -l info`
(Windows: add `--pool=solo`) and `celery -A config beat -l info` in two more terminals.

Demo logins (password `Demo@1234` for all): `vimal@trainwithvimal.com` (admin), `aman@trainwithvimal.com` (trainer),
`riya@example.com` (client). Mobile numbers work too.

### Tests
```bash
cd backend && pytest
```

## Run the app
```bash
cd app
flutter pub get
flutter run -d chrome --dart-define=API_URL=http://localhost:8000
flutter run -d emulator-5554 --dart-define=API_URL=http://10.0.2.2:8000   # Android emulator
```

## Branches
`working` (daily work) → `develop` (testing / staging) → `main` (production).


## Flutter app (needs Flutter 3.47+ / Dart 3.13+)
```bash
flutter upgrade            # once, if `flutter --version` shows an older Flutter
cd app
flutter pub get
flutter run -d chrome --web-port 5173 --dart-define=API_URL=http://localhost:8000
```
`--web-port 5173` matches `CORS_ALLOWED_ORIGINS` in `backend/.env`. Demo logins: see `docs/phases/CURRENT.md`.
