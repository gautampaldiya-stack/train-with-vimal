# D-14 · Client setup steps vs the staff checklist

- **Date:** 2026-10-14
- **Status:** Accepted

## Decision
The client app asks 5 setup steps, as on the `ClientLogin` / `ClientWelcome` boards:
`goal` (Your goal), `about` (About you), `schedule` (Training days), `health` (Health & injuries), `food` (Food preferences).

Staff boards (`Approvals`, `Clients`) show a different checklist: Account made, Basic details, Goal and body, Health and PAR-Q, Food preferences.
The backend fills the staff checklist from the client steps:

| Staff step | Done when the client finished |
|---|---|
| `account` | set when the account is made |
| `basics` | `about` + `schedule` |
| `goal_body` | `goal` + `about` |
| `health` | `health` |
| `food` | `food` |

So a client who finishes all 5 client steps also shows 5 of 5 to the coach.

## How it is stored
- `ClientProfile.onboarding` = answers per client step (`{"goal": {...}, "about": {...}}`), plus `_remind` for "Finish setup later?".
- `ClientProfile.onboarding_done` = staff step keys (used by filters, dashboard, approvals).
- `POST me/onboarding/ {step, data}` validates each step strictly (options from the board, number ranges from the steppers).
- `DELETE me/onboarding/ {remind: tonight|tomorrow|3days|off}` = Save & leave. The reminder job sends at that time; `off` sends nothing.
- `auth/me/` and the login response carry `user.client = {setup_done, setup_total, coach}` so the app knows where to land.

## Why
Both boards are the design and both must match. Keeping one store and deriving the staff view avoids two sources of truth.
