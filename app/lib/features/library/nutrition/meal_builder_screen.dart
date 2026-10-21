import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../app/shell/page.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/leave/leave_guard.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tabs.dart';
import '../../../core/widgets/tooltip.dart';
import '../../trainer/client_profile/cp_plans_meal_edit.dart'
    show DangerText, MatchBadge, MatchPill, MealItemMath, askFoodUnit, portionLabel, showFoodPicker, showPopover;
import '../lib_common.dart';
import '../programs/builder_sheets.dart' show showNameModal;
import 'meal_builder_model.dart';
import 'meal_builder_sheets.dart';
import 'nu_common.dart';
import 'nutrition_screen.dart' show nutritionChanged;

/// Meal plan builder (boards `MealPlanBuilder` / `MealPlanBuilderMobile`): the daily targets against what the
/// meals add up to, one card per meal with its options (the client picks one) and foods, and beside them the
/// Portion and swaps panel for the picked food, the clients on the plan and the client permissions. Changes are
/// a draft until Publish (D-44); leaving with a draft asks first. People who may not change the plan see it
/// read-only with Duplicate to edit.
class MealPlanBuilderScreen extends StatefulWidget {
  const MealPlanBuilderScreen({super.key, required this.id, this.open});
  final String id;

  /// From a plan card menu: 'assign' (Assign to clients) or 'clients' (Clients on this plan).
  final String? open;
  @override
  State<MealPlanBuilderScreen> createState() => _MealPlanBuilderScreenState();
}

double _d(Object? v) => nd(v);

class _MealPlanBuilderScreenState extends State<MealPlanBuilderScreen> {
  late final m = MealBuilderModel(widget.id);
  List<Map>? _clients;

  @override
  void initState() {
    super.initState();
    LeaveGuard.register(this, _askLeave);
    m.addListener(_syncTab);
    m.load().then((_) {
      if (!mounted) return;
      _loadClients();
      if (widget.open == 'assign' && m.canAssign) _assign();
      if (widget.open == 'clients') _manage();
    });
  }

  @override
  void dispose() {
    LeaveGuard.unregister(this);
    m.dispose();
    // After this frame: the Nutrition page under it may not change while the tree is being torn down.
    Future.microtask(() => nutritionChanged.value++);
    super.dispose();
  }

  bool get _edit => m.canEdit;

  Future<void> _loadClients() async {
    try {
      final r = await Services.api.get<List>('meal-plans/${m.id}/clients/');
      if (mounted) setState(() => _clients = [for (final x in r) x as Map]);
    } on ApiError catch (_) {
      if (mounted) setState(() => _clients ??= []);
    }
  }

  Future<void> _run(Future<void> Function() f, {String fail = 'Could not do that'}) async {
    try {
      await f();
    } on ApiError catch (e) {
      if (mounted) showToast(context, fail, sub: e.message, kind: ToastKind.err);
    }
  }

  /// Applies [f] to the draft; the toast's Undo puts the draft back.
  void _change(void Function() f, {String? toast, String? sub, bool undo = true}) {
    final snap = m.snapshot();
    final keep = m.sel;
    m.edit(f);
    if (toast != null && mounted) {
      showToast(context, toast, sub: sub, action: undo ? 'Undo' : null, onAction: undo
          ? () {
              m.restore(snap);
              m.sel = keep;
              if (m.picked == null) m.sel = null;
            }
          : null);
    }
  }

  // ─────────────────────────────── publish / leave (D-43, D-44)

  bool _tabWarn = false;

  void _syncTab() {
    if (_tabWarn == m.unsaved) return;
    _tabWarn = m.unsaved;
    LeaveGuard.unsaved(m.unsaved);
  }

  Future<bool> _publish({bool ask = true}) async {
    if (ask && !await showPublishModal(context, m)) return false;
    final n = await m.publish();
    if (!mounted) return n != null;
    if (n == null) {
      showToast(context, 'Could not publish', sub: m.saveError?.message, kind: ToastKind.err);
      return false;
    }
    showToast(context, 'Plan published', sub: n > 0 ? 'Sent to ${plural(n, 'client')}' : 'Ready to assign');
    return true;
  }

  Future<void> _discard() async {
    final ok = await confirmAction(context,
        title: 'Discard your changes?', body: 'The plan goes back to how it was when it was last published.', confirm: 'Discard', danger: true, icon: AppIcons.undo);
    if (!ok || !mounted) return;
    _run(() async {
      await m.discard();
      if (mounted) showToast(context, 'Changes discarded', sub: m.name);
    }, fail: 'Could not discard');
  }

  Future<bool> _askLeave(BuildContext context) async {
    if (!m.unsaved) return true;
    final r = await showAppModal<String>(
      context,
      title: 'Publish your changes?',
      body: 'You changed ${m.name}. Clients on it only get the changes after you publish.',
      icon: AppIcons.alert,
      actions: (ctx) => [
        AppButton('Cancel', onPressed: () => Navigator.of(ctx).pop(), expand: ctx.isPhone),
        AppButton("Don't publish", kind: BtnKind.danger, onPressed: () => Navigator.of(ctx).pop('drop'), expand: ctx.isPhone),
        AppButton.primary('Publish', onPressed: () => Navigator.of(ctx).pop('save'), expand: ctx.isPhone),
      ],
    );
    if (r == 'drop') {
      m.unsaved = false;
      _syncTab();
      return true;
    }
    if (r == 'save') return _publish(ask: false);
    return false;
  }

  // ─────────────────────────────── plan actions

  Future<void> _rename() async {
    final v = await showNameModal(context, title: 'Rename plan', sub: 'Clients see the new name', label: 'Plan name', initial: m.name, placeholder: 'e.g. Cut · Eggetarian', button: 'Save name');
    if (v == null || v == m.name) return;
    _run(() async {
      await m.rename(v);
      if (mounted) showToast(context, 'Plan renamed', sub: v);
    }, fail: 'Could not rename it');
  }

  void _duplicate() => _run(() async {
        final c = await Services.api.post<Map>('meal-plans/${m.id}/duplicate/');
        if (!mounted) return;
        if (m.unsaved) {
          m.unsaved = false; // the copy is of the published plan; the draft here is dropped on the way out
          _syncTab();
        }
        context.go('/nutrition/${c['id']}');
        showToast(context, 'Plan duplicated', sub: '${c['name']} · same meals, no clients');
      }, fail: 'Could not duplicate it');

  Future<void> _delete() async {
    int n = 0;
    try {
      n = ((await Services.api.get<Map>('meal-plans/${m.id}/delete-preview/'))['clients'] as num?)?.toInt() ?? 0;
    } on ApiError catch (_) {}
    if (!mounted) return;
    final ok = await confirmAction(context,
        title: 'Delete this plan?',
        body: '${m.name} is removed for good${n > 0 ? ' and taken off ${plural(n, 'client')}' : ''}. Meals they already logged stay.',
        confirm: 'Delete',
        danger: true,
        icon: AppIcons.trash);
    if (!ok || !mounted) return;
    final name = m.name, id = m.id;
    _run(() async {
      m.unsaved = false;
      _syncTab();
      await Services.api.delete('meal-plans/$id/');
      if (!mounted) return;
      final router = GoRouter.of(context);
      router.go('/nutrition');
      showToast(context, 'Plan deleted', sub: name, action: 'Undo', onAction: () async {
        try {
          await Services.api.post('meal-plans/$id/restore/');
          router.go('/nutrition/$id');
        } on ApiError catch (_) {}
      });
    }, fail: 'Could not delete it');
  }

  void _planMenu(BuildContext anchor) => showAppMenu(anchor, width: 240, [
        MenuEntry.header(m.name),
        if (_edit) MenuEntry('Rename plan', icon: AppIcons.edit, onTap: _rename),
        if (_edit) MenuEntry('Edit targets', icon: AppIcons.target, sub: 'Calories, protein, carbs, fat, fibre, water', onTap: _editTargets),
        if (_edit) MenuEntry('Add meal', icon: AppIcons.plus, onTap: _addMeal),
        if (m.canAssign) MenuEntry('Assign to clients', icon: AppIcons.assign, onTap: _assign),
        MenuEntry('Clients on this plan', icon: AppIcons.clientsAlt, sub: m.clientCount == 0 ? 'Not assigned yet' : plural(m.clientCount, 'client'), onTap: _manage),
        if (m.canCreate) MenuEntry(_edit ? 'Duplicate plan' : 'Duplicate to edit', icon: AppIcons.copy, sub: 'Same meals, no clients', onTap: _duplicate),
        if (_edit && m.unsaved) MenuEntry('Discard changes', icon: AppIcons.undo, sub: 'Back to the published plan', onTap: _discard),
        if (_edit) const MenuEntry.separator(),
        if (_edit) MenuEntry('Delete plan', icon: AppIcons.trash, danger: true, onTap: _delete),
      ]);

  Future<void> _assign() async {
    final r = await showMealAssignModal(context, m);
    if (r == null || !mounted) return;
    await m.reload();
    await _loadClients();
    if (!mounted) return;
    final n = m.clientCount;
    showToast(context, n > 0 ? 'Plan assigned' : 'Plan unassigned',
        sub: n > 0 ? '${plural(n, 'client')} on ${m.name}' : '${r.$2} removed',
        action: 'Undo',
        onAction: () => _run(() async {
              await Services.api.post('meal-plans/${m.id}/assign/', {'clients': r.$3});
              await m.reload();
              await _loadClients();
            }));
  }

  Future<void> _manage() async {
    final go = await showMealClientsDrawer(context, m, changed: () {
      m.reload();
      _loadClients();
    });
    if (go == true && mounted) _assign();
  }

  // ─────────────────────────────── meals

  String _kcalL(num v) => kfmt(v);

  Future<void> _addMeal() async {
    final r = await showMealModal(context);
    if (r == null || !mounted) return;
    _change(() {
      final meal = {'name': r['name'], 'time': '${r['time']}:00', 'kcal_target': r['kcal_target'], 'options': [{'name': 'Option A', 'is_default': true, 'items': []}]};
      final i = m.meals.indexWhere((x) => '${x['time']}'.compareTo('${meal['time']}') > 0);
      m.meals.insert(i < 0 ? m.meals.length : i, meal);
      m.sel = null;
    }, toast: 'Meal added', sub: '${r['name']} · ${mealTimeLabel(r['time'])}');
  }

  Future<void> _editMeal(Map meal) async {
    final r = await showMealModal(context, meal: meal);
    if (r == null || !mounted) return;
    _change(() {
      meal['name'] = r['name'];
      meal['time'] = '${r['time']}:00';
      meal['kcal_target'] = r['kcal_target'];
      final keep = m.sel == null ? null : m.meals[m.sel!.$1];
      m.meals.sort((a, b) => '${a['time']}'.compareTo('${b['time']}'));
      if (keep != null) m.sel = (m.meals.indexOf(keep), m.sel!.$2, m.sel!.$3);
    }, toast: '${r['name']} saved', sub: 'Target ${_kcalL(r['kcal_target'] as num)} kcal');
  }

  Future<void> _deleteMeal(Map meal) async {
    final n = m.optionsOf(meal).length;
    final ok = await confirmAction(context,
        title: 'Delete ${'${meal['name']}'.toLowerCase()}?',
        body: 'All ${plural(n, 'option')} of this meal are removed for every client on the plan.',
        confirm: 'Delete',
        danger: true,
        icon: AppIcons.trash);
    if (!ok || !mounted) return;
    _change(() {
      m.meals.remove(meal);
      m.sel = null;
    }, toast: '${meal['name']} deleted');
  }

  void _mealMenu(BuildContext anchor, Map meal) => showAppMenu(anchor, width: 250, [
        MenuEntry.header('${meal['name']}'),
        MenuEntry('Edit meal', icon: AppIcons.edit, sub: 'Name, time and calorie target', onTap: () => _editMeal(meal)),
        const MenuEntry.separator(),
        MenuEntry('Delete meal', icon: AppIcons.trash, danger: true, onTap: () => _deleteMeal(meal)),
      ]);

  // ─────────────────────────────── options

  List _optList(Map meal) => (meal['options'] as List?) ?? (meal['options'] = []);

  void _addOption(Map meal, {required bool copy}) {
    final os = _optList(meal);
    final cur = m.optionsOf(meal)[m.shownOf(meal)];
    final n = os.length;
    _change(() {
      os.add(copy
          ? {'name': '${cur['name']} copy', 'is_default': false, 'items': [for (final it in m.itemsOf(cur)) _copyItem(it)]}
          : {'name': 'Option ${String.fromCharCode(65 + n)}', 'is_default': false, 'items': []});
      meal['_oi'] = n;
      m.sel = null;
    }, toast: copy ? 'Option duplicated' : 'Blank option added', sub: copy ? 'Copy of ${cur['name']}' : 'Use Add food to open the food library');
  }

  Map _copyItem(Map it) {
    final c = Map.of(it)..remove('id');
    c['swaps'] = [for (final s in MealItemMath.swapsOf(it)) Map.of(s)];
    c['macros'] = Map.of((it['macros'] as Map?) ?? const {});
    return c;
  }

  void _addOptionMenu(BuildContext anchor, Map meal) {
    final cur = m.optionsOf(meal)[m.shownOf(meal)];
    showAppMenu(anchor, width: 260, [
      MenuEntry.header('Add option to ${meal['name']}'),
      MenuEntry('Blank', icon: AppIcons.plus, sub: 'Empty option, add the foods yourself', onTap: () => _addOption(meal, copy: false)),
      MenuEntry('Duplicate current option', icon: AppIcons.copy, sub: 'Copy of ${cur['name']}', onTap: () => _addOption(meal, copy: true)),
    ]);
  }

  Future<void> _renameOption(Map meal, Map o) async {
    final v = await showNameModal(context, title: 'Rename ${o['name']}', sub: '${meal['name']}', label: 'Option name', initial: '${o['name']}', placeholder: 'Veg, Non-veg, Eating out…', button: 'Save name');
    if (v == null || !mounted) return;
    _change(() => o['name'] = v, toast: 'Option renamed', sub: '${meal['name']} · $v', undo: false);
  }

  void _optionMenu(BuildContext anchor, Map meal) {
    final i = m.shownOf(meal);
    final os = _optList(meal);
    final o = os[i] as Map;
    final def = o['is_default'] == true;
    showAppMenu(anchor, width: 250, [
      MenuEntry.header('${o['name']}'),
      MenuEntry('Rename', icon: AppIcons.edit, onTap: () => _renameOption(meal, o)),
      MenuEntry('Duplicate', icon: AppIcons.copy, sub: 'Same foods, new option', onTap: () => _addOption(meal, copy: true)),
      if (!def)
        MenuEntry('Set as default', icon: AppIcons.check, sub: 'The client sees this one first', onTap: () => _change(() {
              for (final x in os) {
                (x as Map)['is_default'] = x == o;
              }
            }, toast: '${o['name']} is the default', sub: 'The client sees this one first', undo: false)),
      const MenuEntry.separator(),
      MenuEntry('Delete option', icon: AppIcons.trash, danger: true, onTap: () {
        if (os.length < 2) {
          showToast(context, 'A meal needs at least one option', sub: 'Delete the meal instead', kind: ToastKind.err);
          return;
        }
        _change(() {
          os.removeAt(i);
          if (def) (os.first as Map)['is_default'] = true;
          meal['_oi'] = 0;
          m.sel = null;
        }, toast: 'Option deleted', sub: '${o['name']}');
      }),
    ]);
  }

  // ─────────────────────────────── foods

  Future<void> _addFood(int mi) async {
    final meal = m.meals[mi];
    final oi = m.shownOf(meal);
    final opt = m.optionsOf(meal)[oi];
    await showFoodPicker(
      context,
      meal: '${meal['name']}',
      first: '',
      diet: m.diet,
      dietLabel: dietPlan[m.diet] ?? '',
      sub: 'Food library · option ${opt['name']}',
      added: () => {for (final it in m.itemsOf(opt)) '${it['food']}'},
      onAdd: (f) {
        if (!mounted) return;
        final du = f['default_unit'] as Map?;
        final it = {'food': f['id'], 'food_detail': f, 'unit': du?['id'], 'quantity': du?['id'] == null ? 100 : _d(f['default_quantity']).clamp(0.25, 99), 'swaps': []};
        MealItemMath.recalc(it);
        _change(() {
          ((opt['items'] ??= []) as List).add(it);
          m.sel = (m.meals.indexOf(meal), oi, m.itemsOf(opt).length - 1);
        });
        showToast(context, 'Added ${f['name']}', sub: '${meal['name']} · ${opt['name']}');
      },
      onRemove: (f) {
        if (!mounted) return;
        final list = (opt['items'] as List?) ?? [];
        final ii = list.lastIndexWhere((x) => '${(x as Map)['food']}' == '${f['id']}');
        if (ii < 0) return;
        _change(() {
          list.removeAt(ii);
          m.sel = null;
        });
      },
    );
  }

  void _removeFood() {
    final s = m.sel, it = m.picked;
    if (s == null || it == null) return;
    final meal = m.meals[s.$1];
    _change(() {
      ((m.optionsOf(meal)[s.$2]['items']) as List).removeAt(s.$3);
      m.sel = null;
    }, toast: 'Removed from ${meal['name']}', sub: '${(it['food_detail'] as Map?)?['name'] ?? ''}');
  }

  void _setQty(Map it, double q) => _change(() {
        it['quantity'] = q;
        MealItemMath.recalc(it);
        MealItemMath.rescaleSwaps(it);
      });

  void _setUnit(Map it, Object? unitId) {
    final name = '${(it['food_detail'] as Map?)?['name'] ?? ''}';
    final before = portionLabel(_d(it['quantity']), MealItemMath.unitOf(it)?['name'] as String?);
    _change(() {
      final g = _d(it['grams']);
      it['unit'] = unitId;
      final u = MealItemMath.unitOf(it);
      it['quantity'] = u == null ? ((g / 5).round() * 5).clamp(5, 2000).toDouble() : ((g / _d(u['grams'])) * 2).round().clamp(1, 40) / 2;
      MealItemMath.recalc(it);
      MealItemMath.rescaleSwaps(it);
    });
    final u = MealItemMath.unitOf(it);
    showToast(context, '$name in ${u == null ? 'grams' : u['name']}', sub: '$before → ${portionLabel(_d(it['quantity']), u?['name'] as String?)}');
  }

  Future<void> _addUnit(Map it) async {
    final f = (it['food_detail'] as Map?) ?? const {};
    final unit = await askFoodUnit(context, food: '${f['name'] ?? ''}', foodId: '${f['id'] ?? it['food']}');
    if (unit == null || !mounted) return;
    // every row of this food in the plan gets the new unit in its list
    for (final meal in m.meals) {
      for (final o in m.optionsOf(meal)) {
        for (final x in m.itemsOf(o)) {
          final fd = x['food_detail'] as Map?;
          if (x['food'] != it['food'] || fd == null) continue;
          final us = [...((fd['units'] as List?) ?? const [])];
          if (!us.any((u) => (u as Map)['id'] == unit['id'])) fd['units'] = [...us, unit];
        }
      }
    }
    showToast(context, 'Unit added to ${f['name']}', sub: '${unit['name']} = ${fq(_d(unit['grams']))} g · in the food library');
    _setUnit(it, unit['id']);
  }

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
    }, toast: 'Alternative added', sub: '${row['name']} for ${(it['food_detail'] as Map?)?['name'] ?? ''}', undo: false);
  }

  /// `Add alternative` → Pick an alternative: Same group / All foods with match %, amounts for the same calories.
  Future<void> _pickAlternative(BuildContext anchor, Map it) async {
    final f = (it['food_detail'] as Map?) ?? const {};
    final scope = ValueNotifier('group');
    final por = portionLabel(_d(it['quantity']), MealItemMath.unitOf(it)?['name'] as String?);
    final cache = <String, Future<List<Map>>>{};
    Future<List<Map>> load(String s) => cache[s] ??= Services.api.get<List>('foods/${f['id'] ?? it['food']}/swap-options/', query: {
          'scope': s,
          'grams': fq(_d(it['grams'])),
          'client_diet': m.diet,
          'exclude': [for (final x in MealItemMath.swapsOf(it)) x['food']].join(','),
        }).then((r) => [for (final x in r) x as Map]);
    Widget body(VoidCallback close) => ValueListenableBuilder(
          valueListenable: scope,
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
                      for (final r in rows)
                        Hover(
                          onTap: () {
                            close();
                            _addSwap(it, r);
                          },
                          builder: (_, h, _) {
                            final mac = (r['macros'] as Map?) ?? const {};
                            final amt = r['unit'] == null ? portionLabel(_d(r['quantity']), null) : '${portionLabel(_d(r['quantity']), '${r['unit_name']}')} · ${fq(_d(r['grams']))} g';
                            return Container(
                              constraints: const BoxConstraints(minHeight: 52),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              decoration: BoxDecoration(color: h ? AppColors.sub : null, borderRadius: AppRadius.all(AppRadius.item)),
                              child: Row(spacing: 10, children: [
                                FoodTile(tone: groupTone('${r['group'] ?? ''}'), size: 30),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                                    Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w7)),
                                    Text('$amt · ${_d(mac['kcal']).round()} kcal · P ${_d(mac['protein']).round()} g',
                                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted)),
                                  ]),
                                ),
                                MatchPill(_d(r['match']).round()),
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
      await showAppSheet(context, title: 'Swap for ${f['name'] ?? ''}', sub: m.name, fixedBody: true, builder: (ctx) => body(() => Navigator.of(ctx).pop()));
    } else {
      await showPopover(anchor, width: 400, alignRight: true, builder: body);
    }
    scope.dispose();
  }

  /// Narrow layouts: the Portion and swaps panel opens as a drawer (a sheet on phone).
  void _panelSheet() {
    final s = m.sel;
    if (s == null) return;
    final meal = m.meals[s.$1];
    showAppDrawer(
      context,
      title: 'Portion and swaps',
      sub: '${meal['name']} · ${m.optionsOf(meal)[s.$2]['name']}',
      icon: AppIcons.bowl,
      builder: (ctx) => ListenableBuilder(
        listenable: m,
        builder: (_, _) => Padding(padding: const EdgeInsets.only(top: 14), child: _panel(sheet: true, onRemoved: () => Navigator.of(ctx).pop())),
      ),
      footer: (ctx) => [AppButton.primary('Done', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop())],
    );
  }

  // ─────────────────────────────── build

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: m,
        builder: (context, _) {
          if (m.loading) {
            return StaffPage(children: [
              _crumb(),
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5))),
            ]);
          }
          if (m.error != null || m.plan == null) {
            final gone = m.error?.status == 404;
            return StaffPage(children: [
              _crumb(),
              AppCard(
                child: EmptyState(gone ? 'This meal plan is gone' : 'Could not open this meal plan',
                    icon: AppIcons.apple,
                    sub: gone ? 'It may have been deleted.' : m.error?.message,
                    action: AppButton(gone ? 'Back to meal plans' : 'Try again', onPressed: gone ? () => context.go('/nutrition') : m.load)),
              ),
            ]);
          }
          final phone = context.isPhone;
          return StaffPage(
            onRefresh: () async {
              await m.reload();
              await _loadClients();
            },
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 12 : 14, children: [_crumb(), _head(phone)]),
              if (!_edit) _readOnly(),
              if (_edit && m.draft) _draftBanner(),
              if (m.saveError != null) _saveFailed(),
              // the 5 targets in one row need room; narrower, they go in a 3-column grid (`.mb-tg` mobile)
              LayoutBuilder(builder: (context, c) => _targets(phone, grid: c.maxWidth < 960)),
              LayoutBuilder(builder: (context, c) {
                final wide = c.maxWidth >= 900;
                final meals = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
                  for (var i = 0; i < m.meals.length; i++) _mealCard(i, wide, phone),
                  if (m.meals.isEmpty) AppCard(child: EmptyState('No meals yet', icon: AppIcons.apple, sub: _edit ? 'Add the first meal of the day.' : null)),
                  if (_edit) _addMealButton(),
                ]);
                final side = [
                  if (wide) _sideCard(_panel()),
                  _sideCard(_clientsCard()),
                  _sideCard(_permsCard()),
                  _tip(),
                ];
                if (!wide) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [meals, ...side]);
                return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
                  Expanded(child: meals),
                  SizedBox(width: 340, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: side)),
                ]);
              }),
            ],
          );
        },
      );

  Widget _crumb() => Row(spacing: 6, children: [
        Hover(
          onTap: () => context.go('/nutrition'),
          builder: (_, h, _) => Text('Nutrition & foods', style: AppText.s(13, W.w5, color: h ? AppColors.text : AppColors.muted)),
        ),
        const AppIcon(AppIcons.chevronRight, size: 13, color: AppColors.chevron),
        Text('Meal plan', style: AppText.s(13, W.w6)),
      ]);

  Widget _head(bool phone) {
    final narrow = compactTop(context);
    final clientsL = plural(m.clientCount, 'client');
    final pub = !m.draft;
    final w = MediaQuery.sizeOf(context).width;
    final size = phone ? 17.0 : (w * 0.02).clamp(20.0, 28.0);
    final title = Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text(m.name, style: AppText.h1.copyWith(fontSize: size)),
      AppBadge(pub ? 'Published' : 'Draft', tone: pub ? Tone.ok : Tone.warn, plain: true),
    ]);
    final sub = Text(m.sub, style: AppText.sub.copyWith(fontSize: phone ? 12 : 13), maxLines: 2, overflow: TextOverflow.ellipsis);
    final actions = [
      if (_edit || m.canCreate) Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'More options', onPressed: () => _planMenu(b))),
      AppButton(clientsL, icon: AppIcons.clientsAlt, iconOnly: phone || narrow, tooltip: 'Clients on this plan', onPressed: _manage),
      if (m.canAssign) AppButton('Assign', icon: AppIcons.plus, iconOnly: phone, tooltip: 'Assign to clients', onPressed: _assign),
      if (_edit && m.draft && !phone) AppButton.primary('Publish', icon: AppIcons.send, tooltip: 'Send the changes to clients', onPressed: m.saving ? null : _publish),
    ];
    return Row(crossAxisAlignment: phone ? CrossAxisAlignment.start : CrossAxisAlignment.center, spacing: 12, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [title, sub])),
      Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: actions),
    ]);
  }

  Widget _banner({required Color bg, required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: bg, borderRadius: AppRadius.all(10)),
        child: child,
      );

  Widget _draftBanner() {
    final n = m.clientCount;
    final text = n == 0
        ? (m.unsaved ? 'You have changes that are not published yet. Publish to save them.' : 'This plan is a draft. Publish it so it is ready to assign.')
        : 'You have changes the clients have not received yet. Publish to send them to ${n == 1 ? '1 client.' : '$n clients.'}';
    return _banner(
      bg: AppColors.warnBg,
      child: Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(text, style: AppText.s(13, W.w6, color: AppColors.warnText)),
        Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
          if (m.unsaved) SizedBox(height: 32, child: AppButton('Discard', size: BtnSize.sm, tooltip: 'Back to the published plan', onPressed: m.saving ? null : _discard)),
          SizedBox(height: 32, child: AppButton('Publish now', size: BtnSize.sm, icon: AppIcons.send, loading: m.saving, onPressed: m.saving ? null : _publish)),
        ]),
      ]),
    );
  }

  Widget _readOnly() => _banner(
        bg: AppColors.sub,
        child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const AppIcon(AppIcons.lock, size: 15, color: AppColors.muted),
          Text('Only Vimal or a trainer with “Edit gym templates” can change this plan.', style: AppText.s(13, W.w6, color: AppColors.text2)),
          if (m.canCreate) AppButton('Duplicate to edit', size: BtnSize.sm, icon: AppIcons.copy, onPressed: _duplicate),
        ]),
      );

  Widget _saveFailed() => _banner(
        bg: AppColors.badBg,
        child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Not published. ${m.saveError!.message}', style: AppText.s(13, W.w6, color: AppColors.badText)),
          AppButton('Try again', size: BtnSize.sm, onPressed: () => _publish(ask: false)),
        ]),
      );

  // ─────────────────────────────── targets card (`.mb-tg`)

  Widget _targets(bool phone, {bool grid = false}) {
    final t = m.targets, p = m.planned;
    final cells = [
      ('Calories', p['kcal']!, t['kcal_target'] ?? 0, 'kcal', 'Meals add up to '),
      ('Protein', p['protein']!, t['protein_g'] ?? 0, 'g', 'Planned '),
      ('Carbs', p['carbs']!, t['carbs_g'] ?? 0, 'g', 'Planned '),
      ('Fat', p['fat']!, t['fat_g'] ?? 0, 'g', 'Planned '),
    ];
    final water = (t['water_ml'] ?? 0) / 1000;
    Widget cell((String, double, num, String, String) c) {
      final (k, have, want, u, pre) = c;
      final ok = want == 0 ? true : (have - want).abs() / want <= .05;
      final col = ok ? AppColors.mbBarOk : (have > want ? AppColors.mbBarOver : AppColors.mbBarUnder);
      final frac = want == 0 ? 0.0 : (have / want).clamp(0.0, 1.0);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 2 : 4, children: [
        Text(k, style: AppText.s(phone ? 10.5 : 12, W.w6, color: AppColors.muted)),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: kfmt(want)),
            TextSpan(text: ' $u', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.s(phone ? 15 : 20, W.w8, tabular: true),
        ),
        Container(
          height: phone ? 3 : 5,
          margin: EdgeInsets.symmetric(vertical: phone ? 2 : 0),
          decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(3)),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(widthFactor: frac, child: Container(decoration: BoxDecoration(color: col, borderRadius: AppRadius.all(3)))),
        ),
        Text('$pre${kfmt(have)} $u', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(phone ? 10.5 : 11.5, W.w6, color: ok ? AppColors.okText : AppColors.warnText)),
      ]);
    }

    final fw = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 2 : 4, children: [
      Text('Fibre · Water', style: AppText.s(phone ? 10.5 : 12, W.w6, color: AppColors.muted)),
      Text('${kfmt(t['fibre_g'] ?? 0)} g · ${fq(water)} L', style: AppText.s(phone ? 14 : 20, W.w8, tabular: true, h: 1.25)),
      Text('Daily', style: AppText.s(phone ? 10.5 : 11.5, W.w6, color: AppColors.muted)),
    ]);
    // grid: Fibre and Water get a cell each, so both rows have three even cells
    Widget daily(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 2 : 4, children: [
          Text(k, style: AppText.s(phone ? 10.5 : 12, W.w6, color: AppColors.muted)),
          Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(phone ? 15 : 20, W.w8, tabular: true)),
          Text('Daily target', style: AppText.s(phone ? 10.5 : 11.5, W.w6, color: AppColors.muted)),
        ]);
    final edit = AppButton('Edit targets', icon: AppIcons.edit, size: BtnSize.sm, expand: phone || grid, tooltip: 'Daily targets for every client on this plan', onPressed: _edit ? _editTargets : null);
    const line = BorderSide(color: AppColors.line);
    if (phone || grid) {
      Widget box(Widget c, {bool left = false}) => Container(
            padding: phone ? const EdgeInsets.fromLTRB(10, 8, 10, 8) : const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(border: Border(bottom: line, left: left ? line : BorderSide.none)),
            child: c,
          );
      return AppCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: box(cell(cells[0]))),
              Expanded(child: box(cell(cells[1]), left: true)),
              Expanded(child: box(cell(cells[2]), left: true)),
            ]),
          ),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: box(cell(cells[3]))),
              Expanded(child: box(daily('Fibre', '${kfmt(t['fibre_g'] ?? 0)} g'), left: true)),
              Expanded(child: box(daily('Water', '${fq(water)} L'), left: true)),
            ]),
          ),
          if (_edit) Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 8), child: phone ? edit : Center(child: edit)),
        ]),
      );
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, c) in cells.indexed)
            Expanded(
              flex: 10,
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                decoration: BoxDecoration(border: i == 0 ? null : const Border(left: line)),
                child: cell(c),
              ),
            ),
          Expanded(
            flex: 9,
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 0, 14),
              decoration: const BoxDecoration(border: Border(left: line)),
              child: fw,
            ),
          ),
          if (_edit) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Center(child: edit)),
        ]),
      ),
    );
  }

  Future<void> _editTargets() async {
    final r = await showTargetsModal(context, m.targets);
    if (r == null || !mounted) return;
    _change(() => m.targets = r, toast: 'Targets updated', sub: '${kfmt(r['kcal_target']!)} kcal · P ${r['protein_g']} g · C ${r['carbs_g']} g · F ${r['fat_g']} g');
  }

  // ─────────────────────────────── meal card (`.mb-meal`)

  Widget _mealCard(int mi, bool wide, bool phone) {
    final meal = m.meals[mi];
    final os = m.optionsOf(meal);
    final oi = m.shownOf(meal);
    final opt = os.isEmpty ? null : os[oi];
    final items = opt == null ? <Map>[] : m.itemsOf(opt);
    final t = m.sum(items);
    final tgt = _d(meal['kcal_target']);
    final diff = t['kcal']! - tgt;
    final ok = tgt == 0 || diff.abs() / tgt <= .05;
    final badge = ok ? 'On target' : (diff > 0 ? '${kfmt(diff)} kcal over' : '${kfmt(-diff)} kcal under');
    final head = Padding(
      padding: phone ? const EdgeInsets.fromLTRB(12, 12, 12, 8) : const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(spacing: phone ? 10 : 12, children: [
        const IconTile(AppIcons.clock, size: 34, radius: 9, iconSize: 17, bg: AppColors.okBg, fg: AppColors.okText),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
            Text('${meal['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(15.5, W.w8)),
            Text('${mealTimeLabel(meal['time'])} · target ${kfmt(tgt)} kcal', maxLines: phone ? 2 : 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.muted)),
          ]),
        ),
        AppBadge(badge, tone: ok ? Tone.ok : Tone.warn, plain: true),
        if (_edit) Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'Meal options', small: true, ghost: true, onPressed: () => _mealMenu(b, meal))),
      ]),
    );
    final tabs = Wrap(spacing: 4, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (final (i, o) in os.indexed) _optTab(meal, i, o, i == oi),
      if (_edit) Builder(builder: (b) => _optAdd(() => _addOptionMenu(b, meal))),
    ]);
    final optRow = Container(
      padding: phone ? const EdgeInsets.fromLTRB(12, 0, 12, 10) : const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 4, children: [
        Expanded(child: tabs),
        if (!phone)
          Padding(
            padding: const EdgeInsets.only(bottom: 7, right: 4),
            child: Text(os.length > 1 ? '${os.length} options · client picks one' : 'One option', style: AppText.s(12, W.w6, color: AppColors.muted)),
          ),
        if (_edit && opt != null) Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'Option options', small: true, ghost: true, onPressed: () => _optionMenu(b, meal))),
      ]),
    );
    final list = Padding(
      padding: EdgeInsets.symmetric(horizontal: phone ? 4 : 8, vertical: 4),
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
              child: Text('No foods yet. Use Add food to pick from the food library.', textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 1, children: [
              for (final (ii, it) in items.indexed) _foodRow(mi, oi, ii, it, wide, phone),
            ]),
    );
    final tot = Text('P ${t['protein']!.round()} g · C ${t['carbs']!.round()} g · F ${t['fat']!.round()} g', style: AppText.s(12.5, W.w6, color: AppColors.muted, tabular: true));
    final totk = Text.rich(
      TextSpan(children: [
        TextSpan(text: kfmt(t['kcal']!)),
        TextSpan(text: ' / ${kfmt(tgt)} kcal', style: AppText.s(12, W.w6, color: AppColors.muted)),
      ]),
      style: AppText.s(14, W.w8, tabular: true),
    );
    final add = _edit
        ? AppButton('Add food', kind: BtnKind.text, icon: AppIcons.plus, size: BtnSize.sm, tooltip: 'Pick foods from the food library', onPressed: opt == null ? null : () => _addFood(mi))
        : const SizedBox.shrink();
    final foot = Container(
      padding: phone ? const EdgeInsets.fromLTRB(12, 8, 12, 8) : const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.tableHead,
        border: const Border(top: BorderSide(color: AppColors.line)),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppRadius.card)),
      ),
      child: phone
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              add,
              const Spacer(),
              Column(crossAxisAlignment: CrossAxisAlignment.end, spacing: 2, children: [totk, tot]),
            ])
          : Row(spacing: 12, children: [add, const Spacer(), tot, totk]),
    );
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [head, optRow, list, foot]),
    );
  }

  Widget _optTab(Map meal, int i, Map o, bool on) => AppTooltip(
        message: on ? '${o['name']} is open' : 'Show ${o['name']}',
        child: Hover(
          onTap: () => m.showOption(meal, i),
          builder: (_, h, _) => Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: on ? AppColors.accentSoft : (h ? AppColors.sub : null),
              borderRadius: AppRadius.all(8),
              border: Border.all(color: on ? AppColors.pickLine : Colors.transparent),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              Text('${o['name']}', style: AppText.s(13, W.w6, color: on ? AppColors.accentText : AppColors.text2)),
              if (o['is_default'] == true)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: on ? AppColors.card : AppColors.sub, borderRadius: AppRadius.all(5)),
                  child: Text('Default', style: AppText.s(10.5, W.w7, color: on ? AppColors.accentText : AppColors.muted)),
                ),
            ]),
          ),
        ),
      );

  Widget _optAdd(VoidCallback onTap) => AppTooltip(
        message: 'Add an option the client can pick',
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Padding(
            padding: const EdgeInsets.only(left: 4),
            child: CustomPaint(
              painter: _Dashed(h ? AppColors.lineHover : AppColors.line2),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
                  AppIcon(AppIcons.plus, size: 14, color: h ? AppColors.text : AppColors.muted),
                  Text('Option', style: AppText.s(12.5, W.w6, color: h ? AppColors.text : AppColors.muted)),
                ]),
              ),
            ),
          ),
        ),
      );

  Widget _swapChip(Map it) {
    final n = MealItemMath.swapsOf(it).length;
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(color: n > 0 ? AppColors.accentSoft : AppColors.sub, borderRadius: AppRadius.all(6)),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
        AppIcon(AppIcons.swap, size: 13, color: n > 0 ? AppColors.accentText : AppColors.muted),
        Text(n == 0 ? 'No swap' : plural(n, 'swap'), style: AppText.s(11.5, W.w7, color: n > 0 ? AppColors.accentText : AppColors.muted)),
      ]),
    );
  }

  /// `.mb-fr`: tile, name over portion, swaps, P / C / F and kcal. Phone: kcal at the right of the name, the
  /// swaps and P / C / F on a second line.
  Widget _foodRow(int mi, int oi, int ii, Map it, bool wide, bool phone) {
    final f = (it['food_detail'] as Map?) ?? const {};
    final on = m.sel == (mi, oi, ii);
    final tile = FoodTile(tone: groupTone('${f['group'] ?? ''}'), size: 30);
    final name = Text('${f['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7));
    final por = Text(MealItemMath.amount(it), style: AppText.s(12, W.w5, color: AppColors.muted));
    String mac(String k) => '${MealItemMath.m(it, k).round()}';
    final kcal = MealItemMath.m(it, 'kcal').round();
    Widget num(String t, double w) => SizedBox(width: w, child: Text(t, textAlign: TextAlign.right, style: AppText.s(12.5, W.w6, color: AppColors.muted, tabular: true)));
    final row = phone || !wide && MediaQuery.sizeOf(context).width < 700
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
            tile,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [name, por])),
                  Text.rich(
                    TextSpan(children: [TextSpan(text: '$kcal'), TextSpan(text: ' kcal', style: AppText.s(11.5, W.w6, color: AppColors.muted))]),
                    style: AppText.s(13.5, W.w8, tabular: true),
                  ),
                ]),
                Row(spacing: 6, children: [
                  _swapChip(it),
                  const Spacer(),
                  num('P ${mac('protein')}', 40),
                  num('C ${mac('carbs')}', 40),
                  num('F ${mac('fat')}', 40),
                ]),
              ]),
            ),
          ])
        : Row(spacing: 12, children: [
            tile,
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [name, por])),
            _swapChip(it),
            num('P ${mac('protein')}', 48),
            num('C ${mac('carbs')}', 48),
            num('F ${mac('fat')}', 48),
            SizedBox(width: 64, child: Text('$kcal', textAlign: TextAlign.right, style: AppText.s(13.5, W.w8, tabular: true))),
          ]);
    return Semantics(
      button: true,
      selected: on,
      label: '${f['name'] ?? ''}, ${MealItemMath.amount(it)}',
      child: Hover(
        onTap: () {
          m.pick(mi, oi, ii);
          if (!wide) _panelSheet();
        },
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: on ? AppColors.accentSoft : (h ? AppColors.hover : null),
            borderRadius: AppRadius.all(8),
            border: Border.all(color: on ? AppColors.pickLine : Colors.transparent),
          ),
          child: row,
        ),
      ),
    );
  }

  Widget _addMealButton() => AppTooltip(
        message: 'Add a meal to the day',
        child: Hover(
          onTap: _addMeal,
          builder: (_, h, _) => CustomPaint(
            painter: _Dashed(h ? AppColors.accent : AppColors.line2, radius: AppRadius.card, width: 1.5),
            child: Container(
              height: 46,
              decoration: BoxDecoration(color: h ? AppColors.hover : null, borderRadius: AppRadius.all(AppRadius.card)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
                AppIcon(AppIcons.plus, size: 16, color: h ? AppColors.accentText : AppColors.text2),
                Text('Add meal', style: AppText.s(13.5, W.w7, color: h ? AppColors.accentText : AppColors.text2)),
              ]),
            ),
          ),
        ),
      );

  // ─────────────────────────────── right column (`.mb-side`)

  Widget _sideCard(Widget child) => AppCard(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), child: child);

  Widget _label(String t, String tip) => Row(spacing: 4, children: [
        Text(t, style: AppText.label),
        AppTooltip(message: tip, child: const Padding(padding: EdgeInsets.all(2), child: AppIcon(AppIcons.info, size: 14, color: AppColors.muted))),
      ]);

  /// Portion and swaps for the picked food: amount (− n +) and unit, grams and macros, the swaps the client may
  /// use (`Add alternative`), Remove from meal.
  Widget _panel({bool sheet = false, VoidCallback? onRemoved}) {
    final it = m.picked;
    final title = sheet ? null : Text('Portion and swaps', style: AppText.s(14.5, W.w8));
    if (it == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        ?title,
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: AppIcon(AppIcons.swap, size: 16, color: AppColors.muted)),
          Expanded(child: Text('Pick a food in a meal to set its portion and the swaps the client may use.', style: AppText.s(13, W.w5, color: AppColors.muted, h: 1.5))),
        ]),
      ]);
    }
    final f = (it['food_detail'] as Map?) ?? const {};
    final u = MealItemMath.unitOf(it);
    final units = MealItemMath.unitsOf(it);
    final q = _d(it['quantity']);
    final step = u == null ? 5.0 : .5;
    final swaps = MealItemMath.swapsOf(it)..sort((x, y) => _d(y['match']).compareTo(_d(x['match'])));
    final k1 = '${_d(f['kcal']).round()} kcal per 100 g · ${plural(units.length, 'unit')} + grams';
    final unitSel = Builder(
      builder: (b) => Hover(
        onTap: !_edit
            ? null
            : () => showAppMenu(
                b,
                [
                  MenuEntry.header('Units of ${f['name'] ?? ''}'),
                  MenuEntry('Grams', selected: u == null, onTap: () => _setUnit(it, null)),
                  for (final x in units) MenuEntry('${x['name']}', selected: x['id'] == it['unit'], end: '${fq(_d(x['grams']))} g', onTap: () => _setUnit(it, x['id'])),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      ?title,
      Row(spacing: 10, children: [
        FoodTile(tone: groupTone('${f['group'] ?? ''}'), size: 34),
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
                AppIconButton(AppIcons.minus, tooltip: 'Less', ghost: true, small: true, onPressed: !_edit || q - step < step ? null : () => _setQty(it, q - step)),
                Expanded(child: Text(fq(q), textAlign: TextAlign.center, style: AppText.s(14, W.w8, tabular: true))),
                AppIconButton(AppIcons.plus, tooltip: 'More', ghost: true, small: true, onPressed: !_edit || q + step > (u == null ? 2000 : 20) ? null : () => _setQty(it, q + step)),
              ]),
            ),
          ),
          unitSel,
        ]),
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(8)),
          child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: [
            Text('${fq(_d(it['grams']))} g', style: AppText.s(14, W.w8, tabular: true)),
            Text(
                '${MealItemMath.m(it, 'kcal').round()} kcal · P ${MealItemMath.m(it, 'protein').round()} g · C ${MealItemMath.m(it, 'carbs').round()} g · F ${MealItemMath.m(it, 'fat').round()} g',
                style: AppText.s(12, W.w6, color: AppColors.text2, tabular: true)),
          ]),
        ),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('Swaps the client may use', 'The client can eat one of these instead. The amount is set to give about the same calories.'),
        const SizedBox(height: 4),
        for (final (i, s) in swaps.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
            child: Row(spacing: 8, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text('${s['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w7)),
                  Text(s['unit'] == null ? portionLabel(_d(s['quantity']), null) : '${portionLabel(_d(s['quantity']), '${s['unit_name']}')} · ${fq(_d(s['grams']))} g',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted)),
                ]),
              ),
              MatchBadge(_d(s['match']).round()),
              if (_edit) AppIconButton(AppIcons.close, tooltip: 'Remove', ghost: true, small: true, onPressed: () => _change(() => (it['swaps'] as List).remove(s))),
            ]),
          ),
        if (swaps.isEmpty) Text('No swaps. The client has to eat this food.', style: AppText.s(12, W.w5, color: AppColors.muted, h: 1.5)),
        if (_edit) ...[
          const SizedBox(height: 4),
          Builder(
            builder: (b) => Align(
              alignment: Alignment.centerLeft,
              child: AppButton('Add alternative', kind: BtnKind.text, icon: AppIcons.plus, size: BtnSize.sm, onPressed: () => _pickAlternative(b, it)),
            ),
          ),
        ],
      ]),
      if (_edit)
        Align(
          alignment: Alignment.centerLeft,
          child: DangerText('Remove from meal', onTap: () {
            _removeFood();
            onRemoved?.call();
          }),
        ),
    ]);
  }

  Widget _clientsCard() {
    final list = _clients;
    const show = 5;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      Row(children: [
        Expanded(child: Text('Clients on this plan', style: AppText.s(14.5, W.w8))),
        AppButton('Manage', kind: BtnKind.text, size: BtnSize.sm, tooltip: 'Version notes, reset, remove', onPressed: _manage),
      ]),
      if (list == null)
        const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)))
      else if (list.isEmpty)
        Text('Not assigned to anyone yet.', style: AppText.s(13, W.w5, color: AppColors.muted))
      else ...[
        for (final c in list.take(show))
          Hover(
            onTap: () => context.go('/clients/${c['id']}?tab=plans'),
            builder: (_, h, _) {
              final custom = c['custom'] == true;
              final note = '${c['version_note'] ?? ''}';
              return Row(spacing: 10, children: [
                AppAvatar('${c['full_name']}', size: 28, initials: '${c['initials'] ?? ''}', colors: AppColors.avatarCode('${c['avatar_color'] ?? 'c1'}')),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                    Text('${c['full_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7, color: h ? AppColors.accentText : AppColors.text)),
                    Text(custom ? (note.isEmpty ? 'Has changes only for them' : note) : 'Follows the master plan',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted)),
                  ]),
                ),
                AppBadge(custom ? 'Custom version' : 'Master', tone: custom ? Tone.warn : Tone.info, plain: true),
              ]);
            },
          ),
        if (list.length > show)
          Align(alignment: Alignment.centerLeft, child: AppButton('+${list.length - show} more', kind: BtnKind.text, size: BtnSize.sm, onPressed: _manage)),
      ],
      Text('Changes to the master reach everyone. A version note keeps one client\'s changes.', style: AppText.s(12, W.w5, color: AppColors.muted, h: 1.5)),
    ]);
  }

  static const _permL = {
    'allow_swaps': 'Client can swap within the approved list',
    'allow_search_any': 'Client can search any food',
    'allow_switch_options': 'Client can switch meal options',
    'allow_off_plan': 'Allow off-plan meals (flagged to coach)',
  };

  Widget _permsCard() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        Text('Client permissions', style: AppText.s(14.5, W.w8)),
        for (final k in MealBuilderModel.permKeys)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _edit ? () => _change(() => m.perms[k] = !(m.perms[k] ?? false)) : null,
            child: Row(spacing: 10, children: [
              Expanded(child: Text(_permL[k]!, style: AppText.s(13, W.w6, color: AppColors.text2))),
              AppToggle(value: m.perms[k] ?? false, width: 34, height: 20, onChanged: _edit ? (v) => _change(() => m.perms[k] = v) : null),
            ]),
          ),
      ]);

  Widget _tip() => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: AppIcon(AppIcons.docLines, size: 15, color: AppColors.muted)),
          Expanded(
            child: Text.rich(
              const TextSpan(children: [
                TextSpan(text: 'Meal options:', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' the client can pick any option of a meal. Keep every option within 5% of the meal target. Tap a food to set its portion and swaps.'),
              ]),
              style: AppText.s(12.5, W.w5, color: AppColors.text2, h: 1.5),
            ),
          ),
        ]),
      );
}

/// Dashed rounded border (`border: 1px dashed`).
class _Dashed extends CustomPainter {
  _Dashed(this.color, {this.radius = 8, this.width = 1});
  final Color color;
  final double radius, width;
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(radius)).deflate(width / 2));
    for (final mtr in path.computeMetrics()) {
      for (var d = 0.0; d < mtr.length; d += 7) {
        canvas.drawPath(mtr.extractPath(d, d + 4), p);
      }
    }
  }

  @override
  bool shouldRepaint(_Dashed o) => o.color != color;
}
