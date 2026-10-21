# D-44 · Nutrition & foods: who may change a plan, the food library and import, the meal plan builder

Date: 2026-10-21

## Decision
- **Who may change a meal plan** (same rule as programs, D-39 / D-43): Vimal, the trainer who made it, or a trainer
  with "Edit gym templates". Making, duplicating and assigning need the "Meal plans" access. Others see a plan
  read-only with **Duplicate to edit**. A trainer sees and assigns only their own clients (`visible_clients`).
  Cards and the builder say who made a plan (Gym / By you / By Aman).
- **Delete a plan** takes it off its clients; the toast's **Undo** (`restore`) brings the plan and those clients back.
  Assign and Undo on the same day leaves no Plan history (`MealPlanAssignment.end_reason` / `replaced`, like D-43).
- **Food library**: built-in foods can't be deleted (403, "Duplicate it to make your own"); team foods can (Undo).
  Every row says which plans use it (`used_in`, tooltip `used_tip` "Plan · Meal, Meal"). The Create / Edit food
  drawer keeps every number per 100 g and converts when you type per serving; units with a default serving, the
  source (Your team, Pack label, IFCT, USDA), more nutrients and the food's own swaps.
- **Excel import**: upload → check (new / already there / errors, a preview per 100 g) → import, with a choice for
  foods already in the library (skip / update the numbers / add as new) and Undo on the toast.
- **Meal plan builder**: every change is a **draft** on the device (badge "Draft", the warn banner) until **Publish**,
  the board's word for Save changes. Publish sends the meals (`PUT structure/`), the targets and permissions
  (`PATCH`), then `POST publish/`: the plan's clients and their trainers get a notice. **Discard** goes back to the
  published plan. Leaving with a draft asks **Publish / Don't publish / Cancel** (the `LeaveGuard` of D-43).
  Rename, assign, version notes, reset and remove act at once (they are not part of the draft).
- Portion and swaps sits beside the meals from 900 px of content; narrower it opens as a drawer (a sheet on phone)
  when a food is tapped. The targets card is one row from 960 px, else a 3-column grid.

## Why
Gautam: same behaviour as the Program builder (save with a button, ask before leaving, who made it, Undo without
history), and the boards `Nutrition`, `NutritionMobile`, `MealPlanBuilder`, `MealPlanBuilderMobile`.
