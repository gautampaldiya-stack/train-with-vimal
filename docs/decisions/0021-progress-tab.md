# D-21 · Progress tab: one answer, History endpoint, photos by data URL

- **Date:** 2026-10-16
- **Status:** Accepted

## Decision
1. **One answer for the tab:** `GET me/progress/` returns start / now / goal (+ `eta`), every weigh-in, measurements,
   next measurement date, lifts (best, first, series, coach note), adherence (program, done, planned, missed dates,
   today's workout, 6 weeks) and the photo sets. The app caches it, so the tab opens offline.
2. **Chart range on the phone:** `4 wk` / `12 wk` / `6 mo` / `All` filter the weigh-ins already loaded; no request.
3. **Goal date from pace:** `eta` = today + (kg left ÷ kg lost per week over the last 8 weeks), capped at 10 years;
   no `eta` when the weight is not moving toward the goal.
4. **History is its own endpoint:** `GET me/history/?range=week|month|3months&type=workout|meal|checkin|weight&offset=&limit=`
   (limit up to 31). Answer: `range, type, from, to, summary{…}, count, offset, days[{date, score, entries[]}]`.
   Days with no logs of the chosen type are left out. The app asks for 7 days, then 10 more.
5. **Weigh-ins:** one a day; `POST me/weights/` on a day that has one replaces it; future dates are refused.
   Undo puts the old value back (or deletes the new day).
6. **Photos by data URL:** `POST me/photos/ {pose, image: data URL}` adds the pose to today's set (created when
   missing, label "Added by you"); a pose already there is replaced (`replaced: true`). This lets a photo wait in
   the offline outbox. `DELETE me/photos/?id=` removes one (Undo of an added photo).
7. **Demo data:** `seed_demo` gives Riya 4 measurements (every 2 weeks) and photo sets (Start, Week 2, 4, 6) with
   drawn placeholder pictures, so every Progress page has something to show.

## Why
The boards show the whole tab at once and switch ranges instantly; one cached answer keeps that fast and offline.
History can grow (3 months × every log type), so it pages from the server.
