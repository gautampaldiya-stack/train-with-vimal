import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/responsive.dart';
import 'train_model.dart';
import 'workout_model.dart' show SetKind;

/// Workout History (Probid 19 Nov, Strong's History): a page, not a sheet. Months with their workouts; each workout a
/// card with its exercises (sets × name) and best set, then time, kg lifted and PRs. Tap a card for the workout.
/// Only looking here: edit and log are for yesterday, from the Train strip.

String _when(DateTime? at, DateTime day) {
  final d = at ?? day;
  return at == null ? DateFormat('EEEE d MMMM, y').format(d) : '${DateFormat('EEEE d MMMM, y').format(d)} at ${DateFormat('h:mm a').format(d).toLowerCase()}';
}

String _hm(int seconds) {
  final m = (seconds / 60).round();
  return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m';
}

String _kgs(double v) => '${NumberFormat.decimalPattern().format(v.round())} kg';

/// Time · kg lifted · PRs, with icons (the line under a Strong history card and workout).
Widget _stats(int seconds, double volume, int prs) {
  Widget stat(AppIconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
        AppIcon(icon, size: 16, color: AppColors.muted),
        Text(text, style: AppText.s(14, W.w5, color: AppColors.text2, tabular: true)),
      ]);
  return Wrap(spacing: 22, runSpacing: 6, children: [
    stat(AppIcons.clock, _hm(seconds)),
    if (volume > 0) stat(AppIcons.dumbbell, _kgs(volume)),
    if (prs > 0) stat(AppIcons.award, '$prs ${prs == 1 ? 'PR' : 'PRs'}'),
  ]);
}

/// A phone page with the Strong bar (Back, moving title) or, wider, a plain column with a back link.
Widget _page(BuildContext context, {required String title, String? sub, required String backTip, required VoidCallback onBack, required List<Widget> children, ScrollController? scroll}) {
  if (context.isPhone) {
    return CaPinned(
      titleTop: 2,
      head: CaTopBar(title: title, onBack: onBack, backTip: backTip),
      body: ListView(
        controller: scroll,
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
          Align(
            alignment: Alignment.centerLeft,
            child: CaBarText(backTip, icon: AppIcons.chevronLeft, onTap: onBack),
          ),
          Padding(padding: const EdgeInsets.only(top: 6, bottom: 18), child: CaPageTitle(title, sub: sub)),
          ...children,
        ],
      ),
    ),
  );
}

Widget _spinner() => const Padding(
      padding: EdgeInsets.all(28),
      child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))),
    );

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
      else if (_rows.isEmpty && !_loading && _last != null)
        const Padding(
          padding: EdgeInsets.only(top: 24),
          child: CaEmpty(icon: AppIcons.dumbbell, title: 'No workouts yet', sub: 'Finished workouts show here, newest first.'),
        ),
      for (final (i, (m, rows)) in months.indexed) ...[
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 2 : 18, bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: Text(DateFormat(m.year == DateTime.now().year ? 'MMMM' : 'MMMM y').format(m), style: AppText.s(19, W.w6, ls: -0.2))),
            // a month still loading more is not counted yet
            if (i < months.length - 1 || !_more)
              Text('${rows.length} ${rows.length == 1 ? 'workout' : 'workouts'}', style: AppText.s(13, W.w5, color: AppColors.muted)),
          ]),
        ),
        for (final r in rows) Padding(padding: const EdgeInsets.only(bottom: 12), child: _card(r)),
      ],
      if (_loading) _spinner(),
    ];
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: () => _load(again: true),
      child: _page(
        context,
        title: 'History',
        sub: _last == null ? null : '$n ${n == 1 ? 'workout' : 'workouts'}',
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
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: h ? AppColors.sub : AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: h ? AppColors.line2 : AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(spacing: 8, children: [
              Expanded(child: Text(r.name, style: AppText.s(16.5, W.w6))),
              if (r.edited > 0) Text('Edited', style: AppText.s(12, W.w6, color: AppColors.muted)),
            ]),
            Text(_when(r.startedAt, r.date), style: AppText.s(13.5, W.w4, color: AppColors.text2)),
            if (shown.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(flex: 3, child: Text('Sets', style: AppText.s(14, W.w6))),
                Expanded(flex: 2, child: Text('Best set', style: AppText.s(14, W.w6))),
              ]),
              const SizedBox(height: 4),
              for (final x in shown)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 3, child: Text('${x.sets} × ${x.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(14, W.w4, color: AppColors.text2))),
                    Expanded(flex: 2, child: Text(x.best, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(14, W.w4, color: AppColors.text2, tabular: true))),
                  ]),
                ),
              if (left > 0) Text('and $left more', style: AppText.s(13, W.w5, color: AppColors.muted)),
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

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final back = widget.from == 'progress' ? 'History' : 'History';
    if (d == null) {
      return _page(context, title: 'Workout', backTip: back, onBack: _back, children: [
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
          _spinner(),
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
    return _page(
      context,
      title: r.name,
      sub: _when(shownStart, r.date),
      backTip: back,
      onBack: _back,
      children: [
        for (final g in d.groups) _exercise(g),
        if (d.groups.isEmpty) Text('No sets were ticked in this workout.', style: AppText.s(14, W.w4, color: AppColors.muted)),
        const SizedBox(height: 8),
        _stats(r.seconds, volume, prs),
        if (r.effort != null || edits > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              [if (r.effort != null) 'Effort ${r.effort}/10', if (edits > 0) 'Edited $edits ${edits == 1 ? 'time' : 'times'}'].join(' · '),
              style: AppText.s(13, W.w5, color: AppColors.muted),
            ),
          ),
        if (r.note.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text('Your note', style: AppText.s(11.5, W.w7, color: AppColors.infoText)),
              Text(r.note, style: AppText.s(13.5, W.w4, color: AppColors.text2)),
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
    var n = 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(g.name, style: AppText.s(16, W.w6))),
          if (rm) SizedBox(width: 56, child: Text('1RM', textAlign: TextAlign.right, style: AppText.s(14, W.w6))),
        ]),
        const SizedBox(height: 6),
        for (final s in g.sets) ...[
          () {
            final kind = SetKind.of(s['set_type'] as String?);
            if (kind == SetKind.normal) n++;
            final color = switch (kind) {
              SetKind.warmup => AppColors.amberText,
              SetKind.drop => AppColors.purpleText,
              SetKind.failure => AppColors.badText,
              SetKind.normal => AppColors.text2,
            };
            final one = _oneRm(g.logType, s);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(children: [
                SizedBox(width: 30, child: Text(kind == SetKind.normal ? '$n' : kind.letter, style: AppText.s(15, W.w5, color: color, tabular: true))),
                Expanded(child: Text(PastDetail.setText(g.logType, s), style: AppText.s(15, W.w4, color: AppColors.text2, tabular: true))),
                if (rm) SizedBox(width: 56, child: Text(one == null ? '' : '$one', textAlign: TextAlign.right, style: AppText.s(15, W.w4, color: AppColors.text2, tabular: true))),
              ]),
            );
          }(),
          if (s['is_pr'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
                  decoration: BoxDecoration(color: AppColors.okBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.okText.withValues(alpha: .35))),
                  child: Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
                    const AppIcon(AppIcons.award, size: 13, color: AppColors.okText),
                    Text('Personal best', style: AppText.s(12.5, W.w6, color: AppColors.okText)),
                  ]),
                ),
              ),
            ),
        ],
      ]),
    );
  }
}
