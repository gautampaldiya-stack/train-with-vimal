# D-18 · Habits & supplements page: week grid from the server, water through the water log

- **Date:** 2026-10-15
- **Status:** Accepted

## Decision
1. `GET me/habits/?date=` returns the Mon–Sun week of that date as `week` (day states done / part / missed / today /
   coming, totals, best current streak) and a 7-cell `week` per habit and supplement (done / missed / today / coming /
   off). Totals count days up to yesterday, plus today only when already done, like the board ("10 of 13").
2. A habit whose assignment starts later has `starts_on`; it shows as a dashed card with a "Starts …" pill and its
   grid cells are off. Its "Remind me" button turns on the client's habit reminders (`me/reminders/` `habit`).
3. Water on this page uses `POST me/food-log/water/` (same as the Home water card); the server moves the water habit.
4. Supplements are grouped Morning (breakfast, morning) · After training · Any time · Night (night, before bed),
   with default times 8:00 am and 10:30 pm in the group line until a per-client time exists.
5. The subtitle reads "Daily habits · <supplement plan> · set by <coach>": there is no habit-set name in the data.

## Why
The board's Day and Week views need per-day states the app cannot work out from one day's answer, and the water
habit must match the water card.
