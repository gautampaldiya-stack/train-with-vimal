# D-81 · Plan save with a newly added exercise; exercise picker loads 50 at a time and searches on the server

**Date:** 2026-10-29 · **Asked by:** Probid ("Could not save the plan… esa na aae", "page_size=200 ye isme 50 rakho
but search kare tab ache se aajae… jab typing stop ho tab trigger ho")

## Root cause: "Could not save the plan / Please check the highlighted fields"
The client plan editor (Edit Phase 2 workout plan for Anish → Thursday → Add exercise "Back Squat", "Added for this
client") sends the whole tree to `PUT clients/<id>/programs/<a>/custom-structure/`. A row that is not saved yet goes
up with `"id": null`, and since "changes carry to the later weeks" that row is in every later week too. The
week / day / exercise serializers had `id = IntegerField(required=False)`, which refuses `null`, so the server answered
400 `weeks.N.days.M.exercises.K.id: This field may not be null.` for each week and nothing was saved.
`services.sync_structure` already treats an empty id as a new row, so the fix is `allow_null=True` on the three id
fields. Rows that had ids keep them (logged workouts stay linked).

## Exercise picker (Add exercise / Add superset / Swap drawer)
- It asked `exercises/?page_size=200` once and filtered in the browser. The server caps pages at 100, so exercises
  after the first 100 (by name) could never be found.
- Now: 50 a page, the next 50 load while scrolling; search goes to the server (name or muscle) only when typing stops
  for 400 ms, never on each letter; old answers are ignored if a newer search was sent; muscle tabs filter on the
  server and show counts for the current search (`exercises/facets/`). Ticked exercises stay ticked across searches.

## Other lines in Probid's console (no code change)
- `GET auth/me/ 401` once at start: the saved access token had expired; the app refreshes it and carries on.
- `Push not started: AbortError: Registration failed - push service error`: Brave blocks Google's push service by
  default. brave://settings/privacy → "Use Google services for push messaging" on, restart Brave. Chrome is fine.

## Checked
`tests/test_plan_save_d81.py` (null-id exercise in every week, new week / day with null id; fails without the fix).
`flutter analyze` clean.
