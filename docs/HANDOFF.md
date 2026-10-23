# Handoff — continue this project from a new Claude account

First written 2026-10-18; **rewritten 2026-10-23** when Gautam moved to another claude.ai account again. A new Claude
(or developer) reading only this repo should be able to carry on without asking anything. Read this, then the
files in "Read before any work".

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
5. `docs/decisions/` — D-1 … D-56, why things are the way they are
6. `docs/memory/README.md` — every decision and answer from Gautam (long list, read it all)
7. For a screen: its board in `design/screens/`, its section in `docs/screens/behaviour.md`, tokens in `docs/design-system.md`

## 4. What is built (as of 2026-10-23)
`docs/screens/status.md`: **every board is Done** (101). Not built on purpose: `ClientFood*` / `ClientNutrition*`
(replaced by the combined Food page `ClientMealNutrition`), `Main` (canvas index, not a screen).

- **Login / onboarding, client app, trainer app, library screens** (Programs, Exercises, Nutrition & foods, Habits &
  supplements, Content library) and **all admin screens** (Dashboard, Clients, Approvals, Trainers, Trainer profile,
  Calendar, Activity log, Forms & check-ins + builder, Automations + builder, Emails & alerts, Settings).
- **Last rounds (23 Oct):** D-54 (trainer access, settings trims, tables, tooltips), D-55 (From address in
  Integrations, packages hidden, app icon + splash, one-domain Docker deploy + CI/CD), D-56 (push notifications in the
  app, Firebase config). Details: `docs/changes.md` (newest first) and `docs/phases/CURRENT.md`.
- **Next:** whatever Gautam asks after testing the live site. Open items: Firebase keys from Gautam (section 6),
  Android push test on a real phone, iPhone push after the Apple account, the parked list (section 6b).

## 5. Live server and deploy (D-55)
- **Live (staging):** https://twv.prowavetech.in on Gautam's CloudPanel VPS. One domain: CloudPanel reverse proxy ->
  `127.0.0.1:8080` -> Docker nginx (`deploy/nginx.conf`) -> Flutter web + Django API. Containers: web, api, worker,
  beat, db, redis (`docker-compose.prod.yml`). Server folder `/root/twv` (deploy runs as root, like Gautam's other
  project `/root/probid_v2`). Server `.env` = `/root/twv/backend/.env` (made by hand from `deploy/env.example`; it
  must use the docker names `db` and `redis`, not localhost).
- **Auto deploy:** push to `develop` -> `.github/workflows/deploy-develop.yml`: tests -> build web -> rsync over SSH ->
  `docker compose up -d --build` -> health check. GitHub secrets: `VPS_HOST`, `VPS_USER` (root), `VPS_SSH_KEY`,
  optional `VPS_PORT`, optional `FIREBASE_JSON`. First green deploy 2026-10-23.
- **Branch rule (Gautam 2026-10-23):** push daily work to `working` only. Merge to `develop` **only when Gautam asks**
  (every push to develop deploys the live site).
- Full steps, handy commands, backups: `deploy/README.md`.

## 6. Push notifications (D-56)
- Server sends push through FCM HTTP v1 when `PUSH_PROVIDER=fcm` (`backend/apps/notifications/providers.py`).
- App registers the phone / browser after login (`app/lib/core/push/push.dart`, `devices/` API) and removes it on
  log out; tapping a push opens its page (`data.route`). Web uses `app/web/firebase-messaging-sw.js`.
- Firebase keys are **not in git**: `app/firebase.json` (copy of `app/firebase.example.json`, passed with
  `--dart-define-from-file=firebase.json`; `dart run tool/firebase_web.dart` writes `web/firebase-config.js`) and the
  server key `backend/secrets/firebase-service-account.json` (server: `/root/twv/secrets/`). Steps: root `README.md`
  -> "Push notifications on your PC". Without the keys push is off and everything else works.
- Firebase project: apps for `com.trainwithvimal.app` (Android, iOS) and a Web app. **iPhone push waits** for the
  Apple developer account (APNs key). Push was not tried with real keys yet (Gautam fills `firebase.json` himself).

## 6b. Parked — remember, but do NOT build until Gautam asks
1. **Trainer Daily summary** design (backend sends at 8:00 AM; needs an email design + in-app view; the Daily digest
   card in Emails & alerts is hidden until then).
2. **Gym news admin screen** ("Notices from Vimal"): API exists, no admin screen / reading place yet.
3. **Client brand colour / dark theme** across the client app (Settings -> Branding saves them; the app ignores them).
4. **Phone health data** (Apple Health / Health Connect reading), "7th point abhi rehne do". Card hidden.
5. **WhatsApp** (Meta Cloud API keys) later. **Packages** are not used (hidden, code commented, D-55).
6. Timezone / App language rows in Settings are hidden (IST + English for now).

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
- Work on branch **`working`**. `develop` = staging and **auto-deploys the live site**, so merge only when Gautam asks; `main` = production at the end.
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
- App: `cd app && flutter run -d chrome --dart-define=API_URL=http://localhost:8000` (add `--dart-define-from-file=firebase.json` for push, section 6).
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
   for new rules (next number **D-57**), Gautam's answers in `docs/memory/README.md`, and `docs/changes.md` (newest
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
- Design repo ke design/ folder me hai. Har screen board jaisi hi banao: har button, modal, sheet aur dropdown. Flow ke saare pages ek saath banao. Jo nahi bana, wo status.md me board ke naam se likho.
- Phone layout sirf 600 se kam width par. Har screen 390, 600, 768, 900, 1024 aur 1280 width par browser me check karo.
- Main Flutter web DEBUG mode me Windows par test karta hoon: koi debug assertion nahi aana chahiye.
- Backend Django me, security aur validation strong. Data client, trainer aur admin teeno me same dikhna chahiye.
- Push se pehle backend tests chalao (naye API ke naye tests), flutter analyze clean, aur screen browser me try karo.
- Commit author "Gautam <gautampaldiya@gmail.com>". Claude ka naam ya Co-Authored-By kahin nahi. Commit message detailed. Chhoti-chhoti commits mat karo.
- Har kaam ke saath docs update karo (changes.md, CURRENT.md, status.md, decisions, memory).
- Roz ka kaam sirf working par push karo. develop me merge tabhi jab main bolun (develop par push = live site deploy).
- Daily summary design, Gym news admin screen, client brand colour / dark theme, phone health data aur WhatsApp abhi park hai, jab tak main na bolun mat banao.
- Mujhse Hinglish me, chhota aur simple baat karo.
```

### First message in the new project
```
Ye project mere purane account se aa raha hai. Pehle docs/HANDOFF.md aur usme likhi saari files padho, phir mujhe 5-6 line me batao ki kya ban chuka hai, live server (twv.prowavetech.in) ka kya haal hai aur aage kya bacha hai. Kaam branch working par; develop me tabhi merge jab main bolun.
```
