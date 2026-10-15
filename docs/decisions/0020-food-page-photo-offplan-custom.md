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
