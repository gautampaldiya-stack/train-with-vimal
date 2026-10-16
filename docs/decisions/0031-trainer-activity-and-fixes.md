# D-31 · Trainer dashboard Activity card; stats cards fill the row; readable guides

Date: 2026-10-16 · Asked by Gautam

## Decision
- The trainer dashboard gets an **Activity** card (not on the board) under This week: what the trainer and their
  clients did, newest first, 6 rows a page with "Show more". It reads the same ActivityEvent table as the admin
  Activity log, limited to the trainer's own actions and their own clients (`trainer_home.activity`).
- Web stat cards: 4 equal cards across the row (2 × 2 when the page is under 760 wide), height follows the content
  (min 80). Replaces the fixed 80 px content-width cards, which clipped the number by 4 px.
- Dropdown menus open on the side with more room, never leave the screen, scroll, and start at the picked row.
- Library: the demo PDF is a real designed guide; article text is 15 / 1.7, max ~620 wide, with headings and bullets.
- YouTube box: if the web view part is missing (e.g. a debug run hot-restarted after the plugin was added) or the
  player fails to start, the still + "Open in YouTube" shows instead of an error.

## Why
Gautam (2026-10-16): "trainer dashboard ... stats ache karo", "ye date select wala acha karo", "ek aur activity
card ... trainer ke client and uske related kuch bhi activity ho usko show ho", "ye ek pdf wala example rakho",
"guide ka likhavat ... ache se likha dikhe".
