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

### Without Docker (Windows / Mac / Linux)
Needs Python 3.12+, PostgreSQL 15+ and Redis 7.
```bash
cd backend
python -m venv .venv && .venv\Scripts\activate      # Mac/Linux: source .venv/bin/activate
pip install -r requirements-dev.txt
copy .env.example .env                               # Mac/Linux: cp
python manage.py migrate
python manage.py seed_defaults && python manage.py seed_demo
uvicorn config.asgi:application --reload             # API + WebSocket on :8000
celery -A config worker -l info                      # second terminal (on Windows add: --pool=solo)
celery -A config beat -l info                        # third terminal
```

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
