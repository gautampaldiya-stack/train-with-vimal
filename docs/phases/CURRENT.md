# Currently doing / next (handoff note)

Updated with every push, so anyone (another Claude session, local Claude Code, a developer) can pick up from here.

**Last updated:** 2026-10-14 · branch `working`

## Done
- Backend complete (all modules, offline sync, seeds, tests). Runs without Docker/Redis.
- Docs split per topic (decisions, rulebooks, prd, phases, architecture).
- Flutter foundation (phase 4): theme tokens, all board icons, shared widgets (`lib/core/widgets`),
  API client with JWT refresh (`lib/core/api`), offline outbox + read cache (`lib/core/offline`),
  realtime socket (`lib/core/realtime`), session (`lib/app/services.dart`), shells (`lib/app/shell`),
  router with role redirect (`lib/app/router.dart`). `flutter analyze` clean, `flutter build web` OK.

## Doing now
- Phase 5: login + onboarding (boards `ClientLogin`, `ClientLoginWeb`).

## Next
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
