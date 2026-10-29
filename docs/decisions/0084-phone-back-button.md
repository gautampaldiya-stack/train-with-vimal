# D-84 · Phone back button follows the app, ends at an exit sheet (Phase 4)

Date: 2026-10-29 · Asked by: Probid (batch 1, Phase 4)

## Root cause
- Every tab and page opens with `context.go`, so the router keeps a single page.
- Android back had nothing to pop, so the system closed the app.
- Nothing in the app listened for back: there was no `PopScope`, apart from the exercise editor.

## Decision
- `AppShell` wraps every signed-in page in a `PopScope(canPop: false)`.
  - The back press goes to `AppBack.handle` (`app/lib/app/shell/back_nav.dart`).
  - A widget test (`test/back_shell_test.dart`) checks that a back press inside the `ShellRoute` reaches it.
- Where back goes (`AppBack.parentOf`):
  - A sub-page goes to its section: `/food/log` → `/food`, `/train/workout` → `/train`, `/clients/<id>` → `/clients`.
    - Exception: `/progress/compare` → `/progress/photos`, the same place as the page's own back button.
  - A bottom-bar tab goes to Home (`/home`, or `/dashboard` for staff).
  - A page opened from More (Habits, Check-ins, Library, Programs…) goes to More, then Home.
  - On Home: "Do you want to exit the app?" with Exit and Cancel.
    - While a workout is running, the sheet also says "Your workout is still in progress" and shows **Resume workout**, which opens the logger.
    - Exit pauses the workout timer (D-17), then closes the app.
- Screens with their own steps take back first through `BackIntercept`:
  - The weekly check-in and coach forms do Save and exit (draft).
  - The daily check-in closes its edit first.
  - The workout logger closes the rest panel first.
- The client's phone bottom bar shows only on the main tabs (Home, Train, Food, Progress, More).
  - Sub-pages, pages opened from More and the logger hide it. They already have their own back button on the boards (`ca-back`).
  - The staff bottom bar is unchanged.
- Web is unchanged: the browser's back uses the URL history.

## Open
- Real-phone check with Probid on 2026-10-30 morning (moto g54 over USB).
- The spec's 6-tab bar (with Check-ins) is not done. The bar keeps the 5 tabs from the boards.
- iOS has no back button. Its swipe-back works only on pushed pages, which these are not.
