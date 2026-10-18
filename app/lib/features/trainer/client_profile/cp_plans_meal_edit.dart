import 'dart:convert';
import 'dart:math' as math;

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
import '../../../core/widgets/tabs.dart';
import '../../../core/widgets/tooltip.dart';
import 'cp_common.dart';
import 'cp_plans_model.dart';
import 'cp_plans_parts.dart';

/// Meal plan editor for one client (`pe.meal`, board `TrainerClientProfile`): `Edit X for Y` edits Y's own copy
/// in place (the master is not changed). Day strip Mon–Sun: each day shows that day's meals; a change applies to
/// the picked day only, or to every day with `Apply to every day`. Daily target and what the day adds up to, the
/// meal cards (rename, time, remove, foods with swaps badge, P / C / F / kcal, `Add food`), `Add meal`, and the
/// `Portion and swaps` panel for the picked food (amount, unit, grams, the swaps Y may use, remove).
/// Each food's swaps belong to Y's copy only (`swaps` on the item). Saves through `clients/<id>/meal-plans/<a>/meals/`.
///
/// Layout: the panel sits beside the meals when there is room (desktop and tablet; on narrow tablets the meal
/// rows drop the P / C / F columns), else it is a bottom sheet (phone).
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

const _frac = {0: '', 25: '¼', 50: '½', 75: '¾'};
const _plural = {'piece': 'pieces', 'slice': 'slices', 'cup': 'cups', 'scoop': 'scoops', 'plate': 'plates', 'bowl': 'bowls', 'glass': 'glasses', 'handful': 'handfuls'};

/// 0.5 → "½", 1.5 → "1½", 2 → "2", 0.3 → "0.3".
String _qty(double q) {
  final w = q.floor();
  final f = _frac[((q - w) * 100).round()];
  if (f == null) return _n(q);
  return w == 0 && f.isNotEmpty ? f : '$w$f';
}

/// An amount people read at a glance: "60 g", "1 scoop", "½ katori", "1½ katori", "2 pieces" (never
/// "0.5 × 1 katori"). Same as the server's `portion_label`.
String _portion(double q, String? unit) {
  if (unit == null || unit == 'g') return '${_n(q)} g';
  final name = unit.trim();
  if (!name.startsWith('1 ')) return q == 1 ? name : '${_qty(q)} × $name';
  var noun = name.substring(2).trim();
  if (q > 1) noun = _plural[noun] ?? noun;
  return '${_qty(q)} $noun';
}

/// Swap badge colour by match %: the board's `b-ok` from 80 %, else `b-warn`.
Tone _matchTone(num m) => m >= 80 ? Tone.ok : Tone.warn;

class _MealEditorState extends State<MealEditor> {
  PlansData get d => widget.d;
  Map get a => d.meal!;
  String get first => d.c.first;
  String get she => pronounSub(d.c);

  late Map data = d.mealPlan!;
  late int sel = widget.startDay ?? DateTime.now().weekday - 1;
  late List<Map> draft = _copy(sel);
  bool dirty = false, everyDay = false, busy = false, saved = false;

  /// Picked food: (meal index, item index) in [draft].
  (int, int)? pick;

  /// Bumped on every change so the phone's Portion sheet redraws too.
  final _tick = ValueNotifier(0);

  /// Side panel: it moves down next to the picked food (the board's panel is sticky), so it stays in view
  /// on a long day. Measured from the meals | panel row ([_sideKey]) to the picked food row.
  double _panelTop = 0;
  final _sideKey = GlobalKey();
  final _rowKeys = <(int, int), GlobalKey>{};

  void _follow((int, int) at) {
    final row = _rowKeys[at]?.currentContext?.findRenderObject() as RenderBox?;
    final side = _sideKey.currentContext?.findRenderObject() as RenderBox?;
    if (row == null || side == null) return;
    final y = row.localToGlobal(Offset.zero, ancestor: side).dy;
    setState(() => _panelTop = y < 200 ? 0 : y - 120);
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  /// One day's meals to edit. Each food keeps what it was when loaded (`_m`) so a change shows "Was: …".
  List<Map> _copy(int wd) {
    final out = [for (final m in mealsOnDay(data, wd)) jsonDecode(jsonEncode(m)) as Map];
    for (final m in out) {
      for (final it in items(m).cast<Map>()) {
        if (it['was'] == null) {
          it['_m'] = {'food': it['food'], 'quantity': _d(it['quantity']), 'unit': it['unit'], 'label': '${(it['food_detail'] as Map?)?['name'] ?? ''}, ${amount(it)}'};
        }
      }
    }
    return out;
  }

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

  static List<Map> swapsOf(Map it) => [for (final s in (it['swaps'] as List?) ?? const []) s as Map];

  /// Swaps keep giving the same calories as the food: amounts follow a change of its amount or unit
  /// (in the swap's unit rounded to a half, in grams to 5 g, like the server's `same_kcal_amount`).
  static void rescaleSwaps(Map it) {
    final kcal = _d((it['food_detail'] as Map?)?['kcal']) * _d(it['grams']) / 100;
    for (final s in swapsOf(it)) {
      final fd = (s['food_detail'] as Map?) ?? const {};
      final per100 = _d(fd['kcal']);
      if (per100 <= 0) continue;
      final u = [for (final x in (fd['units'] as List?) ?? const []) x as Map].where((x) => x['id'] == s['unit']).firstOrNull;
      final q = u == null ? ((kcal * 100 / per100 / 5).round() * 5).clamp(5, 5000).toDouble() : ((kcal / (per100 * _d(u['grams']) / 100) * 2).round() / 2).clamp(.5, 400).toDouble();
      final g = q * (u == null ? 1 : _d(u['grams']));
      s['quantity'] = q;
      s['grams'] = g;
      s['kcal'] = (per100 * g / 100).round();
      for (final k in ['protein', 'carbs', 'fat']) {
        s[k] = (_d(fd[k]) * g / 10).round() / 10;
      }
    }
  }

  static double m(Map it, String k) => _d((it['macros'] as Map?)?[k]);
  static double tot(Iterable its, String k) => its.fold(0.0, (a, it) => a + m(it as Map, k));
  double dayTot(String k) => draft.fold(0.0, (a, x) => a + tot(items(x), k));

  /// "2 katori · 300 g", "½ plate · 75 g", "150 g".
  static String amount(Map it) {
    final u = unitOf(it);
    final q = _d(it['quantity']);
    if (u == null) return _portion(q, null);
    return '${_portion(q, '${u['name']}')} · ${_n(_d(it['grams']))} g';
  }

  /// What the master has here when this food differs ("Moong dal (cooked), 1 katori · 150 g", "not in the
  /// master"), else null.
  static String? wasOf(Map it) {
    if (it['was'] != null) return '${it['was']}';
    final o = it['_m'] as Map?;
    if (o == null) return it['id'] == null ? 'not in the master' : null;
    final same = o['food'] == it['food'] && _d(o['quantity']) == _d(it['quantity']) && o['unit'] == it['unit'];
    return same ? null : '${o['label']}';
  }

  Map? get _picked {
    final p = pick;
    if (p == null || p.$1 >= draft.length) return null;
    final its = items(draft[p.$1]);
    return p.$2 < its.length ? its[p.$2] as Map : null;
  }

  // ─────────────────────────────── edits

  Future<void> _addFood(int mi) async {
    final meal = draft[mi];
    await showFoodPicker(
      context,
      meal: '${meal['name']} · ${mealTime(meal['time'])}',
      first: first,
      diet: '${data['diet'] ?? ''}',
      dietLabel: '${a['diet_label'] ?? ''}',
      added: () => {for (final it in items(meal).cast<Map>()) '${it['food']}'},
      onAdd: (f) {
        if (!mounted) return;
        _change(() {
          if (_opt(meal) == null) {
            (meal['options'] ??= []).add({'name': 'Main', 'is_default': true, 'items': []});
          }
          final list = (_opt(meal)!['items'] ??= []) as List;
          final du = f['default_unit'] as Map?;
          final it = {'food': f['id'], 'food_detail': f, 'unit': du?['id'], 'quantity': du?['id'] == null ? 100 : _d(f['default_quantity']).clamp(0.25, 99), 'swaps': []};
          recalc(it);
          list.add(it);
          pick = (draft.indexOf(meal), list.length - 1);
        });
      },
      onRemove: (f) {
        if (!mounted) return;
        final list = items(meal);
        final ii = list.lastIndexWhere((x) => '${(x as Map)['food']}' == '${f['id']}');
        if (ii < 0) return;
        final mi = draft.indexOf(meal);
        _change(() {
          list.removeAt(ii);
          final p = pick;
          if (p != null && p.$1 == mi) pick = p.$2 == ii ? null : (p.$2 > ii ? (mi, p.$2 - 1) : p);
        });
      },
    );
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
        rescaleSwaps(it);
      });

  void _setUnit(Map it, Object? unitId) {
    final name = '${(it['food_detail'] as Map?)?['name'] ?? ''}';
    final before = _portion(_d(it['quantity']), unitOf(it)?['name'] as String?);
    _change(() {
      // About the same grams in the new unit (rounded to a quarter; grams to 1 g), like the board's hint says.
      final g = _d(it['grams']);
      it['unit'] = unitId;
      final u = unitOf(it);
      it['quantity'] = u == null ? g.roundToDouble().clamp(1, 5000).toDouble() : ((g / _d(u['grams'])) * 4).round().clamp(1, 1600) / 4;
      recalc(it);
      rescaleSwaps(it);
    });
    final u = unitOf(it);
    showToast(context, '$name in ${u == null ? 'grams' : u['name']}', sub: '$before → ${_portion(_d(it['quantity']), u?['name'] as String?)} · same grams', kind: ToastKind.ok);
  }

  void _removeSwap(Map it, Map s) => _change(() => (it['swaps'] as List).remove(s));

  void _addSwap(Map it, Map row) {
    _change(() {
      (it['swaps'] ??= []).add({
        'food': row['id'],
        'quantity': _d(row['quantity']),
        'unit': row['unit'],
        'unit_name': row['unit_name'],
        'name': row['name'],
        'match': row['match'],
        'grams': _d(row['grams']),
        ...?(row['macros'] as Map?),
        'food_detail': row,
      });
    });
    showToast(context, 'Swap added for $first', sub: '${row['name']} for ${(it['food_detail'] as Map?)?['name'] ?? ''}', kind: ToastKind.ok);
  }

  /// `+ Add a unit in the food library`: a FoodUnit for this food (every plan sees it), then picks it here.
  Future<void> _addUnit(Map it) async {
    final f = (it['food_detail'] as Map?) ?? const {};
    final unit = await _askUnit(context, food: '${f['name'] ?? ''}', foodId: '${f['id'] ?? it['food']}');
    if (unit == null || !mounted) return;
    void put(Map x) {
      if (x['food'] != it['food']) return;
      final fd = x['food_detail'] as Map?;
      if (fd == null) return;
      final us = [...((fd['units'] as List?) ?? const [])];
      if (!us.any((u) => (u as Map)['id'] == unit['id'])) fd['units'] = [...us, unit]..sort((p, q) => _d((p as Map)['grams']).compareTo(_d((q as Map)['grams'])));
    }

    for (final m in draft) {
      for (final o in (m['options'] as List? ?? const []).cast<Map>()) {
        for (final x in (o['items'] as List? ?? const []).cast<Map>()) {
          put(x);
        }
      }
    }
    for (final m in (data['meals'] as List? ?? const []).cast<Map>()) {
      for (final o in (m['options'] as List? ?? const []).cast<Map>()) {
        for (final x in (o['items'] as List? ?? const []).cast<Map>()) {
          put(x);
        }
      }
    }
    if (!(f['units'] as List? ?? const []).any((u) => (u as Map)['id'] == unit['id'])) put(it);
    showToast(context, 'Unit added to ${f['name']}', sub: '${unit['name']} = ${_n(_d(unit['grams']))} g · in the food library', kind: ToastKind.ok);
    _setUnit(it, unit['id']);
  }

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
                        {
                          if (it['id'] != null) 'id': it['id'],
                          'food': it['food'],
                          'quantity': _n(_d(it['quantity'])),
                          'unit': it['unit'],
                          if (it['swaps'] != null)
                            'swaps': [for (final s in swapsOf(it)) {'food': s['food'], 'quantity': _n(_d(s['quantity'])), 'unit': s['unit']}],
                        },
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
    return LayoutBuilder(builder: (context, b) {
      // `.cpm-grid`: meals | 340 panel. Tablet: a narrower panel, and the meal rows drop P / C / F when the
      // meals column gets narrow. Phone: one column, the panel is a bottom sheet.
      final side = !phone && b.maxWidth >= 600;
      final panelW = b.maxWidth >= 1100 ? 340.0 : (b.maxWidth >= 860 ? 320.0 : 280.0);
      final mealsW = side ? b.maxWidth - panelW - 16 : b.maxWidth;
      final macros = !phone && mealsW >= 600;
      // narrow meals column (phone, small tablet): food rows wrap to two lines like the phone board
      final wrap = phone || mealsW < 440;
      final meals = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        for (var i = 0; i < draft.length; i++) _mealCard(i, side, macros, wrap),
        if (draft.isEmpty) AppCard(child: PdEmpty('No meals on ${weekdayFull[sel]} yet. Add the first one.')),
        AppButton('Add meal', icon: AppIcons.plus, expand: true, onPressed: _addMeal),
      ]);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        PlanEditBar(onBack: _cancel, onCancel: _cancel, onReset: custom ? _reset : null, save: 'Save for $first', busy: busy, onSave: () => _save()),
        head,
        _targetCard(),
        side
            ? Row(key: _sideKey, crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
                Expanded(child: meals),
                AnimatedPadding(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.only(top: pick == null ? 0 : _panelTop),
                  child: SizedBox(width: panelW, child: AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: _panel())),
                ),
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
          short: [for (var i = 0; i < 7; i++) _f.format(kcalOn(i).round())],
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
  Widget _mealCard(int mi, bool side, bool macros, bool wrap) {
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
          padding: EdgeInsets.symmetric(horizontal: context.isPhone ? 6 : 8, vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 1, children: [
            for (var ii = 0; ii < its.length; ii++) _foodRow(mi, ii, its[ii] as Map, side, macros, wrap),
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

  /// `.mb-sw`: "1 swap" / "2 swaps" (blue), "No swap" (grey).
  static Widget swapBadge(int n) => Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(color: n > 0 ? AppColors.accentSoft : AppColors.sub, borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
          AppIcon(AppIcons.swap, size: 13, color: n > 0 ? AppColors.accentText : AppColors.muted),
          Text(n == 0 ? 'No swap' : '$n swap${n == 1 ? '' : 's'}', style: AppText.s(11.5, W.w7, color: n > 0 ? AppColors.accentText : AppColors.muted)),
        ]),
      );

  /// `.cp-chd`: the blue "changed for the client" dot.
  static Widget get _dot => Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle));

  /// `.mb-fr`: food tile, name over amount (· Was: … when changed), swaps badge, P / C / F, kcal. On phone the
  /// row wraps: kcal on the first line, swaps and P / C / F under it. Tap: the Portion and swaps panel.
  Widget _foodRow(int mi, int ii, Map it, bool side, bool macros, bool phone) {
    final on = pick == (mi, ii);
    final f = (it['food_detail'] as Map?) ?? const {};
    final was = wasOf(it);
    final nSw = swapsOf(it).length;
    final (c1, c2) = AppColors.mediaTiles[(mi + ii) % 4];
    Widget mac(String l, String k, {bool fixed = true}) {
      final t = Text('$l ${m(it, k).round()}', textAlign: fixed ? TextAlign.right : TextAlign.left, style: AppText.s(12.5, W.w6, color: AppColors.muted, tabular: true));
      return fixed ? SizedBox(width: 48, child: t) : t;
    }

    final kcal = Text('${m(it, 'kcal').round()}', textAlign: TextAlign.right, style: AppText.s(13.5, W.w8, tabular: true));
    final tile = Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c1, c2])),
      child: const AppIcon(AppIcons.apple, size: 16, color: AppColors.mediaFg),
    );
    final name = Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
      Row(spacing: 6, children: [
        if (was != null) _dot,
        Flexible(child: Text('${f['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7))),
      ]),
      Text.rich(
        TextSpan(text: amount(it), children: [
          if (was != null) TextSpan(text: ' · Was: $was', style: AppText.s(12, W.w6, color: AppColors.accentText)),
        ]),
        maxLines: phone ? 3 : 2,
        overflow: TextOverflow.ellipsis,
        style: AppText.s(12, W.w5, color: AppColors.muted),
      ),
    ]);
    return Hover(
      key: _rowKeys.putIfAbsent((mi, ii), GlobalKey.new),
      onTap: () {
        setState(() => pick = (mi, ii));
        if (side) {
          _follow((mi, ii));
        } else {
          _panelSheet();
        }
      },
      builder: (_, h, _) => Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: phone ? 8 : 7),
        decoration: BoxDecoration(
          color: on ? AppColors.accentSoft : (h ? AppColors.hover : null),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? AppColors.pickLine : Colors.transparent),
        ),
        child: phone
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
                Row(spacing: 10, children: [tile, Expanded(child: name), kcal]),
                Padding(
                  padding: const EdgeInsets.only(left: 40),
                  child: Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    swapBadge(nSw),
                    mac('P', 'protein', fixed: false),
                    mac('C', 'carbs', fixed: false),
                    mac('F', 'fat', fixed: false),
                  ]),
                ),
              ])
            : Row(spacing: 12, children: [
                tile,
                Expanded(child: name),
                swapBadge(nSw),
                if (macros) ...[mac('P', 'protein'), mac('C', 'carbs'), mac('F', 'fat')],
                SizedBox(width: macros ? 64 : 44, child: kcal),
              ]),
      ),
    );
  }

  void _panelSheet() => showAppDrawer(
        context,
        title: 'Portion and swaps',
        sub: '${weekdayFull[sel]} · only for $first',
        icon: AppIcons.apple,
        builder: (ctx) => ValueListenableBuilder(
          valueListenable: _tick,
          builder: (_, _, _) => Padding(padding: const EdgeInsets.only(top: 14), child: _panel(onRemoved: () => Navigator.of(ctx).pop(), sheet: true)),
        ),
        footer: (ctx) => [AppButton.primary('Done', expand: true, onPressed: () => Navigator.of(ctx).pop())],
      );

  /// A swap's name (and [badge]) over its amount ("½ katori · 75 g") and what it gives ("82 kcal · P 5 g · C 14 g ·
  /// F 3 g"); [mac] holds kcal / protein / carbs / fat.
  static Widget _swapText(String name, double q, String? unit, double grams, Map mac, {Widget? badge}) {
    final amt = unit == null ? _portion(q, null) : '${_portion(q, unit)} · ${_n(grams)} g';
    final title = Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w7));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
      badge == null ? title : Row(spacing: 8, children: [Flexible(child: title), badge]),
      Text.rich(
        TextSpan(children: [
          TextSpan(text: amt, style: AppText.s(12, W.w7, color: AppColors.text2, tabular: true)),
          TextSpan(text: ' · ${_d(mac['kcal']).round()} kcal'),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.s(12, W.w6, color: AppColors.muted, tabular: true),
      ),
      Text('P ${_d(mac['protein']).round()} g · C ${_d(mac['carbs']).round()} g · F ${_d(mac['fat']).round()} g',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w5, color: AppColors.muted, tabular: true)),
    ]);
  }

  Widget _label(String t, String tip) => Row(spacing: 4, children: [
        Text(t, style: AppText.label),
        AppTooltip(message: tip, child: const Padding(padding: EdgeInsets.all(2), child: AppIcon(AppIcons.info, size: 14, color: AppColors.muted))),
      ]);

  /// `.mb-side` Portion and swaps: the picked food, its amount (− n +) and unit, grams and macros, the swaps the
  /// client may use (`Add alternative`), remove.
  Widget _panel({VoidCallback? onRemoved, bool sheet = false}) {
    final it = _picked;
    final meal = it == null ? null : draft[pick!.$1];
    final title = sheet
        ? null
        : Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 2, children: [
            Text('Portion and swaps', style: AppText.s(14.5, W.w8)),
            if (meal != null) Text('${meal['name']} · ${mealTime(meal['time'])}', style: AppText.cap),
          ]);
    if (it == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        ?title,
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: AppIcon(AppIcons.swap, size: 16, color: AppColors.muted)),
          Expanded(child: Text('Tap a food to change how much $first eats, its unit, or the swaps $she may use.', style: AppText.s(13, W.w5, color: AppColors.muted, h: 1.5))),
        ]),
      ]);
    }
    final f = (it['food_detail'] as Map?) ?? const {};
    final u = unitOf(it);
    final units = unitsOf(it);
    final q = _d(it['quantity']);
    final step = u == null ? 5.0 : .5;
    final was = wasOf(it);
    final swaps = swapsOf(it)..sort((x, y) => _d(y['match']).compareTo(_d(x['match'])));
    final k1 = '${_d(f['kcal']).round()} kcal per 100 g · ${units.length} unit${units.length == 1 ? '' : 's'} + grams';
    final unitSel = Builder(
      builder: (b) => Hover(
        onTap: () => showAppMenu(
            b,
            [
              MenuEntry.header('Units of ${f['name'] ?? ''}'),
              MenuEntry('Grams', selected: u == null, onTap: () => _setUnit(it, null)),
              for (final x in units) MenuEntry('${x['name']}', selected: x['id'] == it['unit'], end: '${_n(_d(x['grams']))} g', onTap: () => _setUnit(it, x['id'])),
              const MenuEntry.separator(),
              MenuEntry('Add a unit in the food library', icon: AppIcons.plus, onTap: () => _addUnit(it)),
            ],
            width: 260),
        builder: (_, h, _) => Container(
          width: 130,
          height: 36,
          padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.input), border: Border.all(color: h ? AppColors.lineHover : AppColors.line2)),
          child: Row(spacing: 6, children: [
            Expanded(child: Text(u == null ? 'Grams' : '${u['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w6))),
            const AppIcon(AppIcons.chevronDown, size: 16, color: AppColors.muted),
          ]),
        ),
      ),
    );
    final addAlt = Builder(
      builder: (b) => Align(
        alignment: Alignment.centerLeft,
        child: AppButton('Add alternative', kind: BtnKind.text, icon: AppIcons.plus, size: BtnSize.sm, onPressed: () => _pickAlternative(b, it)),
      ),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      ?title,
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
            Text(k1, style: AppText.s(12, W.w5, color: AppColors.muted)),
          ]),
        ),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        _label('Amount', 'Changing the unit keeps the same amount in grams. Change the number to give more or less.'),
        Row(spacing: 8, children: [
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.input), border: Border.all(color: AppColors.line2)),
              child: Row(children: [
                AppIconButton(AppIcons.minus, tooltip: 'Less', ghost: true, small: true, onPressed: q - step < (u == null ? 5 : .5) ? null : () => _setQty(it, q - step)),
                Expanded(child: Text(_n(q), textAlign: TextAlign.center, style: AppText.s(14, W.w8, tabular: true))),
                AppIconButton(AppIcons.plus, tooltip: 'More', ghost: true, small: true, onPressed: q + step > (u == null ? 2000 : 20) ? null : () => _setQty(it, q + step)),
              ]),
            ),
          ),
          unitSel,
        ]),
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(8)),
          child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: [
            Text('${_n(_d(it['grams']))} g', style: AppText.s(14, W.w8, tabular: true)),
            Text('${m(it, 'kcal').round()} kcal · P ${m(it, 'protein').round()} g · C ${m(it, 'carbs').round()} g · F ${m(it, 'fat').round()} g',
                style: AppText.s(12, W.w6, color: AppColors.text2, tabular: true)),
          ]),
        ),
        if (was != null)
          Text(was == 'not in the master' ? 'Added for $first. Not in the master plan.' : 'Was $was in the master plan.', style: AppText.s(12, W.w5, color: AppColors.muted, h: 1.5)),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('Swaps $first may use', '${she[0].toUpperCase()}${she.substring(1)} can eat one of these instead. The amount gives about the same calories.'),
        const SizedBox(height: 4),
        for (var i = 0; i < swaps.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              Expanded(
                child: _swapText('${swaps[i]['name']}', _d(swaps[i]['quantity']), swaps[i]['unit'] == null ? null : '${swaps[i]['unit_name']}', _d(swaps[i]['grams']), swaps[i],
                    badge: _MatchBadge(_d(swaps[i]['match']).round())),
              ),
              AppIconButton(AppIcons.close, tooltip: 'Remove', ghost: true, small: true, onPressed: () => _removeSwap(it, swaps[i])),
            ]),
          ),
        if (swaps.isEmpty) Text('No swaps. $first has to eat this food.', style: AppText.s(12, W.w5, color: AppColors.muted, h: 1.5)),
        const SizedBox(height: 4),
        addAlt,
      ]),
      Align(
        alignment: Alignment.centerLeft,
        child: _DangerText('Remove from this meal', onTap: () {
          _removeFood(pick!.$1, pick!.$2);
          onRemoved?.call();
        }),
      ),
    ]);
  }

  /// `Add alternative` → `.nu-swm` Pick an alternative: Same group / All foods, rows with amount · kcal · P and
  /// match %; amounts give the same calories as the food's amount. A bottom sheet on phone.
  Future<void> _pickAlternative(BuildContext anchor, Map it) async {
    final f = (it['food_detail'] as Map?) ?? const {};
    final scope = ValueNotifier('group');
    final por = _portion(_d(it['quantity']), unitOf(it)?['name'] as String?);
    final cache = <String, Future<List<Map>>>{};
    Future<List<Map>> load(String s) => cache[s] ??= Services.api.get<List>('foods/${f['id'] ?? it['food']}/swap-options/', query: {
          'scope': s,
          'grams': _n(_d(it['grams'])),
          'client_diet': '${data['diet'] ?? ''}',
          'exclude': [for (final x in swapsOf(it)) x['food']].join(','),
        }).then((r) => [for (final x in r) x as Map]);
    Widget body(VoidCallback close) => ValueListenableBuilder(
          valueListenable: scope,
          // Header and footnote stay put; only the rows scroll, so the popover (or sheet) never runs off the window.
          builder: (_, s, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
              child: Row(spacing: 8, children: [
                Expanded(child: Text('Pick an alternative', style: AppText.s(13, W.w7))),
                SegmentedTabs(height: 28, items: const [TabItem('group', 'Same group'), TabItem('all', 'All foods')], value: s, onChanged: (v) => scope.value = v),
              ]),
            ),
            Flexible(
              child: FutureBuilder<List<Map>>(
                future: load(s),
                builder: (_, snap) {
                  if (snap.hasError) return Padding(padding: const EdgeInsets.all(12), child: Text('Could not load the foods', style: AppText.s(12.5, W.w5, color: AppColors.muted)));
                  if (!snap.hasData) return const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))));
                  final rows = snap.data!;
                  if (rows.isEmpty) return Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), child: Text('No other foods in this group.', style: AppText.s(12.5, W.w5, color: AppColors.muted)));
                  return SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 2, children: [
                      for (final (i, r) in rows.indexed)
                        Hover(
                          onTap: () {
                            close();
                            _addSwap(it, r);
                          },
                          builder: (_, h, _) {
                            final (c1, c2) = AppColors.mediaTiles['${r['name']}'.length % 4];
                            final mac = (r['macros'] as Map?) ?? const {};
                            return Container(
                              constraints: const BoxConstraints(minHeight: 56),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              decoration: BoxDecoration(color: h ? AppColors.sub : null, borderRadius: AppRadius.all(AppRadius.item)),
                              child: Row(spacing: 10, children: [
                                Container(
                                  key: ValueKey('alt$i'),
                                  width: 32,
                                  height: 32,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c1, c2])),
                                  child: const AppIcon(AppIcons.apple, size: 16, color: AppColors.mediaFg),
                                ),
                                Expanded(child: _swapText('${r['name']}', _d(r['quantity']), r['unit'] == null ? null : '${r['unit_name']}', _d(r['grams']), mac)),
                                _MatchPill(_d(r['match']).round()),
                              ]),
                            );
                          },
                        ),
                    ]),
                  );
                },
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
              child: Text('Amounts give the same calories as $por.', style: AppText.s(11.5, W.w6, color: AppColors.muted)),
            ),
          ]),
        );
    if (anchor.isPhone) {
      await showAppSheet(context, title: 'Swap for ${f['name'] ?? ''}', sub: '${draft[pick!.$1]['name']} · only for $first', fixedBody: true, builder: (ctx) => body(() => Navigator.of(ctx).pop()));
    } else {
      await _popover(anchor, width: 400, alignRight: true, builder: (close) => body(close));
    }
    scope.dispose();
  }
}

/// `.badge.plain` "74% match" on a swap row (b-ok from 80 %, else b-warn).
class _MatchBadge extends StatelessWidget {
  const _MatchBadge(this.match);
  final int match;
  @override
  Widget build(BuildContext context) {
    final t = _matchTone(match);
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: t.bg, borderRadius: AppRadius.all(AppRadius.badge)),
      child: Text('$match% match', style: AppText.s(11, W.w7, color: t.fg)),
    );
  }
}

/// `.nu-mt` match pill in Pick an alternative: hi (≥ 85 %) green, mid (≥ 65 %) blue, lo grey.
class _MatchPill extends StatelessWidget {
  const _MatchPill(this.match);
  final int match;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = match >= 85 ? (AppColors.okBg, AppColors.okText) : (match >= 65 ? (AppColors.infoBg, AppColors.infoText) : (AppColors.sub, AppColors.muted));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text('$match% match', style: AppText.s(11.5, W.w7, color: fg)),
    );
  }
}

/// `.btn.text.danger`: red text button with a trash icon.
class _DangerText extends StatelessWidget {
  const _DangerText(this.label, {required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: h ? AppColors.badBg : null, borderRadius: AppRadius.all(AppRadius.btn)),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
            const AppIcon(AppIcons.trash, size: 15, color: AppColors.badText),
            Text(label, style: AppText.s(13, W.w7, color: AppColors.badText)),
          ]),
        ),
      );
}

/// A `.menu`-style popover under (or above) [anchor], [width] wide, closed by a tap outside. [alignRight]: its
/// right edge lines up with the anchor's (`.mb-swa .row-menu { right: 0 }`).
Future<void> _popover(BuildContext anchor, {required double width, bool alignRight = false, required Widget Function(VoidCallback close) builder}) {
  final box = anchor.findRenderObject() as RenderBox;
  final overlay = Overlay.of(anchor, rootOverlay: true).context.findRenderObject() as RenderBox;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final size = overlay.size;
  // The anchor clamped to the window (it can sit partly outside it after a scroll).
  final aTop = topLeft.dy.clamp(0.0, size.height), aBottom = (topLeft.dy + box.size.height).clamp(0.0, size.height);
  final below = aBottom + 4;
  final roomBelow = size.height - below - 12, roomAbove = aTop - 4 - 12;
  final up = roomBelow < 360 && roomAbove > roomBelow;
  // Neither side has room for a useful list (short window): pin it inside the window instead; it scrolls inside.
  final pin = (up ? roomAbove : roomBelow) < 220;
  final maxH = pin ? math.min(520.0, size.height - 24) : math.min(520.0, up ? roomAbove : roomBelow);
  return showGeneralDialog(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: 'popover',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 90),
    pageBuilder: (ctx, _, _) => Stack(children: [
      Positioned(
        left: (alignRight ? topLeft.dx + box.size.width - width : topLeft.dx).clamp(8, size.width - width - 8),
        top: pin ? (size.height - maxH) / 2 : (up ? null : below),
        bottom: !pin && up ? size.height - aTop + 4 : null,
        width: width,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(8),
            constraints: BoxConstraints(maxHeight: maxH),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.menu), border: Border.all(color: AppColors.line), boxShadow: AppShadows.menu),
            child: builder(() => Navigator.of(ctx).pop()),
          ),
        ),
      ),
    ]),
    transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  );
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

/// `+ Add a unit in the food library`: name ("1 bowl") and its grams. Saves it to the food (POST
/// `foods/<id>/units/`) and gives back the new unit.
Future<Map?> _askUnit(BuildContext context, {required String food, required String foodId}) {
  final name = TextEditingController(), grams = TextEditingController();
  final err = ValueNotifier<(String?, String?)>((null, null));
  final busy = ValueNotifier(false);
  Future<void> done(BuildContext ctx) async {
    final n = name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final g = double.tryParse(grams.text.trim().replaceAll(',', '.'));
    if (n.isEmpty || g == null || g < .1 || g > 5000) {
      err.value = (n.isEmpty ? 'Name the unit, e.g. 1 bowl.' : null, g == null || g < .1 || g > 5000 ? 'Enter the grams, 0.1 to 5,000.' : null);
      return;
    }
    busy.value = true;
    try {
      final r = await Services.api.post<Map>('foods/$foodId/units/', {'name': n, 'grams': _n(g)});
      if (ctx.mounted) Navigator.of(ctx).pop(r);
    } on ApiError catch (e) {
      busy.value = false;
      err.value = (e.field('name') ?? e.message, e.field('grams'));
    }
  }

  return showAppModal<Map>(
    context,
    title: 'Add a unit of $food',
    icon: AppIcons.plus,
    content: (ctx) => ValueListenableBuilder(
      valueListenable: err,
      builder: (_, e, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        Text('Every meal plan can use it. 1 g is always there.', style: AppText.s(13, W.w5, color: AppColors.muted)),
        AppTextField(label: 'Unit name', controller: name, autofocus: true, placeholder: '1 bowl, 1 katori, 1 slice…', error: e.$1),
        AppTextField(label: 'Grams in one', controller: grams, placeholder: '150', keyboard: const TextInputType.numberWithOptions(decimal: true), error: e.$2, onSubmitted: (_) => done(ctx)),
      ]),
    ),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      ValueListenableBuilder(
        valueListenable: busy,
        builder: (_, b, _) => AppButton.primary('Add unit', icon: AppIcons.check, loading: b, expand: ctx.isPhone, onPressed: b ? null : () => done(ctx)),
      ),
    ],
  ).whenComplete(() => disposeLater([name, grams, err, busy]));
}

/// `Add food` (`.pb-pk` with `.mb-pr` rows): the team's food library that fits the plan's diet, most protein
/// first. Search and the group chips stay fixed; only the list scrolls. `Add` puts a food in the meal at once
/// (it then shows `Added`); `Done` closes.
Future<void> showFoodPicker(
  BuildContext context, {
  required String meal,
  required String first,
  required String diet,
  String dietLabel = '',
  required Set<String> Function() added,
  required ValueChanged<Map> onAdd,
  required ValueChanged<Map> onRemove,
}) {
  final group = ValueNotifier('');
  final q = ValueNotifier('');
  // Foods added / taken out while the drawer is open (the footer count); `n` redraws the rows and the footer.
  final n = ValueNotifier(0);
  final addedNow = <String>{}, removedNow = <String>{};
  final search = TextEditingController();
  const fits = {'veg': ['veg', 'vegan'], 'egg': ['veg', 'vegan', 'egg'], 'vegan': ['vegan']};
  final all = Services.api.get<List>('food-picker/').then((r) => [
        for (final x in r)
          if (fits[diet] == null || fits[diet]!.contains((x as Map)['diet'])) x as Map,
      ]..sort((x, y) => _servingProtein(y).compareTo(_servingProtein(x))));
  const groups = [('', 'All'), ('protein', 'Protein'), ('carbs', 'Carbs'), ('fats', 'Fats'), ('veg', 'Veg'), ('fruits', 'Fruits'), ('dairy', 'Dairy'), ('indian', 'Indian dishes'), ('beverages', 'Drinks'), ('mine', 'My foods')];
  bool inGroup(Map x, String g) => g.isEmpty || (g == 'mine' ? x['team'] == true : x['group'] == g);
  return showAppDrawer<void>(
    context,
    title: 'Add to $meal',
    sub: 'Food library · only for $first',
    icon: AppIcons.apple,
    fixedBody: true,
    builder: (ctx) => FutureBuilder<List<Map>>(
      future: all,
      builder: (ctx, snap) {
        if (snap.hasError) return const EmptyState('Could not load the foods');
        if (!snap.hasData) return const CpLoading();
        final list = snap.data!;
        return ListenableBuilder(
          listenable: Listenable.merge([group, q, n]),
          builder: (ctx, _) {
            final rows = list.where((x) => inGroup(x, group.value) && (q.value.isEmpty || '${x['name']} ${x['brand'] ?? ''}'.toLowerCase().contains(q.value))).toList();
            final inMeal = added();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 14),
              AppSearchField(controller: search, placeholder: 'Search paneer, dal, chicken…', onChanged: (v) => q.value = v.trim().toLowerCase()),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(spacing: 6, children: [
                  for (final (k, l) in groups)
                    if (k.isEmpty || list.any((x) => inGroup(x, k)))
                      FilterChipX(l, selected: group.value == k, count: list.where((x) => inGroup(x, k)).length, onTap: () => group.value = k),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                child: Row(spacing: 8, children: [
                  Text('${rows.length} food${rows.length == 1 ? '' : 's'}', style: AppText.s(12, W.w6, color: AppColors.muted)),
                  Expanded(
                    child: Text('Most protein first${dietLabel.isEmpty || fits[diet] == null ? '' : ' · ${dietLabel.toLowerCase()} foods for $first'}',
                        textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w6, color: AppColors.muted)),
                  ),
                ]),
              ),
              Expanded(
                child: rows.isEmpty
                    ? const Align(alignment: Alignment.topCenter, child: EmptyState('No foods match'))
                    : ListView.separated(
                        padding: const EdgeInsets.only(top: 2, bottom: 12),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const Divider(height: 1, thickness: 1, color: AppColors.line),
                        itemBuilder: (_, i) {
                          final id = '${rows[i]['id']}';
                          return _FoodPickRow(
                            x: rows[i],
                            added: inMeal.contains(id),
                            onAdd: () {
                              onAdd(rows[i]);
                              if (!removedNow.remove(id)) addedNow.add(id);
                              n.value++;
                            },
                            // `✓ Added` is a toggle: a food added by mistake comes out again.
                            onRemove: () {
                              onRemove(rows[i]);
                              if (!addedNow.remove(id)) removedNow.add(id);
                              n.value++;
                            },
                          );
                        },
                      ),
              ),
            ]);
          },
        );
      },
    ),
    footer: (ctx) => [
      ValueListenableBuilder(
        valueListenable: n,
        builder: (_, v, _) {
          final t = Text([if (addedNow.isNotEmpty) '${addedNow.length} added', if (removedNow.isNotEmpty) '${removedNow.length} removed'].join(' · '), style: AppText.cap);
          return ctx.isPhone ? t : Expanded(child: t);
        },
      ),
      AppButton.primary('Done', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
    ],
  ).whenComplete(() => disposeLater([group, q, n, search]));
}

/// Protein in one default serving (the picker's "Most protein first").
double _servingProtein(Map x) {
  final du = x['default_unit'] as Map?;
  final g = du?['id'] == null ? 100.0 : _d(du!['grams']) * _d(x['default_quantity']).clamp(0.25, 99);
  return _d(x['protein']) * g / 100;
}

/// `.mb-pr`: food tile, name (+ Team), "1 katori · 185 kcal · P 4 g · C 38 g · F 2 g", `Add` or `✓ Added`.
class _FoodPickRow extends StatelessWidget {
  const _FoodPickRow({required this.x, required this.added, required this.onAdd, required this.onRemove});
  final Map x;
  final bool added;
  final VoidCallback onAdd, onRemove;

  @override
  Widget build(BuildContext context) {
    final du = x['default_unit'] as Map?;
    final noUnit = du?['id'] == null;
    final g = noUnit ? 100.0 : _d(du!['grams']) * _d(x['default_quantity']).clamp(0.25, 99);
    double per(String k) => _d(x[k]) * g / 100;
    final serv = noUnit ? '100 g' : _portion(_d(x['default_quantity']).clamp(0.25, 99), '${du!['name']}');
    final (c1, c2) = AppColors.mediaTiles['${x['name']}'.length % 4];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(spacing: 10, children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c1, c2])),
          child: const AppIcon(AppIcons.apple, size: 16, color: AppColors.mediaFg),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
            Row(spacing: 6, children: [
              Flexible(child: Text('${x['name']}${'${x['brand'] ?? ''}'.isEmpty ? '' : ' · ${x['brand']}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7))),
              if (x['team'] == true)
                Container(
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: AppRadius.all(AppRadius.badge)),
                  child: Text('Team', style: AppText.s(10.5, W.w7, color: AppColors.infoText)),
                ),
            ]),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: serv, style: AppText.s(12, W.w7, color: AppColors.text2)),
                TextSpan(text: ' · ${per('kcal').round()} kcal · P ${per('protein').round()} g · C ${per('carbs').round()} g · F ${per('fat').round()} g'),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.s(12, W.w5, color: AppColors.muted),
            ),
          ]),
        ),
        if (added)
          // `✓ Added` toggles back: hover shows `Remove` (web), a tap takes the food out of the meal again.
          Hover(
            onTap: onRemove,
            builder: (_, h, _) => Container(
              height: 30,
              constraints: const BoxConstraints(minWidth: 82),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(color: h ? AppColors.badBg : null, borderRadius: AppRadius.all(AppRadius.btn)),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, spacing: 4, children: [
                AppIcon(h ? AppIcons.close : AppIcons.check, size: 14, color: h ? AppColors.badText : AppColors.okText, stroke: 2.4),
                Text(h ? 'Remove' : 'Added', style: AppText.s(12.5, W.w7, color: h ? AppColors.badText : AppColors.okText)),
              ]),
            ),
          )
        else
          AppButton('Add', icon: AppIcons.plus, size: BtnSize.sm, onPressed: onAdd),
      ]),
    );
  }
}
