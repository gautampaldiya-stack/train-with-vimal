import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/photo_viewer.dart' show photoImage;
import '../checkins/checkins_parts.dart' show DashedBox;
import 'progress_model.dart';
import '../../../core/widgets/tooltip.dart';

/// Small pieces of the Progress board (`px-*`), shared by the phone and web layouts.

const pxPerson = Ic.i273259; // the figure on a photo placeholder
const pxScale = Ic.i9c63ed; // weigh-in

/// `px-ch`: bold title, grey line under it, optional action on the right.
class PxHead extends StatelessWidget {
  const PxHead(this.title, this.sub, {super.key, this.action});
  final String title, sub;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
    Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
        Text(title, style: AppText.s(15, W.w8)),
        if (sub.isNotEmpty) Text(sub, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
      ]),
    ),
    ?action,
  ]);
}

/// `px-link`: blue bold text button.
Widget pxLink(String t, VoidCallback onTap) => Semantics(
  button: true,
  child: Hover(
    onTap: onTap,
    builder: (_, h, _) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(t, style: AppText.s(13, W.w7, color: h ? AppColors.text : AppColors.accentText)),
    ),
  ),
);

enum PxTone { green, blue, amber, gray }

/// `fd-pill` in its colours.
Widget pxPill(String t, PxTone tone) {
  final (bg, fg) = switch (tone) {
    PxTone.green => (AppColors.okBg, AppColors.okText),
    PxTone.blue => (AppColors.infoBg, AppColors.infoText),
    PxTone.amber => (AppColors.amberBg, AppColors.amberText),
    PxTone.gray => (AppColors.sub, AppColors.text2),
  };
  return Container(
    height: 22,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    alignment: Alignment.center,
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
    child: Text(t, maxLines: 1, style: AppText.s(11.5, W.w7, color: fg)),
  );
}

/// `px-back`: "‹ Progress" above a sub page's title.
class PxBack extends StatelessWidget {
  const PxBack(this.label, this.onTap, {super.key});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Semantics(
      button: true,
      label: 'Back to $label',
      child: Hover(
        onTap: onTap,
        builder: (_, h, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
            AppIcon(AppIcons.chevronLeft, size: 16, color: h ? AppColors.text : AppColors.muted),
            Text(label, style: AppText.s(13, W.w7, color: h ? AppColors.text : AppColors.muted)),
          ]),
        ),
      ),
    ),
  );
}

/// `fd-top`: page title + grey line, buttons on the right.
class PxTop extends StatelessWidget {
  const PxTop(this.title, this.sub, {super.key, this.actions = const []});
  final String title, sub;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Row(spacing: 8, children: [
    Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
        Text(title, style: AppText.s(26, W.w8, ls: -0.26)),
        Text(sub, style: AppText.s(13, W.w6, color: AppColors.muted)),
      ]),
    ),
    ...actions,
  ]);
}

/// `px-chip`: outline chip (Compare toggle, history type filter). Dark when on.
class PxChip extends StatelessWidget {
  const PxChip(this.label, {super.key, this.icon, required this.on, required this.onTap, this.small = false});
  final String label;
  final AppIconData? icon;
  final bool on, small;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    child: Hover(
      onTap: onTap,
      builder: (_, h, _) => Container(
        height: small ? 32 : 38,
        padding: EdgeInsets.symmetric(horizontal: small ? 11 : 12),
        decoration: BoxDecoration(
          color: on ? AppColors.text : (h ? AppColors.outlineHover : AppColors.white),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? AppColors.text : AppColors.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
          if (icon != null) AppIcon(icon!, size: 15, color: on ? AppColors.white : AppColors.text2),
          Text(label, style: AppText.s(small ? 12.5 : 13, W.w7, color: on ? AppColors.white : AppColors.text2)),
        ]),
      ),
    ),
  );
}

/// `tabs px-tabs`: grey track, the picked tab white. [fit] keeps each tab to its label (web, Gautam 2026-10-16: smaller).
class PxTabs extends StatelessWidget {
  const PxTabs({super.key, required this.labels, required this.index, required this.onPick, this.fit = true});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onPick;
  final bool fit;
  @override
  Widget build(BuildContext context) {
    Widget tab(int i, String l) => Semantics(
      button: true,
      selected: i == index,
      child: Hover(
        onTap: () => onPick(i),
        builder: (_, h, _) => Container(
          height: 32,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: fit ? 16 : 6),
          decoration: BoxDecoration(
            color: i == index ? AppColors.white : null,
            borderRadius: BorderRadius.circular(6),
            boxShadow: i == index ? const [BoxShadow(color: AppColors.shadowSoft, blurRadius: 2, offset: Offset(0, 1)), BoxShadow(color: AppColors.line, spreadRadius: 1)] : null,
          ),
          child: CutText(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w6, color: i == index || h ? AppColors.text : AppColors.text2)),
        ),
      ),
    );
    final track = Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: fit ? MainAxisSize.min : MainAxisSize.max, children: [
        for (final (i, l) in labels.indexed) fit ? tab(i, l) : Expanded(child: tab(i, l)),
      ]),
    );
    return fit ? Align(alignment: Alignment.centerLeft, child: track) : track;
  }
}

/// `px-tile`: a progress photo, or its placeholder (a figure on the set's colour), or "No photo" stripes.
class PxTile extends StatelessWidget {
  const PxTile({
    super.key,
    required this.set,
    required this.pose,
    this.label,
    this.badge,
    this.badgeAccent = false,
    this.selected = false,
    this.noPhoto = 'No photo',
    this.aspect = 4 / 5,
    this.figure = .46,
  });
  final PxSet? set;
  final String pose;

  /// Bottom-left pill ("Front", "4 Oct · Front").
  final String? label;

  /// Top-left round letter ("A", "B").
  final String? badge;
  final bool badgeAccent, selected;
  final String noPhoto;
  final double aspect, figure;

  @override
  Widget build(BuildContext context) {
    final p = set?.of(pose);
    final img = photoImage(p?.image);
    final none = p == null;
    final (c1, c2, fg) = AppColors.pxTiles[(set?.tint ?? 0) % AppColors.pxTiles.length];
    Widget inner = LayoutBuilder(builder: (_, b) {
      final fig = AppIcon(pxPerson, size: b.maxWidth * figure, color: none ? AppColors.pxNoneFig.withValues(alpha: .5) : fg, stroke: 1.3);
      return Stack(fit: StackFit.expand, children: [
        if (img != null)
          Image(image: img, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => Center(child: fig))
        else
          Center(child: fig),
        if (none)
          Positioned(
            left: 6,
            right: 6,
            bottom: b.maxHeight * .34 - 8,
            child: Text(noPhoto, textAlign: TextAlign.center, style: AppText.s(11.5, W.w7, color: AppColors.muted)),
          ),
        if (badge != null)
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: badgeAccent ? AppColors.accent : AppColors.text, shape: BoxShape.circle),
              child: Text(badge!, style: AppText.s(11.5, W.w8, color: AppColors.white)),
            ),
          ),
        if (label != null)
          Positioned(
            left: 6,
            bottom: 6,
            right: 6,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: AppColors.pxPoseBg, borderRadius: BorderRadius.circular(6)),
                child: CutText(label!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11, W.w7)),
              ),
            ),
          ),
      ]);
    });
    final box = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: none ? null : LinearGradient(begin: const Alignment(-.35, -1), end: const Alignment(.35, 1), colors: [c1, c2]),
        color: none ? AppColors.pxNone : null,
        boxShadow: selected ? const [BoxShadow(color: AppColors.accentSoft, spreadRadius: 3)] : null,
      ),
      foregroundDecoration: selected ? BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.accent, width: 2)) : null,
      child: none ? CustomPaint(painter: _Stripes(), child: inner) : inner,
    );
    return AspectRatio(aspectRatio: aspect, child: none ? DashedBox(color: AppColors.line2, radius: 10, child: box) : box);
  }
}

class _Stripes extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.pxNone2
      ..strokeWidth = 8 / math.sqrt2 * 1.0;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final n = (size.width + size.height) / 16 + 2;
    for (var i = 0; i < n; i++) {
      final x = i * 16.0 * math.sqrt2 - size.height;
      canvas.drawLine(Offset(x, size.height + 4), Offset(x + size.height + 8, -4), p..strokeWidth = 8);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Stripes old) => false;
}

/// `px-tbl`: a compare table — metric, A, B (bold), change (green when down, amber when up).
class PxTable extends StatelessWidget {
  const PxTable({super.key, required this.heads, required this.rows});
  final (String, String) heads;

  /// (metric, a, b, change, down?) — down: true = green, false = amber, null = plain.
  final List<(String, String, String, String, bool?)> rows;
  @override
  Widget build(BuildContext context) {
    Widget row(List<Widget> cells, {bool head = false}) => Container(
      padding: EdgeInsets.only(top: head ? 0 : 8, bottom: 8),
      decoration: BoxDecoration(border: head ? null : const Border(top: BorderSide(color: AppColors.line))),
      child: Row(spacing: 6, children: [
        Expanded(flex: 11, child: cells[0]),
        for (final c in cells.skip(1)) Expanded(flex: 10, child: Align(alignment: Alignment.centerRight, child: c)),
      ]),
    );
    final hs = AppText.s(11.5, W.w7, color: AppColors.muted);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row(head: true, [const SizedBox(), Text(heads.$1, style: hs), Text(heads.$2, style: hs), Text('Change', style: AppText.s(11.5, W.w4, color: AppColors.muted))]),
      for (final (m, a, b, d, down) in rows)
        row([
          Text(m, style: AppText.s(13, W.w7)),
          Text(a, maxLines: 1, style: AppText.s(13, W.w4)),
          Text(b, maxLines: 1, style: AppText.s(13, W.w8)),
          Text(d, maxLines: 1, style: AppText.s(13, W.w7, color: down == null ? AppColors.text : (down ? AppColors.okText : AppColors.amberText))),
        ]),
    ]);
  }
}

/// `px-chart`: weight line with its area, the goal line, y labels and tappable dots.
class PxWeightChart extends StatelessWidget {
  const PxWeightChart({super.key, required this.points, required this.goal, required this.selected, required this.onPick, this.height = 156, this.dots = true});
  final List<PxWeight> points;
  final double? goal;
  final DateTime? selected;
  final ValueChanged<PxWeight> onPick;
  final double height;

  /// Tappable dots on each weigh-in (off on the trainer Overview's small trend, as on the board).
  final bool dots;

  @override
  Widget build(BuildContext context) {
    final vals = [for (final p in points) p.kg, ?goal];
    final ymin = (vals.reduce(math.min) - .5).floorToDouble(), ymax = (vals.reduce(math.max) + .5).ceilToDouble();
    final x0 = points.first.date, x1 = points.last.date;
    final span = math.max(1, x1.difference(x0).inDays);
    double xp(DateTime d) => .03 + d.difference(x0).inDays / span * .94;
    double yp(double v) => .04 + (ymax - v) / (ymax - ymin) * .92;
    String lab(double v) {
      final r = (v * 10).round() / 10;
      return r == r.roundToDouble() ? '${r.round()}' : '$r';
    }

    return SizedBox(
      height: height,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        SizedBox(
          width: 26,
          child: LayoutBuilder(builder: (_, b) => Stack(clipBehavior: Clip.none, children: [
            for (final (i, v) in [ymax, (ymax + ymin) / 2, ymin].indexed)
              Positioned(
                right: 0,
                top: b.maxHeight * const [.04, .5, .96][i] - 7,
                child: Text(lab(v), style: AppText.s(10.5, W.w6, color: AppColors.muted)),
              ),
          ])),
        ),
        Expanded(
          child: LayoutBuilder(builder: (_, b) {
            final w = b.maxWidth, h = b.maxHeight;
            return Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ChartPainter(
                    pts: [for (final p in points) Offset(xp(p.date) * w, yp(p.kg) * h)],
                    goalY: goal == null ? null : yp(goal!) * h,
                  ),
                ),
              ),
              if (goal != null)
                Positioned(
                  right: 2,
                  top: (yp(goal!) - .13) * h,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.okBg, borderRadius: BorderRadius.circular(5)),
                    child: Text('Goal ${pxAmt(goal!, 'kgs')}', style: AppText.s(10.5, W.w7, color: AppColors.okText)),
                  ),
                ),
              if (dots)
                for (final (i, p) in points.indexed)
                  Positioned(
                    left: xp(p.date) * w - 11,
                  top: yp(p.kg) * h - 11,
                  child: _Dot(
                    on: selected != null && DateUtils.isSameDay(selected, p.date),
                    last: i == points.length - 1,
                    label: '${pxDm(p.date)}, ${pxAmt(p.kg, 'kg')}',
                    onTap: () => onPick(p),
                  ),
                ),
            ]);
          }),
        ),
      ]),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.on, required this.last, required this.label, required this.onTap});
  final bool on, last;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    label: label,
    child: Hover(
      onTap: onTap,
      builder: (_, h, _) {
        final s = on ? 15.0 : (h ? 14.0 : 11.0); // 7 px dot + 2 px ring; picked 11 + ring
        return SizedBox(
          width: 22,
          height: 22,
          child: Center(
            child: Container(
              width: s,
              height: s,
              decoration: BoxDecoration(
                color: on || last ? AppColors.accent : AppColors.white,
                shape: BoxShape.circle,
                border: on ? null : Border.all(color: AppColors.accent, width: 2),
                boxShadow: on ? const [BoxShadow(color: AppColors.accentSoft, spreadRadius: 4)] : null,
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.pts, required this.goalY});
  final List<Offset> pts;
  final double? goalY;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    for (final y in [.5, size.height / 2, size.height - .5]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (pts.isEmpty) return;
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    final area = Path.from(line)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = AppColors.accentSoft.withValues(alpha: .8));
    if (goalY != null) {
      final g = Paint()
        ..color = AppColors.pxGoal
        ..strokeWidth = 1.5;
      for (var x = 0.0; x < size.width; x += 9) {
        canvas.drawLine(Offset(x, goalY!), Offset(math.min(x + 5, size.width), goalY!), g);
      }
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.pts != pts || old.goalY != goalY;
}

/// `px-spark`: a lift's heaviest set per session, 64 × 26.
class PxSpark extends StatelessWidget {
  const PxSpark(this.series, {super.key});
  final List<PxWeight> series;
  @override
  Widget build(BuildContext context) => SizedBox(width: 64, height: 26, child: CustomPaint(painter: _Spark(series)));
}

class _Spark extends CustomPainter {
  _Spark(this.s);
  final List<PxWeight> s;
  @override
  void paint(Canvas canvas, Size size) {
    if (s.length < 2) return;
    final vs = s.map((p) => p.kg);
    final lo = vs.reduce(math.min), hi = vs.reduce(math.max);
    final a = s.first.date, span = math.max(1, s.last.date.difference(a).inDays);
    final path = Path();
    for (final (i, p) in s.indexed) {
      final x = (2 + p.date.difference(a).inDays / span * 76) / 80 * size.width;
      final y = (25 - (p.kg - lo) / math.max(1, hi - lo) * 22) / 28 * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_Spark old) => old.s != s;
}

/// `px-sg` cell: label, bold value (green when down, amber when up), grey line.
Widget pxStatCell(String l, String v, String s, {bool? down}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
  decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(10)),
  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
    Text(l, style: AppText.s(11, W.w4, color: AppColors.muted)),
    Text(v, style: AppText.s(14, W.w7, color: down == null ? AppColors.text : (down ? AppColors.okText : AppColors.warnText))),
    CutText(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11, W.w4, color: AppColors.muted)),
  ]),
);

/// `px-adl` / `px-lwn`: grey line with an icon.
Widget pxNote(AppIconData icon, String t) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
  decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(10)),
  child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
    Padding(padding: const EdgeInsets.only(top: 1), child: AppIcon(icon, size: 15, color: AppColors.muted)),
    Expanded(child: Text(t, style: AppText.s(12.5, W.w6, color: AppColors.text2, h: 1.4))),
  ]),
);

/// History row icon per log type (`ch-ic` blue / green / purple / amber).
(AppIconData, Color, Color) pxTypeIcon(String type) => switch (type) {
  'workout' => (AppIcons.dumbbell, AppColors.accentSoft, AppColors.accentText),
  'meal' => (AppIcons.food, AppColors.okBg, AppColors.okText),
  'checkin' => (AppIcons.clipboard, AppColors.purpleBg, AppColors.purpleText),
  _ => (pxScale, AppColors.icAmberBg, AppColors.icAmberText),
};

/// `px-e`: one log in a history day — type icon, title, grey line, optional badge.
class PxEntryRow extends StatelessWidget {
  const PxEntryRow(this.e, {super.key, this.first = false});
  final PxEntry e;
  final bool first;
  @override
  Widget build(BuildContext context) {
    final (ic, bg, fg) = pxTypeIcon(e.type);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: AppColors.line))),
      child: Row(spacing: 10, children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
          child: AppIcon(ic, size: 15, color: fg),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
            Text(e.title, style: AppText.s(13.5, W.w7)),
            Text(e.sub, style: AppText.s(12, W.w4, color: AppColors.muted)),
          ]),
        ),
        if (e.badge.isNotEmpty) pxPill(e.badge, e.badgeColor == 'green' ? PxTone.green : (e.badgeColor == 'amber' ? PxTone.amber : PxTone.gray)),
      ]),
    );
  }
}
