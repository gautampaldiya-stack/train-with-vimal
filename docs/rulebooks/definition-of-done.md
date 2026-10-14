# Rulebook — When a screen is "done" (for everyone: Claude sessions and developers)

Why this exists: on 2026-10-14 the reset-password page (boards `ClientResetPassword` / `ClientResetPasswordWeb`,
opened from the forgot-password email) was left unbuilt, while the handoff note said "Reset password", which read
as done. Gautam found it while testing. These rules stop that from happening again.

## 1. Build the whole flow, not just the first page
- A flow is done only when **every page its buttons, links and emails open** is built too.
  Examples: Forgot password → the reset page from the email link. Invite → the join page. Sign up → verify email.
- Before starting a flow, list every board it touches (follow each button and link on the board), and build them in
  the same batch.
- A link that lands on the "This page is on the way" holder counts as **not done**.

## 2. Track every board in `docs/screens/status.md`
- Every one of the 104 boards has a row: **Done**, **Partial** or **Not started**, with a note.
- **Done** only after the screen is checked in a browser against the board, on phone (390) **and** desktop (1440),
  including its modals, sheets, menus, empty states and toasts.
- **Partial** must say exactly what is missing or not checked yet.
- Update the row in the same commit as the code.

## 3. Write what is NOT built, by name
- `docs/phases/CURRENT.md`, phase files, commit messages and replies to Gautam name unbuilt parts by board name.
- Never write a screen name that could read as finished when only part of it is built
  (write "Forgot password modal", not "Reset password").

## 4. When stopping
- The last reply and `CURRENT.md` list the boards still Partial / Not started for the flow being worked on.
