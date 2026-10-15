# Board status — every design board, one row

Source of truth for **what is built**. 104 boards in `design/screens/`. Rules for updating it: [rulebooks/definition-of-done.md](../rulebooks/definition-of-done.md).

Status: **Done** (built and checked in a browser against the board, phone and desktop) · **Partial** (some parts built; the note says what is missing) · **Not started**.

**Last updated:** 2026-10-15


## Client

| Board | Status | Note |
|---|---|---|
| ClientAbout | Not started |  |
| ClientAboutWeb | Not started |  |
| ClientCheckin | Not started |  |
| ClientCheckinWeb | Not started |  |
| ClientFood | Not started |  |
| ClientFoodLog | Not started |  |
| ClientFoodLogWeb | Not started |  |
| ClientFoodWeb | Not started |  |
| ClientHabits | Done | `/habits` (More → Habits, Home See all): Day / Week tabs; Day = Mon–Sun strip (tap a day; past days log, future toasts), each habit (water −/+250 ml through the water log, Add steps sheet, sleep sheet, yes / no tick), last-7 dots, streak, Details sheet (streaks, last 7 days, target set by coach, weekly check-in link, log button), habit that starts later (pill, toast, Details with Remind me = habit reminders on), supplements by group (Take / Undo / Missed + Took it / Upcoming, tick circle, supplement sheet with dose, when, stock, last 7 days, running low, Take now / Undo today) and every toast with Undo. Week = summary cells, habits and supplements grids (tap a cell → that day). Subtitle says "Daily habits" (no habit-set name in the data). Checked 390 on 2026-10-15. |
| ClientHabitsWeb | Done | Same code: row-style week strip, habits left and supplements right from 720 px, week grids side by side, sheets as centred cards. Checked 600, 768, 900, 1024, 1280, 1440. |
| ClientHealth | Done | Step 4 of setup with health conditions, heart hint and doctor’s OK rule. Checked 390 + 1440. |
| ClientHealthWeb | Done | Same code as ClientHealth, desktop steps panel. Checked 1440. |
| ClientHome | Done | Top line, bell (Notifications sheet, Mark all as read); no RS avatar (Gautam removed it, 2026-10-15), week strip (tap a day), workout card (today / past / coming / rest, `+ N more` and See all exercises sheet, session line, progress), Water card (all 5 toasts), Food card (ring, macros, Up next Ate it + Undo, Log food sheet), Habits (Add steps sheet, water from the water card, Sleep sheet, tick habits get Done + Undo), Supplements (Take + Undo), coach reply card, Coming up (session toast, check-in, plan end toast). Start workout opens the logger. See all, Weekly check-in and the food search open Habits / Check-ins / Food, which are not built yet. Checked 390 on 2026-10-15. |
| ClientHomeHero | Not started | Option board: same Home with a blue hero at the top (picture, “Cardio and core today · 3 of 5 workouts done this week”). Waiting for Gautam to pick plain Home or this one. |
| ClientHomeWeb | Done | Client sidebar, two columns (left: week, workout, water, Coming up; right: food, habits, supplements, coach), one-line week days, Notifications dropdown under the bell with Mark all read, sheets as centred cards. Under 680 px of panel the cards stack in one column and the week days stack like the phone. Checked 600, 768, 900, 1024, 1280, 1440 on 2026-10-15. |
| ClientIntro | Done | First-open slides on phone (`twv.introSeen`), then Welcome. Checked 390. |
| ClientJoinLink | Done | `/join/:code`: invite, create account, account created, broken link (expired / off / full / bad code). Terms sheet, Help sheet. Checked 390. |
| ClientJoinLinkWeb | Done | Same pages with the steps side panel; also the login link `/start?token=` (set password, you’re in, used link, Details not right? sheet). Checked 1440. |
| ClientLibrary | Not started |  |
| ClientLibraryWeb | Not started |  |
| ClientLogin | Done | Welcome, Log in, Approval wait, 5 setup steps, Checklist, All set, Need help sheet, Finish later sheet (with the toast gap). Terms sheet has no button on the phone board (only the desktop legal line opens it). Checked 390, 600, 768, 900, 1024, 1280, 1440 on 2026-10-15. |
| ClientLoginWeb | Done | Log in, Terms and Help from the legal line, Approval wait, Checklist, steps 1–5 with the side panel and its “Only you and your coach” card, Finish later sheet, All set (420 column, no line above Go to Home). Checked 1440 + 600–1280 on 2026-10-15. |
| ClientMealNutrition | Not started |  |
| ClientMealNutritionWeb | Not started |  |
| ClientMore | Not started |  |
| ClientMoreWeb | Not started |  |
| ClientNutrition | Not started |  |
| ClientNutritionWeb | Not started |  |
| ClientPermissions | Done | `/permissions`: ask, allowed, blocked, after email is confirmed. Camera / photos use `?kind=` when first needed. Checked 390. |
| ClientPermissionsWeb | Done | Side panel with To ask / Allowed / Blocked / Not now pills. Checked 1440. |
| ClientProfile | Not started |  |
| ClientProfileMobile | Not started |  |
| ClientProgress | Not started |  |
| ClientProgressWeb | Not started |  |
| ClientResetPassword | Done | `/forgot` (forgot, email sent, resend in 30 s) and `/reset-password?token=` (set, updated, link not valid). Checked 390. |
| ClientResetPasswordWeb | Done | Same, desktop panel "Back in a minute". Checked 1440. |
| ClientTrain | Done | `/train`: top line + History (Past workouts sheet with "this workout" / All filter, Show more, workout detail), week strip, Today card (Start / Continue / Log more sets, session line, rest day), Note from coach, exercise blocks (tap → Exercise guide page with target tiles, details, how-to, form cues, body map), live workout bar, "Workout discarded" toast. Block names are worked out by the app (D-16). The guide's video plays only when the exercise has one (none in the seed). Day tap on the week strip shows that day, ⋯ on the running workout (Pause / Resume, Finish, Restart, Discard) (D-17), exercise rows show the video cover / YouTube picture when there is one. Checked 390 on 2026-10-15. |
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
| TrainerCheckins | Not started |  |
| TrainerCheckinsMobile | Not started |  |
| TrainerClientProfile | Not started |  |
| TrainerClientProfileMobile | Not started |  |
| TrainerClients | Not started |  |
| TrainerClientsMobile | Not started |  |
| TrainerDashboard | Not started |  |
| TrainerDashboardMobile | Not started |  |
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

