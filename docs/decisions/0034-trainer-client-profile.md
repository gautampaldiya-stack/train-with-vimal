# D-34 · Trainer client profile (9 tabs)

Date: 2026-10-17

## Decision
- `/clients/<id>?tab=` opens the trainer's view of one client (boards `TrainerClientProfile` + `…Mobile`), code in
  `app/lib/features/trainer/client_profile/` (`cp_*.dart`, one file or more per tab). Only the trainer's own clients
  (`get_visible_client`); another trainer's client is 404.
- Header: breadcrumb, Edit profile (same drawer as My clients → Edit details), Assign plan ▾ (Workout / Meal /
  Supplement / Habit plan), ⋯ (Edit profile details, Assign a plan, Send check-in reminder, Full history). 4 stat cards.
- **Overview**: About (onboarding), Weight trend, Last 7 days, Latest note, Needs attention, Coaching, Current plans,
  Check-ins and schedule (`overview.checkins_schedule`).
- **Plans**: Workout / Meal plan / Supplements / Habits — current card, Up next, Plan history, assign drawer
  (When: after current / next to current / replace / pick a date), workout "Edit for <name>" editor that saves the
  client's own copy (`custom-structure`). New endpoints `clients/<id>/meal-plans/`, `supplement-plans/`, `habit-plan/`.
  A changed day is copied to the same weekday of every later week.
- **Logs**: Workouts, Meals, Daily / Weekly check-ins, Habits, Supplements tables with a shared range (last 7 / 30 /
  90 days or a plan), detail drawers with Previous / Next, a coach comment (in-app message) and review; Compare plans
  (A vs B). Endpoints `clients/<id>/logs/summary|compare|comment/`, `clients/<id>/checkins/`.
- **Progress**: change cards, weight chart, measurements, photos (viewer with compare), personal bests.
- **History**: summary cards, Plans over time chart, Journey by month (chips, Export CSV, Show earlier months).
  Endpoint `clients/<id>/history/`. Goal / goal weight / health note edits are now recorded so history can show them.
- **Content**: what the client sees and why (assigned, from plans, everyone); assign, hide with Undo, remind, "how long".
- **Forms**: onboarding answers (Print), weekly form with "Edit for <name>" = the client's own copy (status `client`,
  never listed with gym forms or picked by automations), Send a form (once or repeating, `send_scheduled_forms`).
- **Activity**: the client's feed (`activity/?client=`) with kind chips and counts; meals, body, content, habit and
  supplement actions now write activity rows. A trainer sees all rows about their client.
- **Notes**: flagged notes first, edit / delete (author or admin only) with Undo (restore is scoped to the client).

## Not built (no data for it yet)
Target date, health changes over time, client form-check videos, device names, supplement stock history, exercise body
map, meal plan per-weekday meals. Open master plan / Open in library go to pages not built yet.
