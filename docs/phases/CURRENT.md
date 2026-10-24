# Currently doing / next (handoff note)

Updated with every push, so anyone (another Claude session, local Claude Code, a developer) can pick up from here.

**Last updated:** 2026-10-24 · branch `working`

## Done
- 2026-10-24 (latest): D-59: Notifications page for admin and trainer (`/notifications`, bell → See all, More → Notifications). Invite links now use `FRONTEND_URL` (twv.prowavetech.in). Checked 390 / 768 / 1280 in debug. **Next:** merge to develop when Probid asks.
- 2026-10-24: D-58: toast for each new notification while the app is open (Open → its page), unread count on every bell (admin, trainer, client), Log out in admin Settings, `seed_demo` reuses the live admin (no second admin). Checked 390 / 768 / 1280 in debug. Live: Probid set `FIREBASE_JSON`, the server key and `.env` on the VPS. **Next:** merge to develop when Probid asks, then try push and the demo data on the live site.
- 2026-10-24: D-57: every admin also has a trainer profile (signal + migration `trainers/0003`), so the Invite links modal works on the live site where the admin comes from `createsuperuser` and there are no trainers. README Firebase section: table of which file goes where + clean-up if `flutterfire configure` was run. Tests, analyzer and browser check done. **Next:** Probid fills `app/firebase.json` and the server key, tries push locally; merge to develop only when he asks.
- 2026-10-23: D-56: push notifications in the app (Android + web; iOS after the Apple account): register after login, remove on log out, tap opens the page; keys in `app/firebase.json` + `backend/secrets/` (not in git), live site via GitHub secret `FIREBASE_JSON`. Live site https://twv.prowavetech.in deploys from `develop` (first green 2026-10-23). `docs/HANDOFF.md` rewritten for Gautam's new account. **Next:** Gautam fills `firebase.json` and tries push locally (README "Push notifications on your PC"), then tests the live site; merge to develop only when he asks. Parked: Daily summary design, Gym news admin screen, client brand colour / dark theme, phone health data, WhatsApp.
- 2026-10-23 (D-55): From address in Integrations → Email sending; packages hidden everywhere (commented, can come back); app icon + splash from Gautam's logo; one-domain deploy (CloudPanel reverse proxy → Docker nginx → app + API) with `docker-compose.prod.yml`, `deploy/` and GitHub Actions `deploy-develop.yml` (push to develop = test + deploy). Tested the whole stack in Docker locally; pytest green, analyzer clean. **Next:** Gautam does the one-time server setup (`deploy/README.md`) and GitHub secrets, then merge working → develop. Firebase: app push code once he shares the Firebase config files. WhatsApp later. Parked: Daily summary design, Gym news admin screen, client brand colour / dark theme, phone health data.
- 2026-10-23 (D-54): Gautam's 8-screenshot feedback (D-54): trainer What clients see / Access save fixed (PUT), new trainer permissions Automations + Assign clients, Settings social links, Timezone / App language / Apple Health card / Daily digest card hidden, every Duplicate asks first, table headers never cut, ellipsis text → tooltip everywhere, template modal, compact Automations list, builder trigger grid, lists in cards scroll after 5. Tests and analyzer clean; checked 390, 768, 1024, 1280. **Next:** whatever Gautam picks (questions answered in the thread: emails, sender, APK + CloudPanel VPS, health, package). Parked: Daily summary design, Gym news admin screen.
- 2026-10-22 (Settings): admin Settings built (D-53, boards Settings / SettingsMobile): Gym profile, Regional & defaults (new clients start with units, week start, timezone, theme), Branding (logo, colour, theme, draft → Apply, preview), Roles & access (real counts, enforced trainer cells, locked cells), Integrations (WhatsApp off skips WhatsApp, email domain DNS check + own from-address, health data types). Debug check 390–1440, tests and analyzer clean. **Decided 2026-10-23:** Daily digest stays Off (comes back with the Daily summary design); brand colour / dark theme across the client app later. **Next:** whatever Gautam picks; all admin pages from the list are built. Parked: Daily summary design, Gym news admin screen.
- 2026-10-22 (Emails): admin Emails & alerts built (D-52, boards Emails / EmailsMobile): Client messages with the board words, editor + preview + where it is used, new / delete with Undo; Team alerts now really pick the channels (owner + the client's trainer), quiet hours, new Daily digest (8 am email, Off until Gautam decides); Sender. Phone list → editor view. Debug check 390–1440, tests and analyzer clean. **Next:** Settings. Parked: Daily summary design, Gym news admin screen.
- 2026-10-22 (Automations): admin Automations + New automation + Automation builder built (D-51, boards Automations / AutomationNew / AutomationBuilder + Mobile): list with switches, chips, counts, ⋯ menu with Undo, starters modal, one builder page for new / edit that saves only on Save as draft / Turn on, board trigger settings, Not ready list, Last 30 days; demo automations seeded. Text box keeps focus when its error line appears / goes. Debug check 390–1440, tests and analyzer clean. **Next:** Emails & alerts, then Settings. Parked: Daily summary design, Gym news admin screen.
- 2026-10-22 (Forms): admin Forms & check-ins + Form builder built (D-50, boards Forms / FormBuilder + Mobile): real DB forms with the NEW onboarding questions, drafts on published forms until Publish, how it is sent, answers so far, create / preview / duplicate / archive / delete with Undo. Login stats row wraps at 900. Debug check 390–1440, tests and analyzer clean. **Next:** Automations + New automation + Automation builder, then Emails & alerts, Settings. Parked: Daily summary design, Gym news admin screen.
- 2026-10-22 (later): client form page built (D-49, boards ClientForm / ClientFormWeb): Check-ins cards for forms the coach sent, `/checkins/forms/<id>` wizard with every question type, review, send (offline), Undo, drafts; notification links fixed (sessions → `/train`, meal plans → `/nutrition/<id>`, forms → the form); admin `/checkins` reuses the trainer page. PAR-Q stays a Forms form (not onboarding). Debug check 390–1440, tests and analyzer clean. **Next:** admin Forms & check-ins + Form builder (show the app's NEW onboarding questions, not the board's old ones), then Automations + New automation + Automation builder, Emails & alerts, Settings. Parked: Daily summary design, Gym news admin screen.
- 2026-10-22 (late night): admin Trainers, Trainer profile, team Calendar and Activity log built (D-48); dashboard tile tooltips removed, Approvals overflow and Review button fixed. Debug check 390–1440 with no console errors, 266 tests green, analyzer clean. **Next:** Gautam checks these, then the remaining admin screens (Forms & check-ins, Automations, Emails & alerts, Settings). Parked: Daily summary design, Gym news admin screen.
- 2026-10-22 (night): admin Clients, Client profile (admin), Approvals built (D-47) with Add client, Change trainer, password / reset link, Invite links modal, Review drawer and Reject / Ask for info / Move back. Debug check 390–1440, tests and analyzer clean. **Next:** Gautam checks these, then the next admin screen (Trainers suggested, then Activity log). Parked: Daily summary design, Gym news admin screen.
- 2026-10-22 (evening): client profile missing parts built (D-46: target date, health over time, stock history, form-check video from the client logger, body map); toolbars wrap and chip rows scroll sideways on every staff page (debug sweep at 600–1024 for trainer and admin, no overflow); trainer dashboard Today rows without avatar. **Next:** Gautam checks these, then the next admin screen (Approvals suggested; ClientProfile is the admin client view, built with admin Clients). Parked: Daily summary design, Gym news admin screen.
- 2026-10-22 (later): Gautam's fixes: trainers make and change their own habits / supplement plans (D-45), habit Type cards, fit-width Frequency tabs, shorter list rows; Content drawer plays videos in place and opens pictures / PDFs full screen inside the app; PDF first-page preview; storage limit enforced; new video cover frame picked before Save (`content/stage/`); drop area reworked (drop never replaces a file, Replace does). Trainer side is complete (TrainerProfile / Trainers are admin pages). **Next:** Gautam checks these, then the next admin screen (Approvals suggested).
- 2026-10-22: Admin Dashboard (`/dashboard`, boards AdminDashboard / AdminDashboardMobile) and admin More page (AdminMoreMobile) built; admin router map `adminScreens` now has these plus the shared library pages. **Next admin screens (ask Gautam which first): Approvals, Clients, Trainers, Activity log**, which the dashboard buttons already open. Parked: Daily summary design, Gym news admin screen.
- 2026-10-21 (night, last): Content library built (`/content`, boards Content / ContentMobile); trainer side complete. **Next: admin screens, 1-2 at a time, done well** (admin router map is empty today; start with the admin Dashboard). Parked: Daily summary design, Gym news admin screen.
- 2026-10-21 (late night, later): Habits & supplements built (`/habits`, boards Habits / HabitsMobile). **Next: Content library** (Content / ContentMobile; wire "Upload to library" and "Open in library"), then admin, 1-2 screens at a time, done well (Gautam). Parked: Daily summary design, Gym news admin screen.
- 2026-10-21 (late night): Gautam's debug-mode round — Food library blank on tablet, meal builder errors, food value limits, meal plan ⋯ menu and stat grid, edit exercise layout, phone top space, trainer More page. **Next: Habits & supplements**, then Content library, then admin.
- 2026-10-21 (night, later): Gautam's Exercise fixes — card layout, first-frame thumbnails, Add to program without doubles, filter submenu on hover, edit page lines / dropdown / upload modal, stats and video card, same-size builder day cards. **Next: Habits & supplements**, then Content library, then admin.
- 2026-10-21 (night): Nutrition & foods Done (D-44): Nutrition page (Meal plans, Food library, food drawer, Excel import) and Meal plan builder `/nutrition/:id` (Publish = save, draft banner, LeaveGuard "Publish your changes?", Assign with only own clients, clients drawer). Checked at 390–1440 and in debug mode. Programs list refresh / card layout / exercise drawer in the builder fixed. **Next: Habits & supplements**, then Content library, then admin. Parked: Daily summary design, Gym news admin screen.
- 2026-10-21 (later): Gautam's fixes — real cover frames (D-42), program card ⋯ menu, card layout, list refresh, tooltips, Add exercises drawer rows, builder week row; builder Save changes / Discard + ask before leaving + week ⋯ menu (Copy / Add empty / Delete), assignment Undo leaves no history, Unassigned label, who made a program (D-43). **Next: Nutrition & foods** (with MealPlanBuilder; give it the same Save changes + LeaveGuard), then Habits & supplements, Content library, then admin. Parked: Daily summary design, Gym news admin screen.
- 2026-10-21: fixes from Gautam's phone test (D-41): Android compileSdk 37, real-phone login (laptop IP, http in debug, any host in dev, README steps), web auth side panel 40 / 60 with a faded blue, help sheets open at once. Android build not verified here (no Android SDK in this environment). **Next: Nutrition & foods** (with MealPlanBuilder), then Habits & supplements, Content library, then admin.
- 2026-10-20 (night): Exercises built — library, Exercise page, Add / Edit exercise (+ mobile) (D-40: built-in read-only, custom needs "Add custom exercises", cover upload, YouTube check, Add to program in every week). Tests 210 pass. **Next: Nutrition & foods** (with MealPlanBuilder), then Habits & supplements, Content library (the Pick a video modal's "Upload to library" opens it), then admin (admin has no screens in the router yet; add the library pages to an admin map then). Parked: Daily summary design, Gym news admin screen.
- 2026-10-20 (evening): Programs page + Program builder built (D-39: who may change a program, trainer sees only own clients, Delete Undo). Tests 203 pass. **Next: Exercises** (ExerciseLibrary, ExerciseDetail, ExerciseAdd + mobile; builder's "Exercise details" opens it), then Nutrition & foods (with MealPlanBuilder), Habits & supplements, Content library, then admin (admin has no screens in the router yet; add the library pages to an admin map then). Parked: Daily summary design, Gym news admin screen.
- 2026-10-20 (later): TrainerMoreMobile built (profile card, Library rows, Log out); Check-ins badge loads on every trainer page. **Next: the library screens** (Programs, Exercises, Nutrition & foods, Habits & supplements, Content library), then admin.
- 2026-10-20: TrainerMeMobile phone layout fixed (header, 2 × 2 stats, detail rows, tab strip follows the open tab, tablet header). 7 backend tests that failed on some dates now pass on any date (`fresh_measure_period` fixture); run `pip install -r requirements.txt` (pypdfium2) and `pytest --create-db` when the date changed. **Next: TrainerMoreMobile**, then the library screens (Programs, Exercises, Nutrition & foods, Habits & supplements, Content library), then admin. Parked: Daily summary design, Gym news admin screen.
- 2026-10-18 (handoff): `docs/HANDOFF.md` written so a new claude.ai account can continue (status, what is left, parked items, artifacts, working method, project instructions to paste). Next is unchanged: TrainerMoreMobile, then the library screens.
- 2026-10-18 (later): web drag and drop in the upload modal (own window drop listener on web), Edit details for documents, document viewer footer fits (Delete is an icon), dashboard Today Done moved into ⋯ ("Mark as done"), Clients who need you chips scroll sideways, Activity card `View all` → My profile · My activity. Parked until Gautam asks: Daily summary design and Gym news screens. Next: TrainerMoreMobile, then the library screens.
- 2026-10-18: round 4 fixes (debug-mode crashes, PlanEditBar, Add food un-select, amount format, Your access card, Daily summary + Gym news sending, drag and drop / PDF preview). Gautam tests in Flutter web DEBUG: check new pages with `flutter run -d web-server --no-web-resources-cdn` and look for console assertions; never put a LayoutBuilder under IntrinsicHeight/Width.
- 2026-10-17 round 3 (D-37): meal editor Portion and swaps (per-client swaps), supplement client copies, adherence from the followed plan, compact pickers, Forms photos, setup panel light. Trainer Calendar and My profile built (D-38). Next: TrainerMoreMobile, then the library screens (Programs, Exercises, Nutrition & foods, Habits & supplements, Content library).
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
- `ClientHomeHero`: Gautam picked it (2026-10-16); phone Home uses the hero (D-29).

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
- Body measurements (D-22): client logs from the Body tab (`POST me/measurements/`, merge per day). Still to do with the
  trainer screens: the coach's measurement picker (`measure_keys`) and a measurement block in the check-in form.
- Habits Day / Week tabs sized like the board (2026-10-16).
- Next: More tab, then trainer / admin boards.

## More tab (built 2026-10-16, D-23 / D-24)
- `/more` (+ profile, notifications, activity) and web My account tabs; all sheets. Code `app/lib/features/client/more/`.
- Backend: `me/account/`, `me/activity/`, `me/data-export/`, `me/report/`; prefs on User; own quiet hours; water and
  supplement reminders; private photos; photos every N weeks; measurements step in photo-week check-ins.
- After pulling: `python manage.py migrate` (accounts 0002, checkins 0004, notifications 0002, clients 0004).
- Not built: dark theme, units / Sunday week outside More, coach pickers (trainer screens).

## Library (built 2026-10-16, D-26)
- `/library` and `/library/<id>`; item sheet for video, PDF, image and article. Code `app/lib/features/client/library/`.
- Backend: `apps/content/library.py`, `me/library/` list / detail / progress; share notes and sources.
- After pulling: `python manage.py migrate` (content 0002) and `seed_demo` (demo PDFs, image and videos; videos need
  ffmpeg, else they show "Video not uploaded yet").
- Media (D-27): real PDF pages (pypdfium2, run `pip install -r requirements.txt`), video seek / full screen, picture zoom, exercise guide shows the exercise's video or picture, new `link` kind (migration content 0003).
- YouTube in-app (D-28): YouTube plays inside the Library sheet and exercise guide (`flutter pub get` for youtube_player_iframe); demo videos ship in `backend/apps/common/demo_media`, rerun `seed_demo`. Check YouTube playback in a real browser / phone (blocked in the sandbox).
- Not built: saving images to the phone gallery.

## About page + Home hero (2026-10-16, D-29)
- `ClientAbout` / `ClientAboutWeb` Done: `app/lib/features/client/more/about_screen.dart`, route `/more/about`,
  opened from Help & about. Contact and coach card come from `GymSettings` (new fields, migration gym 0002;
  `seed_defaults` fills phone, email and stats). Admin edits them with `PATCH settings/gym/`.
- `ClientHomeHero` Done (phone Home). After pulling: `migrate`, `seed_defaults`.
- Client boards are all built now except `ClientProfile*` (that is the trainer / admin view of a client, built with
  the trainer screens). Next: trainer boards.


## Trainer dashboard (2026-10-16, D-30)
- `TrainerDashboard` + `TrainerDashboardMobile` Done: `app/lib/features/trainer/dashboard/` (model, screen, parts =
  bell dropdown, review drawer, New session modal). API `dashboard/trainer/` = `apps/activity/trainer_home.py`;
  review view = `apps/checkins/review.py` (on `GET checkins/<id>/`).
- One check-in queue for all roles: `apps/checkins/queue.py`. Anything that counts "to review" must use it.
- Activity card (D-31): `activity()` in `trainer_home.py`, next pages `GET dashboard/trainer/activity/?before=<next>`
  (keyset on created_at + id). Rows = ActivityEvent where actor or trainer is the trainer, or client is one of theirs.
- Overlays: `showAppMenu` opens on the side with room, caps height and scrolls to the picked row. Sheets and
  drawers with text fields free their controllers with `disposeLater` (after the exit animation), and navigation
  from inside a drawer happens in the caller after it closes (fixes `_dependents.isEmpty`).
- Library demo: `apps/common/demo_media/eat.pdf` is a designed 6-page guide (source `eat.html`, printed with
  `backend/scripts/demo_pdf.js`); `seed_demo` swaps it into older demo databases. Articles support `## heading`
  and `- bullet` paragraphs.
- Router: trainer pages go in `trainerScreens` (paths overlap with the client app). Admin map is empty for now.
- Demo: `seed_demo` gives Aman a full day (5 sessions, 5 more clients, 3 weekly check-ins, Rohan's plan ending
  Sunday). Log in as aman@trainwithvimal.com / Demo@1234.
- My clients (D-32): `app/lib/features/trainer/clients/`; API `clients/` (+ `counts/`, `export/?ids=`). Next
  check-in rule in `apps/clients/serializers.next_checkin` (filter in `filters.py` uses the same rule).
- Client profile (D-34, 2026-10-17): `app/lib/features/trainer/client_profile/` (`cp_model` controller, `cp_common` shared
  pieces, one file per tab + drawers). Check-ins (D-35): `app/lib/features/trainer/checkins/`.
- Next trainer boards: TrainerCalendar, TrainerMe, TrainerMoreMobile, then the library pages the profile links to
  (Programs, Content library), TrainerProfile, Trainers. Then admin.
- Onboarding (D-36, 2026-10-17): setup = the gym's coaching form in 9 steps (`app/lib/features/auth/setup/`);
  fields and rules in `backend/apps/clients/onboarding.py`; answers are profile fields, edited in the Edit profile
  drawer (`trainer/clients/clients_parts.dart`), About card from `overview.about.items`. Not browser-checked yet on
  phone / desktop: the 9 setup steps and the new drawer sections need a look against the setup boards.
