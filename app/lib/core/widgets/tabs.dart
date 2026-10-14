import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'hover.dart';

class TabItem<T> {
  const TabItem(this.value, this.label, {this.count});
  final T value;
  final String label;
  final int? count;
}

/// Segmented `.tabs`: sub bg, padding 4, tab 32 high radius 6, active white + line ring.
class SegmentedTabs<T> extends StatelessWidget {
  const SegmentedTabs({super.key, required this.items, required this.value, required this.onChanged, this.expand = false, this.height = 32});
  final List<TabItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      for (final it in items)
        _wrap(Hover(
          onTap: () => onChanged(it.value),
          builder: (context, h, _) {
            final on = it.value == value;
            return Container(
              height: height,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.white : (h ? AppColors.white.withValues(alpha: .7) : null),
                borderRadius: AppRadius.all(AppRadius.tab),
                border: on ? Border.all(color: AppColors.line) : null,
                boxShadow: on ? AppShadows.tab : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                Text(it.label, style: AppText.s(13, W.w6, color: on ? AppColors.text : AppColors.text2), overflow: TextOverflow.ellipsis),
                if (it.count != null) Text('${it.count}', style: AppText.s(12, W.w6, color: AppColors.muted)),
              ]),
            );
          },
        )),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(AppRadius.btn)),
      child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, spacing: 2, children: tabs),
    );
  }

  Widget _wrap(Widget w) => expand ? Expanded(child: w) : w;
}

/// Underline `.utabs`: 1px line below, gap 20, active dark text + 2px underline.
class UnderlineTabs<T> extends StatelessWidget {
  const UnderlineTabs({super.key, required this.items, required this.value, required this.onChanged});
  final List<TabItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(spacing: 20, children: [
            for (final it in items)
              Hover(
                onTap: () => onChanged(it.value),
                builder: (context, h, _) {
                  final on = it.value == value;
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: on ? AppColors.text : Colors.transparent, width: 2))),
                    child: Row(spacing: 6, children: [
                      Text(it.label, style: AppText.s(13.5, W.w6, color: on || h ? AppColors.text : AppColors.muted)),
                      if (it.count != null) Text('${it.count}', style: AppText.s(12, W.w6, color: AppColors.muted)),
                    ]),
                  );
                },
              ),
          ]),
        ),
      );
}
