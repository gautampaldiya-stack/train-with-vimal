# D-11 · Every screen responsive (phone, tablet, desktop)

- **Date:** 2026-10-14
- **Status:** Accepted

## Decision
Every screen works on phone (<600), tablet (600–1023) and desktop (≥1024).

## Why
Gautam's rule.

## How (added 2026-10-15, Gautam: "mobile ka mobile screen size me hi open ho, tablet me nahi")
- The phone layout is only for widths under 600. A tablet or a small browser window never gets the phone layout.
- Breakpoints live in `Breakpoints` (`lib/core/theme/metrics.dart`); use `context.isPhone` / `screen`, not new numbers.
- Layouts must change smoothly while a browser window is resized: no fixed widths that overflow, side panels
  shrink before they disappear, columns wrap instead of clipping.
- Login / account pages (`auth_frame.dart`):
  - under 600: phone layout (hero, buttons pinned at the bottom);
  - 600–899 (tablet portrait, small window): web layout, logo above, page in a white card, no side panel;
    the page shows the pictures and Help the side panel would have shown;
  - 900 and up: side panel next to the page, 40% wide (360–520); its picture shrinks on short screens.
- Staff shell: phone bottom bar under 600, icon-only sidebar 600–1023, full sidebar from 1024.
- Check every new screen at 390, 600, 768, 900, 1024, 1280 and 1440 before marking a board Done.
