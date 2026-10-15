# Project memory

Things a new person (or a new Claude session) must know. Update when Gautam decides something.

- Gautam writes in Hinglish; reply the same way, short.
- Admin is only Vimal. Trainers and clients are many.
- Design canvas (v282, 104 boards) is the source of truth: `design/screens/` and https://claude.ai/artifact/NKNGUZt9ZJMVXwiKXbfhiK.
- Every screen must be responsive (phone, tablet, desktop) and match the canvas exactly. Phone layout only under 600 (never on tablet); layouts must hold while a browser window is resized (D-11).
- Login = email or mobile, with password.
- Messages now: email + in-app + push + realtime. WhatsApp/SMS later via `.env`.
- No SaaS / independent coaches.
- Client Food tab = combined `ClientMealNutrition` page.
- Store data in full detail as the screens show.
- Client logs (food, workouts, habits, water, check-ins) must work offline and sync later without duplicates.
- Git: `working` → `develop` → `main`. Commits by Gautam only, no Claude names. Claude pushes, Gautam pulls and tests.
- Demo logins after `seed_demo`: vimal@trainwithvimal.com (admin), aman@trainwithvimal.com (trainer), riya@example.com (client); password `Demo@1234`.
- Deadline: working build by Saturday 2026-10-17.
- Gautam (2026-10-15): never leave part of a flow unbuilt without saying so. Build every page a flow's buttons,
  links and emails open; keep `docs/screens/status.md` current; name unbuilt boards in notes and replies.
  Rules: `docs/rulebooks/definition-of-done.md`.
