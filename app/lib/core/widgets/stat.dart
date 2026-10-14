import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import '../theme/theme.dart';
import 'card.dart';
import 'hover.dart';

/// `.stat`: label with 26px icon tile, then number 24/800 with the delta beside it.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.icon, required this.label, required this.value, this.delta, this.deltaUp, this.note});
  final AppIconData icon;
  final String label, value;
  final String? delta, note;
  final bool? deltaUp;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
          Row(spacing: 8, children: [IconTile(icon), Flexible(child: Text(label, style: AppText.s(12.5, W.w6, color: AppColors.muted), overflow: TextOverflow.ellipsis))]),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 8, children: [
            Text(value, style: AppText.stat),
            if (delta != null)
              Flexible(
                child: Text(delta!,
                    style: AppText.s(12, W.w7, color: deltaUp == null ? AppColors.muted : (deltaUp! ? AppColors.okText : AppColors.badText)), overflow: TextOverflow.ellipsis),
              ),
            if (note != null) Flexible(child: Text(note!, style: AppText.s(12.5, W.w6, color: AppColors.text2), overflow: TextOverflow.ellipsis)),
          ]),
        ]),
      );
}

/// `.glance` tile: 28px icon tile, number 18/800, label, sub-line; whole tile is a link.
class GlanceTile extends StatelessWidget {
  const GlanceTile({super.key, required this.icon, required this.value, required this.label, this.sub, this.warn = false, this.onTap});
  final AppIconData icon;
  final String value, label;
  final String? sub;
  final bool warn;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (context, h, _) => Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          decoration: BoxDecoration(
            color: h ? AppColors.hover : AppColors.card,
            borderRadius: AppRadius.all(AppRadius.card),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
            IconTile(icon, size: 28, bg: warn ? AppColors.warnBg : AppColors.sub, fg: warn ? AppColors.warnText : AppColors.text2),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text(value, style: AppText.s(18, W.w8, tabular: true, h: 1.1)),
                Text(label, style: AppText.s(12.5, W.w7), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (sub != null) Text(sub!, style: AppText.s(11.5, W.w5, color: warn ? AppColors.warnText : AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: h ? AppColors.accent : AppColors.line2),
          ]),
        ),
      );
}
