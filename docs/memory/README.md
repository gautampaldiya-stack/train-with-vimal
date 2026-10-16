# Project memory

Things a new person (or a new Claude session) must know. Update when Gautam decides something.

- Gautam writes in Hinglish; reply the same way, short.
- Admin is only Vimal. Trainers and clients are many.
- Design canvas (v282, 104 boards) is the source of truth: `design/screens/` and https://claude.ai/artifact/NKNGUZt9ZJMVXwiKXbfhiK.
- Every screen must be responsive (phone, tablet, desktop) and match the canvas exactly. Phone layout only under 600 (never on tablet); layouts must hold while a browser window is resized (D-11).
- Login = email or mobile, with password.
- Messages now: email + in-app + push + realtime. WhatsApp/SMS later via `.env`.
- No SaaS / independent coaches.
- Client Food tab = combined `ClientMealNutrition` page (`/food`); `ClientFood` / `ClientNutrition` boards are replaced. Mark as eaten is a dropdown with an optional photo; web keeps tabs fixed and scrolls only the meal cards; every stepper number can be typed (Gautam, 2026-10-15).
- Meal photo: picking a photo never logs the meal; the photo waits on the card (change / remove) and a separate Mark as eaten logs it. Copy yesterday has Undo. Grey tab bars (MoTabs / PxTabs / TwoTabs) are label-width at every width, phone too (Gautam, 2026-10-16). Extras logged to a meal show inside that meal card (Gautam, 2026-10-16).
- Store data in full detail as the screens show.
- Client logs (food, workouts, habits, water, check-ins) must work offline and sync later without duplicates.
- Git: `working` → `develop` → `main`. Commits by Gautam only, no Claude names. Claude pushes, Gautam pulls and tests.
- Demo logins after `seed_demo`: vimal@trainwithvimal.com (admin), aman@trainwithvimal.com (trainer), riya@example.com (client); password `Demo@1234`.
- Deadline: working build by Saturday 2026-10-17.
- Gautam (2026-10-15): never leave part of a flow unbuilt without saying so. Build every page a flow's buttons,
  links and emails open; keep `docs/screens/status.md` current; name unbuilt boards in notes and replies.
  Rules: `docs/rulebooks/definition-of-done.md`.
- Gautam (2026-10-15): on tablet and web (≥ 600) toasts sit at the bottom right, not centred like the web boards.
  Phone keeps them centred and full width (12 from each edge); tablet / web toast is 400 wide.
  Undo toasts stay 10 s. No profile avatar (RS) on the client Home top, phone or web. Also: write even small changes into the docs (`docs/changes.md` + the doc they touch).
- Gautam (2026-10-15): phone toasts go to the top while a bottom sheet is open. Running workout has ⋯ (Pause/Resume, Finish, Restart, Discard) on Train.
- Gautam (2026-10-15): Train week strip days tap like Home; logger Past workouts = this exercise only, one tap fills past sets; workout timer stops when leaving Train / logger, goes on with Continue (D-17).
- Gautam (2026-10-15): bottom nav padding top 4, bottom 12 (his code). Do not gender trainers in app text ("You will usually get a reply").
- Check-ins (2026-10-15): weekly check-in due every Sunday 6:00 pm; built-in weekly / daily forms ask the boards' questions; photos go with the check-in through the outbox (D-19).
- Progress (2026-10-16): one `me/progress/` answer, chart range filtered on the phone, goal date from the last 8 weeks' pace, History is its own paged endpoint, photos go as data URLs through the outbox (D-21). Habits Day / Week tabs = board size (Gautam).
- Measurements (2026-10-16): Gautam chose client logging now; 12 measurements + body fat as one values map, coach picks the set (default waist, hips, chest, biceps, body fat); picker comes with trainer screens (D-22).
- More tab (2026-10-16): built (D-23). Past-day or edited weight / measurement must leave its own "You changed … for <day>" line in My activity (Gautam). Photos every 2 weeks (`photo_every_weeks`); in photo weeks the weekly check-in also asks the coach's measurements and saves them to Progress (Gautam chose "Check-in me add", D-24).
- Gautam (2026-10-16): measurements = one entry per period (photo cadence), no date chips, re-log edits it (D-25). Web My account has no Your plan card. Coach Details has no Open check-ins; shows daily check-in. Height editable in Edit profile. History web: top + summary fixed, list scrolls.
