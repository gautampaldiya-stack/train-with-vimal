import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../home/home_model.dart' show clock, inNum;

/// Food tab (`GET me/food/?date=`): the day's ring and macros, the plan's meals, the food log, water and the
/// week. Every write goes through the outbox, so it works offline; the screen changes at once.
class FoodController extends ChangeNotifier {
  FoodController() {
    // Something sent from another page (Log food, Home): show it here too.
    _results = Services.outbox.results.listen((r) {
      if (r.error == null && data != null && !r.tag.startsWith('food:day')) load();
    });
  }

  static const _cacheKey = 'me/food';
  late final StreamSubscription _results;

  FoodDay? data;
  ApiError? error;
  DateTime? _day; // null = today
  String tab = 'plan';
  int? weekSel; // bar picked in "This week" (index 0–6); null = today
  int _seq = 0;

  DateTime get day => _day ?? today;
  DateTime get today => DateUtils0.dateOnly(DateTime.now());

  @override
  void dispose() {
    _results.cancel();
    super.dispose();
  }

  Future<void> start() async {
    final c = await Services.cache.read(_cacheKey);
    if (c is Map && data == null) {
      final d = FoodDay(c.cast<String, dynamic>());
      if (DateUtils0.same(d.date, today)) {
        data = d;
        notifyListeners();
      }
    }
    await load();
  }

  Future<void> load() async {
    final n = ++_seq;
    final d = day;
    try {
      final j = await Services.api.get<Map<String, dynamic>>('me/food/', query: {'date': ymd(d)});
      if (n != _seq) return;
      if (DateUtils0.same(d, today)) unawaited(Services.cache.write(_cacheKey, j));
      data = FoodDay(j);
      error = null;
    } on ApiError catch (e) {
      if (n != _seq) return;
      error = e;
    }
    notifyListeners();
  }

  void pick(DateTime d) {
    _day = DateUtils0.same(d, today) ? null : d;
    notifyListeners();
    load();
  }

  void pickTab(String t) {
    tab = t;
    notifyListeners();
  }

  void pickWeek(int i) {
    weekSel = i;
    notifyListeners();
  }

  // ─────────────────────────────── Writes

  /// A meal action (`eat`, `unlog`, `skip`, `unskip`, `item`, `portions`, `swap`, `photo`, `photo_add`). The server answers with the whole day.
  Future<void> meal(FMeal m, String op, [Map<String, dynamic> body = const {}]) async {
    final d = data!;
    // Show it at once; the server's answer replaces it.
    if (op == 'eat') {
      m.j['status'] = 'logged';
      m.j['logged_at'] ??= DateTime.now().toUtc().toIso8601String();
      if (body['photo'] != null) m.j['photos'] = [body['photo']];
      final all = m.items.every((i) => i.state == 'skipped');
      for (final i in m.items) {
        if (all || i.state != 'skipped') i.j['state'] = 'eaten';
      }
    } else if (op == 'unlog' || op == 'unskip') {
      m.j['status'] = '';
      m.j['logged_at'] = null;
      m.j['photos'] = <String>[];
      for (final i in m.items) {
        i.j['state'] = '';
      }
    } else if (op == 'skip') {
      m.j['status'] = 'skipped';
      for (final i in m.items) {
        i.j['state'] = 'skipped';
      }
    } else if (op == 'item') {
      final it = m.items.where((i) => i.item == body['item']).firstOrNull;
      if (it != null) it.j['state'] = switch (body['action']) { 'eat' => 'eaten', 'skip' => 'skipped', _ => '' };
      final st = m.items.map((i) => i.state).toList();
      m.j['status'] = st.any((s) => s.isEmpty) ? '' : (st.contains('eaten') ? 'logged' : 'skipped');
      if (st.contains('eaten')) m.j['logged_at'] ??= DateTime.now().toUtc().toIso8601String();
    } else if (op == 'photo') {
      m.j['photos'] = body['photo'] == null ? <String>[] : [body['photo']];
    } else if (op == 'photo_add') {
      m.j['photos'] = [...m.photos, body['photo']];
    }
    d.relog(m);
    notifyListeners();
    try {
      final r = await Services.outbox.enqueue('POST', 'me/food/meals/${m.id}/$op/', {...body, 'date': ymd(d.date)}, tag: 'food:day:$op');
      if (r is Map && DateUtils0.same(DateTime.parse('${r['date']}'), day)) {
        data = FoodDay(r.cast<String, dynamic>());
        if (DateUtils0.same(data!.date, today)) unawaited(Services.cache.write(_cacheKey, r));
        notifyListeners();
      }
    } on ApiError {
      await load(); // the server said no: show its day again
      rethrow;
    }
  }

  Future<void> water(int ml) async {
    final d = data!;
    d.j['water'] = {...(d.j['water'] as Map? ?? {}), 'ml': (d.waterMl + ml).clamp(0, 10000)};
    notifyListeners();
    try {
      await Services.outbox.enqueue('POST', 'me/food-log/water/', {'ml': ml, 'date': ymd(d.date)}, tag: 'food:day:water');
    } on ApiError {
      await load();
    }
  }

  /// Removes one food-log entry (Delete entry). Returns it, for Undo.
  Future<FEntry?> deleteEntry(FEntry e) async {
    data!.log.remove(e);
    data!.relog();
    notifyListeners();
    try {
      await Services.outbox.enqueue('DELETE', 'me/food-log/${e.id}/', {}, tag: 'food:day:delete');
    } on ApiError {
      // Already gone.
    }
    await load();
    return e;
  }

  /// Puts a deleted entry back (Undo).
  Future<void> restore(FEntry e) async {
    await Services.outbox.enqueue('POST', 'me/food-log/', e.again(), tag: 'food:day:restore');
    await load();
  }

  /// Copy yesterday: the server's answer (`copied`, `ids`, `meals`) for Undo; null when it waits offline.
  Future<Map<String, dynamic>?> copyYesterday() async {
    final r = await Services.outbox.enqueue('POST', 'me/food-log/copy-yesterday/', {}, tag: 'food:day:copy');
    await load();
    return r is Map ? r.cast<String, dynamic>() : null;
  }

  /// Undo of Copy yesterday.
  Future<void> undoCopy(Map<String, dynamic> copy) async {
    await Services.outbox.enqueue('POST', 'me/food-log/undo-copy/', {'ids': copy['ids'] ?? [], 'meals': copy['meals'] ?? []}, tag: 'food:day:uncopy');
    await load();
  }

  /// The swap sheet's options for one planned food.
  Future<Map<String, dynamic>> swaps(int item) => Services.api.get<Map<String, dynamic>>('me/food/items/$item/swaps/');
}

/// Date helpers without the Material import.
class DateUtils0 {
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static bool same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

double _n(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? 0 : 0);

/// "Fri, 9 Oct"
String fdDay(DateTime d) => DateFormat('EEE, d MMM').format(d);
const fdWd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "60 g" · "1 scoop" · "10 pieces" · "2 medium" · "1.5 katori"
String amtOf(String unit, double q) {
  final qs = q == q.roundToDouble() ? '${q.round()}' : '${(q * 10).round() / 10}';
  if (unit == 'g' || unit.isEmpty) return '${q.round()} g';
  if (unit == 'serving') return q == 1 ? '1 entry' : '$qs entries';
  final w = unit.replaceFirst(RegExp(r'^1 '), '');
  const pl = {'piece': 'pieces', 'scoop': 'scoops', 'plate': 'plates', 'bowl': 'bowls', 'slice': 'slices', 'glass': 'glasses', 'egg white': 'egg whites', 'cube': 'cubes', 'cup': 'cups', 'katori': 'katoris'};
  return '$qs ${q == 1 ? w : pl[w] ?? w}';
}

/// "450 kcal · 32 g P · 71 g C · 6 g F"
String mline(num kcal, num p, num c, num f) => '${inNum(kcal)} kcal · ${p.round()} g P · ${c.round()} g C · ${f.round()} g F';

class FoodDay {
  FoodDay(this.j)
    : meals = [for (final m in (j['meals'] as List? ?? [])) FMeal(m as Map<String, dynamic>)],
      log = [for (final e in (j['log'] as List? ?? [])) FEntry(e as Map<String, dynamic>)],
      week = [for (final w in (j['week'] as List? ?? [])) (w as Map).cast<String, dynamic>()] {
    _log0 = _sumLog();
    for (final m in meals) {
      m.j['status'] ??= m.j['pill'] == 'logged' ? 'logged' : (m.j['pill'] == 'skipped' ? 'skipped' : '');
    }
  }
  final Map<String, dynamic> j;
  final List<FMeal> meals;
  final List<FEntry> log;
  final List<Map<String, dynamic>> week;

  DateTime get date => DateTime.tryParse('${j['date']}') ?? DateTime.now();
  bool get isToday => j['today'] == true;
  String get coach => '${j['coach'] ?? ''}'.isEmpty ? 'your coach' : '${j['coach']}';
  Map<String, dynamic>? get plan => j['plan'] as Map<String, dynamic>?;
  bool get hasPlan => plan != null;
  bool get allowSwaps => plan?['allow_swaps'] == true;

  /// Target: kcal, protein, carbs, fat.
  List<double> get target => [_n(plan?['kcal']), _n(plan?['protein']), _n(plan?['carbs']), _n(plan?['fat'])];

  /// Eaten so far: kcal, protein, carbs, fat. The server's day total (worked out from the unrounded entries,
  /// Phase 1 / D-82) plus whatever changed in the log on the phone since then (eat / undo before the server answers).
  /// Adding the rounded rows again would drift by a few kcal over a day.
  List<double> get eaten {
    final now = _sumLog(), m = j['macros'] as Map?;
    if (m == null) return now;
    final base = [_n(m['kcal']), _n(m['protein']), _n(m['carbs']), _n(m['fat'])];
    return [for (var i = 0; i < 4; i++) base[i] + (now[i] - _log0[i])];
  }

  late final List<double> _log0;

  List<double> _sumLog() {
    final t = [0.0, 0.0, 0.0, 0.0];
    for (final e in log) {
      t[0] += _n(e.j['kcal']);
      t[1] += e.protein;
      t[2] += e.carbs;
      t[3] += e.fat;
    }
    return t;
  }

  /// Every planned meal added up (a future day shows this).
  List<double> get planned {
    final t = [0.0, 0.0, 0.0, 0.0];
    for (final m in meals) {
      t[0] += m.kcal;
      t[1] += m.protein;
      t[2] += m.carbs;
      t[3] += m.fat;
    }
    return t;
  }

  int get waterMl => _n((j['water'] as Map?)?['ml']).round();
  int get waterGoal => _n((j['water'] as Map?)?['goal_ml']).round().clamp(250, 10000);

  /// Recomputes the log rows of plan meals after a local change (eat / undo / skip before the server answers):
  /// [changed] gets one row for every food marked eaten; other meals only get rows when logged without any.
  void relog([FMeal? changed]) {
    for (final m in meals) {
      final has = log.any((e) => e.meal == m.id && e.fromPlan);
      if (m == changed) {
        log.removeWhere((e) => e.meal == m.id && e.fromPlan);
      } else if (has || !m.logged) {
        continue;
      }
      for (final it in m.eatenItems) {
        log.add(FEntry({
          'id': 'local-${m.id}-${it.item}',
          'time': m.j['logged_at'],
          'meal_name': m.name,
          'meal': m.id,
          'name': it.name,
          'quantity': it.quantity,
          'unit': it.unit,
          'kcal': it.j['kcal'],
          'protein': it.protein,
          'carbs': it.carbs,
          'fat': it.fat,
          'source': 'plan',
          'photo': m.photo,
          'swapped_from': it.swappedFrom,
        }));
      }
    }
  }
}

class FMeal {
  FMeal(this.j) : items = [for (final i in (j['items'] as List? ?? [])) FItem(i as Map<String, dynamic>)] {
    _items0 = _sumItems();
    _eaten0;
  }
  final Map<String, dynamic> j;
  final List<FItem> items;
  late final List<double> _items0;
  int get id => (j['id'] as num).toInt();
  String get name => '${j['name']}';
  String get timeRaw => '${j['time']}';
  bool get logged => j['status'] == 'logged';
  bool get skipped => j['status'] == 'skipped';
  bool get open => !logged && !skipped;
  /// Meal total: the server's (from the unrounded item values, D-82) plus any change made on the phone since.
  List<double> get _total {
    final now = _sumItems();
    final base = [j['kcal'], j['protein'], j['carbs'], j['fat']];
    return [for (var i = 0; i < 4; i++) base[i] == null ? now[i] : _n(base[i]) + (now[i] - _items0[i])];
  }

  List<double> _sumItems() {
    final t = [0.0, 0.0, 0.0, 0.0];
    for (final i in items) {
      t[0] += _n(i.j['kcal']);
      t[1] += i.protein;
      t[2] += i.carbs;
      t[3] += i.fat;
    }
    return t;
  }

  int get kcal => _total[0].round();
  double get protein => _total[1];
  double get carbs => _total[2];
  double get fat => _total[3];
  DateTime? get loggedAt => DateTime.tryParse('${j['logged_at']}')?.toLocal();
  /// Up to 4 pictures of the meal (Phase 3); the first one is [photo].
  List<String> get photos => [
    for (final p in (j['photos'] as List? ?? [if (j['photo'] != null) j['photo']]))
      if ('${p ?? ''}'.isNotEmpty) '$p',
  ];
  String? get photo => photos.firstOrNull;

  /// The foods she ate: those marked eaten (a logged meal from before foods had their own state: all but skipped ones).
  List<FItem> get eatenItems => [
    for (final i in items)
      if (i.state == 'eaten' || (logged && i.state.isEmpty)) i,
  ];
  bool get anyEaten => eatenItems.isNotEmpty;
  bool get partly => open && items.any((i) => i.state.isNotEmpty);

  /// What she ate of this meal: the server's `eaten` (from the unrounded entries) when nothing changed since,
  /// else the eaten foods added up on the phone.
  List<double> get eaten {
    final t = [0.0, 0.0, 0.0, 0.0];
    for (final i in eatenItems) {
      t[0] += _n(i.j['kcal']);
      t[1] += i.protein;
      t[2] += i.carbs;
      t[3] += i.fat;
    }
    final e = j['eaten'] as Map?;
    if (e == null || !_sameEaten) return t;
    return [_n(e['kcal']), _n(e['protein']), _n(e['carbs']), _n(e['fat'])];
  }

  late final String _eaten0 = _eatenKey();
  String _eatenKey() => [for (final i in eatenItems) '${i.item}:${i.j['kcal']}'].join(',');
  bool get _sameEaten => _eatenKey() == _eaten0;
  bool get canSwap => items.any((i) => i.swaps > 0);
  String get foods => items.map((i) => i.name).join(', ');
  String get line => mline(kcal, protein, carbs, fat);
}

class FItem {
  FItem(this.j);
  final Map<String, dynamic> j;
  int get item => (j['item'] as num).toInt();
  String get food => '${j['food']}';
  String get name => '${j['name']}';
  double get quantity => _n(j['quantity']);
  double get plannedQuantity => _n(j['planned_quantity']);
  String get unit => '${j['unit'] ?? 'g'}';
  double get grams => _n(j['grams']);
  int get kcal => _n(j['kcal']).round();
  double get protein => _n(j['protein']);
  double get carbs => _n(j['carbs']);
  double get fat => _n(j['fat']);
  String get swappedFrom => '${j['swapped_from'] ?? ''}';
  int get swaps => (j['swaps'] as num?)?.toInt() ?? 0;
  String get amount => amtOf(unit, quantity);

  /// This food today: `eaten`, `skipped` or "" (not logged yet).
  String get state => '${j['state'] ?? ''}';

  /// Today's portion is not the planned one (Edit portions); Set to default puts it back.
  bool get edited => j['edited'] == true;

  /// kcal, protein, carbs, fat for [q] of this food's unit.
  List<double> at(double q) {
    final k = quantity > 0 ? q / quantity : 0.0;
    return [kcal * k, protein * k, carbs * k, fat * k];
  }
}

class FEntry {
  FEntry(this.j);
  final Map<String, dynamic> j;
  String get id => '${j['id']}';
  DateTime get time => (DateTime.tryParse('${j['time']}') ?? DateTime.now()).toLocal();
  String get mealName => '${j['meal_name']}';
  int? get meal => (j['meal'] as num?)?.toInt();
  String get name => '${j['name']}';
  double get quantity => _n(j['quantity']);
  String get unit => '${j['unit'] ?? 'g'}';
  int get kcal => _n(j['kcal']).round();
  double get protein => _n(j['protein']);
  double get carbs => _n(j['carbs']);
  double get fat => _n(j['fat']);
  String get source => '${j['source']}';
  bool get fromPlan => source == 'plan';

  /// Log food → Add to → Other time: eaten outside the meal times; [mealName] is the name the client gave.
  bool get otherTime => j['other_time'] == true;
  String get reason => '${j['reason'] ?? ''}';
  String? get photo => (j['photo'] as String?)?.isEmpty ?? true ? null : j['photo'] as String;
  String get swappedFrom => '${j['swapped_from'] ?? ''}';
  String get amount => amtOf(unit, quantity);

  /// The body that logs this entry again (Undo of Delete entry).
  Map<String, dynamic> again() => {
    ...(j['food'] != null
        ? {'meal_name': mealName, 'food': j['food'], 'quantity': quantity, 'unit_name': unit, 'off_plan': source == 'off_plan', 'reason': reason}
        : {'meal_name': mealName, 'name': name, 'kcal': kcal, 'protein': protein, 'carbs': carbs, 'fat': fat, 'off_plan': source == 'off_plan', 'reason': reason}),
    if (otherTime) ...{'other_time': true, 'logged_at': time.toUtc().toIso8601String()},
  };
}

/// "8:10 am"
String fdClock(DateTime t) => clock(t);
