# D-46 · Client profile: the missing parts; toolbars wrap, chip rows scroll

Date: 2026-10-22

## Decision
- **Target date.** `ClientProfile.target_date` (optional). Edit details → "Goal and body" has Target date (today to
  5 years ahead) next to Enrolled for. History logs "changed target date" (Dec 2026 → Feb 2027) as a milestone, and
  About shows "Feb 2027 · was Dec 2026".
- **Health over time.** Each health-notes change is logged with the text before and after. The History health card
  turns these into rows per line: ongoing lines read "Since 14 Mar · note" (warning), lines that were removed read
  "Feb – Apr · note · cleared" (ok). Up to 6 rows.
- **Supplement stock history.** When a client's supplement stock reaches 0 (a take, or a trainer sets 0), an activity
  "ran out of <name>" is saved. Logs → Compare has a row "Ran out of stock" (fewer is better).
- **Form-check video** (Gautam picked "Workout logger"). In the client's workout logger, the set number menu has
  "Send a form video": record (60 s) or choose on a phone, choose a file on web; mp4 / mov / m4v / webm up to 100 MB.
  A filmed set shows a small camera dot. The trainer gets a notification that opens the workout in the client
  profile Logs tab, where the exercise has a "Form video" badge and a row with duration, "set N", time sent and
  Watch (plays full screen inside the app). API `POST me/workouts/<id>/form-video/`, model `FormVideo`.
- **Body map.** The exercise drawer in the client profile Plans tab shows the body map (front and back) with the
  Primary / Also works chips beside it (stacked when narrow).
- Still not built: device name (no data source).
- **ClientProfile / ClientProfileMobile boards are the admin view of a client.** They reuse the trainer client
  profile code and are built together with the admin Clients page.
- **Layout rule (Gautam, 22 Oct):** chip / badge filter rows never wrap; they stay on one line and scroll sideways.
  The top toolbar (search, tabs, dropdown filters) may wrap to the next line. Tabs that don't fit scroll sideways.
  Nothing overflows. Shared widgets: `SearchTabsRow` and `ChipScroll` in `features/library/lib_common.dart`. Applied
  to Nutrition (Meal plans, Food library), Content, meal builder option tabs, admin Needs action chips.
- Trainer dashboard Today rows no longer show the client avatar (Gautam).

## Why
Gautam (22 Oct): finish the "Not built" parts of the client profile; Nutrition at about 850 px showed overflow
stripes; chips must scroll, toolbars may wrap.
