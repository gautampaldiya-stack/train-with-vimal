import 'package:flutter/material.dart';

import 'colors.dart';
import 'text.dart';

export 'colors.dart';
export 'metrics.dart';
export 'motion.dart';
export 'text.dart';

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.accent, primary: AppColors.accent, surface: AppColors.card);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: AppText.family,
    scaffoldBackgroundColor: AppColors.bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: AppColors.hover,
    dividerColor: AppColors.line,
    textTheme: const TextTheme(bodyMedium: AppText.body),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: AppColors.accent, selectionColor: AppColors.accentSoft),
    // One thin rounded thumb in the list's own right gutter, no grey track, never over the rows' buttons
    // (Probid 2026-11-03). Lists that scroll inside a card leave 12 on the right for it.
    scrollbarTheme: const ScrollbarThemeData(
      thickness: WidgetStatePropertyAll(4),
      radius: Radius.circular(99),
      thumbColor: WidgetStatePropertyAll(AppColors.lineHover),
      trackVisibility: WidgetStatePropertyAll(false),
      crossAxisMargin: 3,
      mainAxisMargin: 6,
    ),
  );
}
