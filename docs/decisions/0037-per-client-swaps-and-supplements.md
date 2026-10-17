# D-37 · Swaps and supplements are per client; adherence counts the client's copy

Date: 2026-10-17

## Decision
- **Food swaps belong to the meal item, not the food.** `MealItem.alternatives` (JSON list of `{food, quantity, unit}`;
  `null` = never set, then `Food.swaps` applies) and `MealItem.origin` (the master item a client-copy item came from,
  for the "Was:" line). Migration `nutrition/0005_meal_item_swaps`. Making a client's copy seeds each item's swaps from
  the food's library swaps, so nothing is lost. Editing swaps in "Edit <plan> for <client>" changes only that client;
  the master and other clients on the same master stay the same. The client app's swap sheet, the Food tab's swap count
  and the "swap" meal action read the item's own swaps.
- **Match %** (`apps/nutrition/swaps.py`): `100 × (1 − (|ΔP%| + |ΔC%| + |ΔF%|) / 2)` on each food's share of calories
  from protein, carbs and fat. Swap amounts give the same calories as the item's amount ("Amounts give the same
  calories as 1 scoop."). `POST foods/<id>/units/` adds a serving unit from the editor ("+ Add a unit in the food
  library"); max 12 units, no duplicate names.
- **Supplements get a client copy like meal plans.** `SupplementPlan.is_master/master`, `SupplementAssignment.custom_plan`
  and `.followed` (= copy or plan). Migration `habits/0003_supplement_client_copy`. `PUT clients/<c>/supplement-plans/<a>/items/`
  creates / edits the copy (ticks and stock move onto it), `POST …/reset/` goes back to the master. The library lists
  and assigns masters only. Every reader (client app, logs, overview, account, reminders) uses `followed`.
- **Meals a day = the client's followed plan, per weekday.** `clients/metrics.py` `meals_by_weekday / meals_per_day /
  planned_meals` use `MealPlanAssignment.followed` and `meals_on(plan, weekday)`. Adherence, last 7 days, Overview,
  Logs → Meals, check-in review and the client's check-in page all count from it. `log_food`'s on-plan check uses it too.

## Why
Gautam (17 Oct): "Ek supplement ke swaps badlo to sab clients ke liye badalte hain"; "Adherence ka meals a day master
meal plan se count hota hai, client ki copy se nahi"; and the board's Portion and swaps panel ("Swaps Riya may use").
