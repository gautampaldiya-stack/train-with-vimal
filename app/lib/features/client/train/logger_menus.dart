import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import 'train_model.dart' show clockText;
import 'workout_model.dart' show SetKind;

/// Menus shared by the logger and the Edit / Log workout page (Probid 19 Nov: the same features on both): the small
/// popover beside a button, its rows, the set type ? card, and the set type texts.

const loggerKindInfo = {
  SetKind.warmup: ('Warm up', 'A light set to get ready. It is not counted in volume or personal bests.'),
  SetKind.drop: ('Drop set', 'Right after a set, lower the weight and keep going with no rest.'),
  SetKind.failure: ('Failure', 'You went until you could not do one more rep with good form.'),
};

Future<void> loggerPopover(BuildContext anchor, {required double width, bool right = false, required Widget Function(BuildContext ctx, VoidCallback close) builder}) {
  final box = anchor.findRenderObject() as RenderBox;
  final overlay = Overlay.of(anchor, rootOverlay: true).context.findRenderObject() as RenderBox;
  final tl = box.localToGlobal(Offset.zero, ancestor: overlay);
  final pad = MediaQuery.paddingOf(anchor);
  return showGeneralDialog(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: 'menu',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 90),
    transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (ctx, _, _) => CustomSingleChildLayout(
      delegate: LoggerPopoverPlace(anchor: tl & box.size, width: width, right: right, top: pad.top + 8, bottom: pad.bottom + 8),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line), boxShadow: AppShadows.menu),
          child: SingleChildScrollView(child: builder(ctx, () => Navigator.of(ctx).pop())),
        ),
      ),
    ),
  );
}


Widget loggerMi(String title, {AppIconData? icon, String? sub, bool danger = false, required VoidCallback onTap}) => Hover(
      onTap: onTap,
      builder: (_, h, _) => Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: sub == null ? 7 : 8),
        decoration: BoxDecoration(color: h ? (danger ? AppColors.badBg : AppColors.hover) : null, borderRadius: BorderRadius.circular(8)),
        child: Row(crossAxisAlignment: sub == null ? CrossAxisAlignment.center : CrossAxisAlignment.start, spacing: 10, children: [
          if (icon != null) Padding(padding: EdgeInsets.only(top: sub == null ? 0 : 2), child: AppIcon(icon, size: 16, color: danger ? AppColors.badText : AppColors.text2)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text(title, style: AppText.s(13.5, W.w6, color: danger ? AppColors.badText : AppColors.text)),
              if (sub != null) Text(sub, style: AppText.s(12, W.w4, color: AppColors.muted)),
            ]),
          ),
        ]),
      ),
    );

void loggerTip(BuildContext anchor, String title, String text) {
  if (!OpenGuard.tap()) return;
  showGeneralDialog<void>(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: AppColors.scrimModal,
    transitionDuration: Motion.short,
    pageBuilder: (ctx, _, _) => Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Material(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(title, style: AppText.s(17, W.w7))),
                  CaBarIcon(tooltip: 'Close', onTap: () => Navigator.of(ctx).pop(), icon: const AppIcon(AppIcons.close, size: 20, color: AppColors.text)),
                ]),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(text, style: AppText.s(14, W.w4, color: AppColors.text2, h: 1.5)),
                ),
              ]),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, a, _, child) {
      final c = CurvedAnimation(parent: a, curve: Motion.curve);
      return FadeTransition(opacity: c, child: ScaleTransition(scale: Tween(begin: .96, end: 1.0).animate(c), child: child));
    },
  );
}


class LoggerPopoverPlace extends SingleChildLayoutDelegate {
  const LoggerPopoverPlace({required this.anchor, required this.width, required this.right, required this.top, required this.bottom});
  final Rect anchor;
  final double width, top, bottom;
  final bool right;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final c = constraints;
    final w = math.min(width, c.maxWidth - 16);
    final room = math.max(anchor.top - 6 - top, c.maxHeight - bottom - anchor.bottom - 6);
    // below or above, whichever has room; a very long menu gets the taller side and scrolls
    return BoxConstraints(minWidth: w, maxWidth: w, maxHeight: math.max(120, math.min(c.maxHeight - top - bottom, math.max(room, 0))));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final child = childSize;
    final x = (right ? anchor.right - child.width : anchor.left).clamp(8.0, math.max(8.0, size.width - child.width - 8)).toDouble();
    final below = anchor.bottom + 6;
    final fitsBelow = below + child.height <= size.height - bottom;
    final above = anchor.top - 6 - child.height;
    final y = fitsBelow || above < top ? below : above;
    return Offset(x, y.clamp(top, math.max(top, size.height - bottom - child.height)).toDouble());
  }

  @override
  bool shouldRelayout(LoggerPopoverPlace o) => o.anchor != anchor || o.width != width || o.right != right || o.top != top || o.bottom != bottom;
}

/// Rest picker rows: − / value / + and quick times (the logger's rest sheets and the Edit workout page).
class RestStepper extends StatelessWidget {
  const RestStepper({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  static const _quick = [0, 30, 60, 90, 120, 180];

  @override
  Widget build(BuildContext context) {
    Widget pm(AppIconData icon, String label, int by) => Semantics(
          button: true,
          label: label,
          child: Hover(
            onTap: () => onChanged((value + by).clamp(0, 900)),
            builder: (_, h, _) => Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: h ? AppColors.pressed : AppColors.sub, borderRadius: BorderRadius.circular(12)),
              child: AppIcon(icon, size: 18, color: AppColors.text),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      Row(spacing: 10, children: [
        pm(AppIcons.minus, 'Less rest', -15),
        Expanded(
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
            child: Text(value == 0 ? 'Off' : clockText(value), style: AppText.s(20, W.w8, tabular: true)),
          ),
        ),
        pm(AppIcons.plus, 'More rest', 15),
      ]),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final q in _quick)
          Hover(
            onTap: () => onChanged(q),
            builder: (_, h, _) => Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: value == q ? AppColors.accent : (h ? AppColors.outlineHover : AppColors.white),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: value == q ? AppColors.accent : AppColors.line),
              ),
              child: Center(widthFactor: 1, child: Text(q == 0 ? 'Off' : clockText(q), style: AppText.s(12.5, W.w7, color: value == q ? AppColors.white : AppColors.text))),
            ),
          ),
      ]),
    ]);
  }
}

/// Places a popover under its anchor when it fits, else above it (bottom next to the anchor), inside the screen.
