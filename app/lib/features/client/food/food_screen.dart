import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/animated_rows.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../home/home_model.dart' show inNum, mealTime;
import '../home/home_parts.dart';
import '../train/train_parts.dart' show TwoTabs;
import 'food_model.dart';
import 'food_parts.dart';
import 'food_sheets.dart';
import '../water/water.dart';
import '../../../core/widgets/tooltip.dart';

/// Food (boards `ClientMealNutrition` phone and `ClientMealNutritionWeb`): the day strip, calories, this week,
/// water, then My plan (the meals to eat) or the Food log of the picked day. On a wide web page the tabs stay
/// put and only the meal cards scroll.
class ClientFoodScreen extends StatefulWidget {
  const ClientFoodScreen({super.key, this.meal, this.water = false});

  /// `/food?meal=<id>` (Home → Ate it): open today's plan scrolled to this meal (C17).
  final int? meal;

  /// `/food?water=1` (the water reminder): open today's water sheet once the day is loaded.
  final bool water;
  @override
  State<ClientFoodScreen> createState() => _ClientFoodScreenState();
}

class _ClientFoodScreenState extends State<ClientFoodScreen> {
  final c = FoodController();

  /// Photos picked for a meal that is not marked as eaten yet (meal id → data URL).
  /// Photos picked for a meal not logged yet (up to 4); one Mark as eaten logs it with all of them (Probid 2026-10-31).
  final Map<int, List<String>> _photos = {};

  final Map<int, GlobalKey> _mealKeys = {};
  int? _flash;

  @override
  void initState() {
    super.initState();
    if (widget.meal != null) {
      c.tab = 'plan';
      c.addListener(_goToMeal);
    }
    if (widget.water) c.addListener(_openWater);
    c.start();
  }

  void _openWater() {
    final d = c.data;
    if (d == null) return;
    c.removeListener(_openWater);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && d.waterAssigned) _waterSheet(d);
    });
  }

  /// Once the day is on screen: scroll to the meal Home asked for and ring it for a moment.
  void _goToMeal() {
    if (c.data == null) return;
    c.removeListener(_goToMeal);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _mealKeys[widget.meal]?.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(ctx, alignment: .08, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
      setState(() => _flash = widget.meal);
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (mounted) setState(() => _flash = null);
      });
    });
  }

  @override
  void dispose() {
    c.dispose();
    _stripCtl?.dispose();
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
            CutText(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w6, color: AppColors.muted)),
          ]),
        ),
        chSm('Log food', _logFood, icon: AppIcons.plus, kind: CaBtnKind.dark),
      ]),
    );
  }

  void _logFood([String? meal]) {
    final d = c.data;
    // yesterday: Log food adds to yesterday (Probid 2026-11-03); any other past day goes back to today
    final y = d != null && d.isYesterday;
    if (d != null && !d.isToday && !y) c.pick(c.today);
    final q = [if (meal != null) 'meal=${Uri.encodeComponent(meal)}', if (y) 'date=${ymd(d.date)}'];
    context.go(q.isEmpty ? '/food/log' : '/food/log?${q.join('&')}');
  }

  /// Last week and this week side by side, scrolled to this week; on a Monday it starts at last Saturday, so
  /// yesterday and the day before show (Probid A8). Swipe right for the rest of last week.
  Widget _strip(FoodDay d, {required bool web}) {
    final monday = DateUtils0.dateOnly(c.today.subtract(Duration(days: c.today.weekday - 1)));
    final narrow = MediaQuery.sizeOf(context).width < 1180;
    final pad = web ? 5.0 : 8.0;
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: LayoutBuilder(builder: (_, b) {
        final w = b.maxWidth / 7;
        final start = c.today.weekday == 1 ? 5 : 7;
        return SizedBox(
          height: web ? 48 : 72,
          child: ListView.builder(
            controller: _stripCtl ??= ScrollController(initialScrollOffset: w * start),
            scrollDirection: Axis.horizontal,
            itemExtent: w,
            itemCount: 14,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _day(d, monday.add(Duration(days: i - 7)), web: web, narrow: narrow),
            ),
          ),
        );
      }),
    );
  }

  ScrollController? _stripCtl;

  Widget _day(FoodDay d, DateTime day, {required bool web, required bool narrow}) {
    final on = DateUtils0.same(day, d.date), real = DateUtils0.same(day, c.today), future = day.isAfter(c.today);
    final w = [...d.strip, ...d.week].where((x) => DateUtils0.same(DateTime.parse('${x['date']}'), day)).firstOrNull;
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
                // plan food in blue, then food outside the plan in amber (Probid 2026-11-03)
                parts: future || over || zero ? const [] : [
                  for (final (v, col) in [(_eatenSplit(d).$1, AppColors.accent), (_eatenSplit(d).$2, AppColors.amberSolid)])
                    if (v > 0 && t[0] > 0) (v / t[0], col),
                ],
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
            if (!future) _split(d),
            fdCap(cap),
          ]),
        ),
      ),
    );
  }

  /// Where today's calories come from, as one bar against the target: plan foods eaten (blue), food outside the plan
  /// (amber), plan foods skipped (grey, they did not count), and what is still open (Probid A5).
  /// Eaten plan food, food outside the plan, skipped plan food (kcal).
  (double, double, double) _eatenSplit(FoodDay d) {
    var plan = 0.0, skip = 0.0;
    for (final m in d.meals) {
      for (final i in m.items) {
        if (i.state == 'skipped' || m.skipped) {
          skip += i.kcalExact;
        } else if (i.state == 'eaten' || (m.logged && i.state.isEmpty)) {
          plan += i.kcalExact;
        }
      }
    }
    final off = d.log.where((e) => !(e.fromPlan && e.meal != null)).fold(0.0, (a, e) => a + e.at(e.quantity)[0]);
    return (plan, off, skip);
  }

  Widget _split(FoodDay d) {
    final (plan, off, skip) = _eatenSplit(d);
    if (plan + off + skip <= 0) return const SizedBox.shrink();
    final tg = d.target[0] > 0 ? d.target[0] : plan + off + skip;
    final total = math.max(tg, plan + off + skip);
    final rest = math.max(0.0, total - plan - off - skip);
    final parts = [(plan, AppColors.accent), (off, AppColors.amberSolid), (skip, AppColors.line2), (rest, AppColors.sub)];
    Widget key(Color c, String l, double v) => Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          Text('$l ${inNum(v.round())}', style: AppText.s(11.5, W.w6, color: AppColors.text2)),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: SizedBox(
          height: 8,
          child: Row(children: [
            for (final (v, col) in parts)
              if (v > 0) Expanded(flex: math.max(1, (v / total * 1000).round()), child: ColoredBox(color: col)),
          ]),
        ),
      ),
      Wrap(spacing: 12, runSpacing: 4, children: [
        key(AppColors.accent, 'Plan', plan),
        if (off > 0) key(AppColors.amberSolid, 'Off-plan', off),
        if (skip > 0) key(AppColors.line2, 'Skipped', skip),
      ]),
    ]);
  }

  // ─────────────────────────────── This week (`nv-wk`)

  Widget _weekCard(FoodDay d) {
    final tg = d.target[0];
    final wk = d.week;
    final kc = [for (final w in wk) ((w['kcal'] as num?) ?? 0).toDouble()];
    // On a Monday the card starts with last Saturday and Sunday (Probid A9); the average is this week's only.
    final last = [for (final w in wk) w['last_week'] == true];
    final logged = [for (var i = 0; i < wk.length; i++) if (kc[i] > 0) i];
    final mine = [for (final i in logged) if (!last[i]) i];
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
    final avgK = mine.isEmpty ? 0 : mine.fold(0.0, (a, i) => a + kc[i]) / mine.length;
    final avgP = mine.isEmpty ? 0 : mine.fold(0.0, (a, i) => a + ((wk[i]['protein'] as num?) ?? 0)) / mine.length;
    // the week of the day picked: This week, Last week, or Week of 19 Oct (Probid 2026-11-03)
    final mon = DateTime.parse('${wk[last.contains(false) ? last.indexOf(false) : 0]['date']}');
    final thisMon = c.today.subtract(Duration(days: c.today.weekday - 1));
    final ago = (DateUtils0.dateOnly(thisMon).difference(DateUtils0.dateOnly(mon)).inDays / 7).round();
    final wkName = ago <= 0 ? 'This week' : ago == 1 ? 'Last week' : 'Week of ${fdDay(mon).split(', ').last}';
    final sm = (wk[sel]['meals'] as num?)?.toInt() ?? 0, sl = (wk[sel]['meals_logged'] as num?)?.toInt() ?? 0;
    return ChCard(gap: 10, children: [
      Row(children: [
        Expanded(child: Text(wkName, style: AppText.s(15, W.w8))),
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
                      return Opacity(opacity: last[i] && !on ? .55 : 1, child: Column(spacing: 4, children: [
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
                      ]));
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
        // one line, never wrapped (Probid 2026-11-03): the day, then its numbers shrinking to fit
        child: Row(spacing: 10, children: [
          Text('${fdDay(sd)}${sel == todayAt ? ' · today' : last[sel] ? ' · last wk' : ''}', maxLines: 1, style: AppText.s(12.5, W.w8)),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: kc[sel] > 0
                    ? Row(spacing: 6, children: [
                        Text('${inNum(kc[sel])} kcal', style: AppText.s(12.5, W.w8)),
                        Text('·', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
                        Text('$sp g P', style: AppText.s(12.5, W.w6, color: AppColors.text2)),
                        if (sm > 0) ...[
                          Text('·', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
                          Text('$sl/$sm meals', style: AppText.s(12.5, W.w6, color: AppColors.text2)),
                        ],
                      ])
                    : Text(sd.isAfter(c.today) ? 'Coming up' : (sel == todayAt ? 'Nothing logged yet' : 'Nothing logged'),
                        maxLines: 1, style: AppText.s(12.5, W.w6, color: AppColors.text2)),
              ),
            ),
          ),
        ]),
      ),
      // the week's summary, its label in bold (Probid 2026-11-03)
      Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: '$wkName  ', style: AppText.s(13, W.w8)),
          TextSpan(
            text: mine.isEmpty
                ? 'nothing logged yet'
                : 'avg ${inNum(avgK)} kcal · ${avgP.round()} g protein',
            style: AppText.s(13, W.w6, color: AppColors.text2),
          ),
        ])),
        if (mine.isNotEmpty || last.contains(true))
          Text(
            '${mine.isEmpty ? '' : 'on ${mine.length} logged ${mine.length == 1 ? 'day' : 'days'}'}${mine.isNotEmpty && last.contains(true) ? ' · ' : ''}${last.contains(true) ? 'first 2 bars are last Sat and Sun' : ''}',
            style: AppText.s(11.5, W.w5, color: AppColors.muted),
          ),
      ]),
    ]);
  }

  // ─────────────────────────────── Water

  Widget _waterCard(FoodDay d) => WaterCard(
        assigned: d.waterAssigned,
        ml: d.waterMl,
        goal: d.waterGoal,
        when: d.isToday ? 'today' : 'on ${fdDay(d.date)}',
        canLog: d.isToday || d.isYesterday,
        onLog: () => _waterSheet(d),
        onHistory: _waterHistory,
      );

  /// One sheet for water (A10): − / the day's amount / +, a tap on the amount types it, Save sets the day.
  void _waterSheet(FoodDay d) {
    if (!d.isToday && !d.isYesterday) {
      showToast(context, _future(d) ? 'You can log water on ${fdDay(d.date)}' : 'Water can be logged for today and yesterday only',
          sub: 'Like meals: today and yesterday', kind: ToastKind.info);
      return;
    }
    showWaterSheet(context,
        when: d.isToday ? 'today' : fdDay(d.date),
        goal: d.waterGoal,
        current: d.waterMl,
        save: (ml) => c.setWater(ml).catchError((Object e) {
              if (mounted && e is ApiError) fdError(context, e);
            }));
  }

  Future<void> _waterHistory() => showWaterHistorySheet(context);

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
          // No Log food here (Probid 2026-11-04): meals come from the plan, so there is nothing to log into yet.
          ChHead(lead: const ChIcon(AppIcons.food, tone: ChTone.green), title: 'No meal plan yet', sub: 'Your coach adds your meal plan. Logging opens once it is ready.'),
        ]),
      ];
    }
    final next = d.isToday ? d.meals.where((m) => m.open).firstOrNull : null;
    return [
      for (final m in d.meals) KeyedSubtree(key: _mealKeys.putIfAbsent(m.id, GlobalKey.new), child: _meal(d, m, next: m == next || _flash == m.id)),
      if (d.isToday || d.isYesterday) FdElse(d.isToday ? 'Ate something else' : 'Ate something else yesterday', icon: AppIcons.plus, onTap: _logFood),
    ];
  }

  String _pill(FoodDay d, FMeal m, bool next) {
    if (m.logged) return 'Logged';
    if (m.skipped) return 'Skipped';
    if (m.partly) return 'Partly eaten';
    if (_future(d)) return 'Planned';
    if (_past(d)) return 'Missed';
    return next ? 'Next' : 'To log';
  }

  Widget _meal(FoodDay d, FMeal m, {required bool next}) {
    // Today, and yesterday for a missed meal: the same buttons (photo, Edit portions, Mark as eaten, the menu)
    // (Probid 2026-11-03). Older days only read.
    final today = d.isToday || d.isYesterday;
    final pill = _pill(d, m, next);
    final dim = m.skipped || (_past(d) && !m.logged);
    // Eaten next to what the coach assigned (Phase 3): "Logged 8:10 am · ate 446 of 259 kcal".
    final ate = m.eaten;
    final ateLine = 'ate ${inNum(ate[0].round())} of ${inNum(m.assignedKcal)} kcal';
    final line = m.skipped
        ? 'Skipped · not counted today'
        : m.logged
        ? '${m.loggedAt != null ? 'Logged ${fdClock(m.loggedAt!)} · ' : ''}$ateLine'
        : m.partly
        ? '${ateLine[0].toUpperCase()}${ateLine.substring(1)} so far'
        : m.line;
    final lock = d.isToday && m.open && m.locked;
    final swaps = today && m.open && d.allowSwaps && !lock;
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
              CutText.rich(
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
          fdPill(pill),
          if (today) CaIconBtn(AppIcons.dots, tooltip: 'Meal options', onTap: () => lock ? _lockedToast(m) : _menu(m)),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final it in m.items) _itemRow(d, m, it, swaps: swaps),
        ]),
        ..._extras(d, m),
        if (today && m.open && _photos[m.id] != null) _photoBar(m),
        // a logged meal's photos under its foods, not up by the menu: thumbnails, the count, tap = view (Probid A3)
        if (m.logged && m.photos.isNotEmpty)
          Row(spacing: 8, children: [
            for (final p in m.photos) FdPhoto(p, name: m.name, size: 44, group: m.photos),
            Expanded(child: Text('${m.photos.length} ${m.photos.length == 1 ? 'photo' : 'photos'}', style: AppText.s(12, W.w6, color: AppColors.muted))),
          ]),
        // Before 30 min ahead of the meal nothing can be logged, skipped or changed (Probid 2026-10-30).
        if (lock)
          _lockedBar(m)
        else if (today && m.open)
          Row(spacing: 8, children: [
            Expanded(child: fdBtn('Edit portions', () => showPortionsSheet(context, c, m), icon: AppIcons.edit)),
            Expanded(
              child: _photos[m.id] != null
                  // A photo is picked: one tap logs the meal with it.
                  ? fdBtn('Mark as eaten', () => _eat(m, photos: _photos[m.id]), icon: AppIcons.check, kind: next ? CaBtnKind.pri : CaBtnKind.dark)
                  : Builder(
                      builder: (bc) => fdBtn('Mark as eaten', () => _eatMenu(bc, m), icon: AppIcons.check, trailing: AppIcons.chevronDown, kind: next ? CaBtnKind.pri : CaBtnKind.dark),
                    ),
            ),
          ])
        else if (m.logged)
          // A logged meal: its foods are not tapped any more, Preview shows it all (Probid A7).
          Row(spacing: 8, children: [
            Expanded(child: fdBtn('Preview this meal', () => _preview(d, m), icon: AppIcons.eye)),
            if (today) Expanded(child: _doneBtn(m)),
          ])
        else if (today && m.skipped)
          fdBtn('I ate it', () => _eatAfterAll(m), icon: AppIcons.check),
      ]),
    );
    return dim ? Opacity(opacity: .75, child: card) : card;
  }

  /// One planned food: its amount, an Edited tag when today's portion is not the planned one, and its own state
  /// (Eaten / Skipped). On today a tap opens what she can do with just this food.
  Widget _itemRow(FoodDay d, FMeal m, FItem it, {required bool swaps}) {
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      child: Row(spacing: 8, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // a food already decided (eaten or skipped) reads lighter than the ones still to log (Probid 2026-10-30)
            Text(it.name, style: AppText.s(13.5, W.w7, color: it.state.isEmpty && !m.logged ? AppColors.text : AppColors.muted)),
            Row(children: [
              Flexible(child: Text(it.amount, style: AppText.s(12, W.w4, color: AppColors.muted))),
              if (it.edited) fdTag('Edited'),
            ]),
            // on its own line, never cut off next to the Edited badge (Probid 2026-11-03)
            if (it.swappedFrom.isNotEmpty)
              Text('Swapped from ${it.swappedFrom}', style: AppText.s(12, W.w6, color: AppColors.accentText)),
          ]),
        ),
        // a logged meal shows Eaten on each food it counted too (Probid 2026-10-30)
        if (it.state == 'eaten' || (m.logged && it.state.isEmpty)) fdPill('Eaten', small: true),
        if (it.state == 'skipped' && !m.skipped) fdPill('Skipped', small: true),
        Text('${inNum(it.kcal)} kcal',
            style: AppText.s(12, W.w7, color: AppColors.text2).copyWith(decoration: it.state == 'skipped' ? TextDecoration.lineThrough : null)),
      ]),
    );
    return Semantics(
      button: true,
      label: '${it.name}. ${switch (it.state) { 'eaten' => 'Eaten', 'skipped' => 'Skipped', _ => 'Not logged yet' }}',
      child: m.logged ? row : Hover(onTap: () => _itemMenu(d, m, it, swaps: swaps), builder: (_, h, _) => Opacity(opacity: h ? .8 : 1, child: row)),
    );
  }

  /// A meal not open yet: what she sees in place of Edit portions · Mark as eaten.
  Widget _lockedBar(FMeal m) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(10)),
    child: Row(spacing: 8, children: [
      const AppIcon(AppIcons.lock, size: 15, color: AppColors.muted),
      Expanded(child: Text('${m.opensLine} · you can log it from then', style: AppText.s(12.5, W.w6, color: AppColors.text2))),
    ]),
  );

  void _lockedToast(FMeal m) => showToast(context, '${m.name} ${m.opensLine.toLowerCase()}', sub: 'You can log, skip or change it from 30 min before its time.', kind: ToastKind.info);

  /// One food, like a food on Log food (Probid 2026-10-30): the amount (a stepper on today, Save portion when
  /// changed), what the coach planned, four macro boxes, then on today what she can do with it: Ate this · Skip this
  /// food · Not logged yet · Set to default · Swap food · Had something else.
  void _itemMenu(FoodDay d, FMeal m, FItem it, {required bool swaps}) {
    final q = ValueNotifier(it.quantity);
    final canEdit = (d.isToday || d.isYesterday) && !m.skipped && !(m.open && m.locked);
    showAppSheet(
      context,
      listen: q,
      title: it.name,
      sub: '${m.name}, ${mealTime(m.timeRaw)}${it.swappedFrom.isEmpty ? '' : ' · swapped from ${it.swappedFrom}'}',
      webWidth: 440,
      builder: (ctx) {
        final changed = q.value != it.quantity;
        final planned = it.plannedQuantity > 0 ? it.plannedQuantity : it.quantity;
        final details = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          Column(spacing: 2, children: [
            if (canEdit)
              NumStepper(
                value: q.value,
                step: portionStep(it),
                min: portionStep(it) == 10 ? 5 : .5,
                max: it.unit == 'g' ? 2000 : 50,
                big: true,
                decimals: it.unit != 'g',
                name: '${it.name} amount',
                label: (v) => amtOf(it.unit, v),
                onChanged: (v) => q.value = v,
              )
            else
              Text(it.amount, style: AppText.s(22, W.w8)),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Planned ${amtOf(it.unit, planned)}', style: AppText.s(12, W.w6, color: AppColors.muted)),
              if (q.value != planned) fdTag('Edited'),
            ]),
          ]),
          fdMacroBoxes(it.at(q.value)),
          if (changed)
            Row(spacing: 8, children: [
              Expanded(child: CaButton('Reset', kind: CaBtnKind.out, small: true, onPressed: () => q.value = it.quantity)),
              Expanded(child: CaButton('Save portion', small: true, icon: AppIcons.check, onPressed: () {
                Navigator.of(ctx).pop();
                _changeLogged(m, () => _savePortion(m, it, q.value));
              })),
            ]),
        ]);
        if (!(d.isToday || d.isYesterday) || (m.open && m.locked)) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            details,
            if (d.isToday) fdCap('${m.opensLine}. You can log, skip or swap it from then.'),
          ]);
        }
      void go(Future<void> Function() f) {
        Navigator.of(ctx).pop();
        f().catchError((Object e) {
          if (mounted && e is ApiError) fdError(context, e);
        });
      }

      final rows = <(AppIconData, String, String, bool, Future<void> Function())>[
        if (it.state != 'eaten') (AppIcons.check, 'Ate this', 'Counts ${inNum(it.kcal)} kcal today', false, () async {
          if (await _didEat(it.name, '${it.amount} · ${inNum(it.kcal)} kcal will count today.')) await _item(m, it, 'eat');
        }),
        if (it.state != 'skipped')
          (AppIcons.close, 'Skip this food', 'It will not count today', true, () async {
            // asks first (Probid 2026-11-03, A4)
            if (await confirmAction(context,
                title: 'Skip ${it.name}?', body: '${it.amount} · ${inNum(it.kcal)} kcal will not count today. You can log it again later.', confirm: 'Skip food', danger: true, icon: AppIcons.close)) {
              await _item(m, it, 'skip');
            }
          }),
        if (it.state.isNotEmpty)
          (AppIcons.undo, 'Not logged yet', 'Take it off today’s log', false, () async {
            // taking an eaten food off asks first, like any change to a logged food (Probid 2026-10-30)
            if (it.state == 'eaten' &&
                !await confirmAction(context,
                    title: 'Take ${it.name} off today’s log?', body: '${inNum(it.kcal)} kcal comes off today. You can mark it again.', confirm: 'Take it off', danger: true)) {
              return;
            }
            await _item(m, it, 'reset');
          }),
        if (it.edited && !changed) (AppIcons.edit, 'Set to default', 'Back to the planned ${amtOf(it.unit, it.plannedQuantity)}', false, () => _setDefault(m, it)),
        // Swap lives here now, not on the row (Probid 2026-10-30).
        if (swaps && it.swaps > 0 && it.state.isEmpty)
          (AppIcons.swap, 'Swap food', '${it.swaps} option${it.swaps == 1 ? '' : 's'} from your coach', false, () async => showSwapSheet(context, c, m, it)),
      ];
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        details,
        const SizedBox(height: 6),
        for (final (i, r) in rows.indexed) FdMenuItem(first: i == 0, icon: r.$1, title: r.$2, sub: r.$3, danger: r.$4, onTap: () => go(r.$5)),
        FdMenuItem(icon: AppIcons.search, title: 'Had something else', sub: 'Log what you ate instead', onTap: () {
          Navigator.of(ctx).pop();
          if (it.state != 'skipped') _item(m, it, 'skip').catchError((_) {});
          context.go('/food/log?meal=${Uri.encodeComponent(m.name)}');
        }),
      ]);
    },
    ).whenComplete(() => Future.delayed(const Duration(milliseconds: 600), q.dispose));
  }

  /// Save portion on a food's sheet: this food's new amount, the other foods' changes kept.
  Future<void> _savePortion(FMeal m, FItem it, double v) async {
    try {
      await c.meal(m, 'portions', {
        'portions': {
          for (final i in m.items)
            if (i == it) '${i.item}': v else if (i.edited) '${i.item}': i.quantity,
        },
      });
      if (mounted) showToast(context, '${it.name} · ${amtOf(it.unit, v)}', sub: '${inNum(it.at(v)[0])} kcal today', kind: ToastKind.ok);
    } on ApiError catch (e) {
      if (mounted) fdError(context, e);
    }
  }

  Future<void> _item(FMeal m, FItem it, String action) async {
    final f = c.meal(m, 'item', {'item': it.item, 'action': action});
    showToast(
      context,
      switch (action) { 'eat' => '${it.name} logged', 'skip' => '${it.name} skipped', _ => '${it.name} not logged yet' },
      sub: switch (action) { 'eat' => '${inNum(it.kcal)} kcal added to today', 'skip' => 'It will not count today', _ => 'Taken off today’s log' },
      kind: action == 'eat' ? ToastKind.ok : (action == 'skip' ? ToastKind.warn : ToastKind.del),
    );
    await f;
  }

  /// Set to default: today's portions without this food's change.
  Future<void> _setDefault(FMeal m, FItem it) async {
    final f = c.meal(m, 'portions', {
      'portions': {for (final i in m.items) if (i.edited && i != it) '${i.item}': i.quantity},
    });
    showToast(context, 'Back to the planned portion', sub: '${it.name} · ${amtOf(it.unit, it.plannedQuantity)}', kind: ToastKind.ok);
    await f;
  }

  /// Skipped meal → "I ate it" (was "Eaten after all", Probid 2026-10-29): logs the whole meal after a "Did you eat this?" check.
  Future<void> _eatAfterAll(FMeal m) async {
    await _eat(m);
  }

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

  /// A logged meal at a glance (Probid A7): what was eaten, skipped and added, the totals, its photos, then
  /// Edit portion (the portions sheet, Edit & Log keeps it logged).
  void _preview(FoodDay d, FMeal m) {
    final xs = d.log.where((e) => e.mealName == m.name && !e.otherTime && !(e.fromPlan && e.meal != null)).toList();
    final ate = m.eaten;
    final tot = [
      ate[0] + xs.fold(0.0, (a, e) => a + e.at(e.quantity)[0]),
      ate[1] + xs.fold(0.0, (a, e) => a + e.protein),
      ate[2] + xs.fold(0.0, (a, e) => a + e.carbs),
      ate[3] + xs.fold(0.0, (a, e) => a + e.fat),
    ];
    final diff = (tot[0] - m.assignedKcal).round();
    final eaten = m.items.where((i) => i.state != 'skipped').toList(), skipped = m.items.where((i) => i.state == 'skipped').toList();
    // a coloured group like the "Did you eat this?" sheet (Probid 2026-11-03): bold heading, its kcal, food rows
    // with amount and protein · carbs · fat
    Widget group(String head, Color bg, Color ink, Color dot, List<(String, String, int, double, double, double, String?)> rows, {bool strike = false}) => Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(spacing: 6, children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              Expanded(child: Text(head, style: AppText.s(13, W.w8, color: ink))),
              Text('${inNum(rows.fold(0, (a, r) => a + r.$3))} kcal', style: AppText.s(13, W.w8, color: ink)),
            ]),
            const SizedBox(height: 4),
            for (final (n, amt, k, pr, cb, ft, tag) in rows)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: dot.withValues(alpha: .25)))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 1, children: [
                  // name (and its tag) on one line, the amount and "swapped from" on their own line so nothing is cut
                  // off next to Edited (Probid 2026-11-03)
                  Row(spacing: 8, children: [
                    // name + tag take the free width, so every kcal sits flush right (a Flexible beside a Spacer
                    // split the space and the kcal drifted per row, Probid 2026-11-03)
                    Expanded(
                      child: Row(spacing: 8, children: [
                        Flexible(child: Text(n, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w7))),
                        if (tag != null) fdTag(tag, amber: tag == 'Off-plan'),
                      ]),
                    ),
                    Text('${inNum(k)} kcal',
                        style: AppText.s(12.5, W.w7, color: AppColors.text2).copyWith(decoration: strike ? TextDecoration.lineThrough : null)),
                  ]),
                  Text(amt, style: AppText.s(12, W.w5, color: AppColors.text2)),
                  Text(macroLine(pr, cb, ft), style: AppText.s(11.5, W.w5, color: AppColors.muted)),
                ]),
              ),
          ]),
        );
    showAppSheet(
      context,
      title: m.name,
      sub: '${m.loggedAt != null ? 'Logged ${fdClock(m.loggedAt!)} · ' : ''}${mealTime(m.timeRaw)}',
      webWidth: 480,
      footerStretch: true,
      builder: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        // what she ate, against the plan, then kcal · protein · carbs · fat side by side
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(border: Border.all(color: AppColors.line2), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 8, children: [
              Text('${inNum(tot[0].round())} kcal', style: AppText.s(22, W.w8)),
              Expanded(child: Text('eaten · plan ${inNum(m.assignedKcal)}', style: AppText.s(12.5, W.w6, color: AppColors.muted))),
              if (diff != 0)
                Text('${diff > 0 ? '+' : '−'}${inNum(diff.abs())}', style: AppText.s(12.5, W.w8, color: diff > 0 ? AppColors.amberText : AppColors.okText)),
            ]),
            IntrinsicHeight(
              child: Row(children: [
                for (final (i, (l, v, col)) in [('Protein', tot[1], AppColors.accent), ('Carbs', tot[2], AppColors.nvCarbs), ('Fat', tot[3], AppColors.nvFat)].indexed) ...[
                  if (i > 0) const VerticalDivider(width: 17, thickness: 1, color: AppColors.line),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(spacing: 5, children: [
                        Container(width: 7, height: 7, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
                        Text(l, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
                      ]),
                      Text('${v.round()} g', style: AppText.s(15, W.w8)),
                    ]),
                  ),
                ],
              ]),
            ),
          ]),
        ),
        if (eaten.isNotEmpty)
          group('Eaten from your plan', AppColors.okBg, AppColors.okText, AppColors.okSolid, [
            for (final it in eaten)
              (it.name, '${it.amount}${it.swappedFrom.isNotEmpty ? ' · swapped from ${it.swappedFrom}' : ''}', it.kcal, it.protein, it.carbs, it.fat, it.edited ? 'Edited' : null),
          ]),
        if (skipped.isNotEmpty)
          group('Skipped', AppColors.sub, AppColors.text2, AppColors.line2, [
            for (final it in skipped) (it.name, it.amount, it.kcal, it.protein, it.carbs, it.fat, null),
          ], strike: true),
        if (xs.isNotEmpty)
          group('Added outside the plan', AppColors.amberBg, AppColors.amberText, AppColors.amberSolid, [
            for (final e in xs) (e.name, '${e.amount}${e.reason.isEmpty ? '' : ' · ${e.reason}'}', e.kcal, e.protein, e.carbs, e.fat, e.source == 'off_plan' ? 'Off-plan' : null),
          ]),
        if (m.photos.isNotEmpty)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
            Text('${m.photos.length} ${m.photos.length == 1 ? 'PHOTO' : 'PHOTOS'} · tap to view', style: AppText.s(10.5, W.w8, color: AppColors.muted, ls: .5)),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final p in m.photos) FdPhoto(p, name: m.name, size: m.photos.length == 1 ? 120 : 72, group: m.photos)]),
          ]),
      ]),
      footer: d.isToday || d.isYesterday
          ? (ctx) => [
                Row(spacing: 8, children: [
                  Expanded(child: CaButton('Close', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop())),
                  Expanded(
                    child: CaButton('Edit portion', icon: AppIcons.edit, onPressed: () {
                      Navigator.of(ctx).pop();
                      showPortionsSheet(context, c, m, logged: true);
                    }),
                  ),
                ]),
              ]
          : null,
    );
  }

  // ─────────────────────────────── Meal actions

  /// "Mark as eaten ▾": with a photo of the meal (optional) or without.
  /// Phone: a sheet with what gets logged and the two ways, each with a line on what happens (Probid 2026-11-03).
  void _eatMenu(BuildContext anchor, FMeal m) {
    if (!anchor.isPhone) {
      showAppMenu(anchor, width: 290, [
        MenuEntry('Upload photo and mark as eaten', icon: AppIcons.camera, onTap: () => _eatWithPhoto(m)),
        MenuEntry('Mark as eaten without a photo', icon: AppIcons.check, onTap: () => _eat(m)),
      ]);
      return;
    }
    final adds = m.items.where((i) => m.items.every((x) => x.state == 'skipped') || i.state.isEmpty).toList();
    final kcal = adds.fold(0, (a, i) => a + i.kcal);
    showAppSheet(
      context,
      title: 'Mark ${m.name} as eaten',
      sub: '${adds.length} ${adds.length == 1 ? 'food' : 'foods'} · ${inNum(kcal)} kcal · ${mealTime(m.timeRaw)}',
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FdMenuItem(
          first: true,
          icon: AppIcons.camera,
          title: 'Add a photo, then log',
          sub: 'Up to 4 photos · your coach sees them',
          onTap: () {
            Navigator.of(ctx).pop();
            _eatWithPhoto(m);
          },
        ),
        FdMenuItem(
          icon: AppIcons.check,
          title: 'Log without a photo',
          sub: '${inNum(kcal)} kcal counts ${c.data?.isToday ?? true ? 'today' : 'for yesterday'}',
          onTap: () {
            Navigator.of(ctx).pop();
            _eat(m);
          },
        ),
      ]),
    );
  }

  /// Adds one more photo (up to 4); the meal is logged only when Mark as eaten is tapped.
  Future<void> _eatWithPhoto(FMeal m) async {
    final n = _photos[m.id]?.length ?? 0;
    if (n >= 4) {
      showToast(context, 'Up to 4 photos a meal', sub: 'Remove one to add another', kind: ToastKind.info);
      return;
    }
    final photo = await pickMealPhoto(context, m.name);
    if (photo == null || !mounted) return;
    setState(() => _photos[m.id] = [...?_photos[m.id], photo]);
    showToast(context, n == 0 ? 'Photo added' : '${n + 1} photos added', sub: 'Add more or tap Mark as eaten to log ${m.name}', kind: ToastKind.info);
  }

  /// Under the foods while photos wait: each photo with its own remove, Add photo (up to 4).
  Widget _photoBar(FMeal m) {
    final ps = _photos[m.id]!;
    Future<void> drop(int i) async {
      // asks first (Probid A3)
      if (!await confirmAction(context, title: 'Delete this image?', body: 'It comes off ${m.name}. You can add another one.', confirm: 'Delete', danger: true, icon: AppIcons.trash)) return;
      if (!mounted) return;
      setState(() {
        final left = [...ps]..removeAt(i);
        left.isEmpty ? _photos.remove(m.id) : _photos[m.id] = left;
      });
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: AppColors.nextBg, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        Row(spacing: 10, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ps.length == 1 ? 'Photo ready' : '${ps.length} photos ready', style: AppText.s(13, W.w7)),
              CutText('${m.name} is not logged yet', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w4, color: AppColors.muted)),
            ]),
          ),
          if (ps.length < 4) chSm('Add photo', () => _eatWithPhoto(m), icon: AppIcons.camera),
        ]),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (i, p) in ps.indexed)
            Stack(clipBehavior: Clip.none, children: [
              FdPhoto(p, name: m.name, size: 48, group: ps), // each its own photo: no "+1" badge (Probid 2026-11-03)
              Positioned(
                top: -6,
                right: -6,
                child: Semantics(
                  button: true,
                  label: 'Remove photo ${i + 1}',
                  child: Hover(
                    onTap: () => drop(i),
                    builder: (_, h, _) => Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: h ? AppColors.badText : AppColors.text, shape: BoxShape.circle, border: Border.all(color: AppColors.white, width: 1.5)),
                      child: const AppIcon(AppIcons.close, size: 11, color: AppColors.white),
                    ),
                  ),
                ),
              ),
            ]),
        ]),
      ]),
    );
  }

  /// Foods added to this meal from Log food (outside the plan's own foods).
  List<Widget> _extras(FoodDay d, FMeal m) {
    final xs = d.log.where((e) => e.mealName == m.name && !e.otherTime && !(e.fromPlan && e.meal != null)).toList();
    if (xs.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(spacing: 6, children: [
          Text('ALSO LOGGED · OUTSIDE THE PLAN', style: AppText.s(10.5, W.w8, color: AppColors.amberText, ls: .5)),
          Expanded(child: Container(height: 1, color: AppColors.line)),
          Text('+${inNum(xs.fold(0, (a, e) => a + e.kcal))} kcal', style: AppText.s(11.5, W.w7, color: AppColors.amberText)),
        ]),
      ),
      // One line a food, like the plan's own foods (Probid 2026-10-31): name, amount, Eaten, kcal.
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, e) in xs.indexed)
          Semantics(
            button: true,
            label: '${e.name}. Eaten',
            child: Hover(
              onTap: m.logged ? null : () => _entryMenu(d, e),
              builder: (_, h, _) => Opacity(
                opacity: h ? .8 : 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
                  child: Row(spacing: 8, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Flexible(child: CutText(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7))),
                          if (e.source == 'off_plan') fdTag('Off-plan', amber: true),
                        ]),
                        CutText('${e.amount}${e.reason.isEmpty ? '' : ' · ${e.reason}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w4, color: AppColors.muted)),
                      ]),
                    ),
                    fdPill('Eaten', small: true),
                    Text('${inNum(e.kcal)} kcal', style: AppText.s(12, W.w7, color: AppColors.text2)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    ];
  }

  /// A food added outside the plan, like a planned food's sheet: its amount (a stepper on today, Save portion when
  /// changed, starting from what was logged, not the food's default), four macro boxes, then Ate it (it counts),
  /// Log more and Remove (Probid 2026-10-31).
  void _entryMenu(FoodDay d, FEntry e) {
    final q = ValueNotifier(e.quantity);
    final g = e.unit == 'g';
    final step = g ? 10.0 : (e.quantity != e.quantity.roundToDouble() ? .5 : 1.0);
    showAppSheet(
      context,
      listen: q,
      title: e.name,
      sub: '${e.mealName} · added ${fdClock(e.time)}${e.source == 'off_plan' ? ' · outside the plan' : ''}',
      webWidth: 440,
      builder: (ctx) {
        final changed = q.value != e.quantity;
        void go(Future<void> Function() f) {
          Navigator.of(ctx).pop();
          f().catchError((Object x) {
            if (mounted && x is ApiError) fdError(context, x);
          });
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          Column(spacing: 2, children: [
            if (d.isToday || d.isYesterday)
              NumStepper(
                value: q.value,
                step: step,
                min: g ? 5 : .5,
                max: g ? 2000 : 50,
                big: true,
                decimals: !g,
                name: '${e.name} amount',
                label: (v) => amtOf(e.unit, v),
                onChanged: (v) => q.value = v,
              )
            else
              Text(e.amount, style: AppText.s(22, W.w8)),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Logged ${e.amount}', style: AppText.s(12, W.w6, color: AppColors.muted)),
              if (changed) fdTag('Edited'),
            ]),
          ]),
          if (e.reason.isNotEmpty) fdCap('Why: ${e.reason}'),
          fdMacroBoxes(e.at(q.value)),
          if (changed)
            Row(spacing: 8, children: [
              Expanded(child: CaButton('Reset', kind: CaBtnKind.out, small: true, onPressed: () => q.value = e.quantity)),
              Expanded(child: CaButton('Save portion', small: true, icon: AppIcons.check, onPressed: () => go(() async {
                final v = q.value;
                await c.editEntry(e, v);
                if (mounted) showToast(context, '${e.name} · ${amtOf(e.unit, v)}', sub: '${inNum(e.at(v)[0])} kcal today', kind: ToastKind.ok);
              }))),
            ]),
          if ((d.isToday || d.isYesterday) && !changed)
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FdMenuItem(
                first: true,
                icon: AppIcons.plus,
                title: 'Log more to ${e.mealName}',
                sub: 'Search and add another food',
                onTap: () => go(() async => context.go('/food/log?meal=${Uri.encodeComponent(e.mealName)}')),
              ),
              FdMenuItem(icon: AppIcons.close, title: 'Not eaten', sub: 'Take it off today’s log · you can undo', danger: true, onTap: () => go(() async {
                await c.deleteEntry(e);
                if (!mounted) return;
                showToast(context, '${e.name} taken off', sub: '${inNum(e.kcal)} kcal off today', kind: ToastKind.del, action: 'Undo', onAction: () => c.restore(e).catchError((_) {}));
              })),
            ]),
        ]);
      },
    ).whenComplete(() => Future.delayed(const Duration(milliseconds: 600), q.dispose));
  }

  /// A meal with foods already logged as eaten asks before its portions or a swap change them (Probid 2026-10-30).
  Future<void> _changeLogged(FMeal m, VoidCallback open) async {
    if (m.anyEaten) {
      final ok = await confirmAction(context,
          title: 'Do you want to change this food which is logged?',
          body: '${m.name} is logged. Changing it updates what counts today.',
          confirm: 'Change it',
          icon: AppIcons.edit);
      if (!ok || !mounted) return;
    }
    open();
  }

  /// "Did you eat this?" before anything is logged as eaten (a food, a meal, a meal with its photo). Shows the photo
  /// when there is one (Probid 2026-10-30).
  /// [rows]: what will be logged, one line a food (name, amount, kcal) with a heading each group; [photos]: the
  /// pictures going with it (Probid 2026-11-03, A6).
  Future<bool> _didEat(String what, String line, {String? photo, List<(String, List<(String, String, int, double, double, double)>)> rows = const [], List<String> photos = const []}) async {
    final pics = photos.isNotEmpty ? photos : [?photo];
    final ok = await showAppModal<bool>(
      context,
      title: 'Did you eat this?',
      body: '$what · $line',
      icon: AppIcons.check,
      content: rows.isEmpty && pics.isEmpty
          ? null
          : (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
              // each group in its own colour, bold heading and its kcal; the meal total last (Probid 2026-11-03)
              for (final (head, foods) in rows)
                if (foods.isNotEmpty)
                  Builder(builder: (_) {
                    final (bg, ink, dot) = head.startsWith('Will')
                        ? (AppColors.accentSoft, AppColors.accentText, AppColors.accent)
                        : head.startsWith('Already')
                        ? (AppColors.okBg, AppColors.okText, AppColors.okSolid)
                        : (AppColors.amberBg, AppColors.amberText, AppColors.amberSolid);
                    return Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(spacing: 6, children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                          Expanded(child: Text(head, style: AppText.s(13, W.w8, color: ink))),
                          Text('${inNum(foods.fold(0, (a, f) => a + f.$3))} kcal', style: AppText.s(13, W.w8, color: ink)),
                        ]),
                        const SizedBox(height: 4),
                        for (final (n, amt, k, pr, cb, ft) in foods)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(border: Border(top: BorderSide(color: dot.withValues(alpha: .25)))),
                            // name and amount, kcal on the right; protein · carbs · fat under it (Probid 2026-11-03)
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 1, children: [
                              Row(spacing: 8, children: [
                                Expanded(
                                  child: Text.rich(TextSpan(children: [
                                    TextSpan(text: n, style: AppText.s(13, W.w7)),
                                    TextSpan(text: '  $amt', style: AppText.s(12, W.w5, color: AppColors.muted)),
                                  ]), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                                Text('${inNum(k)} kcal', style: AppText.s(12.5, W.w7, color: AppColors.text2)),
                              ]),
                              Text(macroLine(pr, cb, ft), style: AppText.s(11.5, W.w5, color: AppColors.muted)),
                            ]),
                          ),
                      ]),
                    );
                  }),
              if (rows.any((r) => r.$2.isNotEmpty))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(border: Border.all(color: AppColors.line2), borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 3, children: [
                    Row(children: [
                      Expanded(child: Text('Meal total', style: AppText.s(14, W.w8))),
                      Text('${inNum(rows.fold(0, (a, r) => a + r.$2.fold(0, (b, f) => b + f.$3)))} kcal', style: AppText.s(15, W.w8)),
                    ]),
                    Text(
                      macroLine(rows.fold(0.0, (a, r) => a + r.$2.fold(0.0, (b, f) => b + f.$4)), rows.fold(0.0, (a, r) => a + r.$2.fold(0.0, (b, f) => b + f.$5)),
                          rows.fold(0.0, (a, r) => a + r.$2.fold(0.0, (b, f) => b + f.$6))),
                      style: AppText.s(12.5, W.w7, color: AppColors.text2),
                    ),
                  ]),
                ),
              if (pics.isNotEmpty) ...[
                Text('${pics.length} ${pics.length == 1 ? 'PHOTO' : 'PHOTOS'}', style: AppText.s(10.5, W.w8, color: AppColors.muted, ls: .5)),
                Wrap(spacing: 8, runSpacing: 8, children: [for (final p in pics) FdPhoto(p, name: what, size: pics.length == 1 ? 120 : 64, group: pics)]),
              ],
            ]),
      // Phone sheet: the two buttons side by side, not stacked (Probid 2026-10-30).
      actions: (ctx) => ctx.isPhone
          ? [
              Row(spacing: 8, children: [
                Expanded(child: CaButton('Cancel', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop(false))),
                Expanded(child: CaButton('Yes, log it', onPressed: () => Navigator.of(ctx).pop(true))),
              ]),
            ]
          : [
              CaButton('Cancel', kind: CaBtnKind.out, expand: false, onPressed: () => Navigator.of(ctx).pop(false)),
              CaButton('Yes, log it', expand: false, onPressed: () => Navigator.of(ctx).pop(true)),
            ],
    );
    return ok == true && mounted;
  }

  Future<void> _eat(FMeal m, {List<String>? photos}) async {
    final photo = photos == null || photos.isEmpty ? null : photos.first;
    // what this tap adds: the foods not decided yet (a fully skipped meal: all of them, "I ate it")
    final allSkipped = m.items.every((i) => i.state == 'skipped');
    final adds = m.items.where((i) => allSkipped || i.state.isEmpty).toList();
    final d0 = c.data!;
    final extras = d0.log.where((e) => e.mealName == m.name && !e.otherTime && !(e.fromPlan && e.meal != null)).toList();
    final kcal = adds.fold(0, (a, i) => a + i.kcal);
    final prot = adds.fold(0.0, (a, i) => a + i.protein);
    final rows = [
      ('Will be logged', [for (final i in adds) (i.name, i.amount, i.kcal, i.protein, i.carbs, i.fat)]),
      ('Already logged', [for (final i in m.items) if (i.state == 'eaten' && !adds.contains(i)) (i.name, i.amount, i.kcal, i.protein, i.carbs, i.fat)]),
      ('Added outside the plan · already counted', [for (final e in extras) (e.name, e.amount, e.kcal, e.protein, e.carbs, e.fat)]),
    ];
    if (!await _didEat(m.name, '${inNum(kcal)} kcal will count ${d0.isToday ? 'today' : 'for ${fdDay(d0.date)}'}.', rows: rows, photos: photos ?? const []) || !mounted) return;
    final d = c.data!;
    final t = d.target;
    final nt = d.eaten[0] + kcal, np = d.eaten[1] + prot;
    final all = d.meals.every((x) => x == m || !x.open);
    try {
      setState(() => _photos.remove(m.id));
      final f = c.meal(m, 'eat', {if (photos != null && photos.isNotEmpty) 'photos': photos});
      if (!d.isToday) {
        showToast(context, '${m.name} logged for ${fdDay(d.date)}', sub: '${inNum(kcal)} kcal · ${prot.round()} g protein', kind: ToastKind.ok, action: 'Undo', onAction: () => _undoEat(m.id));
      } else if (all) {
        showToast(context, 'All meals logged for today',
            sub: '${inNum(nt)} kcal${t[0] > 0 && nt > t[0] ? ' · ${inNum(nt - t[0])} kcal over' : ''} · ${np.round()} g protein', kind: ToastKind.star, action: 'Undo', onAction: () => _undoEat(m.id));
      } else {
        final left = t[0] - nt;
        showToast(context, '${m.name} logged',
            sub: '${inNum(kcal)} kcal · ${left >= 0 ? '${inNum(left)} kcal left' : '${inNum(-left)} kcal over'}${photo == null ? '' : photos!.length == 1 ? ' · photo added' : ' · ${photos.length} photos added'}',
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
    // A tap on Logged asks first (Probid 2026-10-30): un-logging by mistake loses the meal's log.
    final ok = await confirmAction(context,
        title: 'Un-log ${m.name}?', body: '${inNum(m.kcal)} kcal comes off ${d.isToday ? 'today' : fdWd[d.date.weekday - 1]}. You can mark it as eaten again.', confirm: 'Un-log', danger: true);
    if (!ok || !mounted) return;
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
    onSwap: () {
      final it = m.items.firstWhere((i) => i.swaps > 0);
      it.state == 'eaten' ? _changeLogged(m, () => showSwapSheet(context, c, m, it)) : showSwapSheet(context, c, m, it);
    },
    onEdit: () => showPortionsSheet(context, c, m),
    onPhoto: () => _changePhoto(m),
    onRemovePhoto: () => _removePhoto(m),
    onSkip: () async {
      // asks first, with what it leaves out (Probid 2026-11-03, A4)
      final left = m.items.where((i) => i.state != 'skipped').toList();
      final ok = await confirmAction(context,
          title: 'Skip ${m.name}?',
          body: '${left.length} ${left.length == 1 ? 'food' : 'foods'} · ${inNum(left.fold(0, (a, i) => a + i.kcal))} kcal will not count today. You can still log it later with I ate it.',
          confirm: 'Skip meal',
          danger: true,
          icon: AppIcons.close);
      if (!ok || !mounted) return;
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

  /// Logged meal: add a photo, or one more up to 4 (☰ menu).
  Future<void> _changePhoto(FMeal m) async {
    final had = m.photos.length;
    if (had >= fdMaxPhotos) return;
    final photo = await pickMealPhoto(context, m.name);
    if (photo == null || !mounted) return;
    try {
      final f = c.meal(m, had == 0 ? 'photo' : 'photo_add', {'photo': photo});
      showToast(context, had == 0 ? 'Photo added' : 'Photo ${had + 1} of $fdMaxPhotos added', sub: m.name, kind: ToastKind.ok);
      await f;
    } on ApiError catch (e) {
      if (mounted) fdError(context, e);
    }
  }

  Future<void> _removePhoto(FMeal m) async {
    final n = m.photos.length;
    final ok = n < 2 ||
        await confirmAction(context, title: 'Remove all $n photos?', body: '${m.name} stays logged.', confirm: 'Remove', danger: true, icon: AppIcons.trash);
    if (!ok || !mounted) return;
    final old = m.photo;
    try {
      final f = c.meal(m, 'photo', {'photo': null});
      showToast(context, n > 1 ? 'Photos removed' : 'Photo removed', sub: m.name, kind: ToastKind.del,
          action: n == 1 && old != null && old.startsWith('data:') ? 'Undo' : null, onAction: () {
        final again = c.data?.meals.where((x) => x.id == m.id).firstOrNull;
        if (again != null && old != null) c.meal(again, 'photo', {'photo': old}).catchError((_) {});
      });
      await f;
    } on ApiError catch (e) {
      if (mounted) fdError(context, e);
    }
  }

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
            // a food logged or deleted grows in / folds away (Phase 5)
            : AnimatedRows(children: [
                for (final (i, r) in rows.indexed) KeyedSubtree(key: ValueKey(r.meal != null ? 'meal:${r.meal!.id}' : 'entry:${r.entry!.id}'), child: _logRow(d, r, first: i == 0)),
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
      onTap: () => r.entry != null && r.meal == null
          ? _entryMenu(d, r.entry!)
          : showEntrySheet(context, c, r, onEdit: () => showPortionsSheet(context, c, r.meal!), onUneat: () => _uneat(r.meal!)),
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: AppColors.line))),
        child: Row(spacing: 10, children: [
          SizedBox(width: 58, child: Text(fdClock(r.time), style: AppText.s(12, W.w7, color: AppColors.muted))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text(r.title, style: AppText.s(13.5, W.w7, color: h ? AppColors.accentText : AppColors.text)),
              CutText(r.sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w4, color: AppColors.muted)),
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
      final r = await c.copyYesterday();
      if (!mounted) return;
      final n = (r?['copied'] as num?)?.toInt() ?? -1;
      if (n == 0) {
        showToast(context, 'Nothing to copy', sub: 'You did not log anything new yesterday', kind: ToastKind.info);
      } else if (r == null) {
        showToast(context, 'Copying yesterday', sub: 'It will show here once you are back online', kind: ToastKind.info);
      } else {
        showToast(context, 'Copied $n ${n == 1 ? 'food' : 'foods'} from yesterday', sub: 'Added to today’s food log', kind: ToastKind.ok, action: 'Undo', onAction: () {
          c.undoCopy(r).catchError((_) {});
        });
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

/// "14 g protein · 54 g carbs · 6 g fat"
String macroLine(num p, num c, num f) => '${p.round()} g protein · ${c.round()} g carbs · ${f.round()} g fat';
