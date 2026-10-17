# D-35 · Trainer Check-ins page

Date: 2026-10-17

## Decision
- `/checkins` (boards `TrainerCheckins` + `…Mobile`), code `app/lib/features/trainer/checkins/`. Web: list (360) +
  open check-in; phone: list, a tap opens `/checkins/<id>` in the same card. One controller is shared so Back keeps
  the tab, type and rows.
- API `checkins/` (cursor, `tab`, `kind`, `search`), `checkins/counts/` (+ `oldest`, `kinds` per tab),
  `checkins/<id>/` opens from any tab (the tab filter is for the list only), `review/`, `unreview/`.
- Review panel numbers: weekly / monthly = Weight, Change, Workouts, Meals on plan; **daily = Sleep, Energy, Workout,
  Steps** with that day's answers against the previous daily check-in. Each number and answer carries `trend`
  (`up` better = green, `down` worse = red; lower is better for hunger, soreness, stress; weight change is better
  when it moves toward the goal weight).
- Mark reviewed (with or without a reply) → toast with Undo; on To review the next one opens. The sidebar count, the
  dashboard and this page read the same counts.
