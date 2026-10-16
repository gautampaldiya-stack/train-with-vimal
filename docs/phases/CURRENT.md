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

## Login flow (built 2026-10-15)
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
- Responsive (D-11): phone layout only under 600; 600–899 web layout in a card; side panel from 900, fluid.
  Checked login, forgot, join, reset, setup and staff shell at 600, 768, 900, 1024 and 1280.
- Log out: Settings / My profile / My account placeholders have a working Log out (confirm → log in page).
- Web uses path URLs (`usePathUrlStrategy`): the web server must fall back to `index.html` for unknown paths.
- Client-app components: `app/lib/core/widgets/client.dart`; auth-only pieces: `features/auth/account_widgets.dart`.
- Demo logins (password Demo@1234): riya@example.com (all set), isha@example.com (setup not done),
  neha@example.com and karan@example.com (waiting for approval), tara@example.com (email not verified).
  Sana has a login link and `AMAN-4821` is an invite code; `seed_demo` prints the demo links.
- Router: `landingFor(me)` picks /verify, /pending, /setup or /home. Link pages (`/reset-password`, `/join`,
  `/start`, `/verify-email`) open signed in or out; `/login` and `/forgot` send a signed-in person on.
- Known: realtime socket returns 404 under `manage.py runserver` (needs an ASGI server); the gym phone is empty
  in the seed so the support card shows email only.

## Login flow: all boards Done (2026-10-15)
- ClientLogin, ClientLoginWeb, ClientWelcome checked in the browser at 390, 600, 768, 900, 1024, 1280 and 1440.
- Text now uses line height 1.26 by default (`AppText.normal`, the browser's `normal` for Plus Jakarta Sans);
  before, every line was about 10% taller than on the boards. Negative CSS margins use the `Pull` widget.
- Realtime connects only for approved accounts (the server refuses pending ones).
- Browser check tools used: boards served by `design/screens/serve.py`, app by `flutter build web --no-web-resources-cdn`,
  both driven by Playwright (Chromium needs `locale` set, else Flutter fails on "Incorrect locale information").

## Client Home (2026-10-15)
- `ClientHome` and `ClientHomeWeb` Done: `app/lib/features/client/home/` (`home_model.dart` data + writes,
  `home_screen.dart` cards and layouts, `home_sheets.dart` sheets, `home_parts.dart` small `ch-*` pieces).
- Every write (water, Ate it / Undo, habit values, supplements, Mark all read) changes the screen at once and goes
  through the outbox with the day's `date`, so it works offline.
- API `GET me/home/` now also sends: `goal`, `strip` (Mon–Sun with exercises, minutes, done line), `meals` (with
  macros), `habits_soon`, richer `coming_up` (session, check-in with question / photo count, plan end), `unread`,
  `trainer_note` (coach's last check-in reply). Water logs also move the water habit (one glass = 250 ml).
- Seed: Riya has Fat loss support supplements, a 6:30 pm session with Aman, a reviewed check-in, 3 notifications,
  the habits Walk / Water / Sleep 7 hours, and "No sugary drinks" starting next Monday.
- `ClientHomeHero` (blue hero option) not built: waiting for Gautam to choose.

## Train tab and workout logger (2026-10-15)
- `ClientTrain`, `ClientTrainWeb`, `ClientWorkout`, `ClientWorkoutWeb` Done: `app/lib/features/client/train/`
  (`train_model.dart` data + past workouts, `train_screen.dart` the tab, `train_parts.dart` guide / history / body map,
  `workout_model.dart` the running workout, `workout_screen.dart` the logger, sheets and the done page).
- Routes: `/train`, `/train/workout?start=<day id>` (new), `?reopen=<workout id>` ("Log more sets"), plain
  `/train/workout` continues the running one. `/train?discarded=1|2` shows the discard toast.
- API: `me/train/` sends the day note, minutes, `sets_done` per exercise, `in_progress`, `completed_today`, trainer,
  today's session, bodyweight. New `PUT me/workouts/<id>/state/` (whole workout, safe to repeat), `POST reopen/`,
  `POST feedback/`, list filter `?name=` and `since`. New fields `WorkoutLog.paused_at`, `reopened_at`,
  `SetLog.distance_km`, `client_key` (migration `training/0002`). Rules in decision D-16.
- Seed: how-to and form cues for 11 more built-in exercises, Riya's day and exercise notes (`riya_train`).
- Android: `kotlin.incremental=false` in `app/android/gradle.properties` fixes "Could not close incremental caches"
  when plugins (url_launcher, shared_preferences) and the app are on different drives on Windows.
- Bottom nav (phone) is 8 px shorter (Gautam's padding: top 4, bottom 12); toasts sit 75 above the bottom.
- Not built: the guide video player (no video in the seed; YouTube links open outside), block names from the
  program (no field yet, D-16).

## Doing now
- Train follow-ups from Gautam (D-17) pushed: guide dialog background, Past workouts header fixed while the list
  scrolls, week-strip day tap, exercise pictures, logger history for one exercise + Use last time, timer stops when
  the client leaves Train. New API: `POST me/workouts/<id>/pause/` (`at`), `resume/`, `GET me/workouts/exercise-history/?exercise=`, exercise `thumb`.
- Habits & supplements built (`ClientHabits`, `ClientHabitsWeb`, D-18): `GET me/habits/` now carries the Mon–Sun
  `week` grid, `starts_on`, `set_by`, supplement `group` / `taken_at` / `last_7`; demo seed adds supplement stock.
- Check-ins built (`ClientCheckin`, `ClientCheckinWeb`, D-19): `GET me/checkins/?tab=weekly|daily&before=` now
  sends coach, program week, stats, daily / weekly cards (form with chips, today's sent row, steps, water, weights)
  and paged history with Missed rows. `POST me/submissions/` takes `photos` as data URLs; `DELETE me/submissions/<id>/`
  is the Undo. Migration `checkins 0002` gives the built-in forms the board's questions. Seed: Riya's 6 weekly and
  10 days of daily check-ins. New Flutter package `image_picker` (photo slots).
- Check-ins fixes (Gautam, 2026-10-15): Edit answers no longer crashes on old forms (today's rows carry `answers`
  and `photos`), cards refresh after a form (screens reload on outbox sync), fixed form header, Past check-ins scroll
  inside a fixed-height card, full "sent" summary with thumbnails, full-size photo viewer
  (`core/widgets/photo_viewer.dart`), photo question slots named by its options. Autofocus on login / forgot / join.
- Next: Food tab (`ClientMealNutrition` + Web) and Log food (`ClientFoodLog` + Web).

## Next
1. Pages Home links to: Train + Workout logger (`ClientTrain`, `ClientWorkout`), Habits, Check-in, Food log.
2. Rest of the client screens, then trainer, then admin (order in `phase-5-screens.md`).

## How screens plug in
- Signed-in screens: add to `screens` map in `lib/app/router.dart` (`'/clients'`, `'/clients/:id'`).
  Missing ones show a "This page is on the way" holder, so nav never breaks.
- Signed-out and link pages are their own `GoRoute`s in `router.dart`; add new ones to `_public` or `_links`.
- Run: `cd app && flutter run -d chrome --dart-define=API_URL=http://localhost:8000`.

## How to continue
- Read `CLAUDE.md`, then this file, then the phase file for the current phase.
- For a screen: open `design/screens/<Board>.dc.html` (+ Web/Mobile variant), read its section in `docs/screens/behaviour.md`, build it, tick it in the phase file, update this note, commit as Gautam, push `working`.

## Food (built 2026-10-15, D-20)
- `/food` = combined Food page (ClientMealNutrition + Web), `/food/log?meal=` = Log food (ClientFoodLog + Web).
  Code in `app/lib/features/client/food/` (model, parts incl. typeable `NumStepper`, sheets, screens).
- Mark as eaten ▾ with optional photo (data URL with the eat op, outbox); photo on card, log row, details.
- Web ≥ 700 px content: header, strip, tabs fixed; lists scroll. Checked 390, 600, 768, 900, 1024, 1280, 1440.
- Old boards ClientFood / ClientNutrition are replaced by this page (not built on purpose).
- Round 2 (2026-10-16): photo first then Mark as eaten, `photo` meal op, extras inside the meal card, Copy yesterday
  Undo (`undo-copy`), Log food web list scrolls alone, fit tabs (`TwoTabs.fit`), rest-day Train card full width,
  daily edit button `Save changes`. "Other time" in Add to built (D-20 #11).

## Progress (built 2026-10-16, D-21)
- `/progress` (ClientProgress + Web), `/progress/history`, `/progress/photos`, `/progress/compare`.
  Code in `app/lib/features/client/progress/` (model, parts, sheets, screen, pages). API `me/progress/`,
  `me/history/`, `me/weights/`, `me/photos/` (data URL). Demo: `seed_demo` adds Riya's measurements and photo sets.
- Habits Day / Week tabs sized like the board (2026-10-16).
- Next: More tab, then trainer / admin boards.
