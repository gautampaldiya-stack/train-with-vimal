# Notifications, reminders and automations

## Channels
| Channel | When | Status |
|---|---|---|
| In-app | Always (bell + list) | Done |
| Realtime | App open (WebSocket) | Done |
| Push | App closed (FCM: Android, iOS, web) | Backend done; needs Firebase project + keys |
| Email | Per template | Done (console in dev, SMTP in prod) |
| WhatsApp / SMS | Later | Wired as `console` until keys are added |

Users choose channels per kind (client: workouts, meals, check-ins, habits, messages; staff: per team alert).

## Reminders (Celery beat, every 15 min, user's local time)
Workout of the day · meals · check-in due · habits · onboarding not finished · trainer document expiring.
Each reminder goes out once per window (`ReminderLog`). Nightly: client stats refresh and at-risk detection; plan roll-over;
stale workouts auto-saved; deleted rows purged after 30 days.

## Automations (Admin)
Trigger → steps. Triggers include client approved, plan starts, form sent/answered, goal weight reached, inactive N days,
missed check-ins, package ending. Steps: send form, send message, wait, create trainer task.
"Stop when the client responds" ends a run early. Starters: 7 ready-made flows (e.g. client onboarding).
An automation can only be turned on when it has no problems ("Not ready to turn on" lists them).
