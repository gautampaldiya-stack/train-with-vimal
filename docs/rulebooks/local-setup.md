# Rulebook — Running locally

Full steps: `../../README.md`.

- **No Docker, no Redis (Windows, Git Bash):** Python 3.12+ and PostgreSQL 16. Set `REDIS_URL=` (empty) in `backend/.env`;
  cache and realtime run in memory and background jobs run straight away. Scheduled reminders need Redis + Celery.
- **With Docker:** `docker compose up --build`, then `seed_demo`.
- Demo data: `python manage.py seed_demo` (password `Demo@1234`).
- Tests: `cd backend && pytest`. After a pull run `pip install -r requirements.txt` first (new packages, e.g. `pypdfium2` for PDF pages). The test DB is kept between runs (`--reuse-db`) and the demo data is dated from the day it was seeded, so on a new day run `pytest --create-db` once.
- Flutter: `cd app && flutter run -d chrome --dart-define=API_URL=http://localhost:8000`.

## Permissions (camera, photos, notifications)
- The app uses `permission_handler`. Android permissions are in `android/app/src/main/AndroidManifest.xml`,
  iOS usage texts in `ios/Runner/Info.plist`.
- iOS: after the first `pod install`, add the permission macros to `ios/Podfile` `post_install` so iOS asks
  (`PERMISSION_CAMERA=1`, `PERMISSION_PHOTOS=1`, `PERMISSION_NOTIFICATIONS=1`), as the `permission_handler` readme shows.

## Demo links
`python manage.py seed_demo` prints an invite link, a login link (Sana, coach-added), a verify email link (Tara)
and a reset password link (Riya). Set `FRONTEND_URL` to where the app runs so the links point there.
