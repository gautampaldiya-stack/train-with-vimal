# D-53 · Admin Settings

**Date:** 2026-10-22 · **Boards:** Settings, SettingsMobile · **Route:** `/settings` (`?tab=b`, `r`, `i` open Branding,
Roles & access, Integrations)

## What was decided

1. **General → Gym profile.** Name (required), contact email, phone / WhatsApp, address and the board's single
   "Website / Instagram" field (stored as `instagram`). `Save changes` saves all five; the footer shows
   "Last saved 2 Oct" from the new `profile_saved_at` ("Saved just now" right after a save). The phone accepts
   digits, spaces and + only.
2. **General → Regional & defaults save at once.** New fields `default_units` (metric / imperial) and
   `week_start` (mon / sun) on GymSettings, plus the existing timezone and language. Units shows the board toast
   "Units set to metric / For new clients" with Undo. The timezone list is a short list of common zones
   (Asia/Kolkata (IST) first); language is English only until the app has another language.
   **They really apply:** a new client account starts with the gym's units (kg / cm / L or lb / in / oz), week
   start, timezone and default theme (a `pre_save` signal fills only fields still on the model default, so a
   value picked during sign-up wins). Staff accounts are not touched. Existing clients keep their own.
3. **Branding** works like the board: colour and theme changes are saved as a draft ("Not applied yet") until
   `Apply`; picking the live value again clears the draft ("Applied"). `Reset` puts back blue + light at once
   (toast "Branding reset / Blue and light theme"). Logo upload takes PNG, JPG, WebP or SVG, at least 512 x 512,
   at most 5 MB (an SVG with scripts is refused) and is live at once (toast "Logo uploaded / name · 512 x 512");
   `Remove` shows the initials again. The hex box takes any `#RRGGBB`. The preview shows the gym name, logo or
   initials, colour and the dark look.
   **Not yet in the client app:** the client app still uses its fixed blue and has no dark theme; using the
   applied colour, theme and logo across the client app is a separate piece of work (**Gautam,
   2026-10-23: later**, after the admin pages).
4. **Roles & access.** Role cards show real counts: active trainers and active clients. In the matrix only the
   trainer cells the app enforces can change: View all clients, Create programs & meal plans, Daily + weekly
   check-ins, Manage content library, Schedule sessions (these already cap or widen every trainer's own permissions).
   Locked (dimmed, with a tooltip saying why): the admin column; trainer "View assigned clients" (always on),
   "Assign / reassign clients", "Add trainers", "Automations & settings" (admin only, the Admin card says
   trainers cannot be given admin access); and the whole client column ("Clients only ever see their own plan
   and data", check-ins on). The server keeps locked cells as they are even if a request sends something else.
   `Reset` goes back to the defaults (Save to keep it); "Not saved yet" shows while the boxes differ from what is
   saved.
5. **Integrations do something.**
   - **WhatsApp Business:** the business number is the same number as Emails & alerts → Sender. When
     disconnected, WhatsApp messages (automations, reminders, invite text) are skipped; email, push and in-app
     keep going. New installs start Connected, as the app already sent WhatsApp before.
   - **Email sending:** the owner enters a domain; `Check records again` looks up the SPF, DKIM
     (`twv._domainkey`) and DMARC TXT records (DNS over HTTPS, no new library) and shows Verified / Waiting per
     record. When all three are there, emails come from `hello@<domain>` with the sender name, and the owner
     gets an email + notice "Your email domain is verified". While waiting, the check runs again every hour
     (beat `email-domain-check`). Until then emails go from the platform address. Starts as "Checking DNS" for
     trainwithvimal.com.
   - **Apple Health / Health Connect:** Connect saves which data may be read (steps, sleep, heart rate,
     workouts; at least one). The phone side (reading Health / Health Connect on the client app) is **not built
     yet**, so the card says "No clients linked yet".
   - Disconnect asks first (board texts, `Keep it` / `Disconnect`), toast with Undo puts back the old state.
   - "Used in" links are counted from what is set up: automations with a WhatsApp step, client messages with
     WhatsApp / email on; each opens that page.
6. **Layout.** Two columns (main + 340 px side) from 860 px of content; below that one column like the
   mobile board. Role and integration cards are three across from 820 / 980 px, otherwise stacked. On a phone
   the Regional rows put the control under the words and selects go full width; the Connect / Manage modal
   opens as a bottom sheet.

## Not built yet
- The client app using the brand colour, dark theme and logo (Gautam: later).
- Reading health data on client phones (Apple Health / Health Connect).
