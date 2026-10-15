import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';

/// Small pieces of the client Home board (`ch-*` classes), shared by the phone and web layouts.

enum ChTone { blue, green, amber, purple, gray, warm }

(Color, Color) chTone(ChTone t) => switch (t) {
      ChTone.blue => (AppColors.accentSoft, AppColors.accentText),
      ChTone.green => (AppColors.okBg, AppColors.okText),
      ChTone.amber => (AppColors.icAmberBg, AppColors.icAmberText),
      ChTone.purple => (AppColors.purpleBg, AppColors.purpleText),
      ChTone.gray => (AppColors.sub, AppColors.text2),
      ChTone.warm => (AppColors.warmBg, AppColors.warm),
    };

/// `ch-ic`: 34px rounded icon tile.
class ChIcon extends StatelessWidget {
  const ChIcon(this.icon, {super.key, this.tone = ChTone.gray});
  final AppIconData icon;
  final ChTone tone;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = chTone(tone);
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: AppIcon(icon, size: 17, color: fg),
    );
  }
}

/// `ca-card`: white, radius 14, padding 14, children 12 apart.
class ChCard extends StatelessWidget {
  const ChCard({super.key, required this.children, this.padding = const EdgeInsets.all(14), this.gap = 12});
  final List<Widget> children;
  final EdgeInsets padding;
  final double gap;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: gap, children: children),
      );
}

/// `ch-ch`: card header — icon tile, bold title, grey line, optional button.
class ChHead extends StatelessWidget {
  const ChHead({super.key, required this.lead, required this.title, required this.sub, this.action});
  final Widget lead;
  final String title, sub;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(spacing: 10, children: [
        lead,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppText.s(15, W.w8)),
            Text(sub, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
          ]),
        ),
        ?action,
      ]);
}

/// Small outline button (`ca-btn out sm`), its natural width.
Widget chSm(String label, VoidCallback onTap, {AppIconData? icon, CaBtnKind kind = CaBtnKind.out}) =>
    CaButton(label, kind: kind, small: true, expand: false, icon: icon, onPressed: onTap);

/// `ch-mb`: thin progress bar.
class ChBar extends StatelessWidget {
  const ChBar(this.ratio, {super.key, required this.color, this.height = 6});
  final double ratio;
  final Color color;
  final double height;
  @override
  Widget build(BuildContext context) => Container(
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: AppColors.barTrack, borderRadius: BorderRadius.circular(6)),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedFractionallySizedBox(
            duration: const Duration(milliseconds: 250),
            widthFactor: ratio.clamp(0.0, 1.0),
            heightFactor: 1,
            child: DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6))),
          ),
        ),
      );
}

/// `ch-ok`: green "Done" / "Taken" / "Logged" mark.
class ChOk extends StatelessWidget {
  const ChOk(this.label, {super.key, this.icon = false});
  final String label;
  final bool icon;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, spacing: 3, children: [
        if (icon) const AppIcon(AppIcons.check, size: 13, color: AppColors.okText, stroke: 2.6),
        Text(label, style: AppText.s(12, W.w7, color: AppColors.okText)),
      ]);
}

/// A tinted line inside a card (`ch-sess`, `ch-rest`, `ch-wdone`, `ch-next.done`).
class ChNote extends StatelessWidget {
  const ChNote({super.key, this.icon, required this.child, required this.bg, required this.fg, this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10), this.top = false});
  final AppIconData? icon;
  final Widget child;
  final Color bg, fg;
  final EdgeInsets padding;
  final bool top;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: top ? CrossAxisAlignment.start : CrossAxisAlignment.center, spacing: 8, children: [
          if (icon != null) AppIcon(icon!, size: 16, color: fg),
          Expanded(child: child),
        ]),
      );
}

/// A row with a top line (`ch-row`, `ch-hb`, `ch-n`, `ch-uprow`); the first one has none.
class ChRow extends StatelessWidget {
  const ChRow({super.key, required this.children, this.first = false, this.vertical = 10, this.gap = 11, this.onTap, this.top = false});
  final List<Widget> children;
  final bool first, top;
  final double vertical, gap;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    Widget row(bool h) => Container(
          padding: EdgeInsets.symmetric(vertical: vertical),
          decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: AppColors.line))),
          child: Row(crossAxisAlignment: top ? CrossAxisAlignment.start : CrossAxisAlignment.center, spacing: gap, children: children),
        );
    return onTap == null ? row(false) : Hover(onTap: onTap, builder: (_, h, _) => row(h));
  }
}

/// Bold title and a grey line under it.
class ChTwoLine extends StatelessWidget {
  const ChTwoLine(this.title, this.sub, {super.key, this.size = 14, this.subSize = 12, this.titleStyle, this.dot = false});
  final String title, sub;
  final double size, subSize;
  final TextStyle? titleStyle;
  final bool dot;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(
          TextSpan(text: title, children: [
            if (dot)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(width: 7, height: 7, margin: const EdgeInsets.only(left: 6), decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
              ),
          ]),
          style: titleStyle ?? AppText.s(size, W.w7),
        ),
        if (sub.isNotEmpty) Text(sub, style: AppText.s(subSize, W.w4, color: AppColors.muted)),
      ]);
}

/// `ch-sec`: "Coming up" heading between cards.
class ChSection extends StatelessWidget {
  const ChSection(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(left: 2, top: 4), child: Pull(bottom: 4, child: Text(text, style: AppText.s(15, W.w8))));
}

/// `.ca-ib`: 38px icon button with an optional red dot (the bell).
class ChBell extends StatelessWidget {
  const ChBell({super.key, required this.dot, required this.onTap});
  final bool dot;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Notifications',
        button: true,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: h ? AppColors.outlineHover : AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
            child: Stack(alignment: Alignment.center, children: [
              const AppIcon(AppIcons.bell, size: 19, color: AppColors.text2),
              if (dot)
                Positioned(
                  top: 7,
                  right: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: AppColors.red, shape: BoxShape.circle, border: Border.all(color: AppColors.white, width: 2)),
                  ),
                ),
            ]),
          ),
        ),
      );
}

/// `.ca-av`: round initials.
class ChAvatar extends StatelessWidget {
  const ChAvatar(this.initials, {super.key, this.green = false});
  final String initials;
  final bool green;
  @override
  Widget build(BuildContext context) {
    final s = green ? 34.0 : 38.0;
    return Container(
      width: s,
      height: s,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: green ? AppColors.avGreenBg : AppColors.caAvBg, shape: BoxShape.circle),
      child: Text(initials, style: AppText.s(green ? 12 : 13, W.w8, color: green ? AppColors.avGreenText : AppColors.caAvText)),
    );
  }
}

/// `ch-ring`: kcal ring, black arc on a grey track.
class ChRing extends StatelessWidget {
  const ChRing({super.key, required this.ratio, required this.value, required this.label, this.color = AppColors.text, this.valueColor, this.size = 92, this.valueSize = 18});
  final double ratio;
  final String value, label;
  final Color color;
  final Color? valueColor;
  final double size, valueSize;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: ratio.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 300),
              builder: (_, v, _) => CustomPaint(painter: _RingPainter(v, color)),
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(value, style: AppText.s(valueSize, W.w8, color: valueColor ?? AppColors.text)),
            Text(label, style: AppText.s(11, W.w4, color: AppColors.muted)),
          ]),
        ]),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.ratio, this.color);
  final double ratio;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 80;
    final c = size.center(Offset.zero);
    final r = 34 * k;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8 * k
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, p..color = AppColors.barTrack);
    if (ratio > 0) canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * ratio, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.ratio != ratio || old.color != color;
}

/// Dashed 16px circle (`.ch-d.rest .ch-dm`).
class DashedCircle extends StatelessWidget {
  const DashedCircle({super.key, this.size = 16});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _DashPainter());
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = AppColors.tickRing;
    final r = size.width / 2 - .75;
    const n = 8;
    for (var i = 0; i < n; i++) {
      canvas.drawArc(Rect.fromCircle(center: size.center(Offset.zero), radius: r), i * 2 * math.pi / n, math.pi / n, false, p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => false;
}

/// `ch-big` + `ch-qs`: big number with − / + and quick picks (steps and sleep sheets).
class ChBigStepper extends StatelessWidget {
  const ChBigStepper({super.key, required this.value, required this.label, required this.onMinus, required this.onPlus});
  final String value, label;
  final VoidCallback onMinus, onPlus;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(spacing: 12, children: [
          _RoundBtn(AppIcons.minus, 'Less', onMinus),
          Expanded(
            child: Column(children: [
              Text(value, style: AppText.s(34, W.w8, ls: -0.68)),
              Text(label, style: AppText.s(12.5, W.w6, color: AppColors.muted)),
            ]),
          ),
          _RoundBtn(AppIcons.plus, 'More', onPlus),
        ]),
      );
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn(this.icon, this.label, this.onTap);
  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        button: true,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: h ? AppColors.outlineHover : AppColors.white, shape: BoxShape.circle, border: Border.all(color: AppColors.line)),
            child: AppIcon(icon, size: 19, color: AppColors.text2),
          ),
        ),
      );
}

class ChQuick extends StatelessWidget {
  const ChQuick({super.key, required this.items, required this.onPick, this.isOn});
  final List<(String, int)> items;
  final void Function(int) onPick;
  final bool Function(int)? isOn;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        // flex: 1 with min-width 56, wrapping like the board.
        final perRow = math.max(1, math.min(items.length, ((c.maxWidth + 8) / (56 + 8)).floor()));
        final rows = <List<(String, int)>>[];
        for (var i = 0; i < items.length; i += perRow) {
          rows.add(items.sublist(i, math.min(i + perRow, items.length)));
        }
        return Column(spacing: 8, children: [
          for (final r in rows)
            Row(spacing: 8, children: [
              for (final (t, v) in r)
                Expanded(
                  child: Hover(
                    onTap: () => onPick(v),
                    builder: (_, h, _) {
                      final on = isOn?.call(v) ?? false;
                      return Container(
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: on ? AppColors.text : (h ? AppColors.outlineHover : AppColors.white),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: on ? AppColors.text : AppColors.line),
                        ),
                        child: Text(t, style: AppText.s(13.5, W.w7, color: on ? AppColors.white : AppColors.text)),
                      );
                    },
                  ),
                ),
            ]),
        ]);
      });
}
