# D-55 · From address, packages hidden, app icon + splash, one-domain Docker deploy

**Date:** 2026-10-23 · **Asked by:** Gautam ("ha daal do... from wala integration me ok", "package ... comment kar do",
logos, "api ke liye dusri website banane ki jarurat nahi ... docker use karo ... reverse proxy")

## What was decided
1. **From address in Integrations → Email sending.** The modal has "Sending domain" and "From address" (the part
   before `@`, default `hello`). Saved in `Integration.config.local` (letters, numbers, dots, dashes; lower case).
   Once the domain is verified emails come from `<local>@<domain>` (`Integration.from_email()`). Changing only the
   From address keeps the verification; a new domain starts the DNS check again. Reply-to stays in
   Emails & alerts → Sender.
2. **Packages are not used.** Gautam: no need. Hidden everywhere, kept in code as comments so it can come back:
   - `HIDDEN_TRIGGERS = {"package_ending"}`: the trigger is left out of the catalog, its starter (Renewal reminder)
     is hidden, automations with it are not listed or counted, and the engine never runs them.
   - Message templates in the Packages group (Renewal reminder) are not listed.
   - App: the Package trigger, the builder's Who → Package field, the `{{package_name}}` variable and the Packages
     tab in Emails are commented out.
   - Client invite text no longer names the package (migration `notifications/0006`).
   - The client profile never showed a package; `package_name` / `package_ends_on` stay in the database unused.
3. **App icon and splash** from Gautam's logo (`app/assets/brand/`), made with `flutter_launcher_icons` and
   `flutter_native_splash` (white background, Android 12 splash, adaptive icon, web icons and favicon).
4. **Deploy: one domain, everything in Docker.** `https://twv.prowavetech.in` is a CloudPanel Reverse Proxy site
   (SSL) → `127.0.0.1:8080` → the `web` nginx container. nginx sends `/api`, `/ws`, `/media`, `/static`,
   `/django-admin`, `/health` to the `api` container and serves the Flutter web build for everything else. No
   second site for the API. Containers: web, api (uvicorn), worker, beat, db, redis (`docker-compose.prod.yml`).
   Uploads are served by Django when `SERVE_MEDIA=True` (one VPS, no S3).
5. **CI/CD.** Every push to `develop` runs `.github/workflows/deploy-develop.yml`: tests (pytest + flutter analyze),
   then build web, rsync to the VPS and `docker compose up -d --build`, then a health check. Needs GitHub secrets
   `VPS_HOST`, `VPS_PORT`, `VPS_USER`, `VPS_SSH_KEY`; until they exist the deploy job skips itself with a
   warning. App folder = `~/twv` of the SSH user, written in the workflow (`APP_DIR: twv`); Gautam deploys as root (like his
   probid_v2), so `/root/twv`. The first deploy makes it, Gautam only makes `backend/.env` and puts the Firebase file in `secrets/`. Steps: `deploy/README.md`.
6. **App id `com.trainwithvimal.app`** (was `com.trainwithvimal.twv`) on Android and iOS, to match the Firebase
   apps Gautam already made.
7. **Firebase.** Server side is ready (`PUSH_PROVIDER=fcm`). The app does not register for push yet; it is wired
   once Gautam creates the Firebase project and shares the app config files. WhatsApp later.

## Why
Gautam's 23 Oct message: From address in Integrations, packages not needed, his 500 x 500 logos, and a deploy with
no extra steps after setup on one domain.

## Checked
Full prod stack built and ran in Docker locally (app, API, Django admin, static, uploads, WebSocket through nginx).
pytest green, `flutter analyze lib` clean.
