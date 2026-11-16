# D-89 · Workout logger rebuilt Strong-style (tracker F33–F43)

Date: 2026-11-16 · Asked by Probid (screenshots in `/mnt/project-files/strong-logger-nov16/` and the Oct-26/27 set).

## Decision
The Oct-28 logger in the backup bundle is not brought back. The logger is built new on today's code, Strong's layout
with our own theme:

- **One page, every exercise.** Top bar: ⌄ (collapse), rest chip, clock, FINISH. Title with ⋯ (Pause / Resume timer,
  Restart). Each exercise: name (tap = How to do it), target line, focus chip, ⋯, rows SET · PREVIOUS · KG · REPS · ✓,
  + ADD SET (text button). Swipe a row left = delete with Undo. **CANCEL WORKOUT** at the end of the list (red text,
  asks first). After "Log more sets" it reads DISCARD ADDED SETS.
- **Start sheet first:** name, "Last performed: 11 November 2026", exercises with sets; the clock starts on
  **Start workout**, not when the page opens.
- **The workout keeps running.** One `WorkoutController` lives for the whole workout (`WorkoutController.live`).
  ⌄, back or a swipe down shows the **mini bar** on every client page (name, clock, current exercise or Rest);
  tap or swipe up opens the logger. Leaving Train no longer pauses the clock (old D-17 rule dropped). App restart:
  `revive()` brings it back from the phone's copy or the server. Exit sheet: "The workout keeps running".
- **Notification (Android):** ongoing, chronometer, exercise + "60 kg × 8 (2 of 4) · set 1 of 4 done", actions
  Complete set / Pause / Skip rest / +30 sec; tap opens the logger. Cleared on Finish, Cancel, sign out. iOS Live
  Activity stays parked.
- **Numbers:** no −/+ steppers. Phone = our own keypad (digits, ., ⌫, −/+, RPE, NEXT, hide); web / tablet = text box,
  Enter ticks. Placeholders flow down from the set above, else last time, else the target; a tick saves them.
- **PREVIOUS:** same set number of the last session; tap fills it and greys it; it goes back to normal when a value
  differs.
- **Set types:** SET box menu: Warm up (W, amber, not in volume / PR), Drop set (D, purple, its own row, counts),
  Failure (F, red), each with a ? info; Use last time; Bodyweight; RPE; Form video; Delete. Picking the same type again
  = normal set. Rest per set is tracker G.
- **Focus metric** chip per exercise (Total Volume, Volume Increase, Total Reps, Weight/Reps), saved per client and
  exercise (`ClientExercisePref`, `PUT me/exercise-prefs/<exercise>/`).
- **Form video** per set, kept on the phone (path survives an app restart), sent only on Finish.
- **Cardio:** `distance_km` removed (old values dropped, Probid), `bpm` logged; coach sets `bpm_min` / `bpm_max` on the
  plan exercise (library builder modal and client plan drawer, 30–250, max ≥ min). Client sees "Target 120–140 bpm".
- **Reopen:** each "Log more sets" is a new segment timed from 0:00; `WorkoutLog.segments` keeps each part and
  `duration_seconds` is the sum (12 + 4 = 16 min).
- **Finish page:** "Congratulations! That's your 13th workout!", workout card (date, time, volume, PRs, sets, each
  exercise with its best set), where the time went, effort, note, Save and send.
- **Client menus:** no Replace / Remove / Superset / Add exercise (clients log, the plan is the coach's).

## Also (F43)
Edit exercise drawer in the client plan editor wrote into the live exercise on every key press. Now it edits a draft
(`ExerciseDrafts`) applied only on Done; closing any other way drops it. The line above its footer is gone
(`showAppDrawer(footerLine: false)`). Test: `app/test/exercise_drafts_test.dart`.

## Data
Migration `training/0008_logger_set_types_bpm_segments`: `ProgramExercise.bpm_min/bpm_max`, `WorkoutLog.segments`,
`SetLog.bpm`, `SetLog.rpe`, `SetLog.set_type` (warm-ups moved from `is_warmup`), `SetLog.distance_km` removed,
`ClientExercisePref`. Tests: `backend/tests/test_logger_f.py`, `test_client_train.py`.
