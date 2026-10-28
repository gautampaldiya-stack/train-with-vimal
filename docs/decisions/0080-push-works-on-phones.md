# D-80 · Push reaches the phone: token moves to who is logged in, dead tokens only, every device tried

**Date:** 2026-10-28 · **Asked by:** Probid ("sab se pehle notification wala… mere notification aane chaiye").
Done on `working` after it was set back to `develop` (4ccacdd) on Probid's word; the old `working` is kept as
`/mnt/project-files/backup-oct28/working-before-rollback-d059df1.bundle` (project files).

## Root causes found
1. **Token stuck on the first account.** The app saves its FCM token on every start (`POST devices/`). The
   serializer kept the model's unique check on `token`, so from the second time the server answered 400 "Please
   check the highlighted fields": the token stayed with whoever logged in first on that phone / browser, and
   pushes for the person logged in now went nowhere (or to someone else).
2. **Good tokens deleted.** Any FCM 400 with `INVALID_ARGUMENT` deleted the device. That status also means "bad
   message", so one wrong message silently stopped every later push to that phone. Now only a token FCM no
   longer knows is dropped (`token_is_dead`: 404 / UNREGISTERED / "registration token" 400).
3. **Android channel `default`.** The server asked for channel `default`, which the app never makes. The field is
   gone; Android uses Firebase's own channel. Status-bar icon: white bell `ic_stat_notify` (manifest meta-data),
   not a grey square.
4. **One device stopped the rest.** A passing FCM error on one device raised at once: the person's other devices
   got nothing, and the retry sent it twice to the ones before. Now every device is tried; the delivery retries
   only when none got it.
5. **Device not saved until the next start.** Push started only when the live socket connected (approved
   accounts) and asked for permission without a tap (browsers may refuse). Now it starts once per logged-in
   account, also while waiting for approval, and again right after "Allow notifications" on the permissions page.
   `start()` runs its setup once even when called twice at the same time.
6. **Wrong / missing project.** `FCM_PROJECT_ID` empty or not the app's project = every push refused. The server now
   takes `project_id` from the key file when `.env` has none; `push_test` prints which project it uses.
7. **Web:** a browser subscription left from another VAPID key / project ("AbortError: push service error") is
   dropped and asked again; tapping a web push focuses the open tab and opens the page (`sw_routes_web.dart`);
   nginx never caches `firebase-messaging-sw.js` / `firebase-config.js`.
8. **FlutterFire file.** `tool/firebase_web.dart` warns when `app/firebase.json` is FlutterFire's file
   (`{"flutter": …}`); the app logs "Push off: this build has no Firebase keys" once. No FlutterFire files in the
   repo (no `firebase_options.dart`, no google-services plugin).

9. **Server could never get an FCM access token.** `google-auth` needs the `requests` package for its token call,
   and `requests` was not in `requirements.txt`: every push failed with "google-auth is not installed". Added.
10. **Wrong server key file.** On Probid's PC `backend/secrets/firebase-service-account.json` was a copy of
   `google-services.json` (the app file, no `private_key`). The server now says so plainly ("FCM server key is
   wrong … Generate new private key") and `push_test` prints it.

11. **Icon (Probid: "icon nahi aata").** Status-bar icon is now the TWV logo cut out of a white circle
   (`drawable-*/ic_stat_notify.png`, made from `assets/brand/icon_foreground.png`; Android draws that icon in one
   colour only), tinted logo blue `#4FB8EF` in the notification (`default_notification_color`). The bell is gone.
12. README "Daily local commands": pull, deps, API / worker / beat, app on Chrome and phone, push_test, checks
   before a push, files that stay on the PC.

## Checked on the phone
2026-10-28 on Probid's moto g54 (Android 15) and in the browser: app logged "device is saved", `push_test` gave
`android: sent` and `web: sent`, and the notification showed on both.

## Not changed
Setup stays D-56 (`app/firebase.json` FB_* keys, `web/firebase-config.js`, `backend/secrets/` server key, GitHub
secret `FIREBASE_JSON`). iPhone push still needs the Apple account. No new screens.

## Checked
`tests/test_push_d80.py` (8 tests: wrong key file, save twice and by another user, short token, dead tokens, project from key file,
no project error, one bad device, `push_test`). `flutter analyze` clean. Web debug run without assertions.
