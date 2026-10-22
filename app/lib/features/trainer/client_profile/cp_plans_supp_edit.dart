import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/select.dart';
import '../../../core/widgets/tooltip.dart';
import 'cp_common.dart';
import 'cp_model.dart';
import 'cp_plans_parts.dart';

/// Supplement plan editor for one client (`pe.supp`, board `TrainerClientProfile`): `Edit X for Y`. The first save
/// makes Y's own copy (`clients/<id>/supplement-plans/<a>/items/`); the master and other clients stay the same.
/// Table: Supplement · Dose · When · How to take · Stock at home · Remove (phone: one card per supplement),
/// `Add supplement`, `Reset to master` when Y already has a copy.
class SupplementEditor extends StatefulWidget {
  const SupplementEditor({super.key, required this.c, required this.a, required this.onClose});
  final CpController c;

  /// The assignment row of `clients/<id>/supplement-plans/` (`current`).
  final Map a;

  /// [saved] true: reload the Plans tab.
  final void Function(bool saved) onClose;
  @override
  State<SupplementEditor> createState() => _SupplementEditorState();
}

const _timings = [
  ('breakfast', 'Breakfast'),
  ('morning', 'Morning'),
  ('pre_workout', 'Pre-workout'),
  ('post_workout', 'Post-workout'),
  ('any', 'Any time'),
  ('night', 'Night'),
  ('before_bed', 'Before bed'),
];

String _timingLabel(String k) => _timings.firstWhere((t) => t.$1 == k, orElse: () => _timings[4]).$2;

class _SupplementEditorState extends State<SupplementEditor> {
  CpController get c => widget.c;
  Map get a => widget.a;
  String get first => c.first;

  late final List<Map> rows = [
    for (final it in (a['items'] as List? ?? const []).cast<Map>())
      {
        ...jsonDecode(jsonEncode(it)) as Map,
        'stock_text': it['stock'] == null ? '' : '${it['stock']['quantity']} ${it['stock']['unit']}',
      },
  ];

  /// The library plan, to show what differs from it (blue dot).
  List<Map>? master;
  List<Map> quick = const [];
  bool dirty = false, busy = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    Services.api.get<Map>('supplement-plans/${a['plan']}/').then((p) {
      if (mounted) setState(() => master = [for (final x in (p['items'] as List? ?? const [])) x as Map]);
    }).catchError((_) {});
    Services.api.get<List>('supplement-plans/quick-add/').then((q) {
      if (mounted) setState(() => quick = [for (final x in q) x as Map]);
    }).catchError((_) {});
  }

  void _change(VoidCallback f) => setState(() {
        f();
        dirty = true;
      });

  Map? _masterOf(Map r) {
    final n = '${r['name']}'.trim().toLowerCase();
    return master?.where((m) => '${m['name']}'.trim().toLowerCase() == n).firstOrNull;
  }

  bool _changed(Map r) {
    if (master == null) return false;
    final m = _masterOf(r);
    if (m == null) return true;
    return '${m['dose']}' != '${r['dose']}' || '${m['timing']}' != '${r['timing']}' || '${m['how'] ?? ''}' != '${r['how'] ?? ''}';
  }

  int get _nChanges {
    if (master == null) return 0;
    final names = {for (final r in rows) '${r['name']}'.trim().toLowerCase()};
    return rows.where(_changed).length + master!.where((m) => !names.contains('${m['name']}'.trim().toLowerCase())).length;
  }

  /// "12 scoops" → {quantity: 12, unit: scoops}; empty → null; anything else → false (not a number).
  Object? _stock(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final m = RegExp(r'^(\d+)\s*(.*)$').firstMatch(t);
    if (m == null) return false;
    return {'quantity': int.parse(m[1]!), 'unit': m[2]!.trim().isEmpty ? 'tablets' : m[2]!.trim()};
  }

  Future<void> _save() async {
    for (final r in rows) {
      if ('${r['name']}'.trim().length < 2) return showToast(context, 'Check the plan', sub: 'Enter a name for every supplement.', kind: ToastKind.info);
      if ('${r['dose']}'.trim().isEmpty) return showToast(context, 'Check the plan', sub: 'Enter the dose for ${r['name']}, e.g. 1 tablet.', kind: ToastKind.info);
      if (_stock('${r['stock_text'] ?? ''}') == false) return showToast(context, 'Check the plan', sub: 'Stock for ${r['name']} starts with a number, e.g. 12 scoops.', kind: ToastKind.info);
    }
    if (!dirty) return widget.onClose(false);
    setState(() => busy = true);
    try {
      await Services.api.put('clients/${c.id}/supplement-plans/${a['id']}/items/', {
        'items': [
          for (final r in rows)
            {
              if (r['id'] != null) 'id': r['id'],
              'name': '${r['name']}'.trim(),
              'dose': '${r['dose']}'.trim(),
              'how': '${r['how'] ?? ''}'.trim(),
              'timing': r['timing'] ?? 'any',
              'days': r['days'] ?? const [],
              'with_food': r['with_food'] == true,
              'stock': _stock('${r['stock_text'] ?? ''}'),
            },
        ],
      });
      if (!mounted) return;
      showToast(context, 'Saved for $first', sub: '${a['plan_name']} · the master stays the same', kind: ToastKind.ok);
      widget.onClose(true);
    } on ApiError catch (e) {
      if (mounted) {
        setState(() => busy = false);
        showToast(context, 'Could not save the supplements', sub: e.message, kind: ToastKind.info);
      }
    }
  }

  Future<void> _cancel() async {
    if (dirty) {
      final ok = await confirmAction(context, title: 'Leave without saving?', body: 'Your changes for $first are lost.', confirm: 'Leave', danger: true);
      if (!ok) return;
    }
    widget.onClose(false);
  }

  Future<void> _reset() async {
    final ok = await confirmAction(context,
        title: 'Reset to master?',
        body: 'Every change made for $first in ${a['plan_name']} goes away. $first takes the master supplements "${a['master_name'] ?? a['plan_name']}" again. Ticks stay.',
        confirm: 'Reset to master',
        danger: true,
        icon: AppIcons.reset);
    if (!ok || !mounted) return;
    try {
      await Services.api.post('clients/${c.id}/supplement-plans/${a['id']}/reset/', const {});
      if (!mounted) return;
      showToast(context, '$first follows the master again', sub: '${a['master_name'] ?? a['plan_name']}', kind: ToastKind.ok);
      widget.onClose(true);
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not reset the supplements', sub: e.message, kind: ToastKind.info);
    }
  }

  void _add(Map? q) => _change(() {
        rows.add({
          'id': null,
          'new': true,
          'name': q?['name'] ?? '',
          'dose': q?['dose'] ?? '',
          'how': '',
          'timing': q?['timing'] ?? 'any',
          'days': const [],
          'with_food': q?['with_food'] == true,
          'stock_text': '',
        });
        _gen++;
      });

  void _remove(int i) {
    final r = rows[i];
    _change(() {
      rows.removeAt(i);
      _gen++;
    });
    showToast(context, 'Removed for $first', sub: '${r['name']}'.trim().isEmpty ? 'New supplement' : '${r['name']}', kind: ToastKind.ok, action: 'Undo', onAction: () {
      if (!mounted) return;
      setState(() {
        rows.insert(i.clamp(0, rows.length), r);
        _gen++;
      });
    });
  }

  // ─────────────────────────────── build

  @override
  Widget build(BuildContext context) {
    final n = _nChanges;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      PlanEditBar(onBack: _cancel, onCancel: _cancel, onReset: a['custom'] == true ? _reset : null, save: 'Save for $first', busy: busy, onSave: _save),
      Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
          Text('Edit ${a['plan_name']} for $first', style: AppText.s(17, W.w7, ls: -.2)),
          AppTooltip(
            message: 'Only $first’s copy changes. The master plan and other clients stay the same. Changed items get a blue dot.',
            child: const Padding(padding: EdgeInsets.all(3), child: AppIcon(AppIcons.info, size: 16, color: AppColors.muted)),
          ),
        ]),
        Text('Since ${cpDm(a['start_date'])} · ${n == 0 ? 'same as the master' : '$n change${n == 1 ? '' : 's'} from the master'}', style: AppText.cap),
      ]),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (rows.isEmpty) const PdEmptyLine('No supplements yet. Add the first one.'),
          // Under the table's 760 px (phone, tablet beside the side nav): one block per supplement, as `.pf-cards`.
          if (rows.isNotEmpty) LayoutBuilder(builder: (_, k) => k.maxWidth < 760 ? _cards(k.maxWidth >= 520) : _table()),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(children: [Builder(builder: (b) => _AddBtn('Add supplement', () => _addMenu(b)))]),
          ),
        ]),
      ),
    ]);
  }

  void _addMenu(BuildContext anchor) {
    final have = {for (final r in rows) '${r['name']}'.trim().toLowerCase()};
    showAppMenu(anchor, [
      for (final q in quick.where((q) => !have.contains('${q['name']}'.toLowerCase())))
        MenuEntry('${q['name']}', onTap: () => _add(q)),
      MenuEntry('Other supplement', icon: AppIcons.plus, onTap: () => _add(null)),
    ], width: 230, alignRight: false);
  }

  Widget _name(Map r) {
    final dot = _changed(r);
    return Row(spacing: 6, children: [
      if (dot) Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
      Expanded(
        child: r['new'] == true
            ? _Cell(key: ValueKey('n${rows.indexOf(r)}$_gen'), value: '${r['name']}', placeholder: 'Supplement name', onChanged: (v) => _change(() => r['name'] = v))
            : CutText('${r['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7)),
      ),
    ]);
  }

  Widget _dose(Map r, int i) => _Cell(key: ValueKey('d$i$_gen'), value: '${r['dose'] ?? ''}', placeholder: '1 tablet', onChanged: (v) => _change(() => r['dose'] = v));
  Widget _how(Map r, int i) => _Cell(key: ValueKey('h$i$_gen'), value: '${r['how'] ?? ''}', placeholder: 'With breakfast', onChanged: (v) => _change(() => r['how'] = v));
  Widget _stockCell(Map r, int i) => _Cell(key: ValueKey('s$i$_gen'), value: '${r['stock_text'] ?? ''}', placeholder: '12 scoops', onChanged: (v) => _change(() => r['stock_text'] = v));
  Widget _when(Map r) => AppSelect(_timingLabel('${r['timing'] ?? 'any'}'), entries: [
        for (final (k, l) in _timings) MenuEntry(l, selected: k == r['timing'], onTap: () => _change(() => r['timing'] = k)),
      ]);
  Widget _del(int i) => AppIconButton(AppIcons.trash, tooltip: 'Remove', ghost: true, small: true, onPressed: () => _remove(i));

  /// Desktop: `.cp-edt` table.
  Widget _table() {
    Widget head(String t) => Text(t, style: AppText.s(12, W.w7, color: AppColors.muted));
    Widget line(List<Widget> cells, {bool header = false}) => Container(
          padding: EdgeInsets.fromLTRB(16, header ? 10 : 6, 8, header ? 10 : 6),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
          child: Row(spacing: 12, children: [
            Expanded(flex: 16, child: cells[0]),
            SizedBox(width: 150, child: cells[1]),
            SizedBox(width: 130, child: cells[2]),
            Expanded(flex: 20, child: cells[3]),
            SizedBox(width: 100, child: cells[4]),
            SizedBox(width: 32, child: cells[5]),
          ]),
        );
    final table = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      line([head('Supplement'), head('Dose'), head('When'), head('How to take'), head('Stock at home'), const SizedBox()], header: true),
      for (final (i, r) in rows.indexed) line([_name(r), _dose(r, i), _when(r), _how(r, i), _stockCell(r, i), _del(i)]),
    ]);
    return table;
  }

  /// Narrow: `.pf-cards`, one block per supplement with its labelled fields ([wide]: dose, when and stock on one line).
  Widget _cards(bool wide) {
    Widget f(String l, Widget w) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [Text(l, style: AppText.s(11.5, W.w6, color: AppColors.muted)), w]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, r) in rows.indexed)
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
            Row(children: [Expanded(child: _name(r)), _del(i)]),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                if (wide)
                  Row(spacing: 8, children: [Expanded(child: f('Dose', _dose(r, i))), Expanded(child: f('When', _when(r))), Expanded(child: f('Stock at home', _stockCell(r, i)))])
                else
                  Row(spacing: 8, children: [Expanded(child: f('Dose', _dose(r, i))), Expanded(child: f('When', _when(r)))]),
                f('How to take', _how(r, i)),
                if (!wide) f('Stock at home', _stockCell(r, i)),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

class PdEmptyLine extends StatelessWidget {
  const PdEmptyLine(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(text, style: AppText.s(13, W.w5, color: AppColors.muted)),
      );
}

/// `.cp-ci`: a small input box that keeps its own text and reports each change.
class _Cell extends StatefulWidget {
  const _Cell({super.key, required this.value, required this.onChanged, this.placeholder = ''});
  final String value, placeholder;
  final ValueChanged<String> onChanged;
  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  late final t = TextEditingController(text: widget.value);
  @override
  void dispose() {
    t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppTextField(controller: t, placeholder: widget.placeholder, height: 36, fontSize: 13, onChanged: widget.onChanged);
}

/// `.cp-add`: dashed "+ Add supplement".
class _AddBtn extends StatelessWidget {
  const _AddBtn(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: h ? AppColors.accentSoft : null,
            borderRadius: AppRadius.all(AppRadius.input),
            border: Border.all(color: h ? AppColors.changedLine : AppColors.line2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
            const AppIcon(AppIcons.plus, size: 14, color: AppColors.accentText),
            Text(label, style: AppText.s(12.5, W.w7, color: AppColors.accentText)),
          ]),
        ),
      );
}
