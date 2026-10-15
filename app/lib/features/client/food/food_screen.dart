import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../home/home_model.dart' show glasses, inNum, litres, mealTime;
import '../home/home_parts.dart';
import '../train/train_parts.dart' show TwoTabs;
import 'food_model.dart';
import 'food_parts.dart';
import 'food_sheets.dart';

/// Food (boards `ClientMealNutrition` phone and `ClientMealNutritionWeb`): the day strip, calories, this week,
/// water, then My plan (the meals to eat) or the Food log of the picked day. On a wide web page the tabs stay
/// put and only the meal cards scroll.
class ClientFoodScreen extends StatefulWidget {
  const ClientFoodScreen({super.key});
  @override
  State<ClientFoodScreen> createState() => _ClientFoodScreenState();
}

class _ClientFoodScreenState extends State<ClientFoodScreen> {
  final c = FoodController();

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
                    Text(e.offline ? 'Connect to the internet to load your food' : e.message, textAlign: TextAlign.center, style: AppText.s(13, W.w4, color: AppColors.muted)),
                    CaButton('Try again', kind: CaBtnKind.out, expand: false, onPressed: c.load),
                  ]),
                ),
        );
      }
      return context.isPhone ? _phone(d) : _web(d);
    },
  );

  bool _past(FoodDay d) => d.date.isBefore(c.today);
  bool _future(FoodDay d) => d.date.isAfter(c.today);

  // ─────────────────────────────── Layouts

  Widget _phone(FoodDay d) => RefreshIndicator(
    onRefresh: c.load,
    color: AppColors.accent,
    child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        _top(d),
        _strip(d, web: false),
        ..._left(d),
        _tabs(d),
        ..._list(d),
      ]),
    ),
  );

  Widget _web(FoodDay d) => CaWeb(
    web: true,
    child: LayoutBuilder(builder: (context, page) {
      final inner = (page.maxWidth - 64).clamp(0.0, 1080.0);
      final two = inner >= 700 && page.maxHeight >= 560;
      Widget frame(Widget child, {double bottom = 72}) => Padding(
        padding: EdgeInsets.fromLTRB(32, 32, 32, bottom),
        child: Align(alignment: Alignment.topCenter, child: SizedBox(width: inner, child: child)),
      );
      final strip = _strip(d, web: (inner - 10) / 7 >= 92);
      if (!two) {
        // Narrow web: one column, the whole page scrolls.
        return SingleChildScrollView(
          child: frame(Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
            _top(d),
            strip,
            ..._left(d),
            _tabs(d),
            ..._list(d),
          ])),
        );
      }
      // Wide web: the top, the strip and the tabs stay; the left column and the meal cards scroll on their own.
      return frame(
        bottom: 0,
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _top(d),
          const SizedBox(height: 18),
          strip,
          const SizedBox(height: 18),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: _left(d)),
                ),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _tabs(d),
                  const SizedBox(height: 8),
                  // 4 px wider on each side so the Next card's ring is not cut off by the scroll edge.
                  Expanded(
                    child: LayoutBuilder(builder: (_, b) => OverflowBox(
                      maxWidth: b.maxWidth + 8,
                      minWidth: b.maxWidth + 8,
                      child: SingleChildScrollView(
                        key: PageStorageKey('food-${c.tab}'),
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 32),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: _list(d)),
                      ),
                    )),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      );
    }),
  );

  List<Widget> _left(FoodDay d) => [if (d.hasPlan) _calories(d), _weekCard(d), _waterCard(d)];

  // ─────────────────────────────── Header and strip

  Widget _top(FoodDay d) {
    final shown = _future(d) ? d.planned[0] : d.eaten[0];
    final sub = '${fdDay(d.date)}${d.isToday ? ' · today' : ''}${d.hasPlan ? ' · ${inNum(shown)} of ${inNum(d.target[0])} kcal' : ''}';
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(spacing: 10, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text('Food', style: AppText.s(26, W.w8, ls: -0.26)),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w6, color: AppColors.muted)),
          ]),
        ),
        chSm('Log food', _logFood, icon: AppIcons.plus, kind: CaBtnKind.dark),
      ]),
    );
  }

  void _logFood([String? meal]) {
    if (!(c.data?.isToday ?? true)) {
      c.pick(c.today);
    }
    context.go(meal == null ? '/food/log' : '/food/log?meal=${Uri.encodeComponent(meal)}');
  }

  Widget _strip(FoodDay d, {required bool web}) {
    final monday = d.date.subtract(Duration(days: d.date.weekday - 1));
    final narrow = MediaQuery.sizeOf(context).width < 1180;
    return Container(
      padding: web ? const EdgeInsets.all(5) : const EdgeInsets.all(8),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Row(spacing: 4, children: [
        for (var i = 0; i < 7; i++)
          Expanded(child: _day(d, DateUtils0.dateOnly(monday.add(Duration(days: i))), web: web, narrow: narrow)),
      ]),
    );
  }

  Widget _day(FoodDay d, DateTime day, {required bool web, required bool narrow}) {
    final on = DateUtils0.same(day, d.date), real = DateUtils0.same(day, c.today), future = day.isAfter(c.today);
    final w = d.week.where((x) => DateUtils0.same(DateTime.parse('${x['date']}'), day)).firstOrNull;
    final done = w?['done'] == true;
    final size = web && !narrow ? 18.0 : (web ? 16.0 : 18.0);
    final Widget mark;
    if (done) {
      mark = Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: AppColors.okSolid, shape: BoxShape.circle),
        child: AppIcon(AppIcons.check, size: size == 18 ? 11 : 10, color: AppColors.white, stroke: 3),
      );
    } else if (real) {
      mark = Container(width: size, height: size, decoration: BoxDecoration(color: AppColors.white, shape: BoxShape.circle, border: Border.all(color: AppColors.accent, width: 2)));
    } else if (future) {
      mark = DashedCircle(size: size);
    } else {
      mark = Container(width: size, height: size, decoration: const BoxDecoration(color: AppColors.sub, shape: BoxShape.circle));
    }
    final ink = on ? AppColors.sessText : AppColors.text;
    final wd = Text(real ? 'Today' : fdWd[day.weekday - 1], style: AppText.s(11, W.w6, color: on ? AppColors.sessText : AppColors.muted));
    final n = Text('${day.day}', style: AppText.s(web ? (narrow ? 12 : 12.5) : 11.5, future && !on ? W.w6 : W.w7, color: future && !on ? AppColors.muted : ink));
    return Semantics(
      button: true,
      selected: on,
      label: '${fdDay(day)}${done ? ', all meals logged' : ''}${real ? ', today' : ''}',
      child: Hover(
        onTap: () => c.pick(day),
        builder: (_, h, _) => Container(
          padding: web ? EdgeInsets.symmetric(horizontal: narrow ? 6 : 10, vertical: 6) : const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
          decoration: BoxDecoration(
            color: on ? AppColors.accentSoft : (h ? AppColors.outlineHover : null),
            borderRadius: BorderRadius.circular(10),
            border: on && web ? Border.all(color: AppColors.accentRing) : null,
          ),
          child: web
              ? Row(spacing: narrow ? 6 : 8, children: [
                  mark,
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [wd, n])),
                ])
              : Column(spacing: 3, children: [wd, n, mark]),
        ),
      ),
    );
  }

  // ─────────────────────────────── Calories (`nv-cal`)

  Widget _calories(FoodDay d) {
    final t = d.target, e = d.eaten, p = d.planned;
    final future = _future(d);
    final shown = future ? p : e;
    final left = t[0] - e[0], over = left < 0;
    final zero = future || shown[0] <= 0;
    final logged = d.meals.where((m) => m.logged).length, skipped = d.meals.where((m) => m.skipped).length, all = d.meals.length;
    final open = d.meals.where((m) => m.open).toList();
    final ahead = open.fold(0, (a, m) => a + m.kcal);
    final String cap;
    if (future) {
      cap = '$all meals planned · ${inNum(p[0])} kcal for the day';
    } else if (d.isToday) {
      cap = '$logged of $all meals logged${skipped > 0 ? ' · $skipped skipped' : ''}'
          '${open.isNotEmpty ? ' · ${open.length} ${open.length == 1 ? 'meal' : 'meals'} still ahead, ${inNum(ahead)} kcal' : ' · all done for today'}';
    } else {
      cap = '$logged of $all meals logged${all - logged > 0 ? ' · ${all - logged} missed' : ''}';
    }
    return Semantics(
      button: true,
      child: Hover(
        onTap: () => showCaloriesSheet(context, c),
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: h ? AppColors.line2 : AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            Row(spacing: 6, children: [
              Expanded(child: Text(calHead(d, c.today), style: AppText.s(15, W.w8))),
              Text('Target ${inNum(t[0])} kcal', style: AppText.s(12, W.w6, color: AppColors.muted)),
              const AppIcon(AppIcons.chevronRight, size: 15, color: AppColors.muted),
            ]),
            Row(spacing: 16, children: [
              ChRing(
                ratio: zero || t[0] <= 0 ? 0 : shown[0] / t[0],
                color: over && !future ? AppColors.amberSolid : AppColors.accent,
                valueColor: over && d.isToday ? AppColors.amberText : null,
                value: inNum(future ? p[0] : (d.isToday ? left.abs() : e[0])),
                label: future ? 'kcal planned' : (d.isToday ? (over ? 'kcal over' : 'kcal left') : 'kcal eaten'),
              ),
              Expanded(
                child: Column(spacing: 9, children: [
                  for (final (i, (name, color)) in const [('Protein', AppColors.accent), ('Carbs', AppColors.nvCarbs), ('Fat', AppColors.nvFat)].indexed)
                    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(child: Text(name, style: AppText.s(12.5, W.w6, color: AppColors.muted))),
                        Text('${shown[i + 1].round()} / ${t[i + 1].round()} g', style: AppText.s(12.5, W.w7)),
                      ]),
                      const SizedBox(height: 4),
                      ChBar(t[i + 1] > 0 ? shown[i + 1] / t[i + 1] : 0, color: color),
                    ]),
                ]),
              ),
            ]),
            fdCap(cap),
          ]),
        ),
      ),
    );
  }

  // ─────────────────────────────── This week (`nv-wk`)

  Widget _weekCard(FoodDay d) {
    final tg = d.target[0];
    final wk = d.week;
    final kc = [for (final w in wk) ((w['kcal'] as num?) ?? 0).toDouble()];
    final logged = [for (var i = 0; i < wk.length; i++) if (kc[i] > 0) i];
    var top = tg;
    for (final i in logged) {
      if (kc[i] > top) top = kc[i];
    }
    top = top <= 0 ? 1 : top * 1.08;
    final todayAt = wk.indexWhere((w) => DateUtils0.same(DateTime.parse('${w['date']}'), c.today));
    final sel = (c.weekSel ?? (todayAt >= 0 ? todayAt : wk.indexWhere((w) => DateUtils0.same(DateTime.parse('${w['date']}'), d.date)))).clamp(0, wk.isEmpty ? 0 : wk.length - 1);
    if (wk.isEmpty) return const SizedBox.shrink();
    final sd = DateTime.parse('${wk[sel]['date']}');
    final sp = ((wk[sel]['protein'] as num?) ?? 0).round();
    final avgK = logged.isEmpty ? 0 : logged.fold(0.0, (a, i) => a + kc[i]) / logged.length;
    final avgP = logged.isEmpty ? 0 : logged.fold(0.0, (a, i) => a + ((wk[i]['protein'] as num?) ?? 0)) / logged.length;
    return ChCard(gap: 10, children: [
      Row(children: [
        Expanded(child: Text('This week', style: AppText.s(15, W.w8))),
        if (tg > 0) Text('Target ${inNum(tg)} kcal', style: AppText.s(12, W.w6, color: AppColors.muted)),
      ]),
      SizedBox(
        height: 104,
        child: Stack(children: [
          Row(spacing: 6, children: [
            for (var i = 0; i < wk.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == sel,
                  label: '${fdDay(DateTime.parse('${wk[i]['date']}'))}, ${inNum(kc[i])} kcal',
                  child: Hover(
                    onTap: () => c.pickWeek(i),
                    builder: (_, h, _) {
                      final on = i == sel, today = i == todayAt, none = kc[i] <= 0, hi = !none && tg > 0 && kc[i] > tg * 1.03;
                      final color = none
                          ? AppColors.barTrack
                          : on
                          ? (hi ? AppColors.amberSolid : AppColors.accent)
                          : hi
                          ? AppColors.wkHi
                          : today
                          ? AppColors.wkToday
                          : AppColors.wkBar;
                      return Column(spacing: 4, children: [
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(color: on ? AppColors.sub : (h ? AppColors.outlineHover : null), borderRadius: BorderRadius.circular(6)),
                            child: LayoutBuilder(builder: (_, b) {
                              final hh = none ? 4.0 : (kc[i] / top * b.maxHeight).clamp(4.0, b.maxHeight);
                              return Align(
                                alignment: Alignment.bottomCenter,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: (b.maxWidth * .7).clamp(0, 30),
                                  height: hh,
                                  decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(5), bottom: Radius.circular(2))),
                                ),
                              );
                            }),
                          ),
                        ),
                        SizedBox(
                          height: 14,
                          child: Text(
                            fdWd[DateTime.parse('${wk[i]['date']}').weekday - 1][0],
                            style: AppText.s(11, W.w7, color: on ? AppColors.text : (today ? AppColors.accentText : AppColors.muted)),
                          ),
                        ),
                      ]);
                    },
                  ),
                ),
              ),
          ]),
          if (tg > 0)
            Positioned.fill(
              bottom: 18,
              child: IgnorePointer(
                child: LayoutBuilder(builder: (_, b) => Stack(children: [
                  Positioned(left: 0, right: 0, bottom: (tg / top * b.maxHeight).clamp(0, b.maxHeight), child: const _DashLine()),
                ])),
              ),
            ),
        ]),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: AppColors.nextBg, borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 8, children: [
          Expanded(child: Text('${fdDay(sd)}${sel == todayAt ? ' · today' : ''}', style: AppText.s(12.5, W.w8))),
          Text(
            kc[sel] > 0 ? '${inNum(kc[sel])} kcal · $sp g protein' : (sel == todayAt ? 'Nothing logged yet today' : 'Not logged yet'),
            style: AppText.s(12.5, W.w6, color: AppColors.text2),
          ),
        ]),
      ),
      fdCap(logged.isEmpty
          ? 'Nothing logged this week yet'
          : 'Average ${inNum(avgK)} kcal · ${avgP.round()} g protein on ${logged.length} logged ${logged.length == 1 ? 'day' : 'days'}'),
    ]);
  }

  // ─────────────────────────────── Water

  void _water(int delta) {
    final d = c.data!;
    if (_future(d)) {
      showToast(context, 'You can log water on ${fdDay(d.date)}', sub: 'Only today and earlier days can be logged', kind: ToastKind.info);
      return;
    }
    final ml = d.waterMl, goal = d.waterGoal;
    if (delta < 0 && ml <= 0) {
      showToast(context, 'Nothing to remove', sub: 'No water logged yet', kind: ToastKind.info);
      return;
    }
    final now = (ml + delta).clamp(0, 10000);
    final left = goal - now, g = (left / 250).ceil();
    c.water(delta);
    if (delta > 0 && ml < goal && now >= goal) {
      showToast(context, 'Water goal complete!', sub: '${litres(now)} ${d.isToday ? 'today' : 'on ${fdDay(d.date)}'}', kind: ToastKind.star);
    } else if (left > 0) {
      showToast(context, delta > 0 ? '${litres(left)} to go' : 'Removed 250 ml · ${litres(now)} logged', sub: '${glasses(g)} more', kind: delta > 0 ? ToastKind.water : ToastKind.info);
    } else {
      showToast(context, '${litres(now)} ${d.isToday ? 'today' : 'on ${fdDay(d.date)}'}', sub: 'Goal complete', kind: ToastKind.water);
    }
  }

  Widget _waterCard(FoodDay d) {
    final ml = d.waterMl, goal = d.waterGoal;
    final gl = (ml / 250).round(), leftG = ((goal - ml) / 250).ceil().clamp(0, 999);
    final bars = (goal / 250).round().clamp(4, 20);
    return ChCard(children: [
      ChHead(
        lead: const ChIcon(AppIcons.water, tone: ChTone.warm),
        title: 'Water',
        sub: ml >= goal ? 'Goal complete · nice work' : '${litres(goal - ml)} to go · ${glasses(leftG)} more',
      ),
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 6, children: [
        Text(litres(ml), style: AppText.s(30, W.w8, ls: -0.6)),
        Flexible(child: Text('/ ${litres(goal)} · ${glasses(gl)}', style: AppText.s(13, W.w6, color: AppColors.muted))),
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
      Row(spacing: 8, children: [
        chSm('−250 ml', () => _water(-250)),
        chSm('+250 ml · 1 glass', () => _water(250), kind: CaBtnKind.dark),
      ]),
    ]);
  }

  // ─────────────────────────────── Tabs and lists

  Widget _tabs(FoodDay d) => TwoTabs(
    labels: ['My plan', 'Food log · ${logRows(d).length}'],
    index: c.tab == 'plan' ? 0 : 1,
    onPick: (i) => c.pickTab(i == 0 ? 'plan' : 'log'),
  );

  List<Widget> _list(FoodDay d) => c.tab == 'plan' ? _plan(d) : _log(d);

  List<Widget> _plan(FoodDay d) {
    if (!d.hasPlan || d.meals.isEmpty) {
      return [
        ChCard(children: [
          ChHead(lead: const ChIcon(AppIcons.food, tone: ChTone.green), title: 'No meal plan yet', sub: 'Your coach adds your meal plan. You can still log what you eat.'),
          if (d.isToday) CaButton('Log food', kind: CaBtnKind.dark, small: true, icon: AppIcons.plus, onPressed: _logFood),
        ]),
      ];
    }
    final next = d.isToday ? d.meals.where((m) => m.open).firstOrNull : null;
    return [
      for (final m in d.meals) _meal(d, m, next: m == next),
      if (d.isToday) FdElse('Ate something else', icon: AppIcons.plus, onTap: _logFood),
    ];
  }

  String _pill(FoodDay d, FMeal m, bool next) {
    if (m.logged) return 'Logged';
    if (m.skipped) return 'Skipped';
    if (_future(d)) return 'Planned';
    if (_past(d)) return 'Missed';
    return next ? 'Next' : 'To log';
  }

  Widget _meal(FoodDay d, FMeal m, {required bool next}) {
    final today = d.isToday;
    final pill = _pill(d, m, next);
    final dim = m.skipped || (_past(d) && !m.logged);
    final line = m.skipped ? 'Skipped · not counted today' : (m.logged && m.loggedAt != null ? 'Logged ${fdClock(m.loggedAt!)} · ${m.line}' : m.line);
    final swaps = today && m.open && d.allowSwaps;
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: next ? AppColors.accentRing : AppColors.line),
        boxShadow: next ? const [BoxShadow(color: AppColors.accentSoft, spreadRadius: 3)] : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        Row(spacing: 8, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: m.name, style: AppText.s(15, W.w8)),
                  TextSpan(text: '  · ${mealTime(m.timeRaw)}', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(line, style: AppText.s(12, W.w6, color: AppColors.muted)),
            ]),
          ),
          if (m.logged && m.photo != null) FdPhoto(m.photo!, name: m.name),
          fdPill(pill),
          if (today) CaIconBtn(AppIcons.menu, tooltip: 'Meal options', onTap: () => _menu(m)),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final it in m.items)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
              child: Row(spacing: 8, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(it.name, style: AppText.s(13.5, W.w7)),
                    Text.rich(TextSpan(children: [
                      TextSpan(text: it.amount),
                      if (it.swappedFrom.isNotEmpty) TextSpan(text: ' · swapped from ${it.swappedFrom}', style: AppText.s(12, W.w6, color: AppColors.accentText)),
                    ]), style: AppText.s(12, W.w4, color: AppColors.muted)),
                  ]),
                ),
                Text('${inNum(it.kcal)} kcal', style: AppText.s(12, W.w7, color: AppColors.text2)),
                if (swaps && it.swaps > 0) _swapBtn(() => showSwapSheet(context, c, m, it)),
              ]),
            ),
        ]),
        if (today && m.open)
          Row(spacing: 8, children: [
            Expanded(child: fdBtn('Edit portions', () => showPortionsSheet(context, c, m), icon: AppIcons.edit)),
            Expanded(
              child: Builder(
                builder: (bc) => fdBtn('Mark as eaten', () => _eatMenu(bc, m), icon: AppIcons.check, trailing: AppIcons.chevronDown, kind: next ? CaBtnKind.pri : CaBtnKind.dark),
              ),
            ),
          ])
        else if (today && m.logged)
          _doneBtn(m)
        else if (today && m.skipped)
          fdBtn('Eaten after all', () => _eat(m), icon: AppIcons.check),
      ]),
    );
    return dim ? Opacity(opacity: .75, child: card) : card;
  }

  Widget _swapBtn(VoidCallback onTap) => Semantics(
    button: true,
    child: Hover(
      onTap: onTap,
      builder: (_, h, _) => Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(color: h ? AppColors.outlineHover : AppColors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.line)),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
          const AppIcon(AppIcons.swap, size: 13, color: AppColors.text),
          Text('Swap', style: AppText.s(12, W.w7, h: 1)),
        ]),
      ),
    ),
  );

  /// `fd-done`: "✓ Logged · Undo".
  Widget _doneBtn(FMeal m) => Semantics(
    button: true,
    label: '${m.name} logged. Undo',
    child: Hover(
      onTap: () => _uneat(m),
      builder: (_, h, _) => Container(
        height: CaWeb.of(context) ? 32 : 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: h ? AppColors.outlineHover : AppColors.white, borderRadius: BorderRadius.circular(CaWeb.of(context) ? 8 : 10), border: Border.all(color: AppColors.line)),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
          const AppIcon(AppIcons.check, size: 15, color: AppColors.okSolid),
          Text('Logged · Undo', style: AppText.s(13, W.w7, color: AppColors.okText, h: 1)),
        ]),
      ),
    ),
  );

  // ─────────────────────────────── Meal actions

  /// "Mark as eaten ▾": with a photo of the meal (optional) or without.
  void _eatMenu(BuildContext anchor, FMeal m) => showAppMenu(anchor, width: 290, [
    if (anchor.isPhone) MenuEntry.header('Mark ${m.name} as eaten'),
    MenuEntry('Upload photo and mark as eaten', icon: AppIcons.camera, onTap: () => _eatWithPhoto(m)),
    MenuEntry('Mark as eaten without a photo', icon: AppIcons.check, onTap: () => _eat(m)),
  ]);

  Future<void> _eatWithPhoto(FMeal m) async {
    final photo = await pickMealPhoto(context, m.name);
    if (photo == null || !mounted) return;
    _eat(m, photo: photo);
  }

  Future<void> _eat(FMeal m, {String? photo}) async {
    final d = c.data!;
    final t = d.target;
    final nt = d.eaten[0] + m.kcal, np = d.eaten[1] + m.protein;
    final all = d.meals.every((x) => x == m || !x.open);
    try {
      final f = c.meal(m, 'eat', {'photo': ?photo});
      if (all) {
        showToast(context, 'All meals logged for today',
            sub: '${inNum(nt)} kcal${t[0] > 0 && nt > t[0] ? ' · ${inNum(nt - t[0])} kcal over' : ''} · ${np.round()} g protein', kind: ToastKind.star, action: 'Undo', onAction: () => _undoEat(m.id));
      } else {
        final left = t[0] - nt;
        showToast(context, '${m.name} logged',
            sub: '${inNum(m.kcal)} kcal · ${left >= 0 ? '${inNum(left)} kcal left' : '${inNum(-left)} kcal over'}${photo != null ? ' · photo added' : ''}',
            kind: ToastKind.ok, action: 'Undo', onAction: () => _undoEat(m.id));
      }
      await f;
    } on ApiError catch (e) {
      if (mounted) fdError(context, e);
    }
  }

  void _undoEat(int id) {
    final m = c.data?.meals.where((x) => x.id == id).firstOrNull;
    if (m != null) c.meal(m, 'unlog').catchError((_) {});
  }

  Future<void> _uneat(FMeal m) async {
    final d = c.data!;
    try {
      final f = c.meal(m, 'unlog');
      showToast(context, '${m.name} un-logged', sub: '${inNum(m.kcal)} kcal removed from ${d.isToday ? 'today' : fdWd[d.date.weekday - 1]}', kind: ToastKind.del);
      await f;
    } on ApiError catch (e) {
      if (mounted) fdError(context, e);
    }
  }

  void _menu(FMeal m) => showMealMenu(
    context,
    c,
    m,
    onSwap: () => showSwapSheet(context, c, m, m.items.firstWhere((i) => i.swaps > 0)),
    onEdit: () => showPortionsSheet(context, c, m),
    onSkip: () async {
      try {
        final f = c.meal(m, 'skip');
        showToast(context, '${m.name} skipped', sub: 'Try to get your protein in the next meal', kind: ToastKind.warn, action: 'Undo', onAction: () {
          final again = c.data?.meals.where((x) => x.id == m.id).firstOrNull;
          if (again != null) c.meal(again, 'unskip').catchError((_) {});
        });
        await f;
      } on ApiError catch (e) {
        if (mounted) fdError(context, e);
      }
    },
  );

  // ─────────────────────────────── Food log tab

  List<Widget> _log(FoodDay d) {
    final rows = logRows(d);
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        child: rows.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Nothing logged on ${d.isToday ? 'today' : fdDay(d.date)}.', textAlign: TextAlign.center, style: AppText.s(13, W.w4, color: AppColors.muted)),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (i, r) in rows.indexed) _logRow(d, r, first: i == 0),
              ]),
      ),
      if (d.isToday)
        Row(spacing: 8, children: [
          Expanded(child: CaButton('Log food', kind: CaBtnKind.dark, icon: AppIcons.plus, onPressed: _logFood)),
          Expanded(child: CaButton('Copy yesterday', kind: CaBtnKind.out, icon: AppIcons.copy, onPressed: _copy)),
        ])
      else
        fdCap('You can only add food to today. Tap Today in the strip above to log.'),
    ];
  }

  Widget _logRow(FoodDay d, FdLogRow r, {required bool first}) => Semantics(
    button: true,
    child: Hover(
      onTap: () => showEntrySheet(context, c, r, onEdit: () => showPortionsSheet(context, c, r.meal!), onUneat: () => _uneat(r.meal!)),
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: AppColors.line))),
        child: Row(spacing: 10, children: [
          SizedBox(width: 58, child: Text(fdClock(r.time), style: AppText.s(12, W.w7, color: AppColors.muted))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text(r.title, style: AppText.s(13.5, W.w7, color: h ? AppColors.accentText : AppColors.text)),
              Text(r.sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w4, color: AppColors.muted)),
            ]),
          ),
          if (r.photo != null) FdPhoto(r.photo!, name: r.title),
          Text('${inNum(r.kcal)} kcal', style: AppText.s(12, W.w7, color: AppColors.text2)),
          AppIcon(AppIcons.chevronRight, size: 16, color: h ? AppColors.accentText : AppColors.muted),
        ]),
      ),
    ),
  );

  Future<void> _copy() async {
    try {
      final n = await c.copyYesterday();
      if (!mounted) return;
      if (n == 0) {
        showToast(context, 'Nothing to copy', sub: 'You did not log anything yesterday', kind: ToastKind.info);
      } else {
        showToast(context, n < 0 ? 'Copying yesterday' : 'Copied $n ${n == 1 ? 'food' : 'foods'} from yesterday',
            sub: n < 0 ? 'It will show here once you are back online' : 'Added to today’s food log', kind: ToastKind.ok);
      }
    } on ApiError catch (e) {
      if (mounted) fdError(context, e);
    }
  }
}

class _DashLine extends StatelessWidget {
  const _DashLine();
  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(double.infinity, 1.5), painter: _DashPainter());
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.wkToday
      ..strokeWidth = 1.5;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, 0), Offset((x + 4).clamp(0, size.width), 0), p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => false;
}
