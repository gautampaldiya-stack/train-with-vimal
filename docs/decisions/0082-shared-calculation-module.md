# D-82 · Phase 1: one calculation module for every number

**Date:** 2026-10-29 · **Asked by:** Probid (batch 1, Phase 1: "numbers are currently inaccurate… calculation
correctness is top priority"; approved the plan: "done karo")

## Root causes found
1. **Food totals drifted.** `Food.per_grams` rounded every logged food (kcal to a whole number, macros to 1 decimal)
   before it was saved, and day / meal totals added the rounded values. Ten foods of 52.4 kcal showed 520, not 524.
2. **Food diary cut totals down.** `staff_food_log` (client profile → Logs → Meals) used `int()` on the day sum, so
   1799.6 kcal showed 1799, not 1800.
3. **Three volume formulas.** `services.set_volume` (body weight on the day), `SetLog.volume` (bodyweight sets = 0,
   unused) and the app's live logger. Server screens already used the first; the second is removed.
4. **Records** had only "heaviest set"; no best session volume, no estimated 1RM.

## Decision
`backend/apps/common/calc.py` holds every formula, each documented in its docstring and tested in
`tests/test_calc.py` (21 tests, real numbers):

| Number | Formula |
|---|---|
| Set volume | (weight [+ body weight that day for a bodyweight set]) × reps. Warm-up, not done, 0 reps, cardio / timed = 0. No body weight recorded → only the added load counts |
| Session volume | Σ set volume |
| Duration | finished − started − paused + Σ later segments, whole seconds, never < 0 |
| Rest taken | next set start − this set done; None if one is missing; never < 0 |
| e1RM | Epley: weight × (1 + reps / 30); 1 rep = weight |
| Records | heaviest done working set, best session volume, best e1RM (each with its date) |
| Nutrition total | Σ stored unrounded values of eaten entries (skipped meals have no entries) |
| Calories check | 4 kcal/g protein, 4 carbs, 9 fat; "Calories match" within 15 kcal or 10 % |
| Showing | kcal whole, grams 1 decimal, half up (`show_kcal`, `show_g`) |

- `FoodLogEntry.kcal / protein / carbs / fat` are `DecimalField(decimal_places=3)` (migration
  `nutrition.0008_food_log_unrounded`, reversible). Old rows keep their values; nothing is deleted.
- The API still sends whole kcal and 1-decimal grams per entry, so the app needs no change; totals are added from the
  unrounded values and rounded once.
- Body weight for a bodyweight set: the weigh-in on the workout day, else the last one before it
  (`services.body_weights`).
- Rest per set and timed "added later" segments are not stored yet; the formulas are ready for Phases 7, 11 and 12.

## Checked
- `tests/test_calc.py`: 21 passed. Full suite with a fresh database: all pass except two that need this PC's real
  FCM key and local video tools (`test_push_test_command_reports_each_device`, `test_cover_frames_…`).
- Vikram Singh (demo): food 12–16 Oct client app = admin diary (1701, 1339, 1960, 1157, 1960 kcal); workouts
  12–15 Oct admin list = client detail (6218, 5518, 7538, 4778 kg). Screenshots: `docs/screenshots/batch1/phase1/`.
