# D-86 · Food target = assigned foods, meal lock, confirms, progress photo tabs (2026-10-30)

From Probid's phone test of Phases 2–5 (2026-10-30).

## Food
- **Day target = what the plan assigns.** `day_view` adds up the planned portions of every planned meal (no swaps,
  no portion edits) and uses that as kcal / protein / carbs / fat target. The plan's stored `kcal_target` is used only
  when the plan has no foods. Reason: a client who logged every food still saw "404 kcal left".
- **No meal target.** The trainer's meal editor and the library meal builder no longer show a meal target, "/ target"
  or the On target badge. Each meal in the day API has `assigned` (planned totals); the card reads
  "ate 446 of 259 kcal" against it.
- **Meal lock.** A planned meal opens `MEAL_OPEN_BEFORE_MINUTES` (default 30) before its time. Before that the server
  refuses log / skip / portions / swap for that meal (`{"meal": ["Lunch opens at 1:00 pm."]}`) and the app shows
  "Opens at 1:00 pm · you can log it from then" instead of Edit portions / Mark as eaten; item taps, Swap and the
  meal menu show a toast. Home's Up next and Log food sheet show "Opens 1:00 pm" instead of Ate it. Log food → Add to
  says the same and skips locked meals as the default. Un-log, un-skip and photos stay open; past days are not locked;
  Ate something else / Other time is never locked. Day API: `opens_at` per meal.
- **Confirms.** Ate this / Mark as eaten / I ate it ask "Did you eat this?" (with the photo when there is one).
  Changing a meal with eaten foods asks "Do you want to change this food which is logged?". Tapping Logged · Undo asks
  "Un-log Lunch?".
- **Edit portions** shows "Planned <amount>" per food; a changed one shows Edited and Set to default.
- Eaten and skipped food names are muted.

## App
- Phones are portrait only (shortest side < 600, not web).
- Toasts sit 10 px above the bottom bar, measured.
- Android launcher icon: blue background, TWV wordmark at 54 % width, no inset (it looked small next to other apps).

## Progress photos
- **Add photos** has Front / Side / Back tabs; each tab keeps its own picked photo and one Save stores them all
  ("Save 2 photos"). A tab with a picked photo reads "Front ✓". 1–3 photos are fine.
- **Only today.** A set the client added herself can be changed (Change photo) or deleted (Delete photo) on the day it
  was added. Older sets are view only ("Photos can be changed only on the day they were added."); check-in photo sets
  change only through the check-in. The server refuses `DELETE me/photos/` for any other day; deleting the last photo
  of a set removes the empty set.

## Later the same day (Probid, phone round 2)
- **A meal's food** opens a sheet like a food on Log food: amount stepper (today), "Planned …" + Edited, four macro
  boxes, Save portion / Reset when changed, then the actions. Swap moved from the row into this sheet (Swap food).
  Past days show the same sheet without actions; a locked meal says when it opens.
- A logged meal shows Eaten on each food it counted, and those names are muted. Taking an eaten food off
  (Not logged yet) asks first.
- **Edit portions**: Edited sits next to the food name; the total is a plain line ("Total" over the numbers) with
  "+120 kcal vs plan" against the coach's portions.
- **Log food**: + only picks a food (✓); "Add N foods to Lunch · +K kcal" logs them all and goes back to the meal
  plan, one toast with Undo. Back with picked foods asks "Add … to Lunch?" Add · Cancel · Discard. The portion
  sheet's button is Select. Quick add also picks. Order: meal card, Can't find the exact food?, then search and the
  food list, so Show all only grows the end of the page.
- Confirm sheets on phones put Cancel and the action side by side.
- Toasts can be swiped sideways to close.
- Add photos no longer shows the weight.
- Food sheet macros are four plain columns between two lines (no boxes, no colour). Eaten / Skipped tags on food
  rows are smaller (18 px).
- Log food: the phone's back button asks too (the page sits on top of /food, so it pops itself); the default meal
  is the first open meal that is not locked. Plurals: handfuls, slices…
