# D-45 · Habits & supplements: trainers make their own; Content media opens inside the app

Date: 2026-10-22

## Decision
- **Who may change a habit or a supplement plan** (same rule as programs D-39 and meal plans D-44): Vimal, the
  trainer who made it, or a trainer with "Edit gym templates". Making a new one and Duplicate need the tab's access
  ("Meal plans" for habits, "Supplement plans" for supplement plans), which trainers have by default. Before this,
  every change needed "Edit gym templates" (off by default), so Aman could only look.
- A gym habit / plan the trainer can't change shows the lock line *"Only Vimal can change this one. Duplicate it from ⋯
  to make your own."*; its ⋯ menu has only Duplicate. API: rows carry `created_by`; `habits/counts/` → `can` adds
  `create_habits` and `create_supplements`; a 403 says to duplicate.
- **Habit editor look** (Gautam): Type cards with a picture of what the client gets (tick / "123"), the radio on the
  right; Frequency tabs as wide as their labels; list rows 6 px shorter (30 px icons).
- **Content library item drawer**: a video file plays right there (seek bar, full screen from the player); a YouTube
  link plays in YouTube's own player there; a picture and a PDF open full screen inside the app (zoom, pages). No new
  browser tab, except a web link. A picture is its own cover on the cards. A PDF shows its first page as the preview.
- **Content storage is a real limit** (Gautam, 22 Oct, option 1): an upload that would take the gym past
  `CONTENT_STORAGE_GB` (server setting, 20 GB) is refused: *"Content storage is full (20 GB). Delete old videos or
  files first."* Links and YouTube take no space. The limit is changed on the server, not in the app.
- **A new video goes up as soon as it is picked** (`POST content/stage/`), so its cover frame can be chosen before
  Save. Save sends `upload` (the staged name) instead of the file, so the video is not sent twice. The frames then
  take the item's id. Staged videos not saved within a day are removed on the next stage.
- **New content drawer**: Type / Video tabs as wide as their labels, Category select 280 wide (240 on a phone). The
  drop area answers hover and drag (blue, icon lifts) and has a Choose file button; once a file is in, a drop does
  nothing ("A file is already added. Use Replace to change it."): only Replace changes it; × removes a new file. A
  wrong file is refused and the current one stays.

## Why
Gautam (22 Oct): Aman could not add habits or supplements; the type picker and tabs should look better; media
should open on the same screen, not a new tab.
