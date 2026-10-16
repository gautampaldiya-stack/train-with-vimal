import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tooltip.dart';
import '../home/home_parts.dart' show ChCard, chSm;
import 'progress_model.dart';
import 'progress_parts.dart';
import 'progress_sheets.dart';

/// Progress (boards `ClientProgress` phone and `ClientProgressWeb`): goal weight, Weight / Body / Strength
/// tabs with a First day vs now compare, the latest photo set, three stat tiles and adherence by week.
/// History, Progress photos and Compare are their own pages (`/progress/history`, `/progress/photos`,
/// `/progress/compare`).
class ClientProgressScreen extends StatefulWidget {
  const ClientProgressScreen({super.key});
  @override
  State<ClientProgressScreen> createState() => _ClientProgressScreenState();
}

class _ClientProgressScreenState extends State<ClientProgressScreen> {
  final c = ProgressController();
  String _tab = 'Weight';
  bool _cmp = false;
  int _range = 1; // 4 wk · 12 wk · 6 mo · All
  DateTime? _sel; // the weigh-in dot picked on the chart
  String? _open = 'waist'; // the measurement row that is open
  int? _week; // adherence bar picked (null = this week)

  static const _ranges = [('4 wk', 28), ('12 wk', 84), ('6 mo', 182), ('All', 0)];

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
      if (d == null) return pxLoading(c.error, c.load, 'your progress');
      return context.isPhone ? _phone(d) : _web(d);
    },
  );

  // ─────────────────────────────── Layouts

  Widget _phone(PxData d) => RefreshIndicator(
    onRefresh: c.load,
    color: AppColors.accent,
    child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        _top(d, web: false),
        _goal(d),
        _switch(),
        if (_cmp) _firstVsNow(d),
        _tabCard(d),
        _photos(d),
        _stats(d),
        _adherence(d),
      ]),
    ),
  );

  Widget _web(PxData d) => CaWeb(
    web: true,
    child: LayoutBuilder(builder: (context, page) {
      final inner = (page.maxWidth - 64).clamp(0.0, 1080.0);
      final two = inner >= 760;
      final left = [_switch(), if (_cmp) _firstVsNow(d), _tabCard(d), _adherence(d)];
      final right = [_goal(d), _photos(d), _stats(d)];
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 72),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: inner,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
              _top(d, web: true),
              if (two)
                Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: left)),
                  SizedBox(width: 340, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: right)),
                ])
              else
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [right[0], ...left, ...right.skip(1)]),
            ]),
          ),
        ),
      );
    }),
  );

  Widget _top(PxData d, {required bool web}) => PxTop(
    'Progress',
    web ? 'Weight, measurements, strength and adherence' : 'Weight, body and strength',
    actions: [
      if (web)
        chSm('View past logs', () => context.go('/progress/history'), icon: AppIcons.clock)
      else
        CaIconBtn(AppIcons.clock, tooltip: 'View past logs', onTap: () => context.go('/progress/history')),
      chSm('Log weight', () => showLogWeight(context, c, onSaved: (day) => setState(() {
        _tab = 'Weight';
        _sel = day;
      })), icon: AppIcons.plus, kind: CaBtnKind.pri),
    ],
  );

  // ─────────────────────────────── Goal (`px-goal`)

  Widget _goal(PxData d) {
    final start = d.startKg, now = d.last, goal = d.goal;
    final lost = start != null && now != null ? start - now.kg : 0.0;
    final whole = start != null && goal != null ? start - goal : 0.0;
    final pct = whole == 0 ? 0.0 : (lost / whole).clamp(0.0, 1.0);
    final reached = goal != null && now != null && (whole >= 0 ? now.kg <= goal : now.kg >= goal);
    final eta = d.goalEta;
    final tip = 'Set with ${d.coach} when you joined.${eta != null && !reached ? ' At your pace you reach it around ${DateFormatShort.month(eta)}.' : ''}';
    Widget cell(String l, String v, String s, {bool now = false}) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(color: now ? AppColors.accentSoft : AppColors.sub, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
          Text(l, style: AppText.s(11.5, W.w7, color: AppColors.muted)),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(v, style: AppText.s(17, W.w8, ls: -.17, color: now ? AppColors.accentText : AppColors.text))),
          Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w4, color: AppColors.muted)),
        ]),
      ),
    );
    return ChCard(children: [
      Row(spacing: 4, children: [
        Text('Goal weight', style: AppText.s(15, W.w8)),
        AppTooltip(message: tip, child: Semantics(label: 'About your goal', child: const AppIcon(AppIcons.info, size: 15, color: AppColors.muted))),
        const Spacer(),
        if (goal != null && now != null)
          pxPill(reached ? 'Goal reached' : '${pxK1((now.kg - goal).abs())} kg to go', reached ? PxTone.green : PxTone.blue),
      ]),
      Row(spacing: 8, children: [
        cell('Start', start == null ? '—' : pxAmt(start, 'kg'), pxDm(d.startDate)),
        cell('Now', now == null ? '—' : pxAmt(now.kg, 'kg'), now == null ? 'Log your weight' : pxDm(now.date), now: true),
        cell('Goal', goal == null ? '—' : pxAmt(goal, 'kg'), goal == null ? 'Ask ${d.coach}' : (eta == null || reached ? 'Your target' : DateFormatShort.month(eta))),
      ]),
      Container(
        height: 8,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(8)),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: pct,
            child: Container(decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8))),
          ),
        ),
      ),
      Transform.translate(
        offset: const Offset(0, -6),
        child: Row(spacing: 8, children: [
          Expanded(
            child: Text(
              '${lost >= 0 ? '${pxK1(lost)} kg lost' : '${pxK1(-lost)} kg up'} since ${pxDm(d.startDate)}',
              style: AppText.s(12, W.w6, color: AppColors.muted),
            ),
          ),
          Text('${(pct * 100).round()}% of the way', style: AppText.s(12, W.w6, color: AppColors.muted)),
        ]),
      ),
    ]);
  }

  // ─────────────────────────────── Tabs + Compare chip (`px-sw`)

  Widget _switch() => Row(spacing: 8, children: [
    Expanded(
      child: PxTabs(
        labels: const ['Weight', 'Body', 'Strength'],
        index: const ['Weight', 'Body', 'Strength'].indexOf(_tab),
        onPick: (i) => setState(() => _tab = const ['Weight', 'Body', 'Strength'][i]),
      ),
    ),
    PxChip('Compare', icon: AppIcons.swapAlt, on: _cmp, onTap: () => setState(() => _cmp = !_cmp)),
  ]);

  Widget _firstVsNow(PxData d) {
    final start = d.startKg, now = d.last;
    final m0 = d.measures.firstOrNull, m1 = d.measures.lastOrNull;
    final weeks = now == null ? 0 : (now.date.difference(d.startDate).inDays / 7).round();
    final rows = <(String, String, String, String, bool?)>[
      if (start != null && now != null) _row('Weight', 'kg', start, now.kg),
      for (final (k, l, u) in pxMetrics)
        if (k != 'chest' && k != 'arm' && m0?.v[k] != null && m1?.v[k] != null && m0 != m1) _row(l, u, m0!.v[k]!, m1!.v[k]!),
    ];
    return ChCard(children: [
      PxHead('First day vs now', '${pxDm(d.startDate)} → ${pxDm(now?.date ?? c.today)} · $weeks ${weeks == 1 ? 'week' : 'weeks'}'),
      if (rows.isEmpty) fdCapPx('Log your weight and measurements to compare them with day one.') else PxTable(heads: (pxDm(d.startDate), 'Now'), rows: rows),
      CaButton('Compare photos side by side', kind: CaBtnKind.out, small: true, icon: AppIcons.photo, onPressed: () => _compare(d)),
    ]);
  }

  (String, String, String, String, bool?) _row(String m, String u, double a, double b) =>
      (m, pxAmt(a, u), pxAmt(b, u), pxChg(b - a, u), b < a ? true : (b > a ? false : null));

  void _compare(PxData d) {
    if (d.sets.length < 2) {
      showPxToast(context, 'Add a second photo set first', 'Then compare it with your first one');
      return;
    }
    context.go('/progress/compare?a=${d.sets.first.id}&b=${d.sets.last.id}');
  }

  Widget _tabCard(PxData d) => switch (_tab) {
    'Body' => _body(d),
    'Strength' => _strength(d),
    _ => _weight(d),
  };

  // ─────────────────────────────── Weight (`px-wc`)

  Widget _weight(PxData d) {
    final all = d.weights;
    if (all.isEmpty) {
      return ChCard(children: [
        PxHead('No weigh-ins yet', 'Log your weight in the morning, before eating'),
        CaButton('Log weight', icon: AppIcons.plus, small: true, onPressed: () => showLogWeight(context, c)),
      ]);
    }
    final last = all.last;
    final days = _ranges[_range].$2;
    final from = days == 0 ? null : last.date.subtract(Duration(days: days - 1));
    final shown = from == null ? all : all.where((w) => !w.date.isBefore(from)).toList();
    final pts = shown.isEmpty ? [last] : shown;
    final wks = ((pts.last.date.difference(pts.first.date).inDays) / 7).round().clamp(1, 9999);
    final delta = pts.length < 2 ? 'First weigh-in' : '${pxChg(last.kg - pts.first.kg, 'kg')} in $wks ${wks == 1 ? 'wk' : 'wks'}';
    final sel = _sel == null ? null : pts.where((w) => DateUtils.isSameDay(w.date, _sel)).firstOrNull;
    final web = !context.isPhone;
    final mid = pts.first.date.add(Duration(days: pts.last.date.difference(pts.first.date).inDays ~/ 2));
    return ChCard(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 10, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Current', style: AppText.s(12, W.w7, color: AppColors.muted)),
            Text(pxAmt(last.kg, 'kg'), style: AppText.s(30, W.w8, ls: -.6, h: 1.1)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(8)),
          child: Text(delta, style: AppText.s(12.5, W.w7, color: AppColors.accentText)),
        ),
      ]),
      PxWeightChart(
        points: pts,
        goal: d.goal,
        selected: sel?.date,
        height: web ? 220 : 156,
        onPick: (w) => setState(() => _sel = sel != null && DateUtils.isSameDay(sel.date, w.date) ? null : w.date),
      ),
      Transform.translate(
        offset: const Offset(0, -6),
        child: Padding(
          padding: const EdgeInsets.only(left: 32),
          child: Row(children: [
            Text(pxDm(pts.first.date), style: AppText.s(11, W.w6, color: AppColors.muted)),
            const Spacer(),
            if (pts.length > 2) Text(pxDm(mid), style: AppText.s(11, W.w6, color: AppColors.muted)),
            if (pts.length > 2) const Spacer(),
            Text(pxDm(pts.last.date), style: AppText.s(11, W.w6, color: AppColors.muted)),
          ]),
        ),
      ),
      if (sel != null) _selected(d, sel) else fdCapPx('Tap a dot to see that weigh-in.'),
      Row(spacing: 6, children: [
        for (final (i, (n, _)) in _ranges.indexed)
          Expanded(
            child: Semantics(
              button: true,
              selected: i == _range,
              child: Hover(
                onTap: () => setState(() => _range = i),
                builder: (_, h, _) => Container(
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == _range ? AppColors.text : (h ? AppColors.outlineHover : AppColors.white),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: i == _range ? AppColors.text : AppColors.line),
                  ),
                  child: Text(n, style: AppText.s(12.5, W.w7, color: i == _range ? AppColors.white : AppColors.text2)),
                ),
              ),
            ),
          ),
      ]),
    ]);
  }

  Widget _selected(PxData d, PxWeight w) {
    final prev = d.weights.where((x) => x.date.isBefore(w.date)).lastOrNull;
    final start = d.startKg ?? d.weights.first.kg, goal = d.goal;
    final latest = DateUtils.isSameDay(w.date, d.last?.date);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        Row(spacing: 10, children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.icAmberBg, borderRadius: BorderRadius.circular(10)),
            child: const AppIcon(pxScale, size: 16, color: AppColors.icAmberText),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text(pxWdm(w.date), style: AppText.s(13.5, W.w7)),
              Text('${pxAmt(w.kg, 'kg')}${latest ? ' · latest weigh-in' : ''}', style: AppText.s(12, W.w4, color: AppColors.muted)),
            ]),
          ),
          CaIconBtn(AppIcons.close, size: 30, tooltip: 'Close', onTap: () => setState(() => _sel = null)),
        ]),
        Row(spacing: 6, children: [
          Expanded(
            child: pxStatCell('Vs previous', prev == null ? '—' : pxChg(w.kg - prev.kg, 'kg'),
                prev == null ? 'First weigh-in' : '${pxDm(prev.date)} · ${pxAmt(prev.kg, 'kg')}', down: prev == null ? null : w.kg <= prev.kg),
          ),
          Expanded(child: pxStatCell('Since start', pxChg(w.kg - start, 'kg'), '${pxDm(d.startDate)} · ${pxAmt(start, 'kg')}', down: w.kg <= start)),
          Expanded(
            child: pxStatCell('To goal', goal == null ? '—' : (w.kg <= goal ? 'Reached' : '${pxK1(w.kg - goal)} kg'), goal == null ? 'No goal set' : 'Goal ${pxAmt(goal, 'kg')}'),
          ),
        ]),
      ]),
    );
  }

  // ─────────────────────────────── Body measurements

  Widget _body(PxData d) {
    final ms = d.measures;
    final cap = 'Next measurements are due with your week ${d.nextMeasureWeek} check-in on ${pxWdm(d.nextMeasure)}.';
    if (ms.isEmpty) {
      return ChCard(children: [
        const PxHead('Body measurements', 'Measured every 2 weeks with your photo check-in'),
        fdCapPx('No measurements yet. $cap'),
      ]);
    }
    final rows = <Widget>[];
    for (final (k, l, u) in pxMetrics) {
      final pts = [for (final m in ms) if (m.v[k] != null) (m.date, m.v[k]!)];
      if (pts.isEmpty) continue;
      final first = pts.first, last = pts.last, diff = last.$2 - first.$2;
      final top = pts.map((p) => p.$2).reduce((a, b) => a > b ? a : b);
      final open = _open == k;
      rows.add(Container(
        decoration: BoxDecoration(border: rows.isEmpty ? null : const Border(top: BorderSide(color: AppColors.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            button: true,
            expanded: open,
            child: Hover(
              onTap: () => setState(() => _open = open ? null : k),
              builder: (_, h, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(spacing: 10, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                      Text(l, style: AppText.s(14, W.w7, color: h ? AppColors.accentText : AppColors.text)),
                      Text('From ${pxAmt(first.$2, u)} on ${pxDm(first.$1)}', style: AppText.s(12, W.w4, color: AppColors.muted)),
                    ]),
                  ),
                  Text(pxAmt(last.$2, u), style: AppText.s(15, W.w8)),
                  pxPill(pxChg(diff, u), diff < 0 ? PxTone.green : (diff > 0 ? PxTone.amber : PxTone.gray)),
                  AnimatedRotation(turns: open ? .5 : 0, duration: const Duration(milliseconds: 150), child: const AppIcon(AppIcons.chevronDown, size: 15, color: AppColors.muted)),
                ]),
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(spacing: 6, children: [
                for (final (i, (dt, v)) in pts.reversed.indexed)
                  Row(spacing: 8, children: [
                    SizedBox(width: 52, child: Text(pxDm(dt), style: AppText.s(12, W.w6, color: AppColors.muted))),
                    Expanded(
                      child: Container(
                        height: 6,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(6)),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: top <= 0 ? 0 : (v / top).clamp(0.0, 1.0),
                            child: Container(decoration: BoxDecoration(color: i == 0 ? AppColors.accent : AppColors.pxHist, borderRadius: BorderRadius.circular(6))),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 52, child: Text(pxAmt(v, u), textAlign: TextAlign.right, style: AppText.s(12, W.w7))),
                  ]),
              ]),
            ),
        ]),
      ));
    }
    return ChCard(children: [
      const PxHead('Body measurements', 'Measured every 2 weeks with your photo check-in'),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
      fdCapPx(cap),
    ]);
  }

  // ─────────────────────────────── Strength

  Widget _strength(PxData d) => ChCard(children: [
    const PxHead('Strength', 'Your best working set per lift'),
    if (d.lifts.isEmpty)
      fdCapPx('Finish a workout with weights and your best sets show here.')
    else
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, l) in d.lifts.indexed)
          Semantics(
            button: true,
            child: Hover(
              onTap: () => showLiftSheet(context, l),
              builder: (_, h, _) => Container(
                padding: EdgeInsets.only(top: i == 0 ? 2 : 10, bottom: 10),
                decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
                child: Row(spacing: 10, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                      Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(14, W.w7, color: h ? AppColors.accentText : AppColors.text)),
                      Text('Best set ${l.bestSet}', style: AppText.s(12, W.w4, color: AppColors.muted)),
                    ]),
                  ),
                  PxSpark(l.series),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 76),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(pxAmt(l.series.lastOrNull?.kg ?? l.bestKg, 'kgs'), style: AppText.s(15, W.w8)),
                      Text('${pxChg(l.gain, 'kgs')} in ${l.weeks} ${l.weeks == 1 ? 'wk' : 'wks'}',
                          style: AppText.s(11.5, W.w7, color: l.gain >= 0 ? AppColors.okText : AppColors.amberText)),
                    ]),
                  ),
                  const AppIcon(AppIcons.chevronRight, size: 15, color: AppColors.muted),
                ]),
              ),
            ),
          ),
      ]),
  ]);

  // ─────────────────────────────── Photos

  Widget _photos(PxData d) {
    final latest = d.sets.lastOrNull;
    return ChCard(children: [
      PxHead(
        'Photos',
        latest == null ? 'No photos yet' : 'Latest set · ${pxDm(latest.date)}${latest.kg == null ? '' : ' · ${pxAmt(latest.kg!, 'kg')}'}',
        action: pxLink('All photos', () => context.go('/progress/photos')),
      ),
      Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        for (final pose in pxPoses)
          Expanded(
            child: Semantics(
              button: true,
              label: '$pose photo',
              child: Hover(
                onTap: () => latest == null ? showAddPhotos(context, c, pose: pose) : showPhotoSheet(context, c, latest, pose),
                builder: (_, h, _) => Column(spacing: 5, children: [
                  PxTile(set: latest, pose: pose, selected: h && latest?.has(pose) == true),
                  Text(pose, style: AppText.s(12, W.w7, color: AppColors.text2)),
                ]),
              ),
            ),
          ),
      ]),
      Row(spacing: 8, children: [
        Expanded(child: CaButton('Add photos', kind: CaBtnKind.out, small: true, icon: AppIcons.camera, onPressed: () => showAddPhotos(context, c))),
        Expanded(child: CaButton('Compare', kind: CaBtnKind.out, small: true, icon: AppIcons.photo, onPressed: () => _compare(d))),
      ]),
    ]);
  }

  // ─────────────────────────────── Stat tiles

  Widget _stats(PxData d) {
    final waist = d.measures.where((m) => m.v['waist'] != null).lastOrNull?.v['waist'];
    final lift = d.lifts.where((l) => l.name.toLowerCase().contains('bench')).firstOrNull ?? d.lifts.firstOrNull;
    final liftName = lift == null ? 'Best lift' : (lift.name.toLowerCase().contains('bench') ? 'Bench best' : '${lift.name.split(' ').last} best');
    Widget tile(String l, String v, VoidCallback onTap) => Expanded(
      child: Semantics(
        button: true,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: h ? AppColors.line2 : AppColors.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w7, color: AppColors.muted)),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(v, style: AppText.s(18, W.w8))),
            ]),
          ),
        ),
      ),
    );
    return Row(spacing: 8, children: [
      tile('Waist', waist == null ? '—' : pxAmt(waist, 'cm'), () => setState(() {
        _tab = 'Body';
        _open = 'waist';
      })),
      tile('Workouts', '${d.adherence.done}', () => showWorkoutsSheet(context, d)),
      tile(liftName, lift == null ? '—' : pxAmt(lift.bestKg, 'kgs'), () => setState(() => _tab = 'Strength')),
    ]);
  }

  // ─────────────────────────────── Adherence

  Widget _adherence(PxData d) {
    final a = d.adherence;
    final wk = a.weeks;
    if (wk.isEmpty) return const SizedBox.shrink();
    final sel = (_week ?? wk.length - 1).clamp(0, wk.length - 1);
    final w = wk[sel], thisWeek = sel == wk.length - 1;
    final barH = !context.isPhone ? 80.0 : 64.0;
    final line = '${thisWeek ? 'This week · ${w.done} of ${w.planned} workouts so far' : 'Week of ${pxDm(w.start)} · ${w.done} of ${w.planned} workouts'}'
        '${w.pct == null ? '' : ' · ${w.pct}% of the plan followed'}';
    return ChCard(children: [
      PxHead(
        'Adherence',
        a.program == null ? 'No workout plan yet' : '${a.program} · ${a.done} of ${a.planned} workouts so far',
        action: a.avg == null ? null : pxPill('${a.avg}% avg', PxTone.green),
      ),
      Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 6, children: [
        for (final (i, x) in wk.indexed)
          Expanded(
            child: Semantics(
              button: true,
              selected: i == sel,
              label: 'Week of ${pxDm(x.start)}${x.pct == null ? '' : ', ${x.pct}%'}',
              child: Hover(
                onTap: () => setState(() => _week = i),
                builder: (_, h, _) {
                  final on = i == sel, lo = (x.pct ?? 0) < 85;
                  final fill = on ? (lo ? AppColors.pxBarLoOn : AppColors.accent) : (lo ? AppColors.pxBarLo : AppColors.pxBar);
                  return Column(spacing: 4, children: [
                    Text(x.pct == null ? '—' : '${x.pct}%', style: AppText.s(11, W.w7, color: on ? AppColors.text : AppColors.muted)),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 40),
                      height: barH,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(8)),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: ((x.pct ?? 0) / 100).clamp(0.0, 1.0),
                          widthFactor: 1,
                          child: Container(decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(8))),
                        ),
                      ),
                    ),
                    Text(i == wk.length - 1 ? 'This wk' : pxDm(x.start), maxLines: 1, style: AppText.s(10.5, W.w7, color: on ? AppColors.text : AppColors.muted)),
                  ]);
                },
              ),
            ),
          ),
      ]),
      pxNote(AppIcons.dumbbell, line),
    ]);
  }
}

/// "Feb 2027"
abstract final class DateFormatShort {
  static const _m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String month(DateTime d) => '${_m[d.month - 1]} ${d.year}';
}

/// Loading spinner, or the offline / error card with Try again.
Widget pxLoading(Object? error, Future<void> Function() retry, String what) => Center(
  child: error == null
      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))
      : Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, spacing: 10, children: [
            Text('Could not load $what', style: AppText.s(15, W.w7)),
            Text('Check your internet and try again', textAlign: TextAlign.center, style: AppText.s(13, W.w4, color: AppColors.muted)),
            CaButton('Try again', kind: CaBtnKind.out, expand: false, onPressed: retry),
          ]),
        ),
);

/// `fd-cap`
Widget fdCapPx(String t) => Text(t, style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.45));
