import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../app/shell/page.dart';
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
import '../../trainer/client_profile/cp_plans_edit.dart' show showExercisePicker;
import '../lib_common.dart';
import 'builder_model.dart';
import 'builder_sheets.dart';

/// Program builder (boards `ProgramBuilder` / `ProgramBuilderMobile`): weeks as pills, the week's days as a
/// 7-column grid (a list on narrow screens), and the open day's exercises with sets, reps, RPE, tempo and rest.
/// Every change shows at once and is saved in the background ([BuilderModel]); most have Undo on the toast.
/// People who may not change the program (D-39) see it read-only with a Duplicate button.
class ProgramBuilderScreen extends StatefulWidget {
  const ProgramBuilderScreen({super.key, required this.id});
  final String id;
  @override
  State<ProgramBuilderScreen> createState() => _ProgramBuilderScreenState();
}

class _ProgramBuilderScreenState extends State<ProgramBuilderScreen> {
  late final m = BuilderModel(widget.id);
  final _note = TextEditingController();
  Object? _noteFor;
  Timer? _noteTimer;
  final _pills = ScrollController();

  @override
  void initState() {
    super.initState();
    m.load();
  }

  @override
  void dispose() {
    _saveNote();
    m.flushNow().whenComplete(m.dispose);
    _note.dispose();
    _pills.dispose();
    super.dispose();
  }

  bool get _phone => context.isPhone;
  bool get _edit => m.canEdit;

  // ─────────────────────────────── helpers

  Future<void> _run(Future<void> Function() f, {String fail = 'Could not do that'}) async {
    try {
      await f();
    } on ApiError catch (e) {
      if (mounted) showToast(context, fail, sub: e.message, kind: ToastKind.err);
    }
  }

  /// Applies [f] to the tree and shows a toast whose Undo puts the tree back.
  void _change(void Function() f, {String? toast, String? sub, bool undo = true}) {
    final snap = m.snapshot();
    final keepSel = m.sel;
    m.edit(f);
    if (toast != null && mounted) {
      showToast(context, toast, sub: sub, action: undo ? 'Undo' : null, onAction: undo ? () {
        m.sel = keepSel;
        m.restore(snap);
      } : null);
    }
  }

  List<Map> _dayList() => m.days;

  /// Days stay in a row from Monday: after a move or remove, weekday = position.
  void _setDays(List<Map> ds) {
    for (var i = 0; i < ds.length; i++) {
      ds[i]['weekday'] = i;
    }
    m.weekMap['days'] = ds;
  }

  List _exList(Map d) => (d['exercises'] as List?) ?? (d['exercises'] = []);

  /// Coach note: saved 600 ms after typing stops, and when another day opens or the page closes.
  void _syncNote() {
    final d = m.day;
    final key = d == null ? null : (m.week, m.sel, d['id']);
    if (key == _noteFor) return;
    _saveNote();
    _noteFor = key;
    _note.text = '${d?['rest_note'] ?? ''}';
  }

  void _typed(String v) {
    _noteTimer?.cancel();
    _noteTimer = Timer(const Duration(milliseconds: 600), _saveNote);
  }

  void _saveNote() {
    if (_noteTimer == null) return;
    _noteTimer!.cancel();
    _noteTimer = null;
    final d = m.day;
    if (d == null || '${d['rest_note'] ?? ''}' == _note.text) return;
    if (mounted) {
      m.edit(() => d['rest_note'] = _note.text);
    } else {
      d['rest_note'] = _note.text;
      m.retry();
    }
  }

  // ─────────────────────────────── program actions

  Future<void> _rename() async {
    final v = await showNameModal(context,
        title: 'Rename program', sub: 'Clients see the new name in their app', label: 'Program name', initial: m.name, button: 'Save');
    if (v == null || v == m.name) return;
    _run(() async {
      await m.rename(v);
      if (mounted) showToast(context, 'Program renamed', sub: v);
    }, fail: 'Could not rename it');
  }

  void _duplicate() => _run(() async {
        await m.flushNow();
        final c = await Services.api.post<Map>('programs/${m.id}/duplicate/');
        if (!mounted) return;
        context.go('/programs/${c['id']}');
        showToast(context, 'Program duplicated', sub: 'Now editing ${c['name']}');
      }, fail: 'Could not duplicate it');

  void _archive() {
    final arch = m.archived;
    _run(() async {
      await m.setArchived(!arch);
      if (!mounted) return;
      showToast(context, arch ? 'Program restored' : 'Program archived',
          sub: 'Assigned clients keep their plan', action: 'Undo', onAction: () => _run(() => m.setArchived(arch)));
    });
  }

  Future<void> _delete() async {
    int n = 0;
    try {
      n = ((await Services.api.get<Map>('programs/${m.id}/delete-preview/'))['clients'] as num?)?.toInt() ?? 0;
    } on ApiError catch (_) {}
    if (!mounted) return;
    final ok = await confirmAction(context,
        title: 'Delete this program?',
        body: '${m.name} will be removed for good${n > 0 ? ' and unassigned from ${plural(n, 'client')}' : ''}. Workouts they already logged stay safe.',
        confirm: 'Delete',
        danger: true,
        icon: AppIcons.trash);
    if (!ok || !mounted) return;
    final name = m.name, id = m.id;
    _run(() async {
      await m.flushNow();
      await Services.api.delete('programs/$id/');
      if (!mounted) return;
      final router = GoRouter.of(context);
      router.go('/programs');
      showToast(context, 'Program deleted', sub: name, action: 'Undo', onAction: () async {
        try {
          await Services.api.post('programs/$id/restore/');
          router.go('/programs/$id');
        } on ApiError catch (_) {}
      });
    }, fail: 'Could not delete it');
  }

  void _programMenu(BuildContext anchor) => showAppMenu(anchor, width: 220, [
        if (_edit) MenuEntry('Rename', icon: AppIcons.edit, onTap: _rename),
        if (m.canCreate) MenuEntry('Duplicate program', icon: AppIcons.copy, onTap: _duplicate),
        if (_edit) MenuEntry(m.archived ? 'Restore' : 'Archive', icon: m.archived ? AppIcons.undo : AppIcons.archive, onTap: _archive),
        if (_edit) const MenuEntry.separator(),
        if (_edit) MenuEntry('Delete', icon: AppIcons.trash, danger: true, onTap: _delete),
      ]);

  Future<void> _assign() async {
    final before = Services.api.get<List>('programs/${m.id}/clients/').then((r) => [
          for (final x in r) '${((x as Map)['client'] as Map?)?['id'] ?? x['client']}',
        ]);
    final r = await showAssignModal(context, m);
    if (r == null || !mounted) return;
    await m.reload();
    if (!mounted) return;
    final n = m.clientCount;
    List<String>? prev;
    try {
      prev = await before;
    } on ApiError catch (_) {}
    if (!mounted) return;
    showToast(context, n > 0 ? 'Assigned to ${plural(n, 'client')}' : 'Program unassigned',
        sub: '${r.$1} added · ${r.$2} removed',
        action: prev == null ? null : 'Undo',
        onAction: prev == null
            ? null
            : () => _run(() async {
                  await Services.api.post('programs/${m.id}/assign/', {'clients': prev});
                  await m.reload();
                }));
  }

  Future<void> _clients() async {
    final change = await showClientsDrawer(context, m);
    if (change == true && mounted) _assign();
  }

  // ─────────────────────────────── week actions

  void _copyWeek() {
    final last = m.week == m.weeks.length;
    final snap = m.snapshot();
    final n = m.days.length, w = m.week;
    _run(() async {
      await m.copyWeek();
      if (!mounted) return;
      showToast(context, last ? 'Week ${w + 1} added' : 'Week $w copied to week ${w + 1}',
          sub: '${plural(n, 'day')} · all exercises and notes', action: 'Undo', onAction: () => m.restore(snap));
    }, fail: 'Could not copy the week');
  }

  // ─────────────────────────────── day actions

  Future<void> _addDay() async {
    final ds = _dayList();
    if (ds.length >= 7) return;
    final v = await showNameModal(context,
        title: 'Add day', sub: 'Week ${m.week}', label: 'Workout name', placeholder: 'e.g. Upper B', button: 'Add day', icon: AppIcons.plus);
    if (v == null || !mounted) return;
    _change(() {
      _setDays([...ds, {'weekday': ds.length, 'name': v, 'is_rest': false, 'rest_note': '', 'exercises': []}]);
      m.sel = ds.length;
    }, toast: '$v added', sub: weekdayNames[ds.length]);
  }

  Future<void> _renameDay() async {
    final d = m.day;
    if (d == null) return;
    final v = await showNameModal(context, title: 'Rename day', sub: m.dayHead, label: 'Workout name', initial: '${d['name'] ?? ''}', button: 'Save');
    if (v == null || !mounted) return;
    _change(() => d['name'] = v, toast: 'Day renamed', sub: v, undo: false);
  }

  void _moveDay(int by) {
    final ds = _dayList(), i = m.sel, j = i + by;
    if (j < 0 || j >= ds.length) return;
    _change(() {
      final t = ds[i];
      ds[i] = ds[j];
      ds[j] = t;
      _setDays(ds);
      m.sel = j;
    });
  }

  void _toggleRest() {
    final d = m.day;
    if (d == null) return;
    final rest = d['is_rest'] == true, title = dayTitle(d);
    _change(() {
      d['is_rest'] = !rest;
      if (rest && '${d['name']}' == 'Rest') d['name'] = '';
    },
        toast: rest ? 'Changed to a workout day' : '$title is now a rest day',
        sub: rest ? null : 'Its exercises are kept if you change it back',
        undo: false);
  }

  void _removeDay() {
    final ds = _dayList(), i = m.sel;
    if (ds.length < 2) return;
    final title = dayTitle(ds[i]);
    _change(() {
      _setDays([for (var k = 0; k < ds.length; k++) if (k != i) ds[k]]);
      m.sel = (i - 1).clamp(0, 6);
    }, toast: '$title removed', sub: 'Later days of the week moved up');
  }

  void _dayMenu(BuildContext anchor) {
    final ds = _dayList(), i = m.sel, d = m.day!;
    final rest = d['is_rest'] == true;
    showAppMenu(anchor, width: 240, [
      MenuEntry.header(m.dayHead),
      MenuEntry('Rename', icon: AppIcons.edit, onTap: _renameDay),
      MenuEntry('Move earlier', icon: AppIcons.chevronUp, sub: i > 0 ? 'Swap with ${weekdayNames[i - 1]}' : 'Already the first day', onTap: i > 0 ? () => _moveDay(-1) : null),
      MenuEntry('Move later',
          icon: AppIcons.chevronDown, sub: i < ds.length - 1 ? 'Swap with ${weekdayNames[i + 1]}' : 'Already the last day', onTap: i < ds.length - 1 ? () => _moveDay(1) : null),
      MenuEntry(rest ? 'Make workout day' : 'Make rest day', icon: rest ? AppIcons.dumbbell : AppIcons.moon, onTap: _toggleRest),
      if (ds.length > 1) const MenuEntry.separator(),
      if (ds.length > 1) MenuEntry('Remove day', icon: AppIcons.trash, danger: true, onTap: _removeDay),
    ]);
  }

  // ─────────────────────────────── exercise actions

  Future<void> _addExercises([int? dayIndex]) async {
    if (dayIndex != null) m.pickDay(dayIndex);
    final d = m.day;
    if (d == null) return;
    final have = {for (final e in m.exercisesOf(d)) '${e['exercise']}'};
    final picked = await showExercisePicker(context, title: 'Add exercises', sub: '${m.dayHead} · ${dayTitle(d)}', single: false, need: 1, have: have);
    if (picked == null || picked.isEmpty || !mounted) return;
    _change(() {
      final xs = _exList(d);
      for (final x in picked) {
        xs.add({
          'exercise': x['id'],
          'exercise_detail': x,
          'superset_group': '',
          'sets': x['default_sets'] ?? 3,
          'reps': '${x['default_reps'] ?? '10'}',
          'rpe': x['default_rpe'],
          'rest_seconds': x['default_rest_seconds'] ?? 90,
          'tempo': '${x['default_tempo'] ?? ''}',
          'target_weight_kg': null,
          'note': '',
          'override': <String, dynamic>{},
        });
      }
    },
        toast: picked.length == 1 ? '${picked.first['name']} added' : '${plural(picked.length, 'exercise')} added',
        sub: 'Default sets and reps from the exercise · ${_phone ? 'tap' : 'click'} a row to change them');
  }

  Future<void> _editSets(Map e) async {
    if (!_edit) return;
    final r = await showSetsModal(context, e);
    if (r == null || !mounted) return;
    _change(() => e.addAll(r),
        toast: '${exNameOf(e)} updated', sub: '${r['sets']} × ${r['reps']} · Rest ${restShort(r['rest_seconds'])}', undo: false);
  }

  Future<void> _editForProgram(Map e) async {
    final r = await showEditForProgram(context, e, program: m.name, dayHead: '${m.dayHead} · ${dayTitle(m.day!)}');
    if (r == null || !mounted) return;
    if (r.isEmpty) return _reset(e);
    _change(() => e['override'] = r, toast: '${exNameOf(e)} edited for this program', sub: 'The library and other programs stay the same');
  }

  void _reset(Map e) {
    final name = exNameOf(e);
    _change(() => e['override'] = <String, dynamic>{}, toast: '$name reset to the library version', sub: 'Library changes reach it again');
  }

  void _moveEx(List xs, int i, int by) {
    final j = i + by;
    if (j < 0 || j >= xs.length) return;
    _change(() {
      final t = xs[i];
      xs[i] = xs[j];
      xs[j] = t;
    });
  }

  void _superset(List xs, int i) {
    final e = xs[i] as Map, g = '${e['superset_group'] ?? ''}';
    if (g.isNotEmpty) {
      _change(() {
        e['superset_group'] = '';
        cleanSupersets(xs);
      });
      return;
    }
    if (i + 1 >= xs.length) return;
    final next = xs[i + 1] as Map, ng = '${next['superset_group'] ?? ''}';
    final used = {for (final o in xs) '${(o as Map)['superset_group'] ?? ''}'};
    final letter = ng.isNotEmpty ? ng : 'ABCDEFGH'.split('').firstWhere((c) => !used.contains(c), orElse: () => 'A');
    _change(() {
      e['superset_group'] = letter;
      next['superset_group'] = letter;
    });
  }

  void _removeEx(List xs, int i) {
    final name = exNameOf(xs[i] as Map);
    _change(() {
      xs.removeAt(i);
      cleanSupersets(xs);
    }, toast: '$name removed', sub: dayTitle(m.day!));
  }

  void _exMenu(BuildContext anchor, List xs, int i) {
    final e = xs[i] as Map;
    final g = '${e['superset_group'] ?? ''}';
    final edited = (e['override'] as Map?)?.isNotEmpty == true;
    showAppMenu(anchor, width: 240, [
      MenuEntry('Edit sets and rest', icon: AppIcons.edit, onTap: () => _editSets(e)),
      MenuEntry('Edit for this program', icon: AppIcons.docLines, onTap: () => _editForProgram(e)),
      if (edited) MenuEntry('Reset to library version', icon: AppIcons.undo, onTap: () => _reset(e)),
      MenuEntry('Exercise details', icon: AppIcons.eye, onTap: () => context.go('/exercises/${e['exercise']}')),
      MenuEntry('Move up', icon: AppIcons.chevronUp, onTap: i > 0 ? () => _moveEx(xs, i, -1) : null),
      MenuEntry('Move down', icon: AppIcons.chevronDown, onTap: i < xs.length - 1 ? () => _moveEx(xs, i, 1) : null),
      if (g.isNotEmpty)
        MenuEntry('Remove from superset', icon: AppIcons.link, onTap: () => _superset(xs, i))
      else if (i < xs.length - 1)
        MenuEntry('Make superset with next', icon: AppIcons.link, onTap: () => _superset(xs, i)),
      const MenuEntry.separator(),
      MenuEntry('Remove', icon: AppIcons.trash, danger: true, onTap: () => _removeEx(xs, i)),
    ]);
  }

  // ─────────────────────────────── build

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: m,
        builder: (context, _) {
          if (m.loading) {
            return StaffPage(children: [
              _crumb(),
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5))),
            ]);
          }
          if (m.error != null || m.program == null) {
            final gone = m.error?.status == 404;
            return StaffPage(children: [
              _crumb(),
              AppCard(
                child: EmptyState(gone ? 'This program is gone' : 'Could not open this program',
                    icon: AppIcons.dumbbell,
                    sub: gone ? 'It may have been deleted.' : m.error?.message,
                    action: AppButton(gone ? 'Back to programs' : 'Try again', onPressed: gone ? () => context.go('/programs') : m.load)),
              ),
            ]);
          }
          _syncNote();
          final phone = _phone;
          return StaffPage(
            onRefresh: m.reload,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 12 : 14, children: [
                _crumb(),
                _head(phone),
              ]),
              if (m.archived) _archBanner(),
              if (!_edit) _readOnly(),
              if (m.saveError != null) _saveFailed(),
              _weekCard(phone),
              if (m.day != null) _panel(phone),
            ],
          );
        },
      );

  Widget _crumb() => Row(spacing: 6, children: [
        Hover(
          onTap: () => context.go('/programs'),
          builder: (_, h, _) => Text('Programs', style: AppText.s(13, W.w5, color: h ? AppColors.text : AppColors.muted)),
        ),
        const AppIcon(AppIcons.chevronRight, size: 13, color: AppColors.chevron),
        Text('Master plan', style: AppText.s(13, W.w6)),
      ]);

  Widget _head(bool phone) {
    final clientsL = m.clientCount > 0 ? plural(m.clientCount, 'client') : 'No clients yet';
    final narrow = compactTop(context);
    return PageTop(
      title: m.name,
      sub: m.sub,
      actions: [
        if (_edit || m.canCreate) Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'Program options', onPressed: () => _programMenu(b))),
        AppButton(clientsL, icon: AppIcons.clientsAlt, iconOnly: phone || narrow, onPressed: _clients),
        if (m.canAssign && !m.archived) AppButton.primary('Assign', icon: AppIcons.plus, iconOnly: phone, onPressed: _assign),
      ],
    );
  }

  Widget _archBanner() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: AppColors.warnBg, borderRadius: AppRadius.all(AppRadius.card)),
        child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const AppBadge('Archived', tone: Tone.warn, plain: true),
          Text('Hidden from the programs list. You can still edit it.', style: AppText.s(13, W.w6, color: AppColors.warnText)),
          if (_edit) SizedBox(height: 32, child: AppButton('Restore', size: BtnSize.sm, onPressed: _archive)),
        ]),
      );

  Widget _readOnly() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(AppRadius.card)),
        child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const AppIcon(AppIcons.lock, size: 15, color: AppColors.muted),
          Text('Only Vimal or a trainer with “Edit gym templates” can change this program.', style: AppText.s(13, W.w6, color: AppColors.text2)),
          if (m.canCreate) AppButton('Duplicate to edit', size: BtnSize.sm, icon: AppIcons.copy, onPressed: _duplicate),
        ]),
      );

  Widget _saveFailed() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: AppColors.badBg, borderRadius: AppRadius.all(AppRadius.card)),
        child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Your last change is not saved. ${m.saveError!.message}', style: AppText.s(13, W.w6, color: AppColors.badText)),
          AppButton('Try again', size: BtnSize.sm, onPressed: m.retry),
        ]),
      );

  // ─────────────────────────────── week card

  Widget _weekCard(bool phone) {
    final last = m.week == m.weeks.length;
    final copy = AppButton(last ? 'Copy week ${m.week} → new week' : 'Copy week ${m.week} → ${m.week + 1}',
        size: BtnSize.sm, icon: AppIcons.copy, onPressed: _edit ? _copyWeek : null);
    final pills = SingleChildScrollView(
      controller: _pills,
      scrollDirection: Axis.horizontal,
      child: Row(spacing: 6, children: [
        for (final w in m.weeks)
          () {
            final n = (w['number'] as num).toInt(), on = n == m.week;
            return Hover(
              onTap: () => m.pickWeek(n),
              builder: (_, h, _) => Container(
                height: 30,
                constraints: const BoxConstraints(minWidth: 40),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: on ? AppColors.text : (h ? AppColors.pbPillHover : AppColors.sub), borderRadius: AppRadius.all(8)),
                child: Text('W$n', style: AppText.s(12.5, W.w7, color: on ? Colors.white : AppColors.text2)),
              ),
            );
          }(),
      ]),
    );
    return AppCard(
      padding: phone ? const EdgeInsets.all(12) : const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 10 : 14, children: [
        if (phone)
          Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [pills, if (_edit) copy])
        else
          Row(spacing: 12, children: [Expanded(child: pills), if (_edit) copy]),
        LayoutBuilder(builder: (context, c) => c.maxWidth >= 840 ? _grid() : _dayRows()),
      ]),
    );
  }

  Widget _grid() {
    final ds = _dayList();
    return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
      for (var i = 0; i < 7; i++)
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
            Padding(padding: const EdgeInsets.only(left: 2), child: Text(weekdayShort[i].toUpperCase(), style: AppText.over)),
            if (i < ds.length) ...[
              _dayCard(ds[i], i),
              if (_edit && ds[i]['is_rest'] != true)
                Align(alignment: Alignment.centerLeft, child: _addText(() => _addExercises(i), height: 26)),
            ] else if (i == ds.length && _edit)
              _slot(132),
          ]),
        ),
    ]);
  }

  Widget _dayRows() {
    final ds = _dayList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      for (var i = 0; i < ds.length; i++)
        Row(spacing: 8, children: [
          SizedBox(width: 38, child: Text(weekdayShort[i].toUpperCase(), style: AppText.over)),
          Expanded(child: _dayCard(ds[i], i, compact: true)),
          if (_edit && ds[i]['is_rest'] != true) _addText(() => _addExercises(i), height: 32),
        ]),
      if (ds.length < 7 && _edit)
        Row(spacing: 8, children: [
          SizedBox(width: 38, child: Text(weekdayShort[ds.length].toUpperCase(), style: AppText.over)),
          Expanded(child: _slot(46)),
        ]),
    ]);
  }

  Widget _addText(VoidCallback onTap, {required double height}) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(color: h ? AppColors.hover : null, borderRadius: AppRadius.all(AppRadius.btn)),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
            const AppIcon(AppIcons.plus, size: 14, color: AppColors.accentText),
            Text('Add', style: AppText.s(12, W.w7, color: AppColors.accentText)),
          ]),
        ),
      );

  Widget _slot(double h) => Hover(
        onTap: _addDay,
        builder: (_, hv, _) => Container(
          constraints: BoxConstraints(minHeight: h),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hv ? AppColors.pbSlotHover : null,
            borderRadius: AppRadius.all(10),
            border: Border.all(color: hv ? AppColors.accent : AppColors.line2, width: 1.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
            AppIcon(AppIcons.plus, size: 15, color: hv ? AppColors.accentText : AppColors.muted),
            Text('Day', style: AppText.s(13, W.w6, color: hv ? AppColors.accentText : AppColors.muted)),
          ]),
        ),
      );

  Widget _dayCard(Map d, int i, {bool compact = false}) {
    final on = i == m.sel, rest = d['is_rest'] == true;
    final ex = m.exercisesOf(d);
    return Hover(
      onTap: () => m.pickDay(i),
      builder: (_, h, _) {
        final border = on ? AppColors.accent : (h ? AppColors.pbDayHover : (rest ? AppColors.line : AppColors.line2));
        final deco = BoxDecoration(
          color: on ? AppColors.pbOnBg : (rest ? AppColors.pbRestBg : AppColors.card),
          borderRadius: AppRadius.all(10),
          border: Border.all(color: border),
          boxShadow: on ? const [BoxShadow(color: AppColors.accentSoft, spreadRadius: 3)] : null,
        );
        final title = Text(dayTitle(d), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(compact ? 14 : 13.5, W.w7));
        final sum = Text(daySummary(d), maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis, style: AppText.s(compact ? 12 : 11.5, W.w5, color: AppColors.muted));
        final moon = AppIcon(AppIcons.moon, size: 16, color: AppColors.muted);
        final box = compact
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: deco,
                child: Row(spacing: 8, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [title, sum])),
                  if (rest) moon,
                ]),
              )
            : Container(
                constraints: const BoxConstraints(minHeight: 132),
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                decoration: deco,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 3, children: [
                  title,
                  Padding(padding: const EdgeInsets.only(bottom: 4), child: sum),
                  if (!rest)
                    for (final e in ex.take(3))
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                        child: Row(spacing: 6, children: [
                          Expanded(child: Text(exNameOf(e), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w5, color: AppColors.text2))),
                          Text('${e['sets']}×${e['reps']}', style: AppText.s(11.5, W.w6, color: AppColors.muted)),
                        ]),
                      ),
                  if (!rest && ex.length > 3)
                    Padding(padding: const EdgeInsets.only(top: 2), child: Text('+${ex.length - 3} more', style: AppText.s(11.5, W.w6, color: AppColors.accentText))),
                  if (rest) Padding(padding: const EdgeInsets.only(top: 10), child: Align(alignment: Alignment.centerLeft, child: moon)),
                ]),
              );
        return Semantics(button: true, selected: on, label: '${weekdayNames[i]}, ${dayTitle(d)}', child: box);
      },
    );
  }

  // ─────────────────────────────── day panel

  Widget _panel(bool phone) {
    final d = m.day!;
    final rest = d['is_rest'] == true;
    final ex = m.exercisesOf(d);
    final sets = ex.fold<int>(0, (a, e) => a + ((e['sets'] as num?)?.toInt() ?? 0));
    final sumL = rest ? 'Rest day' : (ex.isEmpty ? 'No exercises yet' : '≈ ${dayMinutes(ex)} min · $sets sets · ${plural(ex.length, 'exercise')}');
    final menu = Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'Day options', onPressed: () => _dayMenu(b)));
    final add = AppButton('Add exercise', icon: AppIcons.plus, expand: phone, onPressed: () => _addExercises());
    final titles = Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
      Text(m.dayHead.toUpperCase(), style: AppText.over),
      Text(dayTitle(d), style: AppText.h2.copyWith(fontSize: phone ? 18 : 20)),
      Text(sumL, style: AppText.sub),
    ]);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: phone ? const EdgeInsets.fromLTRB(14, 14, 14, 12) : const EdgeInsets.fromLTRB(20, 16, 20, 14),
          child: phone
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
                  titles,
                  if (_edit) Row(spacing: 10, children: [menu, if (!rest) Expanded(child: add)]),
                ])
              : Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 10, children: [Expanded(child: titles), if (_edit) menu, if (_edit && !rest) add]),
        ),
        if (!rest)
          if (ex.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
              child: Text('No exercises yet. Add one from the exercise library.', textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)),
            )
          else
            LayoutBuilder(builder: (context, c) => phone || c.maxWidth < 760 ? _cards(d) : _table(d)),
        if (rest) _restBlock(phone),
        _noteBox(phone, rest),
      ]),
    );
  }

  /// "1", "2", superset rows "A1", "A2".
  List<String> _tags(List xs) {
    var n = 0;
    return [
      for (var i = 0; i < xs.length; i++)
        () {
          final g = '${(xs[i] as Map)['superset_group'] ?? ''}';
          if (g.isEmpty) return '${++n}';
          final k = xs.take(i).where((o) => '${(o as Map)['superset_group'] ?? ''}' == g).length;
          return '$g${k + 1}';
        }(),
    ];
  }

  Widget _tag(String t, bool ss) => Container(
        constraints: const BoxConstraints(minWidth: 26),
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: ss ? AppColors.pbSsTagBg : AppColors.sub, borderRadius: AppRadius.all(6)),
        child: Text(t, style: AppText.s(11.5, W.w8, color: ss ? AppColors.pbSsTagText : AppColors.text2)),
      );

  Widget _exName(Map e) {
    final edited = (e['override'] as Map?)?.isNotEmpty == true;
    final note = '${e['note'] ?? ''}'.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(exNameOf(e), style: AppText.s(13.5, W.w7)),
        if (edited) const AppBadge('Edited for this program', tone: Tone.warn, plain: true),
      ]),
      Padding(padding: const EdgeInsets.only(top: 1), child: Text(exMuscles(e), style: AppText.s(12, W.w5, color: AppColors.muted))),
      if (note.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(spacing: 5, children: [
            const AppIcon(AppIcons.docLines, size: 13, color: AppColors.muted),
            Flexible(child: Text(note, style: AppText.s(12, W.w5, color: AppColors.text2))),
          ]),
        ),
    ]);
  }

  Widget _rowMenu(List xs, int i) => _edit
      ? Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'Exercise options', small: true, ghost: true, onPressed: () => _exMenu(b, xs, i)))
      : const SizedBox(width: 30);

  static const _cols = [44.0, null, 76.0, 120.0, 72.0, 110.0, 90.0, 48.0];

  Widget _cell(int col, Widget child, {bool num = false}) {
    final w = _cols[col];
    final c = Padding(padding: EdgeInsets.only(left: col == 0 ? 14 : 10, right: col == 1 ? 10 : (col == 7 ? 10 : 0)), child: Align(alignment: num ? Alignment.centerRight : Alignment.centerLeft, child: child));
    return w == null ? Expanded(child: c) : SizedBox(width: w, child: c);
  }

  Widget _table(Map d) {
    final xs = _exList(d);
    final tags = _tags(xs);
    String g(int i) => i < 0 || i >= xs.length ? '' : '${(xs[i] as Map)['superset_group'] ?? ''}';
    final head = Container(
      height: 34,
      decoration: const BoxDecoration(color: AppColors.tableHead, border: Border(top: BorderSide(color: AppColors.line), bottom: BorderSide(color: AppColors.line))),
      child: Row(children: [
        for (final (i, l) in ['', 'Exercise', 'Sets', 'Reps', 'RPE', 'Tempo', 'Rest', ''].indexed)
          _cell(i, Text(l, style: AppText.s(12, W.w7, color: AppColors.muted)), num: i == 2 || i == 4 || i == 6),
      ]),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      head,
      for (var i = 0; i < xs.length; i++)
        () {
          final e = xs[i] as Map, ss = g(i).isNotEmpty, endOfSs = ss && g(i + 1) != g(i);
          final v = AppText.s(13.5, W.w5, tabular: true), b = AppText.s(13.5, W.w7, tabular: true);
          return Hover(
            onTap: _edit ? () => _editSets(e) : null,
            builder: (_, h, _) => Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: ss ? AppColors.pbSsRow : (h && _edit ? AppColors.tableHead : null),
                border: Border(bottom: BorderSide(color: ss && !endOfSs ? Colors.transparent : AppColors.line)),
              ),
              foregroundDecoration: ss ? const BoxDecoration(border: Border(left: BorderSide(color: AppColors.pbSsBar, width: 3))) : null,
              child: Row(children: [
                _cell(0, _tag(tags[i], ss)),
                _cell(1, _exName(e)),
                _cell(2, Text('${e['sets']}', style: b), num: true),
                _cell(3, Text('${e['reps']}', style: b)),
                _cell(4, Text(e['rpe'] == null || e['rpe'] == 0 ? '–' : '${e['rpe']}', style: v), num: true),
                _cell(5, Text('${e['tempo'] ?? ''}'.isEmpty ? '–' : '${e['tempo']}', style: v)),
                _cell(6, Text(restShort(e['rest_seconds']), style: v), num: true),
                _cell(7, _rowMenu(xs, i)),
              ]),
            ),
          );
        }(),
    ]);
  }

  /// Phone: one card per exercise, the numbers as grey chips under the name.
  Widget _cards(Map d) {
    final xs = _exList(d);
    final tags = _tags(xs);
    Widget chip(String l, String v, bool ss) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(color: ss ? AppColors.card : AppColors.sub, borderRadius: AppRadius.all(6)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, style: AppText.s(10.5, W.w6, color: AppColors.muted)),
            Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w6, tabular: true)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < xs.length; i++)
        () {
          final e = xs[i] as Map, ss = '${e['superset_group'] ?? ''}'.isNotEmpty;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _edit ? () => _editSets(e) : null,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(color: ss ? AppColors.pbSsRow : null, border: const Border(top: BorderSide(color: AppColors.line))),
              foregroundDecoration: ss ? const BoxDecoration(border: Border(left: BorderSide(color: AppColors.pbSsBar, width: 3))) : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                  SizedBox(width: 34, child: Align(alignment: Alignment.topLeft, child: _tag(tags[i], ss))),
                  Expanded(child: _exName(e)),
                  _rowMenu(xs, i),
                ]),
                Padding(
                  padding: const EdgeInsets.only(left: 40),
                  child: Row(spacing: 6, children: [
                    Expanded(flex: 8, child: chip('Sets', '${e['sets']}', ss)),
                    Expanded(flex: 13, child: chip('Reps', '${e['reps']}', ss)),
                    Expanded(flex: 8, child: chip('RPE', e['rpe'] == null || e['rpe'] == 0 ? '–' : '${e['rpe']}', ss)),
                    Expanded(flex: 10, child: chip('Tempo', '${e['tempo'] ?? ''}'.isEmpty ? '–' : '${e['tempo']}', ss)),
                    Expanded(flex: 12, child: chip('Rest', restShort(e['rest_seconds']), ss)),
                  ]),
                ),
              ]),
            ),
          );
        }(),
    ]);
  }

  Widget _restBlock(bool phone) => Padding(
        padding: EdgeInsets.symmetric(horizontal: phone ? 14 : 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.pbRestBg, borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: AppColors.line2)),
          child: Wrap(spacing: 14, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const AppIcon(AppIcons.moon, size: 22, color: AppColors.muted),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: phone ? 260 : 520),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text('Rest day', style: AppText.s(14, W.w7)),
                Text('Clients see no workout on this day. Use the note below for steps, mobility or a check-in reminder.', style: AppText.s(13, W.w5, color: AppColors.muted)),
              ]),
            ),
            if (_edit) AppButton('Make workout day', icon: AppIcons.dumbbell, onPressed: _toggleRest),
          ]),
        ),
      );

  Widget _noteBox(bool phone, bool rest) => Container(
        padding: phone ? const EdgeInsets.fromLTRB(14, 12, 14, 14) : const EdgeInsets.fromLTRB(20, 14, 20, 18),
        decoration: rest ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
          Text('Coach note for the client', style: AppText.label),
          AppTextField(
            controller: _note,
            enabled: _edit,
            maxLines: 4,
            minLines: 2,
            placeholder: rest ? 'e.g. 8k steps and 10 minutes of mobility' : 'e.g. Slow on the way down, pause at the bottom',
            onChanged: _typed,
          ),
          Text('Saved as you type. Clients see it on this day.', style: AppText.cap),
        ]),
      );
}
