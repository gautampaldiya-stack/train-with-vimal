import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/page.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import 'cal_drawers.dart';
import 'cal_grid.dart';
import 'cal_model.dart';
import '../../../core/widgets/tooltip.dart';

/// Calendar (boards `TrainerCalendar` + `TrainerCalendarMobile`): the trainer's own sessions. Web opens on the
/// week, the phone on the day with a Mon–Sun strip (its Week = a 3-day window). Stats, ‹ Today ›, Week / Day,
/// the kind legend, the grid; a block opens the session panel (Open profile · Reschedule · Mark as done ·
/// Cancel session + Undo). Header: My working hours, New session (no avatar on web, as on the dashboard).
class TrainerCalendarScreen extends StatefulWidget {
  const TrainerCalendarScreen({super.key});

  @override
  State<TrainerCalendarScreen> createState() => _TrainerCalendarScreenState();
}

class _TrainerCalendarScreenState extends State<TrainerCalendarScreen> {
  CalendarController? _c;
  CalendarController get c => _c!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c == null) {
      _c = CalendarController(phone: context.isPhone);
      c.load();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  void _fail(Object e) {
    if (!mounted) return;
    showToast(context, 'Something went wrong', sub: ApiError.from(e).message, kind: ToastKind.err);
  }

  // ─────────────────────────────── Actions

  Future<void> _new() async {
    final r = await showSessionForm(context, c);
    if (r == null || !mounted) return;
    final (s, _) = r;
    c.show(s.start);
    showToast(context, 'Session booked', sub: '${s.client} · ${s.shortWhen}', action: 'Undo', onAction: () => c.unbook(s.id).catchError(_fail));
  }

  Future<void> _move(CalSession old) async {
    final r = await showSessionForm(context, c, move: old);
    if (r == null || !mounted) return;
    final (s, _) = r;
    c.show(s.start);
    showToast(context, 'Session moved', sub: '${s.client} · now ${s.shortWhen}', action: 'Undo', onAction: () => c.moveBack(old).catchError(_fail));
  }

  Future<void> _open(CalSession s) async {
    final a = await showSessionPanel(context, s);
    if (!mounted || a == null) return;
    switch (a) {
      case 'profile':
        context.go('/clients/${s.clientId}');
      case 'move':
        await _move(s);
      case 'toggle':
        final was = s.status, to = s.done ? 'booked' : 'done';
        try {
          await c.setStatus(s, to);
          if (!mounted) return;
          showToast(context, to == 'done' ? 'Marked as done' : 'Marked as not done', sub: s.client, action: 'Undo',
              onAction: () => c.setStatus(s, was).catchError(_fail));
        } catch (e) {
          _fail(e);
        }
      case 'cancel':
        final tell = await confirmCancelSession(context, s);
        if (tell == null || !mounted) return;
        try {
          await c.cancel(s, tell: tell);
          if (!mounted) return;
          showToast(context, 'Session cancelled',
              sub: tell ? '${s.client} gets a message in the app' : '${s.client} · ${s.shortWhen}',
              action: 'Undo',
              onAction: () => c.restore(s.id).catchError(_fail));
        } catch (e) {
          _fail(e);
        }
    }
  }

  Future<void> _hours() async {
    final ok = await showWorkingHours(context, c);
    if (!ok || !mounted) return;
    final n = c.workingDays;
    showToast(context, 'Working hours saved', sub: '$n working ${n == 1 ? 'day' : 'days'}');
  }

  // ─────────────────────────────── Page

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final phone = context.isPhone;
          final compact = compactTop(context);
          return StaffPage(
            onRefresh: c.load,
            header: PageTop(
              title: 'Calendar',
              sub: 'Your sessions, ${calWeekRange(c.week)}',
              actions: [
                AppButton('My working hours', icon: AppIcons.clockAlt, iconOnly: compact, onPressed: _hours),
                AppButton.primary('New session', icon: AppIcons.plus, iconOnly: compact, onPressed: _new),
              ],
            ),
            children: [
              if (c.error != null && c.sessions.isEmpty && !c.loading)
                EmptyState(c.error!.offline ? 'You are offline' : 'Could not load your calendar',
                    sub: c.error!.offline ? 'Connect to the internet and try again.' : c.error!.message,
                    action: AppButton('Try again', onPressed: c.load))
              else ...[
                phone ? _phoneStats() : _webStats(),
                _bar(phone),
                if (phone) _strip(),
                _legend(phone),
                CalGrid(c: c, days: _days(phone), phone: phone, onOpen: _open),
              ],
            ],
          );
        },
      );

  List<int> _days(bool phone) {
    if (c.view == 'day') return [c.day];
    if (!phone) return const [0, 1, 2, 3, 4, 5, 6];
    final w0 = (c.day - 1).clamp(0, 4);
    return [w0, w0 + 1, w0 + 2];
  }

  /// Board stats: Sessions this week · Done (% of the week) · On a call · Working days (the picked day's hours).
  List<(AppIconData, String, String, String)> get _stats {
    final st = c.stats;
    final total = (st['total'] as num?)?.toInt() ?? c.sessions.length;
    final done = (st['done'] as num?)?.toInt() ?? 0;
    final calls = (st['calls'] as num?)?.toInt() ?? 0;
    final av = c.hoursOn(c.day);
    final wd = calWd[c.day];
    return [
      (AppIcons.calStat, 'Sessions this week', '$total', c.view == 'day' ? '${c.on(c.day).length} on $wd' : ''),
      (AppIcons.check, 'Done', '$done', total > 0 ? '${(st['done_pct'] as num?)?.toInt() ?? (done * 100 / total).round()}% of the week' : ''),
      (AppIcons.call, 'On a call', '$calls', 'Quick calls and reviews'),
      (AppIcons.person, 'Working days', '${c.workingDays}', av == null ? '' : (av.open ? '$wd ${calRange(av.from, av.to - av.from)}' : '$wd off')),
    ];
  }

  Widget _webStats() => LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth < 760 ? 2 : 4;
        final w = (box.maxWidth - 12 * (cols - 1)) / cols;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final (icon, label, value, delta) in _stats)
            Container(
              width: w,
              constraints: const BoxConstraints(minHeight: 80),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: AppColors.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                Row(spacing: 8, children: [
                  IconTile(icon, radius: 8),
                  Expanded(child: CutText(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.muted))),
                ]),
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 10, children: [
                  Text(value, style: AppText.stat),
                  if (delta.isNotEmpty) Flexible(child: CutText(delta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w7))),
                ]),
              ]),
            ),
        ]);
      });

  /// Phone: one card, 4 cells (number over a small grey label).
  Widget _phoneStats() => Container(
        decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: AppColors.line)),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, (_, label, value, _)) in _stats.indexed)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 9),
                  decoration: BoxDecoration(border: i == 0 ? null : const Border(left: BorderSide(color: AppColors.line))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                    CutText(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(16, W.w8, h: 1.2)),
                    Text(label, maxLines: 2, style: AppText.s(10.5, W.w6, color: AppColors.muted, h: 1.25)),
                  ]),
                ),
              ),
          ]),
        ),
      );

  /// `.cal-bar`: ‹ Today › and the range; Week / Day on the right (phone: under it).
  Widget _bar(bool phone) {
    final range = c.view == 'day' ? '${calDayLabel(c.dateOf(c.day))} ${c.dateOf(c.day).year}' : calWeekRange(c.week);
    final nav = Row(mainAxisSize: phone ? MainAxisSize.max : MainAxisSize.min, spacing: 6, children: [
      AppIconButton(AppIcons.prev, tooltip: 'Previous', onPressed: c.prev),
      SizedBox(height: 32, child: AppButton('Today', size: BtnSize.sm, onPressed: c.today)),
      AppIconButton(AppIcons.next, tooltip: 'Next', onPressed: c.next),
      Flexible(
        child: Padding(
          padding: EdgeInsets.only(left: phone ? 4 : 8),
          child: CutText(range, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(phone ? 14.5 : 16, W.w7, ls: -0.16)),
        ),
      ),
      if (c.loading) const Padding(padding: EdgeInsets.only(left: 6), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))),
    ]);
    final tabs = CalTabs<String>(items: const [('week', 'Week'), ('day', 'Day')], value: c.view, onChanged: c.setView);
    if (phone) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [nav, Align(alignment: Alignment.centerRight, child: tabs)]);
    }
    return Row(children: [Expanded(child: nav), tabs]);
  }

  /// Phone `.mcal-strip`: M–S with the date; the picked day is a blue disc, the 3-day window is grey, a dot = sessions.
  Widget _strip() {
    final win = c.view == 'day' ? const <int>[] : _days(true);
    return Row(spacing: 4, children: [
      for (var i = 0; i < 7; i++)
        Expanded(
          child: Hover(
            onTap: () => c.pickDay(i),
            builder: (_, h, _) {
              final on = i == c.day, today = c.isToday(i), has = c.on(i).isNotEmpty;
              return Container(
                padding: const EdgeInsets.fromLTRB(0, 6, 0, 5),
                decoration: BoxDecoration(color: win.contains(i) ? AppColors.sub : null, borderRadius: AppRadius.all(AppRadius.item)),
                child: Column(spacing: 2, children: [
                  Text(calWd[i].substring(0, 1), style: AppText.s(11, W.w6, color: today ? AppColors.accentText : AppColors.muted)),
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: on ? AppColors.accent : null, shape: BoxShape.circle),
                    child: Text('${c.dateOf(i).day}', style: AppText.s(15, W.w7, color: on ? AppColors.white : (today ? AppColors.accentText : AppColors.text))),
                  ),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(color: has ? (on ? AppColors.accent : AppColors.line2) : null, shape: BoxShape.circle),
                  ),
                ]),
              );
            },
          ),
        ),
    ]);
  }

  /// `.cal-legend`: the 3 kinds with their length, Outside working hours, Done. Phone: one scrolling line.
  Widget _legend(bool phone) {
    Widget item(Widget sw, String label, [String? end]) => Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
          sw,
          Text(label, style: AppText.s(phone ? 12 : 12.5, W.w6, color: AppColors.text2)),
          if (end != null) Text(end, style: AppText.s(phone ? 12 : 12.5, W.w5, color: AppColors.muted)),
        ]);
    Widget dot(Color c, {double o = 1}) => Opacity(
          opacity: o,
          child: Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: AppRadius.all(3))),
        );
    final items = [
      for (final k in CalKind.values) item(dot(k.dot), k.label, '${k.minutes} min'),
      item(const CalOffSwatch(), 'Outside working hours'),
      item(dot(AppColors.kSsDot, o: .4), 'Done'),
    ];
    if (phone) {
      return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(spacing: 14, children: items));
    }
    return Wrap(spacing: 16, runSpacing: 6, children: items);
  }
}
