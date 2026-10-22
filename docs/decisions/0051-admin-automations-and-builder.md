# D-51 · Admin Automations and the Automation builder

**Date:** 2026-10-22 · **Boards:** Automations, AutomationsMobile, AutomationNew, AutomationNewMobile, AutomationBuilder, AutomationBuilderMobile

## What was decided

1. **One builder page for new and edit.** `/automations/new` is the `AutomationNew` board (blank),
   `/automations/new?starter=<key>` fills it from a ready-made automation (the `AutomationBuilder` board look),
   `/automations/<id>` edits one. The board says "Nothing is saved until you turn it on or save it", so the
   builder keeps everything on the page and writes only on **Save as draft** or **Turn on** (**Save and keep
   on** when it is already on). That is why the starters modal does not call `from-starter/` any more: a
   starter is only saved when the admin saves it. Cancel with changes asks "Leave without saving?".
2. **Not ready to turn on.** In plain words lists what is missing, checked on the page the same way the server
   checks it (`engine.problems`): pick what starts it, the form for "Form sent in", at least one step, no wait
   as the last step, a template / form and at least one channel on each send step, a task text. Turn on with a
   problem shows the first one as a toast and saves nothing; the server still refuses (`not_ready`) if
   something slipped through.
3. **Trigger settings follow the board** (`TD` / `NUM`): Plan starts → Which plan; Plan ends and Package ending
   → days before + **time**; Birthday, Every day → time; Every week → day + time; On a date → date + time;
   Missed check-in (hours, 6–72 in steps of 6), Missed workouts, No app activity, Workout streak, Weight not
   changing → a number; Form sent in → the form. Times move in half hours. Plan ends no longer shows a plan
   type (the board has none); it fires for programs and meal plans. The engine now waits for the picked time
   for Plan ends and Package ending, and "Weight not changing" means within 0.5 kg (the board's words).
4. **Board text from the server.** `trigger_line` ("Every Sunday at 9 am", "When 3 workouts in a row are
   missed") and each step's `summary` ("Send the form “Weekly check-in” by Push and Email") use the board's
   words, so the list, the "+N more" tip and In plain words read the same. Catalog starters carry their
   `trigger_line`. Rows come in the order they were made.
5. **Who it is for.** Package (from clients' packages) and Trainer (active trainers; a client is refused).
   The list line says "All clients", "Package: …" or "Trainer: …" (`scope_trainer_name`).
6. **Message preview** shows the first picked channel that has text in the template, with sample names filled
   in; when the template has no text for that channel it says so and points to Emails & alerts.
7. **Last 30 days** counts and lists runs started in the last 30 days (latest 20; the card shows 6). A row
   opens the client's profile.
8. **Demo data** (`seed_demo`): the five board automations with a few runs. Weekly check-in is seeded **Off**
   because the client app already asks the weekly check-in every week; turning it on would send the form twice.

## Not built yet
- `Message templates`, `Edit message templates` and the list's `Sender settings` open Emails & alerts and
  Settings, which are the next admin pages (they show the holding page until then).
