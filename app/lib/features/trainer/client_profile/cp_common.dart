import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tooltip.dart';

// Shared pieces of the Client profile tabs (boards `TrainerClientProfile` / `…Mobile`).

/// "12 Jan" / "Sun, 4 Oct" / "12 Jan 2026" from an ISO date or date-time.
DateTime? cpParse(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
String cpDm(Object? v) => cpParse(v) == null ? '—' : DateFormat('d MMM').format(cpParse(v)!);
String cpDay(Object? v) => cpParse(v) == null ? '—' : DateFormat('EEE, d MMM').format(cpParse(v)!);
String cpDmy(Object? v) => cpParse(v) == null ? '—' : DateFormat('d MMM yyyy').format(cpParse(v)!);
String cpTime(Object? v) => cpParse(v) == null ? '' : DateFormat('h:mm a').format(cpParse(v)!).toLowerCase();

/// "2 days ago", "3 h ago", "yesterday"; older than 2 months → "12 Jan 2026".
String cpAgo(Object? iso) {
  final t = cpParse(iso);
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 14) return '${d.inDays} days ago';
  if (d.inDays < 60) return '${d.inDays ~/ 7} weeks ago';
  return cpDmy(iso);
}

/// "71.2 kg", "68 kg" (one decimal, no ".0" unless [keep]).
String cpKg(Object? v, {bool keep = false, String unit = 'kg'}) {
  final d = v is num ? v.toDouble() : double.tryParse('$v');
  if (d == null) return '—';
  final s = d.toStringAsFixed(1);
  return '${!keep && s.endsWith('.0') ? s.substring(0, s.length - 2) : s} $unit';
}

/// "−3.6 kg" with a real minus sign.
String cpSigned(num v, String unit) => '${v < 0 ? '−' : '+'}${cpKg(v.abs(), keep: true, unit: unit)}';

/// `.card` with the `.card-h` header (title, small grey line, link or button on the right).
class CpCard extends StatelessWidget {
  const CpCard({super.key, required this.title, this.sub, this.action, this.count, required this.child, this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 18)});
  final String title;
  final String? sub;
  final Widget? action;
  final int? count;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHeader(title, sub: sub, action: action, count: count == null ? null : AppCount(count!)),
          Padding(padding: padding, child: child),
        ]),
      );
}

/// Blue text link (`a`, 13 / 700): "Edit", "Open progress", "All notes".
class CpLink extends StatelessWidget {
  const CpLink(this.label, {super.key, required this.onTap});
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Text(label, style: AppText.s(13, W.w7, color: h ? AppColors.linkHover : AppColors.accent)),
      );
}

/// `.cp-g` label / value grid with a line under each pair: "Age" over "29". [warn] values are amber.
class CpKvGrid extends StatelessWidget {
  const CpKvGrid(this.items, {super.key, this.columns = 3});
  final List<(String, String, {bool warn})> items;
  final int columns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, b) {
        final cols = context.isPhone ? 2 : columns;
        const gap = 20.0;
        final w = (b.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, children: [
          for (final it in items)
            Container(
              width: w,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
                Text(it.$1, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
                Text(it.$2, style: AppText.s(14, W.w7, color: it.warn ? AppColors.amberText : AppColors.text)),
              ]),
            ),
        ]);
      });
}

/// Small round icon tile used on rows (`.cp-ic`): sub background, muted icon.
Widget cpIcon(AppIconData icon, {Color bg = AppColors.sub, Color fg = AppColors.text2, double size = 32}) =>
    IconTile(icon, size: size, bg: bg, fg: fg, radius: 8, iconSize: 16);

/// The range picker on every chart and log (`.cp-range`): Last 7 / 30 / 90 days, Last 6 months, Since start,
/// one row per plan, Custom dates…. [value] is the API's `range` (7d, 30d, 90d, 6m, start, `plan:<id>`, custom).
class CpRange {
  const CpRange(this.value, this.label, {this.from, this.to});
  final String value, label;
  final DateTime? from, to;

  Map<String, dynamic> get query => {
        'range': value,
        if (value == 'custom' && from != null) 'from': DateFormat('yyyy-MM-dd').format(from!),
        if (value == 'custom' && to != null) 'to': DateFormat('yyyy-MM-dd').format(to!),
      };

  static const fixed = [CpRange('7d', 'Last 7 days'), CpRange('30d', 'Last 30 days'), CpRange('90d', 'Last 90 days'), CpRange('6m', 'Last 6 months'), CpRange('start', 'Since start')];
}

class CpRangePicker extends StatelessWidget {
  /// [plans] = (assignment id, name) of the client's workout plans, shown as "Plan: `name`".
  const CpRangePicker({super.key, required this.value, required this.onChanged, this.plans = const [], this.width = 160});
  final CpRange value;
  final ValueChanged<CpRange> onChanged;
  final List<(String, String)> plans;
  final double width;

  List<MenuEntry> _entries(BuildContext context) => [
        for (final r in CpRange.fixed) MenuEntry(r.label, selected: r.value == value.value, onTap: () => onChanged(r)),
        for (final (id, n) in plans) MenuEntry('Plan: $n', selected: value.value == 'plan:$id', onTap: () => onChanged(CpRange('plan:$id', 'Plan: $n'))),
        MenuEntry('Custom dates…', selected: value.value == 'custom', onTap: () => _custom(context)),
      ];

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Builder(
          builder: (b) => Hover(
            // Phone: the action sheet shows every label in full. Wider screens: a menu at least 260 wide, so
            // "Plan: …" and "Custom dates…" are not cut; a long plan name ends in "…" with the full name on hover.
            onTap: () => b.isPhone ? showActionSheet(b, _entries(context)) : cpShowMenu(b, _entries(context), minWidth: 260),
            builder: (_, h, _) => Container(
              height: 36,
              padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: AppRadius.all(AppRadius.input),
                border: Border.all(color: h ? AppColors.lineHover : AppColors.line2),
              ),
              child: Row(spacing: 8, children: [
                const AppIcon(AppIcons.calendar, size: 15, color: AppColors.text2),
                Expanded(child: Text(value.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w6))),
                const AppIcon(AppIcons.chevronDown, size: 16, color: AppColors.muted),
              ]),
            ),
          ),
        ),
      );

  Future<void> _custom(BuildContext context) async {
    final r = await showCpDateRange(context, initial: value.from != null && value.to != null ? DateTimeRange(start: value.from!, end: value.to!) : null);
    if (r == null) return;
    onChanged(CpRange('custom', cpRangeLabel(r), from: r.start, to: r.end));
  }
}

/// "12 Sep – 30 Sep" (with the year when it is not this year).
String cpRangeLabel(DateTimeRange r) {
  final y = DateTime.now().year;
  final f = DateFormat(r.start.year == y && r.end.year == y ? 'd MMM' : 'd MMM yy');
  return '${f.format(r.start)} – ${f.format(r.end)}';
}

/// A `.menu` under [anchor] at least [minWidth] wide (wider than its button when the labels need it). Every row
/// is one line; a cut label shows in full on hover. Tall lists get the room on that side and scroll.
Future<void> cpShowMenu(BuildContext anchor, List<MenuEntry> entries, {double minWidth = 220}) async {
  final box = anchor.findRenderObject() as RenderBox;
  final overlay = Overlay.of(anchor, rootOverlay: true).context.findRenderObject() as RenderBox;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final size = overlay.size;
  final width = (box.size.width < minWidth ? minWidth : box.size.width).clamp(0.0, size.width - 16);
  const rowH = 37.0;
  final below = topLeft.dy + box.size.height + 6;
  final need = 12 + rowH * entries.length;
  final roomBelow = size.height - below - 12, roomAbove = topLeft.dy - 6 - 12;
  final openUp = need > roomBelow && roomAbove > roomBelow;
  final maxH = (openUp ? roomAbove : roomBelow).clamp(need < 120 ? need : 120.0, need);
  await showGeneralDialog(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: 'menu',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 90),
    transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (ctx, _, _) => Stack(children: [
      Positioned(
        left: topLeft.dx.clamp(8.0, size.width - width - 8),
        top: openUp ? null : below,
        bottom: openUp ? size.height - topLeft.dy + 6 : null,
        width: width,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(6),
            constraints: BoxConstraints(maxHeight: maxH),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.menu), border: Border.all(color: AppColors.line), boxShadow: AppShadows.menu),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 3, children: [
                for (final e in entries) _CpMenuRow(e, close: () => Navigator.of(ctx).pop()),
              ]),
            ),
          ),
        ),
      ),
    ]),
  );
}

class _CpMenuRow extends StatelessWidget {
  const _CpMenuRow(this.e, {required this.close});
  final MenuEntry e;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    if (e.separator) return Container(height: 1, color: AppColors.line, margin: const EdgeInsets.symmetric(vertical: 3));
    if (e.header) return Padding(padding: const EdgeInsets.fromLTRB(10, 6, 10, 2), child: Text(e.label.toUpperCase(), style: AppText.over));
    final style = AppText.s(13.5, e.selected ? W.w7 : W.w5);
    final row = Hover(
      onTap: e.onTap == null
          ? null
          : () {
              close();
              e.onTap!();
            },
      builder: (_, h, _) => Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: h ? AppColors.sub : null, borderRadius: AppRadius.all(AppRadius.item)),
        child: Row(spacing: 10, children: [
          Expanded(child: Text(e.label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: style)),
          if (e.selected) AppIcon(AppIcons.check, size: 15, color: AppColors.accent, stroke: 2.2),
        ]),
      ),
    );
    return LayoutBuilder(builder: (context, b) {
      final tp = TextPainter(text: TextSpan(text: e.label, style: style), maxLines: 1, textDirection: Directionality.of(context))..layout();
      final cut = tp.width > b.maxWidth - 20 - (e.selected ? 25 : 0);
      tp.dispose();
      return cut ? AppTooltip(message: e.label, side: TipSide.right, child: row) : row;
    });
  }
}

/// "Custom dates…": a compact modal (bottom sheet on phone) with a month calendar — two months side by side
/// when there is room. Tap the first day, then the last; Apply returns the range.
Future<DateTimeRange?> showCpDateRange(BuildContext context, {DateTimeRange? initial, DateTime? first, DateTime? last}) {
  final today = DateUtils.dateOnly(DateTime.now());
  final pick = ValueNotifier<(DateTime?, DateTime?)>((initial?.start, initial?.end));
  final lastDay = last ?? today;
  final firstDay = first ?? DateTime(today.year - 5, today.month);
  return showAppModal<DateTimeRange>(
    context,
    title: 'Custom dates',
    body: 'Pick the first day, then the last day.',
    icon: AppIcons.calendar,
    width: 600,
    content: (_) => _CpRangeCalendar(pick: pick, first: firstDay, last: lastDay),
    actions: (ctx) => [
      AppButton('Cancel', onPressed: () => Navigator.of(ctx).pop(), expand: ctx.isPhone),
      ValueListenableBuilder(
        valueListenable: pick,
        builder: (_, p, _) => AppButton.primary('Apply', expand: ctx.isPhone,
            onPressed: p.$1 == null ? null : () => Navigator.of(ctx).pop(DateTimeRange(start: p.$1!, end: p.$2 ?? p.$1!))),
      ),
    ],
  );
}

class _CpRangeCalendar extends StatefulWidget {
  const _CpRangeCalendar({required this.pick, required this.first, required this.last});
  final ValueNotifier<(DateTime?, DateTime?)> pick;
  final DateTime first, last;
  @override
  State<_CpRangeCalendar> createState() => _CpRangeCalendarState();
}

class _CpRangeCalendarState extends State<_CpRangeCalendar> {
  /// The month on the right (or the only month on a narrow screen).
  late DateTime month = DateTime((widget.pick.value.$2 ?? widget.last).year, (widget.pick.value.$2 ?? widget.last).month);

  (DateTime?, DateTime?) get p => widget.pick.value;

  void _tap(DateTime d) {
    final (a, b) = p;
    widget.pick.value = a == null || b != null ? (d, null) : (d.isBefore(a) ? (d, a) : (a, d));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final two = box.maxWidth >= 520;
        final months = [if (two) DateTime(month.year, month.month - 1), month];
        final canBack = DateTime(months.first.year, months.first.month).isAfter(DateTime(widget.first.year, widget.first.month));
        final canNext = month.isBefore(DateTime(widget.last.year, widget.last.month));
        final (a, b) = p;
        final days = a == null ? 0 : (b ?? a).difference(a).inDays + 1;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
            for (final (i, m) in months.indexed)
              Expanded(
                child: _month(m,
                    back: i == 0 && canBack ? () => setState(() => month = DateTime(month.year, month.month - 1)) : null,
                    next: i == months.length - 1 && canNext ? () => setState(() => month = DateTime(month.year, month.month + 1)) : null,
                    showBack: i == 0, showNext: i == months.length - 1),
              ),
          ]),
          Text(a == null ? 'No days picked yet' : '${cpRangeLabel(DateTimeRange(start: a, end: b ?? a))} · $days day${days == 1 ? '' : 's'}',
              style: AppText.s(12.5, W.w6, color: a == null ? AppColors.muted : AppColors.text2)),
        ]);
      });

  Widget _month(DateTime m, {VoidCallback? back, VoidCallback? next, bool showBack = false, bool showNext = false}) {
    final (a, b) = p;
    final lead = DateTime(m.year, m.month).weekday - 1; // Monday first
    final n = DateUtils.getDaysInMonth(m.year, m.month);
    Widget arrow(AppIconData ic, String tip, VoidCallback? on, bool show) =>
        show ? AppIconButton(ic, tooltip: tip, small: true, ghost: true, onPressed: on) : const SizedBox(width: 30, height: 30);
    return Column(spacing: 6, children: [
      Row(children: [
        arrow(AppIcons.chevronLeft, 'Previous month', back, showBack),
        Expanded(child: Text(DateFormat('MMMM yyyy').format(m), textAlign: TextAlign.center, style: AppText.s(13.5, W.w7))),
        arrow(AppIcons.chevronRight, 'Next month', next, showNext),
      ]),
      Row(children: [
        for (final w in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
          Expanded(child: Text(w, textAlign: TextAlign.center, style: AppText.s(11.5, W.w6, color: AppColors.muted))),
      ]),
      for (var row = 0; row * 7 < lead + n; row++)
        Row(children: [
          for (var col = 0; col < 7; col++)
            Expanded(
              child: () {
                final i = row * 7 + col - lead + 1;
                if (i < 1 || i > n) return const SizedBox(height: 34);
                final d = DateTime(m.year, m.month, i);
                final off = d.isAfter(widget.last) || d.isBefore(widget.first);
                final end = b ?? a;
                final isEdge = d == a || d == end;
                final inside = a != null && end != null && d.isAfter(a) && d.isBefore(end);
                final today = d == DateUtils.dateOnly(DateTime.now());
                return Hover(
                  onTap: off ? null : () => _tap(d),
                  builder: (_, h, _) => Container(
                    height: 34,
                    margin: const EdgeInsets.symmetric(vertical: 1),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isEdge ? AppColors.accent : (inside ? AppColors.accentSoft : (h && !off ? AppColors.sub : null)),
                      borderRadius: AppRadius.all(AppRadius.item),
                      border: today && !isEdge ? Border.all(color: AppColors.line2) : null,
                    ),
                    child: Text('$i',
                        style: AppText.s(13, isEdge ? W.w7 : W.w5,
                            color: isEdge ? AppColors.white : (off ? AppColors.line2 : (inside ? AppColors.accentText : AppColors.text)), tabular: true)),
                  ),
                );
              }(),
            ),
        ]),
    ]);
  }
}

/// Tone of a status word used across the tabs (Done / Partly / Missed / Waiting / Current …).
Tone cpTone(String s) => switch (s.toLowerCase()) {
      'done' || 'completed' || 'filled' || 'signed' || 'current' || 'on time' || 'reviewed' => Tone.ok,
      'partly' || 'partial' || 'waiting' || 'due' || 'replaced' || 'to review' => Tone.warn,
      'missed' || 'skipped' || 'overdue' || 'ended' => Tone.bad,
      'up next' || 'sent' || 'new' => Tone.info,
      _ => Tone.neutral,
    };

/// Loading spinner used while a tab fetches.
class CpLoading extends StatelessWidget {
  const CpLoading({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))),
      );
}

/// Error card with Try again.
class CpError extends StatelessWidget {
  const CpError(this.message, {super.key, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => AppCard(child: EmptyState('Could not load this', sub: message, action: AppButton('Try again', onPressed: onRetry)));
}

/// Two columns on wide screens (main 1fr / side 1fr or a fixed side), one column on phone and tablet.
class CpColumns extends StatelessWidget {
  const CpColumns({super.key, required this.left, required this.right, this.rightFlex = 1, this.leftFlex = 1, this.breakpoint = 980});
  final List<Widget> left, right;
  final int leftFlex, rightFlex;
  final double breakpoint;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, b) {
        if (b.maxWidth < breakpoint) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: context.isPhone ? 14 : 16, children: [...left, ...right]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
          Expanded(flex: leftFlex, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: left)),
          Expanded(flex: rightFlex, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: right)),
        ]);
      });
}
