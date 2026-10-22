import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tabs.dart';
import '../../../core/widgets/tooltip.dart';
import '../lib_common.dart';
import 'habits_screen.dart';
import 'hb_common.dart';

/// Habit editor (`.hb-ed`): name, Tick / Counter, daily target and unit, frequency, icon, why it matters, and the
/// save bar. Text fields start again when the draft is replaced (the key carries `hRev`).
class HabitEditorCard extends StatefulWidget {
  const HabitEditorCard({super.key, required this.c, required this.onMenu});
  final HbCtl c;
  final void Function(BuildContext anchor) onMenu;
  @override
  State<HabitEditorCard> createState() => _HabitEditorCardState();
}

const _maxTarget = 100000;

class _HabitEditorCardState extends State<HabitEditorCard> {
  HbCtl get c => widget.c;
  Map get d => c.hd!;
  late final name = TextEditingController(text: '${d['name'] ?? ''}');
  late final unit = TextEditingController(text: '${d['unit'] ?? ''}');
  late final why = TextEditingController(text: '${d['why'] ?? ''}');
  late final target = TextEditingController(text: '${d['target'] ?? 8}');

  @override
  void dispose() {
    for (final x in [name, unit, why, target]) {
      x.dispose();
    }
    super.dispose();
  }

  int get _target => (d['target'] as num?)?.toInt() ?? 8;

  /// The board's step: 1 under 20, 5 under 100, 25 under 1,000, then 1,000.
  int get _step => _target >= 1000 ? 1000 : (_target >= 100 ? 25 : (_target >= 20 ? 5 : 1));

  void _setTarget(int v) {
    v = v.clamp(1, _maxTarget);
    target.text = '$v';
    c.setH((x) => x['target'] = v);
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final can = c.canEditH;
    final counter = d['kind'] == 'counter';
    final n = (d['client_count'] as num?)?.toInt() ?? 0;
    final freq = '${d['frequency'] ?? 'daily'}';
    final days = {for (final x in (d['days'] as List? ?? const [])) (x as num).toInt()};
    final pad = phone ? 14.0 : 18.0;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HbEditorHead(
          icon: habitIcon('${d['icon']}'),
          tone: habitTone('${d['icon']}'),
          title: '${d['name'] ?? ''}',
          sub: '${kindLabel(d)} · ${freqLabel(d)} · ${n == 0 ? 'not assigned' : plural(n, 'client')}',
          actions: [
            if (c.canNewH) Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'Habit options', fill: true, onPressed: () => widget.onMenu(b))),
          ],
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 16, pad, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
            hbField('Habit name', error: c.hErr['name'],
                AppTextField(controller: name, enabled: can, placeholder: 'e.g. Drink 3 L water', formatters: [LengthLimitingTextInputFormatter(80)], onChanged: (v) => c.setH((x) => x['name'] = v))),
            hbField('Type', _types(phone, can)),
            if (counter)
              _pair(
                phone,
                hbField('Daily target', error: c.hErr['target'], _TargetStep(controller: target, enabled: can, onLess: () => _setTarget(_target - _step), onMore: () => _setTarget(_target + _step), onTyped: (v) => c.setH((x) => x['target'] = v.clamp(1, _maxTarget)), atMin: _target <= 1, atMax: _target >= _maxTarget)),
                hbField('Unit', hint: 'Glasses, steps, min…', error: c.hErr['unit'],
                    AppTextField(controller: unit, enabled: can, placeholder: 'glasses', formatters: [LengthLimitingTextInputFormatter(20)], onChanged: (v) => c.setH((x) => x['unit'] = v))),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(8)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                  const Padding(padding: EdgeInsets.only(top: 1), child: AppIcon(AppIcons.info, size: 16, color: AppColors.muted)),
                  Expanded(child: Text('The client gets a simple tick: "Done today?". Streaks are counted for you.', style: AppText.s(12.5, W.w5, color: AppColors.text2, h: 1.45))),
                ]),
              ),
            hbField(
              'Frequency',
              error: c.hErr['days'] ?? c.hErr['times_per_week'],
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                // Tabs as wide as their labels (Gautam, 22 Oct), not the whole card.
                Align(
                  alignment: Alignment.centerLeft,
                  child: IgnorePointer(
                    ignoring: !can,
                    child: SegmentedTabs<String>(
                    items: const [TabItem('daily', 'Daily'), TabItem('days', 'Specific days'), TabItem('times_week', 'Times per week')],
                    value: freq,
                    onChanged: (v) => c.setH((x) {
                      x['frequency'] = v;
                      if (v == 'days' && (x['days'] as List? ?? const []).isEmpty) x['days'] = [0, 2, 4];
                      if (v == 'times_week' && x['times_per_week'] == null) x['times_per_week'] = 3;
                    }),
                    ),
                  ),
                ),
                if (freq == 'days')
                  HbDays(
                    days: days,
                    enabled: can,
                    onTap: (i) {
                      if (days.contains(i) && days.length == 1) return; // at least one day
                      c.setH((x) => x['days'] = (days.contains(i) ? (days..remove(i)) : (days..add(i))).toList()..sort());
                    },
                  ),
                if (freq == 'times_week')
                  Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    SizedBox(
                      width: 220,
                      child: LibStepper(
                        value: (d['times_per_week'] as num?)?.toInt() ?? 3,
                        unit: 'times a week',
                        min: 1,
                        max: 7,
                        onChanged: (v) => can ? c.setH((x) => x['times_per_week'] = v) : null,
                      ),
                    ),
                    Text('Any days. The week resets on Monday.', style: AppText.s(12, W.w5, color: AppColors.muted)),
                  ]),
              ]),
            ),
            hbField('Icon', Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (i, k) in habitIconKeys.indexed) _IconPick(k, label: habitIconNames[i], on: d['icon'] == k, onTap: can ? () => c.setH((x) => x['icon'] = k) : null),
            ])),
            hbField('Why it matters (the client sees this)', error: c.hErr['why'],
                AppTextField(controller: why, enabled: can, minLines: 2, maxLines: 4, placeholder: 'e.g. Staying hydrated keeps energy up.', formatters: [LengthLimitingTextInputFormatter(200)], onChanged: (v) => c.setH((x) => x['why'] = v))),
          ]),
        ),
        HbSaveBar(dirty: c.hDirty, saving: c.saving, canEdit: can, canCopy: c.canNewH, onDiscard: c.discardH, onSave: () => c.saveH(context)),
      ]),
    );
  }

  Widget _pair(bool phone, Widget a, Widget b) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: phone ? 10 : 12, children: [Expanded(child: a), Expanded(child: b)]);

  Widget _types(bool phone, bool can) {
    Widget one(String k, String t, String s) => Hover(
          onTap: can
              ? () => c.setH((x) {
                    x['kind'] = k;
                    if (k == 'counter' && ((x['target'] as num?) ?? 0) < 2) {
                      x['target'] = 8;
                      target.text = '8';
                      if ('${x['unit'] ?? ''}'.isEmpty) {
                        x['unit'] = 'glasses';
                        unit.text = 'glasses';
                      }
                    }
                  })
              : null,
          builder: (_, h, _) {
            final on = d['kind'] == k;
            final tick = k == 'tick';
            // Small and plain (Gautam, 22 Oct): radio · icon · name, the hint in grey after it.
            return AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: on ? AppColors.accentSoft : AppColors.card,
                borderRadius: AppRadius.all(AppRadius.input),
                border: Border.all(color: on ? AppColors.accent : (h && can ? AppColors.hbIcoHover : AppColors.line2)),
              ),
              child: Row(spacing: 8, children: [
                Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: on ? AppColors.accent : AppColors.line2, width: on ? 5 : 1.5),
                  ),
                ),
                tick
                    ? AppIcon(AppIcons.checkCircle, size: 16, color: on ? AppColors.accent : AppColors.text2, stroke: 2)
                    : Text('123', style: AppText.s(11, W.w8, color: on ? AppColors.accent : AppColors.text2, ls: -0.2)),
                Text(t, style: AppText.s(13.5, W.w7, color: on ? AppColors.accentText : AppColors.text)),
                Expanded(child: CutText(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted))),
              ]),
            );
          },
        );
    final a = one('tick', 'Tick', 'Done or not'), b = one('counter', 'Counter', 'Counts up');
    return phone
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [a, b])
        : Row(spacing: 8, children: [Expanded(child: a), Expanded(child: b)]);
  }
}

/// `.pg-step` with a number you can also type: − [value] +.
class _TargetStep extends StatelessWidget {
  const _TargetStep({required this.controller, required this.enabled, required this.onLess, required this.onMore, required this.onTyped, required this.atMin, required this.atMax});
  final TextEditingController controller;
  final bool enabled, atMin, atMax;
  final VoidCallback onLess, onMore;
  final ValueChanged<int> onTyped;
  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(borderRadius: AppRadius.all(AppRadius.input), border: Border.all(color: AppColors.line2)),
        child: Row(spacing: 6, children: [
          AppIconButton(AppIcons.minus, tooltip: 'Less', small: true, onPressed: enabled && !atMin ? onLess : null),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              style: AppText.s(16, W.w8, tabular: true),
              cursorColor: AppColors.accent,
              decoration: const InputDecoration.collapsed(hintText: ''),
              onChanged: (v) {
                final n = int.tryParse(v);
                if (n != null && n > 0) onTyped(n);
              },
            ),
          ),
          AppIconButton(AppIcons.plus, tooltip: 'More', small: true, onPressed: enabled && !atMax ? onMore : null),
        ]),
      );
}

/// `.hb-ico`: 40 icon tile; picked = tinted with a blue ring.
class _IconPick extends StatelessWidget {
  const _IconPick(this.k, {required this.label, required this.on, this.onTap});
  final String k, label;
  final bool on;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final tone = habitTone(k);
    return AppTooltip(
      message: label,
      child: Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? tone.$1 : AppColors.card,
            borderRadius: AppRadius.all(10),
            border: Border.all(color: on ? AppColors.accent : (h ? AppColors.hbIcoHover : AppColors.line2), width: on ? 2 : 1),
          ),
          child: AppIcon(habitIcon(k), size: 18, color: on ? tone.$2 : (h ? AppColors.text : AppColors.muted)),
        ),
      ),
    );
  }
}

/// Client preview: the habit card as the client's Today shows it; the button logs in the preview only.
class HabitPreviewCard extends StatefulWidget {
  const HabitPreviewCard({super.key, required this.c});
  final HbCtl c;
  @override
  State<HabitPreviewCard> createState() => _HabitPreviewCardState();
}

class _HabitPreviewCardState extends State<HabitPreviewCard> {
  int v = 0;

  @override
  Widget build(BuildContext context) {
    final d = widget.c.hd!;
    final tick = d['kind'] != 'counter';
    final t = tick ? 1 : ((d['target'] as num?)?.toInt() ?? 1).clamp(1, _maxTarget);
    final done = v >= t;
    final inc = tick ? 1 : (t / 4).round().clamp(1, _maxTarget);
    final u = '${d['unit'] ?? ''}';
    final icon = '${d['icon']}';
    return HbSideCard(title: 'Client preview', children: [
      HbPhone(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(12), border: Border.all(color: done ? AppColors.hbDoneLine : AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            Row(spacing: 10, children: [
              HbIcon(habitIcon(icon), habitTone(icon)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  CutText('${d['name'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(14, W.w7)),
                  Text(tick ? (done ? 'Done today' : 'Done today?') : freqLabel(d), style: AppText.s(12, W.w5, color: AppColors.muted)),
                ]),
              ),
            ]),
            if (!tick) ...[
              ClipRRect(
                borderRadius: AppRadius.all(4),
                child: LinearProgressIndicator(value: (v / t).clamp(0.0, 1.0), minHeight: 8, backgroundColor: AppColors.sub, color: done ? AppColors.mbBarOk : AppColors.accent),
              ),
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 4, children: [
                Text(hbNum(v.clamp(0, t)), style: AppText.s(20, W.w8, tabular: true)),
                Flexible(child: CutText('/ ${hbNum(t)} $u', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.muted))),
              ]),
            ],
            if (done)
              Container(
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.okBg, borderRadius: AppRadius.all(8)),
                child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                  const AppIcon(AppIcons.checkCircle, size: 16, color: AppColors.okText),
                  Text(tick ? 'Done today · streak 6 days' : 'Goal complete', style: AppText.s(13, W.w7, color: AppColors.okText)),
                ]),
              )
            else
              AppButton.primary(tick ? 'Mark as done' : '+ ${hbNum(inc)} $u'.trim(), expand: true, onPressed: () => setState(() => v += inc)),
            if ('${d['why'] ?? ''}'.trim().isNotEmpty) Text('${d['why']}', style: AppText.s(12, W.w5, color: AppColors.muted, h: 1.5)),
          ]),
        ),
      ),
      Text(done ? 'Preview: the client sees this celebration.' : 'Tap the button to log in the preview.', style: AppText.s(12, W.w5, color: AppColors.muted)),
      if (done) Align(alignment: Alignment.centerLeft, child: AppButton('Reset preview', kind: BtnKind.text, size: BtnSize.sm, icon: AppIcons.reset, onPressed: () => setState(() => v = 0))),
    ]);
  }
}

/// New habit template: name and Tick / Counter. Gives back the new habit.
Future<Map?> showNewHabit(BuildContext context) async {
  final name = TextEditingController();
  final kind = ValueNotifier('tick');
  final err = ValueNotifier<String?>(null);
  var saving = false;
  final r = await showAppModal<Map>(
    context,
    title: 'New habit template',
    body: 'You can set the target, days and icon next',
    icon: AppIcons.checkCircle,
    content: (ctx) => ListenableBuilder(
      listenable: Listenable.merge([kind, err]),
      builder: (ctx, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
        hbField('Name', req: true, error: err.value,
            AppTextField(controller: name, autofocus: true, placeholder: 'e.g. Drink 3 L water', formatters: [LengthLimitingTextInputFormatter(80)], onChanged: (_) => err.value = null)),
        hbField(
          'Type',
          hint: kind.value == 'tick' ? 'Done or not done, once a day.' : 'Counted up to a daily target, like 12 glasses.',
          SegmentedTabs<String>(expand: true, items: const [TabItem('tick', 'Tick'), TabItem('counter', 'Counter')], value: kind.value, onChanged: (v) => kind.value = v),
        ),
      ]),
    ),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      StatefulBuilder(
        builder: (bctx, set) => AppButton.primary('Create', icon: AppIcons.plus, expand: ctx.isPhone, loading: saving, onPressed: () async {
          final n = name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
          if (n.length < 2) {
            err.value = 'Enter the habit name.';
            return;
          }
          set(() => saving = true);
          final counter = kind.value == 'counter';
          try {
            final h = await Services.api.post<Map>('habits/', {
              'name': n,
              'kind': kind.value,
              'target': counter ? 8 : null,
              'unit': counter ? 'glasses' : '',
              'frequency': 'daily',
              'icon': 'habit',
              'why': 'Small steps every day add up.',
            });
            if (ctx.mounted) Navigator.of(ctx).pop(h);
          } on ApiError catch (e) {
            set(() => saving = false);
            err.value = e.field('name') ?? e.message;
          }
        }),
      ),
    ],
  );
  disposeLater([name, kind, err]);
  return r;
}
