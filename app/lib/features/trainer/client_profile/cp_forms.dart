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
import '../../auth/setup/setup_state.dart';
import 'cp_common.dart';
import 'cp_content_drawers.dart';
import 'cp_forms_editor.dart';
import 'cp_forms_print.dart';
import 'cp_forms_send.dart';
import 'cp_model.dart';

/// Client profile → Forms tab (`clients/<id>/forms/`). Left: "Forms · N forms for Riya · copies of the master
/// forms" with Send a form and one row per form (Done / Signed / Waiting / Recurring). Right: the selected form —
/// answers by section with Print, or the questions with what was changed for her, Edit for Riya, ⋯ Duplicate and
/// edit · Send now · Reset to master · Stop sending, and Remind again on a form she has not answered.
class CpFormsTab extends StatefulWidget {
  const CpFormsTab(this.c, {super.key});
  final CpController c;
  @override
  State<CpFormsTab> createState() => _CpFormsTabState();
}

enum _Mode { view, edit, dup }

class _CpFormsTabState extends State<CpFormsTab> {
  CpController get c => widget.c;
  List<Map> rows = [], canSend = [];
  String? sel;
  Map? detail;
  bool loading = true, detailLoading = false;
  ApiError? error, detailError;
  _Mode mode = _Mode.view;
  // the editor's source: a list key, or a library form (from Send a form → edit first)
  String? edKey, edForm, edName;
  CpSendOpts? edOpts;
  int _seen = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CpFormsTab old) {
    super.didUpdateWidget(old);
    if (_seen != c.version) _load();
  }

  Future<void> _load({String? select}) async {
    _seen = c.version;
    try {
      final r = await Services.api.get<Map>('clients/${c.id}/forms/');
      if (!mounted) return;
      rows = [for (final x in (r['sent'] as List? ?? const [])) x as Map];
      canSend = [for (final x in (r['can_send'] as List? ?? const [])) x as Map];
      final want = select ?? sel;
      sel = rows.any((x) => x['key'] == want) ? want : (rows.isEmpty ? null : '${rows.first['key']}');
      error = null;
      loading = false;
      setState(() {});
      await _loadDetail();
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          loading = false;
        });
      }
    }
  }

  Future<void> _loadDetail() async {
    final k = sel;
    if (k == null || k == 'onboarding') {
      setState(() => detail = null);
      return;
    }
    setState(() => detailLoading = true);
    try {
      final d = await Services.api.get<Map>('clients/${c.id}/forms/$k/');
      if (mounted && sel == k) {
        setState(() {
          detail = d;
          detailError = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => detailError = e);
    }
    if (mounted) setState(() => detailLoading = false);
  }

  void _pick(String key) {
    setState(() {
      sel = key;
      mode = _Mode.view;
    });
    _loadDetail();
  }

  Map? get _row => rows.where((r) => r['key'] == sel).firstOrNull;

  // ─────────────────────────────── Actions

  Future<void> _send() async {
    final r = await showSendFormDrawer(context, c, canSend);
    if (r == null || !mounted) return;
    if (r.key != null) {
      showToast(context, '${r.name} sent to ${c.first}', sub: r.key!.startsWith('sched:') ? 'It goes out on the day you picked' : null);
      await _afterChange(select: r.key);
    } else {
      setState(() {
        mode = _Mode.dup;
        edKey = null;
        edForm = r.formId;
        edName = r.name;
        edOpts = r.opts;
      });
    }
  }

  Future<void> _afterChange({String? select}) async {
    if (select != null) sel = select;
    mode = _Mode.view;
    await c.refresh(); // header, tab count; this tab reloads through `version`
  }

  Future<void> _act(String act) async {
    final k = sel;
    if (k == null) return;
    final name = '${detail?['name'] ?? ''}';
    if (act == 'reset') {
      final ok = await confirmAction(context,
          title: 'Reset to master?',
          body: 'Every change made for ${c.first} goes away and ${cpShe(c)} gets the master "$name" again. Answers already sent are kept.',
          confirm: 'Reset to master',
          danger: true,
          icon: AppIcons.reset);
      if (!ok || !mounted) return;
    }
    if (act == 'stop' && k.startsWith('req:')) {
      final ok = await confirmAction(context,
          title: 'Stop sending $name?',
          body: '${c.first} has not answered it yet. It goes away from ${cpHer(c)} app.',
          confirm: 'Stop sending',
          danger: true,
          icon: AppIcons.stop);
      if (!ok) return;
    }
    try {
      final r = await Services.api.post<Map>('clients/${c.id}/forms/$k/$act/');
      if (!mounted) return;
      final undo = act == 'stop' && !k.startsWith('req:');
      showToast(context, '${r['message'] ?? 'Done'}',
          action: undo ? 'Undo' : null,
          onAction: undo
              ? () async {
                  try {
                    await Services.api.post('clients/${c.id}/forms/$k/start/');
                    await c.refresh();
                  } on ApiError catch (e) {
                    if (mounted) showToast(context, 'Could not undo', sub: e.message);
                  }
                }
              : null);
      await _afterChange(select: act == 'send_now' ? '${r['key']}' : (r['key'] == null ? null : k));
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not do that', sub: e.message);
    }
  }

  void _edit({required bool dup}) => setState(() {
        mode = dup ? _Mode.dup : _Mode.edit;
        edKey = sel;
        edForm = null;
        edName = '${detail?['name'] ?? _row?['name'] ?? ''}';
        edOpts = null;
      });

  Future<void> _print(String title, String cap, List<(String, List<(String, String)>)> sections) async {
    final where = await printForm(title: title, cap: cap, sections: sections);
    if (where != null && mounted) showToast(context, 'Saved for printing', sub: where);
  }

  /// (key, name) of what she gets now, for the editor's "Instead of".
  List<(String, String)> get _sending => [
        for (final r in rows)
          if (['waiting', 'recurring', 'scheduled'].contains(r['status'])) ('${r['key']}', '${r['name']}'),
      ];

  // ─────────────────────────────── Build

  @override
  Widget build(BuildContext context) {
    if (loading) return const AppCard(child: CpLoading());
    if (error != null) return CpError(error!.message, onRetry: _load);
    if (mode != _Mode.view) {
      return CpFormEditor(
        key: ValueKey('$mode$edKey$edForm'),
        c: c,
        dup: mode == _Mode.dup,
        source: edKey,
        formId: edForm,
        name: edName ?? '',
        sendOpts: edOpts,
        sending: _sending,
        onCancel: () => setState(() => mode = _Mode.view),
        onDone: (k) => _afterChange(select: k),
      );
    }
    return LayoutBuilder(builder: (context, b) {
      final list = _list(context);
      final card = _card(context);
      if (b.maxWidth < 760) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: context.isPhone ? 14 : 16, children: [list, card]);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [SizedBox(width: 340, child: list), Expanded(child: card)]);
    });
  }

  // Left card: Forms · N forms for Riya · copies of the master forms · Send a form.
  Widget _list(BuildContext context) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHeader(
            'Forms',
            sub: '${rows.length} ${rows.length == 1 ? 'form' : 'forms'} for ${c.first} · copies of the master forms',
            action: AppButton('Send a form', icon: AppIcons.plus, size: BtnSize.sm, onPressed: _send),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: rows.isEmpty
                ? EmptyState('No forms yet', sub: 'Send ${c.first} a check-in, survey or waiver.')
                : Column(children: [for (final r in rows) _listRow(r)]),
          ),
        ]),
      );

  Widget _listRow(Map r) {
    final on = r['key'] == sel;
    return Hover(
      onTap: () => _pick('${r['key']}'),
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: on ? AppColors.accentSoft : (h ? AppColors.hover : null), borderRadius: AppRadius.all(AppRadius.item)),
        child: Row(spacing: 12, children: [
          cpIcon(r['icon'] == 'calendar' ? AppIcons.calendar : AppIcons.clipboard, size: 30),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle),
              Text('${r['sub']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.rowSub),
            ]),
          ),
          AppBadge('${r['status_label']}', tone: _tone('${r['status']}')),
        ]),
      ),
    );
  }

  Tone _tone(String s) => switch (s) {
        'done' || 'signed' => Tone.ok,
        'waiting' => Tone.warn,
        'scheduled' => Tone.info,
        'stopped' => Tone.bad,
        _ => Tone.neutral,
      };

  // Right card.
  Widget _card(BuildContext context) {
    final r = _row;
    if (r == null) return AppCard(child: EmptyState('Pick a form', sub: 'Its answers or questions show here.'));
    if (r['key'] == 'onboarding') return _onboarding(r);
    if (detailLoading && detail == null) return const AppCard(child: CpLoading());
    if (detailError != null) return CpError(detailError!.message, onRetry: _loadDetail);
    final d = detail;
    if (d == null || d['key'] != r['key']) return const AppCard(child: CpLoading());
    if (d['sections'] != null) {
      final sections = [
        for (final s in d['sections'] as List)
          ('${s['title']}', [for (final x in (s['rows'] as List? ?? const [])) ('${x['q']}', '${x['a']}')]),
      ];
      return _answers('${d['name']}', '${d['cap']}', sections);
    }
    return _questions(context, d);
  }

  // `.cp-qsec` / `.cp-qa`: OVER line, then question (grey) and answer (bold); stacked on a phone.
  Widget _answers(String title, String cap, List<(String, List<(String, String)>)> sections) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHeader(title, sub: cap, action: CpLink('Print', onTap: () => _print(title, cap, sections))),
          for (final (t, qa) in sections)
            Padding(
              padding: EdgeInsets.fromLTRB(context.isPhone ? 16 : 20, 4, context.isPhone ? 16 : 20, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(padding: const EdgeInsets.only(top: 6, bottom: 4), child: Text(t.toUpperCase(), style: AppText.over)),
                if (qa.isEmpty) Text('No answers.', style: AppText.sub),
                for (final (i, (q, a)) in qa.indexed) _qa(q, a, last: i == qa.length - 1),
              ]),
            ),
        ]),
      );

  Widget _qa(String q, String a, {required bool last}) {
    final qs = AppText.s(13.5, W.w6, color: AppColors.muted), as = AppText.s(13.5, W.w7);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.line))),
      child: context.isPhone
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [Text(q, style: qs), Text(a, style: as)])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
              Expanded(flex: 10, child: Text(q, style: qs)),
              Expanded(flex: 12, child: Text(a, style: as)),
            ]),
    );
  }

  /// The onboarding questionnaire from her setup answers (same labels as the client app's setup screens).
  Widget _onboarding(Map r) {
    final on = c.onboarding;
    Map m(String k) => (on[k] as Map?) ?? const {};
    final goal = m('goal'), about = m('about'), sched = m('schedule'), health = m('health'), food = m('food');
    String pick(List<(String, String, String)> xs, Object? v, {bool third = false}) {
      final x = xs.where((e) => e.$1 == '$v').firstOrNull;
      return x == null ? '—' : (third ? x.$3 : x.$2);
    }

    String pick2(List<(String, String)> xs, Object? v) => xs.where((e) => e.$1 == '$v').firstOrNull?.$2 ?? '—';
    String list(List<(String, String)> xs, Object? vs) {
      final l = [for (final v in (vs as List? ?? const [])) if (v != 'none') pick2(xs, v)];
      return l.isEmpty ? 'None' : l.join(', ');
    }

    String num1(Object? v, String unit, {bool keep = false}) => v == null ? '—' : cpKg(v, unit: unit, keep: keep);
    final notes = '${c.profile['health_notes'] ?? health['notes'] ?? ''}'.trim();
    final injuries = list(SetupState.injuries, health['injuries']);
    final wake = SetupState.wakes.where((w) => w.$1 == '${sched['wake_time']}').firstOrNull?.$2 ?? '${sched['wake_time'] ?? '—'}';
    final days = (sched['days'] as List?)?.length;
    final activity = SetupState.activities.where((a) => a.$1 == '${health['activity']}').firstOrNull;
    final diet = SetupState.diets.where((d) => d.$1 == '${food['diet']}').firstOrNull?.$2 ?? '—';
    final sections = <(String, List<(String, String)>)>[
      if (goal.isNotEmpty)
        ('Goal', [
          ('Main goal', SetupState.goals.where((g) => g.$1 == '${goal['goal']}').firstOrNull?.$2 ?? '—'),
          ('Training experience', pick(SetupState.levels, goal['level'], third: true)),
        ]),
      if (about.isNotEmpty || sched.isNotEmpty)
        ('Body and lifestyle', [
          if (about['age'] != null) ('Age', '${about['age']}'),
          ('Height', num1(about['height_cm'], 'cm')),
          ('Weight', num1(about['weight_kg'], 'kg', keep: true)),
          ('Goal weight', num1(about['target_weight_kg'], 'kg')),
          ('Where do you train?', pick(SetupState.places, about['place'])),
          if (days != null) ('Days a week', '$days'),
          if (sched['session_min'] != null) ('Session length', '${sched['session_min']} min'),
        ]),
      if (health.isNotEmpty)
        ('Health', [
          ('Injuries or pain', notes.isNotEmpty ? notes.split('\n').first : injuries),
          ('Health conditions', list(SetupState.conditionOptions, health['conditions'])),
          ('Doctor clearance to exercise', health['doctor_ok'] == true ? 'Yes' : (health['doctor_ok'] == false ? 'No' : '—')),
          ('Daily activity', activity == null ? '—' : '${activity.$2} (${activity.$3.split(',').first.toLowerCase()})'),
          ('Wake-up time', wake),
        ]),
      if (food.isNotEmpty)
        ('Food', [
          ('Food preference', diet),
          if (food['meals_per_day'] != null) ('Meals a day', '${food['meals_per_day']}'),
          ('Foods to avoid', list(SetupState.avoids, food['avoid'])),
          if (food['home_cooked'] != null) ('Mostly home-cooked food', food['home_cooked'] == true ? 'Yes' : 'No'),
        ]),
    ];
    final filled = cpParse(r['filled_at']);
    final cap = filled == null
        ? '${c.first} has not finished it yet · ${r['sub']}'
        : 'Filled by ${c.first} on ${DateFormat('d MMM yyyy').format(filled)} · edits change ${cpHer(c)} profile too';
    return _answers('Onboarding questionnaire', cap, sections);
  }

  // A form she gets (waiting / recurring / scheduled): badges, caption, Edit for Riya + ⋯, the questions.
  Widget _questions(BuildContext context, Map d) {
    final first = c.first;
    final actions = [for (final a in (d['actions'] as List? ?? const [])) '$a'];
    final phone = context.isPhone;
    final qs = (d['questions'] as List? ?? const []);
    final edit = actions.contains('edit') ? AppButton('Edit for $first', icon: AppIcons.edit, onPressed: () => _edit(dup: false)) : null;
    final more = Builder(
      builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'More actions', fill: true, onPressed: () => showAppMenu(b, [
            if (actions.contains('duplicate')) MenuEntry('Duplicate and edit', icon: AppIcons.copy, onTap: () => _edit(dup: true)),
            if (actions.contains('send_now')) MenuEntry('Send now', icon: AppIcons.send, onTap: () => _act('send_now')),
            if (actions.contains('reset')) MenuEntry('Reset to master', icon: AppIcons.reset, onTap: () => _act('reset')),
            if (actions.contains('start')) MenuEntry('Start sending again', icon: AppIcons.restart, onTap: () => _act('start')),
            if (actions.contains('stop')) MenuEntry('Stop sending', icon: AppIcons.stop, danger: true, onTap: () => _act('stop')),
          ], width: 230)),
    );
    final title = Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text('${d['name']}', style: AppText.s(15.5, W.w7, ls: -0.15)),
      AppBadge('${d['status_label']}', tone: _tone('${d['status']}')),
      if (d['edited'] == true) AppBadge('Edited for $first', tone: Tone.info, plain: true),
    ]);
    final head = Padding(
      padding: EdgeInsets.fromLTRB(phone ? 16 : 20, 16, phone ? 16 : 20, 8),
      child: phone
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [title, Text('${d['cap']}', style: AppText.cap)]),
              Row(spacing: 8, children: [if (edit != null) Expanded(child: edit), more]),
            ])
          : Row(spacing: 12, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [title, Text('${d['cap']}', style: AppText.cap)])),
              ?edit,
              more,
            ]),
    );
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        if (d['waiting'] != null)
          Padding(
            padding: EdgeInsets.fromLTRB(phone ? 16 : 20, 4, phone ? 16 : 20, 8),
            child: Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${d['waiting']}', style: AppText.s(13, W.w5, color: AppColors.muted)),
              AppButton('Remind again', icon: AppIcons.bell, size: BtnSize.sm, onPressed: () => _act('remind')),
            ]),
          ),
        if (d['kind'] == 'weekly')
          Padding(
            padding: EdgeInsets.fromLTRB(phone ? 16 : 20, 0, phone ? 16 : 20, 4),
            child: Align(alignment: Alignment.centerLeft, child: CpLink('Open answers in Logs', onTap: () => c.setTab('logs', log: 'weekly'))),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(phone ? 16 : 20, 0, phone ? 16 : 20, 10),
          child: qs.isEmpty
              ? Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('This form has no questions.', style: AppText.sub))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final (i, q) in qs.indexed)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(border: i == qs.length - 1 ? null : const Border(bottom: BorderSide(color: AppColors.line))),
                      child: Row(spacing: 10, children: [
                        cpChangeDot(q['changed'] == true),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                            Text('${q['text']}', style: AppText.s(13.5, W.w6)),
                            if ('${q['change'] ?? ''}'.isNotEmpty) Text('${q['change']}', style: AppText.cap),
                          ]),
                        ),
                        Text('${q['type_label']}', style: AppText.cap),
                        if (q['required'] == true) const AppBadge('Required', plain: true),
                      ]),
                    ),
                ]),
        ),
      ]),
    );
  }
}
