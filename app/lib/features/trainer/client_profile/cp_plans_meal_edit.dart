import 'dart:convert';

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
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import '../../../core/widgets/tooltip.dart';
import 'cp_common.dart';
import 'cp_plans_model.dart';
import 'cp_plans_parts.dart';

/// Meal plan editor for one client (`pe.meal`, board `TrainerClientProfile`): `Edit X for Y` edits Y's own copy
/// in place (the master is not changed). Day strip Mon–Sun: each day shows that day's meals; a change applies to
/// the picked day only, or to every day with `Apply to every day`. Daily target and what the day adds up to, the
/// meal cards (rename, time, remove, foods with P / C / F / kcal, `Add food`), `Add meal`, and the `Portion` panel
/// for the picked food (amount, unit, grams, remove). Saves through `clients/<id>/meal-plans/<a>/meals/`.
class MealEditor extends StatefulWidget {
  const MealEditor({super.key, required this.d, required this.onClose, this.startDay});
  final PlansData d;
  final int? startDay;

  /// Closes the editor; gives back the day it was on.
  final ValueChanged<int?> onClose;
  @override
  State<MealEditor> createState() => _MealEditorState();
}

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

String _n(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

final _f = NumberFormat.decimalPattern('en_IN');

class _MealEditorState extends State<MealEditor> {
  PlansData get d => widget.d;
  Map get a => d.meal!;
  String get first => d.c.first;

  late Map data = d.mealPlan!;
  late int sel = widget.startDay ?? DateTime.now().weekday - 1;
  late List<Map> draft = _copy(sel);
  bool dirty = false, everyDay = false, busy = false, saved = false;

  /// Picked food: (meal index, item index) in [draft].
  (int, int)? pick;

  /// Bumped on every change so the phone's Portion sheet redraws too.
  final _tick = ValueNotifier(0);

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  List<Map> _copy(int wd) => [for (final m in mealsOnDay(data, wd)) jsonDecode(jsonEncode(m)) as Map];

  Set<int> get own => ownMealDays(data);

  void _change(VoidCallback f) {
    setState(() {
      f();
      dirty = true;
    });
    _tick.value++;
  }

  // ─────────────────────────────── foods

  static Map? _opt(Map meal) {
    final opts = [for (final o in (meal['options'] as List?) ?? const []) o as Map];
    return opts.where((o) => o['is_default'] == true).firstOrNull ?? opts.firstOrNull;
  }

  static List items(Map meal) => (_opt(meal)?['items'] as List?) ?? const [];

  static List<Map> unitsOf(Map it) => [for (final u in ((it['food_detail'] as Map?)?['units'] as List?) ?? const []) u as Map];
  static Map? unitOf(Map it) => unitsOf(it).where((u) => u['id'] == it['unit']).firstOrNull;

  /// Grams and macros of one food after its amount or unit changed (food values are per 100 g).
  static void recalc(Map it) {
    final f = (it['food_detail'] as Map?) ?? const {};
    final u = unitOf(it);
    final g = _d(it['quantity']) * (u == null ? 1 : _d(u['grams']));
    double per(String k) => _d(f[k]) * g / 100;
    it['grams'] = g;
    it['macros'] = {'kcal': per('kcal').round(), 'protein': (per('protein') * 10).round() / 10, 'carbs': (per('carbs') * 10).round() / 10, 'fat': (per('fat') * 10).round() / 10};
  }

  static double m(Map it, String k) => _d((it['macros'] as Map?)?[k]);
  static double tot(Iterable its, String k) => its.fold(0.0, (a, it) => a + m(it as Map, k));
  double dayTot(String k) => draft.fold(0.0, (a, x) => a + tot(items(x), k));

  /// "2 × 1 katori · 300 g", "150 g".
  static String amount(Map it) {
    final u = unitOf(it);
    final q = _n(_d(it['quantity']));
    if (u == null) return '$q g';
    return '${q == '1' ? '' : '$q × '}${u['name']} · ${_n(_d(it['grams']))} g';
  }

  Map? get _picked {
    final p = pick;
    if (p == null || p.$1 >= draft.length) return null;
    final its = items(draft[p.$1]);
    return p.$2 < its.length ? its[p.$2] as Map : null;
  }

  // ─────────────────────────────── edits

  Future<void> _addFood(int mi) async {
    final picked = await showFoodPicker(context, meal: '${draft[mi]['name']}', first: first);
    if (picked == null || picked.isEmpty || !mounted) return;
    _change(() {
      final o = _opt(draft[mi]);
      if (o == null) {
        (draft[mi]['options'] ??= []).add({'name': 'Main', 'is_default': true, 'items': []});
      }
      final list = (_opt(draft[mi])!['items'] ??= []) as List;
      for (final f in picked) {
        final du = f['default_unit'] as Map?;
        final it = {'food': f['id'], 'food_detail': f, 'unit': du?['id'], 'quantity': du?['id'] == null ? 100 : _d(f['default_quantity']).clamp(0.25, 99)};
        recalc(it);
        list.add(it);
      }
      pick = (mi, list.length - 1);
    });
  }

  void _removeFood(int mi, int ii) {
    final list = items(draft[mi]);
    final it = list[ii];
    _change(() {
      list.removeAt(ii);
      pick = null;
    });
    showToast(context, 'Removed for $first', sub: '${(it['food_detail'] as Map?)?['name'] ?? ''} · ${draft[mi]['name']}', kind: ToastKind.ok, action: 'Undo', onAction: () {
      if (!mounted) return;
      _change(() => list.insert(ii.clamp(0, list.length), it));
    });
  }

  void _setQty(Map it, double q) => _change(() {
        it['quantity'] = q.clamp(0.25, 5000);
        recalc(it);
      });

  void _setUnit(Map it, Object? unitId) => _change(() {
        // Same amount in grams in the new unit (rounded to a quarter), like the board's hint says.
        final g = _d(it['grams']);
        it['unit'] = unitId;
        final u = unitOf(it);
        it['quantity'] = u == null ? g.roundToDouble().clamp(1, 5000) : ((g / _d(u['grams'])) * 4).round().clamp(1, 400) / 4;
        recalc(it);
      });

  Future<void> _rename(int mi) async {
    final name = await _askName(context, title: 'Rename meal', value: '${draft[mi]['name']}');
    if (name != null && mounted) _change(() => draft[mi]['name'] = name);
  }

  Future<void> _time(int mi) async {
    final t = DateTime.tryParse('2000-01-01 ${draft[mi]['time']}');
    final v = await showTimePicker(context: context, initialTime: TimeOfDay(hour: t?.hour ?? 8, minute: t?.minute ?? 0));
    if (v == null || !mounted) return;
    _change(() {
      draft[mi]['time'] = '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}:00';
      final m = draft.removeAt(mi);
      draft.add(m);
      draft.sort((x, y) => '${x['time']}'.compareTo('${y['time']}'));
      pick = null;
    });
  }

  Future<void> _removeMeal(int mi) async {
    final ok = await confirmAction(context,
        title: 'Remove ${draft[mi]['name']}?',
        body: everyDay ? '$first no longer has it on any day.' : '$first no longer has it on ${weekdayFull[sel]}s.',
        confirm: 'Remove meal',
        danger: true,
        icon: AppIcons.trash);
    if (ok && mounted) {
      _change(() {
        draft.removeAt(mi);
        pick = null;
      });
    }
  }

  Future<void> _addMeal() async {
    final name = await _askName(context, title: 'Add a meal', value: '', confirm: 'Add meal');
    if (name == null || !mounted) return;
    final last = draft.isEmpty ? null : DateTime.tryParse('2000-01-01 ${draft.last['time']}');
    final h = ((last?.hour ?? 7) + 2).clamp(0, 23);
    _change(() {
      draft.add({
        'name': name,
        'time': '${h.toString().padLeft(2, '0')}:00:00',
        'kcal_target': 0,
        'options': [
          {'name': 'Main', 'is_default': true, 'items': []},
        ],
      });
      draft.sort((x, y) => '${x['time']}'.compareTo('${y['time']}'));
    });
  }

  // ─────────────────────────────── save

  Map<String, dynamic> get _payload => {
        'weekday': sel,
        'every_day': everyDay,
        'meals': [
          for (final x in draft)
            {
              if (x['id'] != null) 'id': x['id'],
              'name': '${x['name']}',
              'time': '${x['time']}',
              'kcal_target': x['kcal_target'] ?? 0,
              'options': [
                for (final o in (x['options'] as List? ?? const []).cast<Map>())
                  {
                    if (o['id'] != null) 'id': o['id'],
                    'name': '${o['name']}',
                    'is_default': o['is_default'] == true,
                    'items': [
                      for (final it in (o['items'] as List? ?? const []).cast<Map>())
                        {if (it['id'] != null) 'id': it['id'], 'food': it['food'], 'quantity': _n(_d(it['quantity'])), 'unit': it['unit']},
                    ],
                  },
              ],
            },
        ],
      };

  /// Saves the picked day (or every day). [stay]: keep editing (switching day), else close.
  Future<bool> _save({bool stay = false}) async {
    if (!dirty) {
      if (!stay) _close();
      return true;
    }
    setState(() => busy = true);
    try {
      final r = await Services.api.put<Map>('clients/${d.c.id}/meal-plans/${a['id']}/meals/', _payload);
      if (!mounted) return false;
      showToast(context, 'Saved for $first',
          sub: '${everyDay ? 'Every day' : '${weekdayFull[sel]} only'} · the master stays the same', kind: ToastKind.ok);
      saved = true;
      setState(() {
        busy = false;
        data = r;
        d.mealPlan = r;
        dirty = false;
        pick = null;
        draft = _copy(sel);
      });
      if (!stay) _close();
      return true;
    } on ApiError catch (e) {
      if (mounted) {
        setState(() => busy = false);
        showToast(context, 'Could not save the meals', sub: e.message, kind: ToastKind.info);
      }
      return false;
    }
  }

  void _close() {
    widget.onClose(sel);
    if (saved) d.reload();
  }

  Future<void> _cancel() async {
    if (dirty) {
      final ok = await confirmAction(context, title: 'Leave without saving?', body: 'Your changes for $first are lost.', confirm: 'Leave', danger: true);
      if (!ok) return;
    }
    _close();
  }

  Future<void> _pickDay(int i) async {
    if (i == sel) return;
    if (dirty) {
      final ok = await confirmAction(context,
          title: 'Save ${weekdayFull[sel]} first?',
          body: 'Your changes to ${everyDay ? 'every day' : weekdayFull[sel]} are not saved yet. Save them, then open ${weekdayFull[i]}.',
          confirm: 'Save and open ${weekdayShort[i]}');
      if (!ok || !mounted || !await _save(stay: true)) return;
    }
    setState(() {
      sel = i;
      draft = _copy(i);
      pick = null;
      everyDay = false;
    });
  }

  Future<void> _reset() async {
    final ok = await confirmAction(context,
        title: 'Reset to master?',
        body: 'Every change made for $first goes away, on every day. $first follows the master meal plan "${a['plan_name']}" again. Logged meals stay.',
        confirm: 'Reset to master',
        danger: true,
        icon: AppIcons.reset);
    if (!ok || !mounted) return;
    try {
      await Services.api.post('clients/${d.c.id}/meal-plans/${a['id']}/reset/', const {});
      if (!mounted) return;
      showToast(context, '$first follows the master again', sub: '${a['plan_name']}', kind: ToastKind.ok);
      saved = true;
      _close();
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not reset the plan', sub: e.message, kind: ToastKind.info);
    }
  }

  // ─────────────────────────────── build

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final custom = data['custom'] == true;
    final head = Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
        Text('Edit ${a['plan_name']} for $first', style: AppText.s(17, W.w7, ls: -.2)),
        AppTooltip(
          message: 'Only $first’s copy changes. The master plan and other clients stay the same. Each day can have its own meals.',
          child: const Padding(padding: EdgeInsets.all(3), child: AppIcon(AppIcons.info, size: 16, color: AppColors.muted)),
        ),
      ]),
      Text(
        [
          'Since ${cpDm(a['start_date'])}',
          custom ? '$first’s own copy' : 'same as the master',
          if (own.isNotEmpty) '${own.length} day${own.length == 1 ? '' : 's'} with ${own.length == 1 ? 'its' : 'their'} own meals',
          if (dirty) 'not saved yet',
        ].join(' · '),
        style: AppText.cap,
      ),
    ]);
    final acts = <Widget>[
      if (custom) AppButton('Reset to master', kind: BtnKind.text, icon: AppIcons.reset, onPressed: busy ? null : _reset),
      if (!phone || !custom) AppButton('Cancel', onPressed: busy ? null : _cancel),
      AppButton.primary('Save for $first', icon: AppIcons.check, loading: busy, onPressed: busy ? null : () => _save()),
    ];
    return LayoutBuilder(builder: (context, b) {
      final side = b.maxWidth >= 900;
      final meals = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        for (var i = 0; i < draft.length; i++) _mealCard(i, side),
        if (draft.isEmpty) AppCard(child: PdEmpty('No meals on ${weekdayFull[sel]} yet. Add the first one.')),
        AppButton('Add meal', icon: AppIcons.plus, expand: true, onPressed: _addMeal),
      ]);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        Wrap(alignment: WrapAlignment.spaceBetween, runSpacing: 10, spacing: 8, children: [
          AppButton('Back to plan', icon: AppIcons.chevronLeft, onPressed: _cancel),
          Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: acts),
        ]),
        head,
        _targetCard(),
        side
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
                Expanded(child: meals),
                SizedBox(width: 340, child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: _panel())),
              ])
            : meals,
      ]);
    });
  }

  /// `.cp-mtgt`: day strip, Apply to every day, daily target and what the day adds up to.
  Widget _targetCard() {
    final k = dayTot('kcal'), target = _d(data['kcal_target']);
    final diff = k - target;
    final (String bl, Tone bt) = target == 0
        ? ('', Tone.neutral)
        : diff.abs() <= target * .05
            ? ('On target', Tone.ok)
            : diff > 0
                ? ('${_f.format(diff.round())} kcal over', Tone.warn)
                : ('${_f.format(-diff.round())} kcal under', Tone.info);
    double kcalOn(int i) => i == sel ? k : mealsOnDay(data, i).fold<double>(0, (a, x) => a + tot(items(x), 'kcal'));
    Widget chip(String t) => Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(AppRadius.input), border: Border.all(color: AppColors.line2)),
          child: Center(widthFactor: 1, child: Text(t, style: AppText.s(13, W.w6, color: AppColors.text2, tabular: true))),
        );
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DayStrip(
          days: [for (var i = 0; i < 7; i++) (weekdayShort[i], '${_f.format(kcalOn(i).round())} kcal', own.contains(i) || (dirty && i == sel && !everyDay), false)],
          selected: sel,
          onPick: _pickDay,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            Hover(
              onTap: () => _change(() => everyDay = !everyDay),
              builder: (_, _, _) => Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
                Padding(padding: const EdgeInsets.only(top: 2), child: AppToggle(value: everyDay, onChanged: (v) => _change(() => everyDay = v))),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                    Text('Apply to every day', style: AppText.s(13.5, W.w7)),
                    Text(
                      everyDay
                          ? 'Saving gives $first these meals on all 7 days${own.isNotEmpty ? '. Days with their own meals get these too' : ''}.'
                          : 'Off: only ${weekdayFull[sel]} changes. The other days keep their meals.',
                      style: AppText.s(12.5, W.w5, color: AppColors.muted),
                    ),
                  ]),
                ),
              ]),
            ),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('Daily target', style: AppText.s(12.5, W.w7)),
              chip('${_f.format(_d(data['kcal_target']).round())} kcal'),
              chip('${data['protein_g']} g protein'),
              chip('${data['carbs_g']} g carbs'),
              chip('${data['fat_g']} g fat'),
            ]),
            Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text.rich(
                TextSpan(text: '${weekdayFull[sel]} adds up to ', children: [
                  TextSpan(text: '${_f.format(k.round())} kcal', style: AppText.s(13, W.w8, color: AppColors.text)),
                  TextSpan(text: ' · P ${dayTot('protein').round()} g · C ${dayTot('carbs').round()} g · F ${dayTot('fat').round()} g'),
                ]),
                style: AppText.s(13, W.w5, color: AppColors.text2),
              ),
              if (bl.isNotEmpty) AppBadge(bl, tone: bt, plain: true),
            ]),
          ]),
        ),
      ]),
    );
  }

  /// `.mb-meal`: icon, name, "8:00 am · target 450 kcal", ⋯; the foods; `Add food` and the meal's totals.
  Widget _mealCard(int mi, bool side) {
    final x = draft[mi];
    final its = items(x);
    final k = tot(its, 'kcal');
    final tgt = _d(x['kcal_target']);
    final more = Builder(
      builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'More actions', ghost: true, small: true, onPressed: () => showAppMenu(b, [
            MenuEntry('Rename meal', icon: AppIcons.edit, onTap: () => _rename(mi)),
            MenuEntry('Change time', icon: AppIcons.clock, onTap: () => _time(mi)),
            MenuEntry('Remove meal', icon: AppIcons.trash, danger: true, onTap: () => _removeMeal(mi)),
          ], width: 200)),
    );
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
          child: Row(spacing: 12, children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.okBg, borderRadius: BorderRadius.circular(9)),
              child: const AppIcon(AppIcons.apple, size: 18, color: AppColors.okText),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Hover(
                  onTap: () => _rename(mi),
                  builder: (_, h, _) => Text('${x['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(15.5, W.w8, color: h ? AppColors.accentText : AppColors.text)),
                ),
                Text([mealTime(x['time']), if (tgt > 0) 'target ${_f.format(tgt.round())} kcal'].join(' · '), style: AppText.s(12.5, W.w6, color: AppColors.muted)),
              ]),
            ),
            more,
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 1, children: [
            for (var ii = 0; ii < its.length; ii++) _foodRow(mi, ii, its[ii] as Map, side),
            if (its.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Text('No foods yet. Use Add food to pick from the food library.', style: AppText.s(13, W.w5, color: AppColors.muted)),
              ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 16, 10),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
          child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 4, children: [
            AppButton('Add food', kind: BtnKind.text, icon: AppIcons.plus, size: BtnSize.sm, onPressed: () => _addFood(mi)),
            Row(mainAxisSize: MainAxisSize.min, spacing: 12, children: [
              Text('P ${tot(its, 'protein').round()} g · C ${tot(its, 'carbs').round()} g · F ${tot(its, 'fat').round()} g', style: AppText.s(12, W.w6, color: AppColors.muted, tabular: true)),
              Text.rich(
                TextSpan(text: _f.format(k.round()), children: [if (tgt > 0) TextSpan(text: ' / ${_f.format(tgt.round())} kcal', style: AppText.s(12, W.w6, color: AppColors.muted)) else const TextSpan(text: ' kcal')]),
                style: AppText.s(13.5, W.w8, tabular: true),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  /// `.mb-fr`: food tile, name over amount, P / C / F, kcal. Tap: the Portion panel (a sheet on narrow screens).
  Widget _foodRow(int mi, int ii, Map it, bool side) {
    final on = pick == (mi, ii);
    final f = (it['food_detail'] as Map?) ?? const {};
    final (c1, c2) = AppColors.mediaTiles[(mi + ii) % 4];
    Widget mac(String l, String k) => SizedBox(width: 48, child: Text('$l ${m(it, k).round()}', textAlign: TextAlign.right, style: AppText.s(12, W.w6, color: AppColors.muted, tabular: true)));
    return Hover(
      onTap: () {
        setState(() => pick = (mi, ii));
        if (!side) _panelSheet();
      },
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: on ? AppColors.accentSoft : (h ? AppColors.hover : null),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? AppColors.pickLine : Colors.transparent),
        ),
        child: Row(spacing: 12, children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c1, c2])),
            child: const AppIcon(AppIcons.apple, size: 16, color: AppColors.mediaFg),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text('${f['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7)),
              Text(amount(it), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted)),
            ]),
          ),
          if (!context.isPhone) ...[mac('P', 'protein'), mac('C', 'carbs'), mac('F', 'fat')],
          SizedBox(width: 64, child: Text('${m(it, 'kcal').round()} kcal', textAlign: TextAlign.right, style: AppText.s(13, W.w8, tabular: true))),
        ]),
      ),
    );
  }

  void _panelSheet() => showAppDrawer(
        context,
        title: 'Portion',
        sub: '${weekdayFull[sel]} · only for $first',
        icon: AppIcons.apple,
        builder: (ctx) => ValueListenableBuilder(
          valueListenable: _tick,
          builder: (_, _, _) => Padding(padding: const EdgeInsets.only(top: 14), child: _panel(onRemoved: () => Navigator.of(ctx).pop())),
        ),
        footer: (ctx) => [AppButton.primary('Done', expand: true, onPressed: () => Navigator.of(ctx).pop())],
      );

  /// `.mb-side` Portion: the picked food, its amount (− n +) and unit, grams and macros, remove.
  Widget _panel({VoidCallback? onRemoved}) {
    final it = _picked;
    final title = Row(children: [Expanded(child: Text('Portion', style: AppText.s(14.5, W.w8))), if (it != null) Text('${draft[pick!.$1]['name']}', style: AppText.cap)]);
    if (it == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        title,
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: AppIcon(AppIcons.info, size: 16, color: AppColors.muted)),
          Expanded(child: Text('Tap a food to change how much $first eats or its unit.', style: AppText.s(13, W.w5, color: AppColors.muted, h: 1.5))),
        ]),
      ]);
    }
    final f = (it['food_detail'] as Map?) ?? const {};
    final u = unitOf(it);
    final q = _d(it['quantity']);
    final step = u == null ? 10.0 : (q < 1 ? .25 : .5);
    final per = u == null ? '100 g = ${_d(f['kcal']).round()} kcal' : '${u['name']} = ${_n(_d(u['grams']))} g · ${(_d(f['kcal']) * _d(u['grams']) / 100).round()} kcal';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      title,
      Row(spacing: 10, children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: LinearGradient(colors: [AppColors.mediaTiles[0].$1, AppColors.mediaTiles[0].$2])),
          child: const AppIcon(AppIcons.apple, size: 18, color: AppColors.mediaFg),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
            Text('${f['name'] ?? ''}', style: AppText.s(14, W.w7)),
            Text(per, style: AppText.s(12, W.w5, color: AppColors.muted)),
          ]),
        ),
      ]),
      Text('Amount', style: AppText.label),
      Row(spacing: 8, children: [
        Expanded(
          child: Container(
            height: 36,
            decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.input), border: Border.all(color: AppColors.line2)),
            child: Row(children: [
              AppIconButton(AppIcons.minus, tooltip: 'Less', ghost: true, small: true, onPressed: q - step < .25 ? null : () => _setQty(it, q - step)),
              Expanded(child: Text(_n(q), textAlign: TextAlign.center, style: AppText.s(14, W.w8, tabular: true))),
              AppIconButton(AppIcons.plus, tooltip: 'More', ghost: true, small: true, onPressed: () => _setQty(it, q + step)),
            ]),
          ),
        ),
        SizedBox(
          width: 130,
          child: AppSelect(u == null ? 'g' : '${u['name']}', entries: [
            MenuEntry('g', selected: u == null, end: '1 g', onTap: () => _setUnit(it, null)),
            for (final x in unitsOf(it)) MenuEntry('${x['name']}', selected: x['id'] == it['unit'], end: '${_n(_d(x['grams']))} g', onTap: () => _setUnit(it, x['id'])),
          ]),
        ),
      ]),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(8)),
        child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: [
          Text('${_n(_d(it['grams']))} g', style: AppText.s(14, W.w8, tabular: true)),
          Text('${m(it, 'kcal').round()} kcal · P ${_n(m(it, 'protein'))} g · C ${_n(m(it, 'carbs'))} g · F ${_n(m(it, 'fat'))} g',
              style: AppText.s(12, W.w6, color: AppColors.text2, tabular: true)),
        ]),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: AppButton('Remove from this meal', kind: BtnKind.text, icon: AppIcons.trash, size: BtnSize.sm, onPressed: () {
          _removeFood(pick!.$1, pick!.$2);
          onRemoved?.call();
        }),
      ),
    ]);
  }
}

/// Small modal with one name field (Rename meal / Add a meal).
Future<String?> _askName(BuildContext context, {required String title, required String value, String confirm = 'Save'}) {
  final t = TextEditingController(text: value);
  final err = ValueNotifier<String?>(null);
  void done(BuildContext ctx) {
    final v = t.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (v.length < 2) {
      err.value = 'Enter the meal name, e.g. Breakfast.';
      return;
    }
    Navigator.of(ctx).pop(v.length > 60 ? v.substring(0, 60) : v);
  }

  return showAppModal<String>(
    context,
    title: title,
    icon: AppIcons.edit,
    content: (ctx) => ValueListenableBuilder(
      valueListenable: err,
      builder: (_, e, _) => AppTextField(controller: t, autofocus: true, placeholder: 'Breakfast, Pre-workout, Dinner…', error: e, onSubmitted: (_) => done(ctx)),
    ),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      AppButton.primary(confirm, expand: ctx.isPhone, onPressed: () => done(ctx)),
    ],
  ).whenComplete(() => disposeLater([t, err]));
}

/// `Add food`: the team's food library (search, groups), tick one or more. Returns the picked foods.
Future<List<Map>?> showFoodPicker(BuildContext context, {required String meal, required String first}) {
  final picked = ValueNotifier<List<Map>>([]);
  final group = ValueNotifier('');
  final q = ValueNotifier('');
  final search = TextEditingController();
  final all = Services.api.get<List>('food-picker/').then((r) => [for (final x in r) x as Map]);
  const groups = [('', 'All'), ('protein', 'Protein'), ('carbs', 'Carbs'), ('fats', 'Fats'), ('veg', 'Veg'), ('fruits', 'Fruits'), ('dairy', 'Dairy'), ('indian', 'Indian'), ('beverages', 'Drinks')];
  return showAppDrawer<List<Map>>(
    context,
    title: 'Add food to $meal',
    sub: 'From the food library · only for $first',
    icon: AppIcons.apple,
    builder: (ctx) => FutureBuilder<List<Map>>(
      future: all,
      builder: (ctx, snap) {
        if (snap.hasError) return const EmptyState('Could not load the foods');
        if (!snap.hasData) return const CpLoading();
        final list = snap.data!;
        return ListenableBuilder(
          listenable: Listenable.merge([picked, group, q]),
          builder: (ctx, _) {
            final rows = list.where((x) => (group.value.isEmpty || x['group'] == group.value) && (q.value.isEmpty || '${x['name']}'.toLowerCase().contains(q.value))).toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
              const SizedBox(height: 4),
              AppSearchField(controller: search, placeholder: 'Search foods', onChanged: (v) => q.value = v.trim().toLowerCase()),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(spacing: 6, children: [
                  for (final (k, l) in groups)
                    if (k.isEmpty || list.any((x) => x['group'] == k))
                      FilterChipX(l, selected: group.value == k, count: k.isEmpty ? list.length : list.where((x) => x['group'] == k).length, onTap: () => group.value = k),
                ]),
              ),
              if (rows.isEmpty) const EmptyState('No foods match'),
              for (final x in rows)
                () {
                  final on = picked.value.any((p) => p['id'] == x['id']);
                  final du = x['default_unit'] as Map?;
                  final g = du?['id'] == null ? 100.0 : _d(du!['grams']);
                  return AppRow(
                    leading: AppCheckbox(value: on, size: 18),
                    title: '${x['name']}${'${x['brand'] ?? ''}'.isEmpty ? '' : ' · ${x['brand']}'}',
                    sub: '${du?['id'] == null ? '100 g' : du!['name']} · ${(_d(x['kcal']) * g / 100).round()} kcal · P ${_n((_d(x['protein']) * g / 100 * 10).roundToDouble() / 10)} g',
                    trailing: x['team'] == true ? Text('Your team', style: AppText.cap) : null,
                    onTap: () => picked.value = on ? picked.value.where((p) => p['id'] != x['id']).toList() : [...picked.value, x],
                  );
                }(),
            ]);
          },
        );
      },
    ),
    footer: (ctx) => [
      ValueListenableBuilder(
        valueListenable: picked,
        builder: (_, p, _) {
          final t = Text(p.isEmpty ? 'Tick the foods to add' : '${p.length} selected', style: AppText.cap);
          return ctx.isPhone ? t : Expanded(child: t);
        },
      ),
      if (!ctx.isPhone) AppButton('Cancel', onPressed: () => Navigator.of(ctx).pop()),
      ValueListenableBuilder(
        valueListenable: picked,
        builder: (_, p, _) => AppButton.primary(p.length > 1 ? 'Add ${p.length} foods' : 'Add food',
            icon: AppIcons.check, expand: ctx.isPhone, onPressed: p.isEmpty ? null : () => Navigator.of(ctx).pop(p)),
      ),
    ],
  ).whenComplete(() => disposeLater([picked, group, q, search]));
}
