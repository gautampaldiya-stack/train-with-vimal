# D-39 · Programs library, Program builder, and who may change a program

Date: 2026-10-20

## Decision
- **Who may change a program** (`training.services.can_edit_program`):
  - Vimal (admin): every program.
  - A trainer with "Edit gym templates" (`training.edit_templates`, default off): every program.
  - Any other trainer: only programs **they created**, and only while they have "Use templates"
    (`training.use_templates`, default on). Without this, a trainer could make a new program but never build it.
  - Everyone who can see the Programs page can **Duplicate** a program (needs `use_templates`) and edit the copy.
  - Assign needs `training.programs_edit`.
  - Anything else (rename, structure, archive, delete, copy week) on someone else's program → 403
    "Only Vimal or a trainer with "Edit gym templates" can change this program. Duplicate it to make your own."
- API flags for the screens: `programs/counts/` → `can: {create, assign, edit_all}`; each card / program → `can_edit`.
  The builder opens read-only (with **Duplicate to edit**) when `can_edit` is false.
- **Trainer privacy**: program cards, counts, the clients drawer and the assign list show only the trainer's own
  clients (`visible_clients`). Assign changes only those clients; other trainers' clients stay on the plan.
- **Delete → Undo**: delete ends the program's active assignments and remembers them for one hour (cache key
  `program-unassigned:<id>`). `POST programs/<id>/restore/` brings the program and those clients back.
- **Builder saving**: the whole week → day → exercise tree is edited on the device and sent with
  `PUT programs/<id>/structure/`, one request at a time (newest tree wins). Ids from the server are copied onto the
  local tree, so logged workouts stay linked. Undo puts back a copy of the tree from before the change. The coach
  note saves 0.6 s after typing stops. A failed save shows a red line with Try again.
- **Days are a row from Monday**: Move earlier / later swap two days, Remove day moves later days up, Add day fills
  the next weekday (max 7). Day changes apply to the open week only; Copy week N → N+1 (or → new week) repeats a week.
- Edit for this program = an `override` on that program's exercise row (name, video, how-to, form cues); the library
  and other programs stay the same. Reset to library version clears it.
- Exercise details opens `/exercises/<id>` (board ExerciseDetail, built with the Exercises screens).
- Demo data: five more master programs (one archived) so the page and the Archived tab have content.
