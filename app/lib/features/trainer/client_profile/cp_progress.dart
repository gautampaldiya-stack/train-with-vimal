import 'package:flutter/material.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/responsive.dart';
import '../../client/progress/progress_model.dart' show PxWeight;
import '../../client/progress/progress_parts.dart' show PxWeightChart;
import 'cp_common.dart';
import 'cp_logs_parts.dart';
import 'cp_model.dart';
import 'cp_progress_photos.dart';

/// Client profile → Progress tab (board `TrainerClientProfile` Progress): 4 change cards (weight, waist, body fat,
/// the lift that went up most), the Weight chart with the range picker, Measurements with a Change row (left);
/// Progress photos start vs latest with All photos, Personal bests (right). Data: `clients/<id>/progress/`.
class CpProgressTab extends StatefulWidget {
  const CpProgressTab(this.c, {super.key});
  final CpController c;
  @override
  State<CpProgressTab> createState() => _CpProgressTabState();
}

/// Measurements shown in the table; left / right pairs merge into one column ("Arm"), as on the board.
const _cols = [
  ('waist', 'Waist', ['waist']),
  ('hips', 'Hips', ['hips']),
  ('chest', 'Chest', ['chest']),
  ('arm', 'Arm', ['bicep_r', 'bicep_l']),
  ('thigh', 'Thigh', ['thigh_r', 'thigh_l']),
  ('calf', 'Calf', ['calf_r', 'calf_l']),
  ('abdomen', 'Abdomen', ['abdomen']),
  ('neck', 'Neck', ['neck']),
  ('body_fat', 'Body fat', ['body_fat']),
];

class _CpProgressTabState extends State<CpProgressTab> {
  CpController get c => widget.c;
  Map? d;
  ApiError? error;
  late CpRange range = cpRangeOf(c);
  List<CpPlan> plans = const [];
  bool allMeasures = false;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _version = c.version;
    c.addListener(_onC);
    cpPlansOf(c).then((p) {
      if (mounted) setState(() => plans = p);
    });
    _load();
  }

  @override
  void dispose() {
    c.removeListener(_onC);
    super.dispose();
  }

  void _onC() {
    if (c.version != _version) {
      _version = c.version;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final r = await Services.api.get<Map>('clients/${c.id}/progress/');
      if (mounted) {
        setState(() {
          d = r;
          error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  // ─────────────────────────────── Data

  List<PxWeight> get weights => [
        for (final w in (d?['weights'] as List? ?? const []))
          if (cpParse((w as Map)['date']) != null && double.tryParse('${w['weight_kg']}') != null) PxWeight(cpParse(w['date'])!, double.parse('${w['weight_kg']}')),
      ];

  List<Map> get measures => [for (final m in (d?['measurements'] as List? ?? const [])) m as Map]; // oldest first

  double? _mv(Map m, List<String> keys) {
    final v = (m['values'] as Map?) ?? const {};
    for (final k in keys) {
      final x = v[k];
      if (x is num) return x.toDouble();
    }
    return null;
  }

  List<CpPhotoSet> get photoSets => [for (final s in (d?['photo_sets'] as List? ?? const [])) CpPhotoSet(s as Map)]
    ..sort((a, b) => (a.date ?? DateTime(0)).compareTo(b.date ?? DateTime(0)));

  double? get goal => (d?['goal'] as num?)?.toDouble();

  /// Weigh-ins inside the picked range.
  List<PxWeight> _inRange(List<PxWeight> all) {
    if (all.isEmpty) return all;
    final today = DateUtils.dateOnly(DateTime.now());
    DateTime? from, to;
    switch (range.value) {
      case '7d' || '30d' || '90d' || '6m':
        final n = const {'7d': 7, '30d': 30, '90d': 90, '6m': 182}[range.value]!;
        from = today.subtract(Duration(days: n - 1));
      case 'custom':
        from = range.from;
        to = range.to;
      case 'start':
        break;
      default:
        final p = plans.where((p) => 'plan:${p.id}' == range.value).firstOrNull;
        from = p?.start;
        to = p?.end;
    }
    return [for (final w in all) if ((from == null || !w.date.isBefore(from)) && (to == null || !w.date.isAfter(to))) w];
  }

  // ─────────────────────────────── Build

  @override
  Widget build(BuildContext context) {
    if (error != null && d == null) return CpError(error!.message, onRetry: _load);
    if (d == null) return const AppCard(child: CpLoading());
    final phone = context.isPhone;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 14 : 16, children: [
      _changes(phone),
      CpColumns(left: [_weight(), _measurements(phone)], right: [_photos(), _bests(phone)]),
    ]);
  }

  // ─────────────────────────────── Change cards

  Widget _changes(bool phone) {
    final ws = weights;
    final start = (d?['start'] as Map?) ?? const {};
    final startKg = (start['kg'] as num?)?.toDouble() ?? (ws.isEmpty ? null : ws.first.kg);
    final nowKg = ws.isEmpty ? null : ws.last.kg;
    final g = goal;
    final ms = measures;
    (double, double)? span(List<String> keys) {
      final vals = [for (final m in ms) ?_mv(m, keys)];
      return vals.isEmpty ? null : (vals.first, vals.last);
    }

    final waist = span(['waist']), fat = span(['body_fat']);
    final lifts = [for (final l in (d?['lifts'] as List? ?? const [])) l as Map];
    double gain(Map l) => ((l['best']?['kg'] as num?) ?? 0).toDouble() - ((l['start']?['kg'] as num?) ?? 0).toDouble();
    final top = lifts.isEmpty ? null : (lifts.toList()..sort((a, b) => gain(b).compareTo(gain(a)))).first;
    String n(double v) => cpOne(v);

    final cards = <Widget>[
      _stat(
        'Weight',
        nowKg == null ? '—' : cpKg(nowKg, keep: true),
        startKg == null ? 'No weigh-ins yet' : 'from ${cpKg(startKg, keep: true)} · ${cpDm(start['date'])}',
        nowKg == null || startKg == null ? null : cpSigned(nowKg - startKg, 'kg'),
        nowKg == null || startKg == null || (nowKg - startKg).abs() < .05 ? null : (g == null ? nowKg < startKg : (nowKg - g).abs() < (startKg - g).abs()),
      ),
      _stat('Waist', waist == null ? '—' : '${n(waist.$2)} cm', waist == null ? 'Not measured yet' : 'from ${n(waist.$1)} cm',
          waist == null ? null : _sgn(waist.$2 - waist.$1, ' cm'), waist == null || waist.$1 == waist.$2 ? null : waist.$2 < waist.$1),
      _stat('Body fat', fat == null ? '—' : '${n(fat.$2)}%', fat == null ? 'Not measured yet' : 'from ${n(fat.$1)}%',
          fat == null ? null : _sgn(fat.$2 - fat.$1, '%'), fat == null || fat.$1 == fat.$2 ? null : fat.$2 < fat.$1),
      _stat(
        top == null ? 'Top lift' : '${top['name']}',
        top == null ? '—' : cpKg(top['best']['kg']),
        top == null ? 'No lifts logged yet' : 'best set ${cpKg(top['best']['kg'])}${top['best']['reps'] == null ? '' : ' × ${top['best']['reps']}'}',
        top == null ? null : _sgn(gain(top), ' kg'),
        top == null || gain(top) == 0 ? null : gain(top) > 0,
      ),
    ];
    if (phone) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [for (final x in cards) SizedBox(width: 200, child: x)]),
      );
    }
    return Wrap(spacing: 12, runSpacing: 12, children: cards);
  }

  static String _sgn(double v, String unit) {
    if (v.abs() < .05) return '±0$unit';
    return '${v < 0 ? '−' : '+'}${cpOne(v.abs())}$unit';
  }

  Widget _stat(String label, String value, String sub, String? delta, bool? good) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 6, children: [
          Row(mainAxisSize: MainAxisSize.min, spacing: 12, children: [
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w5, color: AppColors.text2))),
            if (delta != null) AppBadge(delta, plain: true, tone: good == null ? Tone.neutral : (good ? Tone.ok : Tone.warn)),
          ]),
          Text.rich(TextSpan(children: [
            TextSpan(text: value, style: AppText.s(20, W.w8, ls: -0.4, tabular: true)),
            TextSpan(text: '  $sub', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
          ])),
        ]),
      );

  // ─────────────────────────────── Weight chart

  Widget _weight() {
    final pts = _inRange(weights);
    final g = goal;
    final head = range.label.startsWith('Last ') ? range.label.substring(5) : range.label;
    return CpCard(
      title: 'Weight',
      sub: [head, if (g != null) 'goal ${cpKg(g)}'].join(' · '),
      action: CpRangePicker(
        value: range,
        plans: [for (final p in plans) (p.id, p.name)],
        onChanged: (r) => setState(() {
          range = r;
          cpSetRange(c, r);
        }),
      ),
      child: pts.length < 2
          ? EmptyState(pts.isEmpty ? 'No weigh-ins in this range' : 'One weigh-in in this range', sub: 'The line shows after two weigh-ins.')
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
              PxWeightChart(points: pts, goal: g, selected: null, onPick: (_) {}, height: 200, dots: false),
              Row(children: [
                Text('${cpDm(pts.first.date)} · ${cpKg(pts.first.kg, keep: true)}', style: AppText.cap),
                const Spacer(),
                Text(cpDm(pts[pts.length ~/ 2].date), style: AppText.cap),
                const Spacer(),
                Text('${cpDm(pts.last.date)} · ${cpKg(pts.last.kg, keep: true)}', style: AppText.cap),
              ]),
            ]),
    );
  }

  // ─────────────────────────────── Measurements

  Widget _measurements(bool phone) {
    final ms = measures;
    final ws = weights;
    final cols = [for (final col in _cols) if (ms.any((m) => _mv(m, col.$3) != null)) col];
    final every = (d?['measure_every_weeks'] as num?)?.toInt() ?? 2;
    final sub = 'Taken every ${every == 1 ? 'week' : '$every weeks'}';
    if (ms.isEmpty) {
      return CpCard(title: 'Measurements', sub: sub, child: EmptyState('No measurements yet', sub: '${c.first}’s measurements show here once they log them.'));
    }
    double? kgOn(DateTime? day) {
      if (day == null) return null;
      PxWeight? best;
      for (final w in ws) {
        if (!w.date.isAfter(day)) best = w;
      }
      return best?.kg;
    }

    String unit(String key) => key == 'body_fat' ? '%' : ' cm';
    String fmt(double? v, String key) => v == null ? '—' : '${cpOne(v)}${unit(key)}';
    final newest = ms.reversed.toList();
    final shown = allMeasures ? newest : newest.take(6).toList();
    final first = ms.first;
    final last = ms.last;
    final w0 = kgOn(cpParse(first['date'])), w1 = kgOn(cpParse(last['date']));
    Widget chg(double? a, double? b, String u) {
      if (a == null || b == null) return cpCell('—', bold: true);
      final v = b - a;
      return Text(_sgn(v, u), maxLines: 1, softWrap: false, style: AppText.s(13.5, W.w8, color: v < 0 ? AppColors.okText : AppColors.text, tabular: true));
    }

    String dateOf(Map m) => identical(m, first) ? '${cpDm(m['date'])} · start' : cpDm(m['date']);
    final more = newest.length > 6
        ? CpLink(allMeasures ? 'Show fewer' : 'Show all ${newest.length}', onTap: () => setState(() => allMeasures = !allMeasures))
        : null;
    final changeCells = [
      chg(w0, w1, ' kg'),
      for (final col in cols) chg(_mv(first, col.$3) ?? _firstOf(ms, col.$3), _mv(last, col.$3) ?? _lastOf(ms, col.$3), unit(col.$1)),
    ];
    if (phone) {
      return CpTableCard(
        title: 'Measurements',
        sub: sub,
        action: more,
        child: CpPhoneRows(
          titles: [for (final m in shown) dateOf(m), 'Change'],
          labels: ['Weight', for (final col in cols) col.$2],
          values: [
            for (final m in shown) [cpPv(kgOn(cpParse(m['date'])) == null ? '—' : cpKg(kgOn(cpParse(m['date'])), keep: true)), for (final col in cols) cpPv(fmt(_mv(m, col.$3), col.$1))],
            changeCells,
          ],
        ),
      );
    }
    return CpTableCard(
      title: 'Measurements',
      sub: sub,
      action: more,
      child: CpTable(
        // Wide enough that "79.5 cm" / "71.2 kg" stay on one line; a narrow card scrolls the table sideways.
        cols: [const CpCol('Date', 110, grow: 1.4), const CpCol('Weight', 92, right: true), for (final col in cols) CpCol(col.$2, 90, right: true)],
        rows: [
          for (final m in shown)
            [
              cpCell(dateOf(m)),
              _one(kgOn(cpParse(m['date'])) == null ? '—' : cpKg(kgOn(cpParse(m['date'])), keep: true)),
              for (final col in cols) _one(fmt(_mv(m, col.$3), col.$1)),
            ],
        ],
        footer: [cpCell('Change', bold: true), ...changeCells],
      ),
    );
  }

  /// A value cell that never wraps ("79.5 cm" on one line).
  static Widget _one(String s) => Text(s, maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: AppText.s(13.5, W.w5, tabular: true));

  double? _firstOf(List<Map> ms, List<String> keys) {
    for (final m in ms) {
      final v = _mv(m, keys);
      if (v != null) return v;
    }
    return null;
  }

  double? _lastOf(List<Map> ms, List<String> keys) {
    for (final m in ms.reversed) {
      final v = _mv(m, keys);
      if (v != null) return v;
    }
    return null;
  }

  // ─────────────────────────────── Photos

  Widget _photos() {
    final sets = photoSets;
    final hidden = d?['photos_hidden'] == true;
    if (sets.isEmpty) {
      return CpCard(
        title: 'Progress photos',
        sub: 'Start vs latest',
        child: EmptyState(hidden ? 'Photos are not part of your access' : 'No progress photos yet',
            sub: hidden ? 'Ask Vimal to turn on progress photos for you.' : 'Photos ${c.first} sends with check-ins show here.', icon: AppIcons.camera),
      );
    }
    final a = sets.first, b = sets.last;
    final tiles = <(CpPhotoSet, String, int)>[];
    for (final (k, _) in cpPoses.take(2)) {
      if (a.photos[k] != null) tiles.add((a, k, 0));
      if (b != a && b.photos[k] != null) tiles.add((b, k, sets.length - 1));
    }
    return CpCard(
      title: 'Progress photos',
      sub: sets.length == 1 ? 'Start' : 'Start vs latest',
      action: CpLink('All photos', onTap: () => showCpAllPhotos(context, name: c.name, sets: sets)),
      child: LayoutBuilder(builder: (context, box) {
        final w = (box.maxWidth - 10) / 2;
        return Wrap(spacing: 10, runSpacing: 12, children: [
          for (final (s, pose, i) in tiles)
            SizedBox(
              width: w,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                CpPhoto(s.photos[pose]!, height: w * .72, onTap: () => showCpPhotoViewer(context, sets, index: i, pose: pose)),
                Text.rich(TextSpan(style: AppText.cap, children: [
                  TextSpan(text: s.dm, style: AppText.s(12, W.w7)),
                  TextSpan(text: [if (pose == 'front' && s.kg != null) ' · ${cpKg(s.kg, keep: true)}', ' · $pose'].join()),
                ])),
              ]),
            ),
        ]);
      }),
    );
  }

  // ─────────────────────────────── Personal bests

  Widget _bests(bool phone) {
    final lifts = [for (final l in (d?['lifts'] as List? ?? const [])) l as Map];
    String set(Map? s) => s == null ? '—' : '${cpKg(s['kg'], unit: 'kg')}${s['reps'] == null ? '' : ' × ${s['reps']}'}';
    Widget change(Map l) {
      final v = ((l['best']?['kg'] as num?) ?? 0) - ((l['start']?['kg'] as num?) ?? 0);
      return Text(_sgn(v.toDouble(), ' kg'), style: AppText.s(13.5, W.w8, color: v > 0 ? AppColors.okText : AppColors.text, tabular: true));
    }

    if (lifts.isEmpty) {
      return CpCard(title: 'Personal bests', sub: 'Heaviest set logged', child: EmptyState('No lifts logged yet', sub: 'Sets ${c.first} logs with a weight show here.'));
    }
    if (phone) {
      return CpTableCard(
        title: 'Personal bests',
        sub: 'Heaviest set logged',
        child: CpPhoneRows(
          titles: [for (final l in lifts) '${l['name']}'],
          labels: const ['Start', 'Best', 'Change'],
          values: [for (final l in lifts) [cpPv(set(l['start'] as Map?)), cpPv(set(l['best'] as Map?)), change(l)]],
        ),
      );
    }
    return CpTableCard(
      title: 'Personal bests',
      sub: 'Heaviest set logged',
      child: CpTable(
        cols: const [CpCol('Exercise', 150, grow: 2), CpCol('Start', 90, right: true), CpCol('Best', 90, right: true), CpCol('Change', 80, right: true)],
        rows: [for (final l in lifts) [cpCell('${l['name']}', bold: true), cpCell(set(l['start'] as Map?)), cpCell(set(l['best'] as Map?)), change(l)]],
      ),
    );
  }
}
