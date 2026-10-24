# D-57 · Admin is always a trainer too (invite links work with no trainers)

**Date:** 2026-10-24 · **Asked by:** Probid ("admin bhi trainer profile ho sakti hai na... jesa demo data me tha",
"invite link create hi nahi ho raha jab admin ek hai and trainer koi nahi")

## Problem
The Invite links modal fills "Clients go to" from `GET trainers/`, which lists only users with a `TrainerProfile`.
`seed_demo` gives Vimal a profile, but the live site's admin comes from `createsuperuser` (deploy/README), which made
no profile. With no trainers yet the list was empty, so no code was suggested and **Create link** stayed off.

## What was decided
1. Every admin has a `TrainerProfile` (`is_owner=True`, access all): a `post_save` signal on `User`
   (`apps/trainers/signals.py` → `services.ensure_admin_trainer_profile`) and migration `trainers/0003` for admins
   that already exist (the live one gets it on the next deploy).
2. The admin shows in the trainer list, so in the invite modal the admin picks himself or any active trainer.
   Not picking a trainer (API without `trainer_id`) makes the link in the admin's name.
3. `seed_demo` fills Vimal's demo details with `update_or_create` (no clash with the signal).

## Checked
Backend tests (`tests/test_invite_links.py`), `flutter analyze` clean, and in the browser (debug, 1280): fresh DB with
only `createsuperuser` → Approvals → Invite link → "Clients go to: Vimal Singh", code VIMAL-xxxx → Create link works.
No app code changed.
