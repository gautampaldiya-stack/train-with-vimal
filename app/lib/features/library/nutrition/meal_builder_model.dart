import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../trainer/client_profile/cp_plans_meal_edit.dart' show MealItemMath;
import 'nu_common.dart';

/// Meal plan builder state (boards `MealPlanBuilder` / `MealPlanBuilderMobile`).
/// The plan's meals → options → foods, its daily targets and the client permissions are edited here locally and
/// show at once. Nothing reaches clients until Publish (the board's word for Save changes, D-43 / D-44): it sends
/// the meals with `PUT meal-plans/<id>/structure/`, the targets and permissions with `PATCH`, then
/// `POST publish/` (clients and their trainers get a notice). Discard reloads the saved plan. Undo puts back a
/// copy of the draft from before the change.
class MealBuilderModel extends ChangeNotifier {
  MealBuilderModel(this.id);
  final String id;

  Map? plan;
  List<Map> meals = [];
  Map<String, num> targets = {};
  Map<String, bool> perms = {};
  bool loading = true, saving = false;
  ApiError? error, saveError;
  Map can = const {};

  /// Picked food: (meal, option, item) indexes into [meals].
  (int, int, int)? sel;

  bool _disposed = false;
  bool unsaved = false;
  int _rev = 0;

  static const targetKeys = ['kcal_target', 'protein_g', 'carbs_g', 'fat_g', 'fibre_g', 'water_ml'];
  static const permKeys = ['allow_swaps', 'allow_search_any', 'allow_switch_options', 'allow_off_plan'];

  String get name => '${plan?['name'] ?? ''}';
  String get diet => '${plan?['diet'] ?? 'veg'}';
  bool get canEdit => plan?['can_edit'] == true;
  bool get canCreate => can['create'] == true;
  bool get canAssign => can['assign'] == true;
  int get clientCount => (plan?['client_count'] as num?)?.toInt() ?? 0;
  int get customCount => (plan?['custom_count'] as num?)?.toInt() ?? 0;

  /// Draft (the board's `dirty`): changes here, or saved changes clients have not been sent, or never published.
  bool get draft => unsaved || plan?['status'] != 'published' || plan?['has_unpublished_changes'] == true;

  /// "Eggetarian · Master plan · 3 clients, 1 custom version".
  String get sub {
    final d = dietPlan[diet] ?? diet;
    if (clientCount == 0) return '$d · Master plan · not assigned yet';
    final cu = customCount;
    return '$d · Master plan · ${clientCount == 1 ? '1 client' : '$clientCount clients'}${cu > 0 ? ', $cu custom version${cu == 1 ? '' : 's'}' : ''}';
  }

  Future<void> load() async {
    try {
      final r = await Future.wait([Services.api.get<Map>('meal-plans/$id/'), Services.api.get<Map>('meal-plans/counts/')]);
      _apply(r[0]);
      can = (r[1]['can'] as Map?) ?? const {};
      error = null;
    } on ApiError catch (e) {
      error = e;
    }
    loading = false;
    _notify();
  }

  void _apply(Map p) {
    plan = p;
    meals = [
      for (final m in (p['meals'] as List? ?? const []))
        if ((m as Map)['weekday'] == null) jsonDecode(jsonEncode(m)) as Map,
    ];
    targets = {for (final k in targetKeys) k: (p[k] as num?) ?? 0};
    perms = {for (final k in permKeys) k: p[k] == true};
    sel = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ─────────────────────────────── reading the draft

  List<Map> optionsOf(Map meal) => [for (final o in (meal['options'] as List?) ?? const []) o as Map];
  List<Map> itemsOf(Map opt) => [for (final i in (opt['items'] as List?) ?? const []) i as Map];

  int defaultOf(Map meal) {
    final i = optionsOf(meal).indexWhere((o) => o['is_default'] == true);
    return i < 0 ? 0 : i;
  }

  /// The option tab that is open on a meal card (starts on the default one).
  int shownOf(Map meal) {
    final n = optionsOf(meal).length;
    final v = (meal['_oi'] as num?)?.toInt() ?? defaultOf(meal);
    return n == 0 ? 0 : v.clamp(0, n - 1);
  }

  void showOption(Map meal, int i) {
    meal['_oi'] = i;
    sel = null;
    _notify();
  }

  /// kcal / protein / carbs / fat of a list of foods.
  Map<String, double> sum(Iterable<Map> items) {
    final t = {'kcal': 0.0, 'protein': 0.0, 'carbs': 0.0, 'fat': 0.0};
    for (final it in items) {
      for (final k in t.keys.toList()) {
        t[k] = t[k]! + MealItemMath.m(it, k);
      }
    }
    return t;
  }

  /// What the day adds up to: every meal's default option (the targets card).
  Map<String, double> get planned {
    final t = {'kcal': 0.0, 'protein': 0.0, 'carbs': 0.0, 'fat': 0.0};
    for (final m in meals) {
      final os = optionsOf(m);
      if (os.isEmpty) continue;
      final s = sum(itemsOf(os[defaultOf(m)]));
      for (final k in t.keys.toList()) {
        t[k] = t[k]! + s[k]!;
      }
    }
    return t;
  }

  Map? get picked {
    final s = sel;
    if (s == null || s.$1 >= meals.length) return null;
    final os = optionsOf(meals[s.$1]);
    if (s.$2 >= os.length) return null;
    final its = itemsOf(os[s.$2]);
    return s.$3 < its.length ? its[s.$3] : null;
  }

  void pick(int mi, int oi, int ii) {
    sel = (mi, oi, ii);
    _notify();
  }

  void unpick() {
    sel = null;
    _notify();
  }

  // ─────────────────────────────── edits

  /// A deep copy of everything Publish sends, for Undo.
  Map snapshot() => jsonDecode(jsonEncode({'meals': meals, 'targets': targets, 'perms': perms})) as Map;

  void restore(Map snap) {
    meals = [for (final m in snap['meals'] as List) m as Map];
    targets = {for (final e in (snap['targets'] as Map).entries) '${e.key}': e.value as num};
    perms = {for (final e in (snap['perms'] as Map).entries) '${e.key}': e.value == true};
    if (picked == null) sel = null;
    _changed();
  }

  void edit(void Function() f) {
    f();
    _changed();
  }

  void _changed() {
    unsaved = true;
    _rev++;
    _notify();
  }

  // ─────────────────────────────── publish / discard

  /// Publish: saves the draft and sends it to every client on the plan. Returns how many clients got it, or
  /// null when it failed ([saveError] says why).
  Future<int?> publish() async {
    while (saving) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final rev = _rev;
    final send = unsaved;
    saving = true;
    _notify();
    try {
      if (send) {
        await Services.api.put<Map>('meal-plans/$id/structure/', {'meals': _payload()});
        await Services.api.patch<Map>('meal-plans/$id/', {...targets, ...perms});
      }
      final r = await Services.api.post<Map>('meal-plans/$id/publish/');
      final fresh = await Services.api.get<Map>('meal-plans/$id/');
      if (rev == _rev) {
        final keep = sel;
        final shown = [for (final m in meals) m['_oi']];
        _apply(fresh);
        for (var i = 0; i < meals.length && i < shown.length; i++) {
          if (shown[i] != null) meals[i]['_oi'] = shown[i];
        }
        sel = keep;
        if (picked == null) sel = null;
        unsaved = false;
      } else {
        plan = fresh;
      }
      saveError = null;
      saving = false;
      _notify();
      return (r['sent_to'] as num?)?.toInt() ?? 0;
    } on ApiError catch (e) {
      saveError = e;
      saving = false;
      _notify();
      return null;
    }
  }

  Future<void> discard() async {
    final r = await Services.api.get<Map>('meal-plans/$id/');
    _apply(r);
    unsaved = false;
    saveError = null;
    _rev++;
    _notify();
  }

  /// Fresh names and counts. With unsaved changes the draft stays.
  Future<void> reload() async {
    final r = await Services.api.get<Map>('meal-plans/$id/');
    if (unsaved) {
      plan = r;
    } else {
      _apply(r);
    }
    _notify();
  }

  Future<void> rename(String v) async {
    final r = await Services.api.patch<Map>('meal-plans/$id/', {'name': v});
    plan = {...?plan, 'name': r['name'], 'status': r['status'], 'has_unpublished_changes': r['has_unpublished_changes'], 'updated_at': r['updated_at']};
    _notify();
  }

  static String _time(Object? t) {
    final s = '${t ?? ''}';
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  List<Map> _payload() => [
        for (final m in meals)
          {
            if (m['id'] != null) 'id': m['id'],
            'name': '${m['name']}',
            'time': _time(m['time']),
            'kcal_target': (m['kcal_target'] as num?)?.round() ?? 0,
            'options': [
              for (final o in optionsOf(m))
                {
                  if (o['id'] != null) 'id': o['id'],
                  'name': '${o['name']}',
                  'is_default': o['is_default'] == true,
                  'items': [
                    for (final it in itemsOf(o))
                      {
                        if (it['id'] != null) 'id': it['id'],
                        'food': it['food'],
                        'quantity': nd(it['quantity']),
                        'unit': it['unit'],
                        'swaps': [
                          for (final s in MealItemMath.swapsOf(it)) {'food': s['food'], 'quantity': nd(s['quantity']), 'unit': s['unit']},
                        ],
                      },
                  ],
                },
            ],
          },
      ];
}
