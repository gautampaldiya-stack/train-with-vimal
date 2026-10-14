import 'package:flutter/material.dart';

import 'colors.dart';
import 'text.dart';

export 'colors.dart';
export 'metrics.dart';
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
    scrollbarTheme: const ScrollbarThemeData(thickness: WidgetStatePropertyAll(6)),
  );
}
