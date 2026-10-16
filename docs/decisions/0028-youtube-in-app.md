# D-28 · YouTube plays inside the app; demo videos ship with the code

Date: 2026-10-16 · Asked by: Gautam

## Decision
1. **YouTube plays in the same modal.** Library item sheet and exercise guide embed the YouTube player
   (`youtube_player_iframe`: an iframe on web, a web view on Android / iOS), 16:9, with YouTube's own full-screen
   button. Under it an `Open in YouTube` link opens the YouTube app / site for whoever wants it. Chapters seek the
   embedded player. Uploaded videos keep our own player (seek bar, full screen that stays in the app).
2. **Exercise media can be a YouTube link.** If the exercise's library item is a video with no file but a YouTube
   link, `media.kind` is `youtube`; an exercise with only its own `youtube_url` also plays in the guide.
3. **Pictures in a modal are short.** Library image box 240 high (300 on web), guide picture 190 (240 on web), whole
   picture visible (contain), tap = full screen zoom.
4. **Demo videos ship with the code** (`backend/apps/common/demo_media/*.mp4`, about 350 KB total, h264), so
   `seed_demo` works on a machine without ffmpeg and fills in videos that have no file. Demo: Leg Press = uploaded
   video, Walking Lunge = YouTube link, Romanian Deadlift = picture.

5. **No web view → still + Open YouTube.** Windows / Linux desktop have no web view (and a hot-reloaded app has not
   registered the new plugin), so there the box shows the YouTube still with a play button that opens YouTube,
   instead of Flutter's red error. After `flutter pub get`, stop and run the app again (hot reload is not enough).

## Why
Gautam: "video yt ka ho ya library se uploaded ho, isi me show karo, full screen ka option, dusre page me na jae;
yt pe jana hai to option do", and "image itni badi height na le, puri dikhe". His seeded videos said
"Video not uploaded yet" because his machine has no ffmpeg.

## Not built
YouTube playback could not be checked in the sandbox (youtube.com is blocked there); check it in a real browser
and on a phone.
