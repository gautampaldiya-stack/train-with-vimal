import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import 'sw_routes_stub.dart' if (dart.library.js_interop) 'sw_routes_web.dart';

// The server sends to FCM registration tokens (HTTP v1 `token`), so this keeps getToken /
// onTokenRefresh / deleteToken; the new register() hands out installation ids instead.
// ignore_for_file: deprecated_member_use

/// Phone / browser push through Firebase Cloud Messaging (D-56).
///
/// The Firebase keys come from `app/firebase.json` (not in git), passed with
/// `--dart-define-from-file=firebase.json`. Without them push is simply off and the app works
/// as before (in-app + realtime). The server sends the pushes (`PUSH_PROVIDER=fcm`).
class Push {
  Push(this._api);
  final Api _api;

  static const _projectId = String.fromEnvironment('FB_PROJECT_ID');
  static const _senderId = String.fromEnvironment('FB_SENDER_ID');
  static const _vapidKey = String.fromEnvironment('FB_VAPID_KEY');

  /// Opens a notification's page (`data.route`) when it is tapped; set in main().
  void Function(String route)? onOpen;

  String? _token;
  Future<void>? _setup;
  bool _toldOff = false;
  final _subs = <StreamSubscription>[];

  static FirebaseOptions? get _options {
    if (_projectId.isEmpty || _senderId.isEmpty) return null;
    final (apiKey, appId) = kIsWeb
        ? (const String.fromEnvironment('FB_WEB_API_KEY'), const String.fromEnvironment('FB_WEB_APP_ID'))
        : switch (defaultTargetPlatform) {
            TargetPlatform.android =>
              (const String.fromEnvironment('FB_ANDROID_API_KEY'), const String.fromEnvironment('FB_ANDROID_APP_ID')),
            TargetPlatform.iOS => (const String.fromEnvironment('FB_IOS_API_KEY'), const String.fromEnvironment('FB_IOS_APP_ID')),
            _ => ('', ''),
          };
    if (apiKey.isEmpty || appId.isEmpty) return null;
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: _senderId,
      projectId: _projectId,
      authDomain: kIsWeb ? const String.fromEnvironment('FB_AUTH_DOMAIN') : null,
      storageBucket: const String.fromEnvironment('FB_STORAGE_BUCKET'),
      iosBundleId: defaultTargetPlatform == TargetPlatform.iOS ? 'com.trainwithvimal.app' : null,
    );
  }

  static bool get configured => _options != null && (!kIsWeb || _vapidKey.isNotEmpty);

  /// After sign in (also while the account waits for approval) and again when the person taps "Allow
  /// notifications": ask permission, save this device for the account that is logged in now (D-80).
  Future<void> start(String platform) async {
    if (!configured) {
      if (!_toldOff) {
        _toldOff = true;
        debugPrint('Push off: this build has no Firebase keys. Run with --dart-define-from-file=firebase.json '
            '(app/firebase.json with the FB_* keys from firebase.example.json, not the file flutterfire makes).');
      }
      return;
    }
    try {
      // Once per app run, also when start() comes twice at the same time (sign in + Allow button).
      await (_setup ??= _init(platform));
      final perm = await FirebaseMessaging.instance.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('Push: notifications are blocked for this app / site');
        return;
      }
      final t = await _token0();
      if (t != null) await _register(t, platform);
    } catch (e) {
      debugPrint('Push not started: $e${kIsWeb ? ' · $_webHelp' : ''}');
    }
  }

  Future<void> _init(String platform) async {
    try {
      await Firebase.initializeApp(options: _options);
    } catch (e) {
      _setup = null; // try again on the next start()
      rethrow;
    }
    _subs.add(FirebaseMessaging.onMessageOpenedApp.listen(_open));
    if (kIsWeb) listenSwRoutes((r) => onOpen?.call(r));
    _subs.add(FirebaseMessaging.instance.onTokenRefresh.listen((t) => _register(t, platform)));
    final first = await FirebaseMessaging.instance.getInitialMessage();
    if (first != null) _open(first);
  }

  // "AbortError: Registration failed - push service error" is the browser's push service saying no: Brave with
  // "Use Google services for push messaging" off, a browser without Google's push service, or a subscription left
  // from another VAPID key / Firebase project. The last one is fixed here: drop the old subscription, ask again.
  static const _webHelp = 'check FB_VAPID_KEY = Firebase → Cloud Messaging → Web Push certificates key pair; '
      'Brave: Settings → Privacy → "Use Google services for push messaging"';

  Future<String?> _token0() async {
    final m = FirebaseMessaging.instance;
    try {
      return await m.getToken(vapidKey: kIsWeb ? _vapidKey : null);
    } catch (e) {
      if (!kIsWeb) rethrow;
      debugPrint('Push: first try failed ($e), clearing the old subscription and trying again');
      try {
        await m.deleteToken();
      } catch (_) {}
      return m.getToken(vapidKey: _vapidKey);
    }
  }

  Future<void> _register(String token, String platform) async {
    _token = token;
    try {
      await _api.post('devices/', {'token': token, 'platform': platform});
      debugPrint('Push: this $platform device is saved for the logged-in account');
    } catch (e) {
      debugPrint('Push token not saved: $e');
    }
  }

  void _open(RemoteMessage m) {
    final route = '${m.data['route'] ?? ''}';
    if (route.startsWith('/')) onOpen?.call(route);
  }

  /// Before log out (the API call still has the access token): this device gets no more pushes.
  Future<void> stop() async {
    final t = _token;
    _token = null;
    if (t == null) return;
    // Firebase's deleteToken can hang on web after a failed registration: it runs on its own, never awaited.
    unawaited(FirebaseMessaging.instance.deleteToken().catchError((_) {}));
    try {
      await _api.delete('devices/', {'token': t});
    } catch (_) {}
  }
}
