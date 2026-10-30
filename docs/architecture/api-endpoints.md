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
| `auth/me/` | GET, PUT, PATCH | MeView | Includes `permissions` for a trainer (effective permissions, D-54), null for others. |
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
| `activity/` | GET | ActivityViewSet | GET /activity/?range=7d&kind=plan&who=team&person=<id>&search=. `search` matches the person, the client, the item or the change text (Activity log, D-48). Cursor paged. |
| `activity/counts/` | GET | ActivityViewSet | GET /activity/?range=7d&kind=plan&who=team&person=<id> |
| `activity/export/` | GET | ActivityViewSet | GET /activity/?range=7d&kind=plan&who=team&person=<id> |
| `dashboard/admin/` | GET | AdminDashboardView | Admin Dashboard in one call: greeting, `subline`, stats, glance (`onboarding_pending.forms_missing`), `needs_action` rows `{key, kind, title, sub, cta, route}`, trainer performance (`?period=month` = 30-day adherence), at-risk, recent activity, bell `notices` + `unread`. |
| `dashboard/dismiss/` | POST | DismissView | × on a Needs action row. |
| `dashboard/trainer/` | GET | TrainerDashboardView | Trainer dashboard: stats, Today, Clients who need you, Check-ins to review, This week, bell list. |
| `dashboard/trainer/activity/` | GET | TrainerActivityView | Next page of the dashboard's Activity card: `?before=<next>` from the previous page. |
| `me/home/` | GET | ClientHomeView |  |

## automations

| Path | Methods | View | Notes |
|---|---|---|---|
| `automations/` | GET, POST | AutomationViewSet | Admin, or a trainer with `automations.manage` (D-54); oldest first (D-51). Automations with a hidden trigger (`package_ending`, D-55) are not listed or counted. Rows: trigger_line (board words), scope_package, scope_trainer + scope_trainer_name, stop_on_response, steps (each with summary), counts {running, finished, stopped}. POST saves as draft. |
| `automations/<pk>/` | GET, PUT, PATCH, DELETE | AutomationViewSet | Automations are gym-wide: only the admin builds them. |
| `automations/<pk>/duplicate/` | POST | AutomationViewSet | Automations are gym-wide: only the admin builds them. |
| `automations/<pk>/restore/` | POST | AutomationViewSet | Automations are gym-wide: only the admin builds them. |
| `automations/<pk>/runs/` | GET | AutomationViewSet | Builder → Last 30 days: started / finished / stopped (last 30 days) + the latest 20 runs (client, status, step_index, steps_total, last_message). |
| `automations/<pk>/save-draft/` | POST | AutomationViewSet | Automations are gym-wide: only the admin builds them. |
| `automations/<pk>/turn-off/` | POST | AutomationViewSet | Automations are gym-wide: only the admin builds them. |
| `automations/<pk>/turn-on/` | POST | AutomationViewSet | Turns it on; 400 `not_ready` with fields.problems when something is missing. |
| `automations/catalog/` | GET | AutomationViewSet | Triggers (group, line, settings with limits; Plan ends / Package ending have a time) and starters (with trigger_line and step_count). Package ending and its Renewal reminder starter are hidden (D-55). |
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
| `clients/<uuid:client_pk>/checkins/` | GET | ClientCheckinLogView | Client profile → Logs → Daily / Weekly check-ins (staff): `?kind=daily/weekly&range=&page=`. One row per |
| `clients/<uuid:client_pk>/forms/` | GET, POST | ClientFormsView | GET: the tab's list (`sent`) and the library forms to send (`can_send`). |
| `clients/<uuid:client_pk>/forms/<str:key>/` | GET, POST | ClientFormView | One form of the list: GET the card; POST an action: remind · send_now · stop · start · reset. |
| `clients/<uuid:client_pk>/forms/<str:key>/<str:act>/` | GET, POST | ClientFormView | One form of the list: GET the card; POST an action: remind · send_now · stop · start · reset. |
| `clients/<uuid:client_pk>/forms/<str:key>/questions/` | GET, PUT | ClientFormQuestionsView | The per-client editor ("Edit Weekly check-in for Riya"): GET the questions of her copy (or of the master |
| `clients/<uuid:client_pk>/forms/duplicate/` | POST | ClientFormDuplicateView | Duplicate and edit → Send copy: a new form only for her {source: list key / form: library id, name, |
| `clients/<uuid:client_pk>/progress/` | GET | ClientProgressView | Client profile → Progress tab (staff): weights, measurements, photo sets. |
| `forms/` | GET, POST | FormViewSet | Library forms (`tab=archived`, `type`, `search`). Rows: question_count, sent_by (automations), built_in (how the app asks it, D-50), has_draft. POST {name, type, start: template / blank}. |
| `forms/<pk>/` | GET, PUT, PATCH, DELETE | FormViewSet | GET: the builder: questions (the draft when there is one), sent_by, built_in, stats {sent, answered, rate, latest} this month (D-50). PATCH name / type. DELETE soft (Undo = restore/). |
| `forms/<pk>/answers/` | GET | FormViewSet |  |
| `forms/<pk>/archive/` | POST | FormViewSet |  |
| `forms/<pk>/duplicate/` | POST | FormViewSet |  |
| `forms/<pk>/draft/` | POST | FormViewSet | Move back to draft: start a draft of a published form; clients keep the live questions (D-50). |
| `forms/<pk>/discard/` | POST | FormViewSet | Throw the draft away (Undo of Move back to draft). |
| `forms/<pk>/publish/` | POST | FormViewSet | Writes the draft into the questions and publishes; returns the detail. |
| `forms/<pk>/questions/` | GET, PUT | FormViewSet | PUT the whole list (≤ 80). On a published form it is saved as the draft (D-50); onboarding questions with a profile_key keep their type and options. |
| `forms/<pk>/restore/` | POST | FormViewSet |  |
| `forms/<pk>/unarchive/` | POST | FormViewSet |  |
| `forms/counts/` | GET | FormViewSet |  |
| `me/checkins/` | GET | MyCheckinsView | Check-ins page: the daily and weekly cards, `forms` (forms the coach sent: waiting + filled in 14 days, D-49), the numbers on top, and past check-ins (weekly or daily, |
| `me/forms/<id>/` | GET | MyFormView | A form the coach sent: card fields, questions (`form`), and once filled `submission` {id, sent_at, answers}. Another client's request is 404 (D-49). |
| `me/history/` | GET | MyHistoryView | Progress → History: every day's logs, newest first. ?range=week/month/3months &type=workout/meal/checkin/ |
| `me/measurements/` | GET, POST | MyMeasurementViewSet |  |
| `me/measurements/<pk>/` | DELETE | MyMeasurementViewSet |  |
| `me/photos/` | POST, DELETE | MyPhotoView | Add photos sheet: one pose into today's set (a file, or a data URL so it can wait in the offline outbox). DELETE `?id=` only for her own set on the day it was added (D-86); the empty set goes too. |
| `me/progress/` | GET | MyProgressView | Progress tab: goal, every weigh-in (the app filters 4 wk / 12 wk / 6 mo / All), measurements, lifts, |
| `me/submissions/` | POST | MySubmissionViewSet | Send a check-in or a requested form (`request` = the form request id; a filled request is refused). Edit answers; View what you sent. Delete (Undo) puts a requested form back to To fill. |
| `me/submissions/<pk>/` | GET, PATCH, DELETE | MySubmissionViewSet | Send a check-in or a requested form; Edit answers; View what you sent. |
| `me/weights/` | GET, POST | MyWeightViewSet |  |
| `me/weights/<pk>/` | DELETE | MyWeightViewSet |  |

## clients

| Path | Methods | View | Notes |
|---|---|---|---|
| `approvals/` | GET | ApprovalViewSet | Approvals page (admin; a trainer sees people they invited). `?tab=waiting/history&q=` (name, email, phone digits), Waiting filters `invited_by, setup=done/not_finished, waiting=1d/2d, health_note=yes/no, signed_up_from=web/android/ios`, History filters `decision, decided_by, when=7d/30d`, 20 a page. Waiting is oldest first with moved-back people on top. Rows carry `signed_up_from_label`, `setup_done` (0–5), `waiting_hours`, `has_health_note`, `moved_back` (D-47). |
| `approvals/<pk>/` | GET | ApprovalViewSet | Review drawer: the row plus `steps`, `health_notes`, `invite_code`, `answers` [{label, value}] from onboarding (Goal, Body, Trains, Food). |
| `approvals/<pk>/approve/` | POST | ApprovalViewSet | `{trainer, tell_client, ask_finish_setup}`: client becomes active with that trainer. 400 when the trainer is full. |
| `approvals/<pk>/ask-info/` | POST | ApprovalViewSet | `{items: [setup, health_form, doctor_note, photo, phone], channels: [whatsapp, email, in_app, push], message}` → `{asked}`. The person stays in Waiting. |
| `approvals/<pk>/move-back/` | POST | ApprovalViewSet | History → back to Waiting (`moved_back` true, shows on top). An approved client cannot log in again until approved. `{tell_client}`. |
| `approvals/<pk>/reject/` | POST | ApprovalViewSet | `{reason: not_fit/has_account/fake/no_trainer/other, message, tell_client}`; `other` needs a message. |
| `approvals/<pk>/trainers/` | GET | ApprovalViewSet | Trainer pick in the Review drawer: load, `max_clients`, `tag` (full / invited / good_fit), `default`. |
| `approvals/counts/` | GET | ApprovalViewSet | `{waiting, history, oldest_hours}`: tab counts, sidebar badge and "oldest waiting 2 days". |
| `clients/` | GET, POST | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. Admin rows add `trainer`, `date_joined`, `gender`; `?trainer=<id>/none`. POST (admin, Add client): name + phone required; `mode=active/approvals`, optional trainer, `program`, `meal_plan`, `start_date`, send-link / PAR-Q switches; all in one transaction. PATCH `password` is admin only (min 8, hashed, signs the client out everywhere). |
| `clients/<client_pk>[0-9a-f-]+)/notes/` | GET, POST | ClientNoteViewSet | /clients/<client_id>/notes/ — staff-only notes. |
| `clients/<client_pk>[0-9a-f-]+)/notes/<pk>/` | GET, PUT, PATCH, DELETE | ClientNoteViewSet | /clients/<client_id>/notes/ — staff-only notes. |
| `clients/<client_pk>[0-9a-f-]+)/notes/<pk>/restore/` | POST | ClientNoteViewSet | /clients/<client_id>/notes/ — staff-only notes. |
| `clients/<pk>/` | GET, PUT, PATCH, DELETE | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/<pk>/change-trainer/` | POST | ClientViewSet | Admin, or a trainer with `clients.assign` / `clients.view_all` (D-54). `{trainer, move_checkins (default true), tell_old, note}`. Same trainer → 400, full trainer → 400. `move_checkins=false` marks open check-ins as seen so the new trainer starts fresh; the note is saved as a client note; `trainer_since` is set (D-47). |
| `clients/<pk>/send-reset/` | POST | ClientViewSet | Admin. Emails a password reset link → `{sent_to}`; 400 `no_email`. |
| `clients/<pk>/trainers/` | GET | ClientViewSet | Admin, or a trainer with `clients.assign` / `clients.view_all` (D-54). Change trainer drawer: `{trainers: [{…, clients, max_clients, current, full, good_fit}], current, since, open_checkins}`. |
| `clients/<pk>/history/` | GET | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/<pk>/overview/` | GET | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/<pk>/pause/` | POST | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/<pk>/remind/` | POST | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/<pk>/restore/` | POST | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/<pk>/resume/` | POST | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/<pk>/stats/` | GET | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/<uuid:client_pk>/logs/comment/` | POST | ClientLogCommentView | POST clients/<id>/logs/comment/ {about: workout/meals, date, text}: the client gets it in the app. |
| `clients/<uuid:client_pk>/logs/compare/` | GET | ClientLogCompareView | GET clients/<id>/logs/compare/ → A and B side by side. Each side is a workout plan |
| `clients/<uuid:client_pk>/logs/summary/` | GET | ClientLogSummaryView | GET clients/<id>/logs/summary/?range= → {from, to, workouts, meals, checkins}. |
| `clients/counts/` | GET | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/check-phone/` | GET | ClientViewSet | Admin, Add client while typing: `?phone=` → `{valid, taken}` (`taken` = "phone" when a client or sign-up has it). |
| `clients/export/` | GET | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `clients/remind-at-risk/` | POST | ClientViewSet | Clients (admin) and My clients (trainer). Trainers only ever see their own clients. |
| `invite-links/` | GET, POST | InviteLinkViewSet | A trainer needs `clients.invite` (else 403 for every invite-links call); POST also needs `clients.invite_new` and always makes the link for himself. Rows carry `access_off` (the trainer's invite access is off, so the link is `off`). |
| `invite-links/<pk>/` | GET, PUT, PATCH, DELETE | InviteLinkViewSet | A trainer cannot move a link to another trainer (403). |
| `invite-links/<pk>/restore/` | POST | InviteLinkViewSet |  |
| `invite-links/suggest-code/` | GET | InviteLinkViewSet |  |
| `invite-links/summary/` | GET | InviteLinkViewSet |  |
| `join/<str:code>/` | GET, POST | JoinLinkView | Public: GET shows the invite page, POST signs up. |
| `me/account/` | GET | MyAccountView | Client More tab: profile, coach card, plan rows, goal, reminders, deletion date, gym contact. |
| `me/activity/` | GET | MyActivityView | Client More → My activity: everything logged in the last 7 days, newest first, by day. |
| `me/data-export/` | POST | MyDataExportView | Client More → Privacy & data → Download my data: a ZIP is built in the background and the link |
| `me/onboarding/` | GET, POST, DELETE | MyOnboardingView | Client profile setup: the gym's coaching form in steps (D-36), each saved alone ("Finish later"). |
| `me/report/` | POST | MyProblemReportView | Client More → Help & about → Report a problem. The admin gets it in the app and by email. |
| `me/trainer/` | GET | MyTrainerView | Client More → My trainer: only the fields the trainer switched on in What clients see. |

## content

| Path | Methods | View | Notes |
|---|---|---|---|
| `clients/<client_pk>[0-9a-f-]+)/content/` | GET, POST | ClientContentView | Client profile → Content tab: what she sees and why (`?why=all/assigned/plan/everyone&q=&page=`), Assign |
| `clients/<client_pk>[0-9a-f-]+)/content/<pk>[0-9a-f-]+)/remind/` | POST | ClientContentView | Client profile → Content tab: what she sees and why (`?why=all/assigned/plan/everyone&q=&page=`), Assign |
| `clients/<client_pk>[0-9a-f-]+)/content/<pk>[0-9a-f-]+)/restore/` | POST | ClientContentView | Client profile → Content tab: what she sees and why (`?why=all/assigned/plan/everyone&q=&page=`), Assign |
| `clients/<client_pk>[0-9a-f-]+)/content/<pk>[0-9a-f-]+)/unshare/` | POST | ClientContentView | Client profile → Content tab: what she sees and why (`?why=all/assigned/plan/everyone&q=&page=`), Assign |
| `clients/<client_pk>[0-9a-f-]+)/content/<pk>[0-9a-f-]+)/until/` | POST | ClientContentView | Client profile → Content tab: what she sees and why (`?why=all/assigned/plan/everyone&q=&page=`), Assign |
| `clients/<client_pk>[0-9a-f-]+)/content/library/` | GET | ClientContentView | Client profile → Content tab: what she sees and why (`?why=all/assigned/plan/everyone&q=&page=`), Assign |
| `content-categories/` | GET, POST | CategoryViewSet |  |
| `content-categories/<pk>/` | GET, PUT, PATCH, DELETE | CategoryViewSet |  |
| `content/` | GET, POST | ContentViewSet | Rows carry `thumb_url`: the cover, else the picked `frame`, else a video's first frame (ffmpeg, saved once), else the YouTube still. Also `length_label` ("0:42", "6 pages", "PNG", "4 min read"), `uses` (exercises and programs that show it), `who` (Everyone / client name / N clients / Not assigned), `file_name`. `?kind=&category=&search=&page_size=`. Upload fills length, resolution or page count. An upload past `CONTENT_STORAGE_GB` is refused (400 on `file`). |
| `content/stage/` | POST | ContentViewSet | New video before Save (multipart `file`): keeps it under `content/staging/` and gives back `{upload, frames}` so the cover frame can be picked at once. Then `content/` POST / PATCH with `upload` instead of `file`. 400 when storage is full. (D-45) |
| `content/summary/` | GET | ContentViewSet | Content library page: `{total, storage: {used, limit}, can: {manage, everyone}}` (limit = `CONTENT_STORAGE_GB`, 20 GB; `everyone` = Vimal only). |
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
| `gym/` | GET | PublicGymView | Gym name, contact (+ `website`, `instagram`, `youtube`, `facebook`) and live branding. Public: the signed-out "Need help logging in?" sheet uses it too. |
| `settings/branding/` | GET, PATCH | BrandingView | PATCH saves a draft ("Not applied yet"); picking the live value again clears it. GET also gives `logo_name`, `logo_px`, `name`. |
| `settings/branding/apply/` | POST | BrandingApplyView | Makes the draft live. |
| `settings/branding/logo/` | POST, DELETE | LogoView | PNG / JPG / WebP / SVG, at least 512 x 512, max 5 MB; live at once. |
| `settings/branding/reset/` | POST | BrandingResetView | Blue + light, live at once. |
| `settings/gym/` | GET, PATCH | GymProfileView | Gym profile incl. social links `website`, `instagram`, `youtube`, `facebook` (moves `profile_saved_at`) and Regional & defaults (`default_units`, `week_start`, `timezone`, `language`); GET adds `timezones`, `languages`. |
| `settings/integrations/` | GET | IntegrationListView | whatsapp, email_domain, health with `status`, `config`, `meta` (card line) and `used` (Used in links). |
| `settings/integrations/<str:kind>/<str:op>/` | POST | IntegrationActionView | op connect / save (`config`: number, domain + `local` (From address part before @, D-55) or types), check (email DNS), disconnect, undo (`status`). WhatsApp off skips WhatsApp sends; a verified domain is the from-address. |
| `settings/roles/` | GET, PUT | RoleMatrixView | Matrix plus `defaults`, `locked` cells and `counts` (active trainers, active clients). Locked cells keep their value on PUT. |

## habits

| Path | Methods | View | Notes |
|---|---|---|---|
| `clients/<client_pk>[0-9a-f-]+)/habit-plan/` | GET, POST | ClientHabitPlansViewSet |  |
| `clients/<client_pk>[0-9a-f-]+)/habit-plan/<pk>/` | PATCH | ClientHabitPlansViewSet |  |
| `clients/<client_pk>[0-9a-f-]+)/habit-plan/<pk>/end/` | POST | ClientHabitPlansViewSet |  |
| `clients/<client_pk>[0-9a-f-]+)/supplement-plans/` | GET, POST | ClientSupplementPlansViewSet |  |
| `clients/<client_pk>[0-9a-f-]+)/supplement-plans/<pk>/end/` | POST | ClientSupplementPlansViewSet |  |
| `clients/<client_pk>[0-9a-f-]+)/supplement-plans/<pk>/items/` | PUT | ClientSupplementPlansViewSet |  |
| `clients/<client_pk>[0-9a-f-]+)/supplement-plans/<pk>/reset/` | POST | ClientSupplementPlansViewSet |  |
| `clients/<uuid:client_pk>/habits/` | GET | ClientHabitsView | Client profile → Logs → Habits / Supplements (staff, read only). |
| `habits/` | GET, POST | HabitViewSet |  |
| `habits/<pk>/` | GET, PUT, PATCH, DELETE | HabitViewSet |  |
| `habits/<pk>/assign/` | GET, POST | HabitViewSet |  |
| `habits/<pk>/duplicate/` | POST | HabitViewSet |  |
| `habits/<pk>/restore/` | POST | HabitViewSet |  |
| `habits/counts/` | GET | HabitViewSet | Habits & supplements page: tab counts (`habits`, `supplements`) and `can` {edit, assign_habits, assign_supplements} (D-39). |
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
| `gym-news/` | GET, POST | GymNewsViewSet | Admin → Gym news: post a notice to the team. Each trainer with Gym news on gets it in the bell (and push). |
| `me/reminders/` | GET, POST, PUT, PATCH | ReminderPreferenceView |  |
| `me/staff-notifications/` | GET, PUT, PATCH | StaffNotificationPreferenceView |  |
| `message-templates/` | GET, POST | MessageTemplateViewSet | Emails & alerts → Client messages (admin only; a trainer with `automations.manage` can read the list for the builder, D-54). Board order, custom last. Packages group hidden (D-55). Each row has `when`, `sent_by`, `used_in` [{id, name, status, line}]. POST {name, group, channels[]} (+ `key`, `texts` for Undo after a delete). |
| `message-templates/<pk>/` | GET, PUT, PATCH, DELETE | MessageTemplateViewSet | Emails & alerts → Client messages (admin only). |
| `message-templates/<pk>/preview/` | GET | MessageTemplateViewSet | Emails & alerts → Client messages (admin only). |
| `message-templates/<pk>/reset/` | POST | MessageTemplateViewSet | Emails & alerts → Client messages (admin only). |
| `message-templates/stats/` | GET | MessageTemplateViewSet | Emails & alerts → Client messages (admin only). |
| `message-templates/variables/` | GET | MessageTemplateViewSet | Emails & alerts → Client messages (admin only). |
| `notifications/` | GET | NotificationViewSet | Bell panel / Notifications page (client `/more/notifications`, staff `/notifications`). Cursor paged, ?unread=1 for the Unread tab. Rows carry `actor_name`, `actor_initials`, `actor_color`. |
| `notifications/<pk>/` | DELETE | NotificationViewSet | Bell panel / Notifications page. ?unread=1 for the Unread tab. |
| `notifications/<pk>/read/` | POST | NotificationViewSet | Bell panel / Notifications page. ?unread=1 for the Unread tab. |
| `notifications/<pk>/unread_one/` | POST | NotificationViewSet | Bell panel / Notifications page. ?unread=1 for the Unread tab. |
| `notifications/read_all/` | POST | NotificationViewSet | Bell panel / Notifications page. ?unread=1 for the Unread tab. |
| `notifications/unread/` | GET | NotificationViewSet | `{count, total}`: bell count and the Notifications page sub line (D-59). |
| `settings/notifications/` | GET, PUT, PATCH | NotificationSettingsView | Quiet hours, daily digest (`digest` off / daily / weekly) and sender identity. |
| `team-alerts/` | GET | TeamAlertSettingViewSet | Emails & alerts → Team alerts, board order, with `label` + `description`. |
| `team-alerts/<pk>/` | PUT, PATCH | TeamAlertSettingViewSet | {channels}: missing channels become off. |
| `team-alerts/enable-all/` | POST | TeamAlertSettingViewSet | Every channel on for every team alert; returns the list. |

## nutrition

| Path | Methods | View | Notes |
|---|---|---|---|
| `clients/<client_pk>[0-9a-f-]+)/meal-plans/` | GET, POST | ClientMealPlanViewSet | Client profile → Plans → Meal plan slot: current, Up next and history; assign one plan; end it. |
| `clients/<client_pk>[0-9a-f-]+)/meal-plans/<pk>/end/` | POST | ClientMealPlanViewSet | Client profile → Plans → Meal plan slot: current, Up next and history; assign one plan; end it. |
| `clients/<client_pk>[0-9a-f-]+)/meal-plans/<pk>/meals/` | GET, PUT | ClientMealPlanViewSet | Client profile → Plans → Meal plan slot: current, Up next and history; assign one plan; end it. |
| `clients/<client_pk>[0-9a-f-]+)/meal-plans/<pk>/reset/` | POST | ClientMealPlanViewSet | Client profile → Plans → Meal plan slot: current, Up next and history; assign one plan; end it. |
| `clients/<uuid:client_pk>/food/` | GET | ClientFoodLogView | Client profile → Logs → Meals: one day (`?date=`), or one page of days (`?range=&page=`). |
| `food-picker/` | GET | FoodPickerView | Builder → Add food: team foods first, grouped. |
| `foods/` | GET, POST | FoodViewSet | Food library (staff; `group`, `diet`, `search`, paginated). Rows carry `used_in` (plan names) and `used_tip` ("Plan · Meal, Meal"). Clients search foods through /me/foods/. |
| `foods/<pk>/` | GET, PUT, PATCH, DELETE | FoodViewSet | Create / Edit food drawer (`source_note` editable). DELETE of a built-in food → 403 "Duplicate it to make your own". |
| `foods/<pk>/delete-preview/` | GET | FoodViewSet | Food library (staff). Clients search foods through /me/foods/. |
| `foods/<pk>/duplicate/` | POST | FoodViewSet | Food library (staff). Clients search foods through /me/foods/. |
| `foods/<pk>/restore/` | POST | FoodViewSet | Food library (staff). Clients search foods through /me/foods/. |
| `foods/<pk>/swap-options/` | GET | FoodViewSet | Food library (staff). Clients search foods through /me/foods/. |
| `foods/<pk>/units/` | POST | FoodViewSet | Food library (staff). Clients search foods through /me/foods/. |
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
| `me/food/meals/<int:meal_id>/<str:op>/` | POST | MyMealActionView | POST /me/food/meals/<meal_id>/<op>/  op = eat / unlog / skip / unskip / item (`item`, `action` eat·skip·reset) / portions / swap / option / photo (replace or null) / photo_add (one more, max 4). Each meal carries `eaten` totals and `photos`; each food `state` and `edited` (D-83). Each meal also has `assigned` (planned totals) and `opens_at`; before `opens_at` (time − `MEAL_OPEN_BEFORE_MINUTES`, default 30) every op but unlog / unskip / photo is refused; the day target is the assigned foods' total (D-86) |
| `me/foods/` | GET, POST | MyFoodSearchViewSet | Log food: search team foods + 'My foods'; create a custom food (saved to My foods). |
| `me/foods/recent/` | GET | MyFoodSearchViewSet | Log food: search team foods + 'My foods'; create a custom food (saved to My foods). |
| `meal-plans/` | GET, POST | MealPlanViewSet | Nutrition → Meal plans cards (`diet`, `search`, paginated): `can_edit`, `owner`, `meal_names`, `client_count` / `custom_count` (trainer: own clients only), `status`, `has_unpublished_changes`. |
| `meal-plans/<pk>/` | GET, PUT, PATCH, DELETE | MealPlanViewSet | Meal plan builder: detail with `meals` → `options` → `items` (`swaps` resolved) and `planned`. PATCH name, targets, `allow_*`. Changing needs `can_edit` (D-44). |
| `meal-plans/<pk>/assign/` | POST | MealPlanViewSet |  |
| `meal-plans/<pk>/clients/` | GET | MealPlanViewSet |  |
| `meal-plans/<pk>/clients/<client_id>[0-9a-f-]+)/remove/` | POST | MealPlanViewSet |  |
| `meal-plans/<pk>/clients/<client_id>[0-9a-f-]+)/reset/` | POST | MealPlanViewSet |  |
| `meal-plans/<pk>/clients/<client_id>[0-9a-f-]+)/version-note/` | PUT | MealPlanViewSet |  |
| `meal-plans/<pk>/delete-preview/` | GET | MealPlanViewSet | `{clients}` on the plan, for the Delete confirm. |
| `meal-plans/<pk>/duplicate/` | POST | MealPlanViewSet | Same meals, no clients. |
| `meal-plans/<pk>/publish-preview/` | GET | MealPlanViewSet |  |
| `meal-plans/<pk>/publish/` | POST | MealPlanViewSet | Publish: status published, clients and their trainers get a notice → `{sent_to}`. |
| `meal-plans/<pk>/restore/` | POST | MealPlanViewSet | Delete toast Undo: the plan and the clients it was taken from come back. |
| `meal-plans/<pk>/structure/` | PUT | MealPlanViewSet | Builder Publish step 1: `{meals: [...]}` replaces the every-day meals; an item's `swaps: [{food, quantity, unit}]` replaces its list (leave it out to keep it). |
| `meal-plans/assign-options/` | GET | MealPlanViewSet | Builder Assign to clients: every client the person can see with `plan` / `plan_name` (their current meal plan). |
| `meal-plans/counts/` | GET | MealPlanViewSet | Diet tab counts, `foods`, `can: {create, assign, foods, edit_all}`. |

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
| `sessions/stats/` | GET | SessionViewSet | Calendar (admin: all trainers; trainer: own sessions). Admin gets `busiest` {trainer__full_name, n} and `by_trainer` [{trainer_id, n}] for the Busiest trainer stat and the All trainers menu (D-48). |

## trainers

| Path | Methods | View | Notes |
|---|---|---|---|
| `access-requests/` | GET, POST | AccessRequestViewSet | Trainer → Ask for more access. Admin approves or declines. |
| `access-requests/<pk>/approve/` | POST | AccessRequestViewSet | Trainer → Ask for more access. Admin approves or declines. |
| `access-requests/<pk>/decline/` | POST | AccessRequestViewSet | Trainer → Ask for more access. Admin approves or declines. |
| `trainers/` | GET, POST | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/` | GET, PUT, PATCH, DELETE | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). GET adds `access_presets` {assigned, all} for the Access tab level cards (D-48). The list's search / filters never apply to `trainers/<pk>/…` routes, so a tab's own `?search=` / `?status=` can't hide the trainer. |
| `trainers/<pk>/access/` | GET, PUT | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/assign-clients/` | POST | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/assignable-clients/` | GET | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/deactivate-preview/` | GET | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/deactivate/` | POST | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/move-clients/` | POST | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/password-reset/` | POST | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/reactivate/` | POST | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/stats/` | GET | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<pk>/visibility/` | GET, PUT | TrainerViewSet | Admin → Trainers. PUT allowed for this and `access/` (was 405, D-54); a plain PUT on `trainers/<pk>/` stays 405. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/<trainer_pk>me|[0-9a-f-]+)/documents/` | GET, POST | TrainerDocumentViewSet | Documents tab. Admin manages any trainer's documents; a trainer uploads and sees their own |
| `trainers/<trainer_pk>me|[0-9a-f-]+)/documents/<pk>/` | GET, PUT, PATCH, DELETE | TrainerDocumentViewSet | Documents tab. Admin manages any trainer's documents; a trainer uploads and sees their own |
| `trainers/<trainer_pk>me|[0-9a-f-]+)/documents/<pk>/verify/` | POST | TrainerDocumentViewSet | Documents tab. Admin manages any trainer's documents; a trainer uploads and sees their own |
| `trainers/export/` | GET | TrainerViewSet | Admin → Trainers. Trainers can read the team list (for "Move to another trainer"). |
| `trainers/me/` | GET, PATCH | TrainerMeView | Trainer → Me: own profile, stats, read-only access, visibility. |
| `trainers/me/activity/` | GET | MyActivityView | My activity: what this trainer did in the app, newest first, plus a "Logged in" row per login. |
| `trainers/me/devices/` | GET | MyDevicesView | Account → Where you are logged in: this device first, then the rest by last use; 5 a page. |
| `trainers/me/notifications/` | GET, PUT, PATCH | MyNotificationsView | Account → Notifications ("Push to your phone and email"). |
| `trainers/me/visibility/` | GET, PUT | TrainerMeVisibilityView |  |
| `trainers/summary/` | GET | TrainerViewSet | Admin → Trainers stats: counts per tab, spots, check-ins to review (with who has the most), adherence and `adherence_change` (clients' 7-day minus 30-day average, D-48). |
| `trainers/<pk>/clients/` | GET | TrainerViewSet | Trainer profile → Clients tab: `?search= &status=active|at_risk|paused|pending &goal= &page=` (20 a page), program, adherence, last check-in, since (D-48). |
| `trainers/<pk>/activity/` | GET | TrainerViewSet | Trainer profile → Activity tab: same rows and paging as `me/activity` for that trainer (D-48). |
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
| `exercises/` | GET, POST | ExerciseViewSet | Exercise library: `search`, `ordering` (name, -name, -n_programs, -created_at), `muscle` / `equipment` / `level` / `source` (comma lists), paginated. POST needs "Add custom exercises" (D-40). |
| `exercises/<pk>/` | GET, PUT, PATCH, DELETE | ExerciseViewSet | Exercise page / Edit. Built-in: PATCH 400, DELETE 403. Row has `can_edit`, `cover_image`, `also_works[].note`. |
| `exercises/<pk>/cover/` | POST, DELETE | ExerciseViewSet | Upload image cover (multipart `file`, JPG/PNG ≤ 5 MB) or remove it. Built-in → 403. |
| `exercises/<pk>/duplicate/` | POST | ExerciseViewSet |  |
| `exercises/<pk>/restore/` | POST | ExerciseViewSet |  |
| `exercises/<pk>/used-in/` | GET | ExerciseViewSet | Used in N programs: days, `weekdays` (Add to program marks those days Added), workouts, clients (trainer: own clients only). |
| `exercises/facets/` | GET | ExerciseViewSet | Filter counts (muscle, equipment, level, source), built-in / custom totals, `can: {create}`. |
| `exercises/youtube-info/` | GET | ExerciseViewSet | `?url=` → `{id, thumb, title, author}` (oEmbed, cached 24 h); not YouTube → 400. |
| `exercises/frames/` | GET | ExerciseViewSet | `?video=<content id>` → four stills grabbed with ffmpeg (saved once), or `?url=<YouTube>` → YouTube's four stills: `{frames: [{key, at, label, url}]}`. Unknown video 404, not YouTube 400. Save the pick as `cover_frame` (D-42). |
| `me/train/` | GET | MyTrainView | Train tab: week strip, today's workout with targets, last time and PRs, the running workout. |
| `me/workouts/` | GET, POST | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/<pk>/` | GET | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/<pk>/clear-sets/` | POST | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/<pk>/discard/` | POST | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/<pk>/feedback/` | POST | MyWorkoutViewSet | The logger. Start → tick sets → finish (or discard / restart / clear). |
| `me/workouts/<pk>/form-video/` | POST | MyWorkoutViewSet | Logger set menu → Send a form video. Multipart `file`, `exercise`, `set_number`, `note`. Tells the trainer (`form_video`); shows in the client profile Logs → workout detail (`form_videos`). D-46 |
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
| `programs/` | GET, POST | ProgramViewSet | Programs page (`tab`, `search`, paginated). Cards carry `can_edit`; trainers see only their own clients. POST needs Use templates (D-39). |
| `programs/<pk>/` | GET, PUT, PATCH, DELETE | ProgramViewSet |  |
| `programs/<pk>/add-exercise/` | POST | ProgramViewSet | Add to program: `{exercise, weekday}` → added to that weekday in every week (D-40). Weeks where that day already has it are skipped; 400 when every week has it. |
| `programs/<pk>/archive/` | POST | ProgramViewSet |  |
| `programs/<pk>/assign/` | POST | ProgramViewSet |  |
| `programs/<pk>/clients/` | GET | ProgramViewSet |  |
| `programs/<pk>/copy-week/` | POST | ProgramViewSet | Kept for old clients; the builder now copies weeks locally and saves with `structure/` (D-43). |
| `programs/<pk>/delete-preview/` | GET | ProgramViewSet |  |
| `programs/<pk>/duplicate/` | POST | ProgramViewSet |  |
| `programs/<pk>/restore/` | POST | ProgramViewSet | Undo of Delete: brings back the program and its clients (within one hour). |
| `programs/<pk>/structure/` | PUT | ProgramViewSet | Program builder saves the whole tree. Only who may change it (D-39). |
| `programs/<pk>/unarchive/` | POST | ProgramViewSet |  |
| `programs/assign-options/` | GET | ProgramViewSet |  |
| `programs/counts/` | GET | ProgramViewSet | Tab counts + `can: {create, assign, edit_all}` (D-39). |
