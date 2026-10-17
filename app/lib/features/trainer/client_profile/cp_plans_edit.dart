import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import '../../../core/widgets/tooltip.dart';
import 'cp_common.dart';
import 'cp_plans_model.dart';
import 'cp_plans_parts.dart';

/// Workout plan editor for one client (`pe.workout`): `Edit X for Y` (saves Y's own copy through
/// `custom-structure`) or `New plan for Y: copy of X` (`new-from` + name, start, `Also save to the library`).
/// Left: the 7 days of the current week (blue dot = changed). Right: day name, Workout / Rest, the day's exercises
/// with their numbers and note (drag to reorder; Swap · Edit (a drawer, Previous / Next) · Remove),
/// `Add exercise` · `Add superset`, the coach note for the day.
/// A changed day is copied to the same weekday of every later week of the plan.
class WorkoutEditor extends StatefulWidget {
  const WorkoutEditor({super.key, required this.d, required this.dup, required this.onClose, this.startDay});
  final PlansData d;
  final bool dup;
  final int? startDay;
  final VoidCallback onClose;
  @override
  State<WorkoutEditor> createState() => _WorkoutEditorState();
}

class _WorkoutEditorState extends State<WorkoutEditor> {
  PlansData get d => widget.d;
  Map get a => d.workout!;
  late final Map tree = jsonDecode(jsonEncode(d.wTree ?? const {})) as Map;
  late final int week = planWeek(a);
  late int sel = widget.startDay ?? DateTime.now().weekday - 1;
  final touched = <int>{};
  late final name = TextEditingController(text: '${a['program_name']} · ${d.c.first} v2');
  late String when = d.workoutNext == null ? 'after_current' : 'now';
  bool lib = false, busy = false;
  int _gen = 0; // bumps field keys after swap / reorder

  /// Bumped on every change so the exercise edit drawer (its own route) redraws too.
  final _rev = ValueNotifier(0);

  String get first => d.c.first;

  @override
  void dispose() {
    name.dispose();
    _rev.dispose();
    super.dispose();
  }

  Map get _week {
    final w = weekOf(tree, week);
    if (w != null) return w;
    final nw = {'number': week, 'days': []};
    (tree['program_weeks'] ??= []).add(nw);
    return nw;
  }

  Map _day(int wd) {
    final w = _week;
    final dd = dayOf(w, wd);
    if (dd != null) return dd;
    final nd = {'weekday': wd, 'name': '', 'is_rest': true, 'rest_note': '', 'exercises': []};
    (w['days'] as List).add(nd);
    return nd;
  }

  List get _ex => (_day(sel)['exercises'] ??= []) as List;

  void _change(VoidCallback f) {
    setState(() {
      f();
      touched.add(sel);
    });
    _rev.value++;
  }

  // ─────────────────────────────── save

  Map<String, dynamic> _payload({required bool keepIds}) {
    final weeks = [for (final w in weeksOf(tree)) jsonDecode(jsonEncode(w)) as Map];
    final src = weekOf(tree, week);
    for (final w in weeks) {
      if ((w['number'] as num) <= week) continue;
      for (final wd in touched) {
        final from = dayOf(src, wd);
        if (from == null) continue;
        final days = (w['days'] as List);
        final old = days.cast<Map>().where((x) => x['weekday'] == wd).firstOrNull;
        final copy = jsonDecode(jsonEncode(from)) as Map;
        copy['id'] = old?['id'];
        final oldEx = exercisesOf(old);
        final ex = (copy['exercises'] as List? ?? []).cast<Map>();
        for (var i = 0; i < ex.length; i++) {
          ex[i]['id'] = i < oldEx.length ? oldEx[i]['id'] : null;
        }
        if (old != null) days.remove(old);
        days.add(copy);
      }
    }
    Map clean(Map m) => {for (final e in m.entries) if (keepIds || e.key != 'id') e.key: e.value};
    return {
      'weeks': [
        for (final w in weeks)
          {
            ...clean({'id': w['id'], 'number': w['number']}),
            'days': [
              for (final dd in (w['days'] as List).cast<Map>())
                {
                  ...clean({'id': dd['id']}),
                  'weekday': dd['weekday'],
                  'name': '${dd['name'] ?? ''}',
                  'is_rest': dd['is_rest'] == true || exercisesOf(dd).isEmpty,
                  'rest_note': '${dd['rest_note'] ?? ''}',
                  'exercises': [
                    for (final e in exercisesOf(dd))
                      {
                        ...clean({'id': e['id']}),
                        'exercise': e['exercise'],
                        'superset_group': '${e['superset_group'] ?? ''}',
                        'sets': e['sets'],
                        'reps': '${e['reps']}',
                        'rpe': e['rpe'],
                        'rest_seconds': e['rest_seconds'] ?? 0,
                        'tempo': '${e['tempo'] ?? ''}',
                        'target_weight_kg': e['target_weight_kg'],
                        'note': '${e['note'] ?? ''}',
                        'override': e['override'] ?? {},
                      },
                  ],
                },
            ],
          },
      ],
    };
  }

  String? _check() {
    for (final e in [for (final dd in (_week['days'] as List? ?? const [])) ...exercisesOf(dd as Map)]) {
      if ('${e['reps']}'.trim().isEmpty) return 'Enter reps for ${exName(e)}, e.g. 8–10.';
      final s = (e['sets'] as num?) ?? 0;
      if (s < 1 || s > 12) return 'Sets for ${exName(e)} must be 1 to 12.';
      if (((e['rest_seconds'] as num?) ?? 0) > 300) return 'Rest for ${exName(e)} can be up to 5 min.';
      final r = e['rpe'] as num?;
      if (r != null && (r < 1 || r > 10)) return 'RPE for ${exName(e)} must be 1 to 10.';
    }
    return null;
  }

  Future<void> _save() async {
    final err = _check();
    if (err != null) return showToast(context, 'Check the plan', sub: err, kind: ToastKind.info);
    if (widget.dup && name.text.trim().length < 2) return showToast(context, 'Enter a plan name', kind: ToastKind.info);
    setState(() => busy = true);
    final base = 'clients/${d.c.id}/programs/';
    try {
      if (widget.dup) {
        final n = await Services.api.post<Map>('$base${a['id']}/new-from/', {'name': name.text.trim(), 'save_to_library': lib, 'when': when});
        if (touched.isNotEmpty) await Services.api.put('$base${n['id']}/custom-structure/', _payload(keepIds: false));
        if (!mounted) return;
        showToast(context, 'New plan assigned', sub: '${name.text.trim()} · ${when == 'now' ? 'from today' : 'after the current plan'}', kind: ToastKind.ok);
      } else {
        if (touched.isEmpty) return widget.onClose();
        await Services.api.put('$base${a['id']}/custom-structure/', _payload(keepIds: a['custom'] == true));
        if (!mounted) return;
        showToast(context, 'Saved for $first', sub: '${touched.length} day${touched.length == 1 ? '' : 's'} changed · the master stays the same', kind: ToastKind.ok);
      }
      widget.onClose();
      d.reload();
    } on ApiError catch (e) {
      if (mounted) {
        setState(() => busy = false);
        showToast(context, 'Could not save the plan', sub: e.message, kind: ToastKind.info);
      }
    }
  }

  Future<void> _cancel() async {
    if (touched.isNotEmpty) {
      final ok = await confirmAction(context, title: 'Leave without saving?', body: 'Your changes for $first are lost.', confirm: 'Leave', danger: true);
      if (!ok) return;
    }
    widget.onClose();
  }

  Future<void> _reset() async {
    final ok = await confirmAction(context,
        title: 'Reset to master?',
        body: 'Every change made for $first goes away. $first gets the master program "${a['master_name']}" again. Logged workouts stay.',
        confirm: 'Reset to master',
        danger: true,
        icon: AppIcons.reset);
    if (!ok || !mounted) return;
    try {
      await Services.api.post('clients/${d.c.id}/programs/${a['id']}/reset-to-master/', const {});
      if (!mounted) return;
      showToast(context, '$first follows the master again', sub: '${a['master_name']}', kind: ToastKind.ok);
      widget.onClose();
      d.reload();
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not reset the plan', sub: e.message, kind: ToastKind.info);
    }
  }

  // ─────────────────────────────── edits

  Future<void> _pick({int? swap, bool superset = false}) async {
    final day = _day(sel);
    final have = {for (final e in exercisesOf(day)) '${e['exercise']}'};
    final picked = await showExercisePicker(context,
        title: swap != null ? 'Swap ${exName(_ex[swap] as Map)}' : (superset ? 'Add a superset' : 'Add exercises'),
        sub: '${weekdayFull[sel]} · ${'${day['name'] ?? ''}'.isEmpty ? 'Workout' : day['name']} · only for $first',
        single: swap != null,
        need: superset ? 2 : 1,
        have: have);
    if (picked == null || picked.isEmpty) return;
    final prev = jsonEncode(_ex);
    _change(() {
      Map make(Map x, {Map? like}) => {
            'exercise': x['id'],
            'exercise_detail': x,
            'superset_group': like?['superset_group'] ?? '',
            'sets': like?['sets'] ?? x['default_sets'] ?? 3,
            'reps': like?['reps'] ?? x['default_reps'] ?? '10',
            'rpe': like?['rpe'] ?? x['default_rpe'],
            'rest_seconds': like?['rest_seconds'] ?? x['default_rest_seconds'] ?? 90,
            'tempo': like?['tempo'] ?? x['default_tempo'] ?? '',
            'target_weight_kg': like?['target_weight_kg'],
            'note': '',
            'override': {},
          };
      if (swap != null) {
        final old = _ex[swap] as Map;
        _ex[swap] = {...make(picked.first, like: old), 'id': old['id']};
      } else {
        String g = '';
        if (superset) {
          final used = {for (final e in _ex) '${(e as Map)['superset_group'] ?? ''}'};
          g = ['A', 'B', 'C', 'D', 'E'].firstWhere((x) => !used.contains(x), orElse: () => 'F');
        }
        for (final x in picked) {
          _ex.add({...make(x), 'superset_group': g, if (superset) 'rest_seconds': 60});
        }
        final day = _day(sel);
        day['is_rest'] = false;
      }
      _gen++;
    });
    if (!mounted) return;
    final what = swap != null ? 'Swapped for $first' : (superset ? 'Superset added' : '${picked.length} exercise${picked.length == 1 ? '' : 's'} added');
    showToast(context, what, sub: '${weekdayFull[sel]} · only for $first', kind: ToastKind.ok, action: 'Undo', onAction: () {
      if (!mounted) return;
      setState(() {
        _day(sel)['exercises'] = jsonDecode(prev);
        _gen++;
      });
    });
  }

  void _remove(int i) {
    final e = _ex[i] as Map;
    _change(() {
      _ex.removeAt(i);
      _gen++;
    });
    showToast(context, 'Removed for $first', sub: exName(e), kind: ToastKind.ok, action: 'Undo', onAction: () {
      if (!mounted) return;
      setState(() {
        _ex.insert(i.clamp(0, _ex.length), e);
        _gen++;
      });
    });
  }

  // ─────────────────────────────── build

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final diffN = WorkoutDiff(tree, d.wMaster).daysChanged(week);
    final head = Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
        Text(widget.dup ? 'New plan for $first: copy of ${a['program_name']}' : 'Edit ${a['program_name']} for $first', style: AppText.s(17, W.w7, ls: -.2)),
        _Info(widget.dup
            ? 'A new plan only for $first. ${pronounSub(d.c).capFirst} keeps the current plan until the copy starts. The master stays the same.'
            : 'Only $first’s copy changes. The master plan and other clients stay the same. Changed items get a blue dot.'),
      ]),
      Text(
        widget.dup
            ? 'Change what you need below, then pick when it starts.'
            : 'Week $week of ${a['weeks']} · changes start straight away and carry to the later weeks · ${diffN + touched.length == 0 ? 'same as the master' : '${touched.isEmpty ? diffN : touched.length} day${(touched.isEmpty ? diffN : touched.length) == 1 ? '' : 's'} changed${touched.isEmpty ? ' from the master' : ''}'}',
        style: AppText.cap,
      ),
    ]);
    final acts = <Widget>[
      if (!widget.dup && a['custom'] == true)
        AppButton('Reset to master', kind: BtnKind.text, icon: AppIcons.reset, onPressed: busy ? null : _reset),
      if (!phone || widget.dup || a['custom'] != true) AppButton('Cancel', onPressed: busy ? null : _cancel),
      AppButton.primary(widget.dup ? 'Assign copy' : 'Save for $first', icon: AppIcons.check, loading: busy, onPressed: busy ? null : _save),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      Wrap(alignment: WrapAlignment.spaceBetween, runSpacing: 10, spacing: 8, children: [
        AppButton('Back to plan', icon: AppIcons.chevronLeft, onPressed: _cancel),
        Wrap(spacing: 8, runSpacing: 8, children: acts),
      ]),
      head,
      if (widget.dup) _dupBar(context),
      phone
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [_days(true), _dayCard(context)])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [SizedBox(width: 230, child: _days(false)), Expanded(child: _dayCard(context))]),
    ]);
  }

  Widget _dupBar(BuildContext context) {
    final end = planEnd(a);
    final opts = [
      if (end != null) ('after_current', 'After current plan ends · ${DateFormat('EEE, d MMM').format(end.add(const Duration(days: 1)))}'),
      ('now', 'From today · replaces current'),
    ];
    Widget f(String l, Widget c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [Text(l, style: AppText.label), c]);
    final fields = [
      f('Plan name', AppTextField(controller: name, placeholder: 'Plan name')),
      f('Starts', AppSelect(opts.firstWhere((o) => o.$1 == when, orElse: () => opts.last).$2, entries: [for (final (k, l) in opts) MenuEntry(l, selected: k == when, onTap: () => setState(() => when = k))])),
      f('Length', Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(AppRadius.input), border: Border.all(color: AppColors.line2)),
        child: Text('${a['weeks']} weeks', style: AppText.s(14, W.w6, color: AppColors.muted)),
      )),
    ];
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        context.isPhone
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: fields)
            : Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [for (final x in fields) Expanded(child: x)]),
        Hover(
          onTap: () => setState(() => lib = !lib),
          builder: (_, _, _) => Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: AppToggle(value: lib, onChanged: (v) => setState(() => lib = v))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text('Also save to the library as a new master plan', style: AppText.s(13.5, W.w7)),
                Text('Other clients can then get it too.', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  /// `.cp-days`: one row per weekday (day chip, name, "6 exercises" / "Rest day", blue dot when changed).
  Widget _days(bool phone) {
    final diff = WorkoutDiff(tree, d.wMaster);
    Widget row(int i) {
      final dd = dayOf(weekOf(tree, week), i);
      final rest = isRest(dd);
      final on = i == sel;
      final changed = touched.contains(i) || diff.day(week, i);
      return Hover(
        onTap: () => setState(() => sel = i),
        builder: (_, h, _) => Container(
          width: phone ? 150 : null,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: on ? AppColors.accentSoft : (h ? AppColors.hover : null), borderRadius: BorderRadius.circular(AppRadius.item)),
          child: Row(spacing: 10, children: [
            Container(
              width: 38,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: on ? AppColors.accent : AppColors.accentSoft, borderRadius: BorderRadius.circular(8)),
              child: Text(weekdayShort[i], style: AppText.s(12, W.w8, color: on ? AppColors.white : AppColors.accentText)),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text(rest ? 'Rest' : '${dd?['name'] ?? ''}'.ifEmpty('Workout'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle),
                Text(rest ? 'Rest day' : '${exercisesOf(dd).length} exercises', style: AppText.rowSub),
              ]),
            ),
            if (changed) Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
          ]),
        ),
      );
    }

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: phone
            ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [for (var i = 0; i < 7; i++) row(i)]))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (var i = 0; i < 7; i++) row(i)]),
      ),
    );
  }

  Widget _dayCard(BuildContext context) {
    final day = _day(sel);
    final ex = exercisesOf(day);
    final rest = day['is_rest'] == true && ex.isEmpty;
    final tags = tagsOf(ex);
    final diff = WorkoutDiff(tree, d.wMaster);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
            Row(mainAxisSize: context.isPhone ? MainAxisSize.max : MainAxisSize.min, spacing: 8, children: [
              // Phone: the name takes what is left beside the 140 px select (200 + 140 would overflow at 360).
              () {
                final cell = _Cell(
                  key: ValueKey('name$sel$_gen'),
                  value: '${day['name'] ?? ''}',
                  placeholder: rest ? 'Rest' : 'Day name',
                  onChanged: (v) => _change(() => day['name'] = v),
                );
                return context.isPhone ? Expanded(child: cell) : SizedBox(width: 200, child: cell);
              }(),
              SizedBox(
                width: 140,
                child: AppSelect(rest ? 'Rest' : 'Workout', entries: [
                  MenuEntry('Workout', selected: !rest, onTap: () => _change(() => day['is_rest'] = false)),
                  MenuEntry('Rest', selected: rest, onTap: () => _change(() {
                        day['is_rest'] = true;
                        day['exercises'] = [];
                        _gen++;
                      })),
                ]),
              ),
            ]),
            Text(rest ? 'No exercises' : '${ex.length} exercises · drag to reorder · tap one to edit it', style: AppText.cap),
          ]),
        ),
        if (rest)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 10, children: [
              Text('Rest day. $first sees only ${pronoun(d.c)} rest note.', style: AppText.s(13, W.w5, color: AppColors.muted)),
              AppButton('Make it a workout day', size: BtnSize.sm, onPressed: () => _change(() => day['is_rest'] = false)),
            ]),
          )
        else ...[
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: ex.length,
              onReorderItem: (o, n) => _change(() {
                final x = _ex.removeAt(o);
                _ex.insert(n, x);
                _gen++;
              }),
              itemBuilder: (ctx, i) => _exRow(i, ex[i], tags[i], diff.exercise(week, sel, i, ex[i]), key: ValueKey('r$i$_gen')),
            ),
          ),
          if (ex.isEmpty) const PdEmpty('No exercises yet. Add the first one.'),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              _AddBtn('Add exercise', () => _pick()),
              _AddBtn('Add superset', () => _pick(superset: true)),
            ]),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
            Text(rest ? 'Rest day note' : 'Coach note for this day', style: AppText.label),
            _Cell(
              key: ValueKey('note$sel$_gen'),
              value: '${day['rest_note'] ?? ''}',
              placeholder: rest ? 'Walk 8,000 steps and stretch for 10 minutes' : 'Shown to $first above the workout',
              lines: 4,
              onChanged: (v) => _change(() => day['rest_note'] = v),
            ),
          ]),
        ),
      ]),
    );
  }

  /// One exercise of the day (`.cp-exl` row): drag handle, tag, name and what changed, its numbers in even
  /// columns (sets × reps, RPE, tempo, rest, load), the note, and Swap / Edit / Remove.
  Widget _exRow(int i, Map e, (String, bool) tag, String? was, {required Key key}) => LayoutBuilder(
        key: key,
        // Narrow day card (phone, or tablet / small desktop next to the 230 day list): actions beside the name and
        // the numbers at their own width, wrapping when they must. Wide: even columns.
        builder: (context, k) => _exRowIn(i, e, tag, was, phone: context.isPhone || k.maxWidth < 640),
      );

  Widget _exRowIn(int i, Map e, (String, bool) tag, String? was, {required bool phone}) {
    final note = '${e['note'] ?? ''}'.trim();
    Widget stat(String l, String v, double w) => SizedBox(
          width: phone ? null : w,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
            Text(l, style: AppText.s(11, W.w6, color: AppColors.muted)),
            Text(v.isEmpty ? '–' : v, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w7, color: v.isEmpty ? AppColors.muted : AppColors.text, tabular: true)),
          ]),
        );
    final stats = [
      stat('Sets × reps', '${e['sets'] ?? '–'} × ${'${e['reps'] ?? ''}'.ifEmpty('–')}', 92),
      stat('RPE', '${e['rpe'] ?? ''}', 44),
      stat('Tempo', '${e['tempo'] ?? ''}', 64),
      stat('Rest', restText(e['rest_seconds']), 76),
      stat('Load', loadText(e), 64),
    ];
    final acts = Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
      AppIconButton(AppIcons.swap, tooltip: 'Swap exercise', ghost: true, small: true, onPressed: () => _pick(swap: i)),
      AppIconButton(AppIcons.edit, tooltip: 'Edit', ghost: true, small: true, onPressed: () => _editExercise(i)),
      AppIconButton(AppIcons.trash, tooltip: 'Remove', ghost: true, small: true, onPressed: () => _remove(i)),
    ]);
    final name = Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
      Row(spacing: 6, children: [
        Flexible(child: Text(exName(e), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7))),
        if (was != null) Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
      ]),
      if (was != null) Text(was, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cap),
      if (e['edited'] == true && was == null) Text('Edited in the program', style: AppText.cap),
    ]);
    return Material(
      color: AppColors.card,
      child: Hover(
        onTap: () => _editExercise(i),
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          decoration: BoxDecoration(color: h ? AppColors.outlineHover : null, border: const Border(bottom: BorderSide(color: AppColors.line))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: ReorderableDragStartListener(
                index: i,
                child: const MouseRegion(cursor: SystemMouseCursors.grab, child: AppIcon(AppIcons.drag, size: 16, color: AppColors.chevron)),
              ),
            ),
            numTag(tag),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                if (phone) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: name), acts]) else name,
                // A Wrap, not a Row: at mid widths (side nav + 230 day list) the five columns need 396 px and
                // the name column can be narrower, so the last ones (Load, then Rest) drop to a second line.
                Wrap(spacing: phone ? 16 : 14, runSpacing: 8, children: stats),
                if (note.isNotEmpty)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                    const Padding(padding: EdgeInsets.only(top: 2), child: AppIcon(AppIcons.info, size: 13, color: AppColors.muted)),
                    Expanded(child: Text(note, style: AppText.s(12.5, W.w5, color: AppColors.text2, h: 1.45))),
                  ]),
              ]),
            ),
            if (!phone) acts,
          ]),
        ),
      ),
    );
  }

  /// Edit drawer for one exercise of the day: sets, reps, RPE, tempo, rest, load, note. Previous / Next walk the
  /// day's exercises; every change shows in the list at once (only for this client).
  Future<void> _editExercise(int start) {
    final i = ValueNotifier(start);
    Widget field(String label, Widget f) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [Text(label, style: AppText.label), f]);
    Widget two(BuildContext ctx, Widget a, Widget b) => ctx.isPhone
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [a, b])
        : Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [Expanded(child: a), Expanded(child: b)]);
    void go(int by) => i.value = (i.value + by + _ex.length) % _ex.length;
    return showAppDrawer(
      context,
      title: 'Edit exercise',
      sub: '${weekdayFull[sel]} · only for $first',
      icon: AppIcons.dumbbell,
      headerAction: ValueListenableBuilder(
        valueListenable: i,
        builder: (_, n, _) => Row(mainAxisSize: MainAxisSize.min, children: [
          AppIconButton(AppIcons.chevronLeft, tooltip: 'Previous', ghost: true, small: true, onPressed: _ex.length < 2 ? null : () => go(-1)),
          AppIconButton(AppIcons.chevronRight, tooltip: 'Next', ghost: true, small: true, onPressed: _ex.length < 2 ? null : () => go(1)),
        ]),
      ),
      builder: (ctx) => ListenableBuilder(
        listenable: Listenable.merge([i, _rev]),
        builder: (ctx, _) {
          final n = i.value;
          if (n >= _ex.length) return const SizedBox();
          final e = _ex[n] as Map;
          final tag = tagsOf(exercisesOf(_day(sel)))[n];
          Widget cell(String k, String v, ValueChanged<String> on, {String ph = '–', TextInputType? kb}) =>
              _Cell(key: ValueKey('ed$k$n$_gen'), value: v, placeholder: ph, height: 36, keyboard: kb, onChanged: (x) => _change(() => on(x)));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
            const SizedBox(height: 2),
            Row(spacing: 10, children: [
              numTag(tag),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text(exName(e), style: AppText.s(15, W.w8)),
                  Text('Exercise ${n + 1} of ${_ex.length}${'${e['superset_group'] ?? ''}'.isEmpty ? '' : ' · superset ${e['superset_group']}'}', style: AppText.cap),
                ]),
              ),
              AppButton('Swap', icon: AppIcons.swap, size: BtnSize.sm, onPressed: () => _pick(swap: n)),
            ]),
            two(ctx, field('Sets', cell('sets', '${e['sets'] ?? ''}', (x) => e['sets'] = int.tryParse(x.trim()) ?? 0, ph: '3', kb: TextInputType.number)),
                field('Reps', cell('reps', '${e['reps'] ?? ''}', (x) => e['reps'] = x.trim(), ph: '8–10'))),
            two(ctx, field('RPE (1–10)', cell('rpe', '${e['rpe'] ?? ''}', (x) => e['rpe'] = int.tryParse(x.trim()), kb: TextInputType.number)),
                field('Tempo', cell('tempo', '${e['tempo'] ?? ''}', (x) => e['tempo'] = x.trim(), ph: '3-1-1'))),
            two(ctx, field('Rest', cell('rest', restText(e['rest_seconds']), (x) => e['rest_seconds'] = parseRest(x), ph: '90 s or 2 min')),
                field('Load', cell('load', loadText(e), (x) => e['target_weight_kg'] = parseKg(x), ph: 'kg, or empty for body weight'))),
            field('Note for $first', _Cell(key: ValueKey('ednote$n$_gen'), value: '${e['note'] ?? ''}', placeholder: 'Two warm-up sets first, slow on the way down…', lines: 3, onChanged: (x) => _change(() => e['note'] = x))),
            Text('Rest up to 5 min. Changes carry to the later weeks when you save.', style: AppText.cap),
          ]);
        },
      ),
      footer: (ctx) => [
        if (ctx.isPhone) ...[
          AppButton('Previous', icon: AppIcons.chevronLeft, onPressed: _ex.length < 2 ? null : () => go(-1)),
          AppButton('Next', trailingIcon: AppIcons.chevronRight, onPressed: _ex.length < 2 ? null : () => go(1)),
        ] else
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: i,
              builder: (_, n, _) => Text(n < _ex.length ? 'Exercise ${n + 1} of ${_ex.length} · only for $first' : '', style: AppText.cap),
            ),
          ),
        AppButton.primary('Done', icon: AppIcons.check, onPressed: () => Navigator.of(ctx).pop()),
      ],
    ).whenComplete(() => disposeLater([i]));
  }
}

/// "90 s", "2 min", "1 min 30 s", "90" → seconds.
int parseRest(String s) {
  final t = s.toLowerCase().replaceAll(' ', '');
  final m = RegExp(r'^(\d+)min(?:(\d+)s?)?$').firstMatch(t);
  if (m != null) return int.parse(m[1]!) * 60 + int.parse(m[2] ?? '0');
  return int.tryParse(t.replaceAll('s', '').replaceAll('sec', '')) ?? 0;
}

/// "50 kg" / "42.5" → "50" / "42.5"; anything else (Body, Band) → null.
String? parseKg(String s) {
  final m = RegExp(r'^(\d+(?:\.\d+)?)').firstMatch(s.trim());
  return m?[1];
}

/// `.cp-ci`: a small input box that keeps its own text and reports each change.
class _Cell extends StatefulWidget {
  const _Cell({super.key, required this.value, required this.onChanged, this.placeholder = '', this.lines = 1, this.height = 32, this.keyboard});
  final String value, placeholder;
  final ValueChanged<String> onChanged;

  /// More than 1: a text area that many lines tall (the day's coach note).
  final int lines;
  final double height;
  final TextInputType? keyboard;
  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  late final t = TextEditingController(text: widget.value);
  @override
  void dispose() {
    t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.lines > 1
      ? AppTextField(controller: t, placeholder: widget.placeholder, maxLines: widget.lines, minLines: widget.lines, fontSize: 13, onChanged: widget.onChanged)
      : AppTextField(controller: t, placeholder: widget.placeholder, height: widget.height, fontSize: 13, keyboard: widget.keyboard, onChanged: widget.onChanged);
}

class _AddBtn extends StatelessWidget {
  const _AddBtn(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: h ? AppColors.accentSoft : null,
            borderRadius: AppRadius.all(AppRadius.input),
            border: Border.all(color: h ? AppColors.changedLine : AppColors.line2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
            const AppIcon(AppIcons.plus, size: 14, color: AppColors.accentText),
            Text(label, style: AppText.s(12.5, W.w7, color: AppColors.accentText)),
          ]),
        ),
      );
}

class _Info extends StatelessWidget {
  const _Info(this.tip);
  final String tip;
  @override
  Widget build(BuildContext context) => AppTooltip(message: tip, child: const Padding(padding: EdgeInsets.all(3), child: AppIcon(AppIcons.info, size: 16, color: AppColors.muted)));
}

/// Exercise picker drawer (`cwk.pk`): search, muscle tabs, tick rows (or pick one to swap), `Add exercise(s)` /
/// `Add superset` / `Swap`. Exercises already on the day are greyed with `On this day`.
Future<List<Map>?> showExercisePicker(BuildContext context,
    {required String title, required String sub, required bool single, required int need, required Set<String> have}) {
  final picked = ValueNotifier<List<Map>>([]);
  final mus = ValueNotifier('');
  final q = ValueNotifier('');
  final search = TextEditingController();
  final all = Services.api.get<Map>('exercises/', query: {'page_size': 200}).then((r) => [for (final x in r['results'] as List) x as Map]);
  const groups = [('', 'All'), ('chest', 'Chest'), ('back', 'Back'), ('legs', 'Legs'), ('shoulders', 'Shoulders'), ('arms', 'Arms'), ('core', 'Core'), ('cardio', 'Cardio')];
  return showAppDrawer<List<Map>>(
    context,
    title: title,
    sub: sub,
    icon: AppIcons.dumbbell,
    fixedBody: true,
    builder: (ctx) => FutureBuilder<List<Map>>(
      future: all,
      builder: (ctx, snap) {
        if (snap.hasError) return const EmptyState('Could not load the exercises');
        if (!snap.hasData) return const CpLoading();
        final list = snap.data!;
        return ListenableBuilder(
          listenable: Listenable.merge([picked, mus, q]),
          builder: (ctx, _) {
            final rows = list.where((x) => (mus.value.isEmpty || x['muscle_group'] == mus.value) && (q.value.isEmpty || '${x['name']}'.toLowerCase().contains(q.value))).toList();
            Widget row(int i) {
              final x = rows[i];
              final on2 = have.contains('${x['id']}');
              final on = picked.value.any((p) => p['id'] == x['id']);
              return Hover(
                onTap: on2 ? null : () => picked.value = single ? [x] : (on ? picked.value.where((p) => p['id'] != x['id']).toList() : [...picked.value, x]),
                builder: (_, h, _) => Opacity(
                  opacity: on2 ? .55 : 1,
                  child: Padding(
                    // `.pb-pkr`, tightened: 8px rows with a 1px line between them.
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(spacing: 12, children: [
                      single ? AppRadio(selected: on) : AppCheckbox(value: on),
                      MediaTile(tone: i, size: 40),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                          Text('${x['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7, color: h && !on2 ? AppColors.accentText : AppColors.text)),
                          Text(['${x['primary_muscle'] ?? ''}'.ifEmpty('${x['muscle_group']}'), '${x['level'] ?? ''}'.capFirst].where((s) => s.isNotEmpty).join(' · '),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.text2)),
                        ]),
                      ),
                      on2 ? const AppBadge('On this day', tone: Tone.info, plain: true) : Text('${x['equipment'] ?? ''}'.capFirst, style: AppText.cap),
                    ]),
                  ),
                ),
              );
            }

            // `.pb-pk`: search, muscle tabs and the hint stay put (`.pb-pkh`); only the list scrolls (`.pb-pklist`).
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 14),
              AppSearchField(controller: search, placeholder: 'Search exercises', onChanged: (v) => q.value = v.trim().toLowerCase()),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(spacing: 6, children: [
                  for (final (k, l) in groups)
                    FilterChipX(l, selected: mus.value == k, count: k.isEmpty ? list.length : list.where((x) => x['muscle_group'] == k).length, onTap: () => mus.value = k),
                ]),
              ),
              if (single || need == 2) ...[
                const SizedBox(height: 6),
                Text(single ? 'Pick one exercise. Sets, reps and rest stay the same.' : 'Pick 2 exercises. They are done back to back.', style: AppText.cap),
              ],
              const SizedBox(height: 4),
              Expanded(
                child: rows.isEmpty
                    ? const Align(alignment: Alignment.topCenter, child: EmptyState('No exercises match'))
                    : ListView.separated(
                        padding: const EdgeInsets.only(top: 2, bottom: 12),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const Divider1(),
                        itemBuilder: (_, i) => row(i),
                      ),
              ),
            ]);
          },
        );
      },
    ),
    footer: (ctx) => [
      ValueListenableBuilder(
        valueListenable: picked,
        builder: (_, p, _) {
          final t = Text(p.isEmpty ? (single ? 'Pick one' : 'Tick the exercises to add') : '${p.length} selected', style: AppText.cap);
          return ctx.isPhone ? t : Expanded(child: t);
        },
      ),
      if (!ctx.isPhone) AppButton('Cancel', onPressed: () => Navigator.of(ctx).pop()),
      ValueListenableBuilder(
        valueListenable: picked,
        builder: (_, p, _) => AppButton.primary(
          single ? 'Swap' : (need == 2 ? 'Add superset' : (p.length > 1 ? 'Add ${p.length} exercises' : 'Add exercise')),
          icon: AppIcons.check,
          expand: ctx.isPhone,
          onPressed: p.length >= need ? () => Navigator.of(ctx).pop(p) : null,
        ),
      ),
    ],
  ).whenComplete(() => disposeLater([picked, mus, q, search]));
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
  String get capFirst => isEmpty ? this : this[0].toUpperCase() + substring(1);
}
