# D-52 · Admin Emails & alerts

**Date:** 2026-10-22 · **Boards:** Emails, EmailsMobile

## What was decided

1. **The board's words are the built-in messages.** The ten built-in messages now carry the text the board shows
   (Client invite, Welcome, Password reset, Onboarding form reminder, Check-in reminder, Missed workouts nudge,
   Coach feedback, Birthday wish, Renewal reminder, Trainer invite). Migration `notifications 0004` moves every
   built-in that was never edited to these words and makes them its "Reset to default" text; a message the owner
   already changed keeps its words. Two facts differ from the board on purpose: Password reset says the link
   works for **15 minutes** (the real token time, the board says 30), and the invite's `{{date}}` is the day the
   login link stops working (7 days).
2. **Trainer invite is in its own Team group** (the board's fourth group). New templates still pick Access,
   Coaching or Packages, like the modal.
3. **"Sent:" line and "Where it is used" come from the server.** Each message carries `when` (board text, custom
   ones "By an automation you pick"), `sent_by` (for messages the app itself sends, e.g. "Sent by the app on
   Forgot password") and `used_in`: every automation with a Send message step that uses it, with the board line
   "Step 3 · Push and WhatsApp" or "Steps 1 and 3". A message both the app and an automation send shows both.
   A custom message nobody uses shows "Not used yet" and `Open automation builder` (`/automations/new`).
   The list comes in the board's order, custom messages last.
4. **Editing.** Text is kept per message on the page until Save, so moving between messages or channels loses
   nothing ("Not saved yet" stays until saved). Save checks every channel that is on: email needs a subject,
   every channel needs text, at least one channel stays on; the first problem opens that channel and shows the
   error under the field. Variables go in where the cursor is (subject or message, whichever was used last), not
   only at the end. Limits: subject / title 50, push 120, WhatsApp 1000, in-app 500, email 2000. Turning on a
   channel with no text gives the board toast "… turned on / Write the text and save" (no made-up text).
5. **Delete + Undo.** Deleting a custom template removes it; Undo creates it again with the same key, name,
   group and words (`POST message-templates/` takes `key` and `texts` for this), so automation steps that point
   at the key work again.
6. **Team alerts do something now.** The four switches decide the channels of the team alerts, which go to the
   owner and the client's trainer, never to the person who did it:
   - New client: approving a sign-up, adding an active client, joining from a link without approval.
   - Check-in submitted: a weekly / monthly / survey check-in (daily pulses only refresh the queue, as before).
   - Plan updated: someone gives a client a workout plan or a meal plan.
   - Missed workout: the nightly at-risk alert.
   Each person's own switches still count (Me → Notifications: new check-in, missed workouts, new client; Push
   and Email). `Enable all` turns every channel on (`team-alerts/enable-all/`).
7. **Quiet hours** save at once (switch, From, To in half hours) and already hold push / WhatsApp / email for
   everyone (`in_quiet_hours`).
8. **Daily digest** is a new setting (`digest`: off / daily / weekly). At 8:00 am (weekly: Mondays) the owner and
   every active trainer with email on get one email: check-ins to review, at-risk clients and plans ending in
   the next 7 days, each for their own clients (`staff_digests` task). **It starts Off** (migration 0005), not
   Daily as the board shows: it is close to the trainer's Daily summary, whose design Gautam parked, so nothing
   new is sent until he decides. **Gautam, 2026-10-23: keep it Off**; it comes back with the Daily summary design.
9. **Sender** saves From name (required), Reply-to email and WhatsApp display number (digits, spaces and +).
   Emails already use the name and reply-to; the Clients see card follows what is typed. The invite's WhatsApp
   text is now sent too when it is on and the client has a mobile number.
10. **Layout.** 3 columns (list, editor, preview + where used) from 1040 px of content; list beside the editor
    with preview and where used under it from 680 px; below that (and on phones) the board's list → editor view
    with `‹ Messages`. On a phone the editor hides the page title and tabs, like the board.

## Not built yet
- Gym news (admin) and Daily summary design stay parked.
