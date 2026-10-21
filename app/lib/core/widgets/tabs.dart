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
  const SegmentedTabs({super.key, required this.items, required this.value, required this.onChanged, this.expand = false, this.height = 32, this.byLabel = false});
  final List<TabItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;
  final bool expand;

  /// With [expand]: a longer label gets a wider tab ("Times per week" next to "Daily"), as the boards' flex tabs.
  final bool byLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      for (final it in items)
        _wrap(it, Hover(
          onTap: () => onChanged(it.value),
          builder: (context, h, _) {
            final on = it.value == value;
            return Container(
              height: height,
              padding: EdgeInsets.symmetric(horizontal: expand ? 8 : 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.white : (h ? AppColors.white.withValues(alpha: .7) : null),
                borderRadius: AppRadius.all(AppRadius.tab),
                border: on ? Border.all(color: AppColors.line) : null,
                boxShadow: on ? AppShadows.tab : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                // stretched tabs share the width, so a long label shortens instead of overflowing
                if (expand)
                  Flexible(child: Text(it.label, maxLines: 1, style: AppText.s(13, W.w6, color: on ? AppColors.text : AppColors.text2), overflow: TextOverflow.ellipsis))
                else
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

  Widget _wrap(TabItem<T> it, Widget w) => expand ? Expanded(flex: byLabel ? it.label.length + 8 : 1, child: w) : w;
}

/// Underline `.utabs`: 1px line below, gap 20, active dark text + 2px underline. Scrolls sideways when the tabs
/// do not fit (phone); the active tab is scrolled into view, so a tab opened by link is never cut off.
class UnderlineTabs<T> extends StatefulWidget {
  const UnderlineTabs({super.key, required this.items, required this.value, required this.onChanged, this.pillCounts = false, this.gap = 20});
  final List<TabItem<T>> items;

  /// Counts in a grey pill (`.utab .n`, Nutrition & foods) instead of plain grey text.
  final bool pillCounts;
  final double gap;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  State<UnderlineTabs<T>> createState() => _UnderlineTabsState<T>();
}

class _UnderlineTabsState<T> extends State<UnderlineTabs<T>> {
  final _active = GlobalKey();

  @override
  void initState() {
    super.initState();
    _reveal(animate: false);
  }

  @override
  void didUpdateWidget(UnderlineTabs<T> old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _reveal();
  }

  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Centres the active tab in the strip. Only the sideways strip moves (not the page around it).
  void _reveal({bool animate = true}) => WidgetsBinding.instance.addPostFrameCallback((_) => _centre(animate));

  void _centre(bool animate) {
    if (!mounted || !_scroll.hasClients) return;
    final tab = _active.currentContext?.findRenderObject();
    final strip = context.findRenderObject();
    if (tab is! RenderBox || strip is! RenderBox || !tab.hasSize || !strip.hasSize) return;
    final pos = _scroll.position;
    if (pos.maxScrollExtent <= 0) return;
    final left = tab.localToGlobal(Offset.zero, ancestor: strip).dx + pos.pixels;
    final to = (left + tab.size.width / 2 - strip.size.width / 2).clamp(0.0, pos.maxScrollExtent);
    if (animate) {
      _scroll.animateTo(to, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    } else {
      _scroll.jumpTo(to);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: Row(spacing: widget.gap, children: [
            for (final it in widget.items)
              Hover(
                key: it.value == widget.value ? _active : null,
                onTap: () => widget.onChanged(it.value),
                builder: (context, h, _) {
                  final on = it.value == widget.value;
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: on ? AppColors.text : Colors.transparent, width: 2))),
                    child: Row(spacing: 6, children: [
                      Text(it.label, style: AppText.s(13.5, W.w6, color: on || h ? AppColors.text : AppColors.muted)),
                      if (it.count != null && widget.pillCounts)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(9)),
                          child: Text('${it.count}', style: AppText.s(11, W.w7, color: AppColors.muted)),
                        )
                      else if (it.count != null)
                        Text('${it.count}', style: AppText.s(12, W.w6, color: AppColors.muted)),
                    ]),
                  );
                },
              ),
          ]),
        ),
      );
}
