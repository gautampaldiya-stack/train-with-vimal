/// Web: browsers have no ongoing notification, so the workout notification does nothing here.
class LiveNotice {
  LiveNotice._();

  /// A button on the notification: `complete_set`, `rest_pause`, `rest_skip`, `rest_add`.
  static void Function(String action)? onAction;

  /// The notification itself was tapped: open the logger.
  static void Function()? onOpen;

  static Future<void> init() async {}

  static Future<void> workout({required String title, required String body, required DateTime startedAt, bool paused = false, bool canComplete = true}) async {}

  static Future<void> rest({required String title, required String body, required DateTime endsAt, required int total, required int left, bool paused = false}) async {}

  static Future<void> clear() async {}
}
