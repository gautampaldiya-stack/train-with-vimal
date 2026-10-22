import 'package:flutter/painting.dart';

import 'colors.dart';

/// Type scale from docs/design.md §1.2. Font: Plus Jakarta Sans (bundled, 400–800).
/// Text without its own line height uses [normal], the browser's `line-height: normal` for this
/// font (hhea 1038 + 222 per 1000). Without it Flutter adds the font's Windows descent and every
/// line comes out about 10% taller than on the boards.
abstract final class AppText {
  static const normal = 1.26;
  static const family = 'PlusJakartaSans';
  static const _tab = [FontFeature.tabularFigures()];

  static const h1 = TextStyle(fontFamily: family, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.7, color: AppColors.text, height: 1.15);
  static const h2 = TextStyle(fontFamily: family, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: AppColors.text, height: 1.25);
  static const h3 = TextStyle(fontFamily: family, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.15, color: AppColors.text, height: 1.3);
  static const sub = TextStyle(fontFamily: family, fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.muted, height: 1.4);
  static const cap = TextStyle(fontFamily: family, fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.muted, height: 1.4);
  static const over = TextStyle(fontFamily: family, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.88, color: AppColors.muted, height: normal);
  static const body = TextStyle(fontFamily: family, fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text, height: 1.45);
  static const rowTitle = TextStyle(fontFamily: family, fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.3);
  static const rowSub = TextStyle(fontFamily: family, fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.muted, height: 1.35);
  static const stat = TextStyle(fontFamily: family, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.48, color: AppColors.text, fontFeatures: _tab, height: 1.1);
  static const label = TextStyle(fontFamily: family, fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.text2, height: normal);
  static const button = TextStyle(fontFamily: family, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1);
  static const num = TextStyle(fontFamily: family, fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.text, fontFeatures: _tab, height: normal);

  static TextStyle s(double size, FontWeight w, {Color color = AppColors.text, double? ls, double? h, bool tabular = false}) =>
      TextStyle(fontFamily: family, fontSize: size, fontWeight: w, color: color, letterSpacing: ls, height: h ?? normal, fontFeatures: tabular ? _tab : null);

  /// Code-looking text (`ui-monospace`): the {{variable}} chips in Emails & alerts.
  static TextStyle mono(double size, {Color color = AppColors.text, FontWeight w = FontWeight.w500}) =>
      TextStyle(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'], fontSize: size, fontWeight: w, color: color, height: normal);
}

abstract final class W {
  static const w4 = FontWeight.w400, w5 = FontWeight.w500, w6 = FontWeight.w600, w7 = FontWeight.w700, w8 = FontWeight.w800;
}
