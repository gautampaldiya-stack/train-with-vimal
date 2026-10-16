# D-23 · More tab: one account answer, my activity, export, report, own quiet hours

- **Date:** 2026-10-16
- **Status:** Accepted

## Decision
1. **One answer for the page:** `GET me/account/` (client only) has profile, coach, next session, check-in day,
   program, meal plan, goal, stats, habits / supplements (short names: "Steps, water, sleep · whey, D3"), unread
   count, reminder settings, deletion date, gym contact and version. Cached for offline like the other tabs.
2. **My activity:** `GET me/activity/?kind=All|Training|Food|Check-ins|Habits|Account`, last 7 days, grouped by the
   day the log is for. Profile / preference edits leave an `ActivityEvent` with `meta.mine` (rows "Old → New").
3. **Changes never hide:** a weigh-in or measurement for a past day, or a change to one already logged, adds its
   own line under today: "You changed measurements for Tue, 13 Oct" · "Chest 92 → 91.5 cm" (also in the coach's
   feed). A late log shows "Logged on Fri, 16 Oct" (Gautam 2026-10-16).
4. **Profile:** the client can edit name, email (verified first), mobile (must be free), city, date of birth.
5. **Preferences on the user:** `unit_weight / unit_length / unit_water`, `week_start`, `theme`, `share_photos`,
   `usage_data`. Photos added while sharing is off are `private` and never reach staff.
6. **Reminders:** `ReminderPreference` gains water, supplements, progress and the client's own quiet hours
   (22:00–07:00 by default). `POST me/reminders/` resets to the board defaults. Coach and progress toggles mute
   push and email only; the in-app row stays. Water (every 2 h when behind) and supplement reminders run on beat.
7. **Download my data:** `POST me/data-export/` (5 a day) builds a ZIP in Celery and emails the link; files go
   after 7 days. **Report a problem:** `POST me/report/` (20 a day) with category, text, optional screenshot of
   the page; the admin gets it in-app and by email.
8. **Photos every N weeks:** `ClientProfile.photo_every_weeks` (default 2). The weekly check-in asks for photos only
   in photo weeks; Coming up, "Next set due" and the Progress caption follow the same rule.

## Not built yet
- Library page (`/library`), dark theme, units / Sunday week start applied app-wide (only More uses them),
  the coach's photo-cadence and measurement pickers (trainer screens).
