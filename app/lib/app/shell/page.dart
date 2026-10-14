import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/widgets/responsive.dart';

/// A staff page inside the panel: padding `24px 32px 48px`, content max 1200, sections 20 apart.
/// Phone: padding `6px 16px 24px`, gap 14.
class StaffPage extends StatelessWidget {
  const StaffPage({super.key, required this.children, this.header, this.maxWidth = Breakpoints.contentMax, this.onRefresh, this.controller});
  final Widget? header;
  final List<Widget> children;
  final double maxWidth;
  final Future<void> Function()? onRefresh;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final list = SingleChildScrollView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: phone ? const EdgeInsets.fromLTRB(16, 6, 16, 24) : const EdgeInsets.fromLTRB(32, 24, 32, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 14 : 20, children: [?header, ...children]),
        ),
      ),
    );
    return onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, color: AppColors.accent, child: list);
  }
}

/// `.top` page header: title + subtitle left, actions right. Narrow widths make outline buttons icon-only (§3.8).
class PageTop extends StatelessWidget {
  const PageTop({super.key, required this.title, this.sub, this.actions = const [], this.back});
  final String title;
  final String? sub;
  final List<Widget> actions;
  final Widget? back;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        final size = w <= 480 ? 17.0 : (w * 0.026).clamp(20.0, 28.0);
        return Row(crossAxisAlignment: CrossAxisAlignment.center, spacing: 16, children: [
          ?back,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
              Text(title, style: AppText.h1.copyWith(fontSize: size), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (sub != null) Text(sub!, style: AppText.sub.copyWith(fontSize: w <= 480 ? 12 : 13), maxLines: w <= 480 ? 2 : 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (actions.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: actions),
        ]);
      });
}

/// Width of the page content area, for buttons that turn icon-only (≤ 760) and phone layouts.
bool compactTop(BuildContext context) => MediaQuery.sizeOf(context).width - (context.isDesktop ? 240 : 68) < 760 || context.isPhone;
