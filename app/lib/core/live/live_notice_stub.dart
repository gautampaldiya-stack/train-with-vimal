/// Web: browsers have no ongoing notification, so the workout notification does nothing here.
class LiveNotice {
  LiveNotice._();

  /// A button on the notification: `complete_set`, `rest_pause`, `rest_skip`, `rest_add`.
  static void Function(String action)? onAction;

  /// The notification itself was tapped: open the logger.
  static void Function()? onOpen;

  static Future<void> init() async {}

  static Future<void> workout({required String title, required String body, required DateTime startedAt, bool paused = false, List<String> actions = const []}) async {}

  static Future<void> rest({required String title, required String body, required DateTime endsAt, required int total, required int left, bool paused = false}) async {}

  /// "Rest is over" at [at] (tracker G48). Web: the open page shows a toast instead.
  static Future<void> restDone({required DateTime at, required String next, bool sound = true, bool vibrate = true}) async {}

  static Future<void> cancelRestDone() async {}

  static Future<void> keep() async {}

  static Future<void> clear() async {}
}
