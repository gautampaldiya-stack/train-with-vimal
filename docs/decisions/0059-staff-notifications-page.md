# D-59 · Notifications page for admin and trainer

**Date:** 2026-10-24 · **Asked by:** Probid ("sare notifications dekhne ka page bhi banana hai... ache se bnana... sab
test kar dena")

## What was decided
1. **`/notifications` for admin and trainer** (`app/lib/features/trainer/notifications/notifications_screen.dart`).
   There is no board for it, so it reuses what the canvas already has: the Activity log's card, day headers
   ("TODAY · 3") and footer ("Showing 30 of 38" + Show more), and the bell dropdown's rows (initials of who did it,
   or a bell for the system; unread rows tinted with a blue dot).
2. **Top:** "Notifications", sub "5 unread · 38 in all" / "All caught up · 38 in all". **Mark all read** (Undo in
   the toast) and a gear for notification settings: admin → Emails & alerts → Team alerts, trainer → My profile →
   Account. Phone and narrow tablet show both as icon buttons.
3. **Tabs:** All · Unread, with counts. `?tab=unread` opens Unread.
4. **Rows:** a tap marks the row read and opens its page (`data.route`). ⋯ (always shown on touch, on hover with a
   mouse) has Open, Mark as read / Mark as unread, Delete. Delete waits 10 s for Undo in the toast, then deletes
   on the server (leaving the page sends it at once).
5. **Live:** a new notification goes on top with no reload, and the counts change with it (socket `notification` and
   `unread`).
6. **Ways in:** bell dropdown → **See all notifications** (new footer link), More → Notifications (admin under
   Workspace, trainer under You). Opening a row from the bell dropdown now also marks it read.
7. **API:** `notifications/unread/` returns `{count, total}`. List rows and the live socket row both carry
   `actor_name`, `actor_initials` and `actor_color`.

## Checked
`flutter analyze` clean. `tests/test_notifications_page.py`: actor fields, count + total, read / unread / delete /
read all, only your own, live payload. Browser, debug mode, demo data with 37 notifications: admin at 1280 and 390,
trainer at 768 and 390. Checked: list and day groups, the Unread tab, the ⋯ menu, Delete + Undo toast, the live row
with its count going up, Mark all read + Undo, Show more (30 → 38), a row opening `/checkins` and being read on the
server, bell → See all, and the More row.
