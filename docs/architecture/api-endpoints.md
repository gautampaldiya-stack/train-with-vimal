# API endpoints

Generated from the Django URL config. Base: `/api/v1/`. Full request/response shapes: `/api/docs/` (Swagger).

## accounts

| Path | Methods | View | Notes |
|---|---|---|---|
| `auth/account/delete/` | POST, DELETE | DeleteAccountView | Client More → Delete account. Data is removed after a 14-day grace period |
| `auth/email/cancel-change/` | POST | CancelEmailChangeView |  |
| `auth/email/change/` | POST | ChangeEmailView | Verify email screen → Change email: the old link stops working. |
| `auth/email/resend/` | POST | ResendVerifyEmailView |  |
| `auth/email/verify/` | POST | VerifyEmailView |  |
| `auth/login-link/accept/` | POST | AcceptLoginLinkView | "Your coach added you": pick a password and you are in (no approval needed). |
| `auth/login-link/check/` | POST | CheckLinkView | GET-like check used by Reset password / Login link / Verify email screens to show the |
| `auth/login-link/not-me/` | POST | LoginLinkNotMeView | Login link page → "These are not my details" → "This is not me": the link stops working and the coach is told. |
| `auth/login/` | POST | LoginView |  |
| `auth/logout/` | POST | LogoutView |  |
| `auth/me/` | GET, PUT, PATCH | MeView |  |
| `auth/password/change/` | POST | PasswordChangeView |  |
| `auth/password/forgot/` | POST | ForgotPasswordView | Board `ClientResetPassword`: an unknown email gets "No account uses this email. Check for a typo." |
| `auth/password/reset/` | POST | ResetPasswordView |  |
| `auth/password/reset/check/` | POST | CheckLinkView | GET-like check used by Reset password / Login link / Verify email screens to show the |
| `auth/refresh/` | POST | RefreshView | Rotates the refresh token. Fails if that device was logged out. |
| `auth/sessions/` | GET | SessionListView |  |
| `auth/sessions/<uuid:pk>/` | DELETE | SessionLogoutView |  |
| `auth/sessions/logout-others/` | POST | LogoutOthersView |  |

## activity

| Path | Methods | View | Notes |
|---|---|---|---|
| `activity/` | GET | ActivityViewSet | GET /activity/?range=7d&kind=plan&who=team&person=<id> |
| `activity/counts/` | GET | ActivityViewSet | GET /activity/?range=7d&kind=plan&who=team&person=<id> |
| `activity/export/` | GET | ActivityViewSet | GET /activity/?range=7d&kind=plan&who=team&person=<id> |
| `dashboard/admin/` | GET | AdminDashboardView |  |
| `dashboard/dismiss/` | POST | DismissView | × on a Needs action row. |
| `dashboard/trainer/` | GET | TrainerDashboardView |  |
| `me/home/` | GET | ClientHomeView |  |

## automations

| Path | Methods | View | Notes |
|---|---|---|---|
| `automations/` | GET, POST | AutomationViewSet | Automations are gym-wide: only the admin builds them. |
| `automations/<pk>/` | GET, PUT, PATCH, DELETE | AutomationViewSet | Automations are gym-wide: only the admin builds them. |
| `automations/<pk>/duplicate/` | POST | AutomationViewSet | Automations are gym-wide: only the admin builds them. |
| `automations/<pk>/restore/` | POST | AutomationViewSet | Automations are gym-wide: only the admin builds them. |
| `automations/<pk>/runs/` | GET | AutomationViewSet | Automations are gym-wide: only the admin builds them. |
| `automations/<pk>/save-draft/` | POST | AutomationViewSet | Automations are gym-wide: only the admin builds them. |
| `automations/<pk>/turn-off/` | POST | AutomationViewSet | Automations are gym-wide: only the admin builds them. |
| `automations/<pk>/turn-on/` | POST | AutomationViewSet | Automations are gym-wide: only the admin builds them. |
| `automations/catalog/` | GET | AutomationViewSet | Automations are gym-wide: only the admin builds them. |
| `automations/from-starter/` | POST | AutomationViewSet | Automations are gym-wide: only the admin builds them. |
| `automations/packages/` | GET | AutomationViewSet | Automations are gym-wide: only the admin builds them. |
| `automations/stats/` | GET | AutomationViewSet | Automations are gym-wide: only the admin builds them. |
| `tasks/` | GET, POST | TaskViewSet | Tasks card (dashboard): tick to finish, add by hand. |
| `tasks/<pk>/` | PUT, PATCH, DELETE | TaskViewSet | Tasks card (dashboard): tick to finish, add by hand. |
| `tasks/<pk>/done/` | POST | TaskViewSet | Tasks card (dashboard): tick to finish, add by hand. |

## checkins

| Path | Methods | View | Notes |
|---|---|---|---|
| `checkins/` | GET | CheckinReviewViewSet | Trainer → Check-ins, dashboard 'Check-ins to review', client profile → Logs → check-ins. |
| `checkins/<pk>/` | GET | CheckinReviewViewSet | Trainer → Check-ins, dashboard 'Check-ins to review', client profile → Logs → check-ins. |
| `checkins/<pk>/review/` | POST | CheckinReviewViewSet | Trainer → Check-ins, dashboard 'Check-ins to review', client profile → Logs → check-ins. |
| `checkins/<pk>/unreview/` | POST | CheckinReviewViewSet | Trainer → Check-ins, dashboard 'Check-ins to review', client profile → Logs → check-ins. |
| `checkins/counts/` | GET | CheckinReviewViewSet | Trainer → Check-ins, dashboard 'Check-ins to review', client profile → Logs → check-ins. |
| `clients/<uuid:client_pk>/forms/` | GET, POST | ClientFormsView | Client profile → Forms tab: sent forms (Filled / Waiting) + Send a form. |
| `clients/<uuid:client_pk>/progress/` | GET | ClientProgressView | Client profile → Progress tab (staff): weights, measurements, photo sets. |
| `forms/` | GET, POST | FormViewSet |  |
| `forms/<pk>/` | GET, PUT, PATCH, DELETE | FormViewSet |  |
| `forms/<pk>/answers/` | GET | FormViewSet |  |
| `forms/<pk>/archive/` | POST | FormViewSet |  |
| `forms/<pk>/duplicate/` | POST | FormViewSet |  |
| `forms/<pk>/publish/` | POST | FormViewSet |  |
| `forms/<pk>/questions/` | GET, PUT | FormViewSet |  |
| `forms/<pk>/restore/` | POST | FormViewSet |  |
| `forms/<pk>/unarchive/` | POST | FormViewSet |  |
| `forms/counts/` | GET | FormViewSet |  |
| `me/checkins/` | GET | MyCheckinsView | Check-ins page: the daily and weekly cards, the numbers on top, and past check-ins (weekly or daily, |
| `me/history/` | GET | MyHistoryView | Progress → History: every day's logs, newest first. ?range=week/month/3months &type=workout/meal/checkin/ |
| `me/measurements/` | GET, POST | MyMeasurementViewSet |  |
| `me/measurements/<pk>/` | DELETE | MyMeasurementViewSet |  |
| `me/photos/` | POST, DELETE | MyPhotoView | Add photos sheet: one pose into today's set (a file, or a data URL so it can wait in the offline outbox). |
| `me/progress/` | GET | MyProgressView | Progress tab: goal, every weigh-in (the app filters 4 wk / 12 wk / 6 mo / All), measurements, lifts, |
| `me/submissions/` | POST | MySubmissionViewSet | Send a check-in or a requested form; Edit answers; View what you sent. |
| `me/submissions/<pk>/` | GET, PATCH, DELETE | MySubmissionViewSet | Send a check-in or a requested form; Edit answers; View what you sent. |
| `me/weights/` | GET, POST | MyWeightViewSet |  |
| `me/weights/<pk>/` | DELETE | MyWeightViewSet |  |

## clients

| Path | Methods | View | Notes |
|---|---|---|---|
| `approvals/` | GET | ApprovalViewSet | ?tab=waiting/history plus filters from the design. |
| `approvals/<pk>/` | GET | ApprovalViewSet | ?tab=waiting/history plus filters from the design. |
| `approvals/<pk>/approve/` | POST | ApprovalViewSet | ?tab=waiting/history plus filters from the design. |
| `approvals/<pk>/ask-info/` | POST | ApprovalViewSet | ?tab=waiting/history plus filters from the design. |
| `approvals/<pk>/move-back/` | POST | ApprovalViewSet | ?tab=waiting/history plus filters from the design. |
| `approvals/<pk>/reject/` | POST | ApprovalViewSet | ?tab=waiting/history plus filters from the design. |
| `approvals/<pk>/trainers/` | GET | ApprovalViewSet | ?tab=waiting/history plus filters from the design. |
| `approvals/counts/` | GET | ApprovalViewSet | ?tab=waiting/history plus filters from the design. |
| `clients/` | GET, POST | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/<client_pk>[0-9a-f-]+)/notes/` | GET, POST | ClientNoteViewSet | /clients/<client_id>/notes/ — staff-only notes. |
| `clients/<client_pk>[0-9a-f-]+)/notes/<pk>/` | GET, PUT, PATCH, DELETE | ClientNoteViewSet | /clients/<client_id>/notes/ — staff-only notes. |
| `clients/<client_pk>[0-9a-f-]+)/notes/<pk>/restore/` | POST | ClientNoteViewSet | /clients/<client_id>/notes/ — staff-only notes. |
| `clients/<pk>/` | GET, PUT, PATCH, DELETE | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/<pk>/change-trainer/` | POST | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/<pk>/overview/` | GET | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/<pk>/pause/` | POST | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/<pk>/remind/` | POST | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/<pk>/restore/` | POST | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/<pk>/resume/` | POST | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/<pk>/stats/` | GET | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/counts/` | GET | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/export/` | GET | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/remind-at-risk/` | POST | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `invite-links/` | GET, POST | InviteLinkViewSet |  |
| `invite-links/<pk>/` | GET, PUT, PATCH, DELETE | InviteLinkViewSet |  |
| `invite-links/<pk>/restore/` | POST | InviteLinkViewSet |  |
| `invite-links/suggest-code/` | GET | InviteLinkViewSet |  |
| `invite-links/summary/` | GET | InviteLinkViewSet |  |
| `join/<str:code>/` | GET, POST | JoinLinkView | Public: GET shows the invite page, POST signs up. |
| `me/account/` | GET | MyAccountView | Client More tab: profile, coach card, plan rows, goal, reminders, deletion date, gym contact. |
| `me/activity/` | GET | MyActivityView | Client More → My activity: everything logged in the last 7 days, newest first, by day. |
| `me/data-export/` | POST | MyDataExportView | Client More → Privacy & data → Download my data: a ZIP is built in the background and the link |
| `me/onboarding/` | GET, POST, DELETE | MyOnboardingView | Client Welcome / profile setup: 5 steps, each can be saved alone ("Finish later"). |
| `me/report/` | POST | MyProblemReportView | Client More → Help & about → Report a problem. The admin gets it in the app and by email. |
| `me/trainer/` | GET | MyTrainerView | Client More → My trainer: only the fields the trainer switched on in What clients see. |

## content

| Path | Methods | View | Notes |
|---|---|---|---|
| `clients/<client_pk>[0-9a-f-]+)/content/` | GET, POST | ClientContentView | Client profile → Content tab: share / unshare. |
| `clients/<client_pk>[0-9a-f-]+)/content/<pk>/unshare/` | POST | ClientContentView | Client profile → Content tab: share / unshare. |
| `content-categories/` | GET, POST | CategoryViewSet |  |
| `content-categories/<pk>/` | GET, PUT, PATCH, DELETE | CategoryViewSet |  |
| `content/` | GET, POST | ContentViewSet |  |
| `content/<pk>/` | GET, PUT, PATCH, DELETE | ContentViewSet |  |
| `content/<pk>/assign/` | GET, POST | ContentViewSet |  |
| `content/<pk>/detail/` | GET | ContentViewSet |  |
| `content/<pk>/restore/` | POST | ContentViewSet |  |
| `me/library/` | GET | MyLibraryViewSet | Client Library: shared with me, with everyone, or with my program / meal plan. |
| `me/library/<pk>/` | GET | MyLibraryViewSet | Client Library: shared with me, with everyone, or with my program / meal plan. |
| `me/library/<pk>/progress/` | POST | MyLibraryViewSet | Client Library: shared with me, with everyone, or with my program / meal plan. |

## gym

| Path | Methods | View | Notes |
|---|---|---|---|
| `gym/` | GET | PublicGymView | Gym name, contact and live branding. Public: the signed-out "Need help logging in?" sheet uses it too. |
| `settings/branding/` | GET, PATCH | BrandingView | PATCH saves a draft ("Not applied yet"); POST apply makes it live for every client. |
| `settings/branding/apply/` | POST | BrandingApplyView |  |
| `settings/branding/logo/` | POST, DELETE | LogoView |  |
| `settings/branding/reset/` | POST | BrandingResetView |  |
| `settings/gym/` | GET, PATCH | GymProfileView |  |
| `settings/integrations/` | GET | IntegrationListView |  |
| `settings/integrations/<str:kind>/<str:op>/` | POST | IntegrationActionView | POST connect / disconnect / check. Real provider keys stay in .env; this records state. |
| `settings/roles/` | GET, PUT | RoleMatrixView |  |

## habits

| Path | Methods | View | Notes |
|---|---|---|---|
| `clients/<uuid:client_pk>/habits/` | GET | ClientHabitsView | Client profile → Logs → Habits / Supplements (staff, read only). |
| `habits/` | GET, POST | HabitViewSet |  |
| `habits/<pk>/` | GET, PUT, PATCH, DELETE | HabitViewSet |  |
| `habits/<pk>/assign/` | GET, POST | HabitViewSet |  |
| `habits/<pk>/duplicate/` | POST | HabitViewSet |  |
| `habits/<pk>/restore/` | POST | HabitViewSet |  |
| `me/habits/` | GET | MyHabitsView | Habits & supplements page (?date=): the day, its Mon–Sun week grid (`week`), start dates, supplement groups. |
| `me/habits/<uuid:habit_id>/log/` | POST | MyHabitLogView | POST {value} for a counter (steps / glasses / minutes) or {done} for a tick. |
| `me/supplements/<int:item_id>/` | POST, PATCH | MySupplementView | POST take / untake (Undo), PATCH stock. |
| `supplement-plans/` | GET, POST | SupplementPlanViewSet |  |
| `supplement-plans/<pk>/` | GET, PUT, PATCH, DELETE | SupplementPlanViewSet |  |
| `supplement-plans/<pk>/assign/` | GET, POST | SupplementPlanViewSet |  |
| `supplement-plans/<pk>/duplicate/` | POST | SupplementPlanViewSet |  |
| `supplement-plans/<pk>/restore/` | POST | SupplementPlanViewSet |  |
| `supplement-plans/quick-add/` | GET | SupplementPlanViewSet |  |

## notifications

| Path | Methods | View | Notes |
|---|---|---|---|
| `devices/` | POST, DELETE | DeviceTokenView | POST registers this phone/browser for push. DELETE (with token) removes it on logout. |
| `me/reminders/` | GET, POST, PUT, PATCH | ReminderPreferenceView |  |
| `me/staff-notifications/` | GET, PUT, PATCH | StaffNotificationPreferenceView |  |
| `message-templates/` | GET, POST | MessageTemplateViewSet | Emails & alerts → Client messages (admin only). |
| `message-templates/<pk>/` | GET, PUT, PATCH, DELETE | MessageTemplateViewSet | Emails & alerts → Client messages (admin only). |
| `message-templates/<pk>/preview/` | GET | MessageTemplateViewSet | Emails & alerts → Client messages (admin only). |
| `message-templates/<pk>/reset/` | POST | MessageTemplateViewSet | Emails & alerts → Client messages (admin only). |
| `message-templates/stats/` | GET | MessageTemplateViewSet | Emails & alerts → Client messages (admin only). |
| `message-templates/variables/` | GET | MessageTemplateViewSet | Emails & alerts → Client messages (admin only). |
| `notifications/` | GET | NotificationViewSet | Bell panel / Notifications page. ?unread=1 for the Unread tab. |
| `notifications/<pk>/` | DELETE | NotificationViewSet | Bell panel / Notifications page. ?unread=1 for the Unread tab. |
| `notifications/<pk>/read/` | POST | NotificationViewSet | Bell panel / Notifications page. ?unread=1 for the Unread tab. |
| `notifications/<pk>/unread_one/` | POST | NotificationViewSet | Bell panel / Notifications page. ?unread=1 for the Unread tab. |
| `notifications/read_all/` | POST | NotificationViewSet | Bell panel / Notifications page. ?unread=1 for the Unread tab. |
| `notifications/unread/` | GET | NotificationViewSet | Bell panel / Notifications page. ?unread=1 for the Unread tab. |
| `settings/notifications/` | GET, PUT, PATCH | NotificationSettingsView | Quiet hours + sender identity. |
| `team-alerts/` | GET | TeamAlertSettingViewSet |  |
| `team-alerts/<pk>/` | PUT, PATCH | TeamAlertSettingViewSet |  |

## nutrition

| Path | Methods | View | Notes |
|---|---|---|---|
| `clients/<uuid:client_pk>/food/` | GET | ClientFoodLogView | Client profile → Logs → Meals: one day, or a date range summary. |
| `food-picker/` | GET | FoodPickerView | Builder → Add food: team foods first, grouped. |
| `foods/` | GET, POST | FoodViewSet | Food library (staff). Clients search foods through /me/foods/. |
| `foods/<pk>/` | GET, PUT, PATCH, DELETE | FoodViewSet | Food library (staff). Clients search foods through /me/foods/. |
| `foods/<pk>/delete-preview/` | GET | FoodViewSet | Food library (staff). Clients search foods through /me/foods/. |
| `foods/<pk>/duplicate/` | POST | FoodViewSet | Food library (staff). Clients search foods through /me/foods/. |
| `foods/<pk>/restore/` | POST | FoodViewSet | Food library (staff). Clients search foods through /me/foods/. |
| `foods/<pk>/swap-options/` | GET | FoodViewSet | Food library (staff). Clients search foods through /me/foods/. |
| `foods/<pk>/used-in/` | GET | FoodViewSet | Food library (staff). Clients search foods through /me/foods/. |
| `foods/counts/` | GET | FoodViewSet | Food library (staff). Clients search foods through /me/foods/. |
| `foods/import/<job_id>[0-9a-f-]+)/run/` | POST | FoodViewSet | Food library (staff). Clients search foods through /me/foods/. |
| `foods/import/<job_id>[0-9a-f-]+)/undo/` | POST | FoodViewSet | Food library (staff). Clients search foods through /me/foods/. |
| `foods/import/check/` | POST | FoodViewSet | Food library (staff). Clients search foods through /me/foods/. |
| `foods/import/template/` | GET | FoodViewSet | Food library (staff). Clients search foods through /me/foods/. |
| `me/food-log/` | POST | MyFoodLogViewSet |  |
| `me/food-log/<pk>/` | DELETE | MyFoodLogViewSet |  |
| `me/food-log/copy-yesterday/` | POST | MyFoodLogViewSet |  |
| `me/food-log/undo-copy/` | POST | MyFoodLogViewSet |  |
| `me/food-log/water/` | POST | MyFoodLogViewSet |  |
| `me/food/` | GET | MyFoodView | Food tab (combined meal plan + nutrition): GET ?date=YYYY-MM-DD. |
| `me/food/items/<int:item_id>/swaps/` | GET | MySwapOptionsView | Swap sheet for one planned food: approved swaps with match % and matched grams. |
| `me/food/meals/<int:meal_id>/<str:op>/` | POST | MyMealActionView | POST /me/food/meals/<meal_id>/<op>/  op = eat / unlog / skip / unskip / portions / swap / option |
| `me/foods/` | GET, POST | MyFoodSearchViewSet | Log food: search team foods + 'My foods'; create a custom food (saved to My foods). |
| `me/foods/recent/` | GET | MyFoodSearchViewSet | Log food: search team foods + 'My foods'; create a custom food (saved to My foods). |
| `meal-plans/` | GET, POST | MealPlanViewSet |  |
| `meal-plans/<pk>/` | GET, PUT, PATCH, DELETE | MealPlanViewSet |  |
| `meal-plans/<pk>/assign/` | POST | MealPlanViewSet |  |
| `meal-plans/<pk>/clients/` | GET | MealPlanViewSet |  |
| `meal-plans/<pk>/clients/<client_id>[0-9a-f-]+)/remove/` | POST | MealPlanViewSet |  |
| `meal-plans/<pk>/clients/<client_id>[0-9a-f-]+)/reset/` | POST | MealPlanViewSet |  |
| `meal-plans/<pk>/clients/<client_id>[0-9a-f-]+)/version-note/` | PUT | MealPlanViewSet |  |
| `meal-plans/<pk>/duplicate/` | POST | MealPlanViewSet |  |
| `meal-plans/<pk>/publish-preview/` | GET | MealPlanViewSet |  |
| `meal-plans/<pk>/publish/` | POST | MealPlanViewSet |  |
| `meal-plans/<pk>/restore/` | POST | MealPlanViewSet |  |
| `meal-plans/<pk>/structure/` | PUT | MealPlanViewSet |  |
| `meal-plans/counts/` | GET | MealPlanViewSet |  |

## scheduling

| Path | Methods | View | Notes |
|---|---|---|---|
| `availability/` | GET, PUT | AvailabilityView | Availability / My working hours drawer. |
| `me/sessions/` | GET | MySessionsView | Client app: upcoming sessions (Home 'Session with', Coming up). |
| `sessions/` | GET, POST | SessionViewSet | Calendar (admin: all trainers; trainer: own sessions). |
| `sessions/<pk>/` | GET, PUT, PATCH, DELETE | SessionViewSet | Calendar (admin: all trainers; trainer: own sessions). |
| `sessions/<pk>/restore/` | POST | SessionViewSet | Calendar (admin: all trainers; trainer: own sessions). |
| `sessions/<pk>/status/` | POST | SessionViewSet | Calendar (admin: all trainers; trainer: own sessions). |
| `sessions/check/` | GET | SessionViewSet | Calendar (admin: all trainers; trainer: own sessions). |
| `sessions/stats/` | GET | SessionViewSet | Calendar (admin: all trainers; trainer: own sessions). |

## trainers

| Path | Methods | View | Notes |
|---|---|---|---|
| `access-requests/` | GET, POST | AccessRequestViewSet | Trainer → Ask for more access. Admin approves or declines. |
| `access-requests/<pk>/approve/` | POST | AccessRequestViewSet | Trainer → Ask for more access. Admin approves or declines. |
| `access-requests/<pk>/decline/` | POST | AccessRequestViewSet | Trainer → Ask for more access. Admin approves or declines. |
| `trainers/` | GET, POST | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/` | GET, PUT, PATCH, DELETE | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/access/` | GET, PUT | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/assign-clients/` | POST | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/assignable-clients/` | GET | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/deactivate-preview/` | GET | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/deactivate/` | POST | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/move-clients/` | POST | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/password-reset/` | POST | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/reactivate/` | POST | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/stats/` | GET | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/visibility/` | GET, PUT | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<trainer_pk>me|[0-9a-f-]+)/documents/` | GET, POST | TrainerDocumentViewSet | Documents tab. Admin manages any trainer's documents; a trainer uploads and sees their own |
| `trainers/<trainer_pk>me|[0-9a-f-]+)/documents/<pk>/` | GET, PUT, PATCH, DELETE | TrainerDocumentViewSet | Documents tab. Admin manages any trainer's documents; a trainer uploads and sees their own |
| `trainers/<trainer_pk>me|[0-9a-f-]+)/documents/<pk>/verify/` | POST | TrainerDocumentViewSet | Documents tab. Admin manages any trainer's documents; a trainer uploads and sees their own |
| `trainers/export/` | GET | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/me/` | GET, PATCH | TrainerMeView | Trainer → Me: own profile, stats, read-only access, visibility. |
| `trainers/me/visibility/` | GET, PUT | TrainerMeVisibilityView |  |
| `trainers/summary/` | GET | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/with-space/` | GET | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |

## training

| Path | Methods | View | Notes |
|---|---|---|---|
| `clients/<client_pk>[0-9a-f-]+)/programs/` | GET, POST | ClientProgramViewSet | Client profile → Plans → Workout slot. |
| `clients/<client_pk>[0-9a-f-]+)/programs/<pk>/custom-structure/` | GET, PUT | ClientProgramViewSet | Client profile → Plans → Workout slot. |
| `clients/<client_pk>[0-9a-f-]+)/programs/<pk>/customise/` | POST | ClientProgramViewSet | Client profile → Plans → Workout slot. |
| `clients/<client_pk>[0-9a-f-]+)/programs/<pk>/end/` | POST | ClientProgramViewSet | Client profile → Plans → Workout slot. |
| `clients/<client_pk>[0-9a-f-]+)/programs/<pk>/new-from/` | POST | ClientProgramViewSet | Client profile → Plans → Workout slot. |
| `clients/<client_pk>[0-9a-f-]+)/programs/<pk>/replace/` | POST | ClientProgramViewSet | Client profile → Plans → Workout slot. |
| `clients/<client_pk>[0-9a-f-]+)/programs/<pk>/reset-to-master/` | POST | ClientProgramViewSet | Client profile → Plans → Workout slot. |
| `clients/<client_pk>[0-9a-f-]+)/programs/compare/` | GET | ClientProgramViewSet | Client profile → Plans → Workout slot. |
| `clients/<client_pk>[0-9a-f-]+)/workouts/` | GET | ClientWorkoutLogViewSet | Client profile → Logs → Workouts (staff, read only). |
| `clients/<client_pk>[0-9a-f-]+)/workouts/<pk>/` | GET | ClientWorkoutLogViewSet | Client profile → Logs → Workouts (staff, read only). |
| `exercise-picker/` | GET | ExercisePickerView | Add exercise picker in the builder: muscle chips with counts + rows. |
| `exercises/` | GET, POST | ExerciseViewSet |  |
| `exercises/<pk>/` | GET, PUT, PATCH, DELETE | ExerciseViewSet |  |
| `exercises/<pk>/duplicate/` | POST | ExerciseViewSet |  |
| `exercises/<pk>/restore/` | POST | ExerciseViewSet |  |
| `exercises/<pk>/used-in/` | GET | ExerciseViewSet |  |
| `exercises/facets/` | GET | ExerciseViewSet |  |
| `me/train/` | GET | MyTrainView | Train tab: week strip, today's workout with targets, last time and PRs, the running workout. |
| `me/workouts/` | GET, POST | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/<pk>/` | GET | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/<pk>/clear-sets/` | POST | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/<pk>/discard/` | POST | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/<pk>/feedback/` | POST | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/<pk>/finish/` | POST | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/<pk>/pause/` | POST | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/<pk>/reopen/` | POST | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/<pk>/restart/` | POST | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/<pk>/restore-set/` | POST | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/<pk>/resume/` | POST | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/<pk>/retick-sets/` | POST | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/<pk>/sets/` | POST | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/<pk>/sets/<set_id>\d+)/` | PATCH, DELETE | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/<pk>/state/` | PUT | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/exercise-history/` | GET | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/sync/` | POST | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `programs/` | GET, POST | ProgramViewSet |  |
| `programs/<pk>/` | GET, PUT, PATCH, DELETE | ProgramViewSet |  |
| `programs/<pk>/archive/` | POST | ProgramViewSet |  |
| `programs/<pk>/assign/` | POST | ProgramViewSet |  |
| `programs/<pk>/clients/` | GET | ProgramViewSet |  |
| `programs/<pk>/copy-week/` | POST | ProgramViewSet |  |
| `programs/<pk>/delete-preview/` | GET | ProgramViewSet |  |
| `programs/<pk>/duplicate/` | POST | ProgramViewSet |  |
| `programs/<pk>/restore/` | POST | ProgramViewSet |  |
| `programs/<pk>/structure/` | PUT | ProgramViewSet |  |
| `programs/<pk>/unarchive/` | POST | ProgramViewSet |  |
| `programs/assign-options/` | GET | ProgramViewSet |  |
| `programs/counts/` | GET | ProgramViewSet |  |
