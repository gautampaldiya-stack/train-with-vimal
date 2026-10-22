import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import '../theme/theme.dart';
import 'hover.dart';
import 'tooltip.dart';

/// `.card`: white, 1px line, radius 12. [padded] = `18px 20px`.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padded = false, this.padding, this.color, this.radius});
  final Widget child;
  final bool padded;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final double? radius;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding ?? (padded ? const EdgeInsets.fromLTRB(20, 18, 20, 18) : null),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: color ?? AppColors.card,
          borderRadius: AppRadius.all(radius ?? AppRadius.card),
          border: Border.all(color: AppColors.line),
        ),
        child: child,
      );
}

/// `.card-h`: title (+count) left, action right, padding `16px 20px 8px`.
class CardHeader extends StatelessWidget {
  const CardHeader(this.title, {super.key, this.sub, this.count, this.action, this.padding});
  final String title;
  final String? sub;
  final Widget? count, action;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Row(spacing: 8, children: [Flexible(child: CutText(title, style: AppText.s(15.5, W.w7, ls: -0.15), overflow: TextOverflow.ellipsis)), ?count]),
              if (sub != null) Text(sub!, style: AppText.cap),
            ]),
          ),
          ?action,
        ]),
      );
}

/// `.row`: padding 10/12, radius 8, gap 12; hover soft blue and the chevron turns accent.
class AppRow extends StatelessWidget {
  const AppRow({super.key, this.leading, required this.title, this.sub, this.trailing, this.onTap, this.compact = false, this.chevron = false, this.titleWidget});
  final Widget? leading, trailing, titleWidget;
  final String title;
  final String? sub;
  final VoidCallback? onTap;
  final bool compact, chevron;

  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (context, h, _) => Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 7 : 10),
          decoration: BoxDecoration(color: h && onTap != null ? AppColors.hover : null, borderRadius: AppRadius.all(AppRadius.item)),
          child: Row(spacing: 12, children: [
            ?leading,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 2, children: [
                titleWidget ?? CutText(title, style: AppText.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (sub != null) CutText(sub!, style: AppText.rowSub, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            ?trailing,
            if (chevron) Icon(Icons.chevron_right_rounded, size: 18, color: h ? AppColors.accent : AppColors.muted),
          ]),
        ),
      );
}

/// 26–36px rounded icon tile (accent-soft by default).
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.size = 26, this.bg = AppColors.accentSoft, this.fg = AppColors.accent, this.radius, this.iconSize});
  final AppIconData icon;
  final double size;
  final Color bg, fg;
  final double? radius, iconSize;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: AppRadius.all(radius ?? size * 0.3)),
        child: AppIcon(icon, size: iconSize ?? size * 0.58, color: fg),
      );
}

class Divider1 extends StatelessWidget {
  const Divider1({super.key, this.indent = 0});
  final double indent;
  @override
  Widget build(BuildContext context) => Container(height: 1, margin: EdgeInsets.only(left: indent), color: AppColors.line);
}

/// Empty state: one clear line + what to do next.
class EmptyState extends StatelessWidget {
  const EmptyState(this.title, {super.key, this.sub, this.action, this.icon});
  final String title;
  final String? sub;
  final Widget? action;
  final AppIconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        child: Column(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
          if (icon != null) IconTile(icon!, size: 40, bg: AppColors.sub, fg: AppColors.muted),
          Text(title, style: AppText.s(14, W.w7), textAlign: TextAlign.center),
          if (sub != null) Text(sub!, style: AppText.sub, textAlign: TextAlign.center),
          if (action != null) Padding(padding: const EdgeInsets.only(top: 4), child: action),
        ]),
      );
}

/// Simple progress bar `.bar` (track sub, fill accent).
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.width, this.height = 6, this.color = AppColors.accent, this.track = AppColors.sub});
  final double value;
  final double? width;
  final double height;
  final Color color, track;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: AppRadius.all(height),
          child: Stack(children: [
            Positioned.fill(child: ColoredBox(color: track)),
            FractionallySizedBox(widthFactor: value.clamp(0, 1).toDouble(), child: ColoredBox(color: color, child: SizedBox(height: height))),
          ]),
        ),
      );
}
