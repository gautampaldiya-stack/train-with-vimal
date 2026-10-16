# Data model

Generated from the Django models. Every field of every app model, with its type, link and choices. Read with `README.md` for the patterns.

## accounts

### User
One login for everyone. Email and mobile are each unique across ALL roles

| Field | Type | Notes |
|---|---|---|
| `password` | CharField |  |
| `last_login` | DateTimeField | optional |
| `is_superuser` | BooleanField | Designates that this user has all permissions without explicitly assigning them. |
| `id` | UUIDField |  |
| `email` | CharField | optional |
| `phone` | CharField | optional |
| `full_name` | CharField |  |
| `role` | CharField | choices: admin, trainer, client; indexed |
| `status` | CharField | choices: pending, active, paused, rejected, deactivated; indexed |
| `gender` | CharField | choices: female, male, other |
| `date_of_birth` | DateField | optional |
| `city` | CharField |  |
| `avatar` | FileField | optional |
| `email_verified_at` | DateTimeField | optional |
| `pending_email` | CharField |  |
| `password_changed_at` | DateTimeField | optional |
| `last_seen_at` | DateTimeField | optional |
| `deletion_requested_at` | DateTimeField | optional |
| `unit_weight` | CharField | choices: kg, lb |
| `unit_length` | CharField | choices: cm, in |
| `unit_water` | CharField | choices: l, oz |
| `timezone` | CharField |  |
| `is_active` | BooleanField |  |
| `is_django_staff` | BooleanField |  |
| `date_joined` | DateTimeField | indexed |
| `groups` | ManyToManyField | → Group; The groups this user belongs to. A user will get all permissions granted to each of their groups. |
| `user_permissions` | ManyToManyField | → Permission; Specific permissions for this user. |

Constraints: uniq_user_email_ci, uniq_user_phone, only_one_admin, user_has_email_or_phone

### UserSession
One row per logged-in device ("Where you are logged in").

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `user` | ForeignKey | → User; indexed |
| `device_name` | CharField |  |
| `platform` | CharField |  |
| `ip_address` | GenericIPAddressField | optional |
| `city` | CharField |  |
| `user_agent` | CharField |  |
| `last_active_at` | DateTimeField |  |
| `revoked_at` | DateTimeField | optional; indexed |

### OneTimeToken
Email verification, password reset and coach-made login links.

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `user` | ForeignKey | → User; indexed |
| `purpose` | CharField | choices: email_verify, password_reset, login_link |
| `token_hash` | CharField | unique |
| `email` | CharField |  |
| `expires_at` | DateTimeField |  |
| `used_at` | DateTimeField | optional |

## activity

### ActivityEvent
One timeline for the whole product: Activity log, trainer profile Activity tab,

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `actor` | ForeignKey | → User; optional; indexed |
| `actor_type` | CharField | choices: team, client, automation, system |
| `actor_label` | CharField |  |
| `source` | CharField |  |
| `kind` | CharField | choices: checkin, plan, workout, meal, body, client, content, session, team, system; indexed |
| `verb` | CharField |  |
| `target_type` | CharField |  |
| `target_id` | CharField |  |
| `target_label` | CharField |  |
| `change_from` | CharField |  |
| `change_to` | CharField |  |
| `client` | ForeignKey | → User; optional; indexed |
| `trainer` | ForeignKey | → User; optional; indexed |
| `meta` | JSONField |  |

### DismissedItem
Dashboard 'Needs action' rows a person closed with ×. Key is stable per row (e.g. 'approvals:5').

| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `user` | ForeignKey | → User; indexed |
| `key` | CharField |  |
| `created_at` | DateTimeField |  |

Constraints: uniq_dismissed_item

## automations

### Automation


| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `deleted_at` | DateTimeField | optional; indexed |
| `name` | CharField |  |
| `status` | CharField | choices: on, off, draft; indexed |
| `trigger` | CharField | choices: client_approved, plan_starts, plan_ends, package_ending, birthday, every_week, every_day, on_date, missed_checkin, misse; indexed |
| `trigger_config` | JSONField |  |
| `scope_package` | CharField |  |
| `scope_trainer` | ForeignKey | → User; optional; indexed |
| `stop_on_response` | BooleanField |  |
| `starter` | CharField |  |
| `created_by` | ForeignKey | → User; optional; indexed |

### Step


| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `automation` | ForeignKey | → Automation; indexed |
| `order` | PositiveSmallIntegerField |  |
| `kind` | CharField | choices: wait, message, form, task |
| `config` | JSONField |  |

### AutomationRun
One client going through one automation.

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `automation` | ForeignKey | → Automation; indexed |
| `client` | ForeignKey | → User; indexed |
| `status` | CharField | choices: running, waiting, finished, stopped, failed; indexed |
| `step_index` | PositiveSmallIntegerField |  |
| `next_run_at` | DateTimeField | optional; indexed |
| `dedupe_key` | CharField |  |
| `finished_at` | DateTimeField | optional |
| `last_message` | CharField |  |
| `log` | JSONField |  |

Constraints: uniq_run_once

### TrainerTask
Tasks card on the trainer dashboard (from automations or added by hand).

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `assignee` | ForeignKey | → User; indexed |
| `client` | ForeignKey | → User; optional; indexed |
| `title` | CharField |  |
| `detail` | CharField |  |
| `automation_run` | ForeignKey | → AutomationRun; optional; indexed |
| `due_on` | DateField | optional |
| `done_at` | DateTimeField | optional; indexed |
| `created_by` | ForeignKey | → User; optional; indexed |

## checkins

### Form


| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `deleted_at` | DateTimeField | optional; indexed |
| `name` | CharField |  |
| `type` | CharField | choices: onboarding, weekly, daily, survey, waiver; indexed |
| `status` | CharField | choices: draft, published, archived; indexed |
| `is_parq` | BooleanField |  |
| `created_by` | ForeignKey | → User; optional; indexed |

### Question


| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `form` | ForeignKey | → Form; indexed |
| `order` | PositiveSmallIntegerField |  |
| `text` | CharField |  |
| `type` | CharField | choices: short, long, number, single, multiple, dropdown, scale, yes_no, photo |
| `options` | ArrayField |  |
| `scale_labels` | ArrayField |  |
| `allow_other` | BooleanField |  |
| `help_text` | CharField |  |
| `required` | BooleanField |  |
| `metric` | CharField |  |
| `is_removed` | BooleanField |  |

### FormRequest
A form sent to a client (by hand, or by an automation). Client profile → Forms tab.

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `form` | ForeignKey | → Form; indexed |
| `client` | ForeignKey | → User; indexed |
| `sent_by` | ForeignKey | → User; optional; indexed |
| `automation_run` | ForeignKey | → AutomationRun; optional; indexed |
| `due_at` | DateTimeField | optional |
| `filled_at` | DateTimeField | optional |

### Submission
A filled form. Weekly and daily check-ins are submissions too.

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `form` | ForeignKey | → Form; indexed |
| `form_type` | CharField | choices: onboarding, weekly, daily, survey, waiver; indexed |
| `client` | ForeignKey | → User; indexed |
| `request` | ForeignKey | → FormRequest; optional; indexed |
| `date` | DateField |  |
| `week_number` | PositiveSmallIntegerField | optional |
| `metrics` | JSONField |  |
| `reviewed_at` | DateTimeField | optional; indexed |
| `reviewed_by` | ForeignKey | → User; optional; indexed |
| `reply` | TextField |  |
| `edited_at` | DateTimeField | optional |

### Answer


| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `submission` | ForeignKey | → Submission; indexed |
| `question` | ForeignKey | → Question; indexed |
| `value` | JSONField | optional |
| `photo` | FileField | optional |

### WeightLog


| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `client` | ForeignKey | → User; indexed |
| `date` | DateField |  |
| `weight_kg` | DecimalField |  |
| `source` | CharField |  |
| `created_at` | DateTimeField |  |

Constraints: uniq_weight_day

### Measurement


| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `client` | ForeignKey | → User; indexed |
| `date` | DateField |  |
| `waist_cm` | DecimalField | optional |
| `hips_cm` | DecimalField | optional |
| `chest_cm` | DecimalField | optional |
| `arm_cm` | DecimalField | optional |
| `body_fat_pct` | DecimalField | optional |
| `created_at` | DateTimeField |  |

Constraints: uniq_measure_day

### PhotoSet


| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `client` | ForeignKey | → User; indexed |
| `label` | CharField |  |
| `date` | DateField |  |
| `weight_kg` | DecimalField | optional |
| `submission` | ForeignKey | → Submission; optional; indexed |

### ProgressPhoto


| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `photo_set` | ForeignKey | → PhotoSet; indexed |
| `pose` | CharField | choices: front, side, back |
| `image` | FileField |  |
| `created_at` | DateTimeField |  |

Constraints: uniq_pose_per_set

## clients

### ClientProfile


| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `user` | OneToOneField | → User; indexed; unique |
| `trainer` | ForeignKey | → User; optional; indexed |
| `goal` | CharField | choices: fat_loss, muscle_gain, strength, recomp, general, event |
| `height_cm` | DecimalField | optional |
| `start_weight_kg` | DecimalField | optional |
| `current_weight_kg` | DecimalField | optional |
| `target_weight_kg` | DecimalField | optional |
| `health_notes` | TextField |  |
| `start_date` | DateField | optional |
| `package_name` | CharField |  |
| `package_ends_on` | DateField | optional |
| `onboarding` | JSONField |  |
| `onboarding_done` | JSONField |  |
| `onboarding_skipped_at` | DateTimeField | optional |
| `ask_parq` | BooleanField |  |
| `signup_source` | CharField | choices: web, android, ios, added |
| `invite_link` | ForeignKey | → InviteLink; optional; indexed |
| `invited_by` | ForeignKey | → User; optional; indexed |
| `paused_at` | DateTimeField | optional |
| `removed_at` | DateTimeField | optional; indexed |
| `adherence_7d` | PositiveSmallIntegerField | optional |
| `adherence_30d` | PositiveSmallIntegerField | optional |
| `at_risk` | BooleanField | indexed |
| `at_risk_reason` | CharField |  |
| `last_reminded_at` | DateTimeField | optional |
| `stats_updated_at` | DateTimeField | optional |

### InviteLink
trainwithvimal.app/join/<code> — sign-up links shared by the team.

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `deleted_at` | DateTimeField | optional; indexed |
| `code` | CharField | unique |
| `trainer` | ForeignKey | → User; indexed |
| `label` | CharField |  |
| `expires_at` | DateTimeField | optional |
| `max_uses` | PositiveIntegerField | optional |
| `needs_approval` | BooleanField |  |
| `is_on` | BooleanField |  |
| `created_by` | ForeignKey | → User; optional; indexed |

### Approval
A sign-up waiting in Approvals, and its decision (History tab).

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `client` | ForeignKey | → User; indexed |
| `status` | CharField | choices: waiting, approved, rejected; indexed |
| `invited_by` | ForeignKey | → User; optional; indexed |
| `signed_up_from` | CharField | choices: web, android, ios, added |
| `decided_by` | ForeignKey | → User; optional; indexed |
| `decided_at` | DateTimeField | optional; indexed |
| `assigned_trainer` | ForeignKey | → User; optional; indexed |
| `reject_reason` | CharField | choices: not_fit, has_account, fake, no_trainer, other |
| `message` | TextField |  |
| `moved_back` | BooleanField |  |

### InfoRequest
Approvals → "Ask for info".

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `approval` | ForeignKey | → Approval; indexed |
| `items` | JSONField |  |
| `channels` | JSONField |  |
| `sent_by` | ForeignKey | → User; optional; indexed |

### ClientNote
Trainer's private notes on a client. Clients never see these.

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `deleted_at` | DateTimeField | optional; indexed |
| `client` | ForeignKey | → User; indexed |
| `author` | ForeignKey | → User; optional; indexed |
| `body` | TextField |  |
| `is_flag` | BooleanField |  |

## common

### IdempotencyRecord
First response to a write sent with an `Idempotency-Key` header.

| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `key` | CharField |  |
| `user_id` | UUIDField |  |
| `method` | CharField |  |
| `path` | CharField |  |
| `status_code` | PositiveSmallIntegerField |  |
| `body` | BinaryField |  |
| `content_type` | CharField |  |
| `created_at` | DateTimeField | indexed |

Constraints: uniq_idempotency_key

## content

### Category


| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `name` | CharField | unique |
| `order` | PositiveSmallIntegerField |  |

### ContentItem


| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `deleted_at` | DateTimeField | optional; indexed |
| `kind` | CharField | choices: video, article, pdf, image; indexed |
| `title` | CharField |  |
| `category` | ForeignKey | → Category; optional; indexed |
| `description` | CharField |  |
| `file` | FileField | optional |
| `youtube_url` | CharField |  |
| `cover` | FileField | optional |
| `body` | TextField |  |
| `read_minutes` | PositiveSmallIntegerField | optional |
| `duration_seconds` | PositiveIntegerField | optional |
| `pages` | PositiveSmallIntegerField | optional |
| `file_size` | PositiveBigIntegerField | optional |
| `resolution` | CharField |  |
| `share_everyone` | BooleanField |  |
| `created_by` | ForeignKey | → User; optional; indexed |

### ContentShare


| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `item` | ForeignKey | → ContentItem; indexed |
| `client` | ForeignKey | → User; indexed |
| `shared_by` | ForeignKey | → User; optional; indexed |
| `created_at` | DateTimeField |  |

Constraints: uniq_content_share

### ContentView
Opened / finished stats, and the client's "New" / "Done" / "Saved" pills.

| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `item` | ForeignKey | → ContentItem; indexed |
| `user` | ForeignKey | → User; indexed |
| `opened_at` | DateTimeField |  |
| `finished` | BooleanField |  |
| `saved` | BooleanField |  |
| `progress` | PositiveSmallIntegerField |  |

Constraints: uniq_content_view

## gym

### GymSettings
Singleton: Settings → Gym profile, Regional & defaults, Branding.

| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `name` | CharField |  |
| `email` | CharField |  |
| `phone` | CharField |  |
| `address` | CharField |  |
| `instagram` | CharField |  |
| `timezone` | CharField |  |
| `language` | CharField |  |
| `logo` | FileField | optional |
| `accent_color` | CharField |  |
| `theme` | CharField | choices: light, dark, system |
| `branding_applied_at` | DateTimeField | optional |
| `branding_draft` | JSONField |  |
| `updated_at` | DateTimeField |  |

### RoleMatrix
Singleton holding the trainer and client columns of the permission matrix.

| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `matrix` | JSONField |  |
| `updated_at` | DateTimeField |  |

### Integration


| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `kind` | CharField | choices: whatsapp, email_domain, health; unique |
| `status` | CharField | choices: not_connected, pending, connected |
| `config` | JSONField |  |
| `connected_at` | DateTimeField | optional |
| `updated_at` | DateTimeField |  |

## habits

### Habit


| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `deleted_at` | DateTimeField | optional; indexed |
| `name` | CharField |  |
| `kind` | CharField | choices: tick, counter |
| `target` | PositiveIntegerField | optional |
| `unit` | CharField |  |
| `frequency` | CharField | choices: daily, days, times_week |
| `days` | ArrayField |  |
| `times_per_week` | PositiveSmallIntegerField | optional |
| `icon` | CharField |  |
| `why` | CharField |  |
| `created_by` | ForeignKey | → User; optional; indexed |

### HabitAssignment


| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `habit` | ForeignKey | → Habit; indexed |
| `client` | ForeignKey | → User; indexed |
| `start_date` | DateField |  |
| `active` | BooleanField | indexed |
| `assigned_by` | ForeignKey | → User; optional; indexed |

Constraints: uniq_habit_client

### HabitLog


| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `habit` | ForeignKey | → Habit; indexed |
| `client` | ForeignKey | → User; indexed |
| `date` | DateField |  |
| `value` | PositiveIntegerField |  |
| `done` | BooleanField |  |
| `updated_at` | DateTimeField |  |

Constraints: uniq_habit_log

### SupplementPlan


| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `deleted_at` | DateTimeField | optional; indexed |
| `name` | CharField |  |
| `note` | CharField |  |
| `created_by` | ForeignKey | → User; optional; indexed |

### SupplementItem


| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `plan` | ForeignKey | → SupplementPlan; indexed |
| `name` | CharField |  |
| `dose` | CharField |  |
| `how` | CharField |  |
| `timing` | CharField | choices: breakfast, morning, post_workout, any, night, before_bed |
| `days` | ArrayField |  |
| `with_food` | BooleanField |  |
| `order` | PositiveSmallIntegerField |  |

### SupplementAssignment


| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `plan` | ForeignKey | → SupplementPlan; indexed |
| `client` | ForeignKey | → User; indexed |
| `start_date` | DateField |  |
| `active` | BooleanField | indexed |
| `assigned_by` | ForeignKey | → User; optional; indexed |

Constraints: uniq_supp_client

### SupplementLog


| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `item` | ForeignKey | → SupplementItem; indexed |
| `client` | ForeignKey | → User; indexed |
| `date` | DateField |  |
| `taken_at` | DateTimeField |  |

Constraints: uniq_supp_log

### SupplementStock
"11 scoops left at home" — the client's own count.

| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `item` | ForeignKey | → SupplementItem; indexed |
| `client` | ForeignKey | → User; indexed |
| `quantity` | PositiveIntegerField |  |
| `unit` | CharField |  |

Constraints: uniq_supp_stock

## notifications

### DeviceToken
FCM registration token of one phone or browser (web push goes through FCM too).

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `user` | ForeignKey | → User; indexed |
| `token` | CharField | unique |
| `platform` | CharField | choices: android, ios, web |
| `session` | ForeignKey | → UserSession; optional; indexed |
| `last_used_at` | DateTimeField |  |

### Notification
In-app notification (bell panel, client Notifications tab). Also the anchor for

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `recipient` | ForeignKey | → User; indexed |
| `actor` | ForeignKey | → User; optional; indexed |
| `event` | CharField | indexed |
| `title` | CharField |  |
| `body` | TextField |  |
| `data` | JSONField |  |
| `read_at` | DateTimeField | optional |
| `in_app` | BooleanField |  |

### Delivery
One send on one channel. Feeds "96% delivered · 61% opened" and lets failures retry.

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `notification` | ForeignKey | → Notification; optional; indexed |
| `user` | ForeignKey | → User; indexed |
| `channel` | CharField | choices: email, push, whatsapp, in_app |
| `status` | CharField | choices: queued, sent, delivered, opened, failed, skipped; indexed |
| `template_key` | CharField |  |
| `automation_run` | ForeignKey | → AutomationRun; optional; indexed |
| `subject` | CharField |  |
| `body` | TextField |  |
| `provider_id` | CharField |  |
| `error` | TextField |  |
| `attempts` | PositiveSmallIntegerField |  |
| `scheduled_for` | DateTimeField | optional |
| `sent_at` | DateTimeField | optional |

### MessageTemplate
Emails & alerts → Client messages. One row per message, text per channel:

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `key` | SlugField | indexed; unique |
| `name` | CharField |  |
| `group` | CharField | choices: access, coaching, packages |
| `is_custom` | BooleanField |  |
| `channels` | JSONField |  |
| `default_channels` | JSONField |  |

### TeamAlertSetting
Emails & alerts → Team alerts. channels = {"email": true, "push": true, ...}.

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `event` | CharField | choices: new_client, checkin_submitted, plan_updated, missed_workout; unique |
| `channels` | JSONField |  |

### NotificationSettings
Singleton: quiet hours + sender identity (Emails & alerts → Sender).

| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `quiet_hours_on` | BooleanField |  |
| `quiet_start` | TimeField |  |
| `quiet_end` | TimeField |  |
| `sender_name` | CharField |  |
| `reply_to_email` | CharField |  |
| `whatsapp_number` | CharField |  |
| `updated_at` | DateTimeField |  |

### ReminderPreference
Client More → Reminders (saved as they change).

| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `user` | OneToOneField | → User; indexed; unique |
| `workout` | BooleanField |  |
| `meal` | BooleanField |  |
| `checkin` | BooleanField |  |
| `habit` | BooleanField |  |
| `trainer_reply` | BooleanField |  |
| `workout_time` | TimeField |  |
| `updated_at` | DateTimeField |  |

### StaffNotificationPreference
Trainer Me → Account → Notifications.

| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `user` | OneToOneField | → User; indexed; unique |
| `new_checkin` | BooleanField |  |
| `missed_workouts` | BooleanField |  |
| `new_client` | BooleanField |  |
| `session_changes` | BooleanField |  |
| `tasks` | BooleanField |  |
| `push` | BooleanField |  |
| `email` | BooleanField |  |

### ReminderLog
De-duplicates scheduled reminders: one row per (user, kind, ref, day).

| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `user` | ForeignKey | → User; indexed |
| `kind` | CharField |  |
| `ref` | CharField |  |
| `day` | DateField |  |
| `created_at` | DateTimeField |  |

Constraints: uniq_reminder_once

## nutrition

### Food
Every number is stored per 100 g (ml counts as g), whatever the person typed in.

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `deleted_at` | DateTimeField | optional; indexed |
| `name` | CharField | indexed |
| `brand` | CharField |  |
| `diet` | CharField | choices: veg, egg, nonveg, vegan; indexed |
| `group` | CharField | indexed |
| `source` | CharField | choices: builtin, team, imported, client; indexed |
| `source_note` | CharField |  |
| `owner_client` | ForeignKey | → User; optional; indexed |
| `kcal` | DecimalField |  |
| `protein` | DecimalField |  |
| `carbs` | DecimalField |  |
| `fat` | DecimalField |  |
| `fibre` | DecimalField |  |
| `sodium_mg` | DecimalField | optional |
| `iron_mg` | DecimalField | optional |
| `calcium_mg` | DecimalField | optional |
| `potassium_mg` | DecimalField | optional |
| `default_unit` | ForeignKey | → FoodUnit; optional; indexed |
| `default_quantity` | DecimalField |  |
| `created_by` | ForeignKey | → User; optional; indexed |
| `swaps` | ManyToManyField | → Food |

### FoodUnit
Serving units of one food. 1 g is always implied and never stored.

| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `food` | ForeignKey | → Food; indexed |
| `name` | CharField |  |
| `grams` | DecimalField |  |

Constraints: uniq_food_unit_name

### MealPlan


| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `deleted_at` | DateTimeField | optional; indexed |
| `name` | CharField |  |
| `diet` | CharField | choices: veg, egg, nonveg, vegan |
| `kcal_target` | PositiveIntegerField |  |
| `protein_g` | PositiveSmallIntegerField |  |
| `carbs_g` | PositiveSmallIntegerField |  |
| `fat_g` | PositiveSmallIntegerField |  |
| `fibre_g` | PositiveSmallIntegerField |  |
| `water_ml` | PositiveIntegerField |  |
| `status` | CharField | choices: draft, published |
| `published_at` | DateTimeField | optional |
| `has_unpublished_changes` | BooleanField |  |
| `allow_swaps` | BooleanField |  |
| `allow_search_any` | BooleanField |  |
| `allow_switch_options` | BooleanField |  |
| `allow_off_plan` | BooleanField |  |
| `created_by` | ForeignKey | → User; optional; indexed |

### Meal


| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `plan` | ForeignKey | → MealPlan; indexed |
| `name` | CharField |  |
| `time` | TimeField |  |
| `kcal_target` | PositiveIntegerField |  |
| `order` | PositiveSmallIntegerField |  |

### MealOption


| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `meal` | ForeignKey | → Meal; indexed |
| `name` | CharField |  |
| `is_default` | BooleanField |  |
| `order` | PositiveSmallIntegerField |  |

### MealItem


| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `option` | ForeignKey | → MealOption; indexed |
| `food` | ForeignKey | → Food; indexed |
| `quantity` | DecimalField |  |
| `unit` | ForeignKey | → FoodUnit; optional; indexed |
| `order` | PositiveSmallIntegerField |  |

### MealPlanAssignment


| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `client` | ForeignKey | → User; indexed |
| `plan` | ForeignKey | → MealPlan; indexed |
| `version_note` | TextField |  |
| `start_date` | DateField |  |
| `end_date` | DateField | optional |
| `status` | CharField | choices: up_next, active, ended; indexed |
| `assigned_by` | ForeignKey | → User; optional; indexed |

### MealDayState
A client's day for one planned meal: logged / skipped, today's portions and swaps.

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `client` | ForeignKey | → User; indexed |
| `date` | DateField | indexed |
| `meal` | ForeignKey | → Meal; indexed |
| `option` | ForeignKey | → MealOption; optional; indexed |
| `status` | CharField | choices: logged, skipped |
| `portions` | JSONField |  |
| `swaps` | JSONField |  |
| `logged_at` | DateTimeField | optional |
| `photo` | FileField | optional |

Constraints: uniq_meal_day

### FoodLogEntry
Everything eaten, one row per food. Big table: always read by (client, date).

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `client` | ForeignKey | → User; indexed |
| `date` | DateField |  |
| `logged_at` | DateTimeField |  |
| `meal_name` | CharField |  |
| `meal` | ForeignKey | → Meal; optional; indexed |
| `food` | ForeignKey | → Food; optional; indexed |
| `name` | CharField |  |
| `quantity` | DecimalField |  |
| `unit_name` | CharField |  |
| `grams` | DecimalField | optional |
| `kcal` | PositiveIntegerField |  |
| `protein` | DecimalField |  |
| `carbs` | DecimalField |  |
| `fat` | DecimalField |  |
| `source` | CharField | choices: plan, off_plan, quick_add |
| `swapped_from` | CharField |  |
| `reason` | CharField |  |
| `other_time` | BooleanField |  |

### WaterLog


| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `client` | ForeignKey | → User; indexed |
| `date` | DateField |  |
| `ml` | PositiveIntegerField |  |
| `updated_at` | DateTimeField |  |

Constraints: uniq_water_day

### FoodImportJob


| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `file` | FileField |  |
| `status` | CharField | choices: checked, imported, failed |
| `rows` | JSONField |  |
| `summary` | JSONField |  |
| `created_by` | ForeignKey | → User; optional; indexed |

## scheduling

### Availability
Working hours per trainer per weekday (Availability / My working hours drawer).

| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `trainer` | ForeignKey | → User; indexed |
| `weekday` | PositiveSmallIntegerField |  |
| `is_working` | BooleanField |  |
| `start` | TimeField |  |
| `end` | TimeField |  |

Constraints: uniq_trainer_weekday

### Session


| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `kind` | CharField | choices: one_on_one, quick_call, program_review |
| `client` | ForeignKey | → User; indexed |
| `trainer` | ForeignKey | → User; indexed |
| `title` | CharField |  |
| `start` | DateTimeField | indexed |
| `end` | DateTimeField |  |
| `is_call` | BooleanField |  |
| `place` | CharField |  |
| `call_link` | CharField |  |
| `note` | CharField |  |
| `status` | CharField | choices: booked, done, missed, cancelled; indexed |
| `booked_by` | ForeignKey | → User; optional; indexed |
| `reminder_sent_at` | DateTimeField | optional |

Constraints: session_end_after_start

## trainers

### TrainerProfile
A trainer (Vimal, the owner, also has one so he can coach his own clients).

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `user` | OneToOneField | → User; indexed; unique |
| `speciality` | ArrayField |  |
| `max_clients` | PositiveSmallIntegerField |  |
| `bio` | TextField |  |
| `experience_since` | PositiveSmallIntegerField | optional |
| `mode` | CharField | choices: gym, online, gym_online |
| `languages` | ArrayField |  |
| `works_best_with` | CharField |  |
| `instagram` | CharField |  |
| `youtube` | CharField |  |
| `page_link` | CharField |  |
| `website` | CharField |  |
| `joining_date` | DateField |  |
| `access_mode` | CharField | choices: assigned, all, custom |
| `permissions` | JSONField |  |
| `visibility` | JSONField |  |
| `is_owner` | BooleanField |  |

### TrainerDocument


| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `trainer` | ForeignKey | → TrainerProfile; indexed |
| `kind` | CharField | choices: certificate, id_proof, contract |
| `name` | CharField |  |
| `issuer` | CharField |  |
| `issued_on` | DateField | optional |
| `expires_on` | DateField | optional |
| `visibility` | CharField | choices: admins, admins_clients |
| `remind_before_expiry` | BooleanField |  |
| `file` | FileField |  |
| `verified_at` | DateTimeField | optional |
| `verified_by` | ForeignKey | → User; optional; indexed |
| `signed` | BooleanField |  |

### AccessRequest
Trainer Me → "Ask for more access".

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `trainer` | ForeignKey | → TrainerProfile; indexed |
| `permissions` | ArrayField |  |
| `reason` | TextField |  |
| `status` | CharField | choices: open, approved, declined; indexed |
| `decided_by` | ForeignKey | → User; optional; indexed |
| `decided_at` | DateTimeField | optional |

## training

### Exercise


| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `deleted_at` | DateTimeField | optional; indexed |
| `name` | CharField | indexed |
| `muscle_group` | CharField | choices: chest, back, legs, shoulders, arms, core, cardio; indexed |
| `primary_muscle` | CharField |  |
| `also_works` | JSONField |  |
| `equipment` | CharField | choices: barbell, dumbbell, cable, machine, bodyweight, kettlebell, band, other; indexed |
| `level` | CharField | choices: beginner, intermediate, advanced; indexed |
| `is_builtin` | BooleanField | indexed |
| `video` | ForeignKey | → ContentItem; optional; indexed |
| `youtube_url` | CharField |  |
| `cover_at_seconds` | PositiveIntegerField |  |
| `how_to` | ArrayField |  |
| `form_cues` | ArrayField |  |
| `log_type` | CharField | choices: weight_reps, bodyweight_reps, time, distance |
| `default_sets` | PositiveSmallIntegerField |  |
| `default_reps` | CharField |  |
| `default_rest_seconds` | PositiveSmallIntegerField |  |
| `default_rpe` | PositiveSmallIntegerField | optional |
| `default_tempo` | CharField |  |
| `duplicated_from` | ForeignKey | → Exercise; optional; indexed |
| `created_by` | ForeignKey | → User; optional; indexed |

### Program
Master plan (is_master) or one client's custom copy (master points at the original).

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `deleted_at` | DateTimeField | optional; indexed |
| `name` | CharField |  |
| `goal_line` | CharField |  |
| `weeks` | PositiveSmallIntegerField |  |
| `days_per_week` | PositiveSmallIntegerField |  |
| `archived_at` | DateTimeField | optional; indexed |
| `is_master` | BooleanField | indexed |
| `master` | ForeignKey | → Program; optional; indexed |
| `created_by` | ForeignKey | → User; optional; indexed |

### ProgramWeek


| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `program` | ForeignKey | → Program; indexed |
| `number` | PositiveSmallIntegerField |  |

Constraints: uniq_program_week

### ProgramDay


| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `week` | ForeignKey | → ProgramWeek; indexed |
| `weekday` | PositiveSmallIntegerField |  |
| `name` | CharField |  |
| `is_rest` | BooleanField |  |
| `rest_note` | CharField |  |

Constraints: uniq_week_weekday

### ProgramExercise


| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `day` | ForeignKey | → ProgramDay; indexed |
| `exercise` | ForeignKey | → Exercise; indexed |
| `order` | PositiveSmallIntegerField |  |
| `superset_group` | CharField |  |
| `sets` | PositiveSmallIntegerField |  |
| `reps` | CharField |  |
| `rpe` | PositiveSmallIntegerField | optional |
| `rest_seconds` | PositiveSmallIntegerField |  |
| `tempo` | CharField |  |
| `target_weight_kg` | DecimalField | optional |
| `note` | CharField |  |
| `override` | JSONField |  |

### ProgramAssignment


| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `client` | ForeignKey | → User; indexed |
| `program` | ForeignKey | → Program; indexed |
| `custom_program` | ForeignKey | → Program; optional; indexed |
| `start_date` | DateField |  |
| `end_date` | DateField | optional |
| `status` | CharField | choices: up_next, active, ended; indexed |
| `assigned_by` | ForeignKey | → User; optional; indexed |

### WorkoutLog
One workout the client did (or is doing) — the logger screen.

| Field | Type | Notes |
|---|---|---|
| `id` | UUIDField |  |
| `created_at` | DateTimeField | indexed |
| `updated_at` | DateTimeField |  |
| `client` | ForeignKey | → User; indexed |
| `assignment` | ForeignKey | → ProgramAssignment; optional; indexed |
| `program_day` | ForeignKey | → ProgramDay; optional; indexed |
| `name` | CharField |  |
| `date` | DateField | indexed |
| `status` | CharField | choices: in_progress, completed, discarded; indexed |
| `started_at` | DateTimeField |  |
| `finished_at` | DateTimeField | optional |
| `duration_seconds` | PositiveIntegerField |  |
| `time_breakdown` | JSONField |  |
| `effort` | PositiveSmallIntegerField | optional |
| `note` | TextField |  |
| `sets_done` | PositiveSmallIntegerField |  |
| `sets_planned` | PositiveSmallIntegerField |  |
| `auto_saved` | BooleanField |  |
| `paused_at` | DateTimeField | optional |
| `reopened_at` | DateTimeField | optional |

### SetLog


| Field | Type | Notes |
|---|---|---|
| `id` | BigAutoField |  |
| `workout` | ForeignKey | → WorkoutLog; indexed |
| `program_exercise` | ForeignKey | → ProgramExercise; optional; indexed |
| `exercise` | ForeignKey | → Exercise; indexed |
| `set_number` | PositiveSmallIntegerField |  |
| `weight_kg` | DecimalField | optional |
| `reps` | PositiveSmallIntegerField | optional |
| `seconds` | PositiveIntegerField | optional |
| `distance_km` | DecimalField | optional |
| `client_key` | CharField |  |
| `is_bodyweight` | BooleanField |  |
| `is_warmup` | BooleanField |  |
| `done` | BooleanField |  |
| `done_at` | DateTimeField | optional |
| `is_pr` | BooleanField |  |
