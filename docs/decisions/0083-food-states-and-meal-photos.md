# D-83 · Food states, eaten vs planned, more meal photos (Phase 3)

Date: 2026-10-29 · Asked by: Probid (batch 1, Phase 3)

## What Probid said
- 3.3 (b): remove the daily target from the trainer's meal plan editor.
- 3.4: yes to a state for each food (database change).
- 3.6: yes to more photos per meal, "3-4 minimum". We use 4.
- "clcint me accurate aane chchaiye.. meal stats food khaya jitna... assign kitna kiya uska": the client sees what she ate next to what was planned.

## Decision
- `MealDayState.items` holds each planned food's state for the day: `eaten`, `skipped`, or missing (not logged yet).
  - The meal status follows the foods. When every food is decided, the meal is logged if something was eaten, else skipped. Until then it stays open ("Partly eaten").
  - "Mark as eaten" eats every food not skipped. If all were skipped, it eats all.
  - "Skip meal" skips every food.
  - Undo clears the states and the photos.
- A skipped meal changes only when she taps. Nothing on the server turns it into eaten. The skipped card's button is now "I ate it" (was "Eaten after all", it read like a status) and asks "Did you eat this?" first, and so does "Ate it" on Home.
- `FoodLogEntry.meal_item` links a plan entry to its planned food. Deleting that entry turns the food back to "not logged yet". Delete asks "Delete this entry?" first.
- Portions and swaps rewrite only the eaten foods' entries, so the states stay. "Edited" shows when today's portion is not the planned one. "Set to default" puts the planned portion back.
- Day API, per meal:
  - `eaten` holds the totals of what she ate (rounded once from the unrounded entries, D-82).
  - `photos` holds up to 4 URLs.
  - Each food has `state` and `edited`.
- Photos: `MealDayState.photo` holds the first, and `MealPhoto` rows hold the rest, up to 4. Op `photo_add` adds one. A 5th returns 400.
- A food whose kcal does not match 4P + 4C + 9F is logged as a server warning. It is not blocked.
- Trainer:
  - The meal-log drawer shows "Partly eaten · X of Y kcal" and "+N" photos.
  - The meal plan editor no longer shows the daily target row or the over/under badge.
  - Per-meal targets and the library template targets stay.

## Not changed yet
- (none of the button names: Probid chose "I ate it" on 2026-10-29)
- The client's "Today's calories" sheet still shows the plan target. Probid picked (b), not (a).
