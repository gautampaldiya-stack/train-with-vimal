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
import 'train_model.dart';
import 'workout_model.dart' show SetKind;

/// Edit workout (tracker H51-H55, Strong's "Edit workout"): a finished workout's start / end time and every set
/// (weight, reps, set type, rest; add or remove sets). Saving makes a new version; the coach sees what changed.
/// Returns true when it was saved.
Future<bool> showEditWorkout(BuildContext context, String workoutId) async {
  final r = await showAppSheet<bool>(
    context,
    title: 'Edit workout',
    tall: true,
    fixedBody: true,
    builder: (ctx) => _EditBody(id: workoutId),
  );
  return r == true;
}

/// Yesterday's workout, missed on the day, logged afterwards (H51a): the plan's exercises with empty sets, the
/// client fills them and the start / end time.
Future<bool> showLogPastWorkout(BuildContext context, TrainData d) async {
  final r = await showAppSheet<bool>(
    context,
    title: 'Log ${d.dayName.isEmpty ? 'workout' : d.dayName}',
    sub: DateFormat('EEEE, d MMM').format(d.date),
    tall: true,
    fixedBody: true,
    builder: (ctx) => _EditBody(past: d),
  );
  return r == true;
}

class _Set {
  _Set({this.id, required this.key, this.kind = SetKind.normal, this.bw = false, this.keep = const {}, String kg = '', String reps = '', String secs = '', String bpm = '', String rest = ''})
      : kg = TextEditingController(text: kg),
        reps = TextEditingController(text: reps),
        secs = TextEditingController(text: secs),
        bpm = TextEditingController(text: bpm),
        rest = TextEditingController(text: rest);
  final int? id;
  final String key;
  SetKind kind;
  bool bw;

  /// Fields this page does not show (RPE, the rest timer and the rest taken): sent back as they were.
  final Map<String, dynamic> keep;
  final TextEditingController kg, reps, secs, bpm, rest;

  bool get empty => [kg, reps, secs, bpm].every((c) => c.text.trim().isEmpty);

  void dispose() {
    for (final c in [kg, reps, secs, bpm, rest]) {
      c.dispose();
    }
  }
}

class _Ex {
  _Ex({required this.exId, required this.name, required this.logType, this.peId, List<_Set>? sets}) : sets = sets ?? [];
  final String exId, name, logType;
  final int? peId;
  final List<_Set> sets;
  bool get cardio => logType == 'distance';
  bool get timed => logType == 'time';
  bool get body => logType == 'bodyweight_reps';
}

String _num(dynamic v) {
  if (v == null) return '';
  final n = v is num ? v.toDouble() : double.tryParse('$v');
  if (n == null) return '';
  return kg(n);
}

class _EditBody extends StatefulWidget {
  const _EditBody({this.id, this.past});
  final String? id;
  final TrainData? past;
  @override
  State<_EditBody> createState() => _EditBodyState();
}

class _EditBodyState extends State<_EditBody> {
  final _ex = <_Ex>[];
  Map<String, dynamic>? _w;
  String? _error;
  bool _saving = false;
  late DateTime _start, _end;
  DateTime? _start0, _end0;
  int _keyN = 0;

  bool get _past => widget.past != null;

  @override
  void initState() {
    super.initState();
    if (_past) {
      _fromPlan(widget.past!);
    } else {
      _load();
    }
  }

  @override
  void dispose() {
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
        sets: [for (var i = 0; i < (e.sets > 0 ? e.sets : 1); i++) _Set(key: _key(), bw: e.bodyweight)],
      ));
    }
  }

  Future<void> _load() async {
    try {
      final j = await Services.api.get<Map<String, dynamic>>('me/workouts/${widget.id}/');
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
          final x = _Ex(exId: k, name: '${s['exercise_name'] ?? ''}', logType: '${s['log_type'] ?? 'weight_reps'}', peId: (s['program_exercise'] as num?)?.toInt());
          _ex.add(x);
          return x;
        });
        final secsV = (s['seconds'] as num?)?.toInt();
        e.sets.add(_Set(
          id: (s['id'] as num?)?.toInt(),
          key: '${s['client_key'] ?? ''}'.isEmpty ? _key() : '${s['client_key']}',
          kind: SetKind.of('${s['set_type'] ?? 'normal'}'),
          bw: s['is_bodyweight'] == true,
          keep: {for (final f in ['rpe', 'rest_planned', 'rest_actual', 'done_at']) f: s[f]},
          kg: _num(s['weight_kg']),
          reps: s['reps'] == null ? '' : '${s['reps']}',
          secs: secsV == null ? '' : (e.cardio ? kg(secsV / 60) : '$secsV'),
          bpm: s['bpm'] == null ? '' : '${s['bpm']}',
          rest: s['rest_seconds'] == null ? '' : '${s['rest_seconds']}',
        ));
      }
      _w = j;
      _error = null;
    } on ApiError catch (e) {
      _error = e.offline ? 'You are offline. Connect to edit this workout.' : 'Could not open this workout. Try again.';
    }
    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> get _segments => [for (final s in (_w?['segments'] as List? ?? const [])) (s as Map).cast<String, dynamic>()];

  bool get _timesChanged => _start0 == null || _start.difference(_start0!).inSeconds.abs() >= 60 || _end.difference(_end0!).inSeconds.abs() >= 60;

  Future<void> _pickTime(bool start) async {
    final cur = start ? _start : _end;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(cur), helpText: start ? 'Start time' : 'End time');
    if (t == null || !mounted) return;
    setState(() {
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
    });
  }

  Map<String, dynamic> _row(_Ex e, _Set s, int n) {
    double? d(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));
    int? i(TextEditingController c) => int.tryParse(c.text.trim());
    final minutes = d(s.secs);
    return {
      for (final k in s.keep.entries)
        if (k.key != 'done_at') k.key: k.value,
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
      'rest_seconds': i(s.rest)?.clamp(0, 900),
    };
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_end.isAfter(_start)) {
      showToast(context, 'The end must be after the start', kind: ToastKind.warn);
      return;
    }
    final sets = <Map<String, dynamic>>[];
    for (final e in _ex) {
      var n = 0;
      for (final s in e.sets) {
        if (s.empty) continue; // a set left empty is not saved
        sets.add(_row(e, s, ++n));
      }
    }
    if (_past && sets.isEmpty) {
      showToast(context, 'Fill at least one set', sub: 'Type the weight and reps you did', kind: ToastKind.warn);
      return;
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

  // ─────────────────────────────── UI

  @override
  Widget build(BuildContext context) {
    if (!_past && _w == null) {
      return Center(
        child: _error != null
            ? Column(mainAxisSize: MainAxisSize.min, spacing: 10, children: [
                Text(_error!, textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)),
                CaButton('Try again', kind: CaBtnKind.out, small: true, expand: false, onPressed: () {
                  setState(() => _error = null);
                  _load();
                }),
              ])
            : const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent)),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
          if (!_past) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${_w!['name'] ?? 'Workout'}', style: AppText.s(15, W.w7))),
          _times(),
          ?_versions(),
          for (final e in _ex) _exercise(e),
          if (_ex.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('No sets left in this workout. Save to keep only the time.', textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: CaButton(_past ? 'Save workout' : 'Save changes', loading: _saving, onPressed: _save),
      ),
    ]);
  }

  Widget _times() {
    final mins = _end.difference(_start).inMinutes;
    final segs = _segments;
    Widget line(String label, String value, VoidCallback onTap) => Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(children: [
              Expanded(child: Text(label, style: AppText.s(13.5, W.w6))),
              Text(value, style: AppText.s(13.5, W.w7, color: h ? AppColors.accentText : AppColors.accent)),
            ]),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 12),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        line('Start', '${DateFormat('EEE, d MMM').format(_start)} · ${DateFormat('h:mm a').format(_start)}', () => _pickTime(true)),
        const Divider(height: 1, color: AppColors.line),
        line('End', DateFormat('h:mm a').format(_end), () => _pickTime(false)),
        const Divider(height: 1, color: AppColors.line),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
            Row(children: [
              Expanded(child: Text('Duration', style: AppText.s(13.5, W.w6))),
              Text(mins >= 60 ? '${mins ~/ 60} h ${mins % 60} min' : '$mins min', style: AppText.s(13.5, W.w7)),
            ]),
            // sets added after finishing ("Log more sets") were timed on their own (H55)
            if (segs.length > 1 && !_timesChanged)
              Text(
                'Workout ${(((segs.first['seconds'] as num?) ?? 0) / 60).round()} min + added sets ${[for (final s in segs.skip(1)) '${(((s['seconds'] as num?) ?? 0) / 60).round()} min'].join(' + ')}',
                style: AppText.s(12, W.w5, color: AppColors.muted),
              ),
            if (segs.length > 1 && _timesChanged)
              Text('The new start and end become the whole workout time.', style: AppText.s(12, W.w5, color: AppColors.muted)),
          ]),
        ),
      ]),
    );
  }

  Widget? _versions() {
    final edits = [for (final e in (_w?['edits'] as List? ?? const [])) (e as Map).cast<String, dynamic>()];
    if (edits.isEmpty) return null;
    final last = DateTime.tryParse('${edits.last['edited_at']}')?.toLocal();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        'Edited ${edits.length} ${edits.length == 1 ? 'time' : 'times'}${last == null ? '' : ' · last ${DateFormat('d MMM, h:mm a').format(last)}'}',
        style: AppText.s(12, W.w5, color: AppColors.muted),
      ),
    );
  }

  Widget _exercise(_Ex e) {
    final cols = e.cardio ? ['MIN', 'BPM'] : (e.timed ? ['SEC'] : [e.body ? '+KG' : 'KG', 'REPS']);
    Widget head(String t, {double? w, bool flex = false}) {
      final c = Text(t, textAlign: TextAlign.center, style: AppText.s(11, W.w8, color: AppColors.muted, ls: .5));
      return flex ? Expanded(child: c) : SizedBox(width: w, child: c);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        Text(e.name, style: AppText.s(14.5, W.w7, color: AppColors.accentText)),
        Row(spacing: 8, children: [
          head('SET', w: 36),
          for (final c in cols) head(c, flex: true),
          head('REST', w: 56),
          const SizedBox(width: 36),
        ]),
        for (final (i, s) in e.sets.indexed) _setRow(e, s, i),
        Align(
          alignment: Alignment.centerLeft,
          child: CaBarText('Add set', icon: AppIcons.plus, onTap: () => setState(() {
                final last = e.sets.isEmpty ? null : e.sets.last;
                e.sets.add(_Set(key: _key(), bw: last?.bw ?? e.body, rest: last?.rest.text ?? ''));
              })),
        ),
      ]),
    );
  }

  Widget _setRow(_Ex e, _Set s, int i) {
    final n = e.sets.take(i + 1).where((x) => x.kind == SetKind.normal).length;
    final color = switch (s.kind) {
      SetKind.warmup => AppColors.amberText,
      SetKind.drop => AppColors.purpleText,
      SetKind.failure => AppColors.badText,
      SetKind.normal => AppColors.text,
    };
    Widget box(TextEditingController c, {bool decimal = false}) => Expanded(
          child: Container(
            height: 32,
            decoration: BoxDecoration(color: AppColors.logField, borderRadius: BorderRadius.circular(7)),
            alignment: Alignment.center,
            child: TextField(
              controller: c,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.numberWithOptions(decimal: decimal),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.,-]' : r'[0-9]')), LengthLimitingTextInputFormatter(6)],
              style: AppText.s(14, W.w7, tabular: true),
              decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 7)),
            ),
          ),
        );
    return Row(spacing: 8, children: [
      // tap the set number to change its type: work → warm up → drop → failure (the logger's W / D / F)
      Semantics(
        button: true,
        label: 'Set type',
        child: Hover(
          onTap: () => setState(() => s.kind = SetKind.values[(s.kind.index + 1) % SetKind.values.length]),
          builder: (_, h, _) => Container(
            width: 36,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: h ? AppColors.logFieldHover : AppColors.logField, borderRadius: BorderRadius.circular(7)),
            child: Text(s.kind == SetKind.normal ? '$n' : s.kind.letter, style: AppText.s(14, W.w8, color: color)),
          ),
        ),
      ),
      if (e.cardio) ...[box(s.secs, decimal: true), box(s.bpm)] else if (e.timed) box(s.secs) else ...[box(s.kg, decimal: true), box(s.reps)],
      SizedBox(width: 56, child: Row(children: [box(s.rest)])),
      Semantics(
        button: true,
        label: 'Remove set',
        child: Hover(
          onTap: () => setState(() {
            e.sets.remove(s);
            s.dispose();
            if (e.sets.isEmpty) _ex.remove(e);
          }),
          builder: (_, h, _) => Container(
            width: 36,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: h ? AppColors.logField : null, shape: BoxShape.circle),
            child: const AppIcon(AppIcons.close, size: 16, color: AppColors.muted),
          ),
        ),
      ),
    ]);
  }
}
