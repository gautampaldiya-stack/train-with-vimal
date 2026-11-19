import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import 'logger_menus.dart';
import 'train_model.dart';
import 'workout_feel.dart';
import 'workout_model.dart' show FocusMetric, SetKind;

/// Edit workout (tracker H51-H55), a page like Strong's "Edit workout" (Probid 19 Nov): X on the left asks before the
/// changes are thrown away, ✓ on the right saves. Each exercise has SET · PREVIOUS · KG · REPS · ✓ rows; a ticked
/// set is a green row. Only ticked sets are saved. Start / end time sit behind the workout's ⋯ (and its time line).
/// Saving makes a new version; the coach sees what changed. Returns true when it was saved.
Future<bool> showEditWorkout(BuildContext context, String workoutId) async {
  final r = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(builder: (_) => _EditPage(id: workoutId)),
  );
  return r == true;
}

/// Yesterday's workout, missed on the day, logged afterwards (H51a): the same page, with the plan's exercises and
/// empty sets. The client types and ticks what was done, and sets the start / end time.
Future<bool> showLogPastWorkout(BuildContext context, TrainData d) async {
  final r = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(builder: (_) => _EditPage(past: d)),
  );
  return r == true;
}

class _Set {
  _Set({this.id, required this.key, this.kind = SetKind.normal, this.bw = false, this.done = false, this.rest, this.keep = const {}, String kg = '', String reps = '', String secs = '', String bpm = ''})
      : kg = TextEditingController(text: kg),
        reps = TextEditingController(text: reps),
        secs = TextEditingController(text: secs),
        bpm = TextEditingController(text: bpm);
  final int? id;
  final String key;
  SetKind kind;
  bool bw, done;

  /// Rest after this set, in seconds (what was rested; null = none). Saved as the set's rest taken.
  int? rest;

  /// Fields this page does not show (RPE, rest, the rest timer and the rest taken): sent back as they were.
  final Map<String, dynamic> keep;
  final TextEditingController kg, reps, secs, bpm;

  List<TextEditingController> get _all => [kg, reps, secs, bpm];
  bool get empty => _all.every((c) => c.text.trim().isEmpty);

  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
  }
}

class _Ex {
  _Ex({required this.exId, required this.name, required this.logType, this.peId, this.prev = const [], this.restWork = 0, this.restWarmup, this.restDrop, this.focus = FocusMetric.volume, List<_Set>? sets})
      : sets = sets ?? [];
  final String exId, name, logType;
  final int? peId;

  /// The coach's rest after a work / warm-up / drop set: what a new set starts with (the logger's rest timers).
  final int restWork;
  final int? restWarmup, restDrop;
  int restOf(SetKind k) => switch (k) { SetKind.warmup => restWarmup ?? restWork, SetKind.drop => restDrop ?? restWork, _ => restWork };

  /// The chip beside the name, like the logger's (Total volume, Volume increase, Total reps, Weight/Reps).
  FocusMetric focus;

  /// The sets of the workout before this one (the PREVIOUS column), working sets in order.
  final List<Map<String, dynamic>> prev;
  final List<_Set> sets;
  bool get cardio => logType == 'distance';
  bool get timed => logType == 'time';
  bool get body => logType == 'bodyweight_reps';
  List<String> get cols => cardio ? const ['MIN', 'BPM'] : (timed ? const ['SEC'] : [body ? '+KG' : 'KG', 'REPS']);
}

String _num(dynamic v) {
  if (v == null) return '';
  final n = v is num ? v.toDouble() : double.tryParse('$v');
  if (n == null) return '';
  return kg(n);
}

class _EditPage extends StatefulWidget {
  const _EditPage({this.id, this.past});
  final String? id;
  final TrainData? past;
  @override
  State<_EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<_EditPage> {
  final _ex = <_Ex>[];
  Map<String, dynamic>? _w;
  String? _error;
  bool _saving = false;
  late DateTime _start, _end;
  DateTime? _start0, _end0;
  int _keyN = 0;
  String _first = '';
  final _scroll = ScrollController();
  bool _scrolled = false;

  bool get _past => widget.past != null;
  bool get _ready => _past || _w != null;

  /// The tick or PREVIOUS that shakes (nothing to fill), and a counter so each refused tap shakes again.
  (String, int)? _shake;

  @override
  void initState() {
    super.initState();
    // the logger's sounds and vibration here too (Probid 19 Nov)
    unawaited(WorkoutFeel.load().then((_) => WorkoutFeel.warm()));
    _scroll.addListener(() {
      final s = _scroll.offset > 2;
      if (s != _scrolled) setState(() => _scrolled = s);
    });
    if (_past) {
      _fromPlan(widget.past!);
      _first = _snapshot();
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final e in _ex) {
      for (final s in e.sets) {
        s.dispose();
      }
    }
    super.dispose();
  }

  String _key() => 'e${DateTime.now().microsecondsSinceEpoch}-${_keyN++}';

  void _fromPlan(TrainData d) {
    final day = d.date;
    // a usual evening time; the client changes it
    _start = DateTime(day.year, day.month, day.day, 18);
    _end = _start.add(Duration(minutes: d.minutes > 0 ? d.minutes : 45));
    for (final e in d.exercises) {
      _ex.add(_Ex(
        exId: e.exId,
        name: e.name,
        logType: e.logType,
        peId: e.peId,
        prev: e.lastTime,
        restWork: e.rest,
        restWarmup: e.restWarmup,
        restDrop: e.restDrop,
        focus: FocusMetric.of(e.focusMetric),
        sets: [for (var i = 0; i < (e.sets > 0 ? e.sets : 1); i++) _Set(key: _key(), bw: e.bodyweight, rest: e.rest > 0 ? e.rest : null)],
      ));
    }
  }

  Future<void> _load() async {
    try {
      final r = await Services.api.get<Map<String, dynamic>>('me/workouts/${widget.id}/edit/');
      final j = (r['workout'] as Map).cast<String, dynamic>();
      final prev = (r['previous'] as Map? ?? const {}).cast<String, dynamic>();
      final end = DateTime.parse('${j['finished_at']}').toLocal();
      final secs = (j['duration_seconds'] as num? ?? 0).toInt();
      _start0 = end.subtract(Duration(seconds: secs));
      _end0 = end;
      _start = _start0!;
      _end = end;
      final by = <String, _Ex>{};
      for (final raw in (j['sets'] as List? ?? const [])) {
        final s = (raw as Map).cast<String, dynamic>();
        if (s['done'] != true) continue;
        final k = '${s['exercise']}';
        final e = by.putIfAbsent(k, () {
          final x = _Ex(
            exId: k,
            name: '${s['exercise_name'] ?? ''}',
            logType: '${s['log_type'] ?? 'weight_reps'}',
            peId: (s['program_exercise'] as num?)?.toInt(),
            prev: [for (final p in (prev[k] as List? ?? const [])) (p as Map).cast<String, dynamic>()],
          );
          _ex.add(x);
          return x;
        });
        final secsV = (s['seconds'] as num?)?.toInt();
        int? n(String f) => (s[f] as num?)?.toInt();
        final rest = n('rest_actual') ?? n('rest_seconds') ?? n('rest_planned');
        e.sets.add(_Set(
          id: (s['id'] as num?)?.toInt(),
          key: '${s['client_key'] ?? ''}'.isEmpty ? _key() : '${s['client_key']}',
          kind: SetKind.of('${s['set_type'] ?? 'normal'}'),
          bw: s['is_bodyweight'] == true,
          done: true,
          rest: rest == null || rest <= 0 ? null : rest,
          keep: {for (final f in ['rpe', 'rest_seconds', 'rest_planned']) f: s[f]},
          kg: _num(s['weight_kg']),
          reps: s['reps'] == null ? '' : '${s['reps']}',
          secs: secsV == null ? '' : (e.cardio ? kg(secsV / 60) : '$secsV'),
          bpm: s['bpm'] == null ? '' : '${s['bpm']}',
        ));
      }
      _w = j;
      _error = null;
      _first = _snapshot();
    } on ApiError catch (e) {
      _error = e.offline ? 'You are offline. Connect to edit this workout.' : 'Could not open this workout. Try again.';
    }
    if (mounted) setState(() {});
  }

  // ─────────────────────────────── Data

  List<Map<String, dynamic>> get _segments => [for (final s in (_w?['segments'] as List? ?? const [])) (s as Map).cast<String, dynamic>()];

  bool get _timesChanged => _start0 == null || _start.difference(_start0!).inSeconds.abs() >= 60 || _end.difference(_end0!).inSeconds.abs() >= 60;

  /// What the page holds now, to tell whether anything changed (X asks only then).
  String _snapshot() => [
        _start.toIso8601String(),
        _end.toIso8601String(),
        for (final e in _ex)
          for (final s in e.sets) '${e.exId}|${s.kind.api}|${s.done}|${s.kg.text}|${s.reps.text}|${s.secs.text}|${s.bpm.text}|${s.rest}',
      ].join(';');

  bool get _dirty => _ready && _snapshot() != _first;

  Map<String, dynamic> _row(_Ex e, _Set s, int n) {
    double? d(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));
    int? i(TextEditingController c) => int.tryParse(c.text.trim());
    final minutes = d(s.secs);
    return {
      ...s.keep,
      'rest_actual': s.rest,
      'rest_planned': s.keep['rest_planned'] ?? s.rest,
      if (s.id != null) 'id': s.id,
      'key': s.key,
      'exercise': e.exId,
      'program_exercise': e.peId,
      'set_number': n,
      'set_type': s.kind.api,
      'is_bodyweight': s.bw,
      'weight_kg': e.cardio || e.timed ? null : d(s.kg),
      'reps': e.cardio || e.timed ? null : i(s.reps),
      'seconds': e.cardio ? (minutes == null ? null : (minutes * 60).round()) : (e.timed ? i(s.secs) : null),
      'bpm': e.cardio ? i(s.bpm) : null,
    };
  }

  /// The PREVIOUS set for set [k]: the same working set of the last time (warm-ups count apart).
  Map<String, dynamic>? _prevOf(_Ex e, int k) {
    final s = e.sets[k];
    if (s.kind == SetKind.warmup) return null;
    final w = e.sets.take(k + 1).where((x) => x.kind != SetKind.warmup).length - 1;
    final work = e.prev.where((p) => p['type'] != 'warmup').toList();
    return w >= 0 && w < work.length ? work[w] : null;
  }

  String _prevText(_Ex e, Map<String, dynamic>? p) {
    if (p == null) return '';
    num? n(String k) => p[k] is num ? p[k] as num : num.tryParse('${p[k] ?? ''}');
    if (e.cardio) {
      final sec = n('seconds'), bpm = n('bpm');
      return [if (sec != null) '${(sec / 60).round()} min', if (bpm != null) '$bpm bpm'].join(' · ');
    }
    if (e.timed) return n('seconds') == null ? '' : '${n('seconds')} s';
    final w = n('weight_kg')?.toDouble() ?? 0;
    return '${p['bw'] == true ? bwText(w) : '${kg(w)} kg'} × ${n('reps') ?? '—'}';
  }

  /// The values of the PREVIOUS set, as they go in the boxes (KG, REPS / SEC / MIN, BPM).
  List<String> _prevValues(_Ex e, Map<String, dynamic>? p) {
    if (p == null) return const [];
    num? n(String k) => p[k] is num ? p[k] as num : num.tryParse('${p[k] ?? ''}');
    if (e.cardio) return [n('seconds') == null ? '' : kg(n('seconds')! / 60), n('bpm') == null ? '' : '${n('bpm')}'];
    if (e.timed) return [n('seconds') == null ? '' : '${n('seconds')}'];
    return [n('weight_kg') == null ? '' : kg(n('weight_kg')!.toDouble()), n('reps') == null ? '' : '${n('reps')}'];
  }

  List<TextEditingController> _boxes(_Ex e, _Set s) => e.cardio ? [s.secs, s.bpm] : (e.timed ? [s.secs] : [s.kg, s.reps]);

  /// kg lifted in the ticked working sets of one exercise (the chip beside its name, like Strong).
  double _volume(_Ex e) {
    if (e.cardio || e.timed) return 0;
    var v = 0.0;
    for (final s in e.sets) {
      if (!s.done || s.kind == SetKind.warmup) continue;
      final w = double.tryParse(s.kg.text.trim().replaceAll(',', '.')) ?? 0, r = int.tryParse(s.reps.text.trim()) ?? 0;
      v += w * r;
    }
    return v;
  }

  // ─────────────────────────────── Actions

  void _tick(_Ex e, int k) {
    final s = e.sets[k];
    if (s.done) {
      setState(() => s.done = false);
      return;
    }
    final boxes = _boxes(e, s);
    if (boxes.every((c) => c.text.trim().isEmpty)) {
      // an empty set takes the PREVIOUS values, like Strong; with nothing to take the tick shakes and the phone buzzes
      final pv = _prevValues(e, _prevOf(e, k));
      if (pv.every((v) => v.isEmpty)) {
        _refuse('tick:${s.key}');
        return;
      }
      for (var j = 0; j < boxes.length && j < pv.length; j++) {
        boxes[j].text = pv[j];
      }
    }
    WorkoutFeel.setDone();
    setState(() => s.done = true);
  }

  void _refuse(String tag) {
    WorkoutFeel.refused();
    setState(() => _shake = (tag, (_shake?.$2 ?? 0) + 1));
  }

  Widget _shaking(Widget child, String tag) {
    final sh = _shake;
    if (sh == null || sh.$1 != tag) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey('$tag:${sh.$2}'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      builder: (_, v, child) => Transform.translate(offset: Offset(math.sin(v * math.pi * 6) * 6 * (1 - v), 0), child: child),
      child: child,
    );
  }

  Future<void> _close() async {
    FocusScope.of(context).unfocus();
    if (_dirty) {
      final ok = await confirmAction(
        context,
        title: _past ? 'Discard this workout?' : 'Discard changes?',
        body: _past ? 'Nothing you typed here is saved.' : 'The changes you made now are not saved. The workout stays as it was.',
        confirm: 'Discard',
        cancel: 'Keep editing',
        danger: true,
        icon: AppIcons.trash,
        center: true,
      );
      if (!ok || !mounted) return;
    }
    Navigator.of(context).pop(false);
  }

  Future<void> _save() async {
    if (_saving || !_ready) return;
    FocusScope.of(context).unfocus();
    if (!_end.isAfter(_start)) {
      showToast(context, 'The end must be after the start', kind: ToastKind.warn);
      return;
    }
    final sets = <Map<String, dynamic>>[];
    var open = 0;
    for (final e in _ex) {
      var n = 0;
      for (final s in e.sets) {
        if (s.empty) continue;
        if (!s.done) {
          open++;
          continue; // only ticked sets are saved
        }
        sets.add(_row(e, s, ++n));
      }
    }
    if (_past && sets.isEmpty) {
      showToast(context, 'Tick at least one set', sub: 'Type what you did and tick the set', kind: ToastKind.warn);
      return;
    }
    if (open > 0) {
      final ok = await confirmAction(
        context,
        title: '$open ${open == 1 ? 'set is' : 'sets are'} not ticked',
        body: 'Only ticked sets are saved. Tick the sets you did, or save without them.',
        confirm: 'Save without them',
        cancel: 'Go back',
        icon: AppIcons.alert,
        center: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    final body = {
      'started_at': _start.toUtc().toIso8601String(),
      'finished_at': _end.toUtc().toIso8601String(),
      'sets': sets,
    };
    try {
      if (_past) {
        final d = widget.past!;
        await Services.api.post('me/workouts/past/', {
          ...body,
          'date': DateFormat('yyyy-MM-dd').format(d.date),
          'program_day': d.dayId,
          'name': d.dayName,
        });
      } else {
        await Services.api.put('me/workouts/${widget.id}/edit/', body);
      }
      if (!mounted) return;
      showToast(context, _past ? 'Workout saved' : 'Changes saved', sub: _past ? null : 'Your coach can see what changed', kind: ToastKind.ok);
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (mounted) showToast(context, e.offline ? 'You are offline' : 'Could not save', sub: e.offline ? 'Connect and save again' : e.shown, kind: ToastKind.warn);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime(bool start, StateSetter sheet) async {
    final cur = start ? _start : _end;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(cur), helpText: start ? 'Start time' : 'End time');
    if (t == null || !mounted) return;
    void apply() {
      final base = start ? _start : _end;
      final next = DateTime(base.year, base.month, base.day, t.hour, t.minute);
      if (start) {
        // the length stays when the start moves, like Strong
        final len = _end.difference(_start);
        _start = next;
        _end = next.add(len);
      } else {
        _end = next.isBefore(_start) ? next.add(const Duration(days: 1)) : next;
      }
    }

    setState(apply);
    sheet(() {});
  }

  /// Start and end time (the workout's ⋯, or a tap on its time line).
  Future<void> _timeSheet() => showAppSheet<void>(
        context,
        title: 'Workout time',
        sub: DateFormat('EEEE, d MMM').format(_start),
        builder: (ctx) => StatefulBuilder(builder: (ctx, sheet) => _times(sheet)),
      );

  // ─────────────────────────────── UI

  String get _title => _past ? 'Log workout' : 'Edit workout';

  String get _name => _past ? (widget.past!.dayName.isEmpty ? 'Workout' : widget.past!.dayName) : '${_w?['name'] ?? 'Workout'}';

  String _len() {
    final m = _end.difference(_start).inMinutes;
    return m >= 60 ? '${m ~/ 60} h ${m % 60} min' : '$m min';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) {
        if (!did) _close();
      },
      child: Scaffold(
        backgroundColor: AppColors.white,
        body: SafeArea(
          bottom: false,
          // the bar is drawn over the list, so its shadow shows on the rows under it (Probid 19 Nov)
          child: Stack(children: [
            Positioned.fill(top: 56, child: _ready ? _body() : _loading()),
            Positioned(left: 0, right: 0, top: 0, child: _bar()),
          ]),
        ),
      ),
    );
  }

  Widget _bar() => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: AppColors.white, boxShadow: _scrolled ? AppShadows.topBar : null),
        child: Row(children: [
          CaBarIcon(icon: const AppIcon(AppIcons.close, size: 22, color: AppColors.text, stroke: 2), tooltip: 'Close', onTap: _close),
          const SizedBox(width: 8),
          Expanded(child: Text(_title, style: AppText.s(18, W.w6))),
          CaBarIcon(
            tooltip: _past ? 'Save workout' : 'Save changes',
            onTap: _ready && !_saving ? _save : null,
            icon: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))
                : AppIcon(AppIcons.check, size: 24, stroke: 2.4, color: _ready ? AppColors.accent : AppColors.muted),
          ),
        ]),
      );

  Widget _loading() => Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, spacing: 10, children: [
                  Text(_error!, textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)),
                  CaButton('Try again', kind: CaBtnKind.out, small: true, expand: false, onPressed: () {
                    setState(() => _error = null);
                    _load();
                  }),
                ]),
              )
            : const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent)),
      );

  Widget _body() {
    final edits = [for (final e in (_w?['edits'] as List? ?? const [])) (e as Map).cast<String, dynamic>()];
    return ListView(
      controller: _scroll,
      padding: EdgeInsets.only(top: 14, bottom: 40 + MediaQuery.paddingOf(context).bottom),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(spacing: 6, children: [
            Flexible(child: Text(_name, style: AppText.s(22, W.w7, ls: -0.3))),
            _dots(_timeSheet, 'Workout time'),
          ]),
        ),
        // the time line opens the start / end times too
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Hover(
              onTap: _timeSheet,
              builder: (_, h, _) => Text.rich(
                TextSpan(children: [
                  TextSpan(text: _len(), style: AppText.s(15, W.w5, color: AppColors.text2, tabular: true)),
                  TextSpan(
                    text: '   ${DateFormat('EEE, d MMM').format(_start)} · ${DateFormat('h:mm').format(_start)} – ${DateFormat('h:mm a').format(_end)}',
                    style: AppText.s(13.5, W.w5, color: h ? AppColors.accentText : AppColors.muted),
                  ),
                ]),
              ),
            ),
          ),
        ),
        if (edits.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              'Edited ${edits.length} ${edits.length == 1 ? 'time' : 'times'}',
              style: AppText.s(12.5, W.w5, color: AppColors.muted),
            ),
          ),
        for (final e in _ex) _exercise(e),
        if (_ex.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('No sets left in this workout. Save to keep only the time.', textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)),
          ),
      ],
    );
  }

  Widget _dots(VoidCallback onTap, String label) => Semantics(
        button: true,
        label: label,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            width: 36,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: h ? AppColors.accentSoft : null, borderRadius: BorderRadius.circular(8)),
            child: const AppIcon(AppIcons.dots, size: 20, color: AppColors.accent),
          ),
        ),
      );

  /// SET 40 · PREVIOUS flex 5 · value boxes flex 4 each · ✓ 40 (the logger's grid).
  Widget _grid(_Ex e, List<Widget> cells) {
    final n = e.cols.length;
    return Row(spacing: 6, children: [
      for (final (k, w) in cells.indexed)
        if (k == 0 || k == cells.length - 1)
          SizedBox(width: 40, child: w)
        else if (k == 1)
          Expanded(flex: n == 1 ? 6 : 5, child: w)
        else
          Expanded(flex: 4, child: w),
    ]);
  }

  Widget _th(String t) => Text(t, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.clip, style: AppText.s(11, W.w7, color: AppColors.text, ls: 1.2));

  /// Volume (kg × reps) of the PREVIOUS workout's working sets: the base of "Volume increase".
  double _prevVolume(_Ex e) {
    var v = 0.0;
    for (final p in e.prev) {
      if (p['type'] == 'warmup') continue;
      num? n(String k) => p[k] is num ? p[k] as num : num.tryParse('${p[k] ?? ''}');
      v += (n('weight_kg') ?? 0) * (n('reps') ?? 0);
    }
    return v;
  }

  int _reps(_Ex e) => e.sets.where((s) => s.done && s.kind != SetKind.warmup).fold(0, (a, s) => a + (int.tryParse(s.reps.text.trim()) ?? 0));

  /// The focus chip's text for [f], like the logger: "557 kg", "+12%", "21 reps", "26.52 kg".
  String _focusText(_Ex e, FocusMetric f) {
    final fmt = NumberFormat.decimalPattern('en_IN');
    final vol = _volume(e);
    switch (f) {
      case FocusMetric.volume:
        return '${fmt.format(vol.round())} kg';
      case FocusMetric.volumeUp:
        final last = _prevVolume(e);
        if (last == 0) return '+0%';
        final p = ((vol - last) / last * 100).round();
        return '${p >= 0 ? '+' : ''}$p%';
      case FocusMetric.reps:
        return '${_reps(e)} reps';
      case FocusMetric.weightReps:
        final r = _reps(e);
        return '${r == 0 ? '0' : (vol / r).toStringAsFixed(2)} kg';
    }
  }

  /// The focus chip: pick what to watch for this exercise (no ⋯ beside it here, Probid 19 Nov).
  void _focusMenu(BuildContext anchor, _Ex e) => loggerPopover(anchor, width: 260, right: true, builder: (ctx, close) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Text('FOCUS METRIC', style: AppText.s(11, W.w8, color: AppColors.muted, ls: 1)),
        ),
        for (final f in FocusMetric.values)
          Hover(
            onTap: () {
              close();
              setState(() => e.focus = f);
              Services.outbox.enqueue('PUT', 'me/exercise-prefs/${e.exId}/', {'focus_metric': f.api}, tag: 'exercise:pref').catchError((_) => null);
            },
            builder: (_, h, _) => Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: h ? AppColors.hover : null, borderRadius: BorderRadius.circular(8)),
              child: Row(spacing: 8, children: [
                SizedBox(width: 18, child: e.focus == f ? const AppIcon(AppIcons.check, size: 16, color: AppColors.accent, stroke: 2.4) : null),
                Expanded(child: Text(f.label, style: AppText.s(13.5, W.w6))),
                Text(_focusText(e, f), style: AppText.s(13, W.w7, color: AppColors.text2, tabular: true)),
              ]),
            ),
          ),
      ]));

  /// SET box: set type (W / D / F, each with ?), the rest after this set, delete (the logger's set menu).
  void _setMenu(BuildContext anchor, _Ex e, _Set s) {
    Widget kind(SetKind t, Color color) {
      final (name, info) = loggerKindInfo[t]!;
      final on = s.kind == t;
      return Builder(
        builder: (rowCtx) => Hover(
          onTap: () {
            Navigator.of(rowCtx).pop();
            setState(() => s.kind = on ? SetKind.normal : t);
          },
          builder: (_, h, _) => Container(
            height: 40,
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(color: on ? AppColors.accentSoft : (h ? AppColors.hover : null), borderRadius: BorderRadius.circular(8)),
            child: Row(spacing: 10, children: [
              SizedBox(width: 16, child: Text(t.letter, textAlign: TextAlign.center, style: AppText.s(14, W.w8, color: color))),
              Expanded(child: Text(on ? '$name (tap to undo)' : name, style: AppText.s(13.5, W.w6))),
              Semantics(
                button: true,
                label: 'What is a $name?',
                child: Hover(
                  onTap: () => loggerTip(rowCtx, name, info),
                  builder: (_, hh, _) => Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: hh ? AppColors.pressed : null, shape: BoxShape.circle),
                    child: const AppIcon(AppIcons.help, size: 16, color: AppColors.muted),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    }

    loggerPopover(anchor, width: 260, builder: (ctx, close) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: Text('SET TYPE', style: AppText.s(11, W.w8, color: AppColors.muted, ls: 1)),
          ),
          kind(SetKind.warmup, AppColors.amberText),
          kind(SetKind.drop, AppColors.purpleText),
          kind(SetKind.failure, AppColors.badText),
          const Divider(height: 10, color: AppColors.line),
          loggerMi('Rest after this set', icon: AppIcons.clockAlt, sub: s.rest == null ? 'No rest' : clockText(s.rest!), onTap: () {
            close();
            _restSheet(e, s);
          }),
          loggerMi('Delete set', icon: AppIcons.trash, danger: true, onTap: () {
            close();
            _deleteSet(e, s);
          }),
        ]));
  }

  void _deleteSet(_Ex e, _Set s) => setState(() {
        e.sets.remove(s);
        s.dispose();
        if (e.sets.isEmpty) _ex.remove(e);
      });

  /// How long the client rested after a set (the logger's rest sheet, without a timer: this workout is over).
  Future<void> _restSheet(_Ex e, _Set s) async {
    var v = s.rest ?? e.restOf(s.kind);
    final n = e.sets.indexOf(s) + 1;
    final r = await showAppSheet<int>(
      context,
      title: 'Rest after set $n',
      sub: '${e.name} · how long you rested',
      builder: (ctx) => StatefulBuilder(builder: (_, set) => RestStepper(value: v, onChanged: (x) => set(() => v = x))),
      footer: (ctx) => [
        if (s.rest != null)
          CaButton('No rest', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop(0)),
        CaButton('Save', icon: AppIcons.check, onPressed: () => Navigator.of(ctx).pop(v)),
      ],
    );
    if (r == null || !mounted) return;
    setState(() => s.rest = r <= 0 ? null : r);
  }

  /// The thin rest line under a set (the logger's): "1:30" between two lines. Tap = change it; swipe left = no rest.
  Widget _restLine(_Ex e, _Set s, int n) => Dismissible(
        key: ValueKey('rest:${s.key}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: AppColors.badBg,
          child: Text('No rest', style: AppText.s(11.5, W.w7, color: AppColors.badText)),
        ),
        confirmDismiss: (_) async {
          WorkoutFeel.restSkipped();
          setState(() => s.rest = null);
          return false;
        },
        child: Semantics(
          button: true,
          label: 'Rest after set $n: ${clockText(s.rest!)}',
          child: Hover(
            onTap: () => _restSheet(e, s),
            builder: (_, h, _) => Container(
              height: 26,
              color: s.done ? AppColors.logDoneRow : AppColors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(spacing: 8, children: [
                Expanded(child: Container(height: 1.5, color: h ? AppColors.accent : AppColors.accentRing)),
                Text(clockText(s.rest!), style: AppText.s(13, W.w7, color: AppColors.accentText, tabular: true)),
                Expanded(child: Container(height: 1.5, color: h ? AppColors.accent : AppColors.accentRing)),
              ]),
            ),
          ),
        ),
      );

  Widget _exercise(_Ex e) {
    final weight = !e.cardio && !e.timed;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(spacing: 8, children: [
            Expanded(child: Text(e.name, style: AppText.s(16, W.w6, color: AppColors.accentText))),
            // the focus metric chip, as in the logger; no ⋯ beside it (Probid 19 Nov)
            if (weight)
              Builder(
                builder: (bc) => Semantics(
                  button: true,
                  label: 'Focus metric ${e.focus.label}',
                  child: Hover(
                    onTap: () => _focusMenu(bc, e),
                    builder: (_, h, _) => Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: h ? AppColors.accentRing : AppColors.accentSoft, borderRadius: BorderRadius.circular(8)),
                      child: Text(_focusText(e, e.focus), style: AppText.s(14, W.w6, color: AppColors.accentText, tabular: true)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _grid(e, [
            _th('SET'),
            _th('PREVIOUS'),
            for (final c in e.cols) _th(c),
            const Center(child: AppIcon(AppIcons.check, size: 16, color: AppColors.text2, stroke: 2.4)),
          ]),
        ),
        const SizedBox(height: 4),
        for (var k = 0; k < e.sets.length; k++)
          KeyedSubtree(
            key: ValueKey(e.sets[k].key),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _setRow(e, k),
              if (e.sets[k].rest != null) _restLine(e, e.sets[k], k + 1),
            ]),
          ),
        const SizedBox(height: 4),
        Center(
          child: Semantics(
            button: true,
            label: 'Add set to ${e.name}',
            child: Hover(
              onTap: () => setState(() {
                final last = e.sets.isEmpty ? null : e.sets.last;
                final rest = last?.rest ?? (e.restWork > 0 ? e.restWork : null);
                e.sets.add(_Set(key: _key(), bw: last?.bw ?? e.body, rest: rest, keep: {if (last?.keep['rest_seconds'] != null) 'rest_seconds': last!.keep['rest_seconds']}));
              }),
              builder: (_, h, _) => Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: h ? AppColors.accentSoft : null, borderRadius: BorderRadius.circular(10)),
                child: Text('ADD SET', style: AppText.s(14, W.w6, color: AppColors.accentText, ls: 1)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _setRow(_Ex e, int k) {
    final s = e.sets[k];
    final n = e.sets.take(k + 1).where((x) => x.kind == SetKind.normal).length;
    final label = s.kind == SetKind.normal ? '$n' : s.kind.letter;
    final color = switch (s.kind) {
      SetKind.warmup => AppColors.amberText,
      SetKind.drop => AppColors.purpleText,
      SetKind.failure => AppColors.badText,
      SetKind.normal => AppColors.text,
    };
    final p = _prevOf(e, k);
    final pt = _prevText(e, p);
    final pv = _prevValues(e, p);
    final fail = p?['type'] == 'failure';
    final boxes = _boxes(e, s);
    Widget box(int j) {
      final c = boxes[j];
      final decimal = !(e.cols[j] == 'REPS' || e.cols[j] == 'BPM' || e.cols[j] == 'SEC');
      return Container(
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: s.done ? Colors.transparent : AppColors.logField, borderRadius: BorderRadius.circular(6)),
        child: TextField(
          controller: c,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal, signed: e.body && j == 0),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.,-]' : r'[0-9]')), LengthLimitingTextInputFormatter(6)],
          onChanged: (_) => setState(() {}),
          style: AppText.s(16, W.w6, tabular: true),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: j < pv.length && pv[j].isNotEmpty ? pv[j] : null,
            hintStyle: AppText.s(16, W.w6, color: AppColors.valPh, tabular: true),
            contentPadding: const EdgeInsets.symmetric(vertical: 5),
          ),
        ),
      );
    }

    final row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: s.done ? AppColors.logDoneRow : AppColors.white,
      child: _grid(e, [
        // tap the set number for its menu: set type, rest, delete (the logger's, Probid 19 Nov: no toggle)
        Builder(
          builder: (bc) => Semantics(
          button: true,
          label: 'Set $label options',
          child: Hover(
            onTap: () => _setMenu(bc, e, s),
            builder: (_, h, _) => Container(
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: h ? AppColors.logFieldHover : null, borderRadius: BorderRadius.circular(6)),
              child: Text(label, style: AppText.s(15, W.w6, color: color)),
            ),
          ),
        ),
        ),
        // PREVIOUS: tap to put those values in the boxes
        Semantics(
          button: true,
          label: pt.isEmpty ? 'No previous set' : 'Previous $pt',
          child: Hover(
            onTap: () {
              // nothing to fill (no previous set, or the set is ticked): it shakes and the phone buzzes
              if (pv.every((v) => v.isEmpty) || s.done) {
                _refuse('prev:${s.key}');
                return;
              }
              setState(() {
                for (var j = 0; j < boxes.length && j < pv.length; j++) {
                  boxes[j].text = pv[j];
                }
              });
            },
            builder: (_, _, _) => _shaking(Container(
              height: 30,
              alignment: Alignment.center,
              child: pt.isEmpty
                  ? Container(width: 16, height: 2.5, decoration: BoxDecoration(color: AppColors.tickOff, borderRadius: BorderRadius.circular(2)))
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text.rich(
                        TextSpan(text: pt, children: [
                          if (fail) TextSpan(text: ' [F]', style: AppText.s(14, W.w5, color: AppColors.badText)),
                        ]),
                        maxLines: 1,
                        style: AppText.s(14, W.w4, color: s.done ? AppColors.valPh : AppColors.text),
                      ),
                    ),
            ), 'prev:${s.key}'),
          ),
        ),
        for (var j = 0; j < boxes.length; j++) box(j),
        Semantics(
          button: true,
          label: s.done ? 'Untick set $label' : 'Tick set $label',
          child: Hover(
            onTap: () => _tick(e, k),
            builder: (_, h, _) => _shaking(Container(
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: s.done ? AppColors.logDoneTick : (h ? AppColors.logFieldHover : AppColors.logField),
                borderRadius: BorderRadius.circular(6),
              ),
              child: AppIcon(AppIcons.check, size: 18, stroke: 2.4, color: s.done ? AppColors.white : (h ? AppColors.logDoneTick : AppColors.valPh)),
            ), 'tick:${s.key}'),
          ),
        ),
      ]),
    );
    // swipe left to delete the set (the logger's way)
    return Dismissible(
      key: ValueKey('d-${s.key}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.red,
        child: const AppIcon(AppIcons.trash, size: 20, color: AppColors.white),
      ),
      onDismissed: (_) => _deleteSet(e, s),
      child: row,
    );
  }

  Widget _times(StateSetter sheet) {
    final segs = _segments;
    Widget line(String label, String value, VoidCallback onTap) => Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(children: [
              Expanded(child: Text(label, style: AppText.s(14, W.w6))),
              Text(value, style: AppText.s(14, W.w7, color: h ? AppColors.accentText : AppColors.accent)),
            ]),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      Container(
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          line('Start', DateFormat('h:mm a').format(_start), () => _pickTime(true, sheet)),
          const Divider(height: 1, color: AppColors.line),
          line('End', DateFormat('h:mm a').format(_end), () => _pickTime(false, sheet)),
          const Divider(height: 1, color: AppColors.line),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(children: [
              Expanded(child: Text('Duration', style: AppText.s(14, W.w6))),
              Text(_len(), style: AppText.s(14, W.w7)),
            ]),
          ),
        ]),
      ),
      // sets added after finishing ("Log more sets") were timed on their own (H55)
      if (segs.length > 1 && !_timesChanged)
        Text(
          'Workout ${(((segs.first['seconds'] as num?) ?? 0) / 60).round()} min + added sets ${[for (final s in segs.skip(1)) '${(((s['seconds'] as num?) ?? 0) / 60).round()} min'].join(' + ')}',
          style: AppText.s(12.5, W.w5, color: AppColors.muted),
        ),
      if (segs.length > 1 && _timesChanged)
        Text('The new start and end become the whole workout time.', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
      Text('Moving the start keeps the length; change the end to make it longer or shorter.', style: AppText.s(12.5, W.w4, color: AppColors.muted)),
    ]);
  }
}
