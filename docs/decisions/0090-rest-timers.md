# D-90 · Rest timers per exercise, per set type and per set (tracker G44–G50)

Date: 2026-11-16 · Asked by Probid ("aage ka G ka kaam start kar do").

## Decision
- **Three rests per exercise:** Working, Warm-up, Drop (seconds, 0–900; 0 = Off). Coach sets them in the plan builder
  (`ProgramExercise.rest_seconds`, `rest_warmup_seconds`, `rest_drop_seconds`; warm-up / drop null = same as working).
- **Client default:** exercise ⋯ → Rest timers. Changes today's workout at once and is saved per client and exercise
  (`ClientExercisePref.rest_work / rest_warmup / rest_drop`, `PUT me/exercise-prefs/<exercise>/`), so it is the default
  for the next workouts until changed. A client pref beats the plan; a per-set value beats both.
- **Per set:** set menu → Rest timer for this set (`SetLog.rest_seconds`). Shown as a thin line under each set; tap =
  editor, swipe left = Off with Undo.
- **Lock:** coach toggle "Lock rest" (`ProgramExercise.rest_locked`). Locked = client sees the rests read-only, the
  server answers 409 `rest_locked`. The 28 Oct answer was "no lock", tracker G47 says lock: built with lock, Probid's
  answer pending on the card. If "no lock", remove the toggle and the check.
- **Running:** a tick starts the rest of that set by end time (`_restEnds`), so sleep or app restart keeps it right
  (saved in `workout:live`). Strong-style sheet: ring, −15 / Pause / +15, Reset, Skip, Next up, X hides. Mini bar
  shows Rest on other pages. Android: exact alarm notification when the rest ends (needs an APK).
- **History:** each set stores `rest_planned` and `rest_actual` (seconds); client past workout and coach Logs show
  "rest 1:45 / 2:00".
- **Sound / haptics:** tick = medium haptic + click, rest end = heavy haptic + alert. More → Workout sound & vibration
  (saved on the phone). System sound follows the phone's silent mode.

Migration: training 0009 (run `migrate` on deploy).
