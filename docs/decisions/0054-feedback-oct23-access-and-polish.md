# D-54 · Gautam's feedback (23 Oct): trainer access, settings trims, table and list polish

**Date:** 2026-10-23 · **Asked by:** Gautam (8 screenshots)

## What was decided
1. **Two new trainer permissions** the admin can give one trainer (Trainer profile → Access and permissions, Custom):
   - `clients.assign` "Assign and reassign clients" (Clients group): the trainer gets Change trainer on the clients
     they can see (Clients list ⋯ and Client profile). Server: `clients/<id>/trainers/` and `change-trainer/` allow
     admin, `clients.assign` or `clients.view_all`.
   - `automations.manage` "Create and edit automations" (new Automations group): the trainer gets Automations in the
     sidebar / More and the whole `automations/` API; message templates are readable for the builder, still only
     the admin edits them. Message templates button, Sender settings and "Edit message templates" stay admin only.
   - Both start Off for Assigned clients and All clients presets. `auth/me/` now returns `permissions` (the trainer's
     effective permissions) so the app can show these entries.
   - The Roles & access matrix cell "Assign / reassign clients" is no longer locked (the role switch grants it).
2. **PUT fix.** Trainer `visibility/` (What clients see) and `access/` saves used PUT, which the trainer view set
   did not allow ("Method PUT not allowed"). PUT is allowed now for these actions; a plain PUT on the trainer itself
   still answers 405 (PATCH edits it).
3. **Settings trims.** Gym profile has Social media fields: Website, Instagram, YouTube, Facebook (new `youtube`,
   `facebook` on GymSettings, also in the public `gym/`). Timezone and App language rows are hidden (commented out;
   the gym runs on IST and the app is English only). The Apple Health / Health Connect card is hidden (phone side not
   built). The Daily digest card on Emails & alerts → Team alerts is hidden (stays Off, comes back with the Daily
   summary design).
4. **Every Duplicate asks first**: one confirm modal `Duplicate "<name>"?` / Cancel / Duplicate, on forms, form
   questions, automations, exercises, programs, meal plans, meal options, foods, habits and supplement plans.
   ("Duplicate and edit" on a client's plan opens the editor, which is already the step to back out of.)
5. **Tables never cut a header.** Each column is at least as wide as its header (measured), so "NEXT CHECK-IN",
   "ACTIONS", "ADHERENCE", "WITH THEM SINCE" show in full; narrow windows scroll the table sideways as before. Trainer
   profile → Clients: Status column wider (pill no longer overflows).
6. **Cut text shows a tooltip everywhere**: every remaining one-line text with an ellipsis is a `CutText`.
7. **New message template modal:** Group tabs fit their words (not stretched), smaller footer buttons, more room
   under them.
8. **Automations list compact:** name on one line with the badge, when / who line under it, steps chips get more
   room, Running + Finished share one "Clients" column ("3 running" over "12 finished"). The chips no longer
   overflow (2.9 px). Builder trigger grid works out its columns from the room it really gets (third column was cut).
9. **Lists in cards scroll after 5 rows** (`ScrollAfter`): Assigned to (habits, supplement plans), Clients on this
   plan (meal plan builder, replaces "+N more"), Used in (exercise), content drawer lists. Five rows and a bit of the
   sixth show, the rest scroll inside the card.
10. **App name on the phone** is "Train With Vimal" (Android label and iOS display name were "twv" / "Twv").
   App icon and splash screen still use the Flutter defaults (next, from `app/assets/logo.svg`).

## Not built yet
- Reading health data on client phones; the Health card comes back when it is built.
- Timezone / language choices (only IST + English today).
