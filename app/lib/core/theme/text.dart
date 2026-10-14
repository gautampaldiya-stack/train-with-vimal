import 'package:flutter/painting.dart';

import 'colors.dart';

/// Type scale from docs/design.md §1.2. Font: Plus Jakarta Sans (bundled, 400–800).
abstract final class AppText {
  static const family = 'PlusJakartaSans';
  static const _tab = [FontFeature.tabularFigures()];

  static const h1 = TextStyle(fontFamily: family, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.7, color: AppColors.text, height: 1.15);
  static const h2 = TextStyle(fontFamily: family, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: AppColors.text, height: 1.25);
  static const h3 = TextStyle(fontFamily: family, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.15, color: AppColors.text, height: 1.3);
  static const sub = TextStyle(fontFamily: family, fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.muted, height: 1.4);
  static const cap = TextStyle(fontFamily: family, fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.muted, height: 1.4);
  static const over = TextStyle(fontFamily: family, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.88, color: AppColors.muted);
  static const body = TextStyle(fontFamily: family, fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text, height: 1.45);
  static const rowTitle = TextStyle(fontFamily: family, fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.3);
  static const rowSub = TextStyle(fontFamily: family, fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.muted, height: 1.35);
  static const stat = TextStyle(fontFamily: family, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.48, color: AppColors.text, fontFeatures: _tab, height: 1.1);
  static const label = TextStyle(fontFamily: family, fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.text2);
  static const button = TextStyle(fontFamily: family, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1);
  static const num = TextStyle(fontFamily: family, fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.text, fontFeatures: _tab);

  static TextStyle s(double size, FontWeight w, {Color color = AppColors.text, double? ls, double? h, bool tabular = false}) =>
      TextStyle(fontFamily: family, fontSize: size, fontWeight: w, color: color, letterSpacing: ls, height: h, fontFeatures: tabular ? _tab : null);
}

abstract final class W {
  static const w4 = FontWeight.w400, w5 = FontWeight.w500, w6 = FontWeight.w600, w7 = FontWeight.w700, w8 = FontWeight.w800;
}
