import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../app/services.dart';
import '../../../app/shell/page.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tooltip.dart';
import '../forms/forms_common.dart' show FmCheck;
import 'automations_common.dart';

/// Admin → Automations (boards `Automations` + `AutomationsMobile`, D-51): forms, messages and tasks that go out
/// by themselves. Four counts; one row per automation with its On / Off switch, trigger, who it is for, the steps
/// as chips (the rest in "+N more"), clients running and finished, last change and ⋯ (Edit, Duplicate, Delete).
/// New automation opens the starters; Use this opens the builder.
class AutomationsScreen extends StatefulWidget {
  const AutomationsScreen({super.key});
  @override
  State<AutomationsScreen> createState() => _AutomationsScreenState();
}

class _AutomationsScreenState extends State<AutomationsScreen> {
  List<Map> rows = [];
  Map stats = {};
  bool loading = true;
  ApiError? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await Future.wait([Services.api.get<List>('automations/'), Services.api.get<Map>('automations/stats/')]);
      if (!mounted) return;
      setState(() {
        rows = [for (final x in r[0] as List) x as Map];
        stats = r[1] as Map;
        error = null;
        loading = false;
      });
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = compactTop(context);
    return StaffPage(
      onRefresh: load,
      header: PageTop(
        title: 'Automations',
        sub: 'Forms, messages and tasks that go out by themselves when something happens.',
        actions: [
          if (Services.session.me?.role == Role.admin) AppButton('Message templates', icon: AppIcons.mail, iconOnly: compact, tooltip: 'Message templates', onPressed: () => context.go('/emails')),
          AppButton.primary('New automation', icon: AppIcons.plus, iconOnly: compact, tooltip: 'New automation', onPressed: _new),
        ],
      ),
      children: [
        if (error != null && rows.isEmpty)
          AppCard(child: EmptyState('Could not load automations', sub: error!.message, action: AppButton('Try again', onPressed: load)))
        else if (loading && rows.isEmpty)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)))
        else
          LayoutBuilder(builder: (context, box) {
            final narrow = box.maxWidth < 760;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: narrow ? 12 : 16, children: [
              _stats(narrow),
              AppCard(
                padding: EdgeInsets.zero,
                child: rows.isEmpty
                    ? EmptyState('No automations yet',
                        icon: AppIcons.bolt,
                        sub: 'Send forms, reminders and trainer tasks by themselves. Start from a ready-made one.',
                        action: AppButton.primary('New automation', icon: AppIcons.plus, onPressed: _new))
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (!narrow) _head(),
                        for (final (i, a) in rows.indexed) narrow ? _card(a, i == 0) : _row(a),
                      ]),
              ),
              _senderNote(narrow),
            ]);
          }),
      ],
    );
  }

  // ─────────────────────────────── Counts (`.au-stats`)

  Widget _stats(bool narrow) {
    final on = (stats['on'] as num?)?.toInt() ?? 0, total = (stats['total'] as num?)?.toInt() ?? rows.length;
    final msgs = (stats['messages_month'] as num?)?.toInt() ?? 0;
    final dp = stats['delivered_pct'], op = stats['opened_pct'];
    final open = (stats['tasks_open'] as num?)?.toInt() ?? 0;
    final cards = [
      (AppIcons.bolt, 1, 'Automations on', '$on of $total', total - on > 0 ? '${total - on} off or draft' : 'All of them are on'),
      (AppIcons.usersAlt, 0, 'Clients in a flow', '${stats['in_flow'] ?? 0}', 'Waiting for their next step'),
      (AppIcons.send, 2, 'Messages this month', '$msgs', msgs == 0 ? 'Nothing sent yet' : '${dp ?? 0}% delivered · ${op ?? 0}% opened'),
      (AppIcons.checkCircle, 3, 'Tasks for trainers', '${stats['tasks'] ?? 0}', open == 0 ? 'None open' : '$open still open'),
    ];
    Widget card((AppIconData, int, String, String, String) c) => AppCard(
          padding: EdgeInsets.symmetric(horizontal: narrow ? 14 : 16, vertical: narrow ? 12 : 13),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: narrow ? 6 : 8, children: [
            Row(spacing: 6, children: [
              AppIcon(c.$1, size: 15, color: AppColors.hbTones[c.$2].$2),
              Expanded(child: CutText(c.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.text2))),
            ]),
            if (narrow) ...[
              Text(c.$4, style: AppText.s(22, W.w8, h: 1, tabular: true)),
              CutText(c.$5, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w5, color: AppColors.muted)),
            ] else
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 8, children: [
                Text(c.$4, style: AppText.s(24, W.w8, h: 1, tabular: true)),
                Expanded(child: CutText(c.$5, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted))),
              ]),
          ]),
        );
    final per = narrow ? 2 : 4;
    return Column(spacing: 10, children: [
      for (var i = 0; i < cards.length; i += per)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: narrow ? 10 : 12, children: [
            for (final c in cards.skip(i).take(per)) Expanded(child: card(c)),
          ]),
        ),
    ]);
  }

  // ─────────────────────────────── Web list (`.au-row` grid)

  static const _gap = 12.0;

  /// Compact row (Gautam 2026-10-23: "congested"): switch | trigger | name + when/who | steps | clients | changed | ⋯.
  /// Running and finished share one "Clients" column, so the name and the steps get the room.
  Widget _cols({required List<Widget> cells}) => Row(children: [
        SizedBox(width: 40, child: cells[0]),
        const SizedBox(width: _gap),
        SizedBox(width: 34, child: cells[1]),
        const SizedBox(width: _gap),
        Expanded(flex: 11, child: ConstrainedBox(constraints: const BoxConstraints(minWidth: 200), child: cells[2])),
        const SizedBox(width: _gap * 1.5),
        Expanded(flex: 10, child: cells[3]),
        const SizedBox(width: _gap),
        SizedBox(width: 92, child: cells[4]),
        const SizedBox(width: _gap),
        SizedBox(width: 60, child: cells[5]),
        const SizedBox(width: 4),
        SizedBox(width: 32, child: cells[6]),
      ]);

  Widget _head() {
    Widget t(String s, {bool r = false}) => CutText(s.toUpperCase(), maxLines: 1, textAlign: r ? TextAlign.right : null, style: AppText.s(11, W.w7, color: AppColors.muted, ls: .45));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
      child: _cols(cells: [const SizedBox(), const SizedBox(), t('Automation'), t('Steps'), t('Clients', r: true), t('Changed', r: true), const SizedBox()]),
    );
  }

  List<AuStep> _steps(Map a) => [for (final s in (a['steps'] as List?) ?? const []) AuStep.fromJson(s as Map)];
  int _n(Map a, String k) => ((a['counts'] as Map?)?[k] as num?)?.toInt() ?? 0;

  Widget _row(Map a) {
    final dim = a['status'] != 'on';
    return Hover(
      onTap: () => _open(a),
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: h ? AppColors.tableHead : null, border: const Border(top: BorderSide(color: AppColors.line))),
        child: _cols(cells: [
          Align(alignment: Alignment.centerLeft, child: _switch(a)),
          AuTriggerTile('${a['trigger']}', tone: auListTone('${a['trigger']}')),
          _main(a, h, dim),
          _flow(a),
          _clients(a),
          Text(_changed(a['updated_at']), maxLines: 1, textAlign: TextAlign.right, style: AppText.s(12, W.w5, color: AppColors.muted)),
          _dots(a),
        ]),
      ),
    );
  }

  /// "20 Sep", or "Today".
  String _changed(Object? iso) {
    final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (d == null) return '—';
    final now = DateTime.now();
    if (DateUtils.isSameDay(d, now)) return 'Today';
    return DateFormat(d.year == now.year ? 'd MMM' : 'd MMM yy').format(d);
  }

  /// "3 running" over "12 finished".
  Widget _clients(Map a) => Column(crossAxisAlignment: CrossAxisAlignment.end, spacing: 1, children: [
        Text.rich(
            TextSpan(children: [
              TextSpan(text: '${_n(a, 'running')}', style: AppText.s(14, W.w7, tabular: true)),
              TextSpan(text: ' running', style: AppText.s(12, W.w5, color: AppColors.muted)),
            ]),
            maxLines: 1),
        Text('${_n(a, 'finished')} finished', maxLines: 1, style: AppText.s(11.5, W.w5, color: AppColors.muted, tabular: true)),
      ]);

  Widget _main(Map a, bool h, bool dim, {bool wrap = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
        if (wrap)
          Wrap(spacing: 8, runSpacing: 3, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${a['name']}', style: AppText.s(14.5, W.w7, color: h ? AppColors.accentText : (dim ? AppColors.text2 : AppColors.text), h: 1.3)),
            auBadge('${a['status']}'),
          ])
        else
          Row(spacing: 8, children: [
            Flexible(child: CutText('${a['name']}', maxLines: 1, style: AppText.s(14, W.w7, color: h ? AppColors.accentText : (dim ? AppColors.text2 : AppColors.text), h: 1.3))),
            auBadge('${a['status']}'),
          ]),
        CutText('${a['trigger_line']} · ${auAudience(a)}',
            maxLines: wrap ? 3 : 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.4)),
      ]);

  /// As many chips as fit on one line; the rest go into "+N more" (its tip lists them).
  Widget _flow(Map a) {
    final steps = _steps(a);
    return LayoutBuilder(builder: (_, box) {
      final lines = [for (final s in (a['steps'] as List?) ?? const []) '${(s as Map)['summary']}'];
      // a few px spare: the measured text can come out a hair narrower than the drawn chip (was 2.9 px over)
      final max = box.maxWidth - 6;
      var fit = 0;
      var used = 0.0;
      for (final (i, s) in steps.indexed) {
        final w = AuChip.widthOf(s.kind, s.chip) + (i > 0 ? 20 : 0);
        final left = steps.length - i - 1;
        final room = max - (left > 0 ? AuChip.widthOf(null, '+$left more') + 20 : 0);
        if (used + w > room) break;
        used += w;
        fit++;
      }
      return ClipRect(child: Row(children: [
        for (final (i, s) in steps.take(fit).indexed) ...[if (i > 0) auArrow, AuChip(s.kind, s.chip)],
        if (fit < steps.length) ...[
          if (fit > 0) auArrow,
          AppTooltip(message: lines.skip(fit).join('  ·  '), child: AuChip(null, '+${steps.length - fit} more')),
        ],
      ]));
    });
  }

  Widget _switch(Map a) => AppTooltip(
        message: a['status'] == 'draft' ? 'Finish it before turning it on' : 'Turn ${a['name']} on or off',
        child: AuSwitch(on: a['status'] == 'on', onTap: () => _toggle(a)),
      );

  Widget _dots(Map a) => Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'More options', small: true, ghost: true, onPressed: () => _menu(b, a)));

  // ─────────────────────────────── Phone / narrow cards (`AutomationsMobile`)

  Widget _card(Map a, bool first) {
    final steps = _steps(a);
    final lines = [for (final s in (a['steps'] as List?) ?? const []) '${(s as Map)['summary']}'];
    // the board keeps about 46 characters of chips; the rest go into "+N more"
    var fit = 0, w = 0;
    for (final (i, s) in steps.indexed) {
      final l = s.chip.length + 6;
      if (w + l > (steps.length - i > 1 ? 46 : 54)) break;
      w += l;
      fit++;
    }
    return Hover(
      onTap: () => _open(a),
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        decoration: BoxDecoration(color: h ? AppColors.tableHead : null, border: first ? null : const Border(top: BorderSide(color: AppColors.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: AuTriggerTile('${a['trigger']}', tone: auListTone('${a['trigger']}'))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
                Expanded(child: _main(a, h, a['status'] != 'on', wrap: true)),
                Padding(padding: const EdgeInsets.only(top: 5), child: _switch(a)),
                _dots(a),
              ]),
              Wrap(spacing: 0, runSpacing: 5, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final (i, s) in steps.take(fit).indexed) Row(mainAxisSize: MainAxisSize.min, children: [if (i > 0) auArrow, AuChip(s.kind, s.chip)]),
                if (fit < steps.length)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (fit > 0) auArrow,
                    AppTooltip(message: lines.skip(fit).join('  ·  '), child: AuChip(null, '+${steps.length - fit} more')),
                  ]),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  /// `.au-snd`: until the gym sets its own sender.
  Widget _senderNote(bool narrow) {
    final text = Text('Emails and WhatsApp go out from Train With Vimal until you set your own sender.', style: AppText.s(12.5, W.w6, color: AppColors.text2, h: 1.45));
    // Emails & alerts → Sender is admin only; a trainer with automation access reads the note without the link.
    final link = Services.session.me?.role == Role.admin
        ? AppButton('Sender settings', kind: BtnKind.text, onPressed: () => context.go('/emails?tab=sender'))
        : const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(10)),
      child: narrow
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                const Padding(padding: EdgeInsets.only(top: 1), child: AppIcon(AppIcons.doc, size: 16, color: AppColors.muted)),
                Expanded(child: text),
              ]),
              Padding(padding: const EdgeInsets.only(left: 12), child: link),
            ])
          : Row(spacing: 8, children: [const AppIcon(AppIcons.doc, size: 16, color: AppColors.muted), Expanded(child: text), link]),
    );
  }

  // ─────────────────────────────── Actions

  void _open(Map a) => context.go('/automations/${a['id']}');

  void _menu(BuildContext anchor, Map a) => showAppMenu(anchor, width: 220, [
        MenuEntry.header('${a['name']}'),
        MenuEntry('Edit', icon: AppIcons.edit, onTap: () => _open(a)),
        MenuEntry('Duplicate', icon: AppIcons.copy, onTap: () => _duplicate(a)),
        const MenuEntry.separator(),
        MenuEntry('Delete', icon: AppIcons.trash, danger: true, onTap: () => _delete(a)),
      ]);

  Future<T?> _call<T>(Future<T> Function() f, String failed) async {
    try {
      return await f();
    } on ApiError catch (e) {
      if (mounted) {
        final probs = e.fields['problems'];
        showToast(context, e.code == 'not_ready' ? 'Not ready to turn on' : failed, sub: probs != null && probs.isNotEmpty ? probs.first : e.message, kind: ToastKind.err);
      }
      return null;
    }
  }

  Future<void> _toggle(Map a) async {
    final name = '${a['name']}';
    if (a['status'] == 'draft') return showToast(context, 'Finish it before turning it on', sub: 'Open it and add what is missing');
    final turnOff = a['status'] == 'on';
    final r = await _call(() => Services.api.post<Map>('automations/${a['id']}/${turnOff ? 'turn-off' : 'turn-on'}/'), 'Could not change it');
    if (r == null || !mounted) return;
    load();
    showToast(context, turnOff ? '$name is off' : '$name is on',
        sub: turnOff ? 'No new runs will start' : 'It starts with the next trigger', action: 'Undo', onAction: () async {
      await _call(() => Services.api.post('automations/${a['id']}/${turnOff ? 'turn-on' : 'turn-off'}/'), 'Could not undo');
      load();
    });
  }

  Future<void> _duplicate(Map a) async {
    if (!await confirmDuplicate(context, '"${a['name']}"', body: 'The copy starts as a draft. The original stays as it is.')) return;
    final r = await _call(() => Services.api.post<Map>('automations/${a['id']}/duplicate/'), 'Could not duplicate it');
    if (r == null || !mounted) return;
    load();
    showToast(context, 'Automation duplicated', sub: 'Saved as a draft', action: 'Undo', onAction: () async {
      await _call(() => Services.api.delete('automations/${r['id']}/'), 'Could not undo');
      load();
    });
  }

  Future<void> _delete(Map a) async {
    final ok = await confirmAction(context,
        title: 'Delete this automation?',
        body: '${a['name']} stops for everyone in it now. Messages already sent stay sent.',
        confirm: 'Delete',
        danger: true,
        icon: AppIcons.trash);
    if (!ok || !mounted) return;
    final r = await _call(() async {
      await Services.api.delete('automations/${a['id']}/');
      return true;
    }, 'Could not delete it');
    if (r == null || !mounted) return;
    load();
    showToast(context, 'Automation deleted', sub: '${a['name']}', action: 'Undo', onAction: () async {
      await _call(() => Services.api.post('automations/${a['id']}/restore/'), 'Could not undo');
      load();
    });
  }

  // ─────────────────────────────── New automation (starters)

  Future<void> _new() async {
    Map? cat;
    try {
      cat = await Services.api.get<Map>('automations/catalog/');
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not open the starters', sub: e.message, kind: ToastKind.err);
      return;
    }
    if (!mounted) return;
    final starters = [for (final s in (cat['starters'] as List?) ?? const []) s as Map];
    var pick = starters.isEmpty ? 'blank' : '${starters.first['key']}';
    final go = await showAppModal<String>(
      context,
      title: 'New automation',
      body: 'Start from a ready-made automation or from scratch.',
      icon: AppIcons.bolt,
      width: 600,
      content: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Widget option(String key, String trigger, String name, String note, String? meta, {bool blank = false}) => Hover(
                onTap: () => set(() => pick = key),
                builder: (_, h, _) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
                  decoration: BoxDecoration(border: key == (starters.isEmpty ? 'blank' : '${starters.first['key']}') ? null : const Border(top: BorderSide(color: AppColors.line))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
                    Padding(padding: const EdgeInsets.only(top: 6), child: FmCheck(on: pick == key)),
                    blank
                        ? IconTile(AppIcons.plus, size: 30, bg: AppColors.hbTones[1].$1, fg: AppColors.hbTones[1].$2, radius: 8, iconSize: 16)
                        : AuTriggerTile(trigger, size: 30, tone: AppColors.hbTones[0]),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                        Text(name, style: AppText.s(13.5, W.w7, color: h ? AppColors.accentText : AppColors.text)),
                        Text(note, style: AppText.s(12.5, W.w5, color: AppColors.text2, h: 1.45)),
                        if (meta != null) Text(meta, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
                      ]),
                    ),
                  ]),
                ),
              );
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final s in starters) option('${s['key']}', '${s['trigger']}', '${s['name']}', '${s['line']}', '${s['trigger_line']} · ${s['step_count']} steps'),
            option('blank', '', 'Start blank', 'Choose the trigger and add the steps yourself.', null, blank: true),
          ]);
        },
      ),
      actions: (ctx) => [
        if (!ctx.isPhone) AppButton('Cancel', onPressed: () => Navigator.of(ctx).pop()),
        AppButton.primary('Use this', trailingIcon: AppIcons.chevronRight, expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop(pick)),
      ],
    );
    if (go == null || !mounted) return;
    context.go(go == 'blank' ? '/automations/new' : '/automations/new?starter=$go');
  }
}
