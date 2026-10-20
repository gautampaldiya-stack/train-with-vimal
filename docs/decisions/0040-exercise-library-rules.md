# D-40 · Exercise library, Exercise page, Add / Edit exercise

Date: 2026-10-20

## Decision
- **Built-in exercises never change.** Edit (PATCH) → 400, Delete → 403, cover upload → 403. The page shows
  **Duplicate to edit**: `POST exercises/<id>/duplicate/` makes a custom copy "<name> (copy)" and opens it in Edit.
- **Custom exercises** are created, changed, duplicated, deleted, restored and get a cover only with
  "Add custom exercises" (`training.custom_exercises`); Vimal always can. API flags: `exercises/facets/` →
  `can: {create}`; each exercise → `can_edit` (custom and the person has the right).
- **Delete → Undo**: delete is a soft delete; the toast's Undo calls `POST exercises/<id>/restore/`. Programs that
  already use the exercise keep it, logged workouts stay.
- **Also works** rows keep a short note (up to 80 characters, extra spaces removed), each muscle once, up to 8.
  The built-in exercises got notes from `seed_data.ALSO_NOTES` (`seed_defaults` fills them in on old databases).
- **Cover image**: "Upload image" → `POST exercises/<id>/cover/` (multipart `file`, JPG or PNG, up to 5 MB, checked
  with Pillow); `DELETE` removes it. Choosing "Frame from the video" on save removes an uploaded cover. The frame
  tiles (0:04, 0:12, 0:21, 0:33) only store `cover_at_seconds`: there is no frame grab from the video yet, so the
  tiles are the tinted placeholders from the board. The library picture is: uploaded cover → video's cover → YouTube
  still → dumbbell tile.
- **YouTube link**: the edit page checks the link with `GET exercises/youtube-info/?url=` (oEmbed, 3 s timeout,
  cached 24 h) and shows the title and channel. A link that is not YouTube → 400 "Paste a YouTube link".
- **Used in N programs**: the Exercise page lists the programs; the client count counts only the trainer's own
  clients (`visible_clients`), Vimal sees all.
- **Add to program**: pick one of the programs you may change (D-39), then a workout day. The exercise is added at
  the end of that weekday **in every week** where it is a workout day, with its default sets and reps
  (`POST programs/<id>/add-exercise/` `{exercise, weekday}` → `{weeks, program, name}`). A rest day → 400.
- **Muscles**: the primary chip decides the library filter (`muscle_group`); Glutes saves as `legs` with
  `primary_muscle` "Glutes". A Cardio chip shows when Client logs is Cardio. The body map on Add / Edit is tappable:
  a tap adds or removes that muscle under Also works (the primary muscle's regions do nothing).
- **Client logs** tabs: Weight & reps → `weight_reps` (an old `bodyweight_reps` stays), Time → `time`,
  Cardio → `distance`. The reps box label and default follow (Reps 8–12 / Time per set 30 s / Minutes 20 min).

## Why
Gautam: after Programs, build Exercises. The boards ExerciseLibrary / ExerciseDetail / ExerciseAdd (+ Mobile) show
every one of these actions; the trainer rights come from the trainer permission list ("Add custom exercises").
