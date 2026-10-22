# D-48 · Admin Trainers, Trainer profile, team Calendar and Activity log

Date: 2026-10-22

## Decision
- **Trainers page** (boards `Trainers` / `TrainersMobile`, route `/trainers`). Stats from `trainers/summary/`
  (Active trainers, Client spots, Check-ins to review with who has the most, Avg adherence with the change vs last
  week). Tabs All / Active / Full / Inactive, search, Filter (Access, Space, Speciality, Check-ins) with chips,
  20 a page, owner first. Row ⋯: Open profile, Access and permissions, Edit details, Move clients, Deactivate or
  Reactivate. Drawers: Add trainer, Deactivate (move clients: share out, to one trainer, or keep), Move clients,
  Assign clients (only as many as free spots, "Tell the clients", "Keep their plans").
- **Trainer profile** (boards `TrainerProfile` / `TrainerProfileMobile`, route `/trainers/<id>`). It reuses the
  trainer's own My profile tabs (`features/trainer/me`) with an admin mode, so one code path serves both: texts name
  the trainer ("About Aman", "Clients who need him"), Edit details adds Work (most clients, joined on) and Login
  (send a reset link), documents get "Mark as verified". Extra admin tabs: Clients (search, Status, Goal, Move to
  another trainer) and Access and permissions (levels from the server's presets, changed rows in amber, Save).
- **Routes use `?tab=`** (`/trainers/<id>?tab=access`, `&assign=1` opens Assign clients) because the router only
  has `/:section` and `/:section/:id`. Notification and dashboard routes were changed to this form.
- **List filters never touch a trainer's own routes.** `trainers/<pk>/…` ignores the list's search and filters;
  before this, searching in the profile's Clients tab looked for a trainer with that name and gave 404.
- **Team Calendar** (boards `Calendar` / `CalendarMobile`, route `/calendar` for admin) is the trainer calendar with
  `admin: true`: All trainers pick with counts, trainer first name on blocks, Busiest trainer stat, no shading on
  All trainers (shading follows the picked trainer), Trainer row in the session panel, New session with Client and
  Trainer (the client's trainer is picked; warnings name the trainer), Availability drawer per trainer.
- **Activity log** (boards `Activity` / `ActivityMobile`, route `/activity`): search (new `search` filter on
  `activity/`), Filter Who / Person, range menu, kind chips with counts, day groups with full day counts, 20 a page
  with Show more (the board shows 8; 20 is kinder for a log that grows fast), Export CSV of what the filters show.
- Sessions that start before 6 am are pinned to the top of the grid; lanes now use where a block shows, so two such
  blocks sit side by side instead of on top of each other.

## Why
Gautam (22 Oct): "ab aage trainer, calender and activity logs... banado... unme ache se check kar dena".

## Not built (still holding page)
Forms & check-ins, Automations, Emails & alerts, Settings (admin). Check-ins for admin.
