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

### On a real phone (same wifi as the laptop)
`10.0.2.2` works only inside the Android emulator. A real phone must use the laptop's wifi IP:
1. Find the laptop IP: Windows `ipconfig` → "Wireless LAN adapter Wi-Fi" → IPv4 Address (for example `192.168.1.5`).
2. Start the API so the phone can reach it (listen on every network, not only on the laptop itself):
   `uvicorn config.asgi:application --reload --host 0.0.0.0 --port 8000`
   (or `python manage.py runserver 0.0.0.0:8000`). Dev settings accept any host name, so `ALLOWED_HOSTS` needs no change.
3. Check from the phone's browser: `http://192.168.1.5:8000/api/docs/` should open. If it does not, Windows Firewall is
   blocking it: allow Python on **Private** networks (the pop-up when the server starts), or run once in an admin
   PowerShell: `New-NetFirewallRule -DisplayName "TWV API 8000" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow -Profile Private`.
   The wifi must be set to **Private** network in Windows (Settings → Network → Wi-Fi → Network profile type).
4. Run the app: `flutter run --dart-define=API_URL=http://192.168.1.5:8000`.

Debug and profile builds allow plain `http` to the laptop (`android/app/src/debug|profile/AndroidManifest.xml`);
release builds need `https`. The app compiles against Android SDK 37 because `permission_handler` needs it
(`android/app/build.gradle.kts`); Android Studio downloads SDK Platform 37 the first time if it is missing.

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

`seed_demo` prints fresh demo links at the end (invite link, coach-added login link, verify email, reset password).
Open them in the browser to try those pages. The reset link works for 15 minutes; run `seed_demo` again for new ones.

The web app uses real paths (`/join/AMAN-4821`, `/reset-password?token=…`), so whatever serves `app/build/web`
must send every unknown path to `index.html` (nginx: `try_files $uri /index.html;`). `flutter run -d chrome` does this already.
