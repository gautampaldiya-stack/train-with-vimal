# D-30 · Trainer dashboard; one check-in queue for every role

Date: 2026-10-16 · Asked by: Gautam ("ab trainer ke banane start karo", "data match hone chahiye sabhi... client admin trainer... kahi ulta na ho")

## Decision
1. **Dashboard API in the board's words.** `GET dashboard/trainer/` (code `apps/activity/trainer_home.py`) returns
   greeting, date, subline, 4 stats, today's sessions (with the next one's "In 40 min"), clients who need you,
   check-ins to review (oldest 5 + `checkins_total`), this week and the bell list. The app only lays it out.
2. **One check-in queue.** `apps/checkins/queue.py` (`review_queue`, `REVIEW_TYPES` = weekly, daily, monthly) is
   the only definition of "waiting for review". The trainer dashboard, Check-ins page + counts, the nav badge,
   trainer My profile, the admin dashboard and the admin's Trainers table all count from it, so the same number
   shows everywhere. Before this the dashboard counted weekly + monthly, the Check-ins page weekly + daily +
   monthly and the Trainers table weekly + daily. A test checks the numbers agree.
3. **Client counts** = active clients not removed (same rule as the admin's Trainers table and trainer My profile).
   Waiting-for-approval clients are not counted in "My clients 10 / 30".
4. **Clients who need you**: one row per client, worst reason first (Not logging → Missed workouts → Plan ending →
   Feeling low). *Feeling low* reads only the client's **latest** check-in with energy or mood (an old low day
   that has passed does not count); "in the last 2 check-ins" when the two latest are both low.
5. **Remind waits for Undo.** The toast's Undo (10 s) cancels it; leaving the page sends it at once.
6. **Review drawer** uses `review` on `GET checkins/<id>/` (`apps/checkins/review.py`): 4 numbers, the week's
   answers with last week beside them, what the client wrote, photos, reply with quick replies. Undo = `unreview`.
7. **New session** adds an "Extra session" (`POST sessions/`), Undo cancels it without a message to the client.
8. **Routes are per role.** Trainer and client paths overlap (`/checkins`, `/calendar`, `/more`, `/habits`), so the
   router has `trainerScreens` beside the client `screens`; admin pages show the holding page until built.
9. **Phone** = TrainerDashboardMobile hero (blue, under the status bar) with the 4-cell stats strip over its edge.
   Drawers now look like the boards' `.drawer` (32 icon tile, 15/800 title, square edge).
