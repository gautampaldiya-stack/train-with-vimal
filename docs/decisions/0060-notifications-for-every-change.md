# D-60 · Notifications for every change, live socket that survives, admin My profile

**Date:** 2026-10-24 · **Asked by:** Probid ("achive kiya assign kiya change kiya to notifications aane chahiye",
"client ka personal best… plan khatam… workout chhod dena", "toast aaya hi nahi", "admin khud ki details ka page
kaha hai", "localhost ka link kyu de raha hai")

## What was decided
1. **Live toast fix.** The app's socket reconnected with the access token it got at login. Tokens last 15 min,
   so after any drop (deploy, `restart web`, wifi, sleep) it never came back: no toast, no live bell, lists only
   changed on a page change. Now every (re)connect asks `Api.freshAccess()` (refreshes when under a minute is left).
   A refresh that fails because the server is down no longer logs the person out (only a refused refresh token does).
2. **Coach hears about their client** (`coach_notice`, bell; push where marked; never the admin unless the admin is
   that client's trainer or `owners`):
   - Daily check-in sent (bell only, Me → Notifications → New check-in; Undo removes it).
   - New personal best (bell).
   - Goal weight reached (bell + push, once per goal).
   - Missed yesterday's planned workout (bell, 9 am, Missed workouts switch).
   - Plan ends within 7 days (bell + push, 9 am, once per plan).
3. **Client hears when the coach changes the plan** (`tell_clients`, bell + push; "Coach updates" mutes the push):
   workout plan updated in the builder (once a day), plan reset to master, workout / meal plan ended, habit or
   supplement removed (drawer or Plans → End). Assigning already told them.
4. **Admin news:** a trainer sets their password from the invite → "Neha joined the team"; a client added by the
   coach sets up their account → their trainer and the admin; a client asks to delete their account → trainer and
   admin (bell + push).
5. **Links in emails** use the live site in production: `config/settings/prod.py` defaults `FRONTEND_URL` to
   `https://twv.prowavetech.in` (it was `localhost:5173` when `.env` had no `FRONTEND_URL`).
6. **Admin My profile** at `/me` (the trainer's My profile; the admin is a trainer too, D-57) without the
   "My access" tab: sidebar Workspace → My profile, dashboard account menu → My profile, More → the top card.

## Checked
Backend tests: `tests/test_coach_notices.py` (8), `tests/test_client_checkins.py` (3 new), full suite green.
Browser (debug, 1-minute tokens): Riya logged in, waited past expiry, API restarted → the socket came back with a
refreshed token. Admin `/me` at 1280.
