# D-38 · Trainer Calendar and My profile

Date: 2026-10-17

## Decision
- **Calendar** (`/calendar`, boards `TrainerCalendar` + `TrainerCalendarMobile`): Week / Day views of the trainer's own
  sessions, 4 stats (Sessions this week, Done, On a call, Working days — counted for the shown week only), kind legend,
  outside-working-hours stripes, now line. Session panel: Open profile · Reschedule · Mark as done / not done · Cancel
  session (confirm) + Undo. New session / Move session drawer with a live clash check (`sessions/check/`, `exclude`).
  My working hours drawer (defaults when none saved). The calendar uses the board's full drawer, not the dashboard's
  small New session modal; both post to `sessions/`. `Session.call_link` is text; new `length` and `client_plan`
  (migration `scheduling/0002`). No avatar top right on web (as on the dashboard).
- **My profile** (`/me`, `/me/<tab>`, boards `TrainerMe` + `TrainerMeMobile`; `TrainerProfile` is the admin's view of a
  trainer, built later with admin screens). Tabs Overview · Documents · What clients see · My access · My activity ·
  Account. Stats come from the same queue and counts as the dashboard and the admin Trainers table (D-30, test).
  Documents upload / view / replace / delete; What clients see = 9 toggles + live preview; Ask for more access sends a
  real request; activity paginated (8, Show more); devices (5 a page, Log out / Log out of all others); 6 notification
  toggles (`trainers/0002_trainer_notify` for Daily summary and Gym news). Edit my details: mobile 10 digits, email
  change through `auth/email/change/` (confirm link), experience in years.
- Fix: admin Trainers table average adherence is no longer weighted by waiting check-ins (Aman 50 % → 56 %, same as
  everywhere else).

## Update 2026-10-18 (Gautam's feedback)
- **Daily summary**: beat task `daily-summaries` at 8:00 gym time (board text "Email at 8:00 am with your day"). Every
  trainer with the toggle on gets one message a day — bell, push and email per their push / email settings — e.g.
  "Today: 3 sessions, 5 check-ins to review, 2 clients need you", opening the Dashboard. Counts come from the
  dashboard's own functions. `apps/notifications/staff.py`.
- **Gym news**: new `GymNews` model (`notifications/0003_gym_news`), `GET/POST gym-news/` (admin only, paginated).
  Posting sends it to active trainers with Gym news on (bell + push). The admin screen to post comes with admin screens.
- **Documents**: drag and drop on web/desktop (`desktop_drop`), any PDF/JPG/PNG on phones (`file_picker`), PDF pages in
  the viewer with page nav and zoom 50–300 % (`pdfrx`; falls back to the file card if a PDF can't be drawn).
- Your access card redesigned (switched-on bar, clients you see, asked for).

## Not built yet
- Admin "post gym news" screen (with admin screens).

## Why
Gautam (17 Oct): "saath me next screens build kar dena.. Agla: Trainer Calendar, phir My profile."
