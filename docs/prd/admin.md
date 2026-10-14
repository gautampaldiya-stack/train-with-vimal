# Admin area

Sidebar: Dashboard · Clients · Approvals · Trainers · Calendar · Activity log — *Build:* Programs · Exercises · Nutrition & foods ·
Habits & supplements · Forms & check-ins · Content library — *Engage:* Automations · Emails & alerts — *Workspace:* Settings.
Phone: bottom nav + More page (`AdminMoreMobile`). Behaviour: `../screens/behaviour.md` §2.

| Screen | Board | What it does | API |
|---|---|---|---|
| Dashboard | `AdminDashboard(Mobile)` | Glance tiles (clients, trainers, check-ins to review, onboarding pending, nutrition plans pending, programs ending), needs-action list with dismiss, team load, recent activity | `dashboard/admin/`, `dashboard/dismiss/` |
| Clients | `Clients(Mobile)` | Table with tabs (all / active / at risk / paused …), filters, search, export, bulk actions, add client | `clients/` |
| Client profile | `ClientProfile(Mobile)` | Overview, plans, logs (workouts, meals, habits), progress, check-ins, notes & flags, sessions, settings | `clients/<id>/…` |
| Approvals | `Approvals(Mobile)` | Waiting sign-ups: approve with trainer, reject with reason, ask for info, move back | `approvals/` |
| Trainers | `Trainers(Mobile)` | Team table, capacity, adherence, add trainer, deactivate (move clients), reactivate, reset password | `trainers/` |
| Trainer profile | `TrainerProfile` | Profile, clients, access, public card visibility, documents (expiry), stats | `trainers/<id>/…` |
| Calendar | `Calendar(Mobile)` | Sessions across the team, clash check, working hours | `sessions/`, `availability/` |
| Activity log | `Activity(Mobile)` | Everything that happened, filter by person/kind/date | `activity/` |
| Programs + builder | `Programs`, `ProgramBuilder` | Program library; builder with weeks → days → exercises, supersets, copy week, assign | `programs/` |
| Exercises | `ExerciseLibrary`, `ExerciseDetail`, `ExerciseAdd` | Built-in + team exercises, facets, how-to, form cues, video | `exercises/` |
| Nutrition & foods + builder | `Nutrition`, `MealPlanBuilder` | Foods (built-in, team, imported, client), Excel import with undo, meal plans with options and swaps, publish | `foods/`, `meal-plans/` |
| Habits & supplements | `Habits(Mobile)` | Habit library, supplement plans, assign | `habits/`, `supplement-plans/` |
| Forms & check-ins + builder | `Forms`, `FormBuilder` | Forms by type, question builder, publish, send/request, answers | `forms/`, `checkins/` |
| Content library | `Content(Mobile)` | Videos, articles, PDFs, images, categories, share | `content/`, `content-categories/` |
| Automations | `Automations`, `AutomationNew`, `AutomationBuilder` | Trigger → steps, 7 starters, turn on/off with readiness check, runs | `automations/` |
| Emails & alerts | `Emails(Mobile)` | Message templates, channels, team alerts | `message-templates/`, `team-alerts/` |
| Settings | `Settings(Mobile)` | Gym info, branding, roles & permissions, integrations, account, sessions | `gym/…`, `settings/…`, `auth/…` |
