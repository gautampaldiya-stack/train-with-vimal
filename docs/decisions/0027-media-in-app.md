# D-27 · Media in the app: video, pictures, PDF pages, links

- **Date:** 2026-10-16
- **Status:** Accepted (Gautam: "pdf, media, article ache se open ho", "exercise me video ya image", "links bhi honge")

## Decision
1. One set of media widgets for the whole app (`app/lib/core/widgets/media.dart`): an in-app video player
   (play / pause, seek bar, full screen that keeps playing) and a full-screen picture viewer (pinch / scroll zoom,
   swipe between pages).
2. **PDFs show their real pages.** The server draws each page once as a PNG (pypdfium2, 1100 px wide, up to 60
   pages, kept at `content/pages/<item>/<n>.png`) and the item detail returns `page_images`. Same look on Android,
   iOS and web, no PDF reader in the app. Download still opens the file.
3. **Exercises can have a video or a picture.** `Exercise.video` may point at a content item of kind video or image;
   the exercise API returns `media` {kind, url, title, duration}. A program's own override video wins. YouTube-only
   exercises show the YouTube still and open YouTube.
4. **New content kind `link`** (`link_url`): a reference web page. Library filter `Links`, length shows the site
   (healthline.com), the sheet has `Open link`. Staff must give a link for this kind.
5. YouTube videos open in the YouTube app / site (no in-app YouTube player yet). *Changed by D-28: YouTube now plays inside the app.*

## Why
Coaches share uploaded videos, YouTube links and web pages; clients need all of them to open well on a phone.
Drawing PDF pages on the server avoids three different PDF readers.
