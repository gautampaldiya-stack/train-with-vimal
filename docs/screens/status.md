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
| ClientHabits | Not started |  |
| ClientHabitsWeb | Not started |  |
| ClientHealth | Done | Step 4 of setup with health conditions, heart hint and doctor’s OK rule. Checked 390 + 1440. |
| ClientHealthWeb | Done | Same code as ClientHealth, desktop steps panel. Checked 1440. |
| ClientHome | Not started |  |
| ClientHomeHero | Not started |  |
| ClientHomeWeb | Not started |  |
| ClientIntro | Done | First-open slides on phone (`twv.introSeen`), then Welcome. Checked 390. |
| ClientJoinLink | Done | `/join/:code`: invite, create account, account created, broken link (expired / off / full / bad code). Terms sheet, Help sheet. Checked 390. |
| ClientJoinLinkWeb | Done | Same pages with the steps side panel; also the login link `/start?token=` (set password, you’re in, used link, Details not right? sheet). Checked 1440. |
| ClientLibrary | Not started |  |
| ClientLibraryWeb | Not started |  |
| ClientLogin | Partial | Welcome, Log in, Approval wait, 5 setup steps, Checklist, All set, Need help sheet: built and browser-checked (390). "Forgot password?" now opens the ClientResetPassword page (the old modal is gone). Not browser-checked yet: Terms sheet from the login board, Finish later sheet. |
| ClientLoginWeb | Partial | Log in, Approval wait, Checklist, setup steps 2 and 4 browser-checked (1440). Not browser-checked yet: steps 1, 3, 5, All set and the sheets on desktop. |
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
| ClientTrain | Not started |  |
| ClientTrainWeb | Not started |  |
| ClientVerifyEmail | Done | `/verify` (inbox, resend, Change email sheet, log out) and `/verify-email?token=` (checking, verified, link not valid). Checked 390. |
| ClientVerifyEmailWeb | Done | Same, desktop panel "Confirm your email". Checked 1440. |
| ClientWelcome | Partial | Shares the welcome / login / setup screens with ClientLogin (same code). Check this board separately before marking Done. |
| ClientWorkout | Not started |  |
| ClientWorkoutWeb | Not started |  |

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

