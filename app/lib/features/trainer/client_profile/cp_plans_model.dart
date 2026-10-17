import 'package:flutter/foundation.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import 'cp_common.dart';
import 'cp_model.dart';

/// Plans tab data: the 4 slots of one client, each with current / up next / history, plus what the open slot
/// needs to draw its days (workout tree, meal plan meals, habits this week).
///
/// APIs: `clients/<id>/programs/` (+ `custom-structure/`, master `programs/<id>/`), `clients/<id>/meal-plans/`
/// (+ `<assignment>/meals/`: the client's own copy or the master), `clients/<id>/supplement-plans/`,
/// `clients/<id>/habit-plan/`, `clients/<id>/habits/`.
class PlansData extends ChangeNotifier {
  PlansData(this.c);
  final CpController c;

  Map programs = const {}, meals = const {}, supps = const {}, habits = const {};
  Map? habitWeek;

  /// Workout: the tree the client follows (their copy or the master) and the master to compare with.
  Map? wTree, wMaster;

  /// Meal plan: what the client follows (their copy, else the master): meals (each with `weekday`, null = every
  /// day), options, foods; `custom`, `own_days`.
  Map? mealPlan;
  bool loading = true;
  ApiError? error;

  String get id => c.id;

  static List<Map> rows(Map m, String k) => [for (final r in (m[k] as List?) ?? const []) r as Map];

  Map? get workout => rows(programs, 'current').firstOrNull;
  Map? get workoutNext => rows(programs, 'up_next').firstOrNull;
  Map? get meal => rows(meals, 'current').firstOrNull;
  Map? get mealNext => rows(meals, 'up_next').firstOrNull;

  Future<void> load() async {
    try {
      final r = await Future.wait([
        Services.api.get<Map>('clients/$id/programs/'),
        Services.api.get<Map>('clients/$id/meal-plans/'),
        Services.api.get<Map>('clients/$id/supplement-plans/'),
        Services.api.get<Map>('clients/$id/habit-plan/'),
        Services.api.get<Map>('clients/$id/habits/'),
      ]);
      programs = r[0];
      meals = r[1];
      supps = r[2];
      habits = r[3];
      habitWeek = r[4];
      await Future.wait([_workoutTree(), _mealPlan()]);
      error = null;
    } on ApiError catch (e) {
      error = e;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _workoutTree() async {
    final w = workout;
    wTree = wMaster = null;
    if (w == null) return;
    wTree = await Services.api.get<Map>('clients/$id/programs/${w['id']}/custom-structure/');
    if (w['custom'] == true) {
      try {
        wMaster = await Services.api.get<Map>('programs/${w['program']}/');
      } on ApiError {
        wMaster = null; // master gone: no "changed" marks
      }
    }
  }

  Future<void> _mealPlan() async {
    final m = meal;
    mealPlan = m == null ? null : await Services.api.get<Map>('clients/$id/meal-plans/${m['id']}/meals/');
  }

  /// After any change: reload this tab and the header / Overview / counts.
  Future<void> reload() async {
    await load();
    c.refresh();
  }
}

// ─────────────────────────────── meal plan helpers

/// The meals of a weekday (0 = Mon): that day's own meals (a client copy), else the every-day ones.
List<Map> mealsOnDay(Map? plan, int weekday) {
  final all = [for (final m in (plan?['meals'] as List?) ?? const []) m as Map];
  final own = all.where((m) => m['weekday'] == weekday).toList();
  return own.isNotEmpty ? own : all.where((m) => m['weekday'] == null).toList();
}

/// Weekdays with their own meals in the client's copy.
Set<int> ownMealDays(Map? plan) => {for (final m in (plan?['meals'] as List?) ?? const []) if ((m as Map)['weekday'] != null) (m['weekday'] as num).toInt()};

// ─────────────────────────────── workout tree helpers

/// Week of the plan the client is on (1-based), or 1 before it starts.
int planWeek(Map a) => ((a['week'] as num?) ?? 1).toInt();

List<Map> weeksOf(Map? tree) => [for (final w in (tree?['program_weeks'] as List?) ?? const []) w as Map];

Map? weekOf(Map? tree, int n) {
  final ws = weeksOf(tree);
  return ws.where((w) => w['number'] == n).firstOrNull ?? (ws.isEmpty ? null : ws.last);
}

/// Day `weekday` (0 = Mon) of a week; null = not in the plan (a rest day).
Map? dayOf(Map? week, int weekday) => [for (final d in (week?['days'] as List?) ?? const []) d as Map].where((d) => d['weekday'] == weekday).firstOrNull;

List<Map> exercisesOf(Map? day) => [for (final e in (day?['exercises'] as List?) ?? const []) e as Map];

bool isRest(Map? day) => day == null || day['is_rest'] == true || exercisesOf(day).isEmpty;

String exName(Map e) => '${(e['override'] as Map?)?['name'] ?? (e['exercise_detail'] as Map?)?['name'] ?? 'Exercise'}';

String restText(Object? s) {
  final n = (s as num?)?.toInt() ?? 0;
  if (n == 0) return '';
  if (n >= 60 && n % 60 == 0) return '${n ~/ 60} min';
  if (n > 60) return '${n ~/ 60} min ${n % 60} s';
  return '$n s';
}

String loadText(Map e) {
  final kg = e['target_weight_kg'];
  if (kg == null || '$kg'.isEmpty) return '';
  return cpKg(kg);
}

/// "A1", "A2" for supersets, "1", "2" for single exercises (`.dr-num` / `.dr-num.ss`).
List<(String, bool)> tagsOf(List<Map> ex) {
  var k = 0;
  final seen = <String, int>{};
  return [
    for (final e in ex)
      if ('${e['superset_group'] ?? ''}'.isEmpty)
        ('${++k}', false)
      else
        ('${e['superset_group']}${seen.update('${e['superset_group']}', (v) => v + 1, ifAbsent: () => 1)}', true),
  ];
}

/// "RPE 8 · tempo 3-1-1 · rest 2 min · 50 kg".
String exMeta(Map e) => [
      if (e['rpe'] != null) 'RPE ${e['rpe']}',
      if ('${e['tempo'] ?? ''}'.isNotEmpty) 'tempo ${e['tempo']}',
      if (restText(e['rest_seconds']).isNotEmpty) 'rest ${restText(e['rest_seconds'])}',
      if (loadText(e).isNotEmpty) loadText(e),
    ].join(' · ');

/// About how long a day takes: each set about 45 s of work plus its rest.
int dayMinutes(Map? day) {
  var s = 0;
  for (final e in exercisesOf(day)) {
    s += ((e['sets'] as num?) ?? 0).toInt() * (45 + ((e['rest_seconds'] as num?) ?? 0).toInt());
  }
  return (s / 60).round();
}

/// What changed for the client compared with the master, per exercise ("Was: Back squat") and per day.
class WorkoutDiff {
  WorkoutDiff(this.tree, this.master);
  final Map? tree, master;

  bool get on => master != null;

  Map? _masterDay(int week, int weekday) => dayOf(weekOf(master, week), weekday);

  /// null = same as the master; otherwise a short "Was: …" line.
  String? exercise(int week, int weekday, int i, Map e) {
    if (!on) return null;
    final m = exercisesOf(_masterDay(week, weekday));
    if (i >= m.length) return 'Added for this client';
    final o = m[i];
    if (o['exercise'] != e['exercise']) return 'Was: ${exName(o)}';
    final diffs = <String>[];
    if (o['sets'] != e['sets'] || '${o['reps']}' != '${e['reps']}') diffs.add('${o['sets']} × ${o['reps']}');
    if (o['rpe'] != e['rpe']) diffs.add(o['rpe'] == null ? 'no RPE' : 'RPE ${o['rpe']}');
    if ('${o['tempo'] ?? ''}' != '${e['tempo'] ?? ''}') diffs.add('${o['tempo'] ?? ''}'.isEmpty ? 'no tempo' : 'tempo ${o['tempo']}');
    if (o['rest_seconds'] != e['rest_seconds']) diffs.add('rest ${restText(o['rest_seconds'])}');
    if ('${o['target_weight_kg'] ?? ''}' != '${e['target_weight_kg'] ?? ''}') diffs.add(loadText(o).isEmpty ? 'no load' : loadText(o));
    if ('${o['note'] ?? ''}' != '${e['note'] ?? ''}') diffs.add('another note');
    if ('${o['superset_group'] ?? ''}' != '${e['superset_group'] ?? ''}') diffs.add('${o['superset_group'] ?? ''}'.isEmpty ? 'not in a superset' : 'superset ${o['superset_group']}');
    return diffs.isEmpty ? null : 'Was: ${diffs.join(' · ')}';
  }

  bool day(int week, int weekday) {
    if (!on) return false;
    final d = dayOf(weekOf(tree, week), weekday), m = _masterDay(week, weekday);
    if (isRest(d) != isRest(m) || '${d?['name'] ?? ''}' != '${m?['name'] ?? ''}' || '${d?['rest_note'] ?? ''}' != '${m?['rest_note'] ?? ''}') return true;
    final ex = exercisesOf(d);
    if (ex.length != exercisesOf(m).length) return true;
    for (var i = 0; i < ex.length; i++) {
      if (exercise(week, weekday, i, ex[i]) != null) return true;
    }
    return false;
  }

  int daysChanged(int week) => on ? [for (var i = 0; i < 7; i++) day(week, i)].where((x) => x).length : 0;
}

const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const weekdayFull = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// End date of a workout assignment (its own, or start + weeks).
DateTime? planEnd(Map a) {
  final e = cpParse(a['end_date']);
  if (e != null) return e;
  final s = cpParse(a['start_date']);
  final w = (a['weeks'] as num?)?.toInt();
  return s == null || w == null ? null : s.add(Duration(days: w * 7 - 1));
}

/// her / his / their from the client's gender.
String pronoun(CpController c) => switch ('${c.detail['gender'] ?? ''}') { 'female' => 'her', 'male' => 'his', _ => 'their' };
String pronounSub(CpController c) => switch ('${c.detail['gender'] ?? ''}') { 'female' => 'she', 'male' => 'he', _ => 'they' };
