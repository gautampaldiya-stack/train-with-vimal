# Handoff — continue this project from a new Claude account

Written 2026-10-18 when Gautam moved the work to another claude.ai account. A new Claude (or developer) reading only
this repo should be able to carry on without asking anything. Read this, then the files in "Read before any work".

## 1. What the app is
**Train With Vimal** — a coaching app for one gym (owner: Vimal). One Flutter codebase for Android, iOS and web,
every screen responsive (phone, tablet, desktop). Backend is Django.

| Role | Who | What they do |
|---|---|---|
| **Admin** | Only Vimal (exactly one) | Runs the gym: clients, approvals, trainers, programs, nutrition, forms, content, automations, emails, settings |
| **Trainer** | Many | Their own clients only (`visible_clients`): dashboard, clients, client profile, check-ins, calendar, own profile |
| **Client** | Many | Logs food, workouts, habits, water, check-ins, progress. Clients **log**, they never change their plan. Logging works offline |

- `backend/` — Django 5 + DRF, PostgreSQL, Celery + Redis (reminders, automations), Channels (realtime). **Complete**: all modules, offline sync, seeds, tests.
- `app/` — Flutter (Riverpod, go_router, dio).
- `design/screens/` — 104 `*.dc.html` boards + `twv.css` tokens. **The UI must match these boards exactly.** Open with `python design/screens/serve.py` (or `serve.bat` on Windows).
- `docs/` — the plan; keep it updated with every piece of work.

## 2. Artifacts (design canvas links)
The project uses claude.ai Artifacts only for the **design canvas** (the same 104 boards as `design/screens/`).
No other artifacts (dashboards, docs) are used. The repo copy in `design/screens/` is the source of truth; the
artifacts are for viewing online.

| Artifact | Link | Use |
|---|---|---|
| Train With Vimal Design New (design canvas, all boards) | https://claude.ai/artifact/3xeZtZYPoU5NPKqyKk1Wah | Latest canvas; referenced in `docs/design.md` |
| Train With Vimal design canvas (v282, 104 boards) | https://claude.ai/artifact/NKNGUZt9ZJMVXwiKXbfhiK | Canvas named in `CLAUDE.md` and `docs/memory/README.md` |

If an artifact link does not open from the new account (artifacts are private to the account that owns them),
Gautam has to share it from the old account, or just use `design/screens/` from the repo, which has everything.

## 3. Read before any work (Gautam's rule)
1. `CLAUDE.md`
2. `docs/phases/CURRENT.md` — what is happening now / next (handoff note, updated with every push)
3. `docs/screens/status.md` — every board, Done / Partial / Not started
4. `docs/rulebooks/definition-of-done.md` — when a screen counts as done
5. `docs/decisions/` — D-1 … D-38, why things are the way they are
6. `docs/memory/README.md` — every decision and answer from Gautam (long list, read it all)
7. For a screen: its board in `design/screens/`, its section in `docs/screens/behaviour.md`, tokens in `docs/design-system.md`

## 4. What is built (as of 2026-10-18)
`docs/screens/status.md`: **49 Done, 54 Not started** (of 104; `Main` is the design-system board).

- **Login / onboarding**: all Done — intro, welcome, log in, forgot / reset password, join (invite) link, login link,
  verify email, permissions, approval wait, setup (the gym's 9-step coaching form, D-36), health.
- **Client app**: all Done — Home (phone uses the **hero** design, Gautam's pick), Train + workout logger, Food
  (combined `ClientMealNutrition` page) + Log food, Habits & supplements, Check-ins, Progress (+ history, photos,
  compare, body measurements), More / My account, Library, About.
  `ClientFood*` and `ClientNutrition*` are **replaced on purpose** by the combined Food page (not to be built).
  `ClientProfile` / `ClientProfileMobile` are the staff view of a client, built as the trainer Client profile.
- **Trainer**: Done — Dashboard, My clients, Client profile (all 9 tabs), Check-ins, Calendar, My profile (TrainerMe).
- **Backend**: complete, incl. Daily summary sending (8 AM) and the Gym news API.

## 5. What is left (Not started, by board name)
- **Trainer app**: only `TrainerMoreMobile` (phone More tab: Library links + Log out; do this next). The trainer's own
  My profile is `TrainerMe` / `TrainerMeMobile` and is **Done**.
- **Polish asked by Gautam (18 Oct):** trainer My profile on phone (`TrainerMeMobile`, route of `TrainerMe`) needs a
  better mobile layout: all details, cards and buttons must fit and line up well at 390 (and under 600), every tab,
  modal and sheet included. Check against `design/screens/TrainerMeMobile.dc.html` in the browser and in debug mode.
- **Library screens TrainerMoreMobile and the client profile link to** (also admin): `Programs`, `ProgramBuilder`, `ExerciseLibrary`,
  `ExerciseDetail`, `ExerciseAdd`, `Nutrition`, `MealPlanBuilder`, `Habits`, `Content` (each + `Mobile`).
- **Admin**: `Trainers` (Vimal's list of trainers, behaviour 2.7), `TrainerProfile` (Vimal's view of one trainer,
  breadcrumb Trainers / Aman Verma, behaviour 2.24), `AdminDashboard`, `AdminMoreMobile`, `Clients`, `Approvals`, `Calendar`, `Activity`, `Forms`,
  `FormBuilder`, `Automations`, `AutomationNew`, `AutomationBuilder`, `Emails`, `Settings` (each + `Mobile`).
- Not checked yet: the 9 setup steps and the new Edit profile drawer sections against the setup boards (phone / desktop).
- Not built (small): guide video player for uploaded videos without YouTube, saving images to the phone gallery,
  dark theme, coach pickers that belong to admin screens.

**Order (from CURRENT.md):** My profile mobile polish → TrainerMoreMobile → library screens (Programs, Exercises, Nutrition & foods, Habits &
supplements, Content library) → admin screens (incl. Trainers, TrainerProfile).

## 6. Parked — remember, but do NOT build until Gautam asks ("baad me karenge", 18 Oct)
1. **Trainer Daily summary** — toggle in My profile → Account → Notifications (board text "Email at 8:00 am with
   your day"). Backend already sends at 8:00 AM as bell + push + plain email (`backend/apps/notifications/staff.py`).
   Missing: a designed email template and an in-app view (no board exists). Agree the look with Gautam first.
2. **Gym news / announcements** ("Notices from Vimal") — `GymNews` model + admin-only `gym-news/` API exist and
   deliver to trainers. Missing: the **admin screen to post** news and a place in the app to read past notices
   (no board). Propose a design when admin screens start.

## 7. Gautam's preferences (short; full list in `docs/memory/README.md`)
- Talk to Gautam in **Hinglish**, short and simple.
- Every screen same-to-same as its board: every button, modal, sheet, dropdown, empty state, toast. Build a whole
  flow together; whatever is not built goes in `status.md` by board name.
- **Phone layout only under 600 px.** Check every screen in a browser at 600, 768, 900, 1024 and 1280 (plus 390 phone).
  A board is Done only when it matches in the browser.
- Gautam tests mostly with **Flutter web in DEBUG mode on Windows**: no debug assertions (never a LayoutBuilder under
  IntrinsicHeight/Width); webview widgets (YouTube player) must handle web properly.
  Check with `flutter run -d web-server --no-web-resources-cdn` and watch the console.
- **Data must match across client, trainer and admin** ("kahi ulta na ho"): one check-in queue (`apps/checkins/queue.py`), shared rules.
- **Input rule** (16 Oct): every field takes only its type (integer / decimal / alphanumeric); mobile = 10 digits;
  email validated; kg / height / weight numeric; dates through a date picker. My clients **Export CSV** and **row
  checkboxes** are commented out for now.
- Toasts: phone centred full width; tablet / web bottom right, 400 wide; Undo toasts 10 s.
- Amounts read "½ katori · 75 g", never "0.5 × 1 katori".
- Backend: strong security and validation. Errors use `{"error": {"code", "message", "fields"}}`. Lists paginated.
- Client logging offline: outbox + `Idempotency-Key`.
- Write even small changes in the docs (`docs/changes.md` + the doc they touch).

## 8. Git and push rules
- Work on branch **`working`**. `develop` = staging (only when Gautam wants to test), `main` = production at the end.
- Commit author and committer **`Gautam <gautampaldiya@gmail.com>`**:
  `git -c user.name=Gautam -c user.email=gautampaldiya@gmail.com commit ...`
- **No Claude / Anthropic name anywhere** in commits: no `Co-Authored-By`, no session links. No tiny commits.
- Before push: `cd backend && pytest` (write new tests for new APIs), `cd app && flutter analyze` clean, try the screen in a browser.
- Push to `working` as soon as each screen / module is complete, and update `docs/phases/CURRENT.md`
  ("abhi kya chal raha hai / aage kya") and `docs/screens/status.md`.
- Never commit `backend/.env`, keys or Firebase service-account files.

## 9. Run it
- Docker: `docker compose up --build`, then `docker compose exec api python manage.py seed_defaults` and `seed_demo`.
- Without Docker (Windows): Python 3.12+, PostgreSQL 16, `REDIS_URL=` empty in `backend/.env` (see `docs/rulebooks/local-setup.md`).
- App: `cd app && flutter run -d chrome --dart-define=API_URL=http://localhost:8000`.
- Demo logins (password `Demo@1234`): vimal@trainwithvimal.com (admin), aman@trainwithvimal.com (trainer),
  riya@example.com (client). More in `CURRENT.md`.
- Browser checks: boards via `design/screens/serve.py`, app via `flutter build web --no-web-resources-cdn`, Playwright
  with `locale` set (else Flutter fails on "Incorrect locale information").

## 10. How the work was done so far (follow the same way)
**Per screen / module, in this order:**
1. **Read first:** `CLAUDE.md`, this file, `CURRENT.md`, `status.md`, `definition-of-done.md`, the decisions that
   touch the area, `docs/memory/README.md`.
2. **List the whole flow:** open the board (`design/screens/<Board>.dc.html` and its `Web` / `Mobile` twin), follow
   every button, link, menu, sheet and email it opens, and build all of those pages in the same batch.
3. **Read the behaviour:** the board's section in `docs/screens/behaviour.md` says what each button does, the toasts,
   empty states and errors. Tokens and components: `docs/design-system.md`, `design/screens/twv.css`.
4. **Backend first if data is missing:** extend the API in `backend/apps/<module>/` (serializer + view + permission
   so trainers only see their own clients), add a migration, add demo data to `seed_demo` so the screen shows real
   data, and write pytest tests for every new endpoint (happy path, validation, wrong role / other trainer's client).
5. **Build the Flutter screen:** code under `app/lib/features/<role>/<area>/` split as `*_model.dart` (data, writes,
   Riverpod), `*_screen.dart` (layouts), `*_parts.dart` (small pieces), `*_sheets.dart` (sheets / modals). Shared
   widgets live in `app/lib/core/widgets`. Only theme tokens, no hard-coded colours. Client writes go through the
   offline outbox. Add the route in `app/lib/app/router.dart` (`trainerScreens` for trainer paths).
6. **Browser check against the board, side by side:**
   - Boards: `python design/screens/serve.py`. App: `cd app && flutter build web --no-web-resources-cdn` and serve
     `build/web` with fallback to `index.html` (path URLs). Backend: `python manage.py runserver` with `seed_demo` data.
   - Playwright (Chromium, `locale: 'en-US'` must be set, else Flutter fails with "Incorrect locale information"):
     log in as the demo user, open the page, take screenshots of the board and the app at **390, 600, 768, 900, 1024,
     1280 and 1440** width, open every modal / sheet / menu and compare. Fix until they match.
   - Also run once in debug (`flutter run -d web-server --no-web-resources-cdn`) and check the console for
     assertions, because Gautam tests in debug.
   - Playwright scripts were throwaway (scratch folder, not in the repo); write a fresh one each time.
7. **Before push:** `cd backend && pytest` all green, `cd app && flutter analyze` with no issues.
8. **Docs in the same commit:** row in `docs/screens/status.md` (Done only after the browser check, else Partial
   with what is missing), `docs/phases/CURRENT.md` (Done / Doing now / Next), a decision file in `docs/decisions/`
   for new rules (next number D-39), Gautam's answers in `docs/memory/README.md`, and `docs/changes.md` (newest
   first, Pehle / Ab / Kyun / Updated) when something earlier changes.
9. **Commit and push:** one meaningful commit per screen / module (or per round of Gautam's fixes), author and
   committer Gautam, message in plain English saying what was built ("Trainer Calendar and My profile"). No
   Claude name. `git push origin working`. Amend or rewrite a pushed commit only if Gautam asks.

**Feedback rounds:** Gautam pulls, tests, and sends a list of fixes (often with screenshots). Do every point in that
list, write any new rule he gives into `docs/memory/README.md` (+ a decision if it is a rule for many screens), check
in the browser, push one commit for the round ("Client profile round 3: …").

**Talking with Gautam:**
- Hinglish, short, simple words. Lead with what was done and what he must do (pull, `migrate`, `seed_demo`,
  `flutter pub get`), then what is not built yet, by board name.
- When a design choice is open (e.g. phone Home: normal vs hero), show the options and let him pick; do not guess
  on visible design.
- Don't ask about small details: pick the board-faithful default, say which, and continue.
- After a pull he often needs: `python manage.py migrate`, `seed_defaults` / `seed_demo`, `pip install -r requirements.txt`, `flutter pub get`. Always say which ones.

## 11. Setting up the new claude.ai project
1. New account → connect GitHub (https://claude.ai/connect-github) with access to `gautampaldiya-stack/train-with-vimal`.
2. Create a new project, add the repository `gautampaldiya-stack/train-with-vimal`.
3. Paste the project instructions below into the project's instructions.
4. Send the first message below.

### Project instructions (paste as is)
```
Repo gautampaldiya-stack/train-with-vimal, branch "working". Har kaam se pehle CLAUDE.md, docs/HANDOFF.md, docs/phases/CURRENT.md, docs/screens/status.md, docs/rulebooks/definition-of-done.md, docs/memory/README.md aur docs/decisions padho.
- Design repo ke design/ folder me hai (online canvas: https://claude.ai/artifact/3xeZtZYPoU5NPKqyKk1Wah). Har screen board jaisi hi banao: har button, modal, sheet aur dropdown. Flow ke saare pages ek saath banao. Jo nahi bana, wo status.md me board ke naam se likho.
- Phone layout sirf 600 se kam width par. Har screen 600, 768, 900, 1024 aur 1280 width par browser me check karo. Board tabhi Done jab browser me design se mil jaye.
- Main Flutter web DEBUG mode me Windows par test karta hoon: koi debug assertion nahi aana chahiye.
- Backend Django me banao, security aur validation strong rakho. Data client, trainer aur admin teeno me same dikhna chahiye.
- Push se pehle backend tests chalao (naye API ke naye tests likho), flutter analyze clean rakho, aur screen browser me try karo.
- Commit author "Gautam <gautampaldiya@gmail.com>". Claude ka naam ya Co-Authored-By kahin nahi. Chhoti-chhoti commits mat karo.
- Har screen ya module poora hote hi working pe push karo, aur CURRENT.md me "abhi kya chal raha hai / aage kya" update karo.
- Daily summary design aur Gym news admin screen abhi park hai, jab tak main na bolun mat banao.
- Mujhse Hinglish me baat karo.
```

### First message in the new project
```
Ye project mere purane account se aa raha hai. Pehle docs/HANDOFF.md aur usme likhi saari files padho, phir mujhe 5-6 line me batao ki kya ban chuka hai aur aage kya hai. Uske baad trainer My profile ka mobile layout theek karo (HANDOFF section 5), phir TrainerMoreMobile (branch working).
```
