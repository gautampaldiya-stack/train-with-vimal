# Board status — every design board, one row

Source of truth for **what is built**. 104 boards in `design/screens/`. Rules for updating it: [rulebooks/definition-of-done.md](../rulebooks/definition-of-done.md).

Status: **Done** (built and checked in a browser against the board, phone and desktop) · **Partial** (some parts built; the note says what is missing) · **Not started**.

**Last updated:** 2026-10-15


## Client

| Board | Status | Note |
|---|---|---|
| ClientAbout | Done | `/more/about` (More → Help & about → About Train With Vimal; no board links here). App card with logo, tagline, Version 1.0.0 (1) chip (copies, toast), head coach card (name, role, intro, 3 stats), Contact (WhatsApp, Call, Email, Website open the apps with board toasts; Support hours info row), App (What’s new sheet + New pill, Rate the app → Play Store, Terms / Privacy sheets, Open-source licences sheet), footer. Contact and coach words come from gym settings (`gym/`, D-29). Checked 390 on 2026-10-16. |
| ClientAboutWeb | Done | Same code: two columns from 680 px (app + coach left, Contact + App right), sheets as centred cards. Checked 1280. |
| ClientCheckin | Done | `/checkins` (More → Check-ins, Home check-in card, reply notification `/checkins/<id>`): header with coach and program week, streak / weekly on time / last weekly change, Daily card (Start, or Sent with View + Edit answers), Weekly card (question chips, draft bar + Continue, or Sent + View what you sent), Past check-ins Weekly / Daily with Sent / Replied / Reviewed / Missed rows, coach reply under the row, paged as you scroll. Daily form `/checkins/daily` (weight stepper, sleep grid, 5-point scales, note + suggestions, steps and water from Habits, Send with the "Answer … first" toast, Sent card, Edit answers, Undo). Weekly form `/checkins/weekly` (one question a page, Back / Next / Skip, weight quick picks, photo slots Front / Side / Back with camera or gallery and Undo remove, No photos this week, review page with Edit, Send, Sent card, Undo, Draft saved on exit). Past check-in sheet with cells, coach reply or waiting note, answers, photos by name (tap → full-size viewer), Newer / Older. Forms keep the top bar fixed; Past check-ins scroll inside a fixed-height card; sent card lists every question with photo thumbnails. Rechecked 390 and 1280 after Gautam's fixes. No per-client question ("Added for you by Aman"), see D-19. Checked 390 on 2026-10-15. |
| ClientCheckinWeb | Done | Same code: cards left and Past check-ins right from 720 px, forms in a 640 px column (sleep in one row of 7, photo slots 4:3), sheet as a centred card. Checked 600, 768, 900, 1024, 1280, 1440. |
| ClientFood | Not started | Replaced by the combined Food page (ClientMealNutrition), Gautam 2026-10-15. |
| ClientFoodLog | Done | `/food/log?meal=` (Food → Log food, Ate something else, Log something different, Home Log food search): back, `Add to <meal> ▾` picker (sheet on phone, menu on web; plan foods or "N kcal added now"), search with Try chips, All / Recent / My foods tabs, first 8 then Show all N (paged 25), + adds at once through the outbox (green tick, tap again removes, toast with Undo), tap a food → portion sheet (big stepper, unit chips, = N g, macro cells, Add to <meal>). Added card with Off-plan tag, remove ×, Done · back to meal plan. Can't find the exact food: Calories / Protein / Carbs / Fat with −/+ and a number you tap to type, Quick add, Create custom food sheet (name, serving, 4 typeable steppers → My foods), Off-plan meal tick with Ate out / Party / Travelling. Add to → Other time sheet (name, time) logs straight to the food log at that time, off-plan (Gautam, 2026-10-16). Checked 390 on 2026-10-15, 390 and 1280 on 2026-10-16. |
| ClientFoodLogWeb | Done | Same code: search and list left (3fr), added + can't-find right (2fr) from 720 px; one column below. From 720 px wide and 520 px tall only the food list scrolls inside its card; fit-width tabs (2026-10-16). Checked 600, 768, 900, 1024, 1280, 1440. |
| ClientFoodWeb | Not started |  |
| ClientHabits | Done | `/habits` (More → Habits, Home See all): Day / Week tabs; Day = Mon–Sun strip (tap a day; past days log, future toasts), each habit (water −/+250 ml through the water log, Add steps sheet, sleep sheet, yes / no tick), last-7 dots, streak, Details sheet (streaks, last 7 days, target set by coach, weekly check-in link, log button), habit that starts later (pill, toast, Details with Remind me = habit reminders on), supplements by group (Take / Undo / Missed + Took it / Upcoming, tick circle, supplement sheet with dose, when, stock, last 7 days, running low, Take now / Undo today) and every toast with Undo. Week = summary cells, habits and supplements grids (tap a cell → that day). Subtitle says "Daily habits" (no habit-set name in the data). Checked 390 on 2026-10-15. |
| ClientHabitsWeb | Done | Same code: row-style week strip, habits left and supplements right from 720 px, week grids side by side, sheets as centred cards. Checked 600, 768, 900, 1024, 1280, 1440. |
| ClientHealth | Done | Step 4 of setup with health conditions, heart hint and doctor’s OK rule. Checked 390 + 1440. |
| ClientHealthWeb | Done | Same code as ClientHealth, desktop steps panel (light like the other account pages, only the step list scrolls; Gautam 17 Oct). All 9 steps run end to end at 390 and 1440 on 2026-10-17; placeholders in every box. |
| ClientHome | Done | Top line, bell (Notifications sheet, Mark all as read); no RS avatar (Gautam removed it, 2026-10-15), week strip (tap a day), workout card (today / past / coming / rest, `+ N more` and See all exercises sheet, session line, progress), Water card (all 5 toasts), Food card (ring, macros, Up next Ate it + Undo, Log food sheet), Habits (Add steps sheet, water from the water card, Sleep sheet, tick habits get Done + Undo), Supplements (Take + Undo), coach reply card, Coming up (session toast, check-in, plan end toast). Start workout opens the logger. See all, Weekly check-in and the food search open Habits / Check-ins / Food, which are not built yet. Checked 390 on 2026-10-15. |
| ClientHomeHero | Done | Gautam picked the hero (2026-10-16): phone Home now has the blue hero under the status bar (date · week, white bell, Hey Riya, today’s workout or Rest day + “N of M workouts done this week”, runner picture) with the week strip overlapping it. Below it the same cards as ClientHome. Web keeps ClientHomeWeb. Checked 390. |
| ClientHomeWeb | Done | Client sidebar, two columns (left: week, workout, water, Coming up; right: food, habits, supplements, coach), one-line week days, Notifications dropdown under the bell with Mark all read, sheets as centred cards. Under 680 px of panel the cards stack in one column and the week days stack like the phone. Checked 600, 768, 900, 1024, 1280, 1440 on 2026-10-15. |
| ClientIntro | Done | First-open slides on phone (`twv.introSeen`), then Welcome. Checked 390. |
| ClientJoinLink | Done | `/join/:code`: invite, create account, account created, broken link (expired / off / full / bad code). Terms sheet, Help sheet. Checked 390. |
| ClientJoinLinkWeb | Done | Same pages with the steps side panel; also the login link `/start?token=` (set password, you’re in, used link, Details not right? sheet). Checked 1440. |
| ClientLibrary | Done | `/library` (+ `/library/<id>` opens one item, the "New in your library" notification links there). Progress card (N of M done, N new from Aman), search + Try chips, filters with counts (All, Videos, PDFs, Images, Articles, Saved), rows with New / Done / Note from Aman / bookmark, empty states. Item sheet: video player (Tap to play, chapters seek, finishing marks done), PDF page card with pager + Download, image + Save image, article text, coach note, Save for later, Mark as done / Done · undo, all board toasts with Undo. Real PDF pages (server-drawn), full-screen zoom for pages and pictures, video seek + full screen, Links filter and link sheet (D-27). YouTube plays inside the sheet with Open in YouTube, short picture box (D-28). Not built: Save image opens the file (no photo-gallery save yet). Checked 390 on 2026-10-16. |
| ClientLibraryWeb | Done | Search, filters, grid of cards (3 across from a 600 px column, then 2, then 1), side column with progress and Notes from Aman (below the grid under 860). Item sheet is a 600 wide dialog, video 260 high. Checked 600, 768, 1024, 1280, 1440 on 2026-10-16. |
| ClientLogin | Done | Welcome, Log in, Approval wait, setup steps (9 since D-36: the gym's coaching form — new steps not browser-checked yet), Checklist, All set, Need help sheet, Finish later sheet (with the toast gap). Terms sheet has no button on the phone board (only the desktop legal line opens it). Checked 390, 600, 768, 900, 1024, 1280, 1440 on 2026-10-15. |
| ClientLoginWeb | Done | Log in, Terms and Help from the legal line, Approval wait, Checklist, steps 1–5 with the side panel and its “Only you and your coach” card, Finish later sheet, All set (420 column, no line above Go to Home). Checked 1440 + 600–1280 on 2026-10-15. |
| ClientMealNutrition | Done | `/food` (Food tab): Food header + Log food, Mon–Sun strip (done ticks, today ring, future dashed; tap a day), calories ring card → calories sheet, This week bars with target line (own selection), Water ±250 ml, My plan / Food log · N tabs. Meal cards with pill (Logged / Next / To log / Missed / Planned / Skipped), ☰ menu (Swap a food, Edit portions, Log something different, Skip meal), Swap per food, Edit portions sheet with typeable steppers, **Mark as eaten ▾ dropdown: Upload photo and mark as eaten / Mark as eaten without a photo** (Gautam), Logged · Undo, Eaten after all, photo thumbnail on the card. Food log rows (one per plan meal, one per extra food) with photo thumbnail, details sheet (foods, photo → full-size viewer, macros, share of day, Edit portions / Mark as not eaten / Log more / Delete entry + Undo), Log food + Copy yesterday (toast with Undo). Round 2 (2026-10-16): photo picked first waits on the card (Change / ×) and a separate Mark as eaten logs it; Add / Change / Remove photo on a logged meal; foods added from Log food show in the meal card under Also logged · outside the plan; fit-width tabs on tablet / web. Checked 390 on 2026-10-15, 1440 on 2026-10-16. |
| ClientMealNutritionWeb | Done | Same code: calories, week and water left; tabs and meals right. From 700 px the header, strip and tabs stay put and only the meal cards (and the left column) scroll (Gautam); narrower = one column, page scrolls. Sheets as centred cards. Checked 600, 768, 900, 1024, 1280, 1440. |
| ClientMore | Done | `/more`: header + bell, deletion banner, profile card → `/more/profile` (details, goal, My activity), coach card + Details sheet, Your plan rows, Account rows, Log out, version. Sheets: Edit profile, Coach, Notification settings (quiet hours), Units, Privacy & data, Delete account, Help & about (FAQ, Report a problem), notification row, activity row. `/more/notifications`, `/more/activity`. Not built: dark theme, units / Sunday week applied outside More, "Verify now (demo)" and typing chips (demo only). Checked 390 on 2026-10-16. |
| ClientMoreWeb | Done | My account: Overview (two columns from 680: details, goal, Log out left; coach and Settings right; no Your plan card on web, Gautam), Notifications and My activity tabs (760 wide). Same sheets as centred cards. Checked 768, 1280 on 2026-10-16. |
| ClientNutrition | Not started | Replaced by the combined Food page (ClientMealNutrition), Gautam 2026-10-15. |
| ClientNutritionWeb | Not started | Replaced by ClientMealNutritionWeb, Gautam 2026-10-15. |
| ClientPermissions | Done | `/permissions`: ask, allowed, blocked, after email is confirmed. Camera / photos use `?kind=` when first needed. Checked 390. |
| ClientPermissionsWeb | Done | Side panel with To ask / Allowed / Blocked / Not now pills. Checked 1440. |
| ClientProfile | Not started |  |
| ClientProfileMobile | Not started |  |
| ClientProgress | Done | `/progress`: goal, Weight / Body / Strength, First day vs now, photos, stats, adherence; sheets Log weight, workouts, lift, photo set, Add photos. Sub pages `/progress/history` (+ day sheet), `/progress/photos`, `/progress/compare`. Checked 390, 600. |
| ClientProgressWeb | Done | Two columns (right 340: goal, photos, stats); History summary sticks on the right; Compare photos 540 + table. Checked 768, 1024, 1280, 1440. |
| ClientResetPassword | Done | `/forgot` (forgot, email sent, resend in 30 s) and `/reset-password?token=` (set, updated, link not valid). Checked 390. |
| ClientResetPasswordWeb | Done | Same, desktop panel "Back in a minute". Checked 1440. |
| ClientTrain | Done | `/train`: top line + History (Past workouts sheet with "this workout" / All filter, Show more, workout detail), week strip, Today card (Start / Continue / Log more sets, session line, rest day), Note from coach, exercise blocks (tap → Exercise guide page with target tiles, details, how-to, form cues, body map), live workout bar, "Workout discarded" toast. Block names are worked out by the app (D-16). The guide's video plays only when the exercise has one (none in the seed). Day tap on the week strip shows that day, ⋯ on the running workout (Pause / Resume, Finish, Restart, Discard) (D-17), exercise rows show the video cover / YouTube picture when there is one. A rest day with no exercises takes the full width on web (2026-10-16). Checked 390 on 2026-10-15. |
| ClientTrainWeb | Done | Same code: live banner, row-style week, blocks left and Today + note right from 680 px, guide as a 980 wide dialog. Checked 600, 768, 900, 1024, 1280, 1440. |
| ClientVerifyEmail | Done | `/verify` (inbox, resend, Change email sheet, log out) and `/verify-email?token=` (checking, verified, link not valid). Checked 390. |
| ClientVerifyEmailWeb | Done | Same, desktop panel "Confirm your email". Checked 1440. |
| ClientWelcome | Done | Same code as ClientLogin, opens on Welcome; Need help logging in? sheet. Checked 390 on 2026-10-15. |
| ClientWorkout | Done | `/train/workout` (`?start=<day>` or `?reopen=<id>`): top bar (time chip → Workout timer sheet, ≡ menu: Past workouts / Restart / Remove logged work, Finish), exercise chips, panel (block, PR, target, Rest, How to do it, info tip), Load kg / Bodyweight, set rows (set menu: warm-up / delete with Undo, BW chip, values with −/+ strip, hold timer ▶ for timed sets, tick), Add set, Previous / Next / Finish workout, rest bar + Rest timer dialog (−15 / Pause / +15 / Skip, Next up), sheets Finish workout?, Remove what you logged? (clear exercise / all sets / discard), Restart workout?, Still working out? (after 30 min idle; saved at the last set after 3 h), Workout done page (time, sets, volume, where the time went, effort 1–10, note + quick notes, Save and send, Back to home) and every toast. Works offline (D-16). Menu Past workouts = this exercise only with Use these sets; Use last time; timer stops when the client leaves Train (D-17). Checked 390 on 2026-10-15. |
| ClientWorkoutWeb | Done | Same code: 280 wide exercise list (chips under 760 px), Prev column, inline −/+ in the value, timer popover, dark rest bar under the panel, done page 620 wide. Checked 600, 768, 900, 1024, 1280, 1440. |

## Trainer

| Board | Status | Note |
|---|---|---|
| TrainerCalendar | Not started |  |
| TrainerCalendarMobile | Not started |  |
| TrainerCheckins | Done | Tabs + counts, search, type chips with counts, rows (age red after 48 h, ✓ Replied), Show more, review panel (numbers with green / red, answers vs last time, note, photos, reply + quick replies, Mark reviewed + Undo, Mark as not reviewed), ‹ › and Open profile. Sidebar count. Checked 1440 on 2026-10-17 (D-35). |
| TrainerCheckinsMobile | Done | List, tap opens the check-in in the same card (`/checkins/<id>`), ‹ back. Checked 390 on 2026-10-17. |
| TrainerClientProfile | Done | All 9 tabs (D-34). Checked 1440 on 2026-10-17. Round 3 (D-37): Portion and swaps panel, per-client swaps and supplement copies, compact pickers, workout editor overflow fixed, Forms inner scroll + start photos, amounts with grams; checked 390, 768, 1024, 1440 on 2026-10-17. Not built (no data): target date, health over time, form-check video, device name, supplement stock history, body map. Open master plan / Open in library go to pages not built yet (Programs, Content library). |
| TrainerClientProfileMobile | Done | Header, 4-column stats, scrolling tabs, every tab stacks to one column. Checked 390 on 2026-10-17. |
| TrainerClients | Done | Tabs + counts, search, Filter (4 groups with side submenu like the board, Clear filters), Export and select boxes off for now (Gautam, D-33; code commented), table, row ⋯ (View profile, Edit details drawer), pager 8 a page, sideways scroll when narrow (as board). No AV top right (Gautam). Add client / Invite link drawers have no button on the board, not built for trainers. Checked 1280, 1440 on 2026-10-16. View profile opens `/clients/<id>` (TrainerClientProfile not built yet). Rechecked 390, 1280, 1440 on 2026-10-16 (filter submenu, DOB picker). |
| TrainerClientsMobile | Done | One line per client (avatar, name, goal, badge, ⋯), icon Filter / Export, Edit details as a tall sheet, pager. Checked 390. |
| TrainerDashboard | Done | Stats, Today (Done, ⋯ menu, cancel + Undo), Clients who need you (chips, Remind + Undo, Show more), Check-ins to review + review drawer (reply, quick replies, Undo), This week (left column), Activity card (latest 10, D-31), review drawer photos open full screen, no AV button on web, bell dropdown, New session modal (Day / Time list fits on screen and scrolls). Numbers match Check-ins page, My profile and the admin Trainers table (D-30). Checked 600, 768, 900, 1024, 1280, 1440 on 2026-10-16. Open client profile / Plan next / Open go to `/clients/<id>` (TrainerClientProfile not built yet; review drawer Open profile now opens it after the drawer closes). Rechecked 390, 1280 on 2026-10-16 (stats cards, Activity, Day list). |
| TrainerDashboardMobile | Done | Blue hero under the status bar with the 4-cell stats strip, same cards; ⋯ menu as a bottom sheet, bell full width, review drawer as a tall sheet. Checked 390. |
| TrainerMe | Not started |  |
| TrainerMeMobile | Not started |  |
| TrainerMoreMobile | Not started |  |
| TrainerProfile | Not started |  |
| TrainerProfileMobile | Not started |  |
| Trainers | Not started |  |
| TrainersMobile | Not started |  |

## Admin / shared staff

| Board | Status | Note |
|---|---|---|
| Activity | Not started |  |
| ActivityMobile | Not started |  |
| AdminDashboard | Not started |  |
| AdminDashboardMobile | Not started |  |
| AdminMoreMobile | Not started |  |
| Approvals | Not started |  |
| ApprovalsMobile | Not started |  |
| AutomationBuilder | Not started |  |
| AutomationBuilderMobile | Not started |  |
| AutomationNew | Not started |  |
| AutomationNewMobile | Not started |  |
| Automations | Not started |  |
| AutomationsMobile | Not started |  |
| Calendar | Not started |  |
| CalendarMobile | Not started |  |
| Clients | Not started |  |
| ClientsMobile | Not started |  |
| Content | Not started |  |
| ContentMobile | Not started |  |
| Emails | Not started |  |
| EmailsMobile | Not started |  |
| ExerciseAdd | Not started |  |
| ExerciseAddMobile | Not started |  |
| ExerciseDetail | Not started |  |
| ExerciseDetailMobile | Not started |  |
| ExerciseLibrary | Not started |  |
| ExerciseLibraryMobile | Not started |  |
| FormBuilder | Not started |  |
| FormBuilderMobile | Not started |  |
| Forms | Not started |  |
| FormsMobile | Not started |  |
| Habits | Not started |  |
| HabitsMobile | Not started |  |
| Main | — | Canvas index board, not an app screen. |
| MealPlanBuilder | Not started |  |
| MealPlanBuilderMobile | Not started |  |
| Nutrition | Not started |  |
| NutritionMobile | Not started |  |
| ProgramBuilder | Not started |  |
| ProgramBuilderMobile | Not started |  |
| Programs | Not started |  |
| ProgramsMobile | Not started |  |
| Settings | Not started |  |
| SettingsMobile | Not started |  |

Staff shell (sidebar, bottom bar, toasts, tooltips) is built; the pages inside it are not.

