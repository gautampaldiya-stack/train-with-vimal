import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../home/home_model.dart';

/// Data of the Train tab (`GET me/train/`): the week, today's workout with targets, last time and
/// PRs, and the workout that is running. Kept in the read cache so the tab opens offline.
class TrainController extends ChangeNotifier {
  TrainController() {
    _sub = Services.realtime.events.where((e) => _reloadOn.contains(e.event)).listen((_) => load());
    Services.outbox.pending.addListener(_sent);
  }

  /// Workout saves waiting in the outbox reached the server: reload so the tab shows them.
  int _pending = Services.outbox.pending.value;
  void _sent() {
    final p = Services.outbox.pending.value;
    if (p == 0 && _pending > 0) load();
    _pending = p;
  }

  static const cacheKey = 'me/train';
  static const _reloadOn = {'plan_updated', 'program_assigned', 'session_booked'};
  StreamSubscription? _sub;

  TrainData? data;
  ApiError? error;
  bool _busy = false;

  @override
  void dispose() {
    Services.outbox.pending.removeListener(_sent);
    _sub?.cancel();
    super.dispose();
  }

  Future<void> start() async {
    final c = await Services.cache.read(cacheKey);
    if (c is Map && data == null) {
      data = TrainData(c.cast<String, dynamic>());
      notifyListeners();
    }
    await load();
  }

  Future<void> load() async {
    if (_busy) return;
    _busy = true;
    try {
      final j = await Services.api.get<Map<String, dynamic>>('me/train/');
      unawaited(Services.cache.write(cacheKey, j));
      data = TrainData(j);
      error = null;
    } on ApiError catch (e) {
      error = e;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}

num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;
num? _nn(dynamic v) => v == null ? null : (v is num ? v : num.tryParse('$v'));
DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

class TrainData {
  TrainData(this.json)
      : date = DateTime.parse('${json['date']}'),
        week = json['week'] as int?,
        weeks = json['weeks'] as int?,
        program = '${json['program'] ?? ''}',
        strip = [for (final d in (json['strip'] as List? ?? const [])) TrainDay(d as Map<String, dynamic>)],
        day = (json['day'] as Map?)?.cast<String, dynamic>(),
        exercises = [for (final (i, e) in (json['exercises'] as List? ?? const []).indexed) TrainEx(e as Map<String, dynamic>, i)],
        completed = (json['completed_today'] as Map?)?.cast<String, dynamic>(),
        live = json['in_progress'] == null ? null : LiveWorkout((json['in_progress'] as Map).cast<String, dynamic>()),
        coach = (json['trainer'] as Map?)?.cast<String, dynamic>(),
        session = json['session'] == null ? null : HomeSession((json['session'] as Map).cast<String, dynamic>()),
        bodyweight = _nn(json['bodyweight_kg'])?.toDouble();

  final Map<String, dynamic> json;
  final DateTime date;
  final int? week, weeks;
  final String program;
  final List<TrainDay> strip;
  final Map<String, dynamic>? day;
  final List<TrainEx> exercises;
  final Map<String, dynamic>? completed;
  final LiveWorkout? live;
  final Map<String, dynamic>? coach;
  final HomeSession? session;
  final double? bodyweight;

  bool get hasPlan => program.isNotEmpty;
  bool get rest => day == null || day!['is_rest'] == true;
  String get dayName => '${day?['name'] ?? ''}';
  int? get dayId => day?['id'] as int?;
  String get note => '${day?['note'] ?? ''}';
  int get minutes => _n(day?['minutes']).toInt();
  int get totalSets => exercises.fold(0, (a, e) => a + e.sets);
  int get exercisesDone => exercises.where((e) => e.done).length;
  bool get finished => completed != null;
  String get coachFull => '${coach?['full_name'] ?? 'Your coach'}';
  String get coachFirst => coachFull.split(' ').first;
  String get coachInitials => '${coach?['initials'] ?? ''}';

  /// "Fat Loss Phase 1 · week 6 of 12".
  String get programLine => [
        if (program.isNotEmpty) program,
        if (week != null && weeks != null) 'week $week of $weeks',
      ].join(' · ');

  /// "Treadmill, kettlebell, mat": what to have ready.
  String get kit {
    final out = <String>[];
    for (final e in exercises) {
      final k = e.kitName;
      if (k.isNotEmpty && !out.contains(k)) out.add(k);
    }
    if (out.isEmpty) return '';
    final s = out.join(', ');
    return s[0].toUpperCase() + s.substring(1);
  }

  /// Exercise list in blocks: cardio, core, supersets and the main lifts, in plan order.
  List<TrainBlock> get blocks {
    final out = <TrainBlock>[];
    for (final e in exercises) {
      final name = e.blockName;
      if (out.isNotEmpty && out.last.name == name) {
        out.last.items.add(e);
      } else {
        out.add(TrainBlock(name, [e]));
      }
    }
    return out;
  }
}

class TrainDay {
  TrainDay(Map<String, dynamic> j)
      : date = DateTime.parse('${j['date']}'),
        name = '${j['name'] ?? ''}',
        rest = j['is_rest'] == true,
        done = j['done'] == true,
        today = j['today'] == true;
  final DateTime date;
  final String name;
  final bool rest, done, today;
}

class LiveWorkout {
  LiveWorkout(Map<String, dynamic> j)
      : id = '${j['id']}',
        name = '${j['name'] ?? ''}',
        startedAt = _dt(j['started_at']) ?? DateTime.now(),
        pausedAt = _dt(j['paused_at']),
        setsDone = _n(j['sets_done']).toInt(),
        setsTotal = _n(j['sets_total']).toInt();
  final String id, name;
  final DateTime startedAt;
  final DateTime? pausedAt;
  final int setsDone, setsTotal;
  int get elapsed => ((pausedAt ?? DateTime.now()).difference(startedAt).inSeconds).clamp(0, 99 * 3600);
}

class TrainBlock {
  TrainBlock(this.name, this.items);
  final String name;
  final List<TrainEx> items;

  /// "1 exercise · 35 min" / "2 exercises · 6 sets, rest 45 s".
  String get sub {
    final n = items.length;
    final head = '$n ${n == 1 ? 'exercise' : 'exercises'}';
    if (items.every((e) => e.kind == ExKind.cardio)) {
      final mins = items.map((e) => e.reps).where((r) => r.isNotEmpty).join(', ');
      return mins.isEmpty ? head : '$head · $mins';
    }
    final sets = items.fold(0, (a, e) => a + e.sets);
    final rests = items.map((e) => e.rest).toSet();
    return '$head · $sets sets${rests.length == 1 && rests.first > 0 ? ', rest ${restText(rests.first)}' : ''}';
  }
}

enum ExKind { weight, time, cardio }

/// One planned exercise with everything the Train list, the guide and the logger need.
class TrainEx {
  TrainEx(this.json, this.index)
      : peId = _n(json['id']).toInt(),
        full = (json['exercise_full'] as Map?)?.cast<String, dynamic>() ?? const {},
        sets = _n(json['sets']).toInt(),
        reps = '${json['reps'] ?? ''}',
        rpe = _nn(json['rpe'])?.toInt(),
        rest = _n(json['rest_seconds']).toInt(),
        tempo = '${json['tempo'] ?? ''}',
        targetKg = _nn(json['target_weight_kg'])?.toDouble(),
        note = '${json['note'] ?? ''}',
        superset = '${json['superset_group'] ?? ''}',
        lastTime = [for (final s in (json['last_time'] as List? ?? const [])) (s as Map).cast<String, dynamic>()],
        pr = (json['pr'] as Map?)?.cast<String, dynamic>(),
        setsDone = _n(json['sets_done']).toInt();

  final Map<String, dynamic> json, full;
  final int index, peId, sets, rest, setsDone;
  final String reps, tempo, note, superset;
  final int? rpe;
  final double? targetKg;
  final List<Map<String, dynamic>> lastTime;
  final Map<String, dynamic>? pr;

  String get exId => '${full['id'] ?? json['exercise']}';
  String get name => '${full['name'] ?? ''}';
  String get muscle => '${full['muscle_group'] ?? ''}';
  String get primary => '${full['primary_muscle'] ?? ''}';
  String get equipment => '${full['equipment'] ?? ''}';
  String get level => '${full['level'] ?? ''}';
  String get logType => '${full['log_type'] ?? 'weight_reps'}';
  String get videoTitle => '${full['video_title'] ?? ''}';
  String get youtube => '${full['youtube_url'] ?? ''}';
  bool get hasVideo => full['video'] != null || youtube.isNotEmpty;
  int get coverAt => _n(full['cover_at_seconds']).toInt();
  List<String> get howTo => [for (final s in (full['how_to'] as List? ?? const [])) '$s'];
  List<String> get cues => [for (final s in (full['form_cues'] as List? ?? const [])) '$s'];
  List<(String, String)> get also => [
        for (final a in (full['also_works'] as List? ?? const []))
          if (a is Map) ('${a['muscle']}', '${a['level']}' == 'strong' ? 'Strong' : 'Light'),
      ];

  ExKind get kind => logType == 'distance' || muscle == 'cardio'
      ? ExKind.cardio
      : logType == 'time'
          ? ExKind.time
          : ExKind.weight;
  bool get bodyweight => logType == 'bodyweight_reps';
  bool get done => sets > 0 && setsDone >= sets;

  String get blockName => superset.isNotEmpty
      ? 'Superset $superset'
      : kind == ExKind.cardio
          ? 'Cardio'
          : muscle == 'core'
              ? 'Core'
              : 'Strength';

  /// "3 × 15 · RPE 7 · rest 60 s", "35 min".
  String get target {
    if (kind == ExKind.cardio) return [reps, if (rpe != null) 'RPE $rpe'].where((s) => s.isNotEmpty).join(' · ');
    return ['$sets × $reps', if (targetKg != null) '${kg(targetKg!)} kg', if (rpe != null) 'RPE $rpe', if (rest > 0) 'rest ${restText(rest)}'].join(' · ');
  }

  /// What to put out for the Train header ("treadmill", "kettlebell", "mat").
  String get kitName {
    if (kind == ExKind.cardio) return name.toLowerCase().contains('treadmill') ? 'treadmill' : (name.toLowerCase().contains('bike') ? 'bike' : 'cardio machine');
    return switch (equipment) {
      'barbell' => 'barbell',
      'dumbbell' => 'dumbbells',
      'cable' => 'cable machine',
      'machine' => name.toLowerCase(),
      'kettlebell' => 'kettlebell',
      'band' => 'band',
      'bodyweight' => 'mat',
      _ => '',
    };
  }

  // ── guide sheet

  String get muscleLabel => label(muscle);
  String get equipmentLabel => label(equipment);
  String get levelLabel => label(level);
  String get logsLabel => switch (logType) {
        'bodyweight_reps' => 'Bodyweight × reps',
        'time' => 'Seconds',
        'distance' => 'Minutes + km',
        _ => 'kg × reps',
      };

  /// The three tiles under Today's target: sets · reps (or time) · rest.
  List<(String, String)> get tiles {
    final m = RegExp(r'^([\d.]+(?:\s?[–-]\s?[\d.]+)?(?:\s?(?:s|sec|min))?)\s*(.*)$').firstMatch(reps.trim());
    var v = reps, l = 'reps';
    if (m != null) {
      v = m.group(1)!;
      final rest = m.group(2)!.trim();
      l = rest.isNotEmpty ? rest : (RegExp(r'(s|sec|min)$').hasMatch(v) ? 'time' : 'reps');
    }
    return [('$sets', sets == 1 ? 'set' : 'sets'), (v, l), (rest > 0 ? '${rest}s' : '—', 'rest')];
  }

  /// "RPE 7 / 10 · tempo not set · 12 kg".
  String get extra => [
        if (rpe != null) 'RPE $rpe / 10',
        if (kind == ExKind.weight) tempo.isEmpty ? 'tempo not set' : 'tempo $tempo' else if (tempo.isNotEmpty) 'tempo $tempo',
        if (targetKg != null) '${kg(targetKg!)} kg',
      ].join(' · ');

  /// One set from history as text: "12 × 15", "BW × 10", "30 s", "35 min · 2.8 km".
  String setText(Map<String, dynamic> s) {
    final w = _nn(s['weight_kg'])?.toDouble(), r = _nn(s['reps'])?.toInt(), sec = _nn(s['seconds'])?.toInt();
    final bw = s['bw'] == true || s['is_bodyweight'] == true;
    return switch (kind) {
      ExKind.cardio => [if (sec != null) '${sec ~/ 60} min', if (_nn(s['distance_km']) != null) '${_nn(s['distance_km'])!.toStringAsFixed(1)} km'].join(' · '),
      ExKind.time => sec == null ? '—' : '$sec s',
      ExKind.weight => '${bw ? bwText(w ?? 0) : kg(w ?? 0)} × ${r ?? '—'}',
    };
  }

  String get lastText => lastTime.isEmpty ? 'not done yet' : lastTime.map(setText).join(' · ');

  /// "16 kg", "45 kg × 6", "40 s".
  String get prText {
    final p = pr;
    if (p == null) return '';
    if (p['seconds'] != null) return '${p['seconds']} s';
    return '${kg(_n(p['weight_kg']).toDouble())} kg';
  }

  String get prLong {
    final p = pr;
    if (p == null) return '';
    if (p['seconds'] != null) return '${p['seconds']} s';
    return '${kg(_n(p['weight_kg']).toDouble())} kg${p['reps'] != null ? ' × ${p['reps']}' : ''}';
  }

  /// Body map colour per region: p primary, s strong, l light.
  Map<String, String> get map {
    final out = <String, String>{};
    void put(String muscleName, String lv) {
      for (final r in regionsOf(muscleName)) {
        final have = out[r];
        if (have == null || 'psl'.indexOf(lv) < 'psl'.indexOf(have)) out[r] = lv;
      }
    }

    put(primary.isEmpty ? muscleLabel : primary, 'p');
    for (final (m, lv) in also) {
      put(m, lv == 'Strong' ? 's' : 'l');
    }
    return out;
  }
}

/// Muscle names in the library → body map regions.
List<String> regionsOf(String muscle) {
  final m = muscle.toLowerCase();
  if (m.contains('pector') || m.contains('chest')) return ['chest'];
  if (m.contains('shoulder') || m.contains('delt')) return ['shoulders'];
  if (m.contains('bicep')) return ['biceps'];
  if (m.contains('tricep')) return ['triceps'];
  if (m.contains('forearm') || m.contains('grip')) return ['forearms'];
  if (m.contains('oblique')) return ['obliques'];
  if (m.contains('abs') || m == 'core') return ['abs', 'obliques'];
  if (m.contains('trap') || m.contains('upper back')) return ['traps'];
  if (m.contains('lower back')) return ['lowback'];
  if (m.contains('lat') || m.contains('back')) return ['back'];
  if (m.contains('glute') || m.contains('hip')) return ['glutes'];
  if (m.contains('quad') || m == 'legs') return ['quads'];
  if (m.contains('hamstring')) return ['hamstrings'];
  if (m.contains('calf') || m.contains('calves')) return ['calves'];
  return const [];
}

// ─────────────────────────────── Past workouts (`GET me/workouts/`)

class PastRow {
  PastRow(Map<String, dynamic> j)
      : id = '${j['id']}',
        name = '${j['name'] ?? 'Workout'}',
        date = DateTime.parse('${j['date']}'),
        seconds = _n(j['duration_seconds']).toInt(),
        exercises = _n(j['exercises']).toInt(),
        sets = _n(j['sets_done']).toInt(),
        effort = _nn(j['effort'])?.toInt(),
        note = '${j['note'] ?? ''}',
        pr = j['has_pr'] == true;
  final String id, name, note;
  final DateTime date;
  final int seconds, exercises, sets;
  final int? effort;
  final bool pr;
  int get minutes => (seconds / 60).round();
}

class PastPage {
  PastPage(Map<String, dynamic> j)
      : rows = [for (final r in (j['results'] as List? ?? const [])) PastRow(r as Map<String, dynamic>)],
        count = _n(j['count']).toInt(),
        next = j['next'] as String?,
        since = j['since'] == null ? null : DateTime.tryParse('${j['since']}');
  final List<PastRow> rows;
  final int count;
  final String? next;
  final DateTime? since;
}

Future<PastPage> loadPast({String? name, int page = 1}) async {
  final q = <String, dynamic>{'page': page, 'page_size': 25, 'name': ?name};
  final j = await Services.api.get<Map<String, dynamic>>('me/workouts/', query: q);
  return PastPage(j);
}

/// One finished workout, its sets grouped by exercise in the order done.
class PastDetail {
  PastDetail(Map<String, dynamic> j)
      : row = PastRow({...j, 'exercises': 0, 'has_pr': false}),
        groups = _group(j['sets'] as List? ?? const []);
  final PastRow row;
  final List<({String name, String logType, bool pr, List<Map<String, dynamic>> sets})> groups;

  static List<({String name, String logType, bool pr, List<Map<String, dynamic>> sets})> _group(List sets) {
    final order = <String>[];
    final by = <String, List<Map<String, dynamic>>>{};
    for (final s in sets) {
      final m = (s as Map).cast<String, dynamic>();
      if (m['done'] != true) continue;
      final k = '${m['exercise']}';
      if (!by.containsKey(k)) order.add(k);
      by.putIfAbsent(k, () => []).add(m);
    }
    return [
      for (final k in order)
        (
          name: '${by[k]!.first['exercise_name'] ?? ''}',
          logType: '${by[k]!.first['log_type'] ?? 'weight_reps'}',
          pr: by[k]!.any((s) => s['is_pr'] == true),
          sets: by[k]!..sort((a, b) => _n(a['set_number']).compareTo(_n(b['set_number']))),
        ),
    ];
  }

  /// Text of a logged set by its exercise's log type.
  static String setText(String logType, Map<String, dynamic> s) {
    final w = _nn(s['weight_kg'])?.toDouble(), r = _nn(s['reps'])?.toInt(), sec = _nn(s['seconds'])?.toInt();
    final km = _nn(s['distance_km'])?.toDouble();
    if (logType == 'distance') return [if (sec != null) '${(sec / 60).round()} min', if (km != null) '${km.toStringAsFixed(1)} km'].join(' · ');
    if (logType == 'time') return sec == null ? '—' : '$sec s';
    final bw = s['is_bodyweight'] == true;
    return '${bw ? bwText(w ?? 0) : '${kg(w ?? 0)} kg'} × ${r ?? '—'}';
  }
}

Future<PastDetail> loadPastDetail(String id) async => PastDetail(await Services.api.get<Map<String, dynamic>>('me/workouts/$id/'));

// ─────────────────────────────── Text helpers

String label(String v) => v.isEmpty ? '' : v[0].toUpperCase() + v.substring(1).replaceAll('_', ' ');

/// 12.0 → "12", 12.5 → "12.5".
String kg(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(v * 10 == (v * 10).roundToDouble() ? 1 : 2);

/// Bodyweight with added load: "BW", "BW+5", "BW−5".
String bwText(double add) => add == 0 ? 'BW' : (add > 0 ? 'BW+${kg(add)}' : 'BW−${kg(-add)}');

/// 60 → "60 s", 150 → "150 s"; whole minutes from 2 min up ("2 min").
String restText(int s) => s >= 120 && s % 60 == 0 ? '${s ~/ 60} min' : '$s s';

/// Timer text: "18:25", "1:02:09".
String clockText(int s) {
  final h = s ~/ 3600, m = (s ~/ 60) % 60, sec = s % 60;
  return h > 0 ? '$h:${'$m'.padLeft(2, '0')}:${'$sec'.padLeft(2, '0')}' : '${s ~/ 60}:${'$sec'.padLeft(2, '0')}';
}

String dayUpper(DateTime d) => DateFormat('EEE, d MMM').format(d);
