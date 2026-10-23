import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/theme.dart';

/// Header labels of the web tables (`.tbl.dt th`): 11.5 bold caps, muted.
TextStyle get tableHeadStyle => AppText.s(11.5, W.w7, color: AppColors.muted, ls: .58);

/// Width of a table column that never cuts its header (Gautam 2026-10-23: "NEXT CHECK-", "ACTIO" were cut).
/// [w] is the column's own width; [pad] is the cell's left + right padding.
double headFit(String label, double w, {double pad = 24}) {
  if (label.isEmpty) return w;
  final tp = TextPainter(text: TextSpan(text: label.toUpperCase(), style: tableHeadStyle), textDirection: TextDirection.ltr, maxLines: 1)..layout();
  final need = (tp.width + pad + 2).ceilToDouble();
  tp.dispose();
  return math.max(w, need);
}
