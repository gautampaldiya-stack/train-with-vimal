# D-42 · Real cover frames, program card menu, tooltips everywhere

Date: 2026-10-21

## Decision
- **Cover frames are real stills** (board ExerciseAdd → Cover image → "Frame from the video"). Before, the four tiles
  were tinted placeholders with made-up times (0:04, 0:12…).
  - Library video: `GET exercises/frames/?video=<content id>` grabs four stills with ffmpeg at 10 %, 30 %, 55 % and
    80 % of the length (1, 4, 8, 12 s when the length is unknown), saves them once under
    `media/exercises/frames/<video id>-<seconds>.jpg` and reuses them. ffmpeg is the system one, else the binary that
    `imageio-ffmpeg` (pip) brings. A still that could not be grabbed comes back with `url: null` and shows a tinted tile.
  - YouTube link (or a library item that is only a YouTube link): `?url=` returns YouTube's own four stills
    (Cover, ¼, ½, ¾ — `img.youtube.com/vi/<id>/hqdefault|1|2|3.jpg`). Not a YouTube link → 400.
  - The pick is saved as `Exercise.cover_frame` (the frame's key, checked against a fixed pattern) and
    `cover_at_seconds`. The exercise picture everywhere is: uploaded cover → chosen frame → video cover → YouTube still.
  - No video yet: "Pick a video first, then choose a frame from it." A new video keeps the old pick if it has that
    frame, else picks its second still.
- **Program card ⋯ menu** (Gautam's image): Open, Rename, Assign to clients, See assigned clients (with the count),
  Duplicate (or Duplicate to edit when you can't change it), Archive / Restore, Delete. Assign and See assigned
  clients open the builder with its drawer already open (`/programs/<id>?open=assign|clients`).
- **Program cards**: "N weeks" pill and "N days / week" sit on one centred line, the footer has a fixed height so every
  card in a row is the same height, and the list reloads when you come back from the builder.
- **Tooltips**: every icon-only or unclear button gets a tooltip that says what it does (builder "+ Add" → "Add
  exercises to Monday", week pills → "Show week 3", the rest-day moon, Add day, Copy week…). `AppButton` takes
  `tooltip:`; icon-only buttons fall back to their label. New screens follow this.
- **Add exercises drawer rows** show the exercise picture (no play badge on a plain picture) and
  "Dumbbell · 3 × 8–12" (equipment, default sets × reps) on the same row height.
