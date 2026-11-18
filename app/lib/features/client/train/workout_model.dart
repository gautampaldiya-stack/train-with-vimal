import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/live/live_notice.dart';
import '../../../core/widgets/overlays.dart' show ToastKind;
import 'train_model.dart';
import 'workout_feel.dart';

export 'workout_feel.dart';

/// Set types (Strong-style, tracker F38/F39). A drop set is its own row marked D, right after the set it drops from.
enum SetKind {
  normal('normal', ''),
  warmup('warmup', 'W'),
  drop('drop', 'D'),
  failure('failure', 'F');

  const SetKind(this.api, this.letter);
  final String api, letter;
  static SetKind of(String? v) => SetKind.values.firstWhere((k) => k.api == v, orElse: () => SetKind.normal);
}

/// One set in the logger. Values stay null until the client types or ticks them; until then the
/// row shows grey placeholders (the set above, else last time, else the target).
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
    this.bpm,
    this.rpe,
    this.bw = false,
    this.kind = SetKind.normal,
    this.done = false,
    this.doneAt,
    this.at,
    this.pr = false,
    this.rest,
    this.restPlanned,
    this.restActual,
  });

  int? id;
  String key;
  String exId;
  int? peId;
  int number;
  double? weight, rpe;
  int? reps, seconds, bpm;
  bool bw, done, pr;
  SetKind kind;
  DateTime? doneAt;

  bool get wu => kind == SetKind.warmup;

  /// Workout time (seconds) when it was ticked: "Where the time went".
  int? at;

  /// Rest after this set (tracker G45/G49): [rest] = this set's own timer (null = the exercise's for its type,
  /// 0 = no rest), [restPlanned] = what the timer was set to when it ran, [restActual] = what the client rested.
  int? rest, restPlanned, restActual;

  WSet copy() => WSet(id: id, key: key, exId: exId, peId: peId, number: number, weight: weight, reps: reps, seconds: seconds, bpm: bpm, rpe: rpe, bw: bw, kind: kind, done: done, doneAt: doneAt, at: at, pr: pr, rest: rest, restPlanned: restPlanned, restActual: restActual);

  bool get touched => weight != null || reps != null || seconds != null || bpm != null;

  Map<String, dynamic> toApi() => {
        'id': ?id,
        'key': key,
        'exercise': exId,
        'program_exercise': peId,
        'set_number': number,
        'weight_kg': weight?.toStringAsFixed(2),
        'reps': reps,
        'seconds': seconds,
        'bpm': bpm,
        'rpe': rpe?.toStringAsFixed(1),
        'is_bodyweight': bw,
        'is_warmup': wu,
        'set_type': kind.api,
        'done': done,
        'done_at': doneAt?.toUtc().toIso8601String(),
        'rest_seconds': rest,
        'rest_planned': restPlanned,
        'rest_actual': restActual,
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
      bpm: _i(j['bpm']),
      rpe: _d(j['rpe']),
      bw: j['is_bodyweight'] == true,
      kind: j['set_type'] != null ? SetKind.of('${j['set_type']}') : (j['is_warmup'] == true ? SetKind.warmup : SetKind.normal),
      done: j['done'] == true,
      doneAt: doneAt,
      at: _i(j['at']) ?? doneAt?.difference(startedAt).inSeconds.clamp(0, 99 * 3600),
      pr: j['pr'] == true || j['is_pr'] == true,
      rest: _i(j['rest_seconds']),
      restPlanned: _i(j['rest_planned']),
      restActual: _i(j['rest_actual']),
    );
  }
}

typedef Toaster = void Function(String title, {String? sub, ToastKind kind, VoidCallback? undo});

/// A form video picked in the logger. It goes to the coach only when the workout is finished (tracker F41), so the
/// client can change or remove it until then. The file's path is kept on the phone, so it survives leaving the app.
class PendingVideo {
  PendingVideo({required this.exId, required this.setKey, required this.exName, required this.setLabel, required this.path, required this.name, this.bytes});
  final String exId, setKey, exName, setLabel, path, name;
  Uint8List? bytes; // web: the picked file lives only in memory

  Map<String, dynamic> toJson() => {'ex': exId, 'set': setKey, 'exName': exName, 'label': setLabel, 'path': path, 'name': name};
  static PendingVideo? from(dynamic j) => j is Map
      ? PendingVideo(exId: '${j['ex']}', setKey: '${j['set']}', exName: '${j['exName']}', setLabel: '${j['label']}', path: '${j['path']}', name: '${j['name']}')
      : null;
}

/// Focus metric beside an exercise's ⋯ (tracker F40), kept per exercise for this client.
enum FocusMetric {
  volume('volume', 'Total Volume'),
  volumeUp('volume_increase', 'Volume Increase'),
  reps('reps', 'Total Reps'),
  weightReps('weight_reps', 'Weight/Reps');

  const FocusMetric(this.api, this.label);
  final String api, label;
  static FocusMetric of(String? v) => FocusMetric.values.firstWhere((f) => f.api == v, orElse: () => FocusMetric.volume);
}

/// The running workout: timer, every exercise's sets, rest, finish. One lives for the whole workout
/// ([WorkoutController.current]), so collapsing the logger to the mini bar, going to another tab or turning the
/// phone off does not stop it (tracker F33/F34). Every change is saved on the phone at once and sent through the
/// outbox (`PUT me/workouts/<id>/state/`), so it works offline; a workout started offline is sent when finished.
class WorkoutController extends ChangeNotifier {
  WorkoutController(this.plan);

  static const _cacheKey = 'workout:live';
  static const _videoKey = 'workout:videos';

  /// The workout running now (null when none). The logger, the mini bar and the notification all use it.
  static final live = ValueNotifier<WorkoutController?>(null);

  /// Goes up when a workout is finished or its effort / note is sent: Train reloads its card.
  static final saved = ValueNotifier<int>(0);
  static WorkoutController? get current => live.value;

  /// Where ⌄ (collapse) goes back to: the tab the logger was opened from.
  static String backTo = '/train';

  final TrainData plan;
  List<TrainEx> get ex => plan.exercises;
  Toaster? toast;

  String? id;
  bool local = false;

  /// Sets whose form video already went to the coach ("exercise id:set number").
  final filmed = <String>{};
  bool isFilmed(WSet s) => filmed.contains('${s.exId}:${s.number}') || videos.any((v) => v.setKey == s.key);

  /// Videos waiting for Finish.
  final videos = <PendingVideo>[];
  PendingVideo? videoOf(WSet s) {
    for (final v in videos) {
      if (v.setKey == s.key) return v;
    }
    return null;
  }

  String name = '';
  DateTime date = DateTime.now();
  DateTime startedAt = DateTime.now();
  DateTime? pausedAt;
  List<List<WSet>> sets = [];
  bool ready = false;
  String? failed;

  /// Focus metric per exercise index.
  late final List<FocusMetric> focus = [for (final x in ex) FocusMetric.of(x.focusMetric)];

  /// Rest timers per exercise index (tracker G44): working, warm-up and drop sets, in seconds (0 = off). The coach's
  /// plan, with the client's own timers on top unless the coach locked them.
  late final List<({int work, int warmup, int drop})> rests = [for (final x in ex) planRest(x)];

  static ({int work, int warmup, int drop}) planRest(TrainEx x) {
    final p = x.restLocked ? null : x.restPref;
    int? v(String k) => (p?[k] as num?)?.toInt();
    return (work: v('work') ?? x.rest, warmup: v('warmup') ?? x.restWarmup ?? x.rest, drop: v('drop') ?? x.restDrop ?? x.rest);
  }

  /// The rest that follows set [k] of exercise [i]: its own timer, else the exercise's for its set type.
  int restFor(int i, int k, {bool own = true}) {
    final s = sets[i][k];
    if (own && s.rest != null) return s.rest!;
    final r = rests[i];
    return switch (s.kind) { SetKind.warmup => r.warmup, SetKind.drop => r.drop, _ => r.work };
  }

  /// Exercise ⋯ → Rest timers: used from now on in this workout and saved as this exercise's rest for next time.
  void setRests(int i, {required int work, required int warmup, required int drop}) {
    final x = ex[i];
    if (x.restLocked) return;
    rests[i] = (work: work, warmup: warmup, drop: drop);
    toast?.call('Rest timers saved', sub: '${x.name} · this workout and next time', kind: ToastKind.ok);
    changed();
    Services.outbox
        .enqueue('PUT', 'me/exercise-prefs/${x.exId}/', {'rest_work': work, 'rest_warmup': warmup, 'rest_drop': drop}, tag: 'exercise:pref')
        .catchError((_) => null);
  }

  /// Set menu → Rest timer for this set (G45): [v] seconds after this set only; null = the exercise's again.
  void setSetRest(int i, int k, int? v) {
    if (ex[i].restLocked) return;
    if (v == 0 && sets[i][k].rest != 0) WorkoutFeel.restSkipped(); // rest removed: same sound as a skip
    sets[i][k].rest = v;
    changed();
  }

  /// The rest running now, for the web Home Rest timer card (D-87): when it ends, what is next and the workout's
  /// route. Null when no rest runs (or it is paused).
  static final liveRest = ValueNotifier<({DateTime ends, String next, String route})?>(null);

  @override
  void notifyListeners() {
    final on = rest > 0 && !restPaused && !finished && id != null;
    final v = liveRest.value;
    if (!on) {
      if (v != null) liveRest.value = null;
    } else {
      final ends = DateTime.now().add(Duration(seconds: rest));
      if (v == null || (v.ends.difference(ends).inSeconds).abs() > 2) liveRest.value = (ends: ends, next: nextUp, route: '/train/workout');
    }
    _notice();
    super.notifyListeners();
  }

  // rest timer: seconds left (worked out from [_restEnds] while it runs, so it survives the app sleeping)
  int rest = 0, restMax = 0, restUsed = 0;
  bool restPaused = false, restOpen = false;
  (int, int) restAt = (0, -1);
  DateTime? _restEnds;

  /// Workout time when this rest began, for the set's actual rest (G49).
  int _restFrom = 0;

  // hold countdown on a timed set: (exercise, set, seconds left)
  (int, int, int)? hold;

  /// Workout time of the last tick or "Keep going" (for "Still working out?").
  int lastActive = 0;

  // after Finish
  bool finished = false, sent = false, _syncLater = false;
  int finalSeconds = 0, effort = 0;
  String note = '';

  /// "That's workout 12!" on the finish page (null until known).
  int? workoutNumber;

  Timer? _tick, _save;
  bool _gone = false;

  /// Opened with "Log more sets": the added sets are timed from 0:00 and added to the first total.
  bool reopened = false;

  /// Time of the earlier part(s) of a reopened workout (for "16 min = 12 + 4").
  int earlierSeconds = 0;

  int get elapsed => ((pausedAt ?? DateTime.now()).difference(startedAt).inSeconds).clamp(0, 99 * 3600);
  bool get paused => pausedAt != null;
  int get setsDone => sets.fold(0, (a, xs) => a + xs.where((s) => s.done && !s.wu).length);
  int get setsAll => sets.fold(0, (a, xs) => a + xs.where((s) => !s.wu).length);
  bool exDone(int i) => sets[i].isNotEmpty && sets[i].every((s) => s.done);
  bool get idle => ready && !finished && !paused && elapsed - lastActive >= 1800;

  /// The exercise being worked on: the first one with a set not ticked (else the last).
  int get cur {
    final i = sets.indexWhere((xs) => xs.any((s) => !s.done));
    return i < 0 ? math.max(0, ex.length - 1) : i;
  }

  TrainEx get e => ex[cur];

  /// The logger screen closed: the workout keeps running; only a finished or discarded one is let go.
  void detach() {
    toast = null;
    if (finished || failed != null) release();
  }

  /// Ends this controller (after Finish, Discard, sign out).
  void release() {
    if (!_gone) dispose();
  }

  @override
  void dispose() {
    _gone = true;
    _tick?.cancel();
    if (_save?.isActive ?? false) {
      _save!.cancel();
      _push();
    }
    if (_syncLater) _sendLocal();
    if (live.value == this) live.value = null;
    liveRest.value = null;
    LiveNotice.clear();
    super.dispose();
  }

  // ─────────────────────────────── Open / start

  static bool _hooked = false;

  static void _hook() {
    if (_hooked) return;
    _hooked = true;
    LiveNotice.onAction = (a) => current?._action(a);
    Services.session.onSignOut.add(() async {
      final c = current;
      if (c != null) {
        c._syncLater = false;
        c.release();
      }
      await LiveNotice.clear();
    });
  }

  /// App opened (or a client signed in) while a workout was running on this phone: bring it back, so the mini bar,
  /// the clock and the notification are there without opening Train first.
  static Future<void> revive() async {
    _hook();
    if (current != null) return;
    final snap = await Services.cache.read(_cacheKey);
    if (snap is Map && snap['finished'] == true) return;
    final t = TrainController();
    try {
      await t.start();
      final d = t.data;
      if (d == null || current != null) return;
      // No workout on this phone and none on the server: nothing to bring back. (A workout started on another
      // device comes back from the server even without the phone's copy.)
      if (d.live == null && !(snap is Map && snap['local'] == true)) {
        if (snap != null) await Services.cache.write(_cacheKey, null); // finished or discarded on another device
        return;
      }
      final c = WorkoutController(d);
      await c.open();
      if (!c.ready) c.release();
    } finally {
      t.dispose();
    }
  }

  /// [start] = program day to start; [reopen] = finished workout to log more sets on.
  Future<void> open({int? start, String? reopen, String? review}) async {
    _hook();
    if (review != null) return _openReview(review);
    await LiveNotice.init();
    await WorkoutFeel.load();
    unawaited(WorkoutFeel.warm()); // the sounds are ready before the first tick
    try {
      final snap = await Services.cache.read(_cacheKey);
      final lv = plan.live;
      if (reopen != null) {
        final j = await Services.api.post<Map<String, dynamic>>('me/workouts/$reopen/reopen/');
        _fromServer(j);
      } else if (lv != null) {
        final mine = snap is Map && '${snap['id']}' == lv.id;
        if (mine && Services.outbox.pending.value > 0) {
          _fromLocal(snap.cast<String, dynamic>()); // changes still on their way to the server
        } else {
          try {
            _fromServer(await Services.api.get<Map<String, dynamic>>('me/workouts/${lv.id}/'));
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
    // A workout paused from the Train banner goes on when the logger opens.
    final resume = ready && paused && !finished;
    if (resume) {
      startedAt = startedAt.add(DateTime.now().difference(pausedAt!));
      pausedAt = null;
    }
    if (ready && reopen == null) {
      final snap = await Services.cache.read(_cacheKey);
      if (snap is Map && ('${snap['id']}' == '$id' || (local && snap['local'] == true))) _restoreRest(snap);
    }
    if (ready) {
      await _loadVideos();
      lastActive = math.max(lastActive, _lastTick() ?? 0);
      if (lastActive == 0) lastActive = elapsed;
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => _second());
      _store();
      if (resume) _push();
      final old = live.value;
      if (old != null && old != this) old.release();
      live.value = this;
    }
    notifyListeners();
  }

  /// A finished workout's Congratulations page, to rate it / write to the coach later (Probid 17 Nov). Nothing
  /// runs: no clock, no notification, not the live workout.
  Future<void> _openReview(String wid) async {
    try {
      final j = await Services.api.get<Map<String, dynamic>>('me/workouts/$wid/');
      _fromServer(j);
      reopened = false;
      earlierSeconds = 0;
      finished = true;
      finalSeconds = (j['duration_seconds'] as num? ?? 0).toInt();
      final tb = j['time_breakdown'];
      restUsed = tb is Map ? (tb['rest'] as num? ?? 0).toInt() : 0;
      effort = (j['effort'] as num?)?.toInt() ?? 0;
      note = '${j['note'] ?? ''}';
      sent = j['effort'] != null;
      ready = true;
      unawaited(_count());
    } on ApiError catch (e) {
      failed = e.offline ? 'You are offline. Connect to open this workout.' : e.message;
    }
    notifyListeners();
  }

  /// Train banner ⋯ → Pause / Resume timer, without opening the logger.
  static Future<void> setPaused(String id, {required bool pause}) async {
    final c = current;
    if (c != null && c.id == id) {
      if (c.paused != pause) c.pauseToggle();
      return;
    }
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
    final c = current;
    if (c != null && c.id == id) {
      await c.discard();
      return;
    }
    try {
      await Services.outbox.enqueue('POST', 'me/workouts/$id/discard/', {}, tag: 'workout:discard');
    } on ApiError catch (_) {}
    await drain();
    await Services.cache.write(_cacheKey, null);
    await Services.cache.write(_videoKey, null);
    await LiveNotice.clear();
  }

  /// A workout is running on this phone (started, not finished or discarded): the exit sheet says so in bold.
  static Future<bool> hasLive() async {
    if (current != null && !current!.finished) return true;
    final snap = await Services.cache.read(_cacheKey);
    return snap is Map && snap['finished'] != true;
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
    earlierSeconds = reopened ? (j['duration_seconds'] as num? ?? 0).toInt() : 0;
    restUsed = 0;
    for (final v in (j['form_videos'] as List? ?? const [])) {
      if (v is Map) filmed.add('${v['exercise']}:${v['set_number']}');
    }
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
    restUsed = j['rest_used'] as int? ?? 0;
    reopened = j['reopened'] == true;
    earlierSeconds = j['earlier'] as int? ?? 0;
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
        'rest_used': restUsed,
        'finished': finished,
        'reopened': reopened,
        'earlier': earlierSeconds,
        'sets': [for (final xs in sets) [for (final s in xs) s.toLocal()]],
        // a rest running now comes back after an app restart (G48)
        'rest': rest > 0
            ? {'ends': _restEnds?.toUtc().toIso8601String(), 'left': rest, 'max': restMax, 'paused': restPaused, 'i': restAt.$1, 'k': restAt.$2, 'from': _restFrom}
            : null,
      });

  /// The rest saved with the phone's copy of this workout, if it has not ended yet.
  void _restoreRest(Map snap) {
    final r = snap['rest'];
    if (r is! Map) return;
    final paused = r['paused'] == true;
    final ends = DateTime.tryParse('${r['ends']}')?.toLocal();
    final left = paused ? (r['left'] as num? ?? 0).toInt() : (ends == null ? 0 : (ends.difference(DateTime.now()).inMilliseconds / 1000).ceil());
    final i = (r['i'] as num? ?? 0).toInt(), k = (r['k'] as num? ?? -1).toInt();
    if (left <= 0 || i >= ex.length) {
      if (k >= 0 && i < sets.length && k < sets[i].length && ends != null && sets[i][k].restActual == null) {
        sets[i][k].restActual = math.max(0, (sets[i][k].restPlanned ?? 0)); // ran out while the app was closed
      }
      return;
    }
    rest = left;
    restMax = math.max(left, (r['max'] as num? ?? left).toInt());
    restPaused = paused;
    restAt = (i, k);
    _restFrom = (r['from'] as num? ?? elapsed).toInt();
    _restEnds = DateTime.now().add(Duration(seconds: left));
    restOpen = false;
    _alarm();
  }

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
        if (!_gone) _store();
      }
    } on ApiError catch (e) {
      toast?.call('Could not save the workout', sub: e.message, kind: ToastKind.warn);
    }
  }

  // ─────────────────────────────── Every second: rest, hold

  void _second() {
    if (finished) return;
    if (!paused) {
      final h = hold;
      if (h != null) {
        if (h.$3 <= 1) {
          hold = null;
          final (i, k, _) = h;
          if (k < sets[i].length) {
            final v = shownVal(i, k, 0);
            tick(i, k, quiet: true);
            toast?.call('Hold done', sub: '${ex[i].name} · set ${k + 1} · ${v.round()} s', kind: ToastKind.ok);
          }
        } else {
          hold = (h.$1, h.$2, h.$3 - 1);
        }
      }
      final ends = _restEnds;
      if (rest > 0 && !restPaused && ends != null) {
        rest = math.max(0, (ends.difference(DateTime.now()).inMilliseconds / 1000).ceil());
        restUsed += 1;
        if (rest > 0 && rest <= 3) WorkoutFeel.restCountdown();
        if (rest == 0) {
          _closeRest();
          WorkoutFeel.restOver();
          toast?.call('Rest is over', sub: 'Next: $nextUp', kind: ToastKind.info);
          changed();
        }
      }
    }
    if (!_gone) LiveNotice.keep();
    notifyListeners();
  }

  // ─────────────────────────────── Notification (F34)

  void _notice() {
    if (_gone || !ready || finished) return;
    if (rest > 0) {
      LiveNotice.rest(
        title: 'Next: $nextUp',
        body: '${restPaused ? 'Rest paused' : 'Rest'} · ${clockText(rest)} left',
        endsAt: DateTime.now().add(Duration(seconds: rest)),
        total: math.max(restMax, rest),
        left: rest,
        paused: restPaused,
      );
      return;
    }
    if (ex.isEmpty) {
      LiveNotice.workout(title: name, body: 'Workout in progress', startedAt: startedAt, paused: paused);
      return;
    }
    // every set ticked: Finish workout / Return to workout (Probid 17 Nov, like Strong)
    if (sets.every((xs) => xs.every((s) => s.done))) {
      LiveNotice.workout(title: 'Workout finished', body: name, startedAt: startedAt, paused: paused, actions: const ['finish', 'back']);
      return;
    }
    final i = cur;
    final xs = sets[i];
    final k = xs.indexWhere((s) => !s.done);
    final left = xs.where((s) => !s.done).length;
    // the last exercise is done but an earlier one still has sets: say which one, Open
    final back = i < ex.length - 1 && exDone(ex.length - 1);
    if (back) {
      LiveNotice.workout(
        title: ex[i].name,
        body: '$left ${left == 1 ? 'set is' : 'sets are'} not done yet. Open this exercise to finish ${left == 1 ? 'it' : 'them'}',
        startedAt: startedAt,
        paused: paused,
        actions: const ['open'],
      );
      return;
    }
    // the set has an empty box (no value, nothing to fill it from): open the app to type it (like Strong)
    if (!canTick(i, k)) {
      LiveNotice.workout(title: ex[i].name, body: 'Add values to mark as complete (${k + 1} of ${xs.length})', startedAt: startedAt, paused: paused, actions: const ['open']);
      return;
    }
    LiveNotice.workout(title: ex[i].name, body: '${setLine(i, k)} (${k + 1} of ${xs.length})', startedAt: startedAt, paused: paused, actions: const ['complete_set']);
  }

  /// Notification → Finish workout: the logger opens and asks "Finish workout?".
  bool askFinish = false;

  /// Notification → Open: the logger shows this exercise (index), once.
  int? showEx;

  void _action(String a) {
    switch (a) {
      case 'open':
        showEx = cur;
        LiveNotice.onOpen?.call();
        notifyListeners();
      case 'back':
        LiveNotice.onOpen?.call();
      case 'finish':
        askFinish = true;
        LiveNotice.onOpen?.call();
        notifyListeners();
      case 'complete_set':
        final i = cur, k = sets[i].indexWhere((s) => !s.done);
        if (k >= 0 && canTick(i, k)) {
          tick(i, k);
        } else if (k >= 0) {
          WorkoutFeel.refused();
        }
      case 'rest_pause':
        if (rest > 0) restToggle();
      case 'rest_skip':
        restSkip();
      case 'rest_add':
        if (rest > 0) restMore(30);
    }
  }

  // ─────────────────────────────── Values

  /// Column titles of an exercise (tracker F36, F42): KG · REPS, +KG · REPS for bodyweight, SEC, MIN · BPM.
  List<String> cols(TrainEx x) => switch (x.kind) {
        ExKind.cardio => ['MIN', 'BPM'],
        ExKind.time => ['SEC'],
        ExKind.weight => [x.bodyweight ? '+KG' : 'KG', 'REPS'],
      };

  /// Weight and minutes take decimals; reps, seconds and BPM are whole numbers.
  bool decimal(TrainEx x, int j) => (x.kind == ExKind.weight && j == 0) || (x.kind == ExKind.cardio && j == 0);

  static int _firstInt(String s, {bool max = false}) {
    final m = RegExp(r'\d+').allMatches(s).map((m) => int.parse(m.group(0)!)).toList();
    if (m.isEmpty) return 0;
    return max ? m.take(2).reduce(math.max) : m.first;
  }

  static num? _n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}');

  /// Value in column [j]: weight / reps, minutes / BPM, or seconds.
  double? value(TrainEx x, WSet s, int j) => switch (x.kind) {
        ExKind.cardio => j == 0 ? (s.seconds == null ? null : s.seconds! / 60) : s.bpm?.toDouble(),
        ExKind.time => s.seconds?.toDouble(),
        ExKind.weight => j == 0 ? s.weight : s.reps?.toDouble(),
      };

  /// Index of [k] among the working sets (warm-ups not counted), or -1 for a warm-up.
  int workIndex(int i, int k) {
    if (sets[i][k].wu) return -1;
    var n = 0;
    for (var m = 0; m < k; m++) {
      if (!sets[i][m].wu) n++;
    }
    return n;
  }

  /// Last time's set for this row (same working set number), for the Previous column (F37).
  Map<String, dynamic>? prevOf(int i, int k) {
    final x = ex[i], w = workIndex(i, k);
    if (w < 0 || w >= x.lastTime.length) return null;
    return x.lastTime[w];
  }

  /// "60 kg × 8", "BW+5 × 10", "45 s", "20 min · 132 bpm"; drop sets end with "(D)" (failure: see [prevFail]).
  String prevText(int i, int k) {
    final p = prevOf(i, k);
    if (p == null) return '';
    final x = ex[i];
    final t = x.setText(p);
    return p['type'] == 'drop' ? '$t (D)' : t;
  }

  /// Last time's set was a failure set: the Previous column adds a red "[F]" after the text (Strong, Probid 17 Nov).
  bool prevFail(int i, int k) => prevOf(i, k)?['type'] == 'failure';

  double? _prevVal(TrainEx x, Map<String, dynamic>? p, int j) {
    if (p == null) return null;
    return switch (x.kind) {
      ExKind.cardio => j == 0 ? (_n(p['seconds']) == null ? null : _n(p['seconds'])! / 60) : _n(p['bpm'])?.toDouble(),
      ExKind.time => _n(p['seconds'])?.toDouble(),
      ExKind.weight => j == 0 ? (_n(p['weight_kg']) ?? (p['bw'] == true ? 0 : null))?.toDouble() : _n(p['reps'])?.toDouble(),
    };
  }

  /// The grey placeholder of an empty box (tracker F36): the nearest set above with a value in this column (sets
  /// below never change it), else last time's same set, else the coach's target.
  double? placeholder(int i, int k, int j) {
    final x = ex[i], xs = sets[i], s = xs[k];
    for (var m = k - 1; m >= 0; m--) {
      final o = xs[m];
      if (o.wu != s.wu) continue;
      final v = value(x, o, j);
      if (v != null) return v;
    }
    if (s.wu) return null;
    final last = _prevVal(x, prevOf(i, k), j);
    switch (x.kind) {
      case ExKind.weight:
        if (j == 1) {
          final t = _firstInt(x.reps, max: true);
          return t > 0 ? t.toDouble() : last;
        }
        return last ?? (s.bw ? null : x.targetKg);
      case ExKind.time:
        final t = _firstInt(x.reps);
        return t > 0 ? t.toDouble() : last;
      case ExKind.cardio:
        if (j == 0) {
          final t = _firstInt(x.reps);
          return last ?? (t > 0 ? t.toDouble() : null);
        }
        return last;
    }
  }

  /// What a tick saves for this box: the typed value, else the placeholder, else 0.
  double shownVal(int i, int k, int j) => value(ex[i], sets[i][k], j) ?? placeholder(i, k, j) ?? 0;

  void _put(TrainEx x, WSet s, int j, double? v) {
    switch (x.kind) {
      case ExKind.cardio:
        if (j == 0) {
          s.seconds = v == null ? null : (v * 60).round();
        } else {
          s.bpm = v?.round();
        }
      case ExKind.time:
        s.seconds = v?.round();
      case ExKind.weight:
        if (j == 0) {
          s.weight = v == null ? null : (v * 100).round() / 100;
        } else {
          s.reps = v?.round();
        }
    }
  }

  /// Limits per column, the same as the server's (`StateSetSerializer`).
  (double, double) limits(TrainEx x, WSet s, int j) => switch (x.kind) {
        ExKind.cardio => j == 0 ? (0, 1440) : (30, 250),
        ExKind.time => (0, 86400),
        ExKind.weight => j == 0 ? (s.bw ? -200 : 0, 1000) : (0, 1000),
      };

  /// Typed into a box (null = cleared, the placeholder shows again).
  void setValue(int i, int k, int j, double? v) {
    final x = ex[i], s = sets[i][k];
    if (v != null) {
      final (lo, hi) = limits(x, s, j);
      v = v.clamp(lo, hi).toDouble();
    }
    _put(x, s, j, v);
    changed();
  }

  /// Keypad − / +: one step from what the box shows.
  void stepValue(int i, int k, int j, int dir) {
    final x = ex[i];
    setValue(i, k, j, shownVal(i, k, j) + dir * stepOf(x, j));
  }

  double stepOf(TrainEx x, int j) => switch (x.kind) {
        ExKind.cardio => 1,
        ExKind.time => 5,
        ExKind.weight => j == 1 ? 1 : (x.equipment == 'kettlebell' ? 4 : (x.equipment == 'dumbbell' ? 2 : 2.5)),
      };

  void setRpe(int i, int k, double? v) {
    sets[i][k].rpe = v;
    changed();
  }

  /// A set can be ticked only when every box shows a value (typed or placeholder). An empty KG on a
  /// bodyweight set is fine (Probid 17 Nov: the tick shakes when KG is empty, like Strong).
  bool canTick(int i, int k) {
    final x = ex[i], s = sets[i][k];
    if (s.done) return true;
    for (var j = 0; j < cols(x).length; j++) {
      if (x.kind == ExKind.weight && j == 0 && (s.bw || x.bodyweight)) continue;
      if ((value(x, s, j) ?? placeholder(i, k, j)) == null) return false;
    }
    return true;
  }

  /// Fill every box with what it shows, so a tick saves what the client sees.
  void _fill(int i, int k) {
    final x = ex[i], s = sets[i][k];
    for (var j = 0; j < cols(x).length; j++) {
      if (value(x, s, j) == null) {
        final p = placeholder(i, k, j);
        _put(x, s, j, p ?? 0);
      }
    }
  }

  /// Number text of a value: "12", "12.5", "BW+5" never (the box shows the number, the header says +KG).
  String fmt(TrainEx x, int j, double v) {
    if (x.kind == ExKind.weight && j == 0) return kg(v);
    if (x.kind == ExKind.cardio && j == 0) return kg((v * 10).round() / 10);
    return '${v.round()}';
  }

  /// "60 kg × 5", "BW × 10", "45 s", "20 min · 130 bpm" for set [k] as it would be saved.
  String setLine(int i, int k) {
    final x = ex[i], s = sets[i][k];
    String t(int j) => fmt(x, j, shownVal(i, k, j));
    return switch (x.kind) {
      ExKind.weight => '${s.bw || x.bodyweight ? bwText(shownVal(i, k, 0)) : '${t(0)} kg'} × ${t(1)}',
      ExKind.time => '${t(0)} s',
      ExKind.cardio => '${t(0)} min${value(x, s, 1) != null ? ' · ${t(1)} bpm' : ''}',
    };
  }

  /// Previous tapped: this row takes last time's values (F37).
  void usePrev(int i, int k) {
    final x = ex[i], s = sets[i][k], p = prevOf(i, k);
    if (p == null || s.done) return;
    for (var j = 0; j < cols(x).length; j++) {
      _put(x, s, j, _prevVal(x, p, j));
    }
    if (x.kind == ExKind.weight) s.bw = p['bw'] == true || x.bodyweight;
    changed();
  }

  /// Previous is shown light while the row holds exactly last time's values; changing one brings it back (F37).
  bool prevUsed(int i, int k) {
    final x = ex[i], s = sets[i][k], p = prevOf(i, k);
    if (p == null) return false;
    var any = false;
    for (var j = 0; j < cols(x).length; j++) {
      final a = value(x, s, j), b = _prevVal(x, p, j);
      if (a == null) {
        if (b != null) return false;
        continue;
      }
      any = true;
      if (b == null || (a - b).abs() > 0.001) return false;
    }
    return any;
  }

  /// SET column: W / D / F, else the working set's number.
  String label(int i, int k) {
    final s = sets[i][k];
    if (s.kind != SetKind.normal && s.kind != SetKind.failure) return s.kind.letter;
    if (s.kind == SetKind.failure) return 'F';
    return '${workIndex(i, k) + 1}';
  }

  // ─────────────────────────────── Sets

  /// Tick or untick set [k] of exercise [i]. A tick saves the placeholders as the values (F36).
  /// Unticked sets that have something to save (a value or what the box shows), for the Finish sheet.
  int get openValid {
    var n = 0;
    for (var i = 0; i < ex.length; i++) {
      for (var k = 0; k < sets[i].length; k++) {
        if (!sets[i][k].done && canTick(i, k)) n++;
      }
    }
    return n;
  }

  /// Finish → "Complete unfinished sets" (Strong, Probid 17 Nov): every unticked set that has values is ticked as
  /// it shows, without rests or sounds.
  void completeOpen() {
    for (var i = 0; i < ex.length; i++) {
      final x = ex[i];
      for (var k = 0; k < sets[i].length; k++) {
        final s = sets[i][k];
        if (s.done || !canTick(i, k)) continue;
        _fill(i, k);
        s.done = true;
        s.doneAt = DateTime.now();
        s.at = elapsed;
        s.restPlanned = restFor(i, k);
        final best = x.pr?['weight_kg'];
        final b = best is num ? best.toDouble() : double.tryParse('${best ?? ''}');
        s.pr = x.kind == ExKind.weight && !s.bw && !s.wu && b != null && (s.weight ?? 0) > b;
      }
    }
    _closeRest();
    changed();
  }

  void tick(int i, int k, {bool quiet = false}) {
    final x = ex[i], s = sets[i][k];
    final on = !s.done;
    if (on) {
      _fill(i, k);
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
    final all = exDone(i);
    final last = setsDone == setsAll && sets.every((xs) => xs.every((y) => y.done));
    final r = restFor(i, k);
    if (on) WorkoutFeel.setDone();
    if (on) s.restPlanned = r; // the timer this set had (0 = off): the coach sees it next to their plan
    if (on && r > 0 && !last) {
      _beginRest(i, k, r, open: false); // the rest runs on the line; the sheet opens only from the line / chip (Probid 17 Nov)
    } else if (on) {
      _closeRest();
    } else if (restAt == (i, k)) {
      _closeRest(); // unticked the set this rest belongs to
      s.restActual = null;
      s.restPlanned = null;
    }
    if (on && s.pr) {
      toast?.call('New best!', sub: '${x.name} · ${kg(s.weight!)} kg × ${s.reps}', kind: ToastKind.star);
    } else if (on && all && !quiet) {
      final next = sets.indexWhere((xs) => xs.any((y) => !y.done));
      toast?.call('${x.name} done', sub: next >= 0 ? 'Next: ${ex[next].name}' : 'Last one. Finish when you are ready', kind: ToastKind.ok);
    }
    changed();
  }

  /// "Add set" (F36): a new row under the last one; its boxes show the last row's values as placeholders.
  void addSet(int i) {
    final x = ex[i], xs = sets[i];
    final last = xs.isEmpty ? null : xs.last;
    xs.add(WSet(key: const Uuid().v4(), exId: x.exId, peId: x.peId, number: (last?.number ?? 0) + 1, bw: last?.bw ?? x.bodyweight));
    _renumber(i);
    changed();
  }

  /// Use last time (set menu, F38): every set not ticked takes last time's values in order; extra past sets are added.
  void fillFrom(int i, List<Map<String, dynamic>> past, {String from = 'last time'}) {
    final work = [for (final p in past) if (p['is_warmup'] != true && p['wu'] != true && p['type'] != 'warmup') p];
    if (work.isEmpty) {
      toast?.call('Nothing from last time', sub: '${ex[i].name} has no past sets yet', kind: ToastKind.info);
      return;
    }
    final before = _snap();
    final x = ex[i], xs = sets[i];
    final open = xs.where((s) => !s.wu).toList();
    var filled = 0;
    for (var k = 0; k < math.max(open.length, work.length); k++) {
      final WSet s;
      if (k < open.length) {
        s = open[k];
      } else {
        s = WSet(key: const Uuid().v4(), exId: x.exId, peId: x.peId, number: xs.length + 1, bw: x.bodyweight);
        xs.add(s);
      }
      if (s.done) continue;
      final p = work[math.min(k, work.length - 1)];
      s.weight = WSet._d(p['weight_kg']);
      s.reps = WSet._i(p['reps']);
      s.seconds = WSet._i(p['seconds']);
      s.bpm = WSet._i(p['bpm']);
      s.bw = p['bw'] == true || p['is_bodyweight'] == true;
      s.kind = SetKind.of('${p['type'] ?? p['set_type'] ?? 'normal'}');
      filled += 1;
    }
    _renumber(i);
    if (filled == 0) {
      toast?.call('All sets are ticked', sub: 'Add a set to log more', kind: ToastKind.info);
      return;
    }
    toast?.call('Sets filled from $from', sub: '${x.name} · $filled ${filled == 1 ? 'set' : 'sets'}. Change any value, then tick', kind: ToastKind.ok, undo: () => _restore(before));
    changed();
  }

  /// Swipe left → delete, with Undo.
  void deleteSet(int i, int k) {
    final before = _snap();
    final x = ex[i];
    final s = sets[i].removeAt(k);
    videos.removeWhere((v) => v.setKey == s.key);
    _saveVideos();
    _renumber(i);
    toast?.call('Set deleted', sub: x.name, kind: ToastKind.del, undo: () => _restore(before));
    changed();
  }

  /// Set menu: Warm up / Drop set / Failure, or back to a work set when the same type is picked again.
  void setKind(int i, int k, SetKind kind) {
    final s = sets[i][k];
    s.kind = s.kind == kind ? SetKind.normal : kind;
    if (s.wu) s.pr = false;
    changed();
  }

  void toggleBw(int i, int k) {
    final s = sets[i][k];
    s.bw = !s.bw;
    s.weight = s.bw ? null : s.weight;
    changed();
  }

  void _renumber(int i) {
    for (final (n, s) in sets[i].indexed) {
      s.number = n + 1;
    }
  }

  void startHold(int i, int k) {
    _closeRest();
    hold = (i, k, shownVal(i, k, 0).round());
    notifyListeners();
  }

  void stopHold() {
    hold = null;
    toast?.call('Hold stopped', sub: 'Tick the set if you finished it', kind: ToastKind.info);
    notifyListeners();
  }

  // ─────────────────────────────── Focus metric (F40)

  /// Volume of the done working sets of exercise [i] (warm-ups never count, cardio never counts).
  double exVolume(int i) => ex[i].kind != ExKind.weight ? 0 : sets[i].fold(0.0, (a, s) => a + setVolume(s));

  double _lastVolume(int i) {
    final x = ex[i];
    if (x.kind != ExKind.weight) return 0;
    var v = 0.0;
    for (final p in x.lastTime) {
      if (p['type'] == 'warmup') continue;
      final r = _n(p['reps'])?.toDouble() ?? 0, w = _n(p['weight_kg'])?.toDouble() ?? 0;
      v += ((p['bw'] == true ? (plan.bodyweight ?? 0) : 0) + w) * r;
    }
    return v;
  }

  int exReps(int i) => sets[i].where((s) => s.done && !s.wu).fold(0, (a, s) => a + (s.reps ?? 0));

  /// The chip text for metric [f] of exercise [i]: "557 kg", "+12%", "21 reps", "26.52 kg".
  String focusText(int i, FocusMetric f) {
    final fmt = NumberFormat.decimalPattern('en_IN');
    switch (f) {
      case FocusMetric.volume:
        return '${fmt.format(exVolume(i).round())} kg';
      case FocusMetric.volumeUp:
        final last = _lastVolume(i);
        if (last == 0) return '+0%';
        final p = ((exVolume(i) - last) / last * 100).round();
        return '${p >= 0 ? '+' : ''}$p%';
      case FocusMetric.reps:
        return '${exReps(i)} reps';
      case FocusMetric.weightReps:
        final r = exReps(i);
        return '${r == 0 ? '0' : (exVolume(i) / r).toStringAsFixed(2)} kg';
    }
  }

  void setFocus(int i, FocusMetric f) {
    focus[i] = f;
    notifyListeners();
    Services.outbox.enqueue('PUT', 'me/exercise-prefs/${ex[i].exId}/', {'focus_metric': f.api}, tag: 'exercise:pref').catchError((_) => null);
  }

  // ─────────────────────────────── Form videos (F41)

  Future<void> _loadVideos() async {
    final raw = await Services.cache.read(_videoKey);
    if (raw is! Map || '${raw['workout']}' != (id ?? 'local')) return;
    videos
      ..clear()
      ..addAll([for (final v in (raw['items'] as List? ?? const [])) ?PendingVideo.from(v)].where((v) => v.path.isNotEmpty && !v.path.startsWith('blob:')));
  }

  void _saveVideos() => Services.cache.write(_videoKey, {
        'workout': id ?? 'local',
        'items': [for (final v in videos) if (v.bytes == null) v.toJson()],
      });

  void pickVideo(int i, int k, {required String path, required String name, Uint8List? bytes}) {
    final s = sets[i][k];
    videos.removeWhere((v) => v.setKey == s.key);
    videos.add(PendingVideo(exId: s.exId, setKey: s.key, exName: ex[i].name, setLabel: label(i, k), path: path, name: name, bytes: bytes));
    _saveVideos();
    toast?.call('Video added', sub: '${ex[i].name} · set ${label(i, k)}. It goes to ${plan.coachFirst} when you finish', kind: ToastKind.ok);
    notifyListeners();
  }

  void removeVideo(PendingVideo v) {
    videos.remove(v);
    _saveVideos();
    notifyListeners();
  }

  /// After Finish: every picked video goes to the coach (needs the internet; the server already has the workout).
  Future<void> _sendVideos(Future<Uint8List> Function(String path) read) async {
    if (videos.isEmpty || id == null) return;
    var ok = 0;
    for (final v in [...videos]) {
      final xs = [for (final xs in sets) ...xs];
      final s = xs.where((s) => s.key == v.setKey).firstOrNull;
      try {
        final b = v.bytes ?? await read(v.path);
        await Services.api.upload<Map>('me/workouts/$id/form-video/',
            FormData.fromMap({'file': MultipartFile.fromBytes(b, filename: v.name), 'exercise': v.exId, 'set_number': ?s?.number}));
        filmed.add('${v.exId}:${s?.number}');
        videos.remove(v);
        ok += 1;
      } on ApiError catch (e) {
        toast?.call('Could not send a video', sub: '${v.exName}: ${e.field('file') ?? e.message}', kind: ToastKind.warn);
      } catch (_) {
        toast?.call('Could not send a video', sub: '${v.exName}: the file is no longer on the phone', kind: ToastKind.warn);
        videos.remove(v);
      }
    }
    _saveVideos();
    if (ok > 0) toast?.call(ok == 1 ? 'Form video sent' : '$ok form videos sent', sub: '${plan.coachFirst} will check your form', kind: ToastKind.ok);
    notifyListeners();
  }

  // ─────────────────────────────── Rest

  /// Starts a rest of [secs] after set [k] of exercise [i] (k = -1: started from the rest chip).
  void _beginRest(int i, int k, int secs, {bool open = true}) {
    _closeRest();
    rest = secs;
    restMax = secs;
    restPaused = false;
    restOpen = open;
    restAt = (i, k);
    _restFrom = elapsed;
    _restEnds = DateTime.now().add(Duration(seconds: secs));
    _alarm();
  }

  /// The rest is over (ran out, skipped, or the next set was ticked): the set keeps what was really rested (G49).
  void _closeRest() {
    final (i, k) = restAt;
    if (_restEnds != null && k >= 0 && i < sets.length && k < sets[i].length) {
      sets[i][k].restActual = math.max(0, elapsed - _restFrom);
    }
    _restEnds = null;
    rest = 0;
    restOpen = false;
    restPaused = false;
    LiveNotice.cancelRestDone();
  }

  /// "Rest is over" notification at the end time, so it rings with the app in the background (G48/G50).
  void _alarm() {
    final ends = _restEnds;
    if (ends == null || restPaused || finished) {
      LiveNotice.cancelRestDone();
      return;
    }
    LiveNotice.restDone(at: ends, next: nextUp, sound: WorkoutFeel.sound, vibrate: WorkoutFeel.haptics);
  }

  void restNow(int i, [int? secs]) {
    _beginRest(i, -1, secs ?? (rests[i].work > 0 ? rests[i].work : 90));
    notifyListeners();
  }

  /// Rest line tap → Start now: the rest after set [k] of exercise [i], [secs] long (its own rest when null).
  void restStart(int i, int k, [int? secs]) {
    final v = secs ?? restFor(i, k);
    _beginRest(i, k, v > 0 ? v : 90);
    changed();
  }

  /// Rest sheet → Change: the running rest becomes [v] long in all (what has passed stays passed), and the set it
  /// follows keeps [v] as its own rest.
  void restEdit(int v) {
    if (v <= 0) {
      restSkip();
      return;
    }
    final used = math.max(0, restMax - rest);
    restMax = v;
    rest = math.max(1, v - used);
    if (!restPaused) _restEnds = DateTime.now().add(Duration(seconds: rest));
    final (i, k) = restAt;
    if (k >= 0 && i < sets.length && k < sets[i].length && !ex[i].restLocked) sets[i][k].rest = v;
    _alarm();
    changed();
  }

  void restMore([int s = 15]) {
    rest += s;
    restMax = math.max(restMax, rest);
    _restEnds = _restEnds?.add(Duration(seconds: s));
    _alarm();
    notifyListeners();
  }

  void restLess() {
    final cut = math.min(15, rest - 1);
    rest -= cut;
    _restEnds = _restEnds?.subtract(Duration(seconds: cut));
    _alarm();
    notifyListeners();
  }

  /// Back to the full time (rest sheet → Reset).
  void restReset() {
    rest = restMax;
    if (!restPaused) _restEnds = DateTime.now().add(Duration(seconds: rest));
    _alarm();
    notifyListeners();
  }

  void restToggle() {
    restPaused = !restPaused;
    // paused: the time left stays; resumed: a new end time from now
    _restEnds = DateTime.now().add(Duration(seconds: rest));
    _alarm();
    notifyListeners();
  }

  void restSkip() {
    _closeRest();
    WorkoutFeel.restSkipped();
    changed();
  }

  void restShow(bool open) {
    restOpen = open;
    notifyListeners();
  }

  /// "Squat (Barbell)" when its sets are left, "Finish the workout" when all are done.
  String get nextUp {
    final i = sets.indexWhere((xs) => xs.any((s) => !s.done));
    if (i < 0) return 'Finish the workout';
    final k = sets[i].indexWhere((s) => !s.done);
    return '${ex[i].name} · ${setLine(i, k)}';
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

  /// "Keep going" on "Still working out?": no toast after the sheet (Probid 17 Nov).
  void keepGoing() {
    lastActive = elapsed;
    notifyListeners();
  }

  int? get lastTickAt => _lastTick();

  // ─────────────────────────────── Restart / discard (with Undo)

  ({DateTime started, DateTime? paused, List<List<WSet>> sets, int restUsed}) _snap() =>
      (started: startedAt, paused: pausedAt, sets: [for (final xs in sets) [for (final s in xs) s.copy()]], restUsed: restUsed);

  void _restore(({DateTime started, DateTime? paused, List<List<WSet>> sets, int restUsed}) b) {
    startedAt = b.started;
    pausedAt = b.paused;
    sets = b.sets;
    restUsed = b.restUsed;
    changed();
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
    _closeRest();
    for (final xs in sets) {
      for (final s in xs) {
        s.restPlanned = null;
        s.restActual = null;
      }
    }
    startedAt = DateTime.now();
    pausedAt = null;
    restUsed = 0;
    hold = null;
    lastActive = 0;
    if (reopened) {
      // After "Log more sets" Restart starts the whole workout again (today only, Probid 17 Nov): the finished
      // part is gone too, so there is no Undo.
      reopened = false;
      earlierSeconds = 0;
      if (!local && id != null) {
        unawaited(Services.outbox.enqueue('POST', 'me/workouts/$id/restart/', {'fresh': true, 'started_at': startedAt.toUtc().toIso8601String()}, tag: 'workout:restart')
            .then((_) {}, onError: (_) {}));
      }
      toast?.call('Workout restarted', sub: 'The whole workout starts again from 0:00', kind: ToastKind.info);
    } else {
      toast?.call('Workout restarted', sub: 'Timer is running from 0:00', kind: ToastKind.info, undo: () => _restore(before));
    }
    changed();
  }

  /// Cancel workout: nothing is saved. After "Log more sets" the server keeps the finished workout as it was and
  /// drops only the sets added since.
  /// [all]: after "Log more sets" the whole workout goes, the finished part too (today only, Probid 17 Nov).
  Future<void> discard({bool all = false}) async {
    _tick?.cancel();
    _save?.cancel();
    _syncLater = false;
    if (!local && id != null) {
      try {
        await Services.outbox.enqueue('POST', 'me/workouts/$id/discard/', {if (all) 'all': true}, tag: 'workout:discard');
      } on ApiError catch (_) {}
      await drain();
    }
    await Services.cache.write(_cacheKey, null);
    await Services.cache.write(_videoKey, null);
    videos.clear();
    finished = true; // nothing more runs
    release();
  }

  /// Waits a moment for queued saves to reach the server, so the next page shows them.
  static Future<void> drain() async {
    for (var i = 0; i < 25 && Services.outbox.pending.value > 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  // ─────────────────────────────── Finish

  /// Saves the workout. [at] finishes at that workout time (the last set) instead of now. [read] loads a picked
  /// video's file for the upload.
  Future<void> finish({int? at, Future<Uint8List> Function(String path)? read}) async {
    finalSeconds = at ?? elapsed;
    _closeRest();
    finished = true;
    hold = null;
    _tick?.cancel();
    _save?.cancel();
    _store();
    await LiveNotice.clear();
    liveRest.value = null;
    notifyListeners();
    final body = {'duration_seconds': finalSeconds, 'time_breakdown': breakdown};
    if (local) {
      // saved now (Probid 17 Nov: finish = saved); the effort and note can follow later
      try {
        final r = await _sendLocal();
        if (r is Map && r['id'] != null) {
          id = '${r['id']}';
          local = false;
        }
      } on ApiError catch (e) {
        toast?.call('Could not save the workout', sub: e.message, kind: ToastKind.warn);
      }
    } else {
      try {
        await Services.outbox.enqueue('PUT', 'me/workouts/$id/state/', _state, tag: 'workout:state');
        await Services.outbox.enqueue('POST', 'me/workouts/$id/finish/', body, tag: 'workout:finish');
      } on ApiError catch (e) {
        toast?.call('Could not save the workout', sub: e.message, kind: ToastKind.warn);
      }
    }
    await Services.cache.write(_cacheKey, null);
    saved.value++;
    if (read != null) unawaited(_sendVideos(read));
    unawaited(_count());
  }

  /// "That's workout 12!": how many workouts the client has finished (this one included).
  Future<void> _count() async {
    try {
      await drain();
      final j = await Services.api.get<Map<String, dynamic>>('me/workouts/', query: {'page_size': 1});
      final n = (j['count'] as num?)?.toInt();
      if (n != null && n > 0) {
        workoutNumber = local ? n + 1 : n;
        if (!_gone) notifyListeners();
      }
    } catch (_) {}
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

  /// kg × reps of one set, the same rule as the server (backend apps/common/calc.py `set_volume`, D-82):
  /// 0 for a warm-up, a set not done or no reps; a bodyweight set counts body weight + added load.
  double setVolume(WSet s) {
    if (!s.done || s.wu || (s.reps ?? 0) == 0) return 0;
    final w = s.bw ? (plan.bodyweight ?? 0) + (s.weight ?? 0) : (s.weight ?? 0);
    return w * s.reps!;
  }

  double get volume {
    var v = 0.0;
    for (var i = 0; i < ex.length; i++) {
      v += exVolume(i);
    }
    return v;
  }

  /// Personal bests set in this workout.
  int get prs => sets.fold(0, (a, xs) => a + xs.where((s) => s.done && s.pr).length);

  /// Finish card: "4 × Squat (Barbell)" and its best set "12 kg × 5" for each exercise with a done set.
  List<({String line, String best})> get summary => [
        for (final (i, x) in ex.indexed)
          if (sets[i].any((s) => s.done && !s.wu))
            (
              line: '${sets[i].where((s) => s.done && !s.wu).length} × ${x.name}',
              best: () {
                final done = [for (final (k, s) in sets[i].indexed) if (s.done && !s.wu) k];
                if (x.kind != ExKind.weight) return setLine(i, done.last);
                done.sort((a, b) => setVolume(sets[i][b]).compareTo(setVolume(sets[i][a])));
                return setLine(i, done.first);
              }(),
            ),
      ];

  /// "Save and send to Aman": effort and note.
  Future<bool> send() async {
    if (effort == 0) return false;
    sent = true;
    notifyListeners();
    if (local) {
      // saved offline and still on its way: the server has no id to send it to yet
      sent = false;
      toast?.call('Your workout is saved', sub: 'Send this to ${plan.coachFirst} from Train when you are online', kind: ToastKind.info);
      notifyListeners();
      return true;
    } else {
      try {
        await Services.outbox.enqueue('POST', 'me/workouts/$id/feedback/', {'effort': effort, 'note': note.trim()}, tag: 'workout:feedback');
        saved.value++;
      } on ApiError catch (_) {}
    }
    return true;
  }

  Future<dynamic> _sendLocal() async {
    _syncLater = false;
    return Services.outbox.enqueue(
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
