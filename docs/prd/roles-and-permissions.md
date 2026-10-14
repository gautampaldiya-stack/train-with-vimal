# Roles and permissions

## Admin (Vimal)
- Exactly one admin. Sees and changes everything.
- Also coaches clients (has a trainer profile marked *owner*), so he appears in trainer lists.

## Trainer
Access mode, set by Admin on Trainer profile → Access:

| Mode | Sees |
|---|---|
| Assigned clients (default) | Only clients assigned to them |
| All clients | Every client in the gym |
| Custom | Picked permissions from the catalog |

Permission catalog (`backend/apps/trainers/permissions_catalog.py`) covers: viewing/assigning clients, creating programs and meal plans,
check-in review, content, sessions, approvals. A trainer can ask for more access (**Access request**); Admin approves or declines.

Role matrix (Settings → Roles & permissions) sets defaults for the whole trainer and client role:
view all / assigned clients, assign clients, create plans, check-ins, manage content, schedule sessions, add trainers, automations & settings.

## Client
- Sees only their own data, through `/me/...` endpoints.
- Logs: workouts, sets, food, water, habits, supplements, weight, measurements, photos, check-ins.
- **Never changes their plan.** Can pick between options the coach allowed (meal option, approved swaps, portions).

## Rules enforced on the server
- Every client lookup goes through `visible_clients(user)`. A client the user cannot see returns **404**, not 403.
- Trainer-only and admin-only routes check role + permission on every request.
- Deactivated trainers and paused/rejected clients cannot log in; their sessions are revoked.
