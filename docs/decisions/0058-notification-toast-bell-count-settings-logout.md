# D-58 · New notification toast, unread count on the bell, Log out in admin Settings, demo data on the live site

**Date:** 2026-10-24 · **Asked by:** Probid ("ek toast aae ki notification aaya hai web me... bell icon pe kitne aae
unread ka count batae", "admin kaha se logout karega... setting me bhi rakho", "new app me demo data seed karo")

## What was decided
1. **Toast for every new notification while the app is open** (web, tablet, phone): `NotificationToasts` in
   `app/lib/app/unread.dart` sits under `ToastHost` and listens to the socket's `notification` event. It shows the
   title and body with a bell icon, **Open** goes to `data.route`. Phone / browser push (D-56) still covers the app in
   the background.
2. **Bell shows how many are unread** instead of the board's red dot: `BellCount` (red pill, "9+" above nine) on
   every bell: admin dashboard, trainer dashboard (both bells), client Home (web + phone hero) and client More. The
   number is live from the socket (`unread` on connect and after reads, +1 on each new one), else the page's own
   count. Deliberate change from the boards, asked by Probid.
3. **Admin Settings has Log out** at the top right (same "Log out?" confirm), besides the dashboard account menu
   and the phone More page.
4. **`seed_demo` works on the live site:** if an admin already exists (made with `createsuperuser`), the demo uses
   him as "Vimal" instead of making a second admin (only one may exist). His email, password and profile stay as they
   are; the demo trainers / clients get password `Demo@1234`.

## Checked
`flutter analyze` clean; backend tests (`test_seed_demo.py`, `test_invite_links.py`). Browser, debug mode: client at
390, 768 and 1280 (count 3 → toast "Coach Aman Verma replied" with Open), trainer at 1280 (9+), admin Settings with
Log out at 390 and 1280. `seed_demo` run twice on a DB with only a `createsuperuser` admin: 7 trainers, 22 clients,
admin login unchanged.
