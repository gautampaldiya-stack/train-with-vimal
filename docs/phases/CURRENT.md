# Currently doing / next (handoff note)

Updated with every push, so anyone (another Claude session, local Claude Code, a developer) can pick up from here.

**Last updated:** 2026-10-15 · branch `working`

## Done
- Backend complete (all modules, offline sync, seeds, tests). Runs without Docker/Redis.
- Docs split per topic (decisions, rulebooks, prd, phases, architecture).
- Flutter foundation (phase 4): theme tokens, all board icons, shared widgets (`lib/core/widgets`),
  API client with JWT refresh (`lib/core/api`), offline outbox + read cache (`lib/core/offline`),
  realtime socket (`lib/core/realtime`), session (`lib/app/services.dart`), shells (`lib/app/shell`),
  router with role redirect (`lib/app/router.dart`). `flutter analyze` clean, `flutter build web` OK.

## Doing now
- 2026-10-15: completing the login flow (decision D-15). Backend part pushed: link lifetimes from the boards
  (reset 15 min, verify 24 h), invite end reasons, login link "not me", `seed_demo` prints demo links. Next: the
  Flutter pages listed under "Not built yet".
- Phase 5: login + onboarding, code in `app/lib/features/auth/`. Checked in a browser against the boards on phone
  (390) and desktop (1440): welcome, log in, approval wait, all 5 setup steps, checklist, all set. Still to check:
  Need help / Forgot / Terms sheets and the Finish later sheet. Screens: Welcome, Log in (phone hero / desktop split with side panel), Need help sheet,
  Forgot password modal, Terms sheet, Approval wait (`/pending`), Setup steps (`/setup?step=0..4`, `&edit=1` from summary),
  Finish later sheet, Checklist (`/setup/checklist`), All set (`/setup/done`).
- Client-app components live in `app/lib/core/widgets/client.dart` (CaButton, CaField, CaChips, CaSeg, ...).
- Demo logins (password Demo@1234): riya@example.com (all set), isha@example.com (setup not done),
  neha@example.com and karan@example.com (waiting for approval).
- Router: `landingFor(me)` picks /pending, /setup or /home; pending clients can only open /pending and /setup.
  `/setup/checklist` and `/setup/done` are top-level routes (not children of `/setup`).
- Known: realtime socket returns 404 under `manage.py runserver` (needs an ASGI server); approval still shows on
  Check status and when the app comes back to the front.

## Not built yet in this flow (see `docs/screens/status.md`)
- `ClientResetPassword` / `ClientResetPasswordWeb`: page from the forgot-password email link (`/reset/:token`).
- `ClientJoinLink` / `ClientJoinLinkWeb`: page from the invite link (`/join/:code`).
- `ClientVerifyEmail` / `ClientVerifyEmailWeb`: verify email page (`/verify`).
- `ClientPermissions` / `ClientPermissionsWeb`.
- Not browser-checked yet: Need help / Forgot password / Terms / Finish later sheets; desktop setup steps 1, 3–5 and All set.

## Next
0. Finish the boards above first (whole flow rule), then mark them in `docs/screens/status.md`.
1. Client screens, then trainer, then admin (order in `phase-5-screens.md`).
2. Notification centre panel, data table component when first needed.

## How screens plug in
- Signed-in screens: add to `screens` map in `lib/app/router.dart` (`'/clients'`, `'/clients/:id'`).
  Missing ones show a "This page is on the way" holder, so nav never breaks.
- Signed-out screens: `publicScreens` (`'/login'`, `'/reset'`, `'/join'`, ...).
- Run: `cd app && flutter run -d chrome --dart-define=API_URL=http://localhost:8000`.

## How to continue
- Read `CLAUDE.md`, then this file, then the phase file for the current phase.
- For a screen: open `design/screens/<Board>.dc.html` (+ Web/Mobile variant), read its section in `docs/screens/behaviour.md`, build it, tick it in the phase file, update this note, commit as Gautam, push `working`.
