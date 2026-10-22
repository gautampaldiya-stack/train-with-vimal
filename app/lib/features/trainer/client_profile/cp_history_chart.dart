import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tooltip.dart';
import 'cp_common.dart';

/// History → "Plans over time" (`.hg`): a label column (Trainer, Workout, Meal plan, Supplements, Habits) and a
/// month track with one bar per plan (Now · Completed · Replaced · Up next), the grid of month lines and the red
/// Today line. Scrolls sideways when narrower than 640. Bars show their dates on hover.
class CpPlansChart extends StatelessWidget {
  const CpPlansChart(this.data, {super.key});

  /// `timeline` from `clients/<id>/history/`: {from, to, today, rows: [{key, label, bars: [{label, start, end, status, tip}]}]}.
  final Map data;

  static const _axisH = 24.0, _rowH = 34.0;

  @override
  Widget build(BuildContext context) {
    final from = _day(data['from']) ?? DateTime.now();
    final to = _day(data['to']) ?? from.add(const Duration(days: 180));
    final today = _day(data['today']) ?? DateTime.now();
    final rows = [for (final r in (data['rows'] as List?) ?? const []) r as Map];
    final total = to.difference(from).inDays + 1;
    double pct(DateTime d) => (d.difference(from).inDays / total).clamp(0.0, 1.0);
    final months = <DateTime>[];
    for (var m = DateTime(from.year, from.month); !m.isAfter(to); m = DateTime(m.year, m.month + 1)) {
      months.add(m);
    }
    final phone = context.isPhone;
    final labelW = phone ? 80.0 : 96.0;
    final h = _axisH + _rowH * rows.length;

    Widget track(double w) => SizedBox(
          width: w,
          height: h,
          child: Stack(clipBehavior: Clip.none, children: [
            // Month grid lines (behind everything).
            for (final m in months)
              Positioned(left: w * pct(m), top: 0, bottom: 0, child: Container(width: 1, color: AppColors.hgGrid)),
            // Axis labels.
            for (final m in months)
              Positioned(
                left: w * pct(m) + 4,
                top: 4,
                child: Text(
                  m.month == 1 && m.year != from.year ? 'Jan ’${'${m.year}'.substring(2)}' : DateFormat('MMM').format(m),
                  style: AppText.s(11, W.w6, color: AppColors.muted),
                ),
              ),
            // Today line + label.
            if (!today.isBefore(from) && !today.isAfter(to)) ...[
              Positioned(left: w * pct(today), top: 18, bottom: 0, child: Container(width: 2, color: AppColors.hgToday)),
            ],
            for (var i = 0; i < rows.length; i++)
              for (final b in (rows[i]['bars'] as List?) ?? const [])
                _bar(b as Map, w, pct, to, top: _axisH + _rowH * i + 6),
            if (!today.isBefore(from) && !today.isAfter(to))
              Positioned(
                left: w * pct(today) - 18,
                top: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(color: AppColors.hgToday, borderRadius: AppRadius.all(4)),
                  child: Text('Today', style: AppText.s(10, W.w7, color: AppColors.white, h: 1.4)),
                ),
              ),
          ]),
        );

    return Padding(
      padding: EdgeInsets.fromLTRB(phone ? 12 : 16, 4, phone ? 12 : 16, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
        SizedBox(
          width: labelW,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: _axisH),
            for (final r in rows)
              SizedBox(
                height: _rowH,
                child: Align(alignment: Alignment.centerLeft, child: Text('${r['label']}', style: AppText.s(phone ? 12 : 12.5, W.w6, color: AppColors.text2))),
              ),
          ]),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            if (c.maxWidth >= 640) return track(c.maxWidth);
            return SingleChildScrollView(scrollDirection: Axis.horizontal, child: track(640));
          }),
        ),
      ]),
    );
  }

  static DateTime? _day(Object? v) {
    final t = cpParse(v);
    return t == null ? null : DateTime(t.year, t.month, t.day);
  }

  Widget _bar(Map b, double w, double Function(DateTime) pct, DateTime to, {required double top}) {
    final s = _day(b['start']);
    if (s == null) return const SizedBox.shrink();
    final e = _day(b['end']) ?? to;
    final left = w * pct(s);
    final right = w * pct(e.add(const Duration(days: 1)));
    final width = (right - left).clamp(6.0, w);
    final status = '${b['status']}';
    final (bg, fg) = switch (status) {
      'cur' => (AppColors.accent, AppColors.white),
      'done' => (AppColors.hgDone, AppColors.okText),
      'next' => (AppColors.white, AppColors.accentText),
      _ => (AppColors.hgOld, AppColors.muted),
    };
    Widget box = Container(
      width: width,
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.all(6)),
      child: CutText('${b['label']}', maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: AppText.s(11.5, W.w7, color: fg, h: 1)),
    );
    if (status == 'next') box = CustomPaint(foregroundPainter: const CpDashedBox(AppColors.accent, radius: 6), child: box);
    return Positioned(left: left, top: top, child: AppTooltip(message: '${b['tip'] ?? b['label']}', child: box));
  }
}

/// The key under the chart (`.hg-key`): Now · Completed · Replaced · Up next · Today.
class CpPlansKey extends StatelessWidget {
  const CpPlansKey({super.key});

  @override
  Widget build(BuildContext context) {
    Widget sw(Widget box, String l) => Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [box, Text(l, style: AppText.s(12, W.w5, color: AppColors.muted))]);
    Widget fill(Color c) => Container(width: 14, height: 8, decoration: BoxDecoration(color: c, borderRadius: AppRadius.all(3)));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Wrap(spacing: 16, runSpacing: 8, children: [
        sw(fill(AppColors.accent), 'Now'),
        sw(fill(AppColors.hgDone), 'Completed'),
        sw(fill(AppColors.hgOld), 'Replaced'),
        sw(const CustomPaint(painter: CpDashedBox(AppColors.accent, radius: 3), size: Size(14, 8)), 'Up next'),
        sw(Container(width: 2, height: 12, color: AppColors.hgToday), 'Today'),
      ]),
    );
  }
}

/// 1px dashed rounded outline (`border: 1px dashed`).
class CpDashedBox extends CustomPainter {
  const CpDashedBox(this.color, {this.radius = 6, this.dash = 3, this.gap = 2});
  final Color color;
  final double radius, dash, gap;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(.5));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += dash + gap) {
        canvas.drawPath(m.extractPath(d, (d + dash).clamp(0, m.length)), p);
      }
    }
  }

  @override
  bool shouldRepaint(CpDashedBox old) => old.color != color || old.radius != radius;
}
