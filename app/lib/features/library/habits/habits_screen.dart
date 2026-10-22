import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../app/services.dart';
import '../../../app/shell/page.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/leave/leave_guard.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tabs.dart';
import '../lib_common.dart';
import '../programs/builder_sheets.dart' show showNameModal;
import 'habit_editor.dart';
import 'hb_common.dart';
import 'supp_editor.dart';

/// The page's data: both lists, the picked habit / plan with its unsaved copy (draft), who is on it, and what this
/// person may do (`habits/counts/` → `can`, D-39). Editors in the page and in the phone sheet both listen to it.
class HbCtl extends ChangeNotifier {
  HbCtl(this.tab);
  String tab; // 'h' habits, 's' supplements
  List<Map> habits = [], plans = [], quick = [];
  Map counts = const {};
  bool loading = true;
  ApiError? error;
  String q = '';
  bool saving = false;

  String? hid, sid;
  Map? hSaved, hd, sSaved, sd;
  int hRev = 0, sRev = 0; // bumped when the draft is replaced, so text fields start again
  List<Map>? hClients, sClients;
  Map<String, String> hErr = {}, sErr = {};

  Map get _can => (counts['can'] as Map?) ?? const {};
  /// "Edit gym templates": may change every habit and plan.
  bool get canEdit => _can['edit'] == true;

  /// New habit / New plan and Duplicate (D-45).
  bool get canNewH => _can['create_habits'] == true || canEdit;
  bool get canNewS => _can['create_supplements'] == true || canEdit;

  /// The open habit / plan: everything with "Edit gym templates", else only what this person made.
  bool _mine(Map? x) => x != null && '${x['created_by'] ?? ''}' == Services.session.me?.id;
  bool get canEditH => canEdit || (canNewH && _mine(hSaved));
  bool get canEditS => canEdit || (canNewS && _mine(sSaved));
  bool get canAssignH => _can['assign_habits'] == true;
  bool get canAssignS => _can['assign_supplements'] == true;

  static const _hKeys = ['name', 'kind', 'target', 'unit', 'frequency', 'days', 'times_per_week', 'icon', 'why'];
  static String _hSig(Map h) => jsonEncode([for (final k in _hKeys) h[k]]);
  static String _sSig(Map p) => jsonEncode([
        p['note'] ?? '',
        for (final i in (p['items'] as List? ?? const [])) [for (final k in ['id', 'name', 'dose', 'timing', 'days', 'with_food']) (i as Map)[k]],
      ]);
  static Map copy(Map m) => jsonDecode(jsonEncode(m)) as Map;

  bool get hDirty => hd != null && hSaved != null && _hSig(hd!) != _hSig(hSaved!);
  bool get sDirty => sd != null && sSaved != null && _sSig(sd!) != _sSig(sSaved!);

  void changed() => notifyListeners();

  Future<void> load() async {
    try {
      final r = await Future.wait([
        Services.api.get<List>('habits/'),
        Services.api.get<List>('supplement-plans/'),
        Services.api.get<Map>('habits/counts/'),
      ]);
      habits = [for (final x in r[0] as List) x as Map];
      plans = [for (final x in r[1] as List) x as Map];
      counts = r[2] as Map;
      error = null;
      if (hid == null || !habits.any((h) => '${h['id']}' == hid)) pickHabit(habits.isEmpty ? null : '${habits.first['id']}', notify: false);
      if (sid == null || !plans.any((p) => '${p['id']}' == sid)) pickPlan(plans.isEmpty ? null : '${plans.first['id']}', notify: false);
    } on ApiError catch (e) {
      error = e;
    }
    loading = false;
    notifyListeners();
    if (canNewS && quick.isEmpty) {
      try {
        quick = [for (final x in await Services.api.get<List>('supplement-plans/quick-add/')) x as Map];
        notifyListeners();
      } on ApiError catch (_) {}
    }
  }

  // ─────────────────────────────── habits

  void pickHabit(String? id, {bool notify = true}) {
    hid = id;
    final h = habits.where((x) => '${x['id']}' == id).firstOrNull;
    hSaved = h == null ? null : copy(h);
    hd = h == null ? null : copy(h);
    hRev++;
    hErr = {};
    hClients = null;
    if (h != null) _loadClients(true);
    if (notify) notifyListeners();
  }

  Future<void> _loadClients(bool habit) async {
    final id = habit ? hid : sid;
    try {
      final l = await hbClientsOn(habit ? 'habits/$id/' : 'supplement-plans/$id/');
      if ((habit ? hid : sid) != id) return;
      habit ? hClients = l : sClients = l;
      notifyListeners();
    } on ApiError catch (_) {
      habit ? hClients = const [] : sClients = const [];
      notifyListeners();
    }
  }

  void setH(void Function(Map d) f) {
    f(hd!);
    hErr = {};
    notifyListeners();
  }

  void discardH() {
    hd = copy(hSaved!);
    hRev++;
    hErr = {};
    notifyListeners();
  }

  Map? get pickedHabit => hd;

  /// The row shows the habit as it is being edited.
  Map habitRow(Map h) => '${h['id']}' == hid && hd != null ? hd! : h;

  Future<void> saveH(BuildContext context) async {
    final d = hd!;
    final name = '${d['name'] ?? ''}'.trim();
    if (name.length < 2) {
      hErr = {'name': 'Enter the habit name.'};
      notifyListeners();
      return;
    }
    if (d['kind'] == 'counter' && '${d['unit'] ?? ''}'.trim().isEmpty) {
      hErr = {'unit': 'Enter a unit, like glasses.'};
      notifyListeners();
      return;
    }
    saving = true;
    notifyListeners();
    try {
      final r = await Services.api.patch<Map>('habits/$hid/', {for (final k in _hKeys) k: d[k], 'name': name, 'unit': '${d['unit'] ?? ''}'.trim()});
      final i = habits.indexWhere((x) => '${x['id']}' == hid);
      if (i >= 0) habits[i] = r;
      hSaved = copy(r);
      hd = copy(r);
      hRev++;
      final n = (r['client_count'] as num?)?.toInt() ?? 0;
      if (context.mounted) showToast(context, 'Changes saved', sub: n == 0 ? 'Not assigned to anyone yet' : 'Sent to ${plural(n, 'client')} on this habit');
    } on ApiError catch (e) {
      hErr = {for (final k in e.fields.keys) k: e.fields[k]!.first};
      if (context.mounted && hErr.isEmpty) showToast(context, 'Could not save it', sub: e.message, kind: ToastKind.err);
    }
    saving = false;
    notifyListeners();
  }

  // ─────────────────────────────── supplement plans

  void pickPlan(String? id, {bool notify = true}) {
    sid = id;
    final p = plans.where((x) => '${x['id']}' == id).firstOrNull;
    sSaved = p == null ? null : copy(p);
    sd = p == null ? null : copy(p);
    sRev++;
    sErr = {};
    sClients = null;
    if (p != null) _loadClients(false);
    if (notify) notifyListeners();
  }

  void setS(void Function(Map d) f) {
    f(sd!);
    notifyListeners();
  }

  void discardS() {
    sd = copy(sSaved!);
    sRev++;
    notifyListeners();
  }

  List<Map> get items => [for (final x in (sd?['items'] as List? ?? const [])) x as Map];

  Future<void> saveS(BuildContext context) async {
    saving = true;
    notifyListeners();
    try {
      final r = await Services.api.patch<Map>('supplement-plans/$sid/', {
        'note': '${sd!['note'] ?? ''}'.trim(),
        'items': [for (final i in items) {for (final k in ['id', 'name', 'dose', 'how', 'timing', 'days', 'with_food']) if (i[k] != null) k: i[k]}],
      });
      _putPlan(r);
      sSaved = copy(r);
      sd = copy(r);
      sRev++;
      final n = (r['client_count'] as num?)?.toInt() ?? 0;
      if (context.mounted) showToast(context, 'Changes saved', sub: n == 0 ? 'Not assigned to anyone yet' : 'Sent to ${plural(n, 'client')} on this plan');
    } on ApiError catch (e) {
      if (context.mounted) showToast(context, 'Could not save it', sub: e.message, kind: ToastKind.err);
    }
    saving = false;
    notifyListeners();
  }

  void _putPlan(Map r) {
    final i = plans.indexWhere((x) => '${x['id']}' == '${r['id']}');
    if (i >= 0) plans[i] = r;
  }

  /// A rename saves at once; an unsaved draft keeps its items and note.
  void renamed(Map r) {
    _putPlan(r);
    sSaved!['name'] = r['name'];
    sd!['name'] = r['name'];
    notifyListeners();
  }

  void clientsChanged(bool habit, List<Map> l) {
    final list = habit ? habits : plans;
    final id = habit ? hid : sid;
    for (final x in list) {
      if ('${x['id']}' == id) x['client_count'] = l.length;
    }
    for (final m in habit ? [hSaved, hd] : [sSaved, sd]) {
      m?['client_count'] = l.length;
    }
    habit ? hClients = l : sClients = l;
    notifyListeners();
  }
}

/// Habits & supplements (boards `Habits` / `HabitsMobile`). Habits: list, editor with Save / Discard, client
/// preview, Assigned to. Supplements: plans, items with dose and timing, quick add, what the client sees.
/// Phone (and a narrow page): the list, and a tap opens the editor in a sheet.
class HabitsScreen extends StatefulWidget {
  const HabitsScreen({super.key, this.tab});
  final String? tab;
  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen> {
  late final c = HbCtl(widget.tab == 'supplements' ? 's' : 'h');
  bool _sheetOpen = false;
  BuildContext? _sheetCtx;

  void _closeSheet() {
    final x = _sheetCtx;
    if (_sheetOpen && x != null && x.mounted) Navigator.of(x).pop();
  }

  @override
  void initState() {
    super.initState();
    LeaveGuard.register(this, _askLeave);
    c.addListener(_onChange);
    c.load();
  }

  void _onChange() {
    LeaveGuard.unsaved(c.hDirty || c.sDirty);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    LeaveGuard.unregister(this);
    c.removeListener(_onChange);
    c.dispose();
    super.dispose();
  }

  bool get _isH => c.tab == 'h';

  Future<bool> _askDiscard(BuildContext context) async {
    if (!c.hDirty && !c.sDirty) return true;
    final name = c.hDirty ? '${c.hd!['name']}' : '${c.sd!['name']}';
    final ok = await confirmAction(context,
        title: 'Leave without saving?', body: 'Your changes to $name are not saved.', confirm: 'Discard', danger: true, icon: AppIcons.alert);
    if (ok) {
      if (c.hDirty) c.discardH();
      if (c.sDirty) c.discardS();
    }
    return ok;
  }

  Future<bool> _askLeave(BuildContext context) => _askDiscard(context);

  Future<void> _pickTab(String t) async {
    if (t == c.tab) return;
    if (!await _askDiscard(context)) return;
    c.tab = t;
    c.q = '';
    c.changed();
  }

  bool _narrow = false;

  Future<void> _pick(String id) async {
    final same = _isH ? id == c.hid : id == c.sid;
    if (!same) {
      if (!await _askDiscard(context)) return;
      _isH ? c.pickHabit(id) : c.pickPlan(id);
    }
    if (_narrow && mounted) _openSheet();
  }

  /// Phone / narrow page: the editor, preview and Assigned to in a tall sheet (a drawer on a narrow page).
  Future<void> _openSheet() async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    final habit = _isH;
    while (true) {
      if (!mounted) break;
      await showAppDrawer(
        context,
        title: habit ? 'Edit habit' : 'Edit supplement plan',
        icon: habit ? AppIcons.checkCircle : AppIcons.pill,
        builder: (ctx) {
          _sheetCtx = ctx;
          return ListenableBuilder(
          listenable: c,
          builder: (ctx, _) => Padding(
            padding: EdgeInsets.only(top: ctx.isPhone ? 0 : 16, bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: habit ? _habitParts(ctx) : _planParts(ctx)),
          ),
        );
        },
      );
      if (!mounted || !(habit ? c.hDirty : c.sDirty)) break;
      if (await _askDiscard(context)) break;
    }
    _sheetOpen = false;
    _sheetCtx = null;
  }

  List<Widget> _habitParts(BuildContext ctx) => c.hd == null
      ? const []
      : [
          HabitEditorCard(key: ValueKey('h${c.hid}-${c.hRev}'), c: c, onMenu: _habitMenu),
          HabitPreviewCard(key: ValueKey('p${c.hid}'), c: c),
          HbAssignedCard(clients: c.hClients, sub: 'Sees it on Today', empty: 'Not assigned yet. Assign it to clients to show it on their Today screen.', onAssign: c.canAssignH ? _assign : null),
        ];

  List<Widget> _planParts(BuildContext ctx) => c.sd == null
      ? const []
      : [
          SuppEditorCard(key: ValueKey('s${c.sid}-${c.sRev}'), c: c, onMenu: _planMenu, onAssign: c.canAssignS ? _assign : null),
          SuppPreviewCard(c: c),
          HbAssignedCard(clients: c.sClients, sub: 'Sees it in the app', empty: 'Not assigned yet. Assign the plan to show it in the client app.', onAssign: c.canAssignS ? _assign : null),
        ];

  // ─────────────────────────────── actions

  Future<void> _assign() async {
    final habit = _isH;
    final url = habit ? 'habits/${c.hid}/' : 'supplement-plans/${c.sid}/';
    final name = habit ? '${c.hSaved!['name']}' : '${c.sSaved!['name']}';
    final r = await showHbAssign(context, url: url, name: name, done: habit ? 'Habit assigned' : 'Plan assigned');
    if (r != null) c.clientsChanged(habit, r);
  }

  Future<void> _run(Future<void> Function() f, String fail) async {
    try {
      await f();
    } on ApiError catch (e) {
      if (mounted) showToast(context, fail, sub: e.message, kind: ToastKind.err);
    }
  }

  void _habitMenu(BuildContext anchor) => showAppMenu(anchor, width: 210, [
        if (c.canNewH) MenuEntry('Duplicate habit', icon: AppIcons.copy, sub: c.canEditH ? null : 'Make your own copy', onTap: _dupHabit),
        if (c.canEditH) ...[
          const MenuEntry.separator(),
          MenuEntry('Delete habit', icon: AppIcons.trash, danger: true, onTap: _delHabit),
        ],
      ]);

  Future<void> _dupHabit() async {
    if (!await _askDiscard(context)) return;
    await _run(() async {
      final r = await Services.api.post<Map>('habits/${c.hid}/duplicate/');
      await c.load();
      c.pickHabit('${r['id']}');
      if (mounted) {
        showToast(context, 'Habit duplicated', sub: 'Same settings, no clients', action: 'Undo', onAction: () => _run(() async {
              await Services.api.delete('habits/${r['id']}/');
              await c.load();
            }, 'Could not undo it'));
      }
    }, 'Could not duplicate it');
  }

  Future<void> _delHabit() async {
    final h = c.hSaved!;
    final n = (h['client_count'] as num?)?.toInt() ?? 0;
    final ok = await confirmAction(context,
        title: 'Delete this habit?',
        body: '${h['name']} is removed${n > 0 ? ' from ${plural(n, 'client')}' : ''}. Their past logs stay.',
        confirm: 'Delete',
        danger: true,
        icon: AppIcons.trash);
    if (!ok || !mounted) return;
    await _run(() async {
      await Services.api.delete('habits/${h['id']}/');
      c.hd = null;
      _closeSheet();
      await c.load();
      if (mounted) {
        showToast(context, 'Habit deleted', sub: '${h['name']}', action: 'Undo', onAction: () => _run(() async {
              await Services.api.post('habits/${h['id']}/restore/');
              await c.load();
              c.pickHabit('${h['id']}');
            }, 'Could not undo it'));
      }
    }, 'Could not delete it');
  }

  void _planMenu(BuildContext anchor) => showAppMenu(anchor, width: 230, [
        if (c.canEditS) MenuEntry('Rename plan', icon: AppIcons.edit, onTap: _renamePlan),
        if (c.canNewS) MenuEntry('Duplicate plan', icon: AppIcons.copy, sub: 'Same items, no clients', onTap: _dupPlan),
        if (c.canEditS) ...[
          const MenuEntry.separator(),
          MenuEntry('Delete plan', icon: AppIcons.trash, danger: true, onTap: _delPlan),
        ],
      ]);

  Future<void> _renamePlan() async {
    final v = await showNameModal(context,
        title: 'Rename plan', sub: 'Clients see the new name', label: 'Plan name', initial: '${c.sSaved!['name']}', button: 'Save name');
    if (v == null || !mounted || v == c.sSaved!['name']) return;
    await _run(() async {
      c.renamed(await Services.api.patch<Map>('supplement-plans/${c.sid}/', {'name': v}));
      if (mounted) showToast(context, 'Plan renamed', sub: v);
    }, 'Could not rename it');
  }

  Future<void> _dupPlan() async {
    if (!await _askDiscard(context)) return;
    await _run(() async {
      final r = await Services.api.post<Map>('supplement-plans/${c.sid}/duplicate/');
      await c.load();
      c.pickPlan('${r['id']}');
      if (mounted) {
        showToast(context, 'Plan duplicated', sub: 'Same items, no clients', action: 'Undo', onAction: () => _run(() async {
              await Services.api.delete('supplement-plans/${r['id']}/');
              await c.load();
            }, 'Could not undo it'));
      }
    }, 'Could not duplicate it');
  }

  Future<void> _delPlan() async {
    final p = c.sSaved!;
    final n = (p['client_count'] as num?)?.toInt() ?? 0;
    final ok = await confirmAction(context,
        title: 'Delete supplement plan?',
        body: '${p['name']} is removed${n > 0 ? ' from ${plural(n, 'client')}' : ''}.',
        confirm: 'Delete',
        danger: true,
        icon: AppIcons.trash);
    if (!ok || !mounted) return;
    await _run(() async {
      await Services.api.delete('supplement-plans/${p['id']}/');
      c.sd = null;
      _closeSheet();
      await c.load();
      if (mounted) {
        showToast(context, 'Plan deleted', sub: '${p['name']}', action: 'Undo', onAction: () => _run(() async {
              await Services.api.post('supplement-plans/${p['id']}/restore/');
              await c.load();
              c.pickPlan('${p['id']}');
            }, 'Could not undo it'));
      }
    }, 'Could not delete it');
  }

  Future<void> _newHabit() async {
    if (!await _askDiscard(context) || !mounted) return;
    final r = await showNewHabit(context);
    if (r == null || !mounted) return;
    await c.load();
    c.pickHabit('${r['id']}');
    if (mounted) showToast(context, 'Template created', sub: 'Set the target, days and icon');
    if (_narrow && mounted) _openSheet();
  }

  Future<void> _newPlan() async {
    if (!await _askDiscard(context) || !mounted) return;
    final v = await showNameModal(context,
        title: 'New supplement plan', sub: 'Add supplements with dose and timing next', label: 'Plan name', placeholder: 'e.g. Recovery stack', button: 'Create plan', icon: AppIcons.pill);
    if (v == null || !mounted) return;
    await _run(() async {
      final r = await Services.api.post<Map>('supplement-plans/', {'name': v, 'items': []});
      await c.load();
      c.tab = 's';
      c.pickPlan('${r['id']}');
      if (mounted) showToast(context, 'Plan created', sub: 'Use quick add to fill it');
      if (_narrow && mounted) _openSheet();
    }, 'Could not create it');
  }

  // ─────────────────────────────── build

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final label = _isH ? 'New habit' : 'New plan';
    final onNew = _isH ? _newHabit : _newPlan;
    return StaffPage(
      onRefresh: c.load,
      header: PageTop(
        title: 'Habits & supplements',
        sub: _isH
            ? 'Build a habit once and assign it to many clients. Saved changes reach everyone on it.'
            : 'Supplement plans with dose and timing. Save to send changes to every client on the plan.',
        actions: [
          if (_isH ? c.canNewH : c.canNewS) phone ? LibPlusButton(label: label, onTap: onNew) : AppButton.primary(label, icon: AppIcons.plus, onPressed: onNew),
        ],
      ),
      children: [
        Transform.translate(
          offset: const Offset(0, -6),
          child: UnderlineTabs<String>(
            pillCounts: true,
            gap: 24,
            items: [
              TabItem('h', 'Habits', count: c.loading ? null : c.habits.length),
              TabItem('s', 'Supplements', count: c.loading ? null : c.plans.length),
            ],
            value: c.tab,
            onChanged: _pickTab,
          ),
        ),
        if (c.loading)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)))
        else if (c.error != null)
          AppCard(child: EmptyState('Could not load this page', sub: c.error!.message, action: AppButton('Try again', onPressed: c.load)))
        else
          LayoutBuilder(builder: (context, b) {
            final w = b.maxWidth;
            _narrow = phone || w < 640;
            final list = _list(phone);
            final empty = _isH ? c.habits.isEmpty : c.plans.isEmpty;
            if (_narrow || empty) return list;
            final parts = _isH ? _habitParts(context) : _planParts(context);
            if (parts.isEmpty) return list;
            if (w >= 1100) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
                SizedBox(width: 300, child: list),
                Expanded(child: parts[0]),
                SizedBox(width: 300, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: parts.sublist(1))),
              ]);
            }
            final lw = w >= 860 ? 280.0 : 240.0;
            final side = w - lw - 16 >= 600
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 14, children: [Expanded(child: parts[1]), Expanded(child: parts[2])])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: parts.sublist(1));
            return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
              SizedBox(width: lw, child: list),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [parts[0], side])),
            ]);
          }),
      ],
    );
  }

  Widget _list(bool phone) {
    if (_isH && c.habits.isEmpty || !_isH && c.plans.isEmpty) {
      return AppCard(
        child: EmptyState(_isH ? 'No habits yet' : 'No supplement plans yet',
            icon: _isH ? AppIcons.checkCircle : AppIcons.pill,
            sub: _isH ? 'Make a habit once and assign it to many clients.' : 'Make a plan with dose and timing, then assign it.',
            action: (_isH ? c.canNewH : c.canNewS) ? AppButton.primary(_isH ? 'New habit' : 'New plan', icon: AppIcons.plus, onPressed: _isH ? _newHabit : _newPlan) : null),
      );
    }
    final rows = <Widget>[];
    if (_isH) {
      final q = c.q.toLowerCase();
      for (final h in c.habits.where((h) => q.isEmpty || '${h['name']}'.toLowerCase().contains(q))) {
        final x = c.habitRow(h);
        rows.add(HbListRow(
          icon: habitIcon('${x['icon']}'),
          tone: habitTone('${x['icon']}'),
          title: '${x['name']}',
          sub: '${kindLabel(x)} · ${freqLabel(x)}',
          count: (h['client_count'] as num?)?.toInt() ?? 0,
          on: !_narrow && '${h['id']}' == c.hid,
          onTap: () => _pick('${h['id']}'),
        ));
      }
    } else {
      for (final p in c.plans) {
        final n = '${p['id']}' == c.sid ? c.items.length : (p['items'] as List? ?? const []).length;
        rows.add(HbListRow(
          icon: AppIcons.pill,
          tone: AppColors.hbTones[suppTone],
          title: '${p['name']}',
          sub: plural(n, 'supplement'),
          count: (p['client_count'] as num?)?.toInt() ?? 0,
          on: !_narrow && '${p['id']}' == c.sid,
          onTap: () => _pick('${p['id']}'),
        ));
      }
    }
    return AppCard(
      padding: const EdgeInsets.all(6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 2, children: [
        if (_isH)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
            child: AppSearchField(placeholder: 'Search habits', icon: AppIcons.search, onChanged: (v) {
              c.q = v.trim();
              c.changed();
            }),
          ),
        if (rows.isEmpty)
          Padding(padding: const EdgeInsets.all(16), child: Text('No habit matches.', textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)))
        else
          ...rows,
      ]),
    );
  }
}
