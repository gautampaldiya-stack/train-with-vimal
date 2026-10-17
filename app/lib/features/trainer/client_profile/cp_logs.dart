import 'package:flutter/material.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/pager.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tabs.dart';
import 'cp_common.dart';
import 'cp_logs_compare.dart';
import 'cp_logs_detail.dart';
import 'cp_logs_parts.dart';
import 'cp_model.dart';

/// Client profile → Logs tab (board `TrainerClientProfile` Logs): sub-tabs Workouts · Meals · Daily check-ins ·
/// Weekly check-ins · Habits · Supplements, the range picker, Compare plans, the summary line, then the log of the
/// picked kind (a table on web, blocks on a phone), 10 rows a page. Each row opens the log drawer.
class CpLogsTab extends StatefulWidget {
  const CpLogsTab(this.c, {super.key});
  final CpController c;
  @override
  State<CpLogsTab> createState() => _CpLogsTabState();
}

const _slots = [
  ('workouts', 'Workouts'),
  ('meals', 'Meals'),
  ('daily', 'Daily check-ins'),
  ('weekly', 'Weekly check-ins'),
  ('habits', 'Habits'),
  ('supps', 'Supplements'),
];

class _CpLogsTabState extends State<CpLogsTab> {
  CpController get c => widget.c;
  late CpRange range = cpRangeOf(c);
  List<CpPlan> plans = const [];
  int page = 1;
  Map? data, summary;
  ApiError? error;
  bool compare = false;
  int _seq = 0, _version = 0;

  String get slot => _slots.any((s) => s.$1 == c.logSlot) ? c.logSlot : 'workouts';

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
      _load(quiet: true);
    }
  }

  (String, Map<String, dynamic>) get _req => switch (slot) {
        'meals' => ('food/', {}),
        'daily' => ('checkins/', {'kind': 'daily'}),
        'weekly' => ('checkins/', {'kind': 'weekly'}),
        'habits' => ('habits/', {'kind': 'habits'}),
        'supps' => ('habits/', {'kind': 'supps'}),
        _ => ('workouts/', {}),
      };

  Future<void> _load({bool quiet = false}) async {
    final seq = ++_seq;
    if (!quiet) setState(() => data = null);
    final (path, q) = _req;
    try {
      final r = await Future.wait([
        Services.api.get<Map>('clients/${c.id}/$path', query: {...q, ...range.query, 'page': page}),
        Services.api.get<Map>('clients/${c.id}/logs/summary/', query: range.query),
      ]);
      if (seq != _seq || !mounted) return;
      setState(() {
        data = r[0];
        summary = r[1];
        error = null;
      });
    } on ApiError catch (e) {
      if (seq != _seq || !mounted) return;
      setState(() => error = e);
    }
  }

  void _slot(String s) {
    c.logSlot = s; // no notify: only this tab changes
    page = 1;
    _load();
  }

  void _range(CpRange r) {
    range = r;
    cpSetRange(c, r);
    page = 1;
    _load();
  }

  void _compare() {
    if (plans.length < 2) {
      showToast(context, 'Nothing to compare yet', sub: '${c.first} has had one workout plan so far. Compare plans needs two.', kind: ToastKind.info);
      return;
    }
    setState(() => compare = true);
  }

  // ─────────────────────────────── Build

  @override
  Widget build(BuildContext context) {
    if (compare) return CpLogsCompare(c, plans: plans, onBack: () => setState(() => compare = false));
    final phone = context.isPhone;
    final tabs = SegmentedTabs<String>(items: [for (final (k, l) in _slots) TabItem(k, l)], value: slot, onChanged: _slot);
    final picker = CpRangePicker(value: range, onChanged: _range, plans: [for (final p in plans) (p.id, p.name)], width: phone ? 170 : 160);
    final cmp = AppButton('Compare plans', icon: AppIcons.swap, onPressed: _compare);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 12 : 16, children: [
      if (phone) ...[
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: tabs),
        Row(spacing: 10, children: [picker, cmp]),
      ] else
        Row(spacing: 12, children: [
          Expanded(child: Align(alignment: Alignment.centerLeft, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: tabs))),
          picker,
          cmp,
        ]),
      Padding(padding: const EdgeInsets.only(top: 0), child: Text(_summary(), style: AppText.s(13, W.w5, color: AppColors.muted))),
      if (error != null)
        CpError(error!.message, onRetry: _load)
      else if (data == null)
        const AppCard(child: CpLoading())
      else
        _card(phone),
    ]);
  }

  String _summary() {
    final s = summary;
    if (s == null) return range.label;
    String n(Object? v, String one, String many) => '${v ?? 0} ${v == 1 ? one : many}';
    var head = range.label;
    if (range.value.startsWith('plan:')) {
      final to = cpParse(s['to']);
      final today = DateUtils.dateOnly(DateTime.now());
      head = '${cpDm(s['from'])} – ${to != null && DateUtils.isSameDay(to, today) ? 'today' : cpDm(s['to'])}';
    }
    return [head, n(s['workouts'], 'workout', 'workouts'), n(s['meals'], 'meal logged', 'meals logged'), n(s['checkins'], 'check-in', 'check-ins')].join(' · ');
  }

  List<Map> get rows => [for (final r in (data?['results'] as List? ?? const [])) r as Map];

  Widget? _pager() {
    final count = (data?['count'] as num?)?.toInt() ?? 0;
    final size = (data?['page_size'] as num?)?.toInt() ?? 10;
    if (count <= size) return null;
    return Pager(page: page, pageSize: size, count: count, onPage: (p) {
      page = p;
      _load();
    });
  }

  void _open(int i) => openCpLog(context, c, slot: slot, rows: rows, index: i, columns: data?['columns'] as List?, onChanged: () {
        _load(quiet: true);
        c.refresh();
      });

  Widget _card(bool phone) {
    final empty = rows.isEmpty;
    final (title, sub, emptyTitle, emptySub) = switch (slot) {
      'meals' => (
          'Meal log',
          _target(),
          'No meals in this range',
          'Days ${c.first} logs food show here.',
        ),
      'daily' => ('Daily check-ins', '${(data?['week'] as Map?)?['sent'] ?? 0} of 7 sent this week', 'No daily check-ins in this range', 'Morning check-ins ${c.first} sends show here.'),
      'weekly' => ('Weekly check-ins', 'Due every Sunday', 'No weekly check-ins in this range', 'Weekly check-ins ${c.first} sends show here.'),
      'habits' => ('Habit log', _habitSub(), 'No habits in this range', 'Assign a habit plan to see what ${c.first} ticks.'),
      'supps' => ('Supplement log', 'Ticked by ${c.first} in the app', 'No supplements in this range', 'Assign a supplement plan to see what ${c.first} ticks.'),
      _ => ('Workout log', 'Open a workout to see every set', 'No workouts in this range', 'Workouts ${c.first} logs, and planned days missed, show here.'),
    };
    return CpTableCard(
      title: title,
      sub: sub,
      pager: _pager(),
      child: empty
          ? Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
              child: EmptyState(emptyTitle, sub: emptySub, icon: AppIcons.clipboard),
            )
          : switch (slot) {
              'meals' => _meals(phone),
              'daily' => _daily(phone),
              'weekly' => _weekly(),
              'habits' || 'supps' => _ticks(phone),
              _ => _workouts(phone),
            },
    );
  }

  String _target() {
    final t = data?['target'] as Map?;
    if (t == null) return 'No meal plan';
    return 'Target ${cpNum(t['kcal'])} kcal · ${cpG(t['protein'])} protein';
  }

  String _habitSub() {
    final n = (data?['columns'] as List? ?? const []).length;
    return '$n habit${n == 1 ? '' : 's'} a day';
  }

  // ─────────────────────────────── Workouts

  static const _wStatus = {'done': ('Done', Tone.ok), 'partly': ('Partly', Tone.warn), 'missed': ('Missed', Tone.bad), 'in_progress': ('In progress', Tone.info)};

  Widget _workouts(bool phone) {
    String sets(Map r) => (r['sets_planned'] ?? 0) == 0 && (r['sets_done'] ?? 0) == 0 ? '—' : '${r['sets_done']} / ${r['sets_planned']}';
    String vol(Map r) => (r['volume'] ?? 0) == 0 ? '—' : '${cpNum(r['volume'])} kg';
    String time(Map r) => (r['duration_seconds'] ?? 0) == 0 ? '—' : '${((r['duration_seconds'] as num) / 60).round()} min';
    Widget badge(Map r) {
      final (l, t) = _wStatus['${r['status']}'] ?? ('${r['status']}', Tone.neutral);
      return AppBadge(l, tone: t);
    }

    if (phone) {
      return CpPhoneRows(
        titles: [for (final r in rows) cpDay(r['date'])],
        labels: const ['Workout', 'Sets done', 'Volume', 'Time', 'Status'],
        values: [
          for (final r in rows) [cpPv('${r['name']}'.isEmpty ? 'Workout' : '${r['name']}'), cpPv(sets(r)), cpPv(vol(r)), cpPv(time(r)), Align(alignment: Alignment.centerLeft, child: badge(r))],
        ],
        onTap: _open,
      );
    }
    return CpTable(
      cols: const [CpCol('Date', 120), CpCol('Workout', 170, grow: 2.2), CpCol('Sets done', 100, grow: 1.6), CpCol('Volume', 100, right: true), CpCol('Time', 90, right: true), CpCol('Status', 120, grow: 1.2)],
      chevron: true,
      onTap: _open,
      rows: [
        for (final r in rows)
          [cpCell(cpDay(r['date'])), cpCell('${r['name']}'.isEmpty ? 'Workout' : '${r['name']}', bold: true), cpCell(sets(r)), cpCell(vol(r)), cpCell(time(r)), badge(r)],
      ],
    );
  }

  // ─────────────────────────────── Meals

  static const _mStatus = {
    'on_plan': ('On plan', Tone.ok),
    'over': ('Over', Tone.bad),
    'partly': ('Partly', Tone.warn),
    'missed': ('Missed', Tone.bad),
    'today': ('Today', Tone.info),
    'logged': ('Logged', Tone.neutral),
  };

  Widget _meals(bool phone) {
    Widget kcal(Map r) {
      final t = (r['kcal_target'] as num?)?.toDouble();
      final k = (r['kcal'] as num?)?.toDouble() ?? 0;
      final over = r['status'] == 'over';
      return Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
        if (t != null && t > 0 && !phone)
          Container(
            width: 70,
            height: 5,
            decoration: BoxDecoration(color: AppColors.barTrack, borderRadius: BorderRadius.circular(3)),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: (k / t).clamp(0.0, 1.0),
              child: Container(decoration: BoxDecoration(color: over ? AppColors.badText : AppColors.accent, borderRadius: BorderRadius.circular(3))),
            ),
          ),
        Text(cpNum(k), style: AppText.s(13.5, phone ? W.w6 : W.w5, tabular: true)),
        if (t != null) Text('/ ${cpNum(t)}', style: AppText.s(12, W.w5, color: AppColors.muted)),
      ]);
    }

    String n(Map r) => (r['meals'] ?? 0) == 0 ? '${r['meals_logged']}' : '${r['meals_logged']} / ${r['meals']}';
    Widget badge(Map r) {
      final (l, t) = _mStatus['${r['status']}'] ?? ('${r['status']}', Tone.neutral);
      return AppBadge(l, tone: t);
    }

    if (phone) {
      return CpPhoneRows(
        titles: [for (final r in rows) cpDay(r['date'])],
        labels: const ['Calories', 'Protein', 'Carbs', 'Fat', 'Meals logged', 'On plan'],
        values: [
          for (final r in rows) [kcal(r), cpPv(cpG(r['protein'])), cpPv(cpG(r['carbs'])), cpPv(cpG(r['fat'])), cpPv(n(r)), Align(alignment: Alignment.centerLeft, child: badge(r))],
        ],
        onTap: _open,
      );
    }
    return CpTable(
      cols: const [
        CpCol('Date', 120),
        CpCol('Calories', 190, grow: 2.5),
        CpCol('Protein', 80, right: true),
        CpCol('Carbs', 80, right: true),
        CpCol('Fat', 70, right: true),
        CpCol('Meals logged', 110, grow: 1.4),
        CpCol('On plan', 100, grow: 1.2),
      ],
      chevron: true,
      onTap: _open,
      rows: [
        for (final r in rows) [cpCell(cpDay(r['date'])), kcal(r), cpCell(cpG(r['protein'])), cpCell(cpG(r['carbs'])), cpCell(cpG(r['fat'])), cpCell(n(r)), badge(r)],
      ],
    );
  }

  // ─────────────────────────────── Daily check-ins

  Widget _daily(bool phone) {
    String v(Object? x) => x == null || '$x'.isEmpty ? '—' : '$x';
    String sleep(Map r) => r['sleep'] == null ? '—' : '${cpOne(r['sleep'] as num)} h';
    String steps(Map r) => r['steps'] == null ? '—' : cpNum(r['steps'] as num);
    Widget note(Map r) => r['id'] == null
        ? const AppBadge('Not sent', tone: Tone.bad)
        : Text('${r['note']}'.isEmpty ? '—' : '${r['note']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted));
    if (phone) {
      return CpPhoneRows(
        titles: [for (final r in rows) cpDay(r['date'])],
        labels: const ['Sleep', 'Energy', 'Mood', 'Hunger', 'Steps', 'Note'],
        values: [
          for (final r in rows) [cpPv(sleep(r)), cpPv(v(r['energy'])), cpPv(v(r['mood'])), cpPv(v(r['hunger'])), cpPv(steps(r)), Align(alignment: Alignment.centerLeft, child: note(r))],
        ],
        onTap: _open,
      );
    }
    return CpTable(
      cols: const [CpCol('Date', 120), CpCol('Sleep', 70, right: true), CpCol('Energy', 90), CpCol('Mood', 90), CpCol('Hunger', 90), CpCol('Steps', 80, right: true), CpCol('Note', 180, grow: 3)],
      onTap: _open,
      rows: [
        for (final r in rows) [cpCell(cpDay(r['date'])), cpCell(sleep(r)), cpCell(v(r['energy'])), cpCell(v(r['mood'])), cpCell(v(r['hunger'])), cpCell(steps(r)), note(r)],
      ],
    );
  }

  // ─────────────────────────────── Weekly check-ins

  Widget _weekly() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
        child: Column(children: [
          for (final (i, r) in rows.indexed)
            AppRow(
              title: 'Week ${r['week']}',
              sub: cpWeeklyLine(r),
              trailing: switch ('${r['status']}') {
                'to_review' => const AppBadge('To review', tone: Tone.info),
                'reviewed' => const AppBadge('Reviewed', tone: Tone.ok),
                _ => const AppBadge('Missed', tone: Tone.bad),
              },
              chevron: true,
              onTap: () => _open(i),
            ),
        ]),
      );

  // ─────────────────────────────── Habits / supplements

  Widget _ticks(bool phone) {
    final cols = [for (final x in (data?['columns'] as List? ?? const [])) x as Map];
    Widget done(Map r) {
      final d = (r['done'] as num?)?.toInt() ?? 0, due = (r['due'] as num?)?.toInt() ?? 0;
      return AppBadge('$d / $due', tone: due == 0 ? Tone.neutral : (d >= due ? Tone.ok : (d == 0 ? Tone.bad : Tone.warn)));
    }

    bool? cell(Map r, Map col) => ((r['cells'] as Map?) ?? const {})['${col['id']}'] as bool?;
    if (phone) {
      return CpPhoneRows(
        titles: [for (final r in rows) cpDay(r['date'])],
        labels: [for (final x in cols) '${x['name']}', 'Done'],
        values: [
          for (final r in rows) [for (final x in cols) Align(alignment: Alignment.centerLeft, child: cpTick(cell(r, x))), Align(alignment: Alignment.centerLeft, child: done(r))],
        ],
        onTap: _open,
      );
    }
    return CpTable(
      cols: [const CpCol('Date', 120), for (final x in cols) CpCol('${x['name']}', 130, grow: 2), const CpCol('Done', 80)],
      onTap: _open,
      rows: [
        for (final r in rows) [cpCell(cpDay(r['date'])), for (final x in cols) cpTick(cell(r, x)), done(r)],
      ],
    );
  }
}

/// "Sent Sun, 4 Oct · 71.6 kg · 3 photos · "Knee better"" / "… · reply by Aman Verma" / "Not sent".
String cpWeeklyLine(Map r) {
  if (r['id'] == null) return 'Not sent';
  final bits = ['Sent ${cpDay(r['date'])}', if (r['weight'] != null) cpKg(r['weight'], keep: true)];
  if (r['status'] == 'reviewed') {
    if ('${r['reply'] ?? ''}'.isNotEmpty && r['reviewer'] != null) {
      bits.add('reply by ${r['reviewer']}');
    } else if (r['reviewer'] != null) {
      bits.add('reviewed by ${r['reviewer']}');
    }
  } else {
    final n = (r['photo_count'] as num?)?.toInt() ?? 0;
    if (n > 0) bits.add('$n photo${n == 1 ? '' : 's'}');
    final note = '${r['note'] ?? ''}'.trim();
    if (note.isNotEmpty) bits.add('“${note.length > 60 ? '${note.substring(0, 60)}…' : note}”');
  }
  return bits.join(' · ');
}
