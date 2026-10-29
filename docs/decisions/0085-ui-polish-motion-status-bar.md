# D-85 · UI polish: 3-dot menus, status bar per page, one motion set (Phase 5)

Date: 2026-10-29 · Asked by: Probid (batch 1, Phase 5)

## 3-dot menus
- "Meal options" (Food) and "Workout options" (logger) used the ☰ icon. They now use `AppIcons.dots`, the same "More actions" icon the staff pages use.
- The bottom-bar **More** tab keeps ☰, because it opens a page, not a menu.

## Status bar
- **Root cause:** only client Home and the trainer dashboard (blue hero) set a status bar style (`SystemUiOverlayStyle.light`). No other page set one, so the phone kept the white icons after leaving Home, and they were unreadable on white pages.
- **Fix:** `AppShell` wraps every signed-in page in an `AnnotatedRegion` with dark icons:
  - Android: `statusBarIconBrightness: dark`.
  - iOS: `statusBarBrightness: light`.
- The hero pages keep their own light region inside it, so the dark icons come back on any other page.

## Motion (`core/theme/motion.dart`)
- One set of values for the whole app:
  - Press: 120 ms.
  - Short (menus, dropdowns, field focus): 200 ms.
  - Medium (pages, dialogs, web sheets): 250 ms.
  - Phone sheets: 280 ms in, 200 ms out.
  - Curve: ease-out cubic.
- `Motion.off(context)` is true when the phone asks for no animations ("Remove animations" / "Reduce motion"). Every animation then runs at zero length.
- **Pages and tabs:** fade with a 2 % rise (`CustomTransitionPage` in router.dart). A query-only change, such as a tab inside a page, does not animate again.
- **Press feedback:** every tappable `Hover` (all custom buttons and rows) shrinks to 97 % while pressed. `pressScale: 1` turns this off.
- **Fields:** the border, the focus ring and the label colour animate on focus, in both client and staff inputs.
- **Menus and dropdowns:** fade in and grow from 96 %.
- **Dialogs and web sheets:** fade in and grow from 96 %.
- **Drawers:** slide in over 250 ms.
- **Lists (`AnimatedRows`):** a new row grows in and a removed row folds away. Rows already shown on the first build do not animate.
  - Used in the client food log and the workout sets.
  - The habits list changes only when the coach edits it, so it is left as is.

## Not checked yet
- The status bar on a real Android or iOS phone, and the feel of the animations on the moto g54: with Probid on 2026-10-30.
