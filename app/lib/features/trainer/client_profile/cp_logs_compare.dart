import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import 'cp_common.dart';
import 'cp_logs_parts.dart';
import 'cp_model.dart';
import '../../../core/widgets/tooltip.dart';

/// Logs → Compare plans (board `cmp`): Back to logs, plan A and plan B pickers with Swap, aspect chips
/// (All · Workouts · Meals · Check-ins · Habits · Supplements · Body), then one card per aspect: each number for
/// A and B, bars for the shares, and the change (green when B is better). Data: `clients/<id>/logs/compare/`.
class CpLogsCompare extends StatefulWidget {
  const CpLogsCompare(this.c, {super.key, required this.plans, required this.onBack});
  final CpController c;
  final List<CpPlan> plans;
  final VoidCallback onBack;
  @override
  State<CpLogsCompare> createState() => _CpLogsCompareState();
}

const _aspects = [
  ('all', 'All'),
  ('workouts', 'Workouts'),
  ('meals', 'Meals'),
  ('checkins', 'Check-ins'),
  ('habits', 'Habits'),
  ('supps', 'Supplements'),
  ('body', 'Body'),
];

/// One compared number. [better]: true = higher is better, false = lower is better, null = neither.
class _Row {
  _Row(this.label, this.a, this.b, {this.na, this.nb, this.better, this.change, this.bars = false, this.max = 100});
  final String label, a, b;
  final double? na, nb;
  final bool? better;
  final String? change;
  final bool bars;
  final double max;

  /// true when B is better, false when worse, null when it can not say.
  bool? get bBetter {
    if (better == null || na == null || nb == null || (na! - nb!).abs() < 1e-9) return null;
    return better! ? nb! > na! : nb! < na!;
  }
}

/// One side of the comparison: a workout plan, part of one, or any period ("Last 30 days", custom dates).
class _Side {
  _Side.plan(CpPlan p)
      : key = 'plan:${p.id}',
        name = p.name,
        plan = p,
        from = null,
        to = null;
  _Side.period(this.key, this.name, DateTime f, DateTime t)
      : plan = null,
        from = DateUtils.dateOnly(f),
        to = DateUtils.dateOnly(t);
  final String key, name;
  final CpPlan? plan;
  final DateTime? from, to;

  static String _d(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  Map<String, dynamic> query(String letter) =>
      plan != null ? {letter: 'plan:${plan!.id}'} : {'${letter}_from': _d(from!), '${letter}_to': _d(to!)};

  /// "3 Sep – now" before the numbers arrive.
  String get when {
    if (plan != null) return [if (plan!.start != null) cpDm(plan!.start), plan!.end == null ? 'now' : cpDm(plan!.end)].join(' – ');
    return cpRangeLabel(DateTimeRange(start: from!, end: to!));
  }
}

class _Table {
  _Table(this.head, this.rows);
  final String head;
  final List<_Row> rows;
}

class _CpLogsCompareState extends State<CpLogsCompare> {
  CpController get c => widget.c;
  // Two plans or more: the one before against the current one. One plan (or none): the 30 days before
  // against the last 30 days.
  late _Side a = widget.plans.length > 1 ? _Side.plan(widget.plans[1]) : _periods()[1];
  late _Side b = widget.plans.length > 1 ? _Side.plan(widget.plans.first) : _periods()[0];
  String aspect = 'all';
  Map? data;
  ApiError? error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      data = null;
      error = null;
    });
    try {
      final d = await Services.api.get<Map>('clients/${c.id}/logs/compare/', query: {...a.query('a'), ...b.query('b')});
      if (seq == _seq && mounted) setState(() => data = d);
    } on ApiError catch (e) {
      if (seq == _seq && mounted) setState(() => error = e);
    }
  }

  /// Last 30 days, the 30 days before, and each plan's first and second half (plans of two weeks or more).
  List<_Side> _periods() {
    final t = DateUtils.dateOnly(DateTime.now());
    final out = [
      _Side.period('30d', 'Last 30 days', t.subtract(const Duration(days: 29)), t),
      _Side.period('prev30', 'Previous 30 days', t.subtract(const Duration(days: 59)), t.subtract(const Duration(days: 30))),
    ];
    for (final p in widget.plans) {
      if (p.start == null) continue;
      final start = DateUtils.dateOnly(p.start!);
      final end = p.end == null || p.end!.isAfter(t) ? t : DateUtils.dateOnly(p.end!);
      final days = end.difference(start).inDays + 1;
      if (days < 14) continue;
      final mid = start.add(Duration(days: days ~/ 2 - 1));
      final own = p == widget.plans.first ? 'This plan' : p.name;
      out.add(_Side.period('h1:${p.id}', '$own: first half', start, mid));
      out.add(_Side.period('h2:${p.id}', '$own: second half', mid.add(const Duration(days: 1)), end));
    }
    return out;
  }

  void _set(bool isA, _Side v) {
    if (isA) {
      if (v.key == b.key) b = a;
      a = v;
    } else {
      if (v.key == a.key) a = b;
      b = v;
    }
    _load();
  }

  Future<void> _custom(bool isA) async {
    final cur = isA ? a : b;
    final r = await showCpDateRange(context, initial: cur.from == null ? null : DateTimeRange(start: cur.from!, end: cur.to!));
    if (r == null || !mounted) return;
    final label = cpRangeLabel(r);
    _set(isA, _Side.period('custom:$label', label, r.start, r.end));
  }

  void _pick(BuildContext anchor, bool isA) {
    final cur = isA ? a : b;
    final entries = [
      if (widget.plans.isNotEmpty) const MenuEntry.header('Plans'),
      for (final p in widget.plans) MenuEntry(p.name, selected: cur.key == 'plan:${p.id}', onTap: () => _set(isA, _Side.plan(p))),
      const MenuEntry.header('Periods'),
      for (final x in _periods()) MenuEntry(x.name, selected: cur.key == x.key, onTap: () => _set(isA, x)),
      MenuEntry('Custom dates…', selected: cur.key.startsWith('custom:'), onTap: () => _custom(isA)),
    ];
    anchor.isPhone ? showActionSheet(anchor, entries) : cpShowMenu(anchor, entries, minWidth: 300);
  }

  void _swap() {
    final t = a;
    a = b;
    b = t;
    _load();
  }

  // ─────────────────────────────── Numbers

  static double? _d(Object? v) => (v as num?)?.toDouble();
  static String _signed(double v, {String unit = '', int dp = 0}) {
    final s = dp == 0 ? cpNum(v.abs()) : v.abs().toStringAsFixed(dp);
    return '${v < 0 ? '−' : '+'}$s$unit';
  }

  static _Row _pct(String label, Object? a, Object? b, {bool better = true, bool bars = true}) {
    final na = _d(a), nb = _d(b);
    return _Row(label, na == null ? '—' : '${na.round()}%', nb == null ? '—' : '${nb.round()}%',
        na: na, nb: nb, better: better, bars: bars, change: na == null || nb == null ? null : _signed(nb - na, unit: '%'));
  }

  static _Row _val(String label, Object? a, Object? b, String Function(double) fmt, {bool? better, String Function(double)? diff}) {
    final na = _d(a), nb = _d(b);
    return _Row(label, na == null ? '—' : fmt(na), nb == null ? '—' : fmt(nb),
        na: na, nb: nb, better: better, change: na == null || nb == null ? null : (diff ?? (v) => _signed(v))(nb - na));
  }

  Map _side(String k, String key) => ((data?[k] as Map?)?[key] as Map?) ?? const {};

  List<_Table> _section(String key) {
    final x = _side('a', key), y = _side('b', key);
    String kg(double v) => '${cpNum(v)} kg';
    switch (key) {
      case 'workouts':
        final bestA = <String, Map>{for (final s in (x['best'] as List? ?? const [])) '${(s as Map)['key']}': s};
        final bestB = <String, Map>{for (final s in (y['best'] as List? ?? const [])) '${(s as Map)['key']}': s};
        String set(Map? s) => s == null ? '—' : '${cpOne(s['kg'] as num)} kg${s['reps'] == null ? '' : ' × ${s['reps']}'}';
        final both = [for (final k in bestB.keys) if (bestA.containsKey(k)) k].take(6);
        return [
          _Table('Number', [
            _val('Workouts planned a week', x['planned_week'], y['planned_week'], (v) => cpNum(v)),
            _val('Workouts done a week', x['done_week'], y['done_week'], (v) => cpOne(v), better: true, diff: (v) => _signed(v, dp: 1)),
            _pct('Completed', x['completed'], y['completed']),
            _pct('Sets done', x['sets'], y['sets']),
            _val('Avg volume per workout', x['volume'], y['volume'], kg, better: true,
                diff: (v) => _d(x['volume']) == null || _d(x['volume']) == 0 ? _signed(v, unit: ' kg') : _signed(100 * v / _d(x['volume'])!, unit: '%')),
            _val('Avg session', x['minutes'], y['minutes'], (v) => '${cpNum(v)} min', diff: (v) => _signed(v, unit: ' min')),
            _val('Missed workouts', x['missed'], y['missed'], (v) => cpNum(v), better: false),
            _Row('Most missed day', '${x['missed_day'] ?? '—'}', '${y['missed_day'] ?? '—'}'),
          ]),
          if (both.isNotEmpty)
            _Table('Best set', [
              for (final k in both)
                _Row('${bestB[k]!['name']}', set(bestA[k]), set(bestB[k]),
                    na: _d(bestA[k]!['kg']), nb: _d(bestB[k]!['kg']), better: true, change: _signed(_d(bestB[k]!['kg'])! - _d(bestA[k]!['kg'])!, unit: ' kg')),
            ]),
        ];
      case 'meals':
        double? off(Map m) => m['kcal'] == null || m['target'] == null ? null : (_d(m['kcal'])! - _d(m['target'])!).abs();
        final perA = {for (final m in (x['per_meal'] as List? ?? const [])) '${(m as Map)['name']}': m['pct']};
        final perB = {for (final m in (y['per_meal'] as List? ?? const [])) '${(m as Map)['name']}': m['pct']};
        final names = [...perA.keys, for (final n in perB.keys) if (!perA.containsKey(n)) n];
        String perDay(Map m) => m['per_day'] == null ? '—' : '${cpOne(m['per_day'] as num)}${m['meals'] == null ? '' : ' of ${m['meals']}'}';
        double? perPct(Map m) => m['per_day'] == null || m['meals'] == null ? null : 100 * _d(m['per_day'])! / _d(m['meals'])!;
        return [
          _Table('Number', [
            _val('Calorie target', x['target'], y['target'], (v) => '${cpNum(v)} kcal', diff: (v) => _signed(v)),
            _Row('Avg calories eaten', x['kcal'] == null ? '—' : '${cpNum(x['kcal'] as num)} kcal', y['kcal'] == null ? '—' : '${cpNum(y['kcal'] as num)} kcal',
                na: off(x), nb: off(y), better: false, change: x['kcal'] == null || y['kcal'] == null ? null : _signed(_d(y['kcal'])! - _d(x['kcal'])!)),
            _Row('Avg protein', x['protein'] == null ? '—' : cpG(x['protein'] as num), y['protein'] == null ? '—' : cpG(y['protein'] as num),
                na: _d(x['protein']), nb: _d(y['protein']), better: true, bars: true, max: [_d(x['protein']) ?? 0, _d(y['protein']) ?? 0, 1.0].reduce((p, q) => p > q ? p : q) * 1.1,
                change: x['protein'] == null || y['protein'] == null ? null : _signed(_d(y['protein'])! - _d(x['protein'])!, unit: ' g')),
            _val('Avg carbs', x['carbs'], y['carbs'], (v) => cpG(v), diff: (v) => _signed(v, unit: ' g')),
            _val('Avg fat', x['fat'], y['fat'], (v) => cpG(v), diff: (v) => _signed(v, unit: ' g')),
            _pct('Days on plan', x['on_plan'], y['on_plan']),
            _pct('Days over target', x['over'], y['over'], better: false),
            _Row('Meals logged a day', perDay(x), perDay(y), na: perPct(x), nb: perPct(y), better: true, bars: true,
                change: x['per_day'] == null || y['per_day'] == null ? null : _signed(_d(y['per_day'])! - _d(x['per_day'])!, dp: 1)),
          ]),
          if (names.isNotEmpty) _Table('Logged per meal', [for (final n in names) _pct(n, perA[n], perB[n])]),
        ];
      case 'checkins':
        String wk(Map m) => '${m['weekly_on_time'] ?? 0} of ${m['weekly_due'] ?? 0}';
        double? wp(Map m) => (m['weekly_due'] ?? 0) == 0 ? null : 100 * _d(m['weekly_on_time'])! / _d(m['weekly_due'])!;
        final pa = wp(x), pb = wp(y);
        return [
          _Table('Number', [
            _pct('Daily check-ins sent', x['daily'], y['daily']),
            _Row('Weekly check-ins on time', wk(x), wk(y), na: pa, nb: pb, better: true, bars: true,
                change: pa == null || pb == null ? null : '${pa.round()}% → ${pb.round()}%'),
            _val('Avg sleep', x['sleep'], y['sleep'], (v) => '${cpOne(v)} h', better: true, diff: (v) => _signed(v, unit: ' h', dp: 1)),
            _pct('Energy good or great', x['energy'], y['energy']),
            _pct('Mood good or great', x['mood'], y['mood']),
            _pct('High hunger days', x['hunger'], y['hunger'], better: false),
          ]),
        ];
      case 'habits':
        final ia = <String, Map>{for (final h in (x['items'] as List? ?? const [])) '${(h as Map)['key']}': h};
        final ib = <String, Map>{for (final h in (y['items'] as List? ?? const [])) '${(h as Map)['key']}': h};
        final keys = [...ia.keys, for (final k in ib.keys) if (!ia.containsKey(k)) k];
        return [
          _Table('Number', [
            for (final k in keys) _pct('${(ib[k] ?? ia[k])!['name']}', ia[k]?['pct'], ib[k]?['pct']),
            _pct('All habits done', x['all'], y['all']),
            _val('Avg steps', x['steps'], y['steps'], (v) => cpNum(v), better: true, diff: (v) => _signed(v)),
            _val('Avg water', x['water'], y['water'], (v) => '${cpOne(v)} L', better: true, diff: (v) => _signed(v, unit: ' L', dp: 1)),
          ]),
        ];
      case 'supps':
        final ia = <String, Map>{for (final h in (x['items'] as List? ?? const [])) '${(h as Map)['key']}': h};
        final ib = <String, Map>{for (final h in (y['items'] as List? ?? const [])) '${(h as Map)['key']}': h};
        final keys = [...ia.keys, for (final k in ib.keys) if (!ia.containsKey(k)) k];
        return [
          _Table('Number', [
            for (final k in keys)
              ia[k] == null || ib[k] == null
                  ? _Row('${(ib[k] ?? ia[k])!['name']}', ia[k] == null ? 'Not in plan' : '${ia[k]!['pct'] ?? '—'}%', ib[k] == null ? 'Not in plan' : '${ib[k]!['pct'] ?? '—'}%',
                      nb: _d(ib[k]?['pct']), bars: true, change: ia[k] == null ? 'New' : 'Stopped')
                  : _pct('${ib[k]!['name']}', ia[k]!['pct'], ib[k]!['pct']),
            _pct('All taken', x['all'], y['all']),
            // Stock history: times a supplement ran out at home (fewer is better).
            _val('Ran out of stock', x['ran_out'], y['ran_out'], (v) => v == 1 ? '1 time' : '${v.round()} times', better: false),
          ]),
        ];
      default: // body
        final p = c.profile;
        final lose = p['target_weight_kg'] != null && p['start_weight_kg'] != null &&
            (double.tryParse('${p['target_weight_kg']}') ?? 0) < (double.tryParse('${p['start_weight_kg']}') ?? 0);
        String s(double v, String u, {int dp = 1}) => '${v < 0 ? '−' : (v > 0 ? '+' : '')}${v.abs().toStringAsFixed(dp).replaceAll(RegExp(r'\.0+$'), '')}$u';
        final pwa = _d(x['per_week']), pwb = _d(y['per_week']);
        return [
          _Table('Number', [
            _val('Weight change', x['weight'], y['weight'], (v) => s(v, ' kg'), better: !lose, diff: (v) => s(v, ' kg')),
            _Row('Per week', pwa == null ? '—' : s(pwa, ' kg', dp: 2), pwb == null ? '—' : s(pwb, ' kg', dp: 2), na: pwa, nb: pwb, better: !lose,
                change: pwa == null || pwb == null ? null : (pwb.abs() > pwa.abs() ? 'faster' : (pwb.abs() < pwa.abs() ? 'slower' : 'same'))),
            _val('Waist', x['waist'], y['waist'], (v) => s(v, ' cm'), better: false, diff: (v) => s(v, ' cm')),
            _val('Body fat', x['body_fat'], y['body_fat'], (v) => s(v, '%'), better: false, diff: (v) => s(v, '%')),
          ]),
        ];
    }
  }

  // ─────────────────────────────── Build

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final keys = aspect == 'all' ? [for (final x in _aspects.skip(1)) x.$1] : [aspect];
    final sections = data == null ? <(String, List<_Table>)>[] : [for (final k in keys) (k, _section(k))];
    var better = 0, total = 0;
    if (data != null) {
      for (final k in [for (final x in _aspects.skip(1)) x.$1]) {
        for (final t in _section(k)) {
          for (final r in t.rows) {
            if (r.better != null && r.na != null && r.nb != null) total++;
            if (r.bBetter == true) better++;
          }
        }
      }
    }
    final head = Text.rich(TextSpan(style: AppText.s(12.5, W.w5, color: AppColors.muted), children: [
      TextSpan(text: a.plan != null && b.plan != null ? 'Averages per week of each plan' : 'Averages per week of each side'),
      if (data != null) ...[
        const TextSpan(text: ' · B is better on '),
        TextSpan(text: '$better of $total', style: AppText.s(12.5, W.w7, color: AppColors.okText)),
        const TextSpan(text: ' numbers'),
      ],
    ]));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      if (phone) ...[
        Align(alignment: Alignment.centerLeft, child: AppButton('Back to logs', icon: AppIcons.chevronLeft, onPressed: widget.onBack)),
        head,
      ] else
        Row(children: [AppButton('Back to logs', icon: AppIcons.chevronLeft, onPressed: widget.onBack), const Spacer(), head]),
      phone
          ? Column(spacing: 8, children: [
              _pickBox('A', a, true),
              AppIconButton(AppIcons.swap, tooltip: 'Swap A and B', onPressed: _swap),
              _pickBox('B', b, false),
            ])
          : Row(spacing: 10, children: [
              Expanded(child: _pickBox('A', a, true)),
              AppIconButton(AppIcons.swap, tooltip: 'Swap A and B', onPressed: _swap),
              Expanded(child: _pickBox('B', b, false)),
            ]),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (k, l) in _aspects) _Chip(l, on: aspect == k, onTap: () => setState(() => aspect = k)),
      ]),
      if (error != null)
        CpError(error!.message, onRetry: _load)
      else if (data == null)
        const AppCard(child: CpLoading())
      else
        for (final (k, tables) in sections) _card(k, tables),
    ]);
  }

  String _sub(_Side p, bool isA) => '${((data?[isA ? 'a' : 'b'] as Map?)?['sub']) ?? p.when}';

  Widget _pickBox(String letter, _Side p, bool isA) => Builder(
        builder: (b) => Hover(
          onTap: () => _pick(b, isA),
          builder: (_, h, _) => Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: AppRadius.all(AppRadius.card),
              border: Border.all(color: h ? AppColors.lineHover : AppColors.line2),
            ),
            child: Row(spacing: 10, children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: isA ? AppColors.sub : AppColors.accent, borderRadius: BorderRadius.circular(6)),
                child: Text(letter, style: AppText.s(12, W.w8, color: isA ? AppColors.text2 : AppColors.white)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  CutText(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7)),
                  CutText(_sub(p, isA), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted)),
                ]),
              ),
              const AppIcon(AppIcons.chevronDown, size: 16, color: AppColors.muted),
            ]),
          ),
        ),
      );

  static const _icons = {
    'workouts': AppIcons.dumbbell,
    'meals': AppIcons.apple,
    'checkins': AppIcons.clipboard,
    'habits': AppIcons.checkCircle,
    'supps': AppIcons.pill,
    'body': AppIcons.scale,
  };

  Widget _card(String k, List<_Table> tables) {
    final label = _aspects.firstWhere((x) => x.$1 == k).$2;
    final rows = [for (final t in tables) ...t.rows];
    final total = rows.where((r) => r.better != null && r.na != null && r.nb != null).length;
    final better = rows.where((r) => r.bBetter == true).length;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(spacing: 10, children: [
            cpIcon(_icons[k] ?? AppIcons.clipboard, bg: AppColors.infoBg, fg: AppColors.infoText, size: 28),
            Expanded(child: Text(label, style: AppText.h3)),
            if (total > 0)
              Text.rich(TextSpan(style: AppText.s(12, W.w5, color: AppColors.muted), children: [
                const TextSpan(text: 'B better on '),
                TextSpan(text: '$better of $total', style: AppText.s(12, W.w7, color: AppColors.okText)),
              ])),
          ]),
        ),
        for (final t in tables)
          CpTable(
            cols: [CpCol(t.head, 200, grow: 3), CpCol('A · ${a.name}', 130, right: true, grow: 2), CpCol('B · ${b.name}', 130, right: true, grow: 2), const CpCol('', 120, grow: 2), const CpCol('Change', 90, right: true)],
            rows: [
              for (final r in t.rows)
                [
                  cpCell(r.label),
                  cpCell(r.a),
                  CutText(r.b, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7, tabular: true)),
                  r.bars ? _bars(r) : const SizedBox(),
                  r.change == null
                      ? const SizedBox()
                      : AppBadge(r.change!, plain: true, tone: switch (r.bBetter) { true => Tone.ok, false => Tone.bad, _ => Tone.neutral }),
                ],
            ],
          ),
      ]),
    );
  }

  Widget _bars(_Row r) {
    Widget bar(double? v, Color col) => LayoutBuilder(
          builder: (_, b) => Container(
            height: 4,
            width: v == null ? 0 : (b.maxWidth * (v / r.max).clamp(0.0, 1.0)),
            decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(2)),
          ),
        );
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
      bar(r.na, AppColors.line2),
      bar(r.nb, AppColors.accent),
    ]);
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: on ? AppColors.text : (h ? AppColors.outlineHover : AppColors.card),
            borderRadius: AppRadius.all(AppRadius.chip),
            border: Border.all(color: on ? AppColors.text : AppColors.line2),
          ),
          child: Center(widthFactor: 1, child: Text(label, style: AppText.s(12.5, W.w6, color: on ? AppColors.white : AppColors.text2))),
        ),
      );
}
