# D-17 · Train: day tap, one-exercise history, Use last time, timer stops when leaving

- **Date:** 2026-10-15
- **Status:** Accepted

## Decision
1. **Week strip day tap** loads `me/train/?date=` for that day, like Home. A past day shows Done (time, sets) or Not
   done, a future day "Planned for …", with Back to today. Only today's answer is cached.
2. **Logger → Past workouts is one exercise only** (`GET me/workouts/exercise-history/?exercise=<id>`, paginated,
   completed workouts that have a done set of it). The whole-workout and All view stays on Train → History.
3. **Use last time / Use these sets** fill only the sets not ticked yet, working sets in order; extra past sets are
   added, ticked sets never change. Toast with Undo. Values still need a tick.
4. **The workout timer stops when the client leaves Train and the logger** (any page outside `/train*`). The app
   saves `paused_at` on the phone and sends `POST me/workouts/<id>/pause/` with `at` through the outbox, so the time is
   right even when it is sent later. Opening the logger again (Continue workout) moves `started_at` on by the
   paused time and saves the state. A manual pause is also resumed by Continue.
5. **⋯ on the Train workout banner / bar:** Pause or Resume timer (in place, through the outbox), Finish workout and
   Restart workout (open the logger with `?then=finish|restart`, which asks the same question as in the logger),
   Discard workout (asks first, then `POST discard/`).
6. **Toasts above a bottom sheet:** while a phone bottom sheet is open the toast shows at the top of the screen; the
   sheet no longer grows to make room for it.
7. **Exercise picture.** `thumb` = the video cover, else the YouTube thumbnail of the exercise's link. No picture →
   the icon tile.

## Why
Gautam (2026-10-15): the day strip should work like Home; past sets in the logger should be of the current exercise
with one tap to copy them; time away from Train should not count as workout time.
