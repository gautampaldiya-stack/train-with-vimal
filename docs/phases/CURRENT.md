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
- 2026-10-15: login flow complete (decision D-15). Code in `app/lib/features/auth/`. Browser-checked on phone (390)
  and desktop (1440) against the boards:
  - Intro slides (phone, first open only), Welcome, Log in, Need help sheet.
  - Forgot password page `/forgot` (no-account error, "Check your email", resend after 30 s).
  - Reset link page `/reset-password?token=` (strength bars, rules, Password updated, Link not valid).
  - Invite page `/join/:code` (invite, form errors, account created, broken link: expired / off / full / invalid).
  - Login link page `/start?token=` (Change email, Need help, "Details not right?" sheets).
  - Verify email `/verify` and `/verify-email?token=` (inbox, resend, change email, verified, link not valid).
  - Permissions `/permissions?kind=notifications|camera|photos&next=` (ask, allowed, blocked).
  - Approval wait, setup steps incl. the new health conditions + doctor's OK, checklist.
- Web uses path URLs (`usePathUrlStrategy`): the web server must fall back to `index.html` for unknown paths.
- Client-app components: `app/lib/core/widgets/client.dart`; auth-only pieces: `features/auth/account_widgets.dart`.
- Demo logins (password Demo@1234): riya@example.com (all set), isha@example.com (setup not done),
  neha@example.com and karan@example.com (waiting for approval), tara@example.com (email not verified).
  Sana has a login link and `AMAN-4821` is an invite code; `seed_demo` prints the demo links.
- Router: `landingFor(me)` picks /verify, /pending, /setup or /home. Link pages (`/reset-password`, `/join`,
  `/start`, `/verify-email`) open signed in or out; `/login` and `/forgot` send a signed-in person on.
- Known: realtime socket returns 404 under `manage.py runserver` (needs an ASGI server); the gym phone is empty
  in the seed so the support card shows email only.

## Not finished in this flow (see `docs/screens/status.md`)
- `ClientLogin` / `ClientLoginWeb` (Partial): Terms sheet and Finish later sheet not browser-checked.
- `ClientWelcome` (Partial): not checked on its own.
- Desktop setup steps 1, 3, 5 and All set not browser-checked.

## Next
0. Check the three Partial boards above, then mark them Done in `docs/screens/status.md`.
1. Client screens, then trainer, then admin (order in `phase-5-screens.md`).
2. Notification centre panel, data table component when first needed.

## How screens plug in
- Signed-in screens: add to `screens` map in `lib/app/router.dart` (`'/clients'`, `'/clients/:id'`).
  Missing ones show a "This page is on the way" holder, so nav never breaks.
- Signed-out and link pages are their own `GoRoute`s in `router.dart`; add new ones to `_public` or `_links`.
- Run: `cd app && flutter run -d chrome --dart-define=API_URL=http://localhost:8000`.

## How to continue
- Read `CLAUDE.md`, then this file, then the phase file for the current phase.
- For a screen: open `design/screens/<Board>.dc.html` (+ Web/Mobile variant), read its section in `docs/screens/behaviour.md`, build it, tick it in the phase file, update this note, commit as Gautam, push `working`.
