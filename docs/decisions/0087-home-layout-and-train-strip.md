# D-87 · Phase 6: Home cards, Edit home, simpler Workout card, Train strip

Date: 2026-10-30 · Batch 1, Phase 6 · Plan OK'd by Probid (Claude Doc "Phase 6 plan: Home and Train").

## Decision
- **Edit home on Home itself, no new page** (Probid's doc comment). "Edit home" at the bottom of Home turns the same
  page into edit mode: each card has a drag handle and ✕; "Add card" (a sheet) puts a removed card back; Done saves,
  Cancel drops the change. Done / Cancel sit at the top and the bottom of the list. Outside edit mode nothing drags.
- **Cards in the layout:** workout, checkin, food, progress, adherence, water, rest_timer. Habits, Supplements, the
  coach note and Coming up stay fixed after them.
- **Saved in the database** (`ClientProfile.home_layout`, `PATCH me/home/layout/`, through the outbox so it works
  offline), so the order is the same on every device. Empty = the default order.
- **Rest timer card: web only** (Probid: not needed on the phone). It shows while a rest runs in the workout
  (`WorkoutController.liveRest`), counts down and has "Back to workout".
- **Workout card:** no exercise list or progress bar; one button, Start workout (opens the logger on today's day) or
  Continue workout once one has started.
- **Daily check-in card:** "Not filled yet · N questions · by 9:00 pm" + Fill now (opens the daily form); after
  sending "Sent ✓ · 8:10 am" for the rest of the day. Hidden when there is no published daily form.
- **Progress summary:** weight, body fat, best lift (same numbers as the Progress page) and muscle mass only when
  measured, each with the change since the start; 2 × 2.
- **Weekly adherence:** daily check-ins sent Monday to today ("2 of 5 days checked in") and a bar.
- **Train strip:** weekday + date only, no workout names (rest / done shown by the mark).
- **Logger:** the "Load: kg / Bodyweight" switch above the sets is gone; the per-set Bodyweight switch stays.

## Open
- Check-ins stay under More (no bottom-nav change); per-client card switches come in Phase 18.1.

## 31 Oct: Progress card tabs and adherence %
Probid asked for accurate numbers and where they come from. The Progress card now has tabs, all since the start:
- **Weight:** latest weigh-in vs start weight (profile, else first weigh-in), goal and kg to go. Source: `WeightLog`
  (daily / weekly check-in, Progress → Log weight). Same as the Progress page.
- **Body fat:** first vs latest `Measurement.body_fat`; fat mass = that day's weight × body fat %.
- **Muscle:** `Measurement.muscle_mass` (new measurement, kg, from a body-composition scale or the coach; off until the
  coach tracks it). Without it: lean mass = weight × (1 − body fat %), labelled as worked out.
- **Strength:** overall % = the average change of every exercise lifted with weight on 2+ days, each one's best
  estimated 1RM (Epley, `calc.e1rm`) on its first day vs its latest day; top 3 lifts listed. The single "Barbell
  Bench Press" cell is gone.
- **Weekly adherence:** big % (daily check-ins sent ÷ days Monday to today) with "N of M days checked in".
