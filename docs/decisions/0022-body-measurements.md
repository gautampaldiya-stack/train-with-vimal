# D-22 · Body measurements: one values map, coach picks the set

- **Date:** 2026-10-16
- **Status:** Accepted (Gautam chose "Client side now")

## Decision
1. **One map, not columns:** `Measurement.values` (JSON) holds any of `neck, chest, abdomen, waist, hips, bicep_l,
   bicep_r, thigh_l, thigh_r, calf_l, calf_r` (cm, 10–300) and `body_fat` (%, 3–70). One row per client per day.
   Weight stays in weigh-ins. The list and order live in `apps/checkins/models.py` `MEASURES`.
2. **Coach picks the set:** `ClientProfile.measure_keys`; empty = waist, hips, chest, bicep L / R, body fat.
   The Progress tab shows the tracked set plus any key already logged (`measures[{key,label,unit,tracked}]`).
3. **Client logs:** `POST me/measurements/ {date, values}` merges into that day's row; a `null` value removes the key;
   an emptied row is deleted (204). Future dates are refused. The app sends it through the offline outbox and Undo
   posts the old values back.
4. **Check-ins feed it:** a check-in number question whose metric is a measurement key is range-checked and copied
   into that day's measurement on submit.
5. **Left / right as a pair:** the app shows `bicep_l` + `bicep_r` as one row "Bicep L · R", "28.5 · 28.5 cm".
6. **Migration:** old columns copied into `values` (arm → both biceps), then dropped.

## Later (trainer screens)
- The coach's checkbox picker for `measure_keys`.
- A measurement block in the check-in form builder.
