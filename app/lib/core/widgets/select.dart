import 'package:flutter/material.dart';

import '../icons/app_icons.dart';
import '../theme/theme.dart';
import 'hover.dart';
import 'overlays.dart';

/// `.select` 36 high, full width: the value and a chevron; opens the entries as a menu the width of the box
/// (an action sheet on a phone).
class AppSelect extends StatelessWidget {
  const AppSelect(this.value, {super.key, required this.entries});
  final String value;
  final List<MenuEntry> entries;
  @override
  Widget build(BuildContext context) => Builder(
        builder: (b) => Hover(
          onTap: entries.isEmpty ? null : () => showAppMenu(b, entries, width: (b.findRenderObject() as RenderBox).size.width, alignRight: false),
          builder: (_, h, _) => Container(
            height: 36,
            padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: AppRadius.all(AppRadius.input),
              border: Border.all(color: h ? AppColors.lineHover : AppColors.line2),
            ),
            child: Row(spacing: 8, children: [
              Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w6))),
              const AppIcon(AppIcons.chevronDown, size: 16, color: AppColors.muted),
            ]),
          ),
        ),
      );
}
