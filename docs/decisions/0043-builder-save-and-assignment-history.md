# D-43 · Program builder saves with a button; leaving asks; assignment Undo leaves no history

Date: 2026-10-21

## Decision
- **Save changes** (Gautam): builder edits stay on the device until **Save changes**. Before (D-39) every change was
  sent at once, so clients saw half-made edits. Now:
  - The header shows "· unsaved changes", a **Discard** button (desktop; in the ⋯ menu on phone and narrow windows) and
    **Save changes** (Save on phone). Assign turns into an icon while there are unsaved changes and saves first,
    because clients get the saved plan. Duplicate also saves first.
  - The coach note goes into the day as you type and is saved with the rest ("Saved with Save changes").
  - Copy week, Add empty week and Delete week change the local tree too (Undo in the toast), saved with Save changes.
- **Leaving with unsaved changes asks** "Save your changes?" — Save / Don't save / Cancel. It is asked for every way
  out: sidebar, bottom tabs, links, back, the breadcrumb. On web the browser also warns before the tab closes or
  reloads. Built as `core/leave/leave_guard.dart`: a page registers a check, the router's `:id` route calls it in
  `onExit`. The Add / Edit exercise form uses the same guard ("Leave without saving?").
- **Week ⋯ menu** replaces the Copy week button: Copy to week N+1 (or a new week), Add empty week, Delete week N
  (confirm; the weeks after it move up; logged workouts stay).
- **Assignment history**:
  - `ProgramAssignment.end_reason` = `replaced` (another plan took over), `unassigned` (taken off in Assign),
    `ended` (End plan). Plan history shows Replaced / Unassigned / Ended (Completed when it ran its full length).
    Older rows were filled in from the dates (migration `training 0006`).
  - `ProgramAssignment.replaced` points at the plan it took over from.
  - **Assigned and taken off the same day with nothing logged** (Undo, a slip) = it never ran: the row is deleted,
    no Plan history entry, and the replaced plan comes back as Current. Before, Undo left "Ended" + "Replaced" rows.
- **Who made a program**: cards show a tag — Gym (Vimal or seeded), By you, By Aman — with the full line as a
  tooltip; the builder's line under the title says "Gym program" / "Made by you" / "Made by Aman Verma". API: `owner`
  on program cards and details.
