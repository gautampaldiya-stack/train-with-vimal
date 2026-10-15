import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../home/home_model.dart' show dayShort, hoursMin, inNum;
import '../home/home_parts.dart';
import 'habits_model.dart';

/// Sheets of the Habits & supplements board (`ClientHabits`): Add steps, sleep, habit details,
/// a habit that starts later, supplement details. On wide screens they are centred 520 cards.

String onDay(HabitsData d) => d.isToday ? 'today' : 'on ${dayShort(d.date)}';

/// "Add steps · today" (and any other counter habit).
Future<void> showStepsSheet(BuildContext context, HabitsController c, Habit h) {
  final d = c.data!;
  final steps = h.isSteps;
  final step = steps ? 500 : (h.target / 16).clamp(1, 5000).round();
  final quick = steps ? [1000, 2000, 5000, 10000] : [step, step * 2, step * 4, step * 8];
  final unit = h.unit.isEmpty ? '' : ' ${h.unit}';
  final v = ValueNotifier(h.value);
  return showAppSheet(
    context,
    title: '${steps ? 'Add steps' : 'Add to ${h.name}'} · ${d.isToday ? 'today' : dayShort(d.date)}',
    sub: 'Goal ${h.goal}',
    builder: (_) => ValueListenableBuilder(
      valueListenable: v,
      builder: (_, n, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        ChBigStepper(value: inNum(n), label: h.unit.isEmpty ? 'done' : h.unit, onMinus: () => v.value = (n - step).clamp(0, 200000), onPlus: () => v.value = (n + step).clamp(0, 200000)),
        ChQuick(items: [for (final q in quick) ('+${inNum(q)}', q)], onPick: (q) => v.value = (n + q).clamp(0, 200000)),
        Padding(padding: const EdgeInsets.only(top: 6), child: ChBar(h.target > 0 ? n / h.target : 0, color: AppColors.okSolid, height: 8)),
        Text(n >= h.target ? 'Goal reached' : '${inNum(h.target - n)}$unit to go', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
      ]),
    ),
    footerStretch: true,
    footer: (ctx) => [
      CaButton(steps ? 'Save steps' : 'Save', icon: AppIcons.check, onPressed: () {
        Navigator.of(ctx).pop();
        final before = h.value, n = v.value;
        c.setValue(h, n);
        void undo() => c.setValue(h, before);
        if (n >= h.target && before < h.target) {
          showToast(context, steps ? 'Step goal reached!' : 'Goal reached!', sub: '${inNum(n)}$unit ${onDay(d)}', kind: ToastKind.star, action: 'Undo', onAction: undo);
        } else {
          showToast(context, steps ? 'Steps saved' : 'Saved', sub: '${inNum(n)} of ${inNum(h.target)} ${onDay(d)}', kind: ToastKind.ok, action: 'Undo', onAction: undo);
        }
      }),
    ],
  );
}

/// "How long did you sleep?" for the picked night.
Future<void> showSleepLog(BuildContext context, HabitsController c, Habit h) {
  final d = c.data!;
  final goal = h.target > 0 ? h.target : 420;
  final v = ValueNotifier(h.logged && h.value > 0 ? h.value : goal);
  return showAppSheet(
    context,
    title: 'How long did you sleep?',
    sub: '${d.isToday ? 'Last night' : 'Night before ${dayShort(d.date)}'} · goal ${goal % 60 == 0 ? '${goal ~/ 60} hours' : hoursMin(goal)}',
    builder: (_) => ValueListenableBuilder(
      valueListenable: v,
      builder: (_, n, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        ChBigStepper(
          value: hoursMin(n),
          label: n >= goal ? 'Goal met' : '${hoursMin(goal - n)} short of ${hoursMin(goal)}',
          onMinus: () => v.value = (n - 15).clamp(0, 900),
          onPlus: () => v.value = (n + 15).clamp(0, 900),
        ),
        ChQuick(items: [for (final m in [360, 390, 420, 450, 480]) ('${m % 60 == 0 ? m ~/ 60 : (m / 60).toStringAsFixed(1)} h', m)], onPick: (m) => v.value = m, isOn: (m) => m == n),
      ]),
    ),
    footerStretch: true,
    footer: (ctx) => [
      CaButton('Save sleep', icon: AppIcons.check, onPressed: () {
        Navigator.of(ctx).pop();
        final before = h.value, n = v.value;
        c.setValue(h, n);
        showToast(context, 'Sleep saved',
            sub: '${hoursMin(n)}${n >= goal ? ' · goal met' : ' · aim for ${hoursMin(goal)} tonight'}',
            kind: n >= goal ? ToastKind.ok : ToastKind.info,
            action: 'Undo',
            onAction: () => c.setValue(h, before));
      }),
    ],
  );
}

// ─────────────────────────────── Pieces

/// `hk-cells`: grey stat tiles.
class HkCells extends StatelessWidget {
  const HkCells(this.cells, {super.key, this.big = false});
  final List<(String, String)> cells;
  final bool big;
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        for (final (v, l) in cells)
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: AppColors.cellBg, borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(big ? 18 : 16, W.w8)),
                Text(l, style: AppText.s(11, W.w6, color: AppColors.muted, h: 1.3)),
              ]),
            ),
          ),
      ]);
}

/// `ch-sec sm`: small grey upper-case section title.
Widget hkSec(String t) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(t.toUpperCase(), style: AppText.s(11.5, W.w7, color: AppColors.muted, ls: .46)),
    );

/// `hk-kv`: label left, value right, lines between.
Widget hkKv(List<(String, String)> rows) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, (k, v)) in rows.indexed)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
          child: Row(spacing: 12, children: [
            Text(k, style: AppText.s(13, W.w4, color: AppColors.muted)),
            Expanded(child: Text(v, textAlign: TextAlign.right, style: AppText.s(13, W.w7))),
          ]),
        ),
    ]);

/// `hk-empty` / `hk-warn`: grey or amber note with an icon.
Widget hkNote(AppIconData icon, String text, {bool warn = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: warn ? AppColors.amberBg : AppColors.cellBg, borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: AppIcon(icon, size: 16, color: warn ? AppColors.lowText : AppColors.text2)),
        Expanded(child: Text(text, style: AppText.s(12.5, W.w4, color: warn ? AppColors.lowText : AppColors.text2, h: 1.45))),
      ]),
    );

/// `hk-dots`: one dot a day, letter under it.
class HkDots extends StatelessWidget {
  const HkDots(this.days, {super.key, this.big = false});

  /// (letter, state) with state ok / now / no.
  final List<(String, String)> days;
  final bool big;
  @override
  Widget build(BuildContext context) {
    final s = big ? 18.0 : 12.0;
    final dots = [
      for (final (l, st) in days)
        Column(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
          Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: st == 'ok' ? AppColors.okSolid : (st == 'now' ? AppColors.white : AppColors.missDot),
              border: st == 'now' ? Border.all(color: AppColors.accent, width: 2) : null,
            ),
          ),
          Text(l, style: AppText.s(big ? 11 : 9.5, W.w7, color: AppColors.muted, h: 1)),
        ]),
    ];
    return big
        ? Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: dots))
        : Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: dots);
  }
}

String letter(DateTime d) => const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1];

/// `fd-pill`: small rounded label (green / blue / red / amber / grey).
Widget hkPill(String t, {Color bg = AppColors.sub, Color fg = AppColors.text2, double? width}) => Container(
      height: 22,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(t, maxLines: 1, style: AppText.s(11.5, W.w7, color: fg)),
    );

// ─────────────────────────────── Habit details

Future<void> showHabitDetails(BuildContext context, HabitsController c, Habit h, {required VoidCallback log}) {
  final d = c.data!;
  final coach = (h.setBy ?? 'your coach').split(' ').first;
  final shown = d.isFuture ? null : (h.logged ? h.value : null);
  final soon = h.startsOn;
  final kv = soon != null
      ? [('Target', h.goal), ('Type', h.counter ? 'Number, log it each day' : 'Yes / no, tick each evening'), ('How often', h.how), ('Starts', dayShort(soon))]
      : [('Target', h.goal), ('How often', h.how), if (h.since != null) ('Since', dayShort(h.since!)), if (h.setBy != null) ('Set by', h.setBy!)];
  final n7 = h.last7.where((x) => x.done).length;
  return showAppSheet(
    context,
    title: h.name,
    sub: soon != null
        ? 'Starts ${dayShort(soon)}${h.setBy == null ? '' : ' · set by ${h.setBy}'}'
        : 'Goal ${h.goal} · ${d.isToday || d.isFuture ? 'today' : dayShort(d.date)}: ${shown == null ? 'not logged' : h.fmt(shown)}',
    builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      if (soon == null) ...[
        HkCells([
          (_days(h.streak), 'Current streak'),
          (_days(h.best), 'Best streak'),
          ('$n7 of 7', 'Last 7 days'),
        ]),
        hkSec('Last 7 days'),
        Column(spacing: 6, children: [
          for (final x in h.last7.reversed) _histRow(d, h, x),
        ]),
      ] else
        hkNote(AppIcons.clock,
            'Nothing logged yet. This habit starts on ${dayShort(soon)}. ${h.counter ? 'Log it each day from then.' : 'Each evening, tick it if you did it.'}'),
      hkSec('Target set by $coach'),
      hkKv(kv),
      Text.rich(
        TextSpan(style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.45), children: [
          TextSpan(text: 'Want a different target? Tell $coach in your '),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Hover(
              onTap: () {
                Navigator.of(ctx).pop();
                context.go('/checkins');
              },
              builder: (_, hv, _) => Text('weekly check-in.',
                  style: AppText.s(12.5, W.w7, color: AppColors.accentText).copyWith(decoration: hv ? TextDecoration.underline : null, decorationColor: AppColors.accentText)),
            ),
          ),
        ]),
      ),
    ]),
    footer: (ctx) => soon != null
        ? [_RemindButton(starts: soon)]
        : [
            Row(spacing: 8, children: [
              Expanded(child: CaButton('Close', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop())),
              Expanded(
                child: CaButton(_logLabel(h), onPressed: () {
                  Navigator.of(ctx).pop();
                  log();
                }),
              ),
            ]),
          ],
    footerStretch: true,
  );
}

String _days(int n) => '$n ${n == 1 ? 'day' : 'days'}';

String _logLabel(Habit h) => h.isWater
    ? '+250 ml today'
    : h.isSteps
        ? 'Add steps today'
        : h.isSleep
            ? 'Log sleep'
            : h.counter
                ? 'Add today'
                : 'Tick today';

Widget _histRow(HabitsData d, Habit h, ({DateTime date, bool done, int? value}) x) {
  final today = DateUtils.isSameDay(x.date, d.today);
  final v = x.value;
  final (pill, bg, fg) = x.done
      ? ('Done', AppColors.okBg, AppColors.okText)
      : today
          ? ('Today', AppColors.infoBg, AppColors.infoText)
          : ('Missed', AppColors.badBg, AppColors.badText);
  final ratio = !h.counter ? (x.done ? 1.0 : 0.0) : (h.target > 0 ? (v ?? 0) / h.target : 0.0);
  return Row(spacing: 10, children: [
    SizedBox(width: 50, child: Text(today ? 'Today' : DateFormat('EEE d').format(x.date), style: AppText.s(12.5, W.w6, color: AppColors.muted))),
    Expanded(child: ChBar(ratio, color: x.done ? AppColors.okSolid : (today ? AppColors.amberSolid : AppColors.missBar), height: 6)),
    SizedBox(width: 92, child: Text(v == null ? '—' : h.fmt(v), textAlign: TextAlign.right, maxLines: 1, style: AppText.s(12.5, W.w7))),
    hkPill(pill, bg: bg, fg: fg, width: 58),
  ]);
}

/// "Remind me on Monday evening": turns on the evening habit reminder (More → Reminders).
class _RemindButton extends StatefulWidget {
  const _RemindButton({required this.starts});
  final DateTime starts;
  @override
  State<_RemindButton> createState() => _RemindButtonState();
}

class _RemindButtonState extends State<_RemindButton> {
  bool? _on;

  @override
  void initState() {
    super.initState();
    Services.api.get<Map<String, dynamic>>('me/reminders/').then((j) {
      if (mounted) setState(() => _on = j['habit'] == true);
    }).catchError((_) {
      if (mounted) setState(() => _on = false);
    });
  }

  Future<void> _set(bool on) async {
    final was = _on;
    setState(() => _on = on);
    try {
      await Services.outbox.enqueue('PATCH', 'me/reminders/', {'habit': on}, tag: 'me/reminders');
      if (!mounted) return;
      showToast(context, on ? 'Reminder set' : 'Reminder removed',
          sub: on ? 'Habit reminders are on. The first one comes on ${dayShort(widget.starts)} evening.' : 'You get no habit reminders now',
          kind: on ? ToastKind.ok : ToastKind.del,
          action: 'Undo',
          onAction: () => _set(!on));
    } on ApiError catch (e) {
      if (mounted) {
        setState(() => _on = was);
        showToast(context, 'Could not change the reminder', sub: e.message, kind: ToastKind.warn);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = _on == true;
    final day = DateFormat('EEEE').format(widget.starts);
    return CaButton(on ? 'Reminder on · $day evening' : 'Remind me on $day evening',
        kind: on ? CaBtnKind.out : CaBtnKind.pri, icon: AppIcons.bell, loading: _on == null, onPressed: _on == null ? null : () => _set(!on));
  }
}

// ─────────────────────────────── Supplement details

Future<void> showSuppDetails(BuildContext context, HabitsController c, Supp s, {required VoidCallback act}) {
  final d = c.data!;
  final st = s.stock;
  final low = st != null && st.quantity <= 7;
  final n7 = s.last7.where((t) => t).length;
  final days = [for (var i = 6; i >= 0; i--) d.date.subtract(Duration(days: i))];
  final takenNow = s.taken;
  return showAppSheet(
    context,
    title: s.name,
    sub: '${s.groupName} · ${s.line}',
    builder: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      hkKv([
        ('Dose', s.dose),
        ('When', s.when),
        if (s.how.isNotEmpty) ('How to take', s.how),
        ('Stock at home', st == null ? 'Not set' : '${st.quantity} ${st.unit} left'),
        ('Plan', '${s.plan}${s.planSince == null ? '' : ' · since ${DateFormat('d MMM').format(s.planSince!)}'}'),
      ]),
      hkSec('Last 7 days · $n7 of 7 taken'),
      HkDots([
        for (final (i, day) in days.indexed)
          (letter(day), i < s.last7.length && s.last7[i] ? 'ok' : (i == 6 && d.isToday ? 'now' : 'no')),
      ], big: true),
      if (low) hkNote(AppIcons.info, 'Running low. Buy more this week so you do not miss days.', warn: true),
    ]),
    footerStretch: true,
    footer: (ctx) => [
      Row(spacing: 8, children: [
        Expanded(child: CaButton('Close', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop())),
        if (!d.isFuture && s.starts == null)
          Expanded(
            child: CaButton(takenNow ? (d.isToday ? 'Undo today' : 'Undo') : (d.isToday ? 'Take now' : 'Took it'),
                kind: takenNow ? CaBtnKind.out : CaBtnKind.pri, onPressed: () {
              Navigator.of(ctx).pop();
              act();
            }),
          ),
      ]),
    ],
  );
}
