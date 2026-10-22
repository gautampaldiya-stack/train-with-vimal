import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../lib_common.dart';
import 'habits_screen.dart';
import 'hb_common.dart';

/// Supplement plan editor (`.hb-ed` on the Supplements tab): items with dose and timing (a table, rows on a
/// narrow card), quick add, Custom, note to client and the save bar.
class SuppEditorCard extends StatefulWidget {
  const SuppEditorCard({super.key, required this.c, required this.onMenu, this.onAssign});
  final HbCtl c;
  final void Function(BuildContext anchor) onMenu;
  final VoidCallback? onAssign;
  @override
  State<SuppEditorCard> createState() => _SuppEditorCardState();
}

class _SuppEditorCardState extends State<SuppEditorCard> {
  HbCtl get c => widget.c;
  Map get d => c.sd!;
  late final note = TextEditingController(text: '${d['note'] ?? ''}');

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  List get _items => d['items'] as List;

  Future<void> _edit(int? i) async {
    final it = await showSuppItem(context, i == null ? null : _items[i] as Map);
    if (it == null || !mounted) return;
    c.setS((x) {
      if (i == null) {
        (x['items'] as List).add(it);
      } else {
        (x['items'] as List)[i] = it;
      }
    });
    showToast(context, i == null ? 'Added ${it['name']}' : 'Updated', sub: '${it['dose']} · ${timingLabel(it['timing'])}');
  }

  void _remove(int i) {
    final before = HbCtl.copy(d)['items'];
    final it = _items[i] as Map;
    c.setS((x) => (x['items'] as List).removeAt(i));
    showToast(context, 'Removed', sub: '${it['name']}', action: 'Undo', onAction: () {
      if (c.sd != null) c.setS((x) => x['items'] = before);
    });
  }

  void _quick(Map q) {
    c.setS((x) => (x['items'] as List).add({
          'name': q['name'],
          'dose': q['dose'] ?? '1 serving',
          'how': '',
          'timing': q['timing'] ?? 'any',
          'days': <int>[],
          'with_food': q['with_food'] == true,
        }));
    showToast(context, 'Added ${q['name']}', sub: 'Tap the row to set dose and timing');
  }

  void _menu(BuildContext anchor, int i) => showAppMenu(anchor, width: 220, [
        MenuEntry('Edit dose and timing', icon: AppIcons.edit, onTap: () => _edit(i)),
        const MenuEntry.separator(),
        MenuEntry('Remove', icon: AppIcons.trash, danger: true, onTap: () => _remove(i)),
      ]);

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final can = c.canEditS;
    final n = (d['client_count'] as num?)?.toInt() ?? 0;
    final pad = phone ? 14.0 : 18.0;
    final have = {for (final i in _items) '${(i as Map)['name']}'.toLowerCase()};
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HbEditorHead(
          icon: AppIcons.pill,
          tone: AppColors.hbTones[suppTone],
          title: '${d['name']}',
          sub: '${plural(_items.length, 'supplement')} · ${n == 0 ? 'not assigned' : plural(n, 'client')}',
          actions: [
            if (widget.onAssign != null) AppButton('Assign', icon: AppIcons.clients, size: BtnSize.sm, onPressed: widget.onAssign),
            if (c.canNewS) Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'Plan options', fill: true, onPressed: () => widget.onMenu(b))),
          ],
        ),
        if (_items.isEmpty)
          Container(
            margin: EdgeInsets.fromLTRB(pad, 16, pad, 0),
            padding: const EdgeInsets.all(18),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.tableHead, borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.line)),
            child: Text('No supplements yet. Use quick add below.', textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)),
          )
        else
          LayoutBuilder(builder: (context, b) => b.maxWidth < 480 ? _rows(can) : _table(can)),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 16, pad, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
            if (can)
              hbField(
                'Quick add from library',
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final q in c.quick) _QuickChip('${q['name']}', done: have.contains('${q['name']}'.toLowerCase()), onTap: () => _quick(q)),
                  _QuickChip('Custom', custom: true, onTap: () => _edit(null)),
                ]),
              ),
            hbField('Note to client',
                AppTextField(controller: note, enabled: can, minLines: 2, maxLines: 4, placeholder: 'e.g. Take creatine every day, rest days too.', formatters: [LengthLimitingTextInputFormatter(300)], onChanged: (v) => c.setS((x) => x['note'] = v))),
          ]),
        ),
        HbSaveBar(dirty: c.sDirty, saving: c.saving, canEdit: can, canCopy: c.canNewS, onDiscard: c.discardS, onSave: () => c.saveS(context)),
      ]),
    );
  }

  Widget _foodLine(Map it) => Text(it['with_food'] == true ? 'With food' : 'Empty stomach is fine', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted));

  Widget _dots(int i) => Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'Supplement options', small: true, ghost: true, fill: true, onPressed: () => _menu(b, i)));

  Widget _when(Map it) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
        _TimingPill(timingLabel(it['timing'])),
        Text(suppDays(it['days']), style: AppText.s(12, W.w6, color: AppColors.muted)),
      ]);

  /// `.tbl.hb-st`: Supplement · Dose · When · ⋯; a row opens Edit dose and timing.
  Widget _table(bool can) {
    Widget head(String t) => Text(t, style: AppText.s(12, W.w7, color: AppColors.muted));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(color: AppColors.tableHead, border: Border(bottom: BorderSide(color: AppColors.line))),
        child: Row(children: [Expanded(child: head('Supplement')), SizedBox(width: 110, child: head('Dose')), SizedBox(width: 130, child: head('When')), const SizedBox(width: 36)]),
      ),
      for (final (i, x) in _items.indexed)
        Hover(
          onTap: can ? () => _edit(i) : null,
          builder: (_, h, _) {
            final it = x as Map;
            return Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
              decoration: BoxDecoration(color: h ? AppColors.tableHead : null, border: const Border(bottom: BorderSide(color: AppColors.line))),
              child: Row(children: [
                Expanded(
                  child: Row(spacing: 10, children: [
                    HbIcon(AppIcons.pill, AppColors.hbTones[suppTone], size: 30),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                        Text('${it['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7)),
                        _foodLine(it),
                      ]),
                    ),
                  ]),
                ),
                SizedBox(width: 110, child: Padding(padding: const EdgeInsets.only(right: 8), child: Text('${it['dose']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7)))),
                SizedBox(width: 130, child: _when(it)),
                SizedBox(width: 36, child: can ? _dots(i) : null),
              ]),
            );
          },
        ),
    ]);
  }

  /// Narrow card (phone sheet): one block per supplement.
  Widget _rows(bool can) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, x) in _items.indexed)
          Hover(
            onTap: can ? () => _edit(i) : null,
            builder: (_, h, _) {
              final it = x as Map;
              return Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                decoration: BoxDecoration(color: h ? AppColors.tableHead : null, border: const Border(bottom: BorderSide(color: AppColors.line))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
                  HbIcon(AppIcons.pill, AppColors.hbTones[suppTone], size: 30),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                      Text('${it['name']}', style: AppText.s(13.5, W.w7)),
                      _foodLine(it),
                      Text('${it['dose']}', style: AppText.s(13.5, W.w7)),
                      const SizedBox(height: 4),
                      Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        _TimingPill(timingLabel(it['timing'])),
                        Text(suppDays(it['days']), style: AppText.s(12, W.w6, color: AppColors.muted)),
                      ]),
                    ]),
                  ),
                  if (can) Padding(padding: const EdgeInsets.only(top: 12), child: _dots(i)),
                ]),
              );
            },
          ),
      ]);
}

/// `.hb-tm`: grey timing pill.
class _TimingPill extends StatelessWidget {
  const _TimingPill(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(6)),
        child: Center(widthFactor: 1, child: Text(text, style: AppText.s(12, W.w7, color: AppColors.text2))),
      );
}

/// `.hb-q`: dashed quick-add chip (+ name); already in the plan = faded; Custom = solid with a pen.
class _QuickChip extends StatelessWidget {
  const _QuickChip(this.label, {this.done = false, this.custom = false, required this.onTap});
  final String label;
  final bool done, custom;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: done ? .45 : 1,
        child: Hover(
          onTap: done ? null : onTap,
          builder: (_, h, _) => CustomPaint(
            painter: custom ? null : _DashBorder(h ? AppColors.accent : AppColors.line2),
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: h ? AppColors.hover : null,
                borderRadius: AppRadius.all(15),
                border: custom ? Border.all(color: h ? AppColors.accent : AppColors.line2) : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
                AppIcon(custom ? AppIcons.edit : AppIcons.plus, size: 13, color: h ? AppColors.accentText : AppColors.muted),
                Text(label, style: AppText.s(12.5, W.w6, color: h ? AppColors.accentText : AppColors.text2)),
              ]),
            ),
          ),
        ),
      );
}

class _DashBorder extends CustomPainter {
  _DashBorder(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(15)).deflate(.5));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 7) {
        canvas.drawPath(m.extractPath(d, (d + 4).clamp(0, m.length)), p);
      }
    }
  }

  @override
  bool shouldRepaint(_DashBorder o) => o.color != color;
}

/// Client sees: the plan grouped by timing, as the client app lists it, with the note under it.
class SuppPreviewCard extends StatelessWidget {
  const SuppPreviewCard({super.key, required this.c});
  final HbCtl c;
  @override
  Widget build(BuildContext context) {
    final items = c.items;
    final note = '${c.sd?['note'] ?? ''}'.trim();
    final groups = [
      for (final (k, l) in suppTimings)
        if (items.any((i) => i['timing'] == k)) (l, items.where((i) => i['timing'] == k).toList()),
    ];
    return HbSideCard(title: 'Client sees', children: [
      HbPhone(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(12), border: Border.all(color: AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            if (groups.isEmpty) Text('Nothing yet. Add a supplement.', style: AppText.s(13, W.w5, color: AppColors.muted)),
            for (final (label, list) in groups)
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
                Text(label.toUpperCase(), style: AppText.over),
                for (final i in list)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                    Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(borderRadius: AppRadius.all(5), border: Border.all(color: AppColors.line2, width: 1.5)),
                    ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                        Text('${i['name']}', style: AppText.s(13, W.w7)),
                        Text([i['dose'], if (i['with_food'] == true) 'with food', suppDays(i['days'])].join(' · '), style: AppText.s(11.5, W.w5, color: AppColors.muted)),
                      ]),
                    ),
                  ]),
              ]),
            if (note.isNotEmpty) Text(note, style: AppText.s(12, W.w5, color: AppColors.muted, h: 1.5)),
          ]),
        ),
      ),
    ]);
  }
}

/// Edit dose and timing / Custom supplement: name, dose, timing, days, Take with food. Gives back the item.
Future<Map?> showSuppItem(BuildContext context, Map? item) async {
  final isNew = item == null;
  final name = TextEditingController(text: '${item?['name'] ?? ''}');
  final dose = TextEditingController(text: '${item?['dose'] ?? ''}');
  final timing = ValueNotifier('${item?['timing'] ?? 'any'}');
  final d0 = [for (final x in (item?['days'] as List? ?? const [])) (x as num).toInt()];
  final days = ValueNotifier<Set<int>>(d0.isEmpty ? {0, 1, 2, 3, 4, 5, 6} : d0.toSet());
  final food = ValueNotifier(item?['with_food'] == true);
  final errs = ValueNotifier<Map<String, String>>({});
  final picks = [...suppPickTimings, if (!suppPickTimings.contains(timing.value)) timing.value];
  void save(BuildContext ctx) {
    final n = name.text.trim().replaceAll(RegExp(r'\s+'), ' '), ds = dose.text.trim();
    final e = <String, String>{
      if (n.length < 2) 'name': 'Enter the supplement name.',
      if (ds.isEmpty) 'dose': 'Enter the dose.',
    };
    if (e.isNotEmpty) {
      errs.value = e;
      return;
    }
    final dl = days.value.toList()..sort();
    Navigator.of(ctx).pop({
      ...?item,
      'name': n,
      'dose': ds,
      'how': item?['how'] ?? '',
      'timing': timing.value,
      'days': dl.length == 7 ? <int>[] : dl,
      'with_food': food.value,
    });
  }

  final r = await showAppModal<Map>(
    context,
    title: isNew ? 'Custom supplement' : '${item['name']}',
    body: 'Dose and timing',
    icon: AppIcons.pill,
    width: 500,
    content: (ctx) => ListenableBuilder(
      listenable: Listenable.merge([timing, days, food, errs]),
      builder: (ctx, _) {
        final e = errs.value;
        final nameF = hbField('Name', req: true, error: e['name'],
            AppTextField(controller: name, autofocus: isNew, placeholder: 'e.g. Glutamine', formatters: [LengthLimitingTextInputFormatter(80)], onChanged: (_) => errs.value = {}));
        final doseF = hbField('Dose', hint: 'e.g. 5 g, 1 tablet', error: e['dose'],
            AppTextField(controller: dose, placeholder: '5 g', formatters: [LengthLimitingTextInputFormatter(60)], onChanged: (_) => errs.value = {}, onSubmitted: (_) => save(ctx)));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [Expanded(child: nameF), Expanded(child: doseF)]),
          hbField('Timing', Wrap(spacing: 6, runSpacing: 6, children: [
            for (final k in picks) _DarkChip(timingLabel(k), on: timing.value == k, onTap: () => timing.value = k),
          ])),
          hbField('Days', hint: suppDays(days.value.toList()), HbDays(days: days.value, onTap: (i) {
            final s = {...days.value};
            if (s.contains(i)) {
              if (s.length > 1) s.remove(i);
            } else {
              s.add(i);
            }
            days.value = s;
          })),
          Hover(
            onTap: () => food.value = !food.value,
            builder: (_, _, _) => Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: AppToggle(value: food.value, onChanged: (v) => food.value = v)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text('Take with food', style: AppText.s(13.5, W.w7)),
                  Text('The client sees "with food" next to it', style: AppText.s(12, W.w5, color: AppColors.muted)),
                ]),
              ),
            ]),
          ),
        ]);
      },
    ),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      AppButton.primary(isNew ? 'Add supplement' : 'Update', icon: AppIcons.check, expand: ctx.isPhone, onPressed: () => save(ctx)),
    ],
  );
  disposeLater([name, dose, timing, days, food, errs]);
  return r;
}

/// `.nu-g` chip: picked = dark.
class _DarkChip extends StatelessWidget {
  const _DarkChip(this.label, {required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: on ? AppColors.text : (h ? AppColors.sub : AppColors.card),
            borderRadius: AppRadius.all(15),
            border: Border.all(color: on ? AppColors.text : AppColors.line2),
          ),
          child: Center(widthFactor: 1, child: Text(label, style: AppText.s(13, W.w6, color: on ? AppColors.white : AppColors.text))),
        ),
      );
}
