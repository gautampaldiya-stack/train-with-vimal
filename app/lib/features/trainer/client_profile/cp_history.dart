import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/util/save_file.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import 'cp_activity.dart' show CpBtn32;
import 'cp_common.dart';
import 'cp_history_chart.dart';
import 'cp_model.dart';

/// Client profile → History tab (`.hs-wrap` on both boards): 4 summary cards, "Plans over time", the Journey
/// (month by month, filter chips, Export, Show earlier months) and the side cards "About her journey" and
/// "Health over time". Everything from `clients/<id>/history/`; Export downloads `?export=csv`.
class CpHistoryTab extends StatefulWidget {
  const CpHistoryTab(this.c, {super.key});
  final CpController c;
  @override
  State<CpHistoryTab> createState() => _CpHistoryTabState();
}

const _groups = [
  ('all', 'All'),
  ('plans', 'Plans and trainer'),
  ('miles', 'Milestones and goals'),
  ('checks', 'Check-ins and forms'),
  ('health', 'Health'),
  ('acct', 'Account'),
];

class _CpHistoryTabState extends State<CpHistoryTab> {
  Map? d;
  ApiError? error;
  String group = 'all';
  int months = 4;
  bool loading = true, exporting = false;
  int _seen = -1, _req = 0;

  CpController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _seen = c.version;
    c.addListener(_onController);
    _load();
  }

  @override
  void dispose() {
    c.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    if (c.version != _seen) {
      _seen = c.version;
      _load();
    }
  }

  Future<void> _load() async {
    final req = ++_req;
    setState(() => loading = true);
    try {
      final r = await Services.api.get<Map>('clients/${c.id}/history/', query: {'group': group, 'months': months});
      if (req != _req || !mounted) return;
      d = r;
      error = null;
    } on ApiError catch (e) {
      if (req != _req || !mounted) return;
      error = e;
    }
    setState(() => loading = false);
  }

  Future<void> _export() async {
    setState(() => exporting = true);
    try {
      final r = await Services.api.download('clients/${c.id}/history/', query: {'export': 'csv'});
      final slug = c.name.toLowerCase().trim().split(RegExp(r'\s+')).join('-');
      final where = await saveFile('${slug.isEmpty ? 'client' : slug}-history-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv', r.data ?? const []);
      if (mounted) showToast(context, 'Exported', sub: '${c.first}’s journey · $where', kind: ToastKind.ok);
    } catch (e) {
      if (mounted) showToast(context, 'Could not export', sub: e is ApiError ? e.message : 'Check your connection and try again.', kind: ToastKind.info);
    }
    if (mounted) setState(() => exporting = false);
  }

  String get _pron => switch ('${c.detail['gender']}') { 'female' => 'her', 'male' => 'his', _ => 'their' };

  @override
  Widget build(BuildContext context) {
    if (d == null) return loading ? const CpLoading() : CpError(error?.message ?? '', onRetry: _load);
    final phone = context.isPhone;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      _summary(phone),
      _plans(),
      LayoutBuilder(builder: (context, b) {
        final journey = _journey(phone);
        final side = [_about(), _health()];
        if (b.maxWidth < 900) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [journey, ...side]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
          Expanded(child: journey),
          SizedBox(width: 320, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: side)),
        ]);
      }),
    ]);
  }

  // ─────────────────────────────── summary cards (`.hs-sum`)

  Widget _summary(bool phone) {
    final s = (d!['summary'] as Map?) ?? const {};
    String one(Object? v) => v is num ? v.toStringAsFixed(1) : '—';
    final start = s['start_weight'], now = s['current_weight'];
    final ch = s['weight_change'] as num?, toGoal = s['to_goal'] as num?;
    final wNote = [
      if (ch != null) cpSigned(ch, 'kg'),
      if (toGoal != null) toGoal < .05 ? 'at goal' : '${cpKg(toGoal, keep: true)} to goal',
    ].join(' · ');
    final wp = s['workouts_pct'], cp = s['checkins_pct'];
    final streak = (s['best_streak'] as num?) ?? 0;
    final cards = [
      ('With Train With Vimal', '${s['duration'] ?? '—'}', 'Joined ${cpParse(s['joined']) == null ? '—' : DateFormat('EEE, d MMM yyyy').format(cpParse(s['joined'])!)}', false),
      ('Weight', start == null && now == null ? '—' : '${one(start)} → ${one(now)} kg', wNote.isEmpty ? 'No weigh-ins yet' : wNote, s['toward_goal'] == true),
      (
        'Workouts done',
        '${s['workouts_done'] ?? 0} of ${s['workouts_planned'] ?? 0}',
        [if (wp != null) '$wp%', if (streak > 0) 'best streak $streak day${streak == 1 ? '' : 's'}'].join(' · ').ifEmpty('No workouts planned yet'),
        false
      ),
      (
        'Check-ins sent',
        '${s['checkins_sent'] ?? 0} of ${s['checkins_expected'] ?? 0}',
        [if (cp != null) '$cp%', '${s['checkins_missed'] ?? 0} missed'].join(' · '),
        false
      ),
    ];
    Widget card((String, String, String, bool) x) => Container(
          padding: EdgeInsets.symmetric(horizontal: phone ? 12 : 16, vertical: 12),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
            Text(x.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.muted)),
            Text(x.$2,
                maxLines: phone ? 2 : 1,
                softWrap: phone,
                overflow: phone ? TextOverflow.visible : TextOverflow.ellipsis,
                style: AppText.s(phone ? 17 : 19, W.w8, ls: phone ? -0.17 : -0.19, h: 1.25)),
            Text(x.$3, style: x.$4 ? AppText.s(12, W.w6, color: AppColors.okText) : AppText.s(12, W.w5, color: AppColors.muted)),
          ]),
        );
    final gap = phone ? 10.0 : 12.0;
    final perRow = phone ? 2 : 4;
    return Column(spacing: gap, children: [
      for (var i = 0; i < cards.length; i += perRow)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: gap, children: [
            for (final x in cards.skip(i).take(perRow)) Expanded(child: card(x)),
          ]),
        ),
    ]);
  }

  // ─────────────────────────────── Plans over time

  Widget _plans() => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHeader('Plans over time',
              sub: 'Every plan ${c.first} has been on, and who coached $_pron. Hover a bar for dates.', padding: const EdgeInsets.fromLTRB(16, 12, 16, 6)),
          CpPlansChart((d!['timeline'] as Map?) ?? const {}),
          const CpPlansKey(),
        ]),
      );

  // ─────────────────────────────── Journey

  Widget _journey(bool phone) {
    final ms = [for (final m in (d!['months'] as List?) ?? const []) m as Map];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader('Journey',
            sub: 'Everything that mattered, month by month. Day to day actions are in Activity.', padding: const EdgeInsets.fromLTRB(16, 12, 16, 6)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(spacing: 12, children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(spacing: 6, children: [
                  for (final (k, l) in _groups)
                    FilterChipX(l, selected: group == k, onTap: () {
                      if (group == k) return;
                      setState(() => group = k);
                      _load();
                    }),
                ]),
              ),
            ),
            CpBtn32('Export', icon: AppIcons.downloadLine, loading: exporting, onTap: _export),
          ]),
        ),
        if (ms.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: Text(group == 'all' ? 'Nothing here yet. Plans, check-ins and milestones show here as they happen.' : 'Nothing of this kind yet.',
                textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)),
          )
        else
          Opacity(
            opacity: loading ? .55 : 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < ms.length; i++) _month(ms[i], first: i == 0, phone: phone),
              ]),
            ),
          ),
        if (d!['more'] == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppButton('Show earlier months', loading: loading, onPressed: () {
                months += 6;
                _load();
              }),
            ),
          )
        else
          const SizedBox(height: 10),
      ]),
    );
  }

  Widget _month(Map m, {required bool first, required bool phone}) {
    final items = [for (final e in (m['items'] as List?) ?? const []) e as Map];
    final sum = '${m['summary'] ?? ''}';
    final head = phone
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
            Text('${m['label']}', style: AppText.s(14, W.w8)),
            if (sum.isNotEmpty) Text(sum, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
          ])
        : Text.rich(TextSpan(children: [
            TextSpan(text: '${m['label']}', style: AppText.s(14, W.w8)),
            if (sum.isNotEmpty) TextSpan(text: '   $sum', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
          ]));
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
      decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: AppColors.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.only(bottom: 6), child: head),
        Stack(children: [
          // The thin line joining the dots (`.hs-items::before`).
          if (items.length > 1) Positioned(left: 5, top: 14, bottom: 14, child: Container(width: 2, color: AppColors.hgOld)),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final e in items) _entry(e, phone)]),
        ]),
      ]),
    );
  }

  static Color _dot(String kind) => switch (kind) {
        'plan' || 'trainer' => AppColors.accent,
        'check' || 'form' => AppColors.hsCheck,
        'mile' => AppColors.vegGreen,
        'goal' || 'health' => AppColors.eggAmber,
        'acct' => AppColors.text,
        _ => AppColors.pxNoneFig,
      };

  static Tone _tone(String t) => switch (t) {
        'ok' => Tone.ok,
        'warn' => Tone.warn,
        'bad' => Tone.bad,
        'info' => Tone.info,
        _ => Tone.neutral,
      };

  Widget _entry(Map e, bool phone) {
    final badge = '${e['badge'] ?? ''}';
    final detail = '${e['detail'] ?? ''}';
    final title = Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
      Text('${e['title']}', style: AppText.s(13.5, W.w7, h: 1.35)),
      if (badge.isNotEmpty) _SmallBadge(badge, _tone('${e['tone']}')),
    ]);
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      title,
      if (detail.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(detail, style: AppText.s(12.5, W.w5, color: AppColors.text2, h: 1.45))),
    ]);
    final when = '${e['when'] ?? ''}', who = '${e['who'] ?? ''}';
    final dot = Container(
      width: 12,
      height: 12,
      margin: const EdgeInsets.only(top: 3),
      decoration: BoxDecoration(
        color: _dot('${e['kind']}'),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.card, width: 2),
        boxShadow: const [BoxShadow(color: AppColors.hsDotRing, spreadRadius: 1)],
      ),
    );
    if (phone) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
          dot,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              body,
              Text.rich(TextSpan(children: [
                TextSpan(text: when, style: AppText.s(12, W.w6, color: AppColors.text2)),
                if (who.isNotEmpty) TextSpan(text: '  ·  $who', style: AppText.s(12, W.w5, color: AppColors.muted)),
              ])),
            ]),
          ),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 14, children: [
        dot,
        Expanded(child: body),
        Column(crossAxisAlignment: CrossAxisAlignment.end, spacing: 1, children: [
          Text(when, style: AppText.s(12, W.w6, color: AppColors.text2)),
          if (who.isNotEmpty) Text(who, style: AppText.s(12, W.w5, color: AppColors.muted)),
        ]),
      ]),
    );
  }

  // ─────────────────────────────── side cards

  Widget _about() {
    final rows = [for (final r in (d!['about'] as List?) ?? const []) r as Map];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader('About $_pron journey', padding: const EdgeInsets.fromLTRB(16, 12, 16, 6)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final r in rows)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
                  Text('${r['label']}', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
                  Text('${r['value']}', style: AppText.s(14, W.w7)),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _health() {
    final rows = [for (final r in (d!['health'] as List?) ?? const []) r as Map];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader('Health over time', padding: const EdgeInsets.fromLTRB(16, 12, 16, 6)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < rows.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(top: 3),
                    decoration: BoxDecoration(
                      color: switch ('${rows[i]['tone']}') { 'warn' => AppColors.eggAmber, 'ok' => AppColors.vegGreen, _ => AppColors.pxNoneFig },
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.card, width: 2),
                      boxShadow: const [BoxShadow(color: AppColors.hsDotRing, spreadRadius: 1)],
                    ),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                      Text('${rows[i]['title']}', style: AppText.s(13, W.w7)),
                      if ('${rows[i]['detail'] ?? ''}'.isNotEmpty) Text('${rows[i]['detail']}', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// `.hs-e .t .badge.plain`: 19 high, 10.5 / 700, no dot.
class _SmallBadge extends StatelessWidget {
  const _SmallBadge(this.label, this.tone);
  final String label;
  final Tone tone;
  @override
  Widget build(BuildContext context) => Container(
        height: 19,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: tone.bg, borderRadius: AppRadius.all(AppRadius.badge)),
        child: Text(label, style: AppText.s(10.5, W.w7, color: tone.fg, h: 1)),
      );
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
