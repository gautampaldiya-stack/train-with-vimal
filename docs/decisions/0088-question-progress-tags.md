# D-88 · Progress tags on form questions

Date: 2026-10-31 · Asked by Probid.

## Decision
Any form (daily / weekly check-in, survey, any form a coach sends) can feed Progress. In the question editor a
**Progress tag (optional)** dropdown sets `Question.metric`:
- Number questions: Weight (kg) → weigh-ins (`WeightLog`, source checkin, also the profile's current weight);
  Height (cm) → `ClientProfile.height_cm`; Body fat, Muscle mass and body sizes → `Measurement`; Sleep (hours).
- 1–5 scales: Energy, Mood, Hunger, Soreness, Sleep.
- Other answer types have no tag.
A new number question whose text says "weight" or "height" gets that tag on its own (it can be set back to None).
The question row shows "Tag: Weight (kg)". So a coach who wants weight weekly, or only now and then, puts a tagged
Weight question in that form; the Home Progress card and the Progress page read the saved values.
Before this, only 7 seeded questions had a tag and the builder could not set one.
