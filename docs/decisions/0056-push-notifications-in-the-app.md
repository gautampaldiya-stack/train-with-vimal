# D-56 · Push notifications in the app (Firebase), keys outside git

**Date:** 2026-10-23 · **Asked by:** Gautam ("mere local me bhi set kar do... notification and all... ki local me try
kar saku", "ye copy ki hui kaha daalni hai")

## What was decided
1. **The app registers for push.** After login (approved accounts, together with realtime) the app asks for
   notification permission, gets the FCM token and sends it to `devices/` (`platform` android / ios / web). Token
   refresh re-sends it. Log out deletes it (`DELETE devices/`) before the session ends. Tapping a push opens
   `data.route` (the same route the in-app notification has). Code: `app/lib/core/push/push.dart`.
2. **Web push** uses `app/web/firebase-messaging-sw.js` (Firebase compat SDK from gstatic), which reads the project
   keys from `web/firebase-config.js`; a notification click focuses the app tab and opens the route.
3. **One config file, not in git:** `app/firebase.json` (template `app/firebase.example.json`) holds the project,
   sender, web, VAPID, Android (and later iOS) keys. The app reads it with `--dart-define-from-file=firebase.json`;
   `dart run tool/firebase_web.dart` writes `web/firebase-config.js` from it. No `google-services.json` /
   `GoogleService-Info.plist` in the project (the app passes FirebaseOptions itself), so nothing Firebase is committed.
   Without the file push is off and the app works as before.
4. **Live site:** GitHub secret `FIREBASE_JSON` = content of `app/firebase.json`; the deploy writes it, makes the web
   config and builds with it. Empty secret = push off.
5. **Server key** stays a file: `backend/secrets/firebase-service-account.json` on a PC
   (`FCM_SERVICE_ACCOUNT_FILE=secrets/firebase-service-account.json`), `/root/twv/secrets/` on the server
   (`/app/secrets/...` inside Docker).
6. The server keeps sending to FCM registration tokens (HTTP v1 `token`), so the app uses `getToken` (marked
   deprecated in firebase_messaging 17 in favour of installation ids; kept on purpose, with a comment).
7. iPhone push waits for the Apple developer account (APNs key); the code already handles iOS.

## Not checked yet
Real pushes need Gautam's Firebase keys; Android was not built in the cloud session (no Android SDK). Web build and
`flutter analyze` pass; without keys nothing Firebase starts.
