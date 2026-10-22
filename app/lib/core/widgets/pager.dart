import 'package:flutter/material.dart';

import '../icons/app_icons.dart';
import '../theme/theme.dart';
import 'hover.dart';

/// `.pager`: "Showing 1–8 of 24" left, page buttons right (28 high, radius 7; current one white with a line).
/// Long lists show the first, last and the pages around the current one with "…" between.
class Pager extends StatelessWidget {
  const Pager({super.key, required this.page, required this.pageSize, required this.count, required this.onPage, this.empty = 'No clients'});
  final int page, pageSize, count;

  /// Left text when there is nothing to show.
  final String empty;
  final ValueChanged<int> onPage;

  int get pages => count == 0 ? 1 : (count + pageSize - 1) ~/ pageSize;

  @override
  Widget build(BuildContext context) {
    final from = count == 0 ? 0 : (page - 1) * pageSize + 1;
    final to = (page * pageSize).clamp(0, count);
    final nums = <int?>[];
    for (var p = 1; p <= pages; p++) {
      if (p == 1 || p == pages || (p - page).abs() <= 1) {
        nums.add(p);
      } else if (nums.isNotEmpty && nums.last != null) {
        nums.add(null);
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(children: [
        Expanded(child: Text(count == 0 ? empty : 'Showing $from–$to of $count', style: AppText.s(12.5, W.w6, color: AppColors.muted))),
        if (pages > 1)
          Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
            _Pg(icon: AppIcons.chevronLeft, label: 'Previous page', onTap: page > 1 ? () => onPage(page - 1) : null),
            for (final p in nums)
              p == null
                  ? SizedBox(width: 20, child: Text('…', textAlign: TextAlign.center, style: AppText.s(12.5, W.w6, color: AppColors.muted)))
                  : _Pg(text: '$p', on: p == page, onTap: p == page ? null : () => onPage(p)),
            _Pg(icon: AppIcons.chevronRight, label: 'Next page', onTap: page < pages ? () => onPage(page + 1) : null),
          ]),
      ]),
    );
  }
}

class _Pg extends StatelessWidget {
  const _Pg({this.text, this.icon, this.label, this.on = false, this.onTap});
  final String? text, label;
  final AppIconData? icon;
  final bool on;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final off = onTap == null && !on;
    return Semantics(
      button: true,
      label: label ?? 'Page $text',
      child: Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          constraints: const BoxConstraints(minWidth: 28),
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.card : (h && !off ? AppColors.sub : null),
            borderRadius: AppRadius.all(7),
            border: Border.all(color: on ? AppColors.line2 : Colors.transparent),
          ),
          child: icon != null
              ? AppIcon(icon!, size: 14, color: off ? AppColors.line2 : AppColors.text2)
              : Text(text!, style: AppText.s(12.5, on ? W.w7 : W.w6, color: on || h ? AppColors.text : AppColors.text2)),
        ),
      ),
    );
  }
}
