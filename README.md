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

## Push notifications on your PC (Firebase, D-56)
Without these steps everything works except phone / browser push (in-app and live notifications still work).

**1. App keys → `app/firebase.json`** (not in git). Copy `app/firebase.example.json` to `app/firebase.json` and fill:

| Key | Where in Firebase console (Project settings) |
|---|---|
| `FB_PROJECT_ID` | General → Project ID |
| `FB_SENDER_ID` | Cloud Messaging → Sender ID (same as `messagingSenderId`) |
| `FB_WEB_API_KEY`, `FB_WEB_APP_ID`, `FB_AUTH_DOMAIN`, `FB_STORAGE_BUCKET` | General → Your apps → **Train With Vimal Web** → SDK setup and configuration → **Config**: `apiKey`, `appId`, `authDomain`, `storageBucket` |
| `FB_VAPID_KEY` | Cloud Messaging → Web Push certificates → Key pair (Generate key pair once) |
| `FB_ANDROID_API_KEY`, `FB_ANDROID_APP_ID` | General → Your apps → **Train With Vimal** (Android) → download `google-services.json`: `client[0].api_key[0].current_key` and `client[0].client_info.mobilesdk_app_id` |
| `FB_IOS_API_KEY`, `FB_IOS_APP_ID` | later (with the Apple developer account): `GoogleService-Info.plist` → `API_KEY`, `GOOGLE_APP_ID` |

Then once (and after every change of `firebase.json`): `cd app && dart run tool/firebase_web.dart`
(writes `app/web/firebase-config.js` for the web push service worker, also not in git).
Run the app with the keys: add `--dart-define-from-file=firebase.json` to `flutter run`, for example
`flutter run -d chrome --dart-define=API_URL=http://localhost:8000 --dart-define-from-file=firebase.json`.

**2. Server key → `backend/secrets/firebase-service-account.json`** (not in git). Firebase → Project settings →
Service accounts → Generate new private key → save the file there with that name. In `backend/.env`:
```
PUSH_PROVIDER=fcm
FCM_PROJECT_ID=<Project ID>
FCM_SERVICE_ACCOUNT_FILE=secrets/firebase-service-account.json
```
Restart the API (and the Celery worker if you run one).

**3. Try it:** log in (web: allow notifications when Chrome asks), close the tab or put the phone app in the
background, then make something that notifies that user (for example the trainer reviews a check-in). The push
opens the right page when tapped.
iPhone push needs the Apple developer account (APNs key) first.

**4. Push not coming? (D-80)** The `flutter run` console says what happened: `Push: this android device is saved for
the logged-in account` = good; `Push off: this build has no Firebase keys` = `--dart-define-from-file=firebase.json`
missing or `firebase.json` is FlutterFire's file. Then send a test straight to that person:
`python manage.py push_test riya@example.com` (Docker: `docker compose exec api python manage.py push_test …`).
It prints the FCM project (must be the same as `FB_PROJECT_ID`), each saved device and FCM's answer.
`FCM_PROJECT_ID` may stay empty: the server then takes `project_id` from the key file.

**Files at a glance (all outside git):**

| File | Where | Made how |
|---|---|---|
| `firebase.json` (FB_* keys) | `app/firebase.json` | copy of `app/firebase.example.json`, filled by hand |
| `firebase-config.js` | `app/web/firebase-config.js` | `cd app && dart run tool/firebase_web.dart` |
| `firebase-service-account.json` | `backend/secrets/` (PC), `~/twv/secrets/` (server) | Firebase → Service accounts → Generate new private key |
| `.env` lines | `backend/.env` | `PUSH_PROVIDER`, `FCM_PROJECT_ID`, `FCM_SERVICE_ACCOUNT_FILE` |

**Ran `flutterfire configure` / `firebase login` before?** This app does not use FlutterFire (no
`firebase_options.dart`, no `google-services.json`, D-56). FlutterFire writes its **own** `app/firebase.json`
(`{"flutter": {...}}`), which replaces the FB_* key file, and then push silently stays off. Clean up:
1. Delete `app/firebase.json` if it starts with `{"flutter"`, then make it again from `app/firebase.example.json`.
2. Delete `app/lib/firebase_options.dart`, `app/android/app/google-services.json`, `app/.firebaserc` if present.
3. `git status` in `app/` must show no change to `android/settings.gradle.kts` or `android/app/build.gradle.kts`
   (FlutterFire adds the `com.google.gms.google-services` plugin there): `git checkout -- android` undoes it.
The Firebase CLI login itself can stay; it is not needed.

## Deploy (server)
One domain, all in Docker, behind CloudPanel; push to `develop` deploys. Steps: [`deploy/README.md`](deploy/README.md).
Site shows **502**? Run `docker compose -f docker-compose.prod.yml restart web` in `~/twv`; the full checklist is in
[`deploy/README.md` → "Site shows 502"](deploy/README.md#site-shows-502-something-went-wrong-502).

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
