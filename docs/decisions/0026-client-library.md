# D-26 · Client Library

- **Date:** 2026-10-16
- **Status:** Accepted (built to the ClientLibrary / ClientLibraryWeb boards)

## Decision
1. A client sees an item when it is shared with everyone or shared with them (`ContentShare`). A share has an optional
   **note** (500 chars) and a **source**: `coach` ("Assigned by Aman · 28 Sep"), `program` or `meal_plan`
   ("From Fat loss · 8 weeks"). Items for everyone read "For all clients · <date>".
2. New / Done / Saved live on `ContentView` (one row per client and item). Opening an item creates the row, so it is
   no longer New. `POST me/library/<id>/progress/` takes `saved`, `finished` and `progress`; the app sends these through
   the offline outbox.
3. `GET me/library/?kind=&q=` returns the rows (unread first, then newest), counts per filter, done / new totals,
   the coach's first name and initials, and every note for the web Notes card. `GET me/library/<id>/` adds the body
   paragraphs, video chapters (`[seconds, name]`), PDF page outline (`[heading, text]`), file URL and a readable
   file name (the title, not the stored name).
4. Videos play in the app (`video_player`); reaching the end marks the item done. PDFs show the coach's page outline
   in the app and open the real file with Download; there is no PDF renderer in the app yet.
5. In development, media is served with HTTP Range support (`apps/common/media.py`) so videos can seek; production
   serves media from S3.

## Why
The boards show a reader per kind, notes from the coach and progress the client can see. Keeping state on
`ContentView` reuses what the coach's analytics already read.
