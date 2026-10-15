# Rulebook — Flutter

- Open the board's `.dc.html` before building a screen; copy spacing, radius, copy and states.
- Breakpoints: phone < 600, tablet 600–1023, desktop ≥ 1024. Phone boards (390) and web boards (1440) are the references.
- Colours, type and radius only from `lib/core/theme` tokens (generated from `twv.css`).
- Every network write from a client screen goes through the outbox (`lib/core/offline`), never straight to dio.
- Modals on desktop = dialogs; on phone = bottom sheets, as the boards show.
- Every toast, empty state and error text comes from the board.
- Never change a `ValueNotifier` (or call `setState` elsewhere) from `dispose()` or while a frame is finishing.
  On web that marks widgets dirty with no next frame, and the app stops repainting until the next tap.
  Defer it with `Timer.run` (see `ToastOffset` in `lib/core/widgets/overlays.dart`).
- Big headlines that use `text-wrap: balance` on the boards use `BalancedText` (`lib/core/widgets/balanced_text.dart`).
- Pages that are separate screens get their own top-level route. A child route keeps its parent page alive
  (hidden) underneath, with its own loads and toasts.
- Tooltips use `AppTooltip` (`lib/core/widgets/tooltip.dart`): the board's white card with a line border, on the
  side the board shows (`above`, `below`, `left`, `right`). Not Flutter's dark `Tooltip`.
- Anything that sticks out over the page panel (like the sidebar edge button) goes in the shell's top `Stack`,
  not inside the sidebar, or the panel paints over it and eats its clicks.
- The web app uses path URLs (`usePathUrlStrategy()` in `main.dart`), because emails link to `/reset-password?token=…`,
  `/verify-email?token=…`, `/start?token=…` and invites to `/join/<code>`. The web server must fall back to `index.html`.
- Link pages (`/reset-password`, `/join`, `/start`, `/verify-email`) open signed in or out and stay open after they sign
  the person in. `/login` and `/forgot` send a signed-in person to `landingFor(me)`. A client whose email is not confirmed
  lands on `/verify` (see `lib/app/router.dart`).
- Account pages share pieces in `lib/features/auth/account_widgets.dart` (top row with Help, illustration box,
  heading, badge, password strength and rules, timeline, Get the app card, resend countdown) and the desktop side
  panels in `auth_frame.dart` (`BrandPlain`, `BrandList`). Illustrations are `assets/ill/<name>.svg`.
- Every "set a password" field pair sends `password` and `confirm_password`.
- Sheet buttons that should fill the width (the boards' `.ca-sf`) pass `footerStretch: true` to `showAppSheet`.
  Without it the web footer is a `Row`, and a full-width `CaButton` inside it crashes ("RenderFlex children have
  non-zero flex but incoming width constraints are unbounded").
- Toast side: phone centred, tablet / web bottom right (see `docs/design.md` §4.5).
- Hot restart on web may print `LegacyJavaScriptObject is not a subtype of JdbNotificationRevision` from
  `sembast_web`: the old page's IndexedDB listener fires into the new Dart code. Debug-only, harmless; a full
  page reload (or `R` then F5) clears it. Release builds never hot restart.
