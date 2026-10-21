# D-41 · Web login side panel 40 / 60, and testing on a real phone

Date: 2026-10-21

## Decision
- **Side panel width** on the web auth pages (Log in, Forgot password, Reset, Join, Login link, Verify email,
  Permissions, Setup, Approval wait): **40 % of the window** (at least 360), the page gets the other 60 %. Before it
  was 40 % but never more than 520, so on big screens the panel looked narrow. Same form, same place in its 60 %.
- **Panel colour**: a stronger light blue (`AppColors.brandPanel`) that **fades into the page colour on every side**
  (48 px left, 72 px top and bottom, 160 px on the right towards the form), so there is no hard edge. This changes the
  ClientLoginWeb board's flat `brandSoft` panel on Gautam's request.
- **Help sheets open at once**: "Need help?" (Help in the footer, the blue Help on the phone log in, "Need help
  logging in?") and the support sheet on the account pages no longer wait for `gym/`; the number and email load
  while the sheet is open (at most 4 s). A slow or unreachable server made the sheet appear only after the request
  gave up.
- **Real phone testing**: `10.0.2.2` is only for the Android emulator. A phone on the same wifi uses the laptop's IP
  (`--dart-define=API_URL=http://<laptop-ip>:8000`), the API must listen on `0.0.0.0`, Windows Firewall must allow
  port 8000 on Private networks. Dev settings accept any host (`ALLOW_ANY_HOST`, default on in `config.settings.dev`).
  Debug and profile Android builds allow plain http (`usesCleartextTraffic`); release builds do not. Steps in README.
- **Android compileSdk 37**: `permission_handler_android` 14 needs it. `compileSdk = maxOf(flutter.compileSdkVersion, 37)`;
  `android.suppressUnsupportedCompileSdk=37` hides AGP 9.1's "newest tested is 36" warning. targetSdk / minSdk unchanged.

## Why
Gautam (2026-10-21): the Android build failed on `checkDebugAarMetadata`; the app on his moto g54 showed "offline"
and could not log in; he wanted the web login split 40 / 60 with the blue panel showing and fading on all sides; the
Help sheet opened late.
