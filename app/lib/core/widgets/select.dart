import 'package:flutter/material.dart';

import '../icons/app_icons.dart';
import '../theme/theme.dart';
import 'hover.dart';
import 'overlays.dart';

/// `.select` 36 high, full width: the value and a chevron; opens the entries as a menu the width of the box
/// (an action sheet on a phone).
class AppSelect extends StatelessWidget {
  const AppSelect(this.value, {super.key, required this.entries, this.icon, this.lead});
  final String value;

  /// Muted word before the value (`.select .lead`, e.g. "Sort").
  final String? lead;
  final List<MenuEntry> entries;

  /// Optional leading icon (the calendar on range pickers).
  final AppIconData? icon;
  @override
  Widget build(BuildContext context) => Builder(
        builder: (b) => Hover(
          onTap: entries.isEmpty ? null : () => showAppMenu(b, entries, width: (b.findRenderObject() as RenderBox).size.width.clamp(180.0, double.infinity), alignRight: false),
          builder: (_, h, _) => Container(
            height: 36,
            padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: AppRadius.all(AppRadius.input),
              border: Border.all(color: h ? AppColors.lineHover : AppColors.line2),
            ),
            child: Row(spacing: 8, children: [
              if (icon != null) AppIcon(icon!, size: 15, color: AppColors.text2),
              if (lead != null) Text(lead!, style: AppText.s(13.5, W.w5, color: AppColors.muted)),
              Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w6))),
              const AppIcon(AppIcons.chevronDown, size: 16, color: AppColors.muted),
            ]),
          ),
        ),
      );
}
