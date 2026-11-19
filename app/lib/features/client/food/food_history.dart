import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/skeleton.dart';
import '../home/home_model.dart' show inNum, litres, mealTime;
import '../train/train_history.dart' show HistPill, HistSkeleton, histPage, histTile;
import 'food_model.dart';

/// Food history (Probid 19 Nov, like Train's Workout history): a page, not a sheet. Each past day a card: how many
/// meals were logged, the kcal against the target as a bar, and protein / carbs / fat as coloured pills. Tap a day
/// for everything eaten that day. Only looking here: food is logged today and yesterday from the Food page.

int _n(Object? v) => v is num ? v.round() : int.tryParse('$v') ?? 0;

class _Day {
  _Day(this.date, this.e);
  final DateTime date;
  final Map<String, dynamic> e;
  int get kcal => _n(e['kcal']);
  int get protein => _n(e['protein']);
  int get carbs => _n(e['carbs']);
  int get fat => _n(e['fat']);
  int get logged => _n(e['logged']);
  int get planned => _n(e['planned']);
  int get foods => _n(e['foods']);
  bool get today => e['partial'] == true;
  bool get empty => foods == 0 && logged == 0;
}

/// Macro pills shared by the list and the day page: protein blue, carbs yellow, fat pink.
Widget _macros(num p, num c, num f) => Wrap(spacing: 8, runSpacing: 6, children: [
      HistPill(AppIcons.bolt, '${p.round()} g protein', bg: AppColors.accentSoft, fg: AppColors.accentText),
      HistPill(AppIcons.apple, '${c.round()} g carbs', bg: AppColors.amberBg, fg: AppColors.amberText),
      HistPill(AppIcons.flame, '${f.round()} g fat', bg: AppColors.purpleBg, fg: AppColors.purpleText),
    ]);

/// kcal eaten against the target: a thick bar, green near the target, amber over it.
Widget _kcalBar(int kcal, int? target) {
  final t = (target ?? 0) > 0 ? target! : 0;
  final f = t == 0 ? 0.0 : kcal / t;
  final over = f > 1.1;
  final color = over ? AppColors.amberSolid : (f >= .85 ? AppColors.okSolid : AppColors.warm);
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
    Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 5, children: [
      Text(inNum(kcal), style: AppText.s(20, W.w8, ls: -0.3, tabular: true, color: AppColors.text)),
      Text(t == 0 ? 'kcal' : 'of ${inNum(t)} kcal', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
      const Spacer(),
      if (t > 0) Text('${(f * 100).round()}%', style: AppText.s(12.5, W.w8, color: over ? AppColors.amberText : (f >= .85 ? AppColors.okText : AppColors.warm), tabular: true)),
    ]),
    if (t > 0)
      ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: LinearProgressIndicator(value: f.clamp(0.0, 1.0), minHeight: 7, backgroundColor: AppColors.barTrack, color: color),
      ),
  ]);
}

// ─────────────────────────────── History list

class FoodHistoryScreen extends StatefulWidget {
  const FoodHistoryScreen({super.key});
  @override
  State<FoodHistoryScreen> createState() => _FoodHistoryScreenState();
}

class _FoodHistoryScreenState extends State<FoodHistoryScreen> {
  final _days = <_Day>[];
  int _count = -1;
  int? _target;
  int? _avgKcal, _avgProtein;
  bool _loading = false;
  String? _error;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool get _more => _count < 0 || _days.length < _count;

  Future<void> _load({bool again = false}) async {
    if (_loading || (!again && !_more)) return;
    setState(() => _loading = true);
    try {
      final j = await Services.api.get<Map<String, dynamic>>('me/history/', query: {
        'range': '3months',
        'type': 'meal',
        'offset': again ? 0 : _days.length,
        'limit': again || _days.isEmpty ? 14 : 20,
      });
      if (again) _days.clear();
      for (final d in (j['days'] as List? ?? const [])) {
        final m = (d as Map).cast<String, dynamic>();
        final e = (m['entries'] as List? ?? const []).cast<Map>().firstOrNull;
        if (e != null) _days.add(_Day(DateTime.parse('${m['date']}'), e.cast<String, dynamic>()));
      }
      _count = (j['count'] as num?)?.toInt() ?? _days.length;
      final s = (j['summary'] as Map?) ?? const {};
      _target = (s['kcal_target'] as num?)?.toInt();
      _avgKcal = (s['avg_kcal'] as num?)?.toInt();
      _avgProtein = (s['avg_protein'] as num?)?.toInt();
      _error = null;
    } on ApiError catch (e) {
      _error = e.offline ? 'You are offline. Connect to see your food history.' : 'Could not load your food history. Try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final months = <(DateTime, List<_Day>)>[];
    for (final d in _days) {
      final m = DateTime(d.date.year, d.date.month);
      if (months.isEmpty || months.last.$1 != m) months.add((m, []));
      months.last.$2.add(d);
    }
    final children = <Widget>[
      if (_days.isEmpty && _error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(spacing: 10, children: [
            Text(_error!, textAlign: TextAlign.center, style: AppText.s(13.5, W.w5, color: AppColors.muted)),
            CaButton('Try again', kind: CaBtnKind.out, small: true, expand: false, onPressed: () => _load(again: true)),
          ]),
        )
      else if (_days.isEmpty && _count < 0)
        const HistSkeleton(lines: 1)
      else if (_days.isEmpty && !_loading)
        const Padding(
          padding: EdgeInsets.only(top: 24),
          child: CaEmpty(icon: AppIcons.food, title: 'No food logged yet', sub: 'Days you log food show here, newest first.'),
        ),
      if (_avgKcal != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: _averages()),
      for (final (i, (m, days)) in months.indexed) ...[
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 2 : 18, bottom: 10),
          child: Text(DateFormat(m.year == DateTime.now().year ? 'MMMM' : 'MMMM y').format(m), style: AppText.s(19, W.w7, ls: -0.2)),
        ),
        for (final d in days) Padding(padding: const EdgeInsets.only(bottom: 12), child: _card(d)),
      ],
      if (_loading && _days.isNotEmpty) const HistSkeleton(cards: 1, lines: 1, header: false),
    ];
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: () => _load(again: true),
      child: histPage(
        context,
        title: 'Food history',
        sub: 'Last 3 months · what you ate each day',
        backTip: 'Food',
        onBack: () => context.go('/food'),
        scroll: _scroll,
        children: children,
      ),
    );
  }

  /// The 3-month averages on top, plain: two numbers side by side in one white card (Probid 19 Nov: simple).
  Widget _averages() {
    Widget cell(String v, String unit, String l) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: v, style: AppText.s(20, W.w8, ls: -0.3, tabular: true)),
              TextSpan(text: ' $unit', style: AppText.s(13, W.w6, color: AppColors.muted)),
            ])),
            Text(l, style: AppText.s(12, W.w5, color: AppColors.muted)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: IntrinsicHeight(
        child: Row(spacing: 16, children: [
          cell(inNum(_avgKcal!), 'kcal', 'Average a day'),
          if (_avgProtein != null) ...[
            const VerticalDivider(width: 1, thickness: 1, color: AppColors.line),
            cell('$_avgProtein', 'g', 'Protein a day'),
          ],
        ]),
      ),
    );
  }

  Widget _card(_Day d) {
    final allLogged = d.planned > 0 && d.logged >= d.planned;
    final (icon, bg, fg) = d.empty
        ? (AppIcons.missed, AppColors.sub, AppColors.muted)
        : allLogged
            ? (AppIcons.checkCircle, AppColors.okBg, AppColors.okText)
            : (AppIcons.food, AppColors.warmBg, AppColors.warm);
    final title = d.planned > 0 ? '${d.logged} of ${d.planned} meals logged' : '${d.foods} ${d.foods == 1 ? 'food' : 'foods'} logged';
    return Semantics(
      button: true,
      label: 'Open ${DateFormat('d MMMM').format(d.date)}',
      child: Hover(
        onTap: () => context.go('/food/history/${ymd(d.date)}'),
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: h ? AppColors.outlineHover : AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: h ? AppColors.line2 : AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            Row(spacing: 12, children: [
              histTile(icon, bg: bg, fg: fg),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Row(spacing: 8, children: [
                    Flexible(
                      child: Text(DateFormat('EEEE d MMMM').format(d.date), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(16.5, W.w7)),
                    ),
                    if (d.today)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(6)),
                        child: Text('Today', style: AppText.s(11, W.w7, color: AppColors.accentText)),
                      ),
                  ]),
                  Text(d.empty ? 'Nothing logged' : title, style: AppText.s(12.5, W.w6, color: allLogged ? AppColors.okText : AppColors.muted)),
                ]),
              ),
              const AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.chevron),
            ]),
            if (!d.empty) ...[
              _kcalBar(d.kcal, _target),
              _macros(d.protein, d.carbs, d.fat),
            ],
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────── One day

class FoodDayHistoryScreen extends StatefulWidget {
  const FoodDayHistoryScreen({super.key, required this.date});
  final String date;
  @override
  State<FoodDayHistoryScreen> createState() => _FoodDayHistoryScreenState();
}

class _FoodDayHistoryScreenState extends State<FoodDayHistoryScreen> {
  FoodDay? _d;
  String? _error;

  DateTime get _date => DateTime.tryParse(widget.date) ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await Services.api.get<Map<String, dynamic>>('me/food/', query: {'date': ymd(_date)});
      if (mounted) {
        setState(() {
          _d = FoodDay(j);
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.offline ? 'You are offline. Connect to see this day.' : 'Could not load this day. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final children = <Widget>[
      if (d == null && _error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(spacing: 10, children: [
            Text(_error!, textAlign: TextAlign.center, style: AppText.s(13.5, W.w5, color: AppColors.muted)),
            CaButton('Try again', kind: CaBtnKind.out, small: true, expand: false, onPressed: _load),
          ]),
        )
      else if (d == null)
        const _DaySkeleton()
      else
        ..._body(d),
    ];
    return histPage(
      context,
      title: DateFormat('EEEE d MMMM').format(_date),
      sub: 'Food · what you ate',
      backTip: 'Food history',
      onBack: () => context.go('/food/history'),
      children: children,
    );
  }

  List<Widget> _body(FoodDay d) {
    final e = d.eaten, t = d.target;
    final other = d.log.where((x) => !x.fromPlan).toList();
    // one plain white card, four columns: number, "of target", a thin bar in the macro's colour (Probid 19 Nov: simple)
    Widget macro(String label, double v, double target, Color c, String unit) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
            Text(label, style: AppText.s(12, W.w6, color: AppColors.muted)),
            Text(unit == 'kcal' ? inNum(v) : '${v.round()} g', style: AppText.s(17, W.w8, tabular: true)),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: target > 0 ? (v / target).clamp(0.0, 1.0) : 0, minHeight: 4, backgroundColor: AppColors.barTrack, color: c),
            ),
            if (target > 0) Text('of ${unit == 'kcal' ? inNum(target) : '${target.round()} g'}', style: AppText.s(11.5, W.w5, color: AppColors.muted)),
          ]),
        );
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 14, children: [
          macro('Calories', e[0], t[0], AppColors.warm, 'kcal'),
          macro('Protein', e[1], t[1], AppColors.accent, 'g'),
          macro('Carbs', e[2], t[2], AppColors.carbs, 'g'),
          macro('Fat', e[3], t[3], AppColors.fat, 'g'),
        ]),
      ),
      const SizedBox(height: 18),
      if (d.meals.isNotEmpty) ...[
        _head('Meals', '${d.meals.where((m) => m.logged).length} of ${d.meals.length} logged'),
        for (final m in d.meals) Padding(padding: const EdgeInsets.only(bottom: 10), child: _meal(d, m)),
      ],
      if (other.isNotEmpty) ...[
        const SizedBox(height: 8),
        _head('Other food', '${other.length} ${other.length == 1 ? 'food' : 'foods'} · not from your plan'),
        _card(AppIcons.plus, AppColors.amberBg, AppColors.amberText, 'Other food', '${inNum(other.fold<int>(0, (a, x) => a + x.kcal))} kcal', [
          for (final x in other) _food(x.name, '${x.amount} · ${x.mealName}', x.kcal),
        ]),
      ],
      if (d.meals.isEmpty && other.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: CaEmpty(icon: AppIcons.food, title: 'Nothing logged this day', sub: 'Meals and foods you log show here.'),
        ),
      if (d.waterAssigned) ...[
        const SizedBox(height: 8),
        _head('Water', null),
        _water(d),
      ],
    ];
  }

  Widget _head(String t, String? sub) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 8, children: [
          Text(t, style: AppText.s(17, W.w8, ls: -0.2)),
          if (sub != null) Flexible(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.muted))),
        ]),
      );

  Widget _meal(FoodDay d, FMeal m) {
    final (icon, bg, fg, pill) = m.logged
        ? (AppIcons.checkCircle, AppColors.okBg, AppColors.okText, 'Logged')
        : m.skipped
            ? (AppIcons.close, AppColors.amberBg, AppColors.amberText, 'Skipped')
            : (AppIcons.missed, AppColors.sub, AppColors.muted, 'Not logged');
    final ate = m.eatenItems;
    return _card(icon, bg, fg, m.name, mealTime(m.timeRaw), [
      for (final i in ate) _food(i.name, i.amount, i.kcal),
      if (ate.isEmpty) Text(m.skipped ? 'Skipped this meal' : 'Nothing logged', style: AppText.s(13, W.w5, color: AppColors.muted)),
    ], pill: (pill, bg, fg), kcal: m.logged ? m.eaten[0].round() : null);
  }

  Widget _card(AppIconData icon, Color bg, Color fg, String title, String sub, List<Widget> rows, {(String, Color, Color)? pill, int? kcal}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
          Row(spacing: 12, children: [
            histTile(icon, bg: bg, fg: fg, size: 36),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(15.5, W.w7, color: AppColors.accentText)),
                Text(kcal == null ? sub : '$sub · ${inNum(kcal)} kcal', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
              ]),
            ),
            if (pill != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: pill.$2, borderRadius: BorderRadius.circular(8)),
                child: Text(pill.$1, style: AppText.s(11.5, W.w7, color: pill.$3)),
              ),
          ]),
          if (rows.isNotEmpty) Container(height: 1, color: AppColors.line),
          ...rows,
        ]),
      );

  Widget _food(String name, String amount, int kcal) => Row(spacing: 10, children: [
        Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.okSolid, shape: BoxShape.circle)),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: name, style: AppText.s(14, W.w6, color: AppColors.text)),
              TextSpan(text: '  $amount', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
            ]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text('${inNum(kcal)} kcal', style: AppText.s(13, W.w6, color: AppColors.text2, tabular: true)),
      ]);

  Widget _water(FoodDay d) {
    final ml = d.waterMl, goal = d.waterGoal, hit = ml >= goal;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: hit ? AppColors.okBg : AppColors.skyFade, borderRadius: BorderRadius.circular(14), border: Border.all(color: hit ? AppColors.okBg : AppColors.skySoft)),
      child: Row(spacing: 12, children: [
        histTile(AppIcons.water, bg: hit ? AppColors.white : AppColors.skySoft, fg: hit ? AppColors.okText : AppColors.skyMid, size: 36),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: litres(ml), style: AppText.s(17, W.w8, color: hit ? AppColors.okText : AppColors.skyMid)),
              TextSpan(text: '  of ${litres(goal)}', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
            ])),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: (ml / goal).clamp(0.0, 1.0), minHeight: 6, backgroundColor: AppColors.white, color: hit ? AppColors.okSolid : AppColors.skyMid),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _DaySkeleton extends StatelessWidget {
  const _DaySkeleton();
  @override
  Widget build(BuildContext context) => Skeleton(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          const Row(spacing: 8, children: [
            Expanded(child: SkelBox(height: 90, radius: 14)),
          ]),
          const SizedBox(height: 4),
          const SkelBox(width: 90, height: 16),
          for (var i = 0; i < 3; i++)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
                Row(spacing: 12, children: [
                  SkelBox(width: 36, height: 36, radius: 11),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 7, children: [SkelBox(width: 110, height: 13), SkelBox(width: 160, height: 11)])),
                ]),
                SkelBox(width: 200, height: 11),
                SkelBox(width: 150, height: 11),
              ]),
            ),
        ]),
      );
}
