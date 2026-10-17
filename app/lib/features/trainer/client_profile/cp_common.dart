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
import '../../../core/widgets/select.dart';

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

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: AppSelect(
          value.label,
          icon: AppIcons.calendar,
          entries: [
            for (final r in CpRange.fixed) MenuEntry(r.label, selected: r.value == value.value, onTap: () => onChanged(r)),
            for (final (id, n) in plans) MenuEntry('Plan: $n', selected: value.value == 'plan:$id', onTap: () => onChanged(CpRange('plan:$id', 'Plan: $n'))),
            MenuEntry('Custom dates…', selected: value.value == 'custom', onTap: () => _custom(context)),
          ],
        ),
      );

  Future<void> _custom(BuildContext context) async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: value.from != null && value.to != null ? DateTimeRange(start: value.from!, end: value.to!) : null,
    );
    if (r == null) return;
    final f = DateFormat('d MMM');
    onChanged(CpRange('custom', '${f.format(r.start)} – ${f.format(r.end)}', from: r.start, to: r.end));
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
