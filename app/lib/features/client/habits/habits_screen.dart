import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../home/home_model.dart' show clock, dayShort, litres;
import '../home/home_parts.dart';
import 'habits_model.dart';
import 'habits_sheets.dart';

/// Habits & supplements (boards `ClientHabits` phone and `ClientHabitsWeb`). Day: the week strip,
/// each habit with its log button and the supplements of the picked day. Week: the Mon–Sun grid.
class ClientHabitsScreen extends StatefulWidget {
  const ClientHabitsScreen({super.key});
  @override
  State<ClientHabitsScreen> createState() => _ClientHabitsScreenState();
}

class _ClientHabitsScreenState extends State<ClientHabitsScreen> {
  final c = HabitsController();
  bool _week = false;

  @override
  void initState() {
    super.initState();
    c.start();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final d = c.data;
          if (d == null) {
            final e = c.error;
            return Center(
              child: e == null
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, spacing: 10, children: [
                        Text(e.offline ? 'You are offline' : 'Could not load this', style: AppText.s(15, W.w7)),
                        Text(e.offline ? 'Connect to the internet to load your habits' : e.message, textAlign: TextAlign.center, style: AppText.s(13, W.w4, color: AppColors.muted)),
                        CaButton('Try again', kind: CaBtnKind.out, expand: false, onPressed: c.load),
                      ]),
                    ),
            );
          }
          return context.isPhone ? _phone(d) : _web(d);
        },
      );

  // ─────────────────────────────── Layouts

  Widget _phone(HabitsData d) => RefreshIndicator(
        onRefresh: c.load,
        color: AppColors.accent,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            _top(d, web: false),
            _tabs(web: false),
            if (!_week) ...[
              _strip(d, web: false),
              _dayLine(d),
              ..._habitCards(d),
              _supps(d),
            ] else
              ..._weekView(d, two: false),
          ]),
        ),
      );

  Widget _web(HabitsData d) => CaWeb(
        web: true,
        child: RefreshIndicator(
          onRefresh: c.load,
          color: AppColors.accent,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 72),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: LayoutBuilder(builder: (context, box) {
                  final two = box.maxWidth >= 720;
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
                    _top(d, web: true),
                    Align(alignment: Alignment.centerLeft, child: _tabs(web: true)),
                    if (!_week) ...[
                      _strip(d, web: (box.maxWidth - 12) / 7 >= 92),
                      _dayLine(d),
                      if (two)
                        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: _habitCards(d))),
                          Expanded(child: _supps(d)),
                        ])
                      else ...[
                        ..._habitCards(d),
                        _supps(d),
                      ],
                    ] else
                      ..._weekView(d, two: two),
                  ]);
                }),
              ),
            ),
          ),
        ),
      );

  Widget _top(HabitsData d, {required bool web}) {
    final title = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Habits & supplements', style: AppText.s(web ? 26 : 22, W.w8, ls: web ? -0.26 : -0.22, h: 1.2)),
      Text(d.by, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w6, color: AppColors.muted)),
    ]);
    if (web) return title;
    return Row(spacing: 10, children: [
      CaIconBtn(AppIcons.chevronLeft, tooltip: 'Back to More', onTap: () => context.go('/more')),
      Expanded(child: title),
    ]);
  }

  Widget _tabs({required bool web}) {
    Widget tab(String l, bool on, VoidCallback tap) => Hover(
          onTap: tap,
          builder: (_, h, _) => Container(
            height: 32,
            constraints: BoxConstraints(minWidth: web ? 110 : 0),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: on ? AppColors.white : null,
              borderRadius: BorderRadius.circular(6),
              boxShadow: on ? const [BoxShadow(color: AppColors.shadowSoft, blurRadius: 2, offset: Offset(0, 1)), BoxShadow(color: AppColors.line, spreadRadius: 1)] : null,
            ),
            child: Text(l, style: AppText.s(13, W.w6, color: on || h ? AppColors.text : AppColors.text2)),
          ),
        );
    final tabs = [tab('Day', !_week, () => setState(() => _week = false)), tab('Week', _week, () => setState(() => _week = true))];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: web ? MainAxisSize.min : MainAxisSize.max, spacing: 4, children: [for (final t in tabs) web ? t : Expanded(child: t)]),
    );
  }

  // ─────────────────────────────── Day: week strip

  Widget _strip(HabitsData d, {required bool web}) => Container(
        padding: EdgeInsets.all(web ? 6 : 8),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        child: Row(spacing: 4, children: [
          for (final day in d.week.days)
            Expanded(
              child: Semantics(
                button: true,
                selected: DateUtils.isSameDay(day.date, d.date),
                label: dayShort(day.date),
                child: Hover(
                  onTap: () => c.pick(day.date),
                  builder: (_, h, _) {
                    final on = DateUtils.isSameDay(day.date, d.date);
                    final l = Text(letter(day.date), style: AppText.s(web ? 12 : 11, W.w6, color: on ? AppColors.daySubOn : AppColors.muted));
                    final n = Text('${day.date.day}', style: AppText.s(web ? 14 : 15, W.w8, color: on ? AppColors.white : AppColors.text));
                    final m = _mark(day.state);
                    return Container(
                      padding: web ? const EdgeInsets.symmetric(vertical: 7) : const EdgeInsets.fromLTRB(0, 7, 0, 6),
                      decoration: BoxDecoration(color: on ? AppColors.text : (h ? AppColors.outlineHover : null), borderRadius: BorderRadius.circular(10)),
                      child: web ? Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [l, n, m]) : Column(spacing: 3, children: [l, n, m]),
                    );
                  },
                ),
              ),
            ),
        ]),
      );

  Widget _mark(String state) {
    if (state == 'today') {
      return Container(width: 16, height: 16, decoration: BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle, border: Border.all(color: AppColors.accent, width: 2)));
    }
    final done = state == 'done';
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: done ? AppColors.okSolid : (state == 'part' || state == 'missed' ? AppColors.partDay : AppColors.dayOff), shape: BoxShape.circle),
      child: done ? const AppIcon(AppIcons.check, size: 11, color: AppColors.white, stroke: 2.6) : null,
    );
  }

  Widget _dayLine(HabitsData d) {
    final hs = d.active;
    final met = hs.where((h) => h.done).length;
    final s = d.isFuture
        ? 'Coming up · nothing to log yet'
        : '$met of ${hs.length} habits done${d.isPast && met < hs.length ? ' · ${hs.length - met} missed' : ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 8, children: [
        Expanded(child: Text(d.isToday ? 'Today, ${dayShort(d.date)}' : dayShort(d.date), style: AppText.s(15, W.w8))),
        Text(s, style: AppText.s(12.5, W.w6, color: AppColors.muted)),
      ]),
    );
  }

  // ─────────────────────────────── Day: habits

  void _later(HabitsData d) =>
      showToast(context, 'You can log this on ${dayShort(d.date)}', sub: 'Only today and earlier days can be logged', kind: ToastKind.info);

  (AppIconData, ChTone) _look(Habit h) => switch (h.icon) {
        'steps' => (AppIcons.steps, ChTone.green),
        'water' => (AppIcons.water, ChTone.warm),
        'sleep' => (AppIcons.moon, ChTone.purple),
        'food' => (AppIcons.food, ChTone.green),
        'timer' => (AppIcons.clock, ChTone.blue),
        'sun' => (AppIcons.sun, ChTone.amber),
        _ => (AppIcons.target, ChTone.amber),
      };

  List<Widget> _habitCards(HabitsData d) => [
        if (d.habits.isEmpty)
          ChCard(children: [
            ChHead(lead: const ChIcon(AppIcons.target, tone: ChTone.amber), title: 'No habits yet', sub: 'Your coach adds the habits for you to follow'),
          ]),
        for (final h in d.active) _habit(d, h),
        for (final h in d.soon) _soon(d, h),
      ];

  void _log(HabitsData d, Habit h) {
    if (d.isFuture) return _later(d);
    if (h.isWater) return _water(d, h, 250);
    if (h.isSleep) {
      showSleepLog(context, c, h);
    } else if (h.counter) {
      showStepsSheet(context, c, h);
    } else {
      _tick(d, h);
    }
  }

  void _tick(HabitsData d, Habit h) {
    if (d.isFuture) return _later(d);
    final was = h.done;
    c.setDone(h, !was);
    showToast(context, was ? '${h.name} un-ticked' : '${h.name} done',
        sub: was ? 'Not done ${onDay(d)}' : (d.isToday ? 'Nice, keep it going' : 'Logged for ${dayShort(d.date)}'),
        kind: was ? ToastKind.del : ToastKind.ok,
        action: 'Undo',
        onAction: () => c.setDone(h, was));
  }

  void _water(HabitsData d, Habit h, int delta) {
    if (d.isFuture) return _later(d);
    final cur = h.ml, goal = h.goalMl, on = onDay(d);
    if (delta < 0 && cur <= 0) {
      showToast(context, 'Nothing to remove', sub: 'No water logged $on', kind: ToastKind.info);
      return;
    }
    final now = (cur + delta).clamp(0, 10000);
    c.addWater(h, delta);
    void undo() => c.addWater(h, -delta);
    if (delta > 0 && cur < goal && now >= goal) {
      showToast(context, 'Water goal complete!', sub: '${litres(now)} $on', kind: ToastKind.star, action: 'Undo', onAction: undo);
    } else if (delta > 0) {
      showToast(context, '+250 ml · ${litres(now)} $on', sub: now >= goal ? 'Goal complete' : '${litres(goal - now)} to go', kind: ToastKind.water, action: 'Undo', onAction: undo);
    } else {
      showToast(context, 'Removed 250 ml', sub: '${litres(now)} logged $on', kind: ToastKind.del, action: 'Undo', onAction: undo);
    }
  }

  void _details(HabitsData d, Habit h) => showHabitDetails(context, c, h, log: () {
        if (!d.isToday) {
          c.pick(DateTime.now()); // "… today" buttons log today
          return;
        }
        _log(d, h);
      });

  Widget _habit(HabitsData d, Habit h) {
    final (icon, tone) = _look(h);
    final met = h.done && !d.isFuture;
    final miss = d.isPast && !h.done;
    final line = d.isFuture
        ? 'Goal ${h.goal}'
        : !h.logged
            ? 'Not logged yet · goal ${h.goal}'
            : h.of;
    final todayDot = d.isToday;
    final dots = [
      for (final (i, x) in h.last7.indexed) (letter(x.date), x.done ? 'ok' : (i == h.last7.length - 1 && todayDot ? 'now' : 'no')),
    ];
    final Widget action;
    if (h.isWater) {
      action = Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
        CaIconBtn(AppIcons.minus, size: 32, tooltip: 'Remove 250 ml', onTap: () => _water(d, h, -250)),
        CaButton('250 ml', small: true, expand: false, kind: CaBtnKind.dark, icon: AppIcons.plus, onPressed: () => _water(d, h, 250)),
      ]);
    } else if (!h.counter) {
      action = _tickBtn(done: h.done, label: 'Tick ${h.name}', onTap: () => _tick(d, h));
    } else {
      action = chSm(h.isSteps ? 'Add steps' : (h.isSleep ? (h.logged ? 'Edit' : 'Log sleep') : 'Add'), () => _log(d, h));
    }
    return ChCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      gap: 10,
      children: [
        Row(spacing: 11, children: [
          ChIcon(icon, tone: tone),
          Expanded(
            child: Hover(
              onTap: () => _details(d, h),
              builder: (_, hv, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Row(spacing: 7, children: [
                  Flexible(child: Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(14, W.w7, color: hv ? AppColors.accentText : AppColors.text))),
                  if (met) const ChOk('Done', icon: true),
                  if (miss) Text('Missed', style: AppText.s(11.5, W.w7, color: AppColors.badText)),
                ]),
                Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w4, color: AppColors.muted)),
              ]),
            ),
          ),
          action,
        ]),
        if (h.counter) ChBar(h.ratio, color: met ? AppColors.okSolid : (miss ? AppColors.missBar : AppColors.amberSolid), height: 5),
        Row(spacing: 10, children: [
          Expanded(child: Align(alignment: Alignment.centerLeft, child: HkDots(dots))),
          Row(mainAxisSize: MainAxisSize.min, spacing: 3, children: [
            const AppIcon(AppIcons.flame, size: 14, color: AppColors.streak),
            Text(h.streak > 0 ? '${h.streak} ${h.streak == 1 ? 'day' : 'days'} streak' : 'No streak yet', style: AppText.s(12, W.w7, color: AppColors.streak)),
          ]),
          _more(() => _details(d, h)),
        ]),
      ],
    );
  }

  Widget _more(VoidCallback onTap) => Semantics(
        button: true,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 1, children: [
              Text('Details', style: AppText.s(12, W.w7, color: AppColors.accentText).copyWith(decoration: h ? TextDecoration.underline : null, decorationColor: AppColors.accentText)),
              const AppIcon(AppIcons.chevronRight, size: 13, color: AppColors.accentText),
            ]),
          ),
        ),
      );

  /// `hk-tick`: dashed circle for a yes / no habit; green when done.
  Widget _tickBtn({required bool done, required String label, required VoidCallback onTap}) => Semantics(
        button: true,
        label: label,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done ? AppColors.okSolid : AppColors.white,
              shape: BoxShape.circle,
              border: done ? null : Border.all(color: h ? AppColors.accent : AppColors.tickRing, width: 1.5),
            ),
            child: AppIcon(AppIcons.check, size: 16, stroke: 2.6, color: done ? AppColors.white : (h ? AppColors.accent : AppColors.tickRing)),
          ),
        ),
      );

  Widget _soon(HabitsData d, Habit h) {
    final starts = h.startsOn!;
    void notYet() => showToast(context, 'This habit starts on ${dayShort(starts)}',
        sub: '${h.setBy == null ? 'Your coach' : h.setBy!.split(' ').first} set the start date. ${h.counter ? 'Log it' : 'Tick it'} from ${DateFormat('EEEE').format(starts)}${h.counter ? '' : ' evening'}.',
        kind: ToastKind.info);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: AppColors.soonBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Row(spacing: 11, children: [
        const ChIcon(AppIcons.clock, tone: ChTone.gray),
        Expanded(
          child: Hover(
            onTap: () => showHabitDetails(context, c, h, log: () {}),
            builder: (_, hv, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Wrap(spacing: 7, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(h.name, style: AppText.s(14, W.w7, color: hv ? AppColors.accentText : AppColors.text)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.amberBg, borderRadius: BorderRadius.circular(99)),
                  child: Text('Starts ${dayShort(starts)}', style: AppText.s(11, W.w7, color: AppColors.amberText, h: 1.2)),
                ),
              ]),
              Text(h.counter ? 'Goal ${h.goal}' : 'Yes / no · tick it each evening', style: AppText.s(12, W.w4, color: AppColors.muted)),
            ]),
          ),
        ),
        _tickBtn(done: false, label: 'Tick ${h.name}', onTap: notYet),
      ]),
    );
  }

  // ─────────────────────────────── Day: supplements

  void _take(HabitsData d, Supp s, bool taken) {
    if (d.isFuture) return _later(d);
    c.setTaken(s, taken);
    final st = s.stock;
    if (taken) {
      showToast(context, '${s.name} taken',
          sub: !d.isToday ? 'Logged for ${dayShort(d.date)}' : (st == null ? s.line : '${st.quantity} ${st.unit} left at home'),
          kind: ToastKind.ok, action: 'Undo', onAction: () => c.setTaken(s, false));
    } else {
      showToast(context, '${s.name} un-ticked', sub: d.isToday ? 'Not taken today' : 'Not taken on ${dayShort(d.date)}', kind: ToastKind.del, action: 'Undo', onAction: () => c.setTaken(s, true));
    }
  }

  Widget _supps(HabitsData d) {
    if (d.supps.isEmpty) {
      return ChCard(children: [
        ChHead(lead: const ChIcon(AppIcons.pill, tone: ChTone.purple), title: 'Supplements', sub: 'No supplement plan yet'),
      ]);
    }
    final due = d.supps.where((s) => s.due && s.starts == null).toList();
    final taken = due.where((s) => s.taken).length;
    final pct = d.week.suppsPct;
    final groups = <String, List<Supp>>{};
    for (final s in d.suppsInOrder) {
      groups.putIfAbsent(s.group, () => []).add(s);
    }
    final keys = groups.keys.toList();
    final first = d.supps.first;
    return ChCard(gap: 8, children: [
      ChHead(
        lead: const ChIcon(AppIcons.pill, tone: ChTone.purple),
        title: 'Supplements',
        sub: d.isFuture ? 'Coming up on ${dayShort(d.date)}' : '$taken of ${due.length} taken ${d.isToday ? 'today' : 'on ${dayShort(d.date)}'}',
        action: hkPill('This week $pct%', bg: pct >= 80 ? AppColors.okBg : AppColors.amberBg, fg: pct >= 80 ? AppColors.okText : AppColors.amberText),
      ),
      for (final k in keys) _group(d, groups[k]!),
      Text(
        'Plan “${first.plan}”${first.by == null ? '' : ' by ${first.by!.split(' ').first}'}${first.planSince == null ? '' : ' · since ${DateFormat('d MMM').format(first.planSince!)}'}. Tap a supplement for dose and stock.',
        style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.45),
      ),
    ]);
  }

  Widget _group(HabitsData d, List<Supp> list) {
    final g = list.first;
    final icon = switch (g.group) { 'morning' => AppIcons.sun, 'night' => AppIcons.moon, 'training' => AppIcons.dumbbell, _ => AppIcons.clock };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 6, 0, 4),
        child: Row(spacing: 6, children: [
          AppIcon(icon, size: 14, color: AppColors.text2),
          Text(g.groupName.toUpperCase(), style: AppText.s(12, W.w8, color: AppColors.text2, ls: .48)),
          Flexible(child: Text(g.groupLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w6, color: AppColors.muted))),
        ]),
      ),
      for (final s in list) _suppRow(d, s),
    ]);
  }

  Widget _suppRow(HabitsData d, Supp s) {
    final notYet = s.starts != null || !s.due;
    final past = d.isPast, fut = d.isFuture || notYet;
    final tk = s.taken;
    final at = s.takenAt;
    final desc = tk
        ? '${d.isToday && at != null ? 'Taken ${clock(at)}' : 'Taken'} · ${s.line}'
        : d.isToday && s.group == 'night' && s.dueAt != null
            ? 'Due ${s.dueAt} · ${s.line}'
            : past && !notYet
                ? 'Not taken · ${s.line}'
                : s.line;
    final missed = past && !tk && !notYet;
    void info() => showSuppDetails(context, c, s, act: () => _take(d, s, !tk));
    void toggle() => fut ? (notYet ? _notDue(s) : _later(d)) : _take(d, s, !tk);
    final Widget end;
    if (tk) {
      end = _smBtn('Undo', () => _take(d, s, false));
    } else if (missed) {
      end = Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [hkPill('Missed', bg: AppColors.badBg, fg: AppColors.badText), _smBtn('Took it', () => _take(d, s, true))]);
    } else if (fut) {
      end = hkPill(s.starts ?? (notYet ? 'Not today' : 'Upcoming'));
    } else {
      end = _smBtn('Take', () => _take(d, s, true), pri: true);
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      child: Row(spacing: 10, children: [
        Semantics(
          button: true,
          label: 'Tick ${s.name}',
          child: Hover(
            onTap: toggle,
            builder: (_, h, _) => Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tk ? AppColors.okSolid : (missed ? AppColors.missTickBg : AppColors.white),
                border: Border.all(color: tk || h ? AppColors.okSolid : (missed ? AppColors.missBar : AppColors.tickRing), width: 1.5),
              ),
              child: tk ? const AppIcon(AppIcons.check, size: 14, color: AppColors.white, stroke: 2.6) : null,
            ),
          ),
        ),
        Expanded(
          child: Hover(
            onTap: info,
            builder: (_, h, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text(s.name, style: AppText.s(14, W.w7, color: h ? AppColors.accentText : AppColors.text)),
              Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w4, color: tk ? AppColors.okText : AppColors.muted)),
            ]),
          ),
        ),
        end,
      ]),
    );
  }

  void _notDue(Supp s) => showToast(context, s.starts != null ? '${s.name} ${s.starts!.toLowerCase().replaceFirst('starts', 'starts on')}' : '${s.name} is not for today',
      sub: s.starts != null ? 'Your coach set the start date' : 'Your plan has it on other days', kind: ToastKind.info);

  /// `hk-sr .ca-btn.sm`: 30 high, 12.5 text.
  Widget _smBtn(String t, VoidCallback onTap, {bool pri = false}) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: pri ? (h ? AppColors.accentHover : AppColors.accent) : (h ? AppColors.outlineHover : AppColors.white),
            borderRadius: BorderRadius.circular(8),
            border: pri ? null : Border.all(color: AppColors.line),
          ),
          child: Text(t, style: AppText.s(12.5, W.w7, color: pri ? AppColors.white : AppColors.text)),
        ),
      );

  // ─────────────────────────────── Week

  List<Widget> _weekView(HabitsData d, {required bool two}) {
    final w = d.week;
    final coach = d.habits.map((h) => h.setBy).followedBy(d.supps.map((s) => s.by)).whereType<String>().firstOrNull?.split(' ').first ?? 'Your coach';
    final summary = ChCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), gap: 8, children: [
      HkCells([
        ('${w.habitsPct}%', 'Habits done'),
        if (d.supps.isNotEmpty) ('${w.suppsPct}%', 'Supplements taken'),
        if (w.best != null) ('${w.best!.days} ${w.best!.days == 1 ? 'day' : 'days'}', '${w.best!.name} streak'),
      ], big: two),
      Text(
        '${w.range} · ${w.habitsDone} of ${w.habitsDue} habits${d.supps.isEmpty ? '' : ' and ${w.suppsTaken} of ${w.suppsDue} supplements'} so far. $coach sees this in your profile.',
        style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.45),
      ),
    ]);
    final habits = _grid(
      d,
      icon: const ChIcon(AppIcons.target, tone: ChTone.amber),
      title: 'Habits this week',
      sub: '${w.range} · tap a day to open it',
      rows: [
        for (final h in d.habits)
          (
            name: h.name,
            sub: h.startsOn != null ? 'Starts ${dayShort(h.startsOn!)}' : h.weekLine,
            cells: h.week,
            count: h.startsOn != null ? '—' : '${h.weekDone}/${h.weekDue}',
            open: () => showHabitDetails(context, c, h, log: () => _details(d, h)),
            off: h.startsOn == null
                ? null
                : () => showToast(context, '${h.name} starts on ${dayShort(h.startsOn!)}', sub: '${h.setBy == null ? 'Your coach' : h.setBy!.split(' ').first} set the start date', kind: ToastKind.info),
          ),
      ],
      legend: true,
      web: two,
    );
    final supps = d.supps.isEmpty
        ? null
        : _grid(
            d,
            icon: const ChIcon(AppIcons.pill, tone: ChTone.purple),
            title: 'Supplements this week',
            sub: '${w.suppsTaken} of ${w.suppsDue} taken so far · ${w.suppsPct}%',
            rows: [
              for (final s in d.suppsInOrder)
                (
                  name: s.name,
                  sub: s.groupName,
                  cells: s.week,
                  count: '${s.week.where((x) => x == 'done').length}/${s.week.where((x) => x != 'off' && x != 'coming').length}',
                  open: () => showSuppDetails(context, c, s, act: () => _take(d, s, !s.taken)),
                  off: null,
                ),
            ],
            legend: false,
            web: two,
          );
    return [
      summary,
      if (two && supps != null)
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [Expanded(child: habits), Expanded(child: supps)])
      else ...[
        habits,
        ?supps,
      ],
    ];
  }

  Widget _grid(
    HabitsData d, {
    required Widget icon,
    required String title,
    required String sub,
    required List<({String name, String sub, List<String> cells, String count, VoidCallback open, VoidCallback? off})> rows,
    required bool legend,
    required bool web,
  }) {
    final cw = web ? 34.0 : 26.0, box = web ? 26.0 : 22.0;
    final days = d.week.days;
    Widget cell(String st, int i, VoidCallback? off) {
      final day = i < days.length ? days[i].date : d.date;
      return SizedBox(
        width: cw,
        child: Center(
          child: Semantics(
            button: true,
            label: dayShort(day),
            child: Hover(
              onTap: off ??
                  () {
                    setState(() => _week = false);
                    c.pick(day);
                  },
              builder: (_, h, _) => Container(
                width: box,
                height: box,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  color: switch (st) {
                    'done' => AppColors.okSolid,
                    'missed' => AppColors.badBg,
                    'today' => AppColors.white,
                    'coming' => AppColors.futCell,
                    _ => null,
                  },
                  gradient: st == 'off'
                      ? const LinearGradient(begin: Alignment.topLeft, end: Alignment(-0.6, -0.6), tileMode: TileMode.repeated, colors: [AppColors.offA, AppColors.offA, AppColors.offB, AppColors.offB], stops: [0, .5, .5, 1])
                      : null,
                  border: st == 'today'
                      ? Border.all(color: AppColors.accent, width: 2)
                      : st == 'coming'
                          ? Border.all(color: AppColors.futLine)
                          : null,
                  boxShadow: h && st != 'off' ? const [BoxShadow(color: AppColors.accentSoft, spreadRadius: 2)] : null,
                ),
                child: st == 'done'
                    ? const AppIcon(AppIcons.check, size: 12, color: AppColors.white, stroke: 2.8)
                    : st == 'missed'
                        ? const AppIcon(AppIcons.close, size: 12, color: AppColors.badText, stroke: 2.8)
                        : null,
              ),
            ),
          ),
        ),
      );
    }

    return ChCard(gap: 8, children: [
      ChHead(lead: icon, title: title, sub: sub),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(spacing: 2, children: [
            const Spacer(),
            for (final x in days)
              SizedBox(width: cw, child: Text(letter(x.date), textAlign: TextAlign.center, style: AppText.s(10.5, W.w7, color: x.today ? AppColors.accentText : AppColors.muted))),
            const SizedBox(width: 30),
          ]),
        ),
        for (final r in rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            child: Row(spacing: 2, children: [
              Expanded(
                child: Hover(
                  onTap: r.open,
                  builder: (_, h, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(web ? 13 : 12.5, W.w7, color: h ? AppColors.accentText : AppColors.text)),
                    Text(r.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11, W.w4, color: AppColors.muted)),
                  ]),
                ),
              ),
              for (final (i, st) in r.cells.indexed) cell(st, i, st == 'off' ? (r.off ?? () => _offDay(i, days)) : null),
              SizedBox(width: 30, child: Text(r.count, textAlign: TextAlign.right, style: AppText.s(11.5, W.w8, color: AppColors.text2))),
            ]),
          ),
      ]),
      if (legend)
        Wrap(spacing: 12, runSpacing: 4, children: [
          for (final (l, st) in [('Done', 'ok'), ('Missed', 'no'), ('Today, not yet', 'now'), ('Coming', 'fut')])
            Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: st == 'ok' ? AppColors.okSolid : (st == 'no' ? AppColors.missDot : null),
                  border: st == 'now' ? Border.all(color: AppColors.accent, width: 2) : (st == 'fut' ? Border.all(color: AppColors.futLegend) : null),
                ),
              ),
              Text(l, style: AppText.s(11, W.w6, color: AppColors.muted)),
            ]),
        ]),
    ]);
  }

  void _offDay(int i, List<({DateTime date, bool today, bool future, String state})> days) =>
      showToast(context, 'Not on your plan that day', sub: i < days.length ? dayShort(days[i].date) : '', kind: ToastKind.info);
}
