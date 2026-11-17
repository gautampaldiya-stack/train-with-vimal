import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

const _port = 'twv.live_notice';
const _id = 7101;
const _restId = 7102;

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
  static Future<void> Function()? _again;
  static bool _checking = false;

  /// Like Strong: a swipe on Android 14+ can hide the ongoing notification, so while the workout runs it is put
  /// back (checked every second, so it comes back at once) until the workout is finished or discarded ([clear]).
  static Future<void> keep() async {
    final again = _again;
    if (!_ready || again == null || _checking) return;
    _checking = true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final on = await android?.getActiveNotifications();
      if (on != null && !on.any((n) => n.id == _id) && identical(again, _again)) await again();
    } catch (e) {
      debugPrint('Workout notification check: $e');
    } finally {
      _checking = false;
    }
  }
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
      // the old silent channels (until 17 Nov) are not used any more; a channel's sound cannot change after it is made
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      for (final old in ['workout', 'workout_live']) {
        await android?.deleteNotificationChannel(channelId: old).catchError((_) {});
      }
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
        // own channel, not "Silent": it sits with the normal notifications and shows its actions like Strong's
        // (Probid 17 Nov). Like Strong it plays the phone's notification sound once when it is shown (start, or back
        // after a swipe); the every-second updates stay quiet (onlyAlertOnce).
        'workout_sound',
        'Workout in progress',
        channelDescription: 'The workout clock, your set and rest while you train',
        icon: 'ic_stat_notify',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: false,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
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
    _again = () => _plugin.show(id: _id, title: title, body: body, notificationDetails: NotificationDetails(android: d), payload: '/train/workout');
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

  static DateTime? _restAt;

  /// "Rest is over · Next: Squat" at the rest's end time (tracker G48/G50). Scheduled with the system, so it rings
  /// with the app in the background or the phone locked. Its channel plays the sound / vibrates as the client set in
  /// My account (one channel per choice: a channel's sound cannot change after it is made); the phone's silent and
  /// do-not-disturb modes are kept by Android itself.
  static Future<void> restDone({required DateTime at, required String next, bool sound = true, bool vibrate = true}) async {
    if (!_ready) return;
    if (_restAt != null && (_restAt!.difference(at).inSeconds).abs() < 1) return;
    _restAt = at;
    final ch = 'rest_done_${sound ? 's' : 'q'}${vibrate ? 'v' : 'n'}';
    final d = NotificationDetails(
      android: AndroidNotificationDetails(
        ch,
        sound ? (vibrate ? 'Rest is over' : 'Rest is over (sound only)') : (vibrate ? 'Rest is over (vibrate only)' : 'Rest is over (silent)'),
        channelDescription: 'Tells you when your rest between sets is over',
        icon: 'ic_stat_notify',
        importance: Importance.high,
        priority: Priority.high,
        playSound: sound,
        enableVibration: vibrate,
        silent: !sound && !vibrate,
        autoCancel: true,
        timeoutAfter: 60 * 1000,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
      ),
    );
    final when = tz.TZDateTime.from(at, tz.UTC);
    try {
      await _plugin.cancel(id: _restId);
      try {
        await _plugin.zonedSchedule(
            id: _restId, title: 'Rest is over', body: 'Next: $next', scheduledDate: when, notificationDetails: d,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, payload: '/train/workout');
      } on PlatformException catch (_) {
        // exact alarms not allowed on this phone: a few seconds late is fine
        await _plugin.zonedSchedule(
            id: _restId, title: 'Rest is over', body: 'Next: $next', scheduledDate: when, notificationDetails: d,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, payload: '/train/workout');
      }
    } catch (e) {
      debugPrint('Rest notification: $e');
    }
  }

  static Future<void> cancelRestDone() async {
    if (_restAt == null) return;
    _restAt = null;
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _restId);
    } catch (_) {}
  }

  static Future<void> clear() async {
    _last = null;
    _again = null;
    await cancelRestDone();
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _id);
    } catch (_) {}
  }
}
