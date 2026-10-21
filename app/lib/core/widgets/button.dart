import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import '../theme/theme.dart';
import 'hover.dart';
import 'tooltip.dart';

enum BtnKind { primary, dark, outline, danger, text, soft }

enum BtnSize { sm, md, lg }

/// Web button `.btn` (docs/design.md §3.1): 36 high (sm 30, lg 42), radius 8, 700/13.5.
class AppButton extends StatelessWidget {
  const AppButton(this.label,
      {super.key, this.onPressed, this.kind = BtnKind.outline, this.size = BtnSize.md, this.icon, this.trailingIcon, this.expand = false, this.loading = false, this.iconOnly = false, this.tooltip});
  const AppButton.primary(this.label,
      {super.key, this.onPressed, this.size = BtnSize.md, this.icon, this.trailingIcon, this.expand = false, this.loading = false, this.iconOnly = false, this.tooltip})
      : kind = BtnKind.primary;

  /// What the button does, shown on hover / long press (an icon-only button shows its label when this is empty).
  final String? tooltip;
  final String label;
  final VoidCallback? onPressed;
  final BtnKind kind;
  final BtnSize size;
  final AppIconData? icon, trailingIcon;
  final bool expand, loading, iconOnly;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    final h = switch (size) { BtnSize.sm => 30.0, BtnSize.md => 36.0, BtnSize.lg => 42.0 };
    return Hover(
      onTap: disabled ? null : onPressed,
      builder: (context, hov, _) {
        final (bg, fg, border) = switch (kind) {
          BtnKind.primary => (hov ? AppColors.accentHover : AppColors.accent, AppColors.white, null),
          BtnKind.dark => (hov ? AppColors.darkHover : AppColors.text, AppColors.white, null),
          BtnKind.outline => (hov ? AppColors.outlineHover : AppColors.white, AppColors.text, hov ? AppColors.lineHover : AppColors.line2),
          BtnKind.danger => (hov ? AppColors.badHoverBg : AppColors.badBg, AppColors.badText, null),
          BtnKind.soft => (hov ? AppColors.sub : AppColors.accentSoft, AppColors.accentText, null),
          BtnKind.text => (Colors.transparent, AppColors.accentText, null),
        };
        final style = AppText.button.copyWith(
          color: fg,
          fontSize: size == BtnSize.sm ? 12.5 : 13.5,
          decoration: kind == BtnKind.text && hov ? TextDecoration.underline : null,
          decorationColor: fg,
        );
        final iconSize = size == BtnSize.sm ? 15.0 : 16.0;
        final children = <Widget>[
          if (loading)
            SizedBox(width: iconSize, height: iconSize, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
          else if (icon != null)
            AppIcon(icon!, size: iconSize, color: fg),
          if (!iconOnly) Flexible(child: Text(label, style: style, overflow: TextOverflow.ellipsis, maxLines: 1)),
          if (trailingIcon != null && !iconOnly) AppIcon(trailingIcon!, size: 15, color: fg),
        ];
        final content = Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 7,
          children: children,
        );
        final btn = Container(
          height: h,
          width: iconOnly ? h : null,
          padding: kind == BtnKind.text || iconOnly ? EdgeInsets.zero : EdgeInsets.symmetric(horizontal: icon != null ? 12 : 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppRadius.all(AppRadius.btn),
            border: border != null ? Border.all(color: border) : null,
          ),
          child: content,
        );
        final out = Opacity(opacity: disabled && !loading ? 0.45 : 1, child: btn);
        final tip = tooltip ?? (iconOnly ? label : null);
        return tip != null ? AppTooltip(message: tip, child: out) : out;
      },
    );
  }
}

/// Square icon button `.ibtn`: 36×36 radius 10 (sm 30×30 radius 8), optional red dot.
class AppIconButton extends StatelessWidget {
  const AppIconButton(this.icon, {super.key, required this.tooltip, this.onPressed, this.small = false, this.ghost = false, this.dot = false, this.color, this.fill = false});
  final AppIconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool small, ghost, dot;
  final Color? color;

  /// Filled glyph (`.i.fill`, e.g. the ⋯ dots).
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final s = small ? 30.0 : 36.0;
    return AppTooltip(
      message: tooltip,
      child: Hover(
        onTap: onPressed,
        builder: (context, hov, _) => Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
            color: hov ? AppColors.outlineHover : (ghost ? Colors.transparent : AppColors.white),
            borderRadius: AppRadius.all(small ? 8 : 10),
            border: Border.all(color: ghost && !hov ? Colors.transparent : AppColors.line),
          ),
          child: Stack(alignment: Alignment.center, children: [
            AppIcon(icon, size: small ? 15 : 16, fill: fill, color: color ?? (hov ? AppColors.text : AppColors.text2)),
            if (dot)
              Positioned(
                top: small ? 6 : 8,
                right: small ? 6 : 8,
                child: Container(width: 7, height: 7, decoration: BoxDecoration(color: AppColors.red, shape: BoxShape.circle, border: Border.all(color: AppColors.white, width: 1.5))),
              ),
          ]),
        ),
      ),
    );
  }
}
