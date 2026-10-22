import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/widgets/overlays.dart' show ToastKind;
import 'train_model.dart';

/// One set in the logger. Values stay null until the client changes or ticks them; until then the
/// screen shows grey suggestions from last time and the target.
class WSet {
  WSet({
    this.id,
    required this.key,
    required this.exId,
    this.peId,
    required this.number,
    this.weight,
    this.reps,
    this.seconds,
    this.km,
    this.bw = false,
    this.wu = false,
    this.done = false,
    this.doneAt,
    this.at,
    this.pr = false,
  });

  int? id;
  String key;
  String exId;
  int? peId;
  int number;
  double? weight, km;
  int? reps, seconds;
  bool bw, wu, done, pr;
  DateTime? doneAt;

  /// Workout time (seconds) when it was ticked: "Where the time went".
  int? at;

  WSet copy() => WSet(id: id, key: key, exId: exId, peId: peId, number: number, weight: weight, reps: reps, seconds: seconds, km: km, bw: bw, wu: wu, done: done, doneAt: doneAt, at: at, pr: pr);

  bool get touched => weight != null || reps != null || seconds != null || km != null;

  Map<String, dynamic> toApi() => {
        'id': ?id,
        'key': key,
        'exercise': exId,
        'program_exercise': peId,
        'set_number': number,
        'weight_kg': weight?.toStringAsFixed(2),
        'reps': reps,
        'seconds': seconds,
        'distance_km': km?.toStringAsFixed(2),
        'is_bodyweight': bw,
        'is_warmup': wu,
        'done': done,
        'done_at': doneAt?.toUtc().toIso8601String(),
      };

  Map<String, dynamic> toLocal() => {...toApi(), 'at': at, 'pr': pr};

  static double? _d(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
  static int? _i(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));

  factory WSet.from(Map<String, dynamic> j, DateTime startedAt) {
    final doneAt = j['done_at'] == null ? null : DateTime.tryParse('${j['done_at']}')?.toLocal();
    return WSet(
      id: _i(j['id']),
      key: '${j['client_key'] ?? j['key'] ?? ''}'.isEmpty ? 'id:${j['id']}' : '${j['client_key'] ?? j['key']}',
      exId: '${j['exercise']}',
      peId: _i(j['program_exercise']),
      number: _i(j['set_number']) ?? 1,
      weight: _d(j['weight_kg']),
      reps: _i(j['reps']),
      seconds: _i(j['seconds']),
      km: _d(j['distance_km']),
      bw: j['is_bodyweight'] == true,
      wu: j['is_warmup'] == true,
      done: j['done'] == true,
      doneAt: doneAt,
      at: _i(j['at']) ?? doneAt?.difference(startedAt).inSeconds.clamp(0, 99 * 3600),
      pr: j['pr'] == true || j['is_pr'] == true,
    );
  }
}

typedef Toaster = void Function(String title, {String? sub, ToastKind kind, VoidCallback? undo});

/// The running workout: timer, sets, rest, hold timer, finish. Every change is saved on the phone
/// at once and sent to the server through the outbox (`PUT me/workouts/<id>/state/`), so the
/// logger keeps working offline. A workout started offline is sent whole when it is finished.
class WorkoutController extends ChangeNotifier {
  WorkoutController(this.plan);

  static const _cacheKey = 'workout:live';
  final TrainData plan;
  List<TrainEx> get ex => plan.exercises;
  Toaster? toast;

  String? id;
  bool local = false;

  /// Sets whose form video went to the coach this time ("exercise id:set number").
  final filmed = <String>{};
  bool isFilmed(WSet s) => filmed.contains('${s.exId}:${s.number}');

  /// Form check: a short clip of one set goes to the coach, who watches it in the workout log. Needs the internet.
  Future<void> sendFormVideo(WSet s, String exName, String file, Uint8List bytes) async {
    if (id == null || local) {
      toast?.call('Could not send the video', sub: 'Connect to the internet, then try again', kind: ToastKind.warn);
      return;
    }
    toast?.call('Sending your form video…', sub: '$exName · set ${s.number}', kind: ToastKind.info);
    try {
      await Services.api.upload<Map>('me/workouts/$id/form-video/',
          FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: file), 'exercise': s.exId, 'set_number': s.number}));
      filmed.add('${s.exId}:${s.number}');
      notifyListeners();
      toast?.call('Form video sent', sub: 'Your coach will check your form', kind: ToastKind.ok);
    } on ApiError catch (e) {
      toast?.call('Could not send the video', sub: e.field('file') ?? e.message, kind: ToastKind.warn);
    }
  }
  String name = '';
  DateTime date = DateTime.now();
  DateTime startedAt = DateTime.now();
  DateTime? pausedAt;
  List<List<WSet>> sets = [];
  int cur = 0;
  bool ready = false;
  String? failed;

  // rest timer
  int rest = 0, restMax = 0, restUsed = 0;
  bool restPaused = false, restOpen = false;
  (int, int) restAt = (0, -1);

  // hold countdown on a timed set: (exercise, set, seconds left)
  (int, int, int)? hold;

  /// Workout time of the last tick or "Keep going" (for "Still working out?").
  int lastActive = 0;

  // after Finish
  bool finished = false, sent = false, _syncLater = false;
  int finalSeconds = 0, effort = 0;
  String note = '';

  Timer? _tick, _save;
  bool _gone = false;

  /// Opened with "Log more sets": Discard keeps the finished workout and drops only what was added.
  bool reopened = false;

  int get elapsed => ((pausedAt ?? DateTime.now()).difference(startedAt).inSeconds).clamp(0, 99 * 3600);
  bool get paused => pausedAt != null;
  int get setsDone => sets.fold(0, (a, xs) => a + xs.where((s) => s.done && !s.wu).length);
  int get setsAll => sets.fold(0, (a, xs) => a + xs.where((s) => !s.wu).length);
  bool exDone(int i) => sets[i].isNotEmpty && sets[i].every((s) => s.done);
  TrainEx get e => ex[cur];
  bool get idle => ready && !finished && !paused && elapsed - lastActive >= 1800;

  @override
  void dispose() {
    _gone = true;
    _tick?.cancel();
    if (_save?.isActive ?? false) {
      _save!.cancel();
      _push();
    }
    if (_syncLater) _sendLocal();
    super.dispose();
  }

  // ─────────────────────────────── Open / start

  /// [start] = program day to start; [reopen] = finished workout to log more sets on.
  Future<void> open({int? start, String? reopen}) async {
    try {
      final snap = await Services.cache.read(_cacheKey);
      final live = plan.live;
      if (reopen != null) {
        final j = await Services.api.post<Map<String, dynamic>>('me/workouts/$reopen/reopen/');
        _fromServer(j);
      } else if (live != null) {
        final mine = snap is Map && '${snap['id']}' == live.id;
        if (mine && Services.outbox.pending.value > 0) {
          _fromLocal(snap.cast<String, dynamic>()); // changes still on their way to the server
        } else {
          try {
            _fromServer(await Services.api.get<Map<String, dynamic>>('me/workouts/${live.id}/'));
            if (mine) restUsed = snap['rest_used'] as int? ?? restUsed; // rest is only counted on the phone
          } on ApiError catch (e) {
            if (!e.offline || !mine) rethrow;
            _fromLocal(snap.cast<String, dynamic>());
          }
        }
      } else if (snap is Map && snap['local'] == true && snap['finished'] != true) {
        _fromLocal(snap.cast<String, dynamic>()); // started offline earlier
      } else if (start != null || plan.dayId != null) {
        await _start(start ?? plan.dayId!);
      } else {
        failed = 'There is no workout planned today.';
      }
    } on ApiError catch (e) {
      failed = e.offline ? 'You are offline. Connect to open this workout.' : e.message;
    }
    ready = failed == null;
    // "Continue workout": the timer stopped when the client left Train, it goes on from there.
    final resume = ready && paused && !finished;
    if (resume) {
      startedAt = startedAt.add(DateTime.now().difference(pausedAt!));
      pausedAt = null;
    }
    if (ready) {
      lastActive = math.max(lastActive, _lastTick() ?? 0);
      if (lastActive == 0) lastActive = elapsed;
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => _second());
      _store();
      if (resume) _push();
    }
    notifyListeners();
  }

  /// Train banner ⋯ → Pause / Resume timer, without opening the logger.
  static Future<void> setPaused(String id, {required bool pause}) async {
    final now = DateTime.now().toUtc();
    final snap = await Services.cache.read(_cacheKey);
    if (snap is Map && '${snap['id']}' == id) {
      final m = Map<String, dynamic>.from(snap);
      final p = DateTime.tryParse('${m['paused_at']}'), st = DateTime.tryParse('${m['started_at']}');
      if (pause && p == null) m['paused_at'] = now.toIso8601String();
      if (!pause && p != null) {
        if (st != null) m['started_at'] = st.add(now.difference(p)).toUtc().toIso8601String();
        m['paused_at'] = null;
      }
      await Services.cache.write(_cacheKey, m);
    }
    try {
      await Services.outbox.enqueue('POST', 'me/workouts/$id/${pause ? 'pause' : 'resume'}/', pause ? {'at': now.toIso8601String()} : {}, tag: 'workout:pause');
    } on ApiError catch (_) {}
  }

  /// Train banner ⋯ → Discard workout.
  static Future<void> discardLive(String id) async {
    try {
      await Services.outbox.enqueue('POST', 'me/workouts/$id/discard/', {}, tag: 'workout:discard');
    } on ApiError catch (_) {}
    await drain();
    await Services.cache.write(_cacheKey, null);
  }

  /// The client left Train and the logger (decision D-17): the workout timer stops. Saved on the
  /// phone and sent through the outbox with the time it happened, so it works offline too.
  static Future<void> pauseLive() async {
    final snap = await Services.cache.read(_cacheKey);
    if (snap is! Map || snap['finished'] == true || snap['paused_at'] != null) return;
    final at = DateTime.now().toUtc().toIso8601String();
    await Services.cache.write(_cacheKey, {...snap.cast<String, dynamic>(), 'paused_at': at});
    if (snap['local'] == true || snap['id'] == null) return;
    try {
      await Services.outbox.enqueue('POST', 'me/workouts/${snap['id']}/pause/', {'at': at}, tag: 'workout:pause');
    } on ApiError catch (_) {
      // finished or discarded somewhere else: nothing to stop
    }
  }

  Future<void> _start(int dayId) async {
    try {
      final j = await Services.api.post<Map<String, dynamic>>('me/workouts/', {'program_day': dayId});
      _fromServer(j);
    } on ApiError catch (e) {
      if (!e.offline) rethrow;
      // Offline: the whole workout lives on the phone and is sent when it is finished.
      local = true;
      id = null;
      name = plan.dayName;
      date = plan.date;
      startedAt = DateTime.now();
      sets = [for (final x in ex) [for (var n = 1; n <= x.sets; n++) _fresh(x, n)]];
    }
  }

  WSet _fresh(TrainEx x, int n) => WSet(key: const Uuid().v4(), exId: x.exId, peId: x.peId, number: n, bw: x.bodyweight);

  void _fromServer(Map<String, dynamic> j) {
    id = '${j['id']}';
    local = false;
    name = '${j['name'] ?? plan.dayName}';
    date = DateTime.tryParse('${j['date']}') ?? plan.date;
    startedAt = DateTime.tryParse('${j['started_at']}')?.toLocal() ?? DateTime.now();
    pausedAt = j['paused_at'] == null ? null : DateTime.tryParse('${j['paused_at']}')?.toLocal();
    reopened = j['reopened_at'] != null;
    final tb = j['time_breakdown'];
    restUsed = tb is Map && tb['rest'] is num ? (tb['rest'] as num).toInt() : 0; // reopened: rest so far
    final all = [for (final s in (j['sets'] as List? ?? const [])) WSet.from((s as Map).cast<String, dynamic>(), startedAt)];
    sets = [for (final _ in ex) <WSet>[]];
    for (final s in all) {
      var i = ex.indexWhere((x) => x.peId == s.peId);
      if (i < 0) i = ex.indexWhere((x) => x.exId == s.exId);
      if (i >= 0) sets[i].add(s);
    }
    for (final (i, xs) in sets.indexed) {
      xs.sort((a, b) => a.number.compareTo(b.number));
      // planned sets that were skipped (dropped at finish) come back empty, ready to log
      for (var n = xs.length + 1; n <= ex[i].sets; n++) {
        xs.add(_fresh(ex[i], n));
      }
    }
    cur = _firstOpen();
  }

  void _fromLocal(Map<String, dynamic> j) {
    id = j['id'] == null ? null : '${j['id']}';
    local = j['local'] == true;
    name = '${j['name'] ?? plan.dayName}';
    date = DateTime.tryParse('${j['date']}') ?? plan.date;
    startedAt = DateTime.tryParse('${j['started_at']}')?.toLocal() ?? DateTime.now();
    pausedAt = j['paused_at'] == null ? null : DateTime.tryParse('${j['paused_at']}')?.toLocal();
    final raw = (j['sets'] as List? ?? const []);
    sets = [
      for (var i = 0; i < ex.length; i++) [for (final s in (i < raw.length ? raw[i] as List : const [])) WSet.from((s as Map).cast<String, dynamic>(), startedAt)],
    ];
    cur = (j['cur'] as int? ?? 0).clamp(0, math.max(0, ex.length - 1));
    restUsed = j['rest_used'] as int? ?? 0;
    reopened = j['reopened'] == true;
  }

  int _firstOpen() {
    final i = sets.indexWhere((xs) => xs.any((s) => !s.done));
    return i < 0 ? 0 : i;
  }

  int? _lastTick() {
    int? m;
    for (final xs in sets) {
      for (final s in xs) {
        if (s.done && s.at != null) m = math.max(m ?? 0, s.at!);
      }
    }
    return m;
  }

  // ─────────────────────────────── Saving

  void changed({bool save = true}) {
    notifyListeners();
    if (!save) return;
    _store();
    if (!local) {
      _save?.cancel();
      _save = Timer(const Duration(milliseconds: 600), _push);
    }
  }

  void _store() => Services.cache.write(_cacheKey, {
        'id': id,
        'local': local,
        'name': name,
        'date': DateFormat('yyyy-MM-dd').format(date),
        'started_at': startedAt.toUtc().toIso8601String(),
        'paused_at': pausedAt?.toUtc().toIso8601String(),
        'cur': cur,
        'rest_used': restUsed,
        'finished': finished,
        'reopened': reopened,
        'sets': [for (final xs in sets) [for (final s in xs) s.toLocal()]],
      });

  Map<String, dynamic> get _state => {
        'started_at': startedAt.toUtc().toIso8601String(),
        'paused_at': pausedAt?.toUtc().toIso8601String(),
        'sets': [for (final xs in sets) for (final s in xs) s.toApi()],
      };

  Future<void> _push() async {
    if (local || id == null) return;
    try {
      final r = await Services.outbox.enqueue('PUT', 'me/workouts/$id/state/', _state, tag: 'workout:state');
      if (r is Map) {
        // new sets get their server id (matched by the app's key)
        final ids = {for (final s in (r['sets'] as List? ?? const [])) '${(s as Map)['client_key']}': s['id']};
        for (final xs in sets) {
          for (final s in xs) {
            if (s.id == null && ids[s.key] != null) s.id = ids[s.key] as int?;
          }
        }
        if (!_gone) _store(); // after the logger closed, the phone copy may already be paused
      }
    } on ApiError catch (e) {
      toast?.call('Could not save the workout', sub: e.message, kind: ToastKind.warn);
    }
  }

  // ─────────────────────────────── Every second: timer, rest, hold

  void _second() {
    if (finished) return;
    if (!paused) {
      final h = hold;
      if (h != null) {
        if (h.$3 <= 1) {
          hold = null;
          final (i, k, _) = h;
          if (i == cur && k < sets[i].length) {
            final v = shown(sets[i][k], 0);
            tick(k, quiet: true);
            toast?.call('Hold done', sub: '${ex[i].name} · set ${k + 1} · ${v.round()} s', kind: ToastKind.ok);
          }
        } else {
          hold = (h.$1, h.$2, h.$3 - 1);
        }
      }
      if (rest > 0 && !restPaused) {
        rest -= 1;
        restUsed += 1;
        if (rest == 0) {
          restOpen = false;
          toast?.call('Rest is over', sub: 'Next: $nextUp', kind: ToastKind.info);
        }
      }
    }
    notifyListeners();
  }

  // ─────────────────────────────── Values

  /// Columns of the current exercise.
  List<String> cols(TrainEx x) => switch (x.kind) {
        ExKind.cardio => ['Min', 'Km'],
        ExKind.time => ['Seconds'],
        ExKind.weight => ['kg / BW', 'Reps'],
      };

  static int _firstInt(String s, {bool max = false}) {
    final m = RegExp(r'\d+').allMatches(s).map((m) => int.parse(m.group(0)!)).toList();
    if (m.isEmpty) return 0;
    return max ? m.take(2).reduce(math.max) : m.first;
  }

  Map<String, dynamic>? _last(TrainEx x, int k) => x.lastTime.isEmpty ? null : (k < x.lastTime.length ? x.lastTime[k] : x.lastTime.last);

  /// The suggestion shown in grey before a value is set.
  double suggest(TrainEx x, WSet s, int j) {
    final k = sets[x.index].where((y) => !y.wu).toList().indexOf(s);
    final last = _last(x, k < 0 ? 0 : k);
    num? n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}');
    switch (x.kind) {
      case ExKind.cardio:
        if (j == 0) return (n(last?['seconds']) != null ? n(last!['seconds'])! / 60 : _firstInt(x.reps)).roundToDouble();
        return (n(last?['distance_km']) ?? 0).toDouble();
      case ExKind.time:
        final t = _firstInt(x.reps);
        return (t > 0 ? t : (n(last?['seconds']) ?? 30)).toDouble();
      case ExKind.weight:
        if (j == 1) return _firstInt(x.reps, max: true).toDouble();
        if (s.bw) return 0;
        return (n(last?['weight_kg']) ?? x.targetKg ?? 0).toDouble();
    }
  }

  /// Value in column [j]: weight / reps, minutes / km, or seconds.
  double? value(TrainEx x, WSet s, int j) => switch (x.kind) {
        ExKind.cardio => j == 0 ? (s.seconds == null ? null : s.seconds! / 60) : s.km,
        ExKind.time => s.seconds?.toDouble(),
        ExKind.weight => j == 0 ? s.weight : s.reps?.toDouble(),
      };

  double shown(WSet s, int j, [TrainEx? x]) {
    x ??= ex[_indexOf(s)];
    return value(x, s, j) ?? suggest(x, s, j);
  }

  int _indexOf(WSet s) => sets.indexWhere((xs) => xs.contains(s));

  void _put(TrainEx x, WSet s, int j, double v) {
    switch (x.kind) {
      case ExKind.cardio:
        if (j == 0) {
          s.seconds = (v * 60).round();
        } else {
          s.km = (v * 10).round() / 10;
        }
      case ExKind.time:
        s.seconds = v.round();
      case ExKind.weight:
        if (j == 0) {
          s.weight = (v * 100).round() / 100;
        } else {
          s.reps = v.round();
        }
    }
  }

  /// Fill every column with what is shown, so a tick saves what the client sees.
  void _fill(TrainEx x, WSet s) {
    for (var j = 0; j < cols(x).length; j++) {
      if (value(x, s, j) == null) _put(x, s, j, suggest(x, s, j));
    }
  }

  double stepOf(TrainEx x, int j) => switch (x.kind) {
        ExKind.cardio => j == 0 ? 1 : 0.1,
        ExKind.time => 5,
        ExKind.weight => j == 1 ? 1 : (x.equipment == 'kettlebell' ? 4 : (x.equipment == 'dumbbell' ? 2 : 2.5)),
      };

  void step(int k, int j, int dir) {
    final x = e, s = sets[cur][k];
    final lo = x.kind == ExKind.weight && j == 0 && s.bw ? -40.0 : 0.0;
    final v = math.max(lo, shown(s, j, x) + dir * stepOf(x, j));
    _fill(x, s);
    _put(x, s, j, v);
    changed();
  }

  /// "12", "BW+5", "2.9", "35".
  String text(WSet s, int j, [TrainEx? x]) {
    x ??= ex[_indexOf(s)];
    final v = shown(s, j, x);
    if (x.kind == ExKind.weight && j == 0) return s.bw ? bwText(v) : kg(v);
    if (x.kind == ExKind.cardio && j == 1) return v.toStringAsFixed(1);
    return '${v.round()}';
  }

  /// Prev column: what was done last time in the same working set.
  String prev(TrainEx x, int workingIndex) {
    if (x.lastTime.isEmpty || workingIndex >= x.lastTime.length) return '—';
    return x.setText(x.lastTime[workingIndex]);
  }

  // ─────────────────────────────── Sets

  /// Tick or untick set [k] of the current exercise.
  void tick(int k, {bool quiet = false}) {
    final x = e, s = sets[cur][k];
    final on = !s.done;
    if (on) {
      _fill(x, s);
      s.done = true;
      s.doneAt = DateTime.now();
      s.at = elapsed;
      lastActive = elapsed;
      final best = x.pr?['weight_kg'];
      final b = best is num ? best.toDouble() : double.tryParse('${best ?? ''}');
      s.pr = x.kind == ExKind.weight && !s.bw && !s.wu && b != null && (s.weight ?? 0) > b;
    } else {
      s.done = false;
      s.doneAt = null;
      s.at = null;
      s.pr = false;
    }
    hold = null;
    final all = exDone(cur);
    if (on && x.rest > 0 && !all) {
      rest = x.rest;
      restMax = x.rest;
      restPaused = false;
      restOpen = true;
      restAt = (cur, k);
    } else if (on) {
      rest = 0;
      restOpen = false;
    }
    if (on && s.pr) {
      toast?.call('New best!', sub: '${x.name} · ${kg(s.weight!)} kg × ${s.reps}', kind: ToastKind.star);
    } else if (on && all && !quiet) {
      toast?.call('${x.name} done', sub: cur < ex.length - 1 ? 'Next: ${ex[cur + 1].name}' : 'Last one. Finish when you are ready', kind: ToastKind.ok);
    }
    if (on && all && cur < ex.length - 1) cur += 1;
    changed();
  }

  void addSet() {
    final x = e, xs = sets[cur];
    final last = xs.isEmpty ? null : xs.last;
    final s = WSet(key: const Uuid().v4(), exId: x.exId, peId: x.peId, number: (last?.number ?? 0) + 1, bw: last?.bw ?? x.bodyweight);
    if (last != null && last.touched) {
      s.weight = last.weight;
      s.reps = last.reps;
      s.seconds = last.seconds;
      s.km = last.km;
    }
    xs.add(s);
    toast?.call('Set added', sub: '${x.name} · set ${xs.length}', kind: ToastKind.ok);
    changed();
  }

  /// "Use last time" / "Use these sets": the sets not ticked yet take the values of a past workout,
  /// working sets in order; extra past sets are added. Ticked sets stay as they are.
  void fillFrom(List<Map<String, dynamic>> past, {String from = 'last time'}) {
    final work = [for (final p in past) if (p['is_warmup'] != true && p['wu'] != true) p];
    if (work.isEmpty) return;
    final before = _snap();
    final x = e, xs = sets[cur];
    final open = xs.where((s) => !s.wu).toList();
    var filled = 0;
    for (var k = 0; k < math.max(open.length, work.length); k++) {
      final WSet s;
      if (k < open.length) {
        s = open[k];
      } else {
        s = WSet(key: const Uuid().v4(), exId: x.exId, peId: x.peId, number: (xs.isEmpty ? 0 : xs.last.number) + 1, bw: x.bodyweight);
        xs.add(s);
      }
      if (s.done) continue;
      final p = work[math.min(k, work.length - 1)];
      s.weight = WSet._d(p['weight_kg']);
      s.reps = WSet._i(p['reps']);
      s.seconds = WSet._i(p['seconds']);
      s.km = WSet._d(p['distance_km']);
      s.bw = p['bw'] == true || p['is_bodyweight'] == true;
      filled += 1;
    }
    if (filled == 0) {
      toast?.call('All sets are ticked', sub: 'Add a set to log more', kind: ToastKind.info);
      return;
    }
    toast?.call('Sets filled from $from', sub: '${x.name} · $filled ${filled == 1 ? 'set' : 'sets'}. Change any value, then tick', kind: ToastKind.ok, undo: () => _restore(before));
    changed();
  }

  void deleteSet(int k) {
    final before = _snap();
    final x = e;
    sets[cur].removeAt(k);
    _renumber(cur);
    toast?.call('Set deleted', sub: x.name, kind: ToastKind.del, undo: () => _restore(before));
    changed();
  }

  void warmup(int k) {
    final x = e, s = sets[cur][k];
    s.wu = !s.wu;
    if (s.wu) s.pr = false;
    toast?.call(s.wu ? 'Warm-up set' : 'Working set', sub: '${x.name} · ${s.wu ? 'not counted in volume' : 'counts towards volume'}', kind: ToastKind.info);
    changed();
  }

  void toggleBw(int k) {
    final s = sets[cur][k];
    s.bw = !s.bw;
    s.weight = s.bw ? 0 : null;
    changed();
  }

  /// Load: kg for every set, or bodyweight for every set.
  void loadAll({required bool bw}) {
    for (final s in sets[cur]) {
      if (s.bw != bw) {
        s.bw = bw;
        s.weight = bw ? 0 : null;
      }
    }
    changed();
  }

  void _renumber(int i) {
    for (final (n, s) in sets[i].indexed) {
      s.number = n + 1;
    }
  }

  void goTo(int i) {
    cur = i.clamp(0, ex.length - 1);
    rest = 0;
    restOpen = false;
    hold = null;
    changed(save: false);
  }

  void startHold(int k) {
    rest = 0;
    restOpen = false;
    hold = (cur, k, shown(sets[cur][k], 0).round());
    notifyListeners();
  }

  void stopHold() {
    hold = null;
    toast?.call('Hold stopped', sub: 'Tick the set if you finished it', kind: ToastKind.info);
    notifyListeners();
  }

  // ─────────────────────────────── Rest

  void restNow() {
    rest = e.rest;
    restMax = e.rest;
    restPaused = false;
    restOpen = true;
    restAt = (cur, -1);
    notifyListeners();
  }

  void restMore() {
    rest += 15;
    restMax = math.max(restMax, rest);
    notifyListeners();
  }

  void restLess() {
    rest = math.max(1, rest - 15);
    notifyListeners();
  }

  void restToggle() {
    restPaused = !restPaused;
    notifyListeners();
  }

  void restSkip() {
    rest = 0;
    restOpen = false;
    restPaused = false;
    notifyListeners();
  }

  void restShow(bool open) {
    restOpen = open;
    notifyListeners();
  }

  /// "Set 2 · 12 kg × 15", or the next exercise.
  String get nextUp {
    final x = e, xs = sets[cur];
    final k = xs.indexWhere((s) => !s.done);
    if (k >= 0) {
      final s = xs[k];
      final parts = [
        for (final (j, c) in cols(x).indexed)
          text(s, j, x) + switch (c) { 'Reps' => '', 'Seconds' => ' s', 'Min' => ' min', 'Km' => ' km', _ => s.bw ? '' : ' kg' },
      ];
      return 'Set ${k + 1} · ${parts.join(' × ')}';
    }
    return cur < ex.length - 1 ? ex[cur + 1].name : 'Finish the workout';
  }

  // ─────────────────────────────── Timer

  void pauseToggle() {
    if (paused) {
      startedAt = startedAt.add(DateTime.now().difference(pausedAt!));
      pausedAt = null;
      lastActive = elapsed;
    } else {
      pausedAt = DateTime.now();
    }
    toast?.call(paused ? 'Timer paused' : 'Timer running', sub: 'Workout time ${clockText(elapsed)}', kind: ToastKind.info);
    changed();
  }

  void shift(int seconds) {
    if (seconds < 0) seconds = -math.min(-seconds, elapsed);
    startedAt = startedAt.subtract(Duration(seconds: seconds));
    changed();
  }

  void keepGoing() {
    lastActive = elapsed;
    toast?.call('Timer keeps running', sub: 'Workout time ${clockText(elapsed)}', kind: ToastKind.info);
    notifyListeners();
  }

  int? get lastTickAt => _lastTick();

  // ─────────────────────────────── Restart / clear / discard (with Undo)

  ({DateTime started, DateTime? paused, List<List<WSet>> sets, int cur, int restUsed}) _snap() =>
      (started: startedAt, paused: pausedAt, sets: [for (final xs in sets) [for (final s in xs) s.copy()]], cur: cur, restUsed: restUsed);

  void _restore(({DateTime started, DateTime? paused, List<List<WSet>> sets, int cur, int restUsed}) b) {
    startedAt = b.started;
    pausedAt = b.paused;
    sets = b.sets;
    cur = b.cur;
    restUsed = b.restUsed;
    changed();
  }

  List<WSet> _freshSets(int i) {
    final old = sets[i];
    final n = ex[i].sets;
    return [
      for (var k = 0; k < n; k++)
        if (k < old.length)
          (old[k].copy()
            ..weight = null
            ..reps = null
            ..seconds = null
            ..km = null
            ..done = false
            ..doneAt = null
            ..at = null
            ..wu = false
            ..pr = false
            ..bw = ex[i].bodyweight
            ..number = k + 1)
        else
          _fresh(ex[i], k + 1),
    ];
  }

  void restart() {
    final before = _snap();
    for (final xs in sets) {
      for (final s in xs) {
        s.done = false;
        s.doneAt = null;
        s.at = null;
        s.pr = false;
      }
    }
    startedAt = DateTime.now();
    pausedAt = null;
    cur = 0;
    restUsed = 0;
    rest = 0;
    restOpen = false;
    hold = null;
    lastActive = 0;
    toast?.call('Workout restarted', sub: 'Timer is running from 0:00', kind: ToastKind.info, undo: () => _restore(before));
    changed();
  }

  void clearExercise() {
    final before = _snap(), x = e;
    sets[cur] = _freshSets(cur);
    rest = 0;
    hold = null;
    toast?.call('${x.name} cleared', sub: 'Timer keeps going', kind: ToastKind.del, undo: () => _restore(before));
    changed();
  }

  void clearAll() {
    final before = _snap();
    sets = [for (var i = 0; i < ex.length; i++) _freshSets(i)];
    cur = 0;
    rest = 0;
    hold = null;
    toast?.call('All sets cleared', sub: 'Timer keeps going', kind: ToastKind.del, undo: () => _restore(before));
    changed();
  }

  /// Discard the whole workout: nothing is saved. After "Log more sets" the server keeps the
  /// finished workout as it was and drops only the sets ticked since.
  Future<void> discard() async {
    _tick?.cancel();
    _save?.cancel();
    if (!local && id != null) {
      try {
        await Services.outbox.enqueue('POST', 'me/workouts/$id/discard/', {}, tag: 'workout:discard');
      } on ApiError catch (_) {}
      await drain();
    }
    await Services.cache.write(_cacheKey, null);
  }

  /// Waits a moment for queued saves to reach the server, so the next page shows them.
  static Future<void> drain() async {
    for (var i = 0; i < 25 && Services.outbox.pending.value > 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  // ─────────────────────────────── Finish

  /// Saves the workout. [at] finishes at that workout time (the last set) instead of now.
  Future<void> finish({int? at}) async {
    finalSeconds = at ?? elapsed;
    finished = true;
    rest = 0;
    restOpen = false;
    hold = null;
    _tick?.cancel();
    _save?.cancel();
    _store();
    notifyListeners();
    final body = {'duration_seconds': finalSeconds, 'time_breakdown': breakdown};
    if (local) {
      _syncLater = true; // sent with the effort and the note, or when the screen closes
    } else {
      try {
        await Services.outbox.enqueue('PUT', 'me/workouts/$id/state/', _state, tag: 'workout:state');
        await Services.outbox.enqueue('POST', 'me/workouts/$id/finish/', body, tag: 'workout:finish');
      } on ApiError catch (e) {
        toast?.call('Could not save the workout', sub: e.message, kind: ToastKind.warn);
      }
    }
    await Services.cache.write(_cacheKey, null);
  }

  Map<String, int> get breakdown {
    final r = math.min(restUsed, finalSeconds);
    return {
      'active': math.max(0, finalSeconds - r),
      'rest': r,
      for (final (i, x) in ex.indexed)
        if (exTime(i) != null) 'pe:${x.peId}': exTime(i)!,
    };
  }

  /// Time on exercise [i]: from the last tick before it (or the start) to its last tick.
  int? exTime(int i) {
    final mine = [for (final s in sets[i]) if (s.done && s.at != null) s.at!];
    if (mine.isEmpty) return null;
    final first = mine.reduce(math.min);
    final before = [for (final xs in sets) for (final s in xs) if (s.done && s.at != null && s.at! < first) s.at!];
    return mine.reduce(math.max) - (before.isEmpty ? 0 : before.reduce(math.max));
  }

  double get volume {
    var v = 0.0;
    for (final (i, xs) in sets.indexed) {
      if (ex[i].kind != ExKind.weight) continue;
      for (final s in xs) {
        if (!s.done || s.wu) continue;
        final w = s.bw ? (plan.bodyweight ?? 0) + (s.weight ?? 0) : (s.weight ?? 0);
        v += w * (s.reps ?? 0);
      }
    }
    return v;
  }

  /// "Save and send to Aman": effort and note.
  Future<bool> send() async {
    if (effort == 0) return false;
    sent = true;
    notifyListeners();
    if (local) {
      await _sendLocal();
    } else {
      try {
        await Services.outbox.enqueue('POST', 'me/workouts/$id/feedback/', {'effort': effort, 'note': note.trim()}, tag: 'workout:feedback');
      } on ApiError catch (_) {}
    }
    return true;
  }

  Future<void> _sendLocal() async {
    _syncLater = false;
    await Services.outbox.enqueue(
        'POST',
        'me/workouts/sync/',
        {
          'date': DateFormat('yyyy-MM-dd').format(date),
          'program_day': plan.dayId,
          'name': name,
          'started_at': startedAt.toUtc().toIso8601String(),
          'finished_at': startedAt.add(Duration(seconds: finalSeconds)).toUtc().toIso8601String(),
          'duration_seconds': finalSeconds,
          'time_breakdown': breakdown,
          'effort': ?(effort == 0 ? null : effort),
          'note': note.trim(),
          'sets': [
            for (final xs in sets)
              for (final s in xs)
                if (s.done) {...s.toApi()..remove('id')..remove('key'), 'done_at': s.doneAt?.toUtc().toIso8601String()},
          ],
        },
        tag: 'workout:sync');
  }
}
