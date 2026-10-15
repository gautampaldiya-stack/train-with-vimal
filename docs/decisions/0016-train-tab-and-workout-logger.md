# D-16 · Train tab and workout logger: blocks, saving, Log more sets, discard

- **Date:** 2026-10-15
- **Status:** Accepted

## Decision
1. **Blocks are worked out by the app.** The data model and the Program builder have no "block" field. The Train tab
   and the logger name them from the exercise: a superset group gives "Superset X", cardio (`log_type` distance or
   muscle cardio) gives "Cardio", muscle core gives "Core", everything else "Strength". The boards' "Conditioning"
   style names need a block field first.
2. **The logger saves the whole workout as it is now.** Every change is kept on the phone (`workout:live` in the read
   cache) and, 0.6 s later, sent as `PUT me/workouts/<id>/state/` through the outbox (timer `started_at` /
   `paused_at` plus every set). Sets are matched by id, else by the app's `client_key`, so a repeated send never
   doubles a set. A workout started offline lives only on the phone and is sent whole with `POST me/workouts/sync/`
   when it is finished.
3. **Timer.** `started_at` + `paused_at`. Resume moves `started_at` forward by the paused time; ± 1 min moves
   `started_at`. Rest time is counted on the phone and sent in `time_breakdown` at finish.
4. **Log more sets** (after finishing) calls `POST reopen/`: the same workout runs again, the timer goes on from its
   time, `reopened_at` is set. Planned sets that were skipped come back empty.
5. **Discard after Log more sets keeps the finished workout.** The server drops only the sets ticked since
   `reopened_at` (and any not ticked) and puts the workout back to completed with the same time, effort and note.
   A set that was done before and changed after reopening keeps its new value. A normal discard still removes
   everything ("Nothing was saved").
6. **Finish again keeps effort and note** already sent.
7. **Trainer's pronoun.** The board says "He usually replies within a few hours". The app says "You will usually get
   a reply within a few hours", so it is right for every trainer.

## Why
The boards show these flows but the data model had no block, and "Log more sets" + "Discard" on a finished workout
would otherwise delete the client's real workout.
