import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import '../theme/theme.dart';
import 'hover.dart';

/// `.badge` 22 high, radius 6, 700/11.5, 6px dot in front (unless [plain]).
class AppBadge extends StatelessWidget {
  const AppBadge(this.label, {super.key, this.tone = Tone.neutral, this.plain = false});
  final String label;
  final Tone tone;
  final bool plain;

  @override
  Widget build(BuildContext context) => Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: tone.bg, borderRadius: AppRadius.all(AppRadius.badge)),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
          if (!plain) Container(width: 6, height: 6, decoration: BoxDecoration(color: tone.fg, shape: BoxShape.circle)),
          Text(label, style: AppText.s(11.5, W.w7, color: tone.fg)),
        ]),
      );
}

/// `.count` dark pill: min 20×20, 700/11.
class AppCount extends StatelessWidget {
  const AppCount(this.n, {super.key, this.size = 20, this.color = AppColors.text});
  final Object n;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        constraints: BoxConstraints(minWidth: size),
        height: size,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, borderRadius: AppRadius.all(size / 2)),
        child: Text('$n', style: AppText.s(size < 18 ? 9.5 : 11, W.w7, color: AppColors.white)),
      );
}

/// Unread count on a bell: red pill (min 16×16, 700/10, white text) with a ring in the button's colour,
/// "9+" above nine. Replaces the board's red dot (Probid, 2026-10-24: show how many are unread).
class BellCount extends StatelessWidget {
  const BellCount(this.n, {super.key, this.ring = AppColors.white});
  final int n;
  final Color ring;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 18),
        height: 18,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.red, borderRadius: AppRadius.all(9), border: Border.all(color: ring, width: 2)),
        child: Text(n > 9 ? '9+' : '$n', style: AppText.s(10, W.w7, color: AppColors.white, h: 1)),
      );
}

/// `.fchip` kind filter (28 high, active = dark fill) with optional count.
class FilterChipX extends StatelessWidget {
  const FilterChipX(this.label, {super.key, this.selected = false, this.count, this.onTap, this.icon});
  final String label;
  final bool selected;
  final int? count;
  final VoidCallback? onTap;
  final AppIconData? icon;

  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (context, h, _) {
          final fg = selected ? AppColors.white : AppColors.text2;
          return Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.text : (h ? AppColors.outlineHover : AppColors.white),
              borderRadius: AppRadius.all(AppRadius.chip),
              border: Border.all(color: selected ? AppColors.text : AppColors.line2),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              if (icon != null) AppIcon(icon!, size: 14, color: fg),
              Text(label, style: AppText.s(12.5, W.w6, color: fg)),
              if (count != null) Text('$count', style: AppText.s(11.5, W.w7, color: selected ? AppColors.white.withValues(alpha: .7) : AppColors.muted)),
            ]),
          );
        },
      );
}

/// `.chip` set filter: label muted + value bold + ×.
class SetChip extends StatelessWidget {
  const SetChip({super.key, required this.label, required this.value, this.onRemove, this.onTap});
  final String label, value;
  final VoidCallback? onRemove, onTap;

  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (context, h, _) => Container(
          height: 30,
          padding: const EdgeInsets.only(left: 10, right: 4),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.all(AppRadius.chip), border: Border.all(color: AppColors.line2)),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
            Text(label, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
            Text(value, style: AppText.s(12.5, W.w7)),
            if (onRemove != null)
              Hover(
                onTap: onRemove,
                builder: (_, hx, _) => Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(color: hx ? AppColors.sub : null, borderRadius: AppRadius.all(6)),
                  child: const Icon(Icons.close_rounded, size: 14, color: AppColors.muted),
                ),
              ),
          ]),
        ),
      );
}

/// Client app chip `.ca-chip` 24 high radius 7.
class CaChip extends StatelessWidget {
  const CaChip(this.label, {super.key, this.tone = Tone.neutral});
  final String label;
  final Tone tone;

  @override
  Widget build(BuildContext context) => Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: tone.bg, borderRadius: AppRadius.all(AppRadius.caChip)),
        child: Text(label, style: AppText.s(12, W.w7, color: tone.fg)),
      );
}
