# Rulebook — Flutter

- Open the board's `.dc.html` before building a screen; copy spacing, radius, copy and states.
- Breakpoints: phone < 600, tablet 600–1023, desktop ≥ 1024. Phone boards (390) and web boards (1440) are the references.
- Colours, type and radius only from `lib/core/theme` tokens (generated from `twv.css`).
- Every network write from a client screen goes through the outbox (`lib/core/offline`), never straight to dio.
- Modals on desktop = dialogs; on phone = bottom sheets, as the boards show.
- Every toast, empty state and error text comes from the board.
