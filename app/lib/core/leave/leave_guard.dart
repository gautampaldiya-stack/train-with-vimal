import 'dart:async';

import 'package:flutter/widgets.dart';

import 'tab_close.dart';

/// Unsaved work on a page (program builder, exercise form). The page that owns it registers [check]; the router
/// asks it before the page closes (sidebar, bottom tabs, links, back), and on web the browser warns before the tab
/// closes or reloads while [unsaved] is true (D-43).
class LeaveGuard {
  LeaveGuard._();

  static Object? _owner;
  static Future<bool> Function(BuildContext context)? _check;

  /// [check] returns true when the page may close (saved, discarded or nothing changed).
  static void register(Object owner, Future<bool> Function(BuildContext context) check) {
    _owner = owner;
    _check = check;
  }

  static void unregister(Object owner) {
    if (_owner != owner) return;
    _owner = null;
    _check = null;
    warnOnTabClose(false);
  }

  /// Keeps the browser's "Leave site?" warning in step with the page.
  static void unsaved(bool v) => warnOnTabClose(v);

  /// Called by the router before a guarded page closes.
  static FutureOr<bool> ask(BuildContext context) {
    final c = _check;
    return c == null ? true : c(context);
  }
}
