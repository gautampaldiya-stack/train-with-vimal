# Decisions

One file per decision. Add a new file for every new decision (next number), and a line in `../changes.md` if it changes an older one.

| # | Decision | Date |
|---|---|---|
| [D-01](0001-flutter-for-android-ios-and-web.md) | Flutter for Android, iOS and web | 2026-10-14 |
| [D-02](0002-django-drf-postgresql-celery-redis-channels.md) | Django + DRF + PostgreSQL + Celery/Redis + Channels | 2026-10-14 |
| [D-03](0003-login-with-email-or-mobile-password-always.md) | Login with email **or** mobile, password always | 2026-10-14 |
| [D-04](0004-outbound-email-in-app-push-realtime-now-whatsapp-s.md) | Outbound: email + in-app + push + realtime now; WhatsApp/SMS later via `.env` | 2026-10-14 |
| [D-05](0005-no-independent-coaches-saas.md) | No independent coaches / SaaS | 2026-10-14 |
| [D-06](0006-client-food-tab-combined-clientmealnutrition-page.md) | Client Food tab = combined `ClientMealNutrition` page; old ClientFood/ClientNutrition not built; ClientFoodLog stays | 2026-10-14 |
| [D-07](0007-client-logging-is-offline-first-outbox-idempotency.md) | Client logging is offline-first (outbox + `Idempotency-Key`, server accepts back-dated logs up to 7 days) | 2026-10-14 |
| [D-08](0008-data-stored-in-full-detail-as-the-screens-show-sna.md) | Data stored in full detail, as the screens show (snapshots of names/macros on logs, set-level workout data) | 2026-10-14 |
| [D-09](0009-tree-editors-save-the-whole-tree-update-rows-by-id.md) | Tree editors save the whole tree, update rows by id | 2026-10-14 |
| [D-10](0010-questions-that-already-have-answers-are-hidden-is.md) | Questions that already have answers are hidden (`is_removed`), never deleted | 2026-10-14 |
| [D-11](0011-every-screen-responsive-phone-tablet-desktop.md) | Every screen responsive (phone, tablet, desktop) | 2026-10-14 |
| [D-12](0012-realtime-websocket-while-the-app-is-open-fcm-push.md) | Realtime: WebSocket while the app is open, FCM push when closed | 2026-10-14 |
| [D-13](0013-branches-working-develop-main-commits-by-gautam-on.md) | Branches `working` → `develop` → `main`; commits by Gautam only | 2026-10-14 |
| [D-14](0014-client-setup-steps-vs-staff-checklist.md) | Client setup steps vs the staff checklist | 2026-10-14 |
| [D-15](0015-account-links-pages-and-lifetimes.md) | Account links: full pages, lifetimes from the boards, invite end reasons | 2026-10-15 |
| [D-16](0016-train-tab-and-workout-logger.md) | Train tab and workout logger: blocks, saving, Log more sets, discard | 2026-10-15 |
| [D-18](0018-habits-page-week-grid.md) | Habits & supplements page: week grid from the server, water through the water log | 2026-10-15 |
| [D-19](0019-checkins-page.md) | Check-ins page: due Sunday 6 pm, missed rows from the server, photos through the outbox | 2026-10-15 |
| [D-17](0017-train-day-tap-history-pause.md) | Train: day tap, one-exercise history, Use last time, timer stops when leaving | 2026-10-15 |
| [D-20](0020-food-page-photo-offplan-custom.md) | Food page: meal photo with Mark as eaten, off-plan reason, custom food per serving | 2026-10-15 |
| [D-21](0021-progress-tab.md) | Progress tab: one `me/progress/` answer, History endpoint, photos by data URL | 2026-10-16 |
| [D-22](0022-body-measurements.md) | Body measurements: one values map, 12 keys + body fat, coach picks the set | 2026-10-16 |
| [D-23](0023-more-tab.md) | More tab: one account answer, my activity, change lines, export, report, own quiet hours, photos every N weeks | 2026-10-16 |
| [D-24](0024-measurements-in-checkin.md) | Body measurements asked in the photo-week check-in, saved to Progress | 2026-10-16 |
| [D-25](0025-measurements-once-per-period.md) | Measurements: one entry per period, no date chips, edits change it | 2026-10-16 |
| [D-26](0026-client-library.md) | Client Library: notes and sources on shares, New / Done / Saved per client, in-app video | 2026-10-16 |
| [D-27](0027-media-in-app.md) | Media in the app: in-app video, picture zoom, real PDF pages, exercise media, link kind | 2026-10-16 |
| [D-28](0028-youtube-in-app.md) | YouTube plays inside the app (Library + exercise guide), short picture box, demo videos ship with the code | 2026-10-16 |
| [D-29](0029-about-and-home-hero.md) | Client About page reads contact and coach from gym settings; phone Home uses the hero | 2026-10-16 |
| [D-30](0030-trainer-dashboard.md) | Trainer dashboard; one check-in queue so trainer, admin and client numbers match | 2026-10-16 |
| [D-32](0032-trainer-my-clients.md) | Trainer My clients: Next check-in rule, export selected, Edit details, no AV | 2026-10-16 |
| [D-33](0033-input-rules-filter-menu-titles.md) | Fields take only their type (phone, number, kg, email); filter side menu; Export off; tab titles + favicon | 2026-10-16 |
| [D-34](0034-trainer-client-profile.md) | Trainer client profile: 9 tabs, plan / meal / supplement / habit assign, logs, history, forms copies | 2026-10-17 |
| [D-35](0035-trainer-checkins.md) | Trainer Check-ins page: list + review panel, daily check-in view, better / worse colours | 2026-10-17 |
| [D-36](0036-onboarding-coaching-form.md) | Onboarding = the gym's coaching form in 9 steps; answers are profile fields, edited in Edit profile, shown in About | 2026-10-17 |
| [D-37](0037-per-client-swaps-and-supplements.md) | Food swaps per meal item (client copy), supplements get a client copy, adherence counts the followed plan | 2026-10-17 |
| [D-38](0038-trainer-calendar-and-me.md) | Trainer Calendar (week / day, sessions, working hours) and My profile (6 tabs), numbers match the dashboard | 2026-10-17 |
| [D-39](0039-programs-library-and-edit-rights.md) | Programs page + Program builder; a trainer changes only programs they made (or all with Edit gym templates), sees only own clients, Delete has Undo | 2026-10-20 |
| [D-40](0040-exercise-library-rules.md) | Exercises: built-in read-only (Duplicate to edit), custom needs "Add custom exercises", cover upload, YouTube check, Add to program in every week, trainer sees own client counts | 2026-10-20 |
| [D-41](0041-login-panel-and-phone-testing.md) | Web login side panel 40 / 60 with a faded blue; help sheets open at once; real-phone testing (laptop IP, cleartext in debug); Android compileSdk 37 | 2026-10-21 |
| [D-42](0042-real-cover-frames-card-menu-tooltips.md) | Exercise cover frames are real stills (ffmpeg / YouTube), program card ⋯ menu, tooltips on every unclear button | 2026-10-21 |
| [D-43](0043-builder-save-and-assignment-history.md) | Program builder: Save changes / Discard, ask before leaving, week ⋯ menu; assignment Undo leaves no history; Unassigned label; who made a program | 2026-10-21 |
| [D-44](0044-nutrition-rights-food-library-meal-builder.md) | Nutrition & foods: who may change a meal plan, delete Undo, food library rules, Excel import, meal plan builder draft + Publish | 2026-10-21 |
| [D-45](0045-habits-own-items-and-media-in-app.md) | Trainers make and change their own habits and supplement plans; habit editor look; Content videos, pictures and PDFs open inside the app | 2026-10-22 |
| [D-46](0046-client-profile-missing-parts-and-toolbar-rule.md) | Client profile: target date, health over time, stock history, form-check video, body map; toolbars wrap, chip rows scroll | 2026-10-22 |
| [D-47](0047-admin-clients-and-approvals.md) | Admin Clients and Approvals: one Clients page for both roles, admin profile extras (password, change trainer), Add client, invite links, Approvals with review drawer | 2026-10-22 |
| [D-48](0048-admin-trainers-calendar-activity.md) | Admin Trainers, Trainer profile, team Calendar and Activity log: reuse of My profile and trainer Calendar with an admin mode, `?tab=` routes, list filters never touch a trainer's own routes | 2026-10-22 |
| [D-49](0049-client-forms-from-coach.md) | Client fills the forms the coach sends (Check-ins cards + `/checkins/forms/<id>`), admin Check-ins reuse, notification links fixed, PAR-Q stays a Forms form | 2026-10-22 |
| [D-50](0050-admin-forms-and-builder.md) | Admin Forms & check-ins and Form builder: real DB forms (new onboarding questions), drafts on a published form until Publish, how it is sent, answers so far | 2026-10-22 |
| [D-51](0051-admin-automations-and-builder.md) | Admin Automations list and builder: one page for new / edit, nothing saved until Save as draft / Turn on, board trigger settings and text, Not ready list, Last 30 days | 2026-10-22 |
| [D-31](0031-trainer-activity-and-fixes.md) | Trainer Activity card, stat cards fill the row, menus fit the screen, readable guides | 2026-10-16 |
