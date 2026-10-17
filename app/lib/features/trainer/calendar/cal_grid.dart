import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/tooltip.dart';
import 'cal_model.dart';

/// `.cal-card`: day headers over a 6 am – 10 pm grid. Week = 7 columns (phone: a 3-day window), Day = 1.
/// Non-working hours are striped, a day off says "Day off", today is blue with the red now line.
class CalGrid extends StatelessWidget {
  const CalGrid({super.key, required this.c, required this.days, required this.phone, required this.onOpen});
  final CalendarController c;

  /// Indexes (0 = Mon) of the columns on screen.
  final List<int> days;
  final bool phone;
  final void Function(CalSession) onOpen;

  double get _gutter => phone ? 46 : 56;
  bool get _single => days.length == 1;

  @override
  Widget build(BuildContext context) {
    final empty = !c.loading && c.sessions.isEmpty;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: AppColors.line)),
      child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _head(),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: _gutter, child: _times()),
              for (final i in days) Expanded(child: _col(context, i)),
            ]),
          ),
        ]),
        if (empty)
          Positioned(
            top: 200,
            left: phone ? 32 : 0,
            right: phone ? 32 : 0,
            child: Center(child: _Empty(phone: phone)),
          ),
      ]),
    );
  }

  // ─────────────────────────────── Header row

  Widget _head() => LayoutBuilder(builder: (context, box) {
        // `.cal-dh` wraps: a narrow column puts "2 sessions" on its own line.
        final narrow = (box.maxWidth - _gutter) / days.length - 20 < 135;
        return Container(
          decoration: const BoxDecoration(color: AppColors.card, border: Border(bottom: BorderSide(color: AppColors.line))),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: _gutter),
              for (final i in days) Expanded(child: _dayHead(i, narrow)),
            ]),
          ),
        );
      });

  Widget _dayHead(int i, bool narrow) {
    final d = c.dateOf(i), today = c.isToday(i), n = c.on(i).length;
    final cnt = n == 0 ? '' : '$n ${n == 1 ? 'session' : 'sessions'}';
    final wd = c.view == 'day' ? calWdLong[i] : calWd[i];
    // A single column on the phone keeps the plain white head (`:not(:has(.cal-dh + .cal-dh))`).
    final tint = today && !(phone && _single) ? AppColors.calToday : (i > 4 && !_single ? AppColors.calWeekend : null);
    final num = today
        ? Container(
            constraints: const BoxConstraints(minWidth: 28),
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.accent, borderRadius: AppRadius.all(999)),
            child: Text('${d.day}', style: AppText.s(15, W.w7, color: AppColors.white)),
          )
        : Text('${d.day}', style: AppText.s(phone ? 15 : 18, W.w7, ls: -0.36));
    final wdText = Text(wd, style: AppText.s(12, W.w6, color: today ? AppColors.accentText : AppColors.muted));
    final stacked = phone && days.length == 3;
    return Hover(
      onTap: c.view == 'week' ? () => c.openDay(i) : null,
      builder: (_, h, _) => Container(
        padding: phone ? const EdgeInsets.fromLTRB(8, 8, 8, 6) : const EdgeInsets.fromLTRB(10, 10, 10, 8),
        decoration: BoxDecoration(
          color: h && c.view == 'week' ? AppColors.hover : tint,
          border: const Border(left: BorderSide(color: AppColors.line)),
        ),
        child: Builder(builder: (context) {
          if (stacked) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              wdText,
              num,
              if (cnt.isNotEmpty) Text(cnt, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11, W.w5, color: AppColors.muted)),
            ]);
          }
          final count = Text(cnt, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w5, color: AppColors.muted));
          if (narrow) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Row(spacing: 6, children: [wdText, num]),
              if (cnt.isNotEmpty) count,
            ]);
          }
          return Row(spacing: 6, children: [wdText, num, const Spacer(), if (cnt.isNotEmpty) Flexible(flex: 0, child: count)]);
        }),
      ),
    );
  }

  // ─────────────────────────────── Hours down the left

  Widget _times() => SizedBox(
        height: (calH1 - calH0) * calHourPx,
        child: Stack(clipBehavior: Clip.none, children: [
          for (var h = calH0; h < calH1; h++)
            Positioned(
              top: (h - calH0) * calHourPx + (h == calH0 ? 0 : -7),
              right: phone ? 6 : 8,
              child: Text(calFmt(h * 60), style: AppText.s(phone ? 10.5 : 11, W.w6, color: AppColors.muted)),
            ),
        ]),
      );

  // ─────────────────────────────── One day column

  Widget _col(BuildContext context, int i) {
    final today = c.isToday(i);
    final av = c.hoursOn(i);
    final plainToday = phone && _single;
    final bg = today && !plainToday ? AppColors.calToday : (i > 4 && !_single ? AppColors.calWeekend : AppColors.card);
    final line = today && !plainToday ? AppColors.calTodayLine : AppColors.line;
    final top0 = calH0 * 60, end0 = calH1 * 60;
    final now = DateTime.now(), nowM = calMinutes(now);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return Container(
        height: (calH1 - calH0) * calHourPx,
        decoration: BoxDecoration(color: bg, border: const Border(left: BorderSide(color: AppColors.line))),
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: CustomPaint(painter: _Lines(line))),
          if (av != null && av.open && av.from > top0) Positioned(top: 0, left: 0, right: 0, height: _px(av.from), child: const _Off()),
          if (av != null && av.open && av.to < end0)
            Positioned(bottom: 0, left: 0, right: 0, height: (end0 - av.to) / 60 * calHourPx, child: const _Off()),
          if (av != null && !av.open) const Positioned.fill(child: _Off(dayOff: true)),
          ..._blocks(i, w),
          if (today && nowM >= top0 && nowM < end0)
            Positioned(
              top: _px(nowM),
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: SizedBox(
                  height: 2,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Container(color: AppColors.calNow),
                    Positioned(
                      left: -5,
                      top: -4,
                      child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.calNow, shape: BoxShape.circle)),
                    ),
                  ]),
                ),
              ),
            ),
        ]),
      );
    });
  }

  static double _px(int m) => ((m - calH0 * 60) / 60 * calHourPx).roundToDouble();

  /// Overlapping sessions share the column side by side (board `blocksOf`).
  List<Widget> _blocks(int i, double w) {
    final xs = c.on(i);
    final cols = <int>[];
    final colOf = <CalSession, int>{};
    for (final s in xs) {
      var k = cols.indexWhere((end) => end <= s.from);
      if (k < 0) {
        k = cols.length;
        cols.add(0);
      }
      cols[k] = s.from + s.minutes;
      colOf[s] = k;
    }
    return [
      for (final s in xs)
        () {
          final grp = xs.where((o) => o.from < s.from + s.minutes && o.from + o.minutes > s.from);
          final n = grp.map((o) => colOf[o]!).reduce(math.max) + 1;
          final top = _px(s.from.clamp(calH0 * 60, calH1 * 60 - 22));
          final h = math.max(22.0, s.minutes / 60 * calHourPx - 3);
          final cw = w / n;
          return Positioned(
            top: top,
            left: colOf[s]! * cw + 2,
            width: cw - 4,
            height: math.min(h, (calH1 - calH0) * calHourPx - top),
            child: _Block(s: s, phone: phone, onTap: () => onOpen(s)),
          );
        }(),
    ];
  }
}

class _Lines extends CustomPainter {
  _Lines(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (var y = 0.0; y < size.height; y += calHourPx) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(_Lines old) => old.color != color;
}

/// `.cal-off`: thin diagonal stripes (135°, 4 px on / 4 px off). A day off adds the "Day off" chip.
class _Off extends StatelessWidget {
  const _Off({this.dayOff = false});
  final bool dayOff;
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(
          painter: _Stripes(AppColors.calOff, 4, 8),
          child: dayOff
              ? Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      border: Border.all(color: AppColors.line),
                      borderRadius: AppRadius.all(AppRadius.badge),
                    ),
                    child: Text('Day off', style: AppText.s(12, W.w6, color: AppColors.muted)),
                  ),
                )
              : const SizedBox.expand(),
        ),
      );
}

/// Diagonal stripes like `repeating-linear-gradient(135deg, c 0 on, transparent on period)`.
class _Stripes extends CustomPainter {
  _Stripes(this.color, this.on, this.period, {this.bg});
  final Color color;
  final Color? bg;
  final double on, period;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (bg != null) canvas.drawRect(Offset.zero & size, Paint()..color = bg!);
    final p = Paint()
      ..color = color
      ..strokeWidth = on
      ..style = PaintingStyle.stroke;
    // Lines run top-left → bottom-right; spacing along the normal = period.
    final step = period * math.sqrt2;
    for (var x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Stripes old) => old.color != color;
}

/// Legend swatch for "Outside working hours" (`.cal-lg.off > i`).
class CalOffSwatch extends StatelessWidget {
  const CalOffSwatch({super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: AppRadius.all(3)),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(painter: _Stripes(AppColors.calOffA, 3, 6, bg: AppColors.calOffB)),
      );
}

/// `.cal-b`: kind-tinted block with the client and "7:00 am · place"; short ones (< 45 min) show the name only.
class _Block extends StatelessWidget {
  const _Block({required this.s, required this.phone, required this.onTap});
  final CalSession s;
  final bool phone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tiny = s.minutes < 45;
    final tip = [s.client, s.kind.label, calRangeL(s.from, s.minutes), s.bookedBy.isEmpty ? null : s.where, s.done ? 'Done' : (s.status == 'missed' ? 'Missed' : 'Booked')]
        .whereType<String>()
        .join(' · ');
    Widget box(bool h) => AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: s.done ? (h ? .85 : .55) : 1,
          child: Container(
            padding: tiny ? EdgeInsets.symmetric(horizontal: phone ? 6 : 8) : (phone ? const EdgeInsets.fromLTRB(6, 4, 6, 4) : const EdgeInsets.fromLTRB(8, 5, 8, 5)),
            alignment: tiny ? Alignment.centerLeft : Alignment.topLeft,
            decoration: BoxDecoration(
              color: s.kind.bg,
              borderRadius: AppRadius.all(6),
              border: h ? Border.all(color: s.kind.dot, width: 1.5, strokeAlign: BorderSide.strokeAlignOutside) : null,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text(s.client, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w7, h: 1.25)),
              if (!tiny)
                Text('${calFmtL(s.from)} · ${s.where}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w5, color: AppColors.muted, h: 1.25)),
            ]),
          ),
        );
    final block = Hover(onTap: onTap, builder: (_, h, _) => box(h));
    if (phone) return Semantics(button: true, label: tip, child: block);
    return AppTooltip(message: tip, side: TipSide.below, child: block);
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.phone});
  final bool phone;
  @override
  Widget build(BuildContext context) => Container(
        padding: phone ? const EdgeInsets.all(16) : const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.line), borderRadius: AppRadius.all(AppRadius.card)),
        child: Column(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
          const AppIcon(AppIcons.calStat, size: 22, color: AppColors.muted),
          Text('No sessions this week', textAlign: TextAlign.center, style: AppText.s(14, W.w7)),
          Text('Use New session to book one.', textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)),
        ]),
      );
}
