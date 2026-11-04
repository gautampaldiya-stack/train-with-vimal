import 'package:flutter/material.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../food/food_model.dart' show DateUtils0, fdWd;
import '../food/food_parts.dart' show NumStepper;
import '../home/home_model.dart' show glasses, inNum, litres;
import '../home/home_parts.dart';

/// Water, one place for every page (Probid 2026-11-03): the card (Food page and Home), the "Log water" sheet (the
/// day's total in ml; Food, Home and Habits) and the History sheet.

/// The water card: amount drunk, a glass bar, the History icon and "Log water" (today and yesterday only).
class WaterCard extends StatelessWidget {
  const WaterCard({
    super.key,
    required this.assigned,
    required this.ml,
    required this.goal,
    required this.onLog,
    required this.onHistory,
    this.when = 'today',
    this.canLog = true,
  });
  final bool assigned, canLog;
  final int ml, goal;
  final String when;
  final VoidCallback onLog, onHistory;

  @override
  Widget build(BuildContext context) {
    // No water habit from the coach: the card only says so (Probid A10).
    if (!assigned) {
      return ChCard(children: [
        const ChHead(lead: ChIcon(AppIcons.water, tone: ChTone.warm), title: 'Water', sub: 'Water habit is not assigned to you yet'),
        Text('Your coach sets your water target. Ask them in your check-in if you want to track water.',
            style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.45)),
      ]);
    }
    final gl = (ml / 250).round(), leftG = ((goal - ml) / 250).ceil().clamp(0, 999);
    final bars = (goal / 250).round().clamp(4, 20);
    return ChCard(children: [
      ChHead(
        lead: const ChIcon(AppIcons.water, tone: ChTone.warm),
        title: 'Water',
        sub: ml >= goal ? 'Goal complete $when · nice work' : '${litres(goal - ml)} to go $when · ${glasses(leftG)} more',
        // one tap straight to History (Probid 2026-11-03)
        action: CaIconBtn(AppIcons.clock, tooltip: 'Water history', onTap: onHistory),
      ),
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 6, children: [
        Text(litres(ml), style: AppText.s(30, W.w8, ls: -0.6)),
        Flexible(child: Text('drunk $when · target ${litres(goal)} (${glasses((goal / 250).round())})', style: AppText.s(13, W.w6, color: AppColors.muted))),
      ]),
      Pull(
        top: 4,
        child: Row(spacing: 5, children: [
          for (var i = 0; i < bars; i++)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 8,
                decoration: BoxDecoration(color: i < gl ? AppColors.warm : AppColors.barTrack, borderRadius: BorderRadius.circular(8)),
              ),
            ),
        ]),
      ),
      // like meals, only today and yesterday can be logged (Probid 2026-11-03)
      if (canLog) Row(children: [chSm('Log water', onLog, icon: AppIcons.water, kind: CaBtnKind.dark)]),
    ]);
  }
}

/// The unit the client last picked in the Log water sheet (L or ml); the server always stores ml.
bool waterInLitres = false;

/// "Log water": a L / ml switch, then − / the day's total / + (250 ml a glass, 0.25 L in litres), a tap on the amount
/// types it; Save calls [save] with the new total in ml and shows the toast (Undo saves the old total).
/// [when] is "today" or a day name.
Future<void> showWaterSheet(BuildContext context, {required String when, required int goal, required int current, required void Function(int ml) save}) {
  final v = ValueNotifier(current.toDouble());
  final unitL = ValueNotifier(waterInLitres);
  final on = when == 'today' ? 'today' : 'on $when';
  String lit(double l) => l == l.roundToDouble() ? l.toStringAsFixed(0) : l.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  return showAppSheet(
    context,
    listen: Listenable.merge([v, unitL]),
    owns: [v, unitL],
    title: 'Water · $when',
    sub: 'Target ${litres(goal)} · set by your coach',
    webWidth: 420,
    footerStretch: true,
    builder: (_) {
      final n = v.value.round();
      final inL = unitL.value;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        Center(
          child: WaterUnitSwitch(
            litres: inL,
            onPick: (l) {
              unitL.value = l;
              waterInLitres = l;
            },
          ),
        ),
        if (inL)
          NumStepper(
            key: const ValueKey('water-l'),
            value: v.value / 1000,
            step: .25,
            min: 0,
            max: 10,
            big: true,
            name: 'Water in litres',
            label: (x) => '${lit(x)} L',
            onChanged: (x) => v.value = (x * 1000).roundToDouble(),
          )
        else
          NumStepper(
            key: const ValueKey('water-ml'),
            value: v.value,
            step: 250,
            min: 0,
            max: 10000,
            big: true,
            decimals: false,
            name: 'Water in ml',
            label: (x) => '${inNum(x.round())} ml',
            onChanged: (x) => v.value = x,
          ),
        Text(n >= goal ? 'Goal complete · ${glasses((n / 250).round())}' : '${litres(goal - n)} to go · ${glasses(((goal - n) / 250).ceil())} more',
            textAlign: TextAlign.center, style: AppText.s(12.5, W.w6, color: AppColors.muted)),
        Text(inL ? 'One glass = 0.25 L. Tap the amount to type it.' : 'One glass = 250 ml. Tap the amount to type it.', textAlign: TextAlign.center, style: AppText.s(12, W.w5, color: AppColors.muted)),
      ]);
    },
    footer: (ctx) => [
      Row(spacing: 8, children: [
        Expanded(child: CaButton('Cancel', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop())),
        Expanded(
          child: CaButton('Save', icon: AppIcons.check, onPressed: () {
            final was = current, now = v.value.round();
            Navigator.of(ctx).pop();
            if (now == was) return;
            save(now);
            if (now >= goal && was < goal) {
              showToast(context, 'Water goal complete!', sub: '${litres(now)} $on', kind: ToastKind.star, action: 'Undo', onAction: () => save(was));
            } else {
              showToast(context, '${litres(now)} logged $on', sub: now >= goal ? 'Goal complete' : '${litres(goal - now)} to go', kind: ToastKind.water,
                  action: 'Undo', onAction: () => save(was));
            }
          }),
        ),
      ]),
    ],
  );
}

/// The L / ml switch on the Log water sheet.
class WaterUnitSwitch extends StatelessWidget {
  const WaterUnitSwitch({super.key, required this.litres, required this.onPick});
  final bool litres;
  final ValueChanged<bool> onPick;

  @override
  Widget build(BuildContext context) {
    Widget opt(String t, bool l) {
      final on = litres == l;
      return Semantics(
        button: true,
        selected: on,
        label: l ? 'Litres' : 'Millilitres',
        child: Hover(
          onTap: on ? null : () => onPick(l),
          builder: (_, _, _) => AnimatedContainer(
            duration: Motion.of(context, Motion.short),
            curve: Motion.curve,
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.white : null,
              borderRadius: BorderRadius.circular(9),
              boxShadow: on ? const [BoxShadow(color: Color(0x14171717), blurRadius: 2, offset: Offset(0, 1)), BoxShadow(color: AppColors.line, spreadRadius: 1)] : null,
            ),
            child: Text(t, style: AppText.s(13, W.w8, color: on ? AppColors.skyMid : AppColors.muted)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [opt('L', true), opt('ml', false)]),
    );
  }
}

/// Water card → History: this week and the 3 before.
Future<void> showWaterHistorySheet(BuildContext context) async {
  final Map<String, dynamic> h;
  try {
    h = await Services.api.get<Map<String, dynamic>>('me/food-log/water-history/?weeks=4');
  } on ApiError catch (e) {
    if (context.mounted) {
      showToast(context, e.offline ? 'You are offline' : 'Could not load water history', sub: e.offline ? 'Try again when you are online' : e.message, kind: ToastKind.err);
    }
    return;
  }
  if (!context.mounted) return;
  final goal = (h['goal_ml'] as num?)?.toInt() ?? 3000;
  final weeks = (h['weeks'] as List? ?? []).cast<Map>();
  await showAppSheet(
    context,
    title: 'Water history',
    sub: 'Target ${litres(goal)} a day (${glasses((goal / 250).round())}) · set by your coach',
    webWidth: 560,
    builder: (_) => WaterHistory(goal: goal, weeks: weeks, today: DateUtils0.dateOnly(DateTime.now())),
  );
}

/// Water history sheet (Probid 2026-11-03 redesign): this week's numbers, then each week as a light bar chart, thin
/// rounded bars, a dashed target line, the value only where water was logged, today's letter marked. Older weeks are
/// folded, tap to open.
class WaterHistory extends StatefulWidget {
  const WaterHistory({super.key, required this.goal, required this.weeks, required this.today});
  final int goal;
  final List<Map> weeks;
  final DateTime today;

  @override
  State<WaterHistory> createState() => _WaterHistoryState();
}

class _WaterHistoryState extends State<WaterHistory> {
  final _open = <int>{0}; // this week open; every other week folded, with its own summary line and dots

  static Color get _water => AppColors.skyMid;

  String _range(DateTime mon) {
    final end = mon.add(const Duration(days: 6));
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return mon.month == end.month ? '${mon.day}–${end.day} ${mo[end.month - 1]}' : '${mon.day} ${mo[mon.month - 1]} – ${end.day} ${mo[end.month - 1]}';
  }

  int _past(Map w) => (w['days'] as List).where((x) => (x as Map)['future'] != true).length;

  Widget _stat(String v, String l, {Color? ink}) => Expanded(
        child: Column(spacing: 2, children: [
          Text(v, style: AppText.s(18, W.w8, tabular: true, color: ink ?? AppColors.text)),
          Text(l, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
        ]),
      );

  Widget _summary(Map w) {
    final hit = w['goal_days'] as int? ?? 0, n = _past(w);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: AppColors.skyFade, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.skySoft)),
      child: IntrinsicHeight(
        child: Row(children: [
          _stat(litres((w['avg_ml'] as num? ?? 0).toInt()), 'avg a day', ink: _water),
          const VerticalDivider(width: 1, thickness: 1, color: AppColors.skySoft),
          _stat('$hit of $n', 'days on target', ink: hit > 0 ? AppColors.okText : null),
          const VerticalDivider(width: 1, thickness: 1, color: AppColors.skySoft),
          _stat(litres((w['total_ml'] as num? ?? 0).toInt()), 'this week total'),
        ]),
      ),
    );
  }

  /// Today and yesterday on top, each with its litres against the target.
  Widget _days(List<Map> ws) {
    final all = {for (final w in ws) for (final d in (w['days'] as List).cast<Map>()) '${d['date']}': (d['ml'] as num? ?? 0).toInt()};
    String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    Widget tile(String label, int ml) {
      final hit = ml >= widget.goal;
      return Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(color: hit ? AppColors.okBg : AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: hit ? AppColors.okBg : AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
            Row(children: [
              Expanded(child: Text(label, style: AppText.s(12, W.w7, color: AppColors.muted))),
              if (hit) const AppIcon(AppIcons.checkCircle, size: 15, color: AppColors.okText),
            ]),
            Text.rich(TextSpan(children: [
              TextSpan(text: litres(ml), style: AppText.s(18, W.w8, color: hit ? AppColors.okText : _water)),
              TextSpan(text: ' / ${litres(widget.goal)}', style: AppText.s(12, W.w6, color: AppColors.muted)),
            ])),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (ml / widget.goal).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: AppColors.sub,
                color: hit ? AppColors.okSolid : _water,
              ),
            ),
          ]),
        ),
      );
    }

    return Row(spacing: 10, children: [
      tile('Today', all[key(widget.today)] ?? 0),
      tile('Yesterday', all[key(widget.today.subtract(const Duration(days: 1)))] ?? 0),
    ]);
  }

  Widget _chart(Map w) {
    final goal = widget.goal;
    final days = (w['days'] as List).cast<Map>();
    final top = days.fold<int>(goal, (a, d) => ((d['ml'] as num? ?? 0).toInt()).clamp(a, 1 << 30));
    const h = 92.0;
    final goalY = h * (1 - goal / top);
    return SizedBox(
      height: h + 36,
      child: Stack(children: [
        Positioned(left: 0, right: 0, top: 16 + h, child: Container(height: 1, color: AppColors.line)),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final d in days)
            Expanded(
              child: LayoutBuilder(builder: (_, box) {
                final bw = (box.maxWidth * .62).clamp(14.0, 40.0);
                final v = (d['ml'] as num? ?? 0).toInt();
                final fut = d['future'] == true;
                final day = DateTime.parse('${d['date']}');
                final today = DateUtils0.same(day, widget.today);
                final hit = v >= goal;
                return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  SizedBox(
                    height: 16,
                    child: v > 0
                        ? Text((v / 1000).toStringAsFixed(1), style: AppText.s(11, W.w8, tabular: true, color: hit ? AppColors.okText : AppColors.text2))
                        : null,
                  ),
                  SizedBox(
                    height: h,
                    child: Container(
                      width: bw,
                      alignment: Alignment.bottomCenter,
                      decoration: BoxDecoration(color: fut ? null : AppColors.skySoft.withValues(alpha: .6), borderRadius: BorderRadius.circular(7)),
                      child: v > 0
                          ? Container(
                              width: bw,
                              height: (h * v / top).clamp(6.0, h),
                              decoration: BoxDecoration(color: hit ? AppColors.okSolid : _water, borderRadius: BorderRadius.circular(7)),
                            )
                          : Container(
                              width: bw,
                              height: 6,
                              decoration: BoxDecoration(color: fut ? null : AppColors.skySoft, borderRadius: BorderRadius.circular(7)),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 22,
                    height: 14,
                    alignment: Alignment.center,
                    decoration: today ? BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(7)) : null,
                    child: Text(fdWd[day.weekday - 1].substring(0, 1),
                        style: AppText.s(11, W.w7, color: today ? AppColors.accentText : (fut ? AppColors.line2 : AppColors.muted))),
                  ),
                ]);
              }),
            ),
        ]),
        // the dashed target line, drawn over the bar tracks so it stays visible
        Positioned(left: 0, right: 0, top: 16 + goalY, child: IgnorePointer(child: CustomPaint(size: const Size.fromHeight(1), painter: _Dash(AppColors.okSolid)))),
      ]),
    );
  }

  Widget _week(int i, Map w) {
    final mon = DateTime.parse('${w['start']}');
    final open = _open.contains(i);
    final name = i == 0 ? 'This week' : i == 1 ? 'Last week' : null;
    final hit = w['goal_days'] as int? ?? 0, n = _past(w);
    final head = Row(spacing: 8, children: [
      Expanded(
        child: Text.rich(TextSpan(children: [
          TextSpan(text: name ?? _range(mon), style: AppText.s(14, W.w8)),
          if (name != null) TextSpan(text: ' · ${_range(mon)}', style: AppText.s(12, W.w6, color: AppColors.muted)),
        ])),
      ),
      Text.rich(TextSpan(children: [
        TextSpan(text: 'avg ${litres((w['avg_ml'] as num? ?? 0).toInt())}', style: AppText.s(12.5, W.w8, color: _water)),
        TextSpan(text: ' · $hit of $n days', style: AppText.s(12, W.w6, color: hit > 0 ? AppColors.okText : AppColors.muted)),
      ])),
      AnimatedRotation(
        turns: open ? .5 : 0,
        duration: Motion.of(context, Motion.short),
        curve: Motion.curve,
        child: AppIcon(AppIcons.chevronDown, size: 16, color: open ? AppColors.skyMid : AppColors.muted),
      ),
    ]);
    // folded: one small dot a day, so each week still shows how it went
    Widget dots() => Row(spacing: 6, children: [
          for (final d in (w['days'] as List).cast<Map>())
            Builder(builder: (_) {
              final v = (d['ml'] as num? ?? 0).toInt();
              final fut = d['future'] == true;
              return Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fut ? null : (v >= widget.goal ? AppColors.okSolid : (v > 0 ? _water.withValues(alpha: .35 + .65 * (v / widget.goal).clamp(0.0, 1.0)) : AppColors.sub)),
                  border: fut ? Border.all(color: AppColors.line) : null,
                ),
              );
            }),
          const SizedBox(width: 2),
          Text('total ${litres((w['total_ml'] as num? ?? 0).toInt())}', style: AppText.s(11.5, W.w6, color: AppColors.muted)),
        ]);
    // An open week sits on its own light-blue panel with a border, so it stands apart from the folded ones
    // around it (Probid 2026-11-04: "sab white hai to pata nahi chalta").
    return Padding(
      padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.short),
        curve: Motion.curve,
        padding: open ? const EdgeInsets.fromLTRB(12, 12, 12, 8) : const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: open ? AppColors.skyFade : AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: open ? AppColors.skySoft : AppColors.line, width: open ? 1.5 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
          Hover(onTap: () => setState(() => open ? _open.remove(i) : _open.add(i)), builder: (_, _, _) => head),
          if (open) ...[
            Container(height: 1, color: AppColors.skySoft),
            _chart(w),
          ] else
            dots(),
        ]),
      ),
    );
  }

  Widget _key(Widget mark, String t) => Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
        mark,
        Text(t, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
      ]);

  @override
  Widget build(BuildContext context) {
    final ws = widget.weeks;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      if (ws.isNotEmpty) _days(ws),
      if (ws.isNotEmpty) _summary(ws.first),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final (i, w) in ws.indexed) _week(i, w)]),
      Wrap(alignment: WrapAlignment.center, spacing: 14, runSpacing: 6, children: [
        _key(SizedBox(width: 16, child: CustomPaint(size: const Size.fromHeight(1), painter: _Dash(AppColors.okSolid))), '${litres(widget.goal)} target'),
        _key(Container(width: 10, height: 10, decoration: BoxDecoration(color: _water, borderRadius: BorderRadius.circular(5))), 'below target'),
        _key(Container(width: 10, height: 10, decoration: BoxDecoration(color: AppColors.okSolid, borderRadius: BorderRadius.circular(5))), 'target reached'),
      ]),
    ]);
  }
}

class _Dash extends CustomPainter {
  _Dash(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, 0), Offset((x + 4).clamp(0, size.width), 0), p);
    }
  }

  @override
  bool shouldRepaint(_Dash old) => old.color != color;
}
