import 'package:flutter/widgets.dart';

/// One set of motion values for the whole app (Phase 5): 200–300 ms, ease-out, and nothing moves when the phone's
/// "Remove animations" / "Reduce motion" is on ([MediaQuery.disableAnimationsOf]).
abstract final class Motion {
  /// Press feedback: quick, so a tap never feels late.
  static const press = Duration(milliseconds: 120);

  /// Menus, dropdowns, field focus, small changes.
  static const short = Duration(milliseconds: 200);

  /// Pages, tabs, sheets, dialogs.
  static const medium = Duration(milliseconds: 250);

  /// Bottom sheets opening (closing uses [short]).
  static const sheet = Duration(milliseconds: 280);

  static const curve = Curves.easeOutCubic;

  /// True when the phone asks for no animations.
  static bool off(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], or zero when animations are off.
  static Duration of(BuildContext context, Duration d) => off(context) ? Duration.zero : d;
}
