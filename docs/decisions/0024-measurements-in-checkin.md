# D-24 · Body measurements ride the photo-week check-in

- **Date:** 2026-10-16
- **Status:** Accepted (Gautam chose "Check-in me add")

## Decision
1. In photo weeks (D-23 §8) the weekly check-in gets a **Body measurements** step just before the photos: one row
   per measurement the coach tracks (`measure_keys`, default set), each starting at the last value
   (*"Last 79.5 cm · 15 Oct"*), step 0.5. All optional; only rows the client changes are sent.
2. The step is not a stored question: it goes out as id `-1`, `type: "measures"`, and its answer is
   `{key: number}`. On submit each number is range-checked (cm 10–300, body fat 3–70), kept in the submission's
   `metrics` (so the coach sees it) and merged into that day's `Measurement` on Progress. No double entry.
3. A form that already has a measurement question (metric = waist, …) gets no extra step.
4. Progress "Next measurements are due …" uses the same date as the next photos, and the caption says the
   coach's cadence ("Measured every 2 weeks with your photo check-in").
5. The Log measurements sheet on Progress stays for extra logs (dates: today and three days back).
