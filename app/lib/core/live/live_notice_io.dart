import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const _port = 'twv.live_notice';
const _id = 7101;

/// A button tapped while the app sleeps runs here, in a small background isolate: it hands the button to the app's
/// main isolate, which owns the workout. If the app was closed the press is dropped (the workout is still saved).
@pragma('vm:entry-point')
void liveNoticeBackground(NotificationResponse r) {
  final id = r.actionId;
  if (id != null) IsolateNameServer.lookupPortByName(_port)?.send(id);
}

/// Android ongoing notification for the running workout (tracker F34). The clock runs in the notification itself
/// (`usesChronometer`), so it is updated only when the exercise, the set or the rest changes, not every second.
class LiveNotice {
  LiveNotice._();

  /// A button on the notification: `complete_set`, `rest_pause`, `rest_skip`, `rest_add`.
  static void Function(String action)? onAction;

  /// The notification itself was tapped: open the logger.
  static void Function()? onOpen;

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static String? _last;
  static ReceivePort? _rx;

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> init() async {
    if (!_android || _ready) return;
    try {
      _rx?.close();
      _rx = ReceivePort();
      IsolateNameServer.removePortNameMapping(_port);
      IsolateNameServer.registerPortWithName(_rx!.sendPort, _port);
      _rx!.listen((m) {
        if (m is String) onAction?.call(m);
      });
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_notify')),
        onDidReceiveNotificationResponse: (r) {
          final a = r.actionId;
          if (a == null || a.isEmpty) {
            onOpen?.call();
          } else {
            onAction?.call(a);
          }
        },
        onDidReceiveBackgroundNotificationResponse: liveNoticeBackground,
      );
      _ready = true;
    } catch (e) {
      debugPrint('Workout notification is off: $e');
    }
  }

  static AndroidNotificationDetails _details({
    required DateTime when,
    bool countDown = false,
    bool chrono = true,
    int? max,
    int? progress,
    List<AndroidNotificationAction> actions = const [],
  }) =>
      AndroidNotificationDetails(
        'workout',
        'Workout in progress',
        channelDescription: 'The workout clock, your set and rest while you train',
        icon: 'ic_stat_notify',
        importance: Importance.low, // no sound or pop-up: it only sits in the shade
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        silent: true,
        showWhen: true,
        when: when.millisecondsSinceEpoch,
        usesChronometer: chrono,
        chronometerCountDown: countDown,
        showProgress: max != null,
        maxProgress: max ?? 0,
        progress: progress ?? 0,
        category: AndroidNotificationCategory.workout,
        visibility: NotificationVisibility.public,
        actions: actions,
      );

  static Future<void> _show(String key, String title, String body, AndroidNotificationDetails d) async {
    if (!_ready || key == _last) return;
    _last = key;
    try {
      await _plugin.show(id: _id, title: title, body: body, notificationDetails: NotificationDetails(android: d), payload: '/train/workout');
    } catch (e) {
      debugPrint('Workout notification: $e');
    }
  }

  /// Between sets: "Squat · 60 kg × 5 (2 of 5)" with the workout clock and Complete set.
  static Future<void> workout({required String title, required String body, required DateTime startedAt, bool paused = false, bool canComplete = true}) => _show(
        'w|$title|$body|${startedAt.millisecondsSinceEpoch}|$paused|$canComplete',
        title,
        body,
        _details(
          when: startedAt,
          chrono: !paused,
          actions: [
            if (canComplete) const AndroidNotificationAction('complete_set', 'Complete set', cancelNotification: false),
          ],
        ),
      );

  /// Resting: "Next: Overhead press" with a bar, the count down and Pause / Skip rest timer / +30 sec.
  static Future<void> rest({required String title, required String body, required DateTime endsAt, required int total, required int left, bool paused = false}) => _show(
        'r|$title|$body|${endsAt.millisecondsSinceEpoch ~/ 1000}|$total|$paused|${left ~/ 5}',
        title,
        body,
        _details(
          when: endsAt,
          countDown: true,
          chrono: !paused,
          max: total,
          progress: total - left,
          actions: [
            AndroidNotificationAction('rest_pause', paused ? 'Resume' : 'Pause', cancelNotification: false),
            const AndroidNotificationAction('rest_skip', 'Skip rest timer', cancelNotification: false),
            const AndroidNotificationAction('rest_add', '+30 sec', cancelNotification: false),
          ],
        ),
      );

  static Future<void> clear() async {
    _last = null;
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _id);
    } catch (_) {}
  }
}
