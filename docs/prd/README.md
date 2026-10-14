# PRD — Train With Vimal

## Product
One gym's coaching app. Vimal (owner) runs the gym, trainers coach clients, clients follow plans and log what they do.
Platforms: Android, iOS, web. Every screen works on phone, tablet and desktop.

## Roles
| Role | Who | Can |
|---|---|---|
| Admin | Vimal only (exactly one) | Everything: team, all clients, approvals, plans, automations, settings, branding, activity log |
| Trainer | Gym coaches | Their own clients (or more, if Admin widens access), programs, meal plans, check-ins, sessions, content |
| Client | Gym members | Log workouts, food, water, habits, supplements, weight, photos, check-ins. Never edits their own plan |

## Detailed specs
| File | About |
|---|---|
| [roles-and-permissions.md](roles-and-permissions.md) | Who can see and do what |
| [auth-and-onboarding.md](auth-and-onboarding.md) | Login, joining, approvals, onboarding |
| [admin.md](admin.md) | Every admin screen |
| [trainer.md](trainer.md) | Every trainer screen |
| [client.md](client.md) | Every client screen |
| [notifications.md](notifications.md) | Push, email, realtime, reminders, automations |

## Modules (all in scope for v1)
- **Auth** — login by email or mobile + password, forgot/reset, sessions list with sign-out, invite links, approvals.
- **Team** — trainers list, add/edit, access (assigned / all / custom), public card visibility, documents with expiry, access requests, deactivate with client move.
- **Clients** — list with filters, profile, notes and flags, onboarding (5 steps + PAR-Q), at-risk detection, adherence.
- **Training** — exercise library (built-in + team), programs (weeks → days → exercises, supersets), assign, per-client custom copy, live workout logging with PRs, rest timer, offline sync.
- **Nutrition** — food library (built-in IFCT, team, imported Excel, client's own), meal plans with meals → options → items, swaps, publish, client day view (eat / skip / swap / portions), quick add, water.
- **Check-ins** — form builder (weekly, daily, survey, waiver, PAR-Q), send/request, review queue, progress (weight, measurements, photos).
- **Habits & supplements** — habit library, supplement plans, daily tick/counter.
- **Content** — videos, articles, PDFs, images; share to clients; view progress.
- **Scheduling** — sessions with clash check, availability, client view.
- **Automations** — trigger → steps (send form, message, wait, task); 7 starters; runs log.
- **Notifications** — in-app, realtime (WebSocket), push (FCM), email. Reminders for workouts, meals, check-ins, habits, onboarding, documents. WhatsApp/SMS later (keys in `.env`).
- **Dashboards** — admin, trainer, client home.

## Out of scope
Independent coaches / SaaS / multi-gym, payments and payouts, WhatsApp and SMS sending (until keys are added).

## Non-functional
- Built for heavy data: paginated lists, indexed filters, annotated counts, nightly stat refresh.
- Strong security: argon2, JWT with server-side sessions, scoped querysets (wrong id = 404), throttled auth, validated uploads.
- Offline-first client logging (see `../decisions/README.md` D-07).
- Deadline for first working build: Saturday 2026-10-17.
