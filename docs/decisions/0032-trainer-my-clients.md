# D-32 · Trainer My clients

Date: 2026-10-16

## Decision
- My clients uses the existing `clients/` API (trainers only see `visible_clients`). Rows now carry `goal_label`,
  `next_checkin` and `last_active`; the list annotates the latest weekly check-in so Next check-in costs no query
  per row.
- Next check-in rule (column and filter share it): weekly check-ins are due on Sunday. Paused → "Paused", not
  active → "—", no weekly check-in in the last 8 days (and started 8+ days ago) → "Overdue", this week's sent →
  next Sunday, Sunday still due → "Today", else this Sunday. Filter `next_checkin=today|week|overdue`.
- Export: `clients/export/` takes the same filters, or `ids=` for "Selected clients". The app saves the CSV
  (browser download on web, Downloads folder elsewhere: `core/util/save_file.dart`).
- Edit details uses the Add client drawer's sections; `PATCH clients/<id>/` now also takes `current_weight_kg`.
- No AV profile button top right (Gautam removed it on the dashboard; same on every trainer page).
- Add client / Invite link drawers exist on the board but nothing opens them there, so the trainer app does not
  have them.
- Shared widgets: `AppSelect` (core/widgets/select.dart), `Pager` (core/widgets/pager.dart), `disposeLater`
  (overlays.dart).
- Export and selection were turned off on 16 Oct (D-33); code is commented, API kept.
