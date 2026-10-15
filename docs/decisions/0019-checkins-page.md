# D-19 · Check-ins page: due every Sunday 6 pm, missed rows from the server, photos through the outbox

- **Date:** 2026-10-15
- **Status:** Accepted

## Decision
1. The weekly check-in is due every **Sunday at 6:00 pm** (a calendar week, Monday to Sunday), like the board. A
   finished week since the client's start with no weekly check-in is a **Missed** row; a day with no daily check-in
   (before today) is a Missed daily row ("reminder went at 9:00 pm"). Missed rows come from the server
   (`GET me/checkins/?tab=weekly|daily`), so the phone and the web show the same list.
2. "Weekly on time" counts check-ins sent by that week's Sunday 6:00 pm, out of every week that was due.
   "Last weekly change" is the latest weekly weight minus the one before it ("In 2 weeks" when a week was missed).
3. History is paged: 20 rows a page, `before=YYYY-MM-DD` for older rows; the list loads more when it reaches the end.
4. The built-in weekly and daily forms ask what the boards ask (migration `checkins 0002`, only when a form still
   holds the first template; answered questions are hidden, not deleted): weekly = body weight, how was your week,
   meal plan, progress photos, anything your coach should know; daily = morning weight, sleep (5 to 9 h, half hours
   included), energy, mood, hunger, soreness, all required except the note. Help text may say `{coach}`; the API
   puts the coach's first name in.
5. Photos go **with the check-in** as data URLs (`photos: {question id: {front, side, back}}`), so a check-in with
   photos also waits in the outbox when offline. The server saves them as answers and as that week's photo set
   (Progress page), by pose.
6. The weekly draft lives on the phone (read cache, per week) until it is sent; "Draft · N of 5 answered" shows on
   the card.
7. Undo on the "sent" toast deletes the check-in (`DELETE me/submissions/<id>/`), only while the coach has not
   reviewed it and within 24 hours. Edit answers keeps the note unless a new one is sent.
8. Steps and water on a daily check-in come from Habits (steps habit, water log) for that day.

## Why
The board shows missed weeks and days, on-time counts and a change "in 2 weeks", which the app cannot work out
from the sent check-ins alone. The old reminder rule ("a week after the last one") is still what sends the 9 am
reminder; Home's "Coming up" date also still uses it (gap, to align when Home is next touched).

## Not covered
- A question added for one client ("Added for you by Aman", the knee question on the board): forms are shared by
  all clients, so per-client questions need a model change.
- The weekly cells "Workouts" and "Meals on plan" are worked out from the program and meal logs of that week; weeks
  before the demo history show 0.
- The answer suggestions on the last weekly question are fixed board text, not per client.
