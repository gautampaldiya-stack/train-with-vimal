import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';

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
  bool _ready = false;
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

  /// After sign in (approved accounts): ask permission once, register this device with the API.
  Future<void> start(String platform) async {
    if (!configured) return;
    try {
      if (!_ready) {
        await Firebase.initializeApp(options: _options);
        _ready = true;
        _subs.add(FirebaseMessaging.onMessageOpenedApp.listen(_open));
        _subs.add(FirebaseMessaging.instance.onTokenRefresh.listen((t) => _register(t, platform)));
        final first = await FirebaseMessaging.instance.getInitialMessage();
        if (first != null) _open(first);
      }
      final perm = await FirebaseMessaging.instance.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      final t = await FirebaseMessaging.instance.getToken(vapidKey: kIsWeb ? _vapidKey : null);
      if (t != null) await _register(t, platform);
    } catch (e) {
      debugPrint('Push not started: $e');
    }
  }

  Future<void> _register(String token, String platform) async {
    _token = token;
    try {
      await _api.post('devices/', {'token': token, 'platform': platform});
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
    try {
      await _api.delete('devices/', {'token': t});
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
