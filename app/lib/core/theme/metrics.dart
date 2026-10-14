import 'package:flutter/painting.dart';

/// Radius, spacing and shadows from docs/design.md §1.3–1.4.
abstract final class AppRadius {
  static const badge = 6.0, tab = 6.0, chip = 8.0, input = 8.0, btn = 8.0, item = 8.0;
  static const menu = 12.0, card = 12.0, modal = 16.0;
  // Client app
  static const caCard = 14.0, caBtn = 12.0, caBtnSm = 10.0, caSheet = 20.0, toast = 14.0, caChip = 7.0;
  static BorderRadius all(double r) => BorderRadius.circular(r);
}

abstract final class AppShadows {
  static const menu = [
    BoxShadow(color: Color(0x0F171717), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x1A171717), offset: Offset(0, 8), blurRadius: 24),
  ];
  static const panel = [
    BoxShadow(color: Color(0x0A171717), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x0A171717), offset: Offset(0, 4), blurRadius: 16),
  ];
  static const modal = [
    BoxShadow(color: Color(0x14171717), offset: Offset(0, 2), blurRadius: 6),
    BoxShadow(color: Color(0x38171717), offset: Offset(0, 24), blurRadius: 60),
  ];
  static const toast = [BoxShadow(color: Color(0x47000000), offset: Offset(0, 12), blurRadius: 28)];
  static const tab = [BoxShadow(color: Color(0x0F171717), offset: Offset(0, 1), blurRadius: 2)];
}

/// Screen widths: phone < 600, tablet 600–1023, desktop >= 1024.
abstract final class Breakpoints {
  static const tablet = 600.0;
  static const desktop = 1024.0;
  static const contentMax = 1200.0;
}
