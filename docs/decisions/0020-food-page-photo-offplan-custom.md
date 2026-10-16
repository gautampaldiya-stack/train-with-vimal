# D-20 · Food page: meal photo, off-plan reason, custom food per serving

- **Date:** 2026-10-15
- **Status:** Accepted

## Decision
1. **One Food page** (`/food`, board `ClientMealNutrition` / `ClientMealNutritionWeb`) replaces the separate meal
   plan and nutrition boards (`ClientFood`, `ClientNutrition`). Log food is `/food/log?meal=`.
2. **Mark as eaten is a dropdown** (Gautam): "Upload photo and mark as eaten" or "Mark as eaten without a photo".
   The photo is optional and goes **with** `POST me/food/meals/<id>/eat/` as a data URL (`photo`), so it waits in the
   outbox when offline. It is saved on `MealDayState.photo` (migration `nutrition 0002`); Undo / un-log clears it.
   `GET me/food/` returns it on the meal (`photo`) and on that meal's food-log rows.
3. **Off-plan reason:** `POST me/food-log/` takes `off_plan` and `reason` (`""`, `Ate out`, `Party`, `Travelling`);
   an off-plan entry has source `off_plan` and keeps the reason (`FoodLogEntry.reason`) for the coach.
4. **Custom food per serving:** `POST me/foods/` with `{name, serving, kcal, protein, carbs, fat}` (numbers for one
   serving) makes a client-only food with a unit named after the serving. The serving is sized
   `max(100 g, P + C + F)` so the per-100 g values stay valid. Answer = the pick shape (units, default unit).
5. `POST me/food-log/` also accepts `unit_name` (Undo of a deleted entry) and maps it to the food's unit.
6. Web: from 700 px of content the header, strip and tabs stay put and only the lists scroll (Gautam).
7. Every number on these pages (portions, quick add, custom food, portion sheet) keeps − / + and can be typed
   by tapping it (Gautam).
8. **Photo first, then confirm** (Gautam, 2026-10-16): picking a photo does not log the meal. The photo waits on
   the card (Change / remove), and a separate `Mark as eaten` sends it with `eat`. A logged meal's photo is
   changed or removed with `POST me/food/meals/<id>/photo/` (`{photo}` data URL, or empty to clear); only a
   logged meal takes it ("Mark the meal as eaten first.").
9. Foods logged from Log food into a meal show inside that meal card as "Also logged · outside the plan".
10. **Copy yesterday Undo:** `copy-yesterday` answers `{copied, ids, meals}` and skips plan rows of meals already
   logged today. `POST me/food-log/undo-copy/ {ids, meals}` deletes exactly those rows (today, own) and un-logs
   a meal that has no plan rows left. Answer `{removed}`.
11. **Other time** (Gautam, 2026-10-16): Log food's Add to has "Other time" for food eaten outside the meal
   times. The client names it and picks a time today (not later than now). `POST me/food-log/` with
   `other_time: true`, `meal_name` = that name and `logged_at` = that time; the entry is always off-plan, has
   `other_time` on it (`FoodLogEntry.other_time`, migration `nutrition 0003`), shows in the food log at that
   time and never inside a meal card. Copy yesterday keeps its clock time. Route `/food/log?meal=<name>&at=HH:MM`.
