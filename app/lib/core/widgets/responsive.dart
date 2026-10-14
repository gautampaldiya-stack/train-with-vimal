import 'package:flutter/widgets.dart';

import '../theme/metrics.dart';

enum ScreenSize { phone, tablet, desktop }

extension ResponsiveX on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  ScreenSize get screen {
    final w = screenWidth;
    if (w >= Breakpoints.desktop) return ScreenSize.desktop;
    if (w >= Breakpoints.tablet) return ScreenSize.tablet;
    return ScreenSize.phone;
  }

  bool get isPhone => screen == ScreenSize.phone;
  bool get isDesktop => screen == ScreenSize.desktop;
  bool get isWide => !isPhone;
}

/// Picks a child by width of the *available* space (container query), like the canvas `cqi` rules.
class WidthSwitch extends StatelessWidget {
  const WidthSwitch({super.key, required this.builder});
  final Widget Function(BuildContext context, double width) builder;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (c, b) => builder(c, b.maxWidth));
}
