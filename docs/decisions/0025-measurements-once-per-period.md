# D-25 · Measurements: one entry per period

- **Date:** 2026-10-16
- **Status:** Accepted (Gautam chose "Period me ek baar")

## Decision
1. A client has **one measurement entry per period**. The period is the photo cadence (`photo_every_weeks`, default
   2): an entry stays "this period's" until the Monday N weeks after its week. `services.measure_entry()`.
2. Logging again in that period (Progress sheet or check-in) **changes that entry**; it never adds a second one.
   The change leaves a line in My activity ("You changed measurements for Thu, 15 Oct · Chest 92 → 91 cm").
3. The Log measurements sheet has **no date chips**: it says "This period · logged Thu, 15 Oct · next one due
   Sun, 1 Nov" or "New entry · Today". Under the steppers, **Your entries** lists the last four entries with dates.
4. The photo-week check-in asks for measurements only when this period has no entry yet (D-24).
5. "Next measurements are due" = the Sunday N weeks after the current entry's week (`next_measure_due`).
6. History (Weight filter) shows each entry as "Measurements · 6 logged" with the change since the entry before.
