import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../lib_common.dart';

/// Program builder state (boards `ProgramBuilder` / `ProgramBuilderMobile`).
/// The whole week → day → exercise tree lives here; every change edits it locally, shows at once and is sent
/// with `PUT programs/<id>/structure/` (one request at a time, the newest tree wins). Undo puts back a copy of
/// the tree from before the change. Ids from the server keep logged workouts linked to their day.
class BuilderModel extends ChangeNotifier {
  BuilderModel(this.id);
  final String id;

  Map? program;
  List<Map> weeks = [];
  int week = 1; // 1-based
  int sel = 0; // index of the open day in the week's day list
  bool loading = true, saving = false;
  ApiError? error, saveError;
  Map can = const {};

  bool _dirty = false, _disposed = false;

  String get name => '${program?['name'] ?? ''}';
  bool get archived => program?['archived'] == true;
  bool get canEdit => program?['can_edit'] == true;
  bool get canCreate => can['create'] == true;
  bool get canAssign => can['assign'] == true;
  int get clientCount => (program?['client_count'] as num?)?.toInt() ?? 0;

  Map get weekMap => weeks.firstWhere((w) => w['number'] == week, orElse: () => weeks.isEmpty ? {'days': []} : weeks.first);
  List<Map> get days {
    final ds = [for (final d in (weekMap['days'] as List? ?? const [])) d as Map];
    ds.sort((a, b) => (a['weekday'] as num).compareTo(b['weekday'] as num));
    return ds;
  }

  Map? get day => days.isEmpty ? null : days[sel.clamp(0, days.length - 1)];
  List<Map> exercisesOf(Map? d) => [for (final e in (d?['exercises'] as List?) ?? const []) e as Map];

  /// "12 weeks · 5 days / week · edited 2 Oct" (days = training days in week 1).
  String get sub {
    final w1 = weeks.where((w) => w['number'] == 1).firstOrNull;
    final n = [for (final d in (w1?['days'] as List? ?? const [])) d as Map].where((d) => d['is_rest'] != true).length;
    return '${plural(weeks.length, 'week')} · $n days / week · ${editedOn(program?['updated_at']).replaceFirst('Edited', 'edited')}';
  }

  String get dayHead => 'Week $week · ${weekdayNames[(day?['weekday'] as num?)?.toInt() ?? 0]}';

  Future<void> load() async {
    try {
      final r = await Future.wait([Services.api.get<Map>('programs/$id/'), Services.api.get<Map>('programs/counts/')]);
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
    program = p;
    weeks = [for (final w in (p['program_weeks'] as List? ?? const [])) w as Map];
    weeks.sort((a, b) => (a['number'] as num).compareTo(b['number'] as num));
    if (week > weeks.length) week = weeks.length.clamp(1, 999);
    if (sel >= days.length) sel = (days.length - 1).clamp(0, 6);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void pickWeek(int n) {
    week = n;
    if (sel >= days.length) sel = 0;
    _notify();
  }

  void pickDay(int i) {
    sel = i;
    _notify();
  }

  // ─────────────────────────────── tree edits

  /// A deep copy of the tree, for Undo.
  List<Map> snapshot() => [for (final w in jsonDecode(jsonEncode(weeks)) as List) w as Map];

  void restore(List<Map> snap) {
    weeks = snap;
    if (sel >= days.length) sel = (days.length - 1).clamp(0, 6);
    _changed();
  }

  /// Runs [f] on the tree, shows it and saves it.
  void edit(void Function() f) {
    f();
    _changed();
  }

  void _changed() {
    _notify();
    _dirty = true;
    _flush();
  }

  Future<void> _flush() async {
    if (saving || !_dirty) return;
    _dirty = false;
    saving = true;
    _notify();
    try {
      final r = await Services.api.put<Map>('programs/$id/structure/', {'weeks': _payload()});
      // Newer edits are waiting: keep the local tree (they go next). Otherwise take the server's ids.
      // Copy the new ids onto the local tree (same shape as what was sent). The maps stay the same objects,
      // so a sheet that is open on a day or an exercise still edits the live tree.
      if (!_dirty) _takeIds(r);
      program = {...?program, 'updated_at': r['updated_at'], 'weeks': r['weeks'], 'days_per_week': r['days_per_week']};
      saveError = null;
    } on ApiError catch (e) {
      saveError = e;
    }
    saving = false;
    _notify();
    if (_dirty) _flush();
  }

  void _takeIds(Map r) {
    final sw = [for (final w in (r['program_weeks'] as List? ?? const [])) w as Map]..sort((a, b) => (a['number'] as num).compareTo(b['number'] as num));
    if (sw.length != weeks.length) return;
    for (var i = 0; i < sw.length; i++) {
      weeks[i]['id'] = sw[i]['id'];
      final ld = [for (final d in (weeks[i]['days'] as List? ?? const [])) d as Map]..sort((a, b) => (a['weekday'] as num).compareTo(b['weekday'] as num));
      final sd = [for (final d in (sw[i]['days'] as List? ?? const [])) d as Map]..sort((a, b) => (a['weekday'] as num).compareTo(b['weekday'] as num));
      if (ld.length != sd.length) continue;
      for (var j = 0; j < sd.length; j++) {
        ld[j]['id'] = sd[j]['id'];
        final le = (ld[j]['exercises'] as List?) ?? const [], se = (sd[j]['exercises'] as List?) ?? const [];
        if (le.length != se.length) continue;
        for (var k = 0; k < se.length; k++) {
          (le[k] as Map)['id'] = (se[k] as Map)['id'];
        }
      }
    }
  }

  List<Map> _payload() => [
        for (final w in weeks)
          {
            if (w['id'] != null) 'id': w['id'],
            'number': w['number'],
            'days': [
              for (final d in (w['days'] as List? ?? const []))
                {
                  if ((d as Map)['id'] != null) 'id': d['id'],
                  'weekday': d['weekday'],
                  'name': '${d['name'] ?? ''}',
                  'is_rest': d['is_rest'] == true,
                  'rest_note': '${d['rest_note'] ?? ''}',
                  'exercises': [
                    for (final e in (d['exercises'] as List? ?? const []))
                      {
                        if ((e as Map)['id'] != null) 'id': e['id'],
                        'exercise': e['exercise'],
                        'superset_group': '${e['superset_group'] ?? ''}',
                        'sets': e['sets'],
                        'reps': '${e['reps']}',
                        'rpe': e['rpe'],
                        'rest_seconds': e['rest_seconds'],
                        'tempo': '${e['tempo'] ?? ''}',
                        'target_weight_kg': e['target_weight_kg'],
                        'note': '${e['note'] ?? ''}',
                        'override': e['override'] ?? {},
                      },
                  ],
                },
            ],
          },
      ];

  /// "Try again" after a failed save: sends the tree as it is now.
  void retry() {
    _dirty = true;
    _flush();
  }

  /// Saves the waiting change now (leaving the page).
  Future<void> flushNow() async {
    while (saving) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await _flush();
  }

  // ─────────────────────────────── program-level calls

  Future<void> reload() async {
    final r = await Services.api.get<Map>('programs/$id/');
    _apply(r);
    _notify();
  }

  Future<void> rename(String v) async {
    final r = await Services.api.patch<Map>('programs/$id/', {'name': v});
    program = {...?program, 'name': r['name'], 'updated_at': r['updated_at']};
    _notify();
  }

  Future<void> setArchived(bool v) async {
    final r = await Services.api.post<Map>('programs/$id/${v ? 'archive' : 'unarchive'}/');
    program = {...?program, 'archived': r['archived'], 'archived_at': r['archived_at']};
    _notify();
  }

  Future<Map> copyWeek() async {
    await flushNow();
    final r = await Services.api.post<Map>('programs/$id/copy-week/', {'week': week});
    _apply(r);
    _notify();
    return r;
  }
}

// ─────────────────────────────── helpers for one exercise row

String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

Map exDetail(Map e) => (e['exercise_detail'] as Map?) ?? const {};

/// "Chest · also Shoulders, Triceps" (+ " · library: Dips" when renamed for this program).
String exMuscles(Map e, {bool library = true}) {
  final x = exDetail(e);
  final main = '${x['primary_muscle'] ?? ''}'.isNotEmpty ? '${x['primary_muscle']}' : cap('${x['muscle_group'] ?? ''}');
  final also = [for (final a in (x['also_works'] as List? ?? const [])) '${(a as Map)['muscle']}'];
  final renamed = '${(e['override'] as Map?)?['name'] ?? ''}';
  return [
    main,
    if (also.isNotEmpty) 'also ${also.join(', ')}',
    if (library && renamed.isNotEmpty && renamed != '${x['name']}') 'library: ${x['name']}',
  ].where((s) => s.isNotEmpty).join(' · ');
}

/// "90s", "2 min", "No rest" (`.pb-t` Rest column).
String restShort(Object? s) {
  final n = (s as num?)?.toInt() ?? 0;
  if (n == 0) return 'No rest';
  if (n >= 120 && n % 60 == 0) return '${n ~/ 60} min';
  return '${n}s';
}

/// Minutes for a day, the boards' estimate: each set ≈ 40 s of work (or the minutes in "30 min") + its rest.
int dayMinutes(List<Map> ex) {
  var s = 0;
  for (final e in ex) {
    final sets = (e['sets'] as num?)?.toInt() ?? 1;
    final m = RegExp(r'(\d+)\s*min').firstMatch('${e['reps']}');
    s += sets * ((m != null ? int.parse(m.group(1)!) * 60 : 40) + ((e['rest_seconds'] as num?)?.toInt() ?? 0));
  }
  final r = ((s / 300).round() * 5);
  return r < 5 ? 5 : r;
}

/// Day card line: "6 exercises · 35 min" / "Rest day" / "No exercises yet".
String daySummary(Map d) {
  final ex = [for (final e in (d['exercises'] as List?) ?? const []) e as Map];
  if (d['is_rest'] == true) return '${d['rest_note'] ?? ''}'.trim().isEmpty ? 'Rest day' : '${d['rest_note']}'.trim();
  if (ex.isEmpty) return 'No exercises yet';
  return '${plural(ex.length, 'exercise')} · ${dayMinutes(ex)} min';
}

/// Day name to show: its name, else "Rest" / "Workout".
String dayTitle(Map d) {
  final n = '${d['name'] ?? ''}'.trim();
  if (n.isNotEmpty) return n;
  return d['is_rest'] == true ? 'Rest' : 'Workout';
}

/// Superset groups with only one row left stop being a superset (boards: "group me ek hi bache to superset khatam").
void cleanSupersets(List ex) {
  final counts = <String, int>{};
  for (final e in ex) {
    final g = '${(e as Map)['superset_group'] ?? ''}';
    if (g.isNotEmpty) counts[g] = (counts[g] ?? 0) + 1;
  }
  for (final e in ex) {
    final g = '${(e as Map)['superset_group'] ?? ''}';
    if (g.isNotEmpty && counts[g]! < 2) e['superset_group'] = '';
  }
}
