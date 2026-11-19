import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/skeleton.dart';
import 'train_model.dart';
import 'workout_model.dart' show SetKind;

/// Workout History (Probid 19 Nov, Strong's History): a page, not a sheet. Months with their workouts; each workout a
/// card with its exercises (sets × name) and best set, then time, kg lifted and PRs as coloured pills. Tap a card for
/// the workout. Only looking here: edit and log are for today / yesterday, from the Train strip.
/// The page frame, the pills and the skeleton are shared with Food → History and Water history.

String _when(DateTime? at, DateTime day) {
  final d = at ?? day;
  return at == null ? DateFormat('EEEE d MMMM, y').format(d) : '${DateFormat('EEEE d MMMM, y').format(d)} at ${DateFormat('h:mm a').format(d).toLowerCase()}';
}

String _hm(int seconds) {
  final m = (seconds / 60).round();
  return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m';
}

String _kgs(double v) => '${NumberFormat.decimalPattern().format(v.round())} kg';

/// A soft coloured pill with a coloured icon: "⏱ 55m", "🏋 4,352 kg", "🏅 3 PRs" (Probid 19 Nov: icons in colour).
class HistPill extends StatelessWidget {
  const HistPill(this.icon, this.text, {super.key, required this.bg, required this.fg});
  final AppIconData icon;
  final String text;
  final Color bg, fg;

  static HistPill time(String t) => HistPill(AppIcons.clock, t, bg: AppColors.skySoft, fg: AppColors.skyMid);
  static HistPill kg(String t) => HistPill(AppIcons.dumbbell, t, bg: AppColors.accentSoft, fg: AppColors.accentText);
  static HistPill prs(String t) => HistPill(AppIcons.award, t, bg: AppColors.amberBg, fg: AppColors.amberText);

  @override
  Widget build(BuildContext context) => Container(
        height: 28,
        padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
          AppIcon(icon, size: 14, color: fg, stroke: 2.2),
          Text(text, style: AppText.s(13, W.w6, color: fg, tabular: true)),
        ]),
      );
}

Widget _stats(int seconds, double volume, int prs) => Wrap(spacing: 8, runSpacing: 6, children: [
      HistPill.time(_hm(seconds)),
      if (volume > 0) HistPill.kg(_kgs(volume)),
      if (prs > 0) HistPill.prs('$prs ${prs == 1 ? 'PR' : 'PRs'}'),
    ]);

/// A round coloured tile with an icon, at the start of a history card.
Widget histTile(AppIconData icon, {Color bg = AppColors.tnBlueBg, Color fg = AppColors.accent, double size = 40}) => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * .3)),
      child: AppIcon(icon, size: size * .45, color: fg),
    );

/// A phone page with the Strong bar (Back, moving title) or, wider, a plain column with a back link.
Widget histPage(BuildContext context, {required String title, String? sub, required String backTip, required VoidCallback onBack, required List<Widget> children, ScrollController? scroll, Widget? action}) {
  if (context.isPhone) {
    return CaPinned(
      titleTop: 2,
      head: CaTopBar(title: title, onBack: onBack, backTip: backTip, actions: [?action]),
      body: ListView(
        controller: scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 32),
        children: [
          Padding(padding: const EdgeInsets.only(bottom: 14), child: CaPageTitle(title, sub: sub)),
          ...children,
        ],
      ),
    );
  }
  return Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
        children: [
          Row(children: [
            CaBarText(backTip, icon: AppIcons.chevronLeft, onTap: onBack),
            const Spacer(),
            ?action,
          ]),
          Padding(padding: const EdgeInsets.only(top: 6, bottom: 18), child: CaPageTitle(title, sub: sub)),
          ...children,
        ],
      ),
    ),
  );
}

/// Loading: [cards] grey cards shaped like the real ones, breathing (Probid 19 Nov: skeleton).
class HistSkeleton extends StatelessWidget {
  const HistSkeleton({super.key, this.cards = 3, this.lines = 3, this.header = true});
  final int cards, lines;
  final bool header;
  @override
  Widget build(BuildContext context) => Skeleton(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          if (header) const Padding(padding: EdgeInsets.only(top: 2, bottom: 2), child: SkelBox(width: 120, height: 18)),
          for (var i = 0; i < cards; i++)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
                const Row(spacing: 12, children: [
                  SkelBox(width: 40, height: 40, radius: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 7, children: [
                      SkelBox(width: 130, height: 14),
                      SkelBox(width: 200, height: 11),
                    ]),
                  ),
                ]),
                for (var k = 0; k < lines; k++)
                  Row(children: [
                    Expanded(child: SkelBox(width: 140.0 - k * 18, height: 11)),
                    const SkelBox(width: 70, height: 11),
                  ]),
                const Row(spacing: 8, children: [SkelBox(width: 64, height: 26, radius: 13), SkelBox(width: 84, height: 26, radius: 13)]),
              ]),
            ),
        ]),
      );
}

// ─────────────────────────────── History list

class WorkoutHistoryScreen extends StatefulWidget {
  const WorkoutHistoryScreen({super.key});
  @override
  State<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends State<WorkoutHistoryScreen> {
  final _rows = <PastRow>[];
  PastPage? _last;
  int _pageNo = 0;
  bool _loading = false;
  String? _error;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // the next page comes in as the list nears its end
      if (_scroll.position.extentAfter < 600) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool get _more => _last == null || _last!.next != null;

  Future<void> _load({bool again = false}) async {
    if (_loading || (!again && !_more)) return;
    setState(() => _loading = true);
    try {
      final p = await loadPast(page: again ? 1 : _pageNo + 1);
      if (again) _rows.clear();
      _pageNo = again ? 1 : _pageNo + 1;
      _last = p;
      _rows.addAll(p.rows);
      _error = null;
    } on ApiError catch (e) {
      _error = e.offline ? 'You are offline. Connect to see your workouts.' : 'Could not load your workouts. Try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = _last?.count ?? 0;
    final months = <(DateTime, List<PastRow>)>[];
    for (final r in _rows) {
      final m = DateTime(r.date.year, r.date.month);
      if (months.isEmpty || months.last.$1 != m) months.add((m, []));
      months.last.$2.add(r);
    }
    final children = <Widget>[
      if (_rows.isEmpty && _error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(spacing: 10, children: [
            Text(_error!, textAlign: TextAlign.center, style: AppText.s(13.5, W.w5, color: AppColors.muted)),
            CaButton('Try again', kind: CaBtnKind.out, small: true, expand: false, onPressed: () => _load(again: true)),
          ]),
        )
      else if (_rows.isEmpty && _last == null)
        const HistSkeleton()
      else if (_rows.isEmpty && !_loading)
        const Padding(
          padding: EdgeInsets.only(top: 24),
          child: CaEmpty(icon: AppIcons.dumbbell, title: 'No workouts yet', sub: 'Finished workouts show here, newest first.'),
        ),
      for (final (i, (m, rows)) in months.indexed) ...[
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 2 : 18, bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, spacing: 8, children: [
            Text(DateFormat(m.year == DateTime.now().year ? 'MMMM' : 'MMMM y').format(m), style: AppText.s(19, W.w7, ls: -0.2)),
            // a month still loading more is not counted yet
            if (i < months.length - 1 || !_more)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(10)),
                child: Text('${rows.length} ${rows.length == 1 ? 'workout' : 'workouts'}', style: AppText.s(12, W.w6, color: AppColors.accentText)),
              ),
          ]),
        ),
        for (final r in rows) Padding(padding: const EdgeInsets.only(bottom: 12), child: _card(r)),
      ],
      if (_loading && _rows.isNotEmpty) const HistSkeleton(cards: 1, header: false),
    ];
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: () => _load(again: true),
      child: histPage(
        context,
        title: 'Workout history',
        sub: _last == null ? 'Your finished workouts' : '$n ${n == 1 ? 'workout' : 'workouts'} done',
        backTip: 'Train',
        onBack: () => context.go('/train'),
        scroll: _scroll,
        children: children,
      ),
    );
  }

  Widget _card(PastRow r) {
    final shown = r.summary.take(6).toList();
    final left = r.summary.length - shown.length;
    return Semantics(
      button: true,
      label: 'Open ${r.name}, ${DateFormat('d MMMM').format(r.date)}',
      child: Hover(
        onTap: () => context.go('/train/history/${r.id}'),
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: h ? AppColors.outlineHover : AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: h ? AppColors.line2 : AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(spacing: 12, children: [
              histTile(r.pr ? AppIcons.award : AppIcons.dumbbell, bg: r.pr ? AppColors.amberBg : AppColors.tnBlueBg, fg: r.pr ? AppColors.amberText : AppColors.accent),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Row(spacing: 8, children: [
                    Flexible(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(16.5, W.w7))),
                    if (r.edited > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.purpleBg, borderRadius: BorderRadius.circular(6)),
                        child: Text('Edited', style: AppText.s(11, W.w7, color: AppColors.purpleText)),
                      ),
                  ]),
                  Text(_when(r.startedAt, r.date), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
                ]),
              ),
              const AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.chevron),
            ]),
            if (shown.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(flex: 3, child: Text('SETS', style: AppText.s(11, W.w8, color: AppColors.muted, ls: .8))),
                Expanded(flex: 2, child: Text('BEST SET', style: AppText.s(11, W.w8, color: AppColors.muted, ls: .8))),
              ]),
              const SizedBox(height: 4),
              for (final x in shown)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      flex: 3,
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: '${x.sets} × ', style: AppText.s(14, W.w7, color: AppColors.accentText, tabular: true)),
                          TextSpan(text: x.name, style: AppText.s(14, W.w5, color: AppColors.text)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(flex: 2, child: Text(x.best, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(14, W.w5, color: AppColors.text2, tabular: true))),
                  ]),
                ),
              if (left > 0) Text('and $left more', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
            ],
            const SizedBox(height: 12),
            _stats(r.seconds, r.volume, r.prs),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────── One workout

class WorkoutDetailScreen extends StatefulWidget {
  const WorkoutDetailScreen({super.key, required this.id, this.from});
  final String id;

  /// Where Back goes ("progress" from Progress → History, else the workout history).
  final String? from;
  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> {
  PastDetail? _d;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await loadPastDetail(widget.id);
      if (mounted) setState(() => _d = d);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.offline ? 'You are offline. Connect to see this workout.' : 'Could not open this workout. Try again.');
    }
  }

  void _back() => context.go(widget.from == 'progress' ? '/progress/history' : '/train/history');
  String get _backTip => widget.from == 'progress' ? 'All history' : 'Workout history';

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) {
      return histPage(context, title: 'Workout', backTip: _backTip, onBack: _back, children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(spacing: 10, children: [
              Text(_error!, textAlign: TextAlign.center, style: AppText.s(13.5, W.w5, color: AppColors.muted)),
              CaButton('Try again', kind: CaBtnKind.out, small: true, expand: false, onPressed: () {
                setState(() => _error = null);
                _load();
              }),
            ]),
          )
        else
          const HistSkeleton(cards: 3, lines: 4, header: false),
      ]);
    }
    final r = d.row;
    final started = DateTime.tryParse('${d.j['started_at'] ?? ''}')?.toLocal();
    final end = DateTime.tryParse('${d.j['finished_at'] ?? ''}')?.toLocal();
    final shownStart = end != null ? end.subtract(Duration(seconds: r.seconds)) : started;
    var volume = 0.0, prs = 0;
    for (final g in d.groups) {
      for (final s in g.sets) {
        volume += (s['volume'] as num?)?.toDouble() ?? 0;
        if (s['is_pr'] == true) prs++;
      }
    }
    final edits = (d.j['edits'] as List? ?? const []).length;
    return histPage(
      context,
      title: r.name,
      sub: _when(shownStart, r.date),
      backTip: _backTip,
      onBack: _back,
      children: [
        // time · kg · PRs on top, then effort and edits as small pills
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Wrap(spacing: 8, runSpacing: 6, children: [
            HistPill.time(_hm(r.seconds)),
            if (volume > 0) HistPill.kg(_kgs(volume)),
            if (prs > 0) HistPill.prs('$prs ${prs == 1 ? 'PR' : 'PRs'}'),
            if (r.effort != null) HistPill(AppIcons.flame, 'Effort ${r.effort}/10', bg: AppColors.warmBg, fg: AppColors.warm),
            if (edits > 0) HistPill(AppIcons.edit, 'Edited $edits×', bg: AppColors.purpleBg, fg: AppColors.purpleText),
          ]),
        ),
        for (final g in d.groups) Padding(padding: const EdgeInsets.only(bottom: 12), child: _exercise(g)),
        if (d.groups.isEmpty) Text('No sets were ticked in this workout.', style: AppText.s(14, W.w4, color: AppColors.muted)),
        if (r.note.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              const AppIcon(AppIcons.chatBubble, size: 16, color: AppColors.infoText),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                  Text('Your note', style: AppText.s(11.5, W.w7, color: AppColors.infoText)),
                  Text(r.note, style: AppText.s(13.5, W.w4, color: AppColors.text2)),
                ]),
              ),
            ]),
          ),
      ],
    );
  }

  /// Estimated one-rep max of a weight set (Epley), like Strong's 1RM column.
  static int? _oneRm(String logType, Map<String, dynamic> s) {
    if (logType != 'weight_reps' || s['is_bodyweight'] == true) return null;
    final w = (s['weight_kg'] is num ? s['weight_kg'] as num : num.tryParse('${s['weight_kg'] ?? ''}'))?.toDouble();
    final r = (s['reps'] as num?)?.toInt();
    if (w == null || w <= 0 || r == null || r <= 0) return null;
    return r == 1 ? w.round() : (w * (1 + r / 30)).round();
  }

  Widget _exercise(({String name, String logType, bool pr, List<Map<String, dynamic>> sets}) g) {
    final rm = g.logType == 'weight_reps';
    final (icon, bg, fg) = switch (g.logType) {
      'distance' => (AppIcons.heartPulse, AppColors.badBg, AppColors.badText),
      'time' => (AppIcons.clock, AppColors.amberBg, AppColors.amberText),
      'bodyweight_reps' => (AppIcons.person, AppColors.okBg, AppColors.okText),
      _ => (AppIcons.dumbbell, AppColors.tnBlueBg, AppColors.accent),
    };
    var n = 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(spacing: 10, children: [
          histTile(icon, bg: bg, fg: fg, size: 32),
          Expanded(child: Text(g.name, style: AppText.s(15.5, W.w7, color: AppColors.accentText))),
          if (rm) SizedBox(width: 50, child: Text('1RM', textAlign: TextAlign.right, style: AppText.s(11, W.w8, color: AppColors.muted, ls: .8))),
        ]),
        const SizedBox(height: 8),
        for (final s in g.sets) ...[
          () {
            final kind = SetKind.of(s['set_type'] as String?);
            if (kind == SetKind.normal) n++;
            final (lbg, lfg) = switch (kind) {
              SetKind.warmup => (AppColors.amberBg, AppColors.amberText),
              SetKind.drop => (AppColors.purpleBg, AppColors.purpleText),
              SetKind.failure => (AppColors.badBg, AppColors.badText),
              SetKind.normal => (AppColors.sub, AppColors.text2),
            };
            final one = _oneRm(g.logType, s);
            final best = s['is_pr'] == true;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(spacing: 10, children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: lbg, borderRadius: BorderRadius.circular(7)),
                  child: Text(kind == SetKind.normal ? '$n' : kind.letter, style: AppText.s(12.5, W.w7, color: lfg, tabular: true)),
                ),
                Expanded(
                  child: Row(spacing: 8, children: [
                    Flexible(child: Text(PastDetail.setText(g.logType, s), style: AppText.s(15, W.w5, color: AppColors.text, tabular: true))),
                    if (best)
                      Container(
                        padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
                        decoration: BoxDecoration(color: AppColors.amberBg, borderRadius: BorderRadius.circular(10)),
                        child: Row(mainAxisSize: MainAxisSize.min, spacing: 3, children: [
                          const AppIcon(AppIcons.award, size: 12, color: AppColors.amberText),
                          Text('PR', style: AppText.s(11.5, W.w7, color: AppColors.amberText)),
                        ]),
                      ),
                  ]),
                ),
                if (rm) SizedBox(width: 50, child: Text(one == null ? '' : '$one', textAlign: TextAlign.right, style: AppText.s(14.5, W.w6, color: AppColors.text2, tabular: true))),
              ]),
            );
          }(),
        ],
      ]),
    );
  }
}

/// One stat in a [HistStats] card.
class HistStat {
  const HistStat(this.icon, this.bg, this.fg, this.value, this.label, {this.unit = '', this.of, this.progress});
  final AppIconData icon;
  final Color bg, fg;
  final String value, unit, label;

  /// "of 1,958" under the label, and a thin bar filled to [progress] (0–1) in [fg].
  final String? of;
  final double? progress;
}

/// The stats on top of a history page (Probid 19 Nov: not plain, not loud): one white card, each stat with a small
/// coloured icon, the number, its label and, when it has a target, a thin bar in the same colour.
class HistStats extends StatelessWidget {
  const HistStats(this.stats, {super.key});
  final List<HistStat> stats;

  @override
  Widget build(BuildContext context) {
    // four stats go 2 × 2, so each has room (Probid 19 Nov: four across looked crowded)
    final cols = stats.length == 4 ? 2 : stats.length;
    final rows = [for (var i = 0; i < stats.length; i += cols) stats.sublist(i, (i + cols).clamp(0, stats.length))];
    Widget cell(HistStat s) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 7, children: [
          Row(spacing: 8, children: [
            histTile(s.icon, bg: s.bg, fg: s.fg, size: 28),
            Flexible(child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.text2))),
          ]),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: s.value, style: AppText.s(21, W.w8, ls: -0.3, tabular: true, color: AppColors.text)),
              if (s.unit.isNotEmpty) TextSpan(text: ' ${s.unit}', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (s.progress != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: s.progress!.clamp(0.0, 1.0), minHeight: 5, backgroundColor: AppColors.barTrack, color: s.fg),
            ),
          if (s.of != null) Text(s.of!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted)),
        ]);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: Column(children: [
        for (final (r, row) in rows.indexed) ...[
          if (r > 0) const Divider(height: 1, thickness: 1, color: AppColors.line),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (i, s) in row.indexed) ...[
                  if (i > 0) const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: VerticalDivider(width: 1, thickness: 1, color: AppColors.line)),
                  Expanded(child: cell(s)),
                ],
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}
