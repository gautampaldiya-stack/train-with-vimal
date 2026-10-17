import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tabs.dart';
import '../../../core/widgets/tooltip.dart';
import 'cp_common.dart';
import 'cp_model.dart';
import 'cp_plans_assign.dart';
import 'cp_plans_edit.dart';
import 'cp_plans_meal_edit.dart';
import 'cp_plans_model.dart';
import 'cp_plans_parts.dart';
import 'cp_plans_supp_edit.dart';

export 'cp_plans_assign.dart' show showAssignPlan;

/// Client profile → Plans tab (boards `TrainerClientProfile` / `…Mobile`, `show.plans`): segment tabs Workout ·
/// Meal plan · Supplements · Habits, `Assign new plan`, the current plan card (badges, info line, `Edit for X`,
/// ⋯ menu), the slot's days / meals / items, Up next and Plan history. `Edit for X` and `Duplicate and edit` open
/// the plan editor in place of the tab (workout, meal plan) or the habits drawer.
class CpPlansTab extends StatefulWidget {
  const CpPlansTab(this.c, {super.key});
  final CpController c;
  @override
  State<CpPlansTab> createState() => _CpPlansTabState();
}

const _slots = [('workout', 'Workout'), ('meal', 'Meal plan'), ('supplements', 'Supplements'), ('habits', 'Habits')];

class _CpPlansTabState extends State<CpPlansTab> {
  CpController get c => widget.c;
  late final d = PlansData(c);
  late int _version = c.version;
  int? _wday, _mday; // picked day in the workout / meal strips (0 = Mon)

  /// Workout editor open: null = no, false = `Edit X for Y`, true = `New plan for Y: copy of X`.
  bool? _edit;

  /// Meal plan editor open (`Edit for X`: the client's own copy, one weekday at a time).
  bool _mealEdit = false;

  /// Supplements editor open for this assignment row (`Edit for X`: the client's own copy).
  Map? _suppEdit;

  @override
  void initState() {
    super.initState();
    d.load();
    c.addListener(_onC);
    PlanEvents.instance.addListener(_onEvent);
  }

  void _onC() {
    if (c.version != _version) {
      _version = c.version;
      d.load();
    }
    if (mounted) setState(() {});
  }

  /// The assign drawer (opened from the header too) asks the tab to reload or to open the editor.
  void _onEvent() {
    final e = PlanEvents.instance.last;
    if (e == null || e.client != c.id || !mounted) return;
    if (e.kind == 'edit' || e.kind == 'dup') {
      setState(() => _edit = e.kind == 'dup');
      if (c.tab != 'plans' || c.planSlot != 'workout') c.setTab('plans', plan: 'workout');
    }
  }

  @override
  void dispose() {
    c.removeListener(_onC);
    PlanEvents.instance.removeListener(_onEvent);
    d.dispose();
    super.dispose();
  }

  String get slot => c.planSlot;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: d,
        builder: (context, _) {
          if (d.loading && d.programs.isEmpty) return const CpLoading();
          if (d.error != null && d.programs.isEmpty) return CpError(d.error!.message, onRetry: d.load);
          if (_edit != null && d.workout != null) {
            return WorkoutEditor(
              key: ValueKey('${d.workout!['id']}$_edit'),
              d: d,
              dup: _edit!,
              startDay: _wday,
              onClose: () => setState(() => _edit = null),
            );
          }
          if (_mealEdit && d.meal != null && d.mealPlan != null) {
            return MealEditor(
              key: ValueKey('meal${d.meal!['id']}'),
              d: d,
              startDay: _mday,
              onClose: (day) => setState(() {
                _mealEdit = false;
                if (day != null) _mday = day;
              }),
            );
          }
          if (_suppEdit != null) {
            return SupplementEditor(
              key: ValueKey('supp${_suppEdit!['id']}'),
              c: c,
              a: _suppEdit!,
              onClose: (saved) {
                setState(() => _suppEdit = null);
                if (saved) d.reload();
              },
            );
          }
          final phone = context.isPhone;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 14 : 16, children: [
            _subbar(phone),
            KeyedSubtree(key: ValueKey(slot), child: _slot()),
          ]);
        },
      );

  Widget _subbar(bool phone) {
    final tabs = SegmentedTabs<String>(
      items: [for (final (k, l) in _slots) TabItem(k, l)],
      value: slot,
      onChanged: (v) => c.setTab('plans', plan: v),
    );
    final btn = Align(
      alignment: Alignment.centerLeft,
      child: AppButton('Assign new plan', icon: AppIcons.plus, onPressed: () => showAssignPlan(context, c, slot)),
    );
    if (phone) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: tabs),
        btn,
      ]);
    }
    return Row(spacing: 12, children: [
      Expanded(child: Align(alignment: Alignment.centerLeft, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: tabs))),
      btn.child!,
    ]);
  }

  Widget _slot() => switch (slot) {
        'meal' => _meal(),
        'supplements' => _supps(),
        'habits' => _habits(),
        _ => _workout(),
      };

  Widget _cols(List<Widget> main, List<Widget> side) => CpColumns(left: main, right: side, leftFlex: 7, rightFlex: 5);

  // ─────────────────────────────── shared pieces

  /// `.card-h` of a plan: title + `Current` + `Edited for X` + (i), the grey info line, `Edit for X` and ⋯.
  Widget _planHead({required String title, required String info, required bool edited, required String tip, VoidCallback? onEdit, required List<MenuEntry> menu}) {
    final phone = context.isPhone;
    final titleRow = Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text(title, style: AppText.h3),
      const AppBadge('Current', tone: Tone.ok),
      if (edited) AppBadge('Edited for ${c.first}', tone: Tone.info, plain: true),
      CpInfo(tip),
    ]);
    final more = Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'More actions', onPressed: () => showAppMenu(b, menu, width: 230)));
    final edit = onEdit == null ? null : AppButton('Edit for ${c.first}', icon: AppIcons.edit, expand: phone, onPressed: onEdit);
    final texts = Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [titleRow, Text(info, style: AppText.cap)]);
    if (phone) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
          texts,
          Row(spacing: 8, children: [if (edit != null) Expanded(child: edit) else const Spacer(), more]),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [Expanded(child: texts), ?edit, more]),
    );
  }

  List<MenuEntry> _menu({VoidCallback? dup, VoidCallback? reset, required VoidCallback openMaster, required VoidCallback end}) => [
        if (dup != null) MenuEntry('Duplicate and edit', icon: AppIcons.copy, onTap: dup),
        MenuEntry('Replace with another plan', icon: AppIcons.swap, onTap: () => showAssignPlan(context, c, slot, replace: true)),
        if (reset != null) MenuEntry('Reset to master', icon: AppIcons.reset, onTap: reset),
        MenuEntry('Open master plan', icon: AppIcons.external, onTap: openMaster),
        MenuEntry('End this plan', icon: AppIcons.stop, danger: true, onTap: end),
      ];

  Widget _noPlan(String title, String sub, String btn) => AppCard(
        child: EmptyState(title, sub: sub, action: AppButton.primary(btn, icon: AppIcons.plus, onPressed: () => showAssignPlan(context, c, slot))),
      );

  /// Up next card: the next plan (`Change`) or `No next … yet` + `Choose next plan`.
  Widget _upNext({Map? next, required String name, required String sub, required String empty}) => CpCard(
        title: 'Up next',
        padding: EdgeInsets.fromLTRB(next == null ? 16 : 8, 0, next == null ? 16 : 8, next == null ? 16 : 10),
        child: next == null
            ? Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 10, children: [
                Text(empty, style: AppText.s(13, W.w5, color: AppColors.muted)),
                AppButton('Choose next plan', icon: AppIcons.plus, size: BtnSize.sm, onPressed: () => showAssignPlan(context, c, slot, next: true)),
              ])
            : AppRow(
                leading: cpIcon(AppIcons.calendar, bg: AppColors.infoBg, fg: AppColors.infoText),
                title: name,
                sub: sub,
                trailing: AppButton('Change', size: BtnSize.sm, onPressed: () => showAssignPlan(context, c, slot, next: true)),
              ),
      );

  /// Plan history: newest first, the current one on top; 5 rows then `Show all`.
  Widget _history(List<(String, String, String)> rows) => _HistoryCard(rows: rows);

  Future<void> _post(String path, {Map<String, dynamic> body = const {}, required String ok, String? sub, String? action, VoidCallback? onAction}) async {
    try {
      await Services.api.post(path, body);
      if (!mounted) return;
      showToast(context, ok, sub: sub, kind: ToastKind.ok, action: action, onAction: onAction);
      d.reload();
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not save that', sub: e.message, kind: ToastKind.info);
    }
  }

  Future<void> _confirmEnd(String name, String path, {String? body}) async {
    final ok = await confirmAction(context,
        title: 'End $name?',
        body: body ?? '${c.first} stops getting it from tomorrow. It moves to Plan history and the logs stay.',
        confirm: 'End plan',
        danger: true,
        icon: AppIcons.stop);
    if (ok) await _post(path, ok: 'Plan ended', sub: '$name moved to Plan history');
  }

  void _openMaster(String route) => context.go(route);

  // ─────────────────────────────── Workout

  Widget _workout() {
    final w = d.workout;
    final next = d.workoutNext;
    final hist = [...PlansData.rows(d.programs, 'current'), ...PlansData.rows(d.programs, 'history')];
    final side = [
      _upNext(
        next: next,
        name: '${next?['program_name'] ?? ''}',
        sub: next == null
            ? ''
            : ['Starts ${cpDay(next['start_date'])}', '${next['weeks']} weeks', if (next['assigned_by'] != null) 'set by ${next['assigned_by']}'].join(' · '),
        empty: w == null ? 'No workout plan is set to start.' : 'No next workout plan yet. ${c.first} stays on this one until it ends.',
      ),
      if (hist.isNotEmpty) _history([for (final a in hist) _wHistRow(a, hist)]),
    ];
    if (w == null) {
      return _cols([_noPlan('No workout plan yet', 'Pick a program from the library. ${c.first} gets ${pronoun(c)} own copy.', 'Assign a workout plan')], side);
    }
    final week = planWeek(w);
    final diff = WorkoutDiff(d.wTree, d.wMaster);
    final end = planEnd(w);
    final info = [
      'From master "${w['master_name']}"',
      '${cpDm(w['start_date'])} – ${cpDm(end?.toIso8601String())}',
      'week $week of ${w['weeks']}',
      '${w['days_per_week']} workouts a week',
    ].join(' · ');
    final wk = weekOf(d.wTree, week);
    final today = DateTime.now().weekday - 1;
    final sel = _wday ?? today;
    final day = dayOf(wk, sel);
    final rest = isRest(day);
    final ex = exercisesOf(day);
    final tags = tagsOf(ex);
    final sets = ex.fold<int>(0, (a, e) => a + ((e['sets'] as num?) ?? 0).toInt());
    final note = '${day?['rest_note'] ?? ''}'.trim();
    final edited = diff.day(week, sel);

    final card = AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _planHead(
          title: '${w['program_name']}',
          info: info,
          edited: w['custom'] == true,
          tip: 'Changes here apply only to ${c.first}. The master program in the library stays the same.',
          onEdit: () => setState(() => _edit = false),
          menu: _menu(
            dup: () => setState(() => _edit = true),
            reset: w['custom'] == true ? () => _resetWorkout(w) : null,
            openMaster: () => _openMaster('/programs/${w['program']}'),
            end: () => _confirmEnd('${w['program_name']}', 'clients/${c.id}/programs/${w['id']}/end/'),
          ),
        ),
        DayStrip(
          days: [
            for (var i = 0; i < 7; i++)
              (weekdayShort[i], isRest(dayOf(wk, i)) ? (('${dayOf(wk, i)?['name'] ?? ''}').isEmpty ? 'Rest' : '${dayOf(wk, i)!['name']}') : '${dayOf(wk, i)?['name'] ?? ''}'.ifEmpty('Workout'), diff.day(week, i), isRest(dayOf(wk, i))),
          ],
          selected: sel,
          onPick: (i) => setState(() => _wday = i),
        ),
        PdHead(
          title: '${weekdayFull[sel]} · ${rest ? 'Rest' : '${day?['name'] ?? ''}'.ifEmpty('Workout')}',
          sub: rest ? 'Rest day' : '${ex.length} exercises · $sets sets · ~${dayMinutes(day)} min · tap an exercise to see it',
          badge: edited ? 'Edited for ${c.first}' : null,
        ),
        if (!rest && note.isNotEmpty) DayNote(note),
        if (rest) PdEmpty(note.isEmpty ? 'Rest day. ${c.first} has nothing to log.' : 'Rest day. ${c.first} sees: $note'),
        if (!rest)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
            child: Column(children: [
              for (final (i, e) in ex.indexed)
                ExerciseRow(
                  e: e,
                  tag: tags[i],
                  tone: i,
                  changed: diff.exercise(week, sel, i, e) != null ? 'Changed for ${c.first}' : null,
                  onTap: () => showExerciseDrawer(context,
                      c: c,
                      list: ex,
                      start: i,
                      dayLabel: '${weekdayFull[sel]} · ${day?['name'] ?? ''}',
                      dayNote: note,
                      program: '${w['program_name']}',
                      was: (j) => diff.exercise(week, sel, j, ex[j]),
                      onEdit: () => setState(() {
                            _wday = sel;
                            _edit = false;
                          })),
                ),
            ]),
          ),
      ]),
    );
    return _cols([card], side);
  }

  (String, String, String) _wHistRow(Map a, List<Map> all) {
    final s = cpParse(a['start_date']), e = planEnd(a);
    final status = '${a['status']}';
    String badge;
    if (status == 'active') {
      badge = 'Current';
    } else {
      final full = s != null && e != null && cpParse(a['end_date']) != null && !cpParse(a['end_date'])!.isBefore(s.add(Duration(days: ((a['weeks'] as num?) ?? 1).toInt() * 7 - 1)));
      final replaced = all.any((o) => o != a && cpParse(o['start_date']) != null && e != null && (cpParse(o['start_date'])!.difference(e).inDays).abs() <= 1);
      badge = full ? 'Completed' : (replaced ? 'Replaced' : 'Ended');
    }
    return ('${a['program_name']}', '${cpDm(a['start_date'])} – ${status == 'active' ? cpDm(e?.toIso8601String()) : cpDm(a['end_date'])}', badge);
  }

  Future<void> _resetWorkout(Map w) async {
    final ok = await confirmAction(context,
        title: 'Reset to master?',
        body: 'Every change made for ${c.first} in ${w['program_name']} goes away. ${c.first} gets the master program "${w['master_name']}" again. Logged workouts stay.',
        confirm: 'Reset to master',
        danger: true,
        icon: AppIcons.reset);
    if (ok) await _post('clients/${c.id}/programs/${w['id']}/reset-to-master/', ok: '${c.first} follows the master again', sub: '${w['master_name']}');
  }

  // ─────────────────────────────── Meal plan

  Widget _meal() {
    final m = d.meal;
    final next = d.mealNext;
    final hist = [...PlansData.rows(d.meals, 'current'), ...PlansData.rows(d.meals, 'history')];
    final side = [
      _upNext(
        next: next,
        name: '${next?['plan_name'] ?? ''}',
        sub: next == null ? '' : ['Starts ${cpDay(next['start_date'])}', '${_kcal(next['kcal'])} kcal', if (next['assigned_by'] != null) 'set by ${next['assigned_by']}'].join(' · '),
        empty: 'No next meal plan yet. The current one keeps going.',
      ),
      if (hist.isNotEmpty)
        _history([
          for (final a in hist)
            ('${a['plan_name']}', '${cpDm(a['start_date'])} – ${a['status'] == 'active' ? 'now' : cpDm(a['end_date'])}', a['status'] == 'active' ? 'Current' : 'Completed'),
        ]),
    ];
    if (m == null) return _cols([_noPlan('No meal plan yet', 'Pick a meal plan from the library for ${c.first}.', 'Assign a meal plan')], side);
    final plan = d.mealPlan ?? const {};
    final own = ownMealDays(plan);
    final info = [
      '${m['diet_label']}',
      'since ${cpDm(m['start_date'])}',
      if (own.isNotEmpty) '${own.length} day${own.length == 1 ? '' : 's'} with ${own.length == 1 ? 'its' : 'their'} own meals',
    ].join(' · ');
    double kcalOn(int i) => mealsOnDay(plan, i).fold<double>(0, (a, x) => a + mealKcal(x));
    final today = DateTime.now().weekday - 1;
    final sel = _mday ?? today;
    final meals = mealsOnDay(plan, sel);
    final tot = meals.fold<(double, double)>((0, 0), (a, x) => (a.$1 + mealKcal(x), a.$2 + mealProtein(x)));
    final card = AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _planHead(
          title: '${m['plan_name']}',
          info: info,
          edited: m['custom'] == true,
          tip: 'Changes here apply only to ${c.first}. The master meal plan in the library stays the same.',
          onEdit: _openMealEditor,
          menu: _menu(
            reset: m['custom'] == true ? () => _resetMeal(m) : null,
            openMaster: () => _openMaster('/meal-plans/${m['plan']}'),
            end: () => _confirmEnd('${m['plan_name']}', 'clients/${c.id}/meal-plans/${m['id']}/end/',
                body: '${c.first} has no meal plan from tomorrow. It moves to Plan history and the logged meals stay.'),
          ),
        ),
        Macros([
          (_kcal(m['kcal']), 'kcal a day'),
          ('${m['protein_g']} g', 'Protein'),
          ('${m['carbs_g']} g', 'Carbs'),
          ('${m['fat_g']} g', 'Fat'),
        ]),
        DayStrip(
          days: [for (var i = 0; i < 7; i++) (weekdayShort[i], '${_kcal(kcalOn(i).round())} kcal', own.contains(i), false)],
          selected: sel,
          onPick: (i) => setState(() => _mday = i),
        ),
        PdHead(
          title: '${weekdayFull[sel]} · ${meals.length} meals',
          sub: '${_kcal(tot.$1.round())} kcal · P ${tot.$2.round()} g · tap a meal to see the foods',
          badge: own.contains(sel) ? 'Own meals this day' : (m['custom'] == true ? 'Edited for ${c.first}' : null),
        ),
        if (meals.isEmpty) const PdEmpty('No meals in this plan yet.'),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
          child: Column(children: [
            for (final (i, x) in meals.indexed)
              MealRow(
                meal: x,
                onTap: () => showMealDrawer(context,
                    c: c,
                    meals: meals,
                    start: i,
                    sub: '${weekdayFull[sel]} · ${m['plan_name']}',
                    custom: m['custom'] == true,
                    onEdit: () => setState(() {
                          _mday = sel;
                          _mealEdit = true;
                        })),
              ),
          ]),
        ),
      ]),
    );
    return _cols([card], side);
  }

  String _kcal(Object? v) => NumberFormat.decimalPattern('en_IN').format((v as num?) ?? 0);

  void _openMealEditor() => setState(() => _mealEdit = true);

  Future<void> _resetMeal(Map m) async {
    final ok = await confirmAction(context,
        title: 'Reset to master?',
        body: 'Every change made for ${c.first} in ${m['plan_name']} goes away, on every day. ${c.first} follows the master meal plan as it is. Logged meals stay.',
        confirm: 'Reset to master',
        danger: true,
        icon: AppIcons.reset);
    if (ok) await _post('clients/${c.id}/meal-plans/${m['id']}/reset/', ok: '${c.first} follows the master again', sub: '${m['plan_name']}');
  }

  // ─────────────────────────────── Supplements

  Widget _supps() {
    final cur = PlansData.rows(d.supps, 'current');
    final next = PlansData.rows(d.supps, 'up_next');
    final hist = [...cur, ...PlansData.rows(d.supps, 'history')];
    final side = [
      _upNext(
        next: next.firstOrNull,
        name: next.map((n) => '${n['plan_name']}').join(', '),
        sub: next.isEmpty ? '' : ['Starts ${cpDay(next.first['start_date'])}', if (next.first['assigned_by'] != null) 'set by ${next.first['assigned_by']}'].join(' · '),
        empty: 'No next supplement plan.',
      ),
      if (hist.isNotEmpty)
        _history([
          for (final a in hist)
            ('${a['plan_name']}', '${cpDm(a['start_date'])} – ${a['active'] == true ? 'now' : cpDm(a['ended_on'])}', a['active'] == true ? 'Current' : 'Ended'),
        ]),
    ];
    if (cur.isEmpty) {
      return _cols([_noPlan('No supplements yet', 'Pick a supplement plan from the library for ${c.first}.', 'Assign a supplement plan')], side);
    }
    return _cols([
      for (final a in cur)
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _planHead(
              title: '${a['plan_name']}',
              info: ['Since ${cpDm(a['start_date'])}', '${(a['items'] as List).length} items', if ('${a['note'] ?? ''}'.isNotEmpty) '${a['note']}'].join(' · '),
              edited: a['custom'] == true,
              tip: 'Changes here apply only to ${c.first}. The master supplement plan in the library stays the same. ${c.first} ticks each one in the app and keeps ${pronoun(c)} own stock count.',
              onEdit: () => setState(() => _suppEdit = a),
              menu: _menu(
                reset: a['custom'] == true ? () => _resetSupps(a) : null,
                openMaster: () => _openMaster('/habits'),
                end: () => _confirmEnd('${a['plan_name']}', 'clients/${c.id}/supplement-plans/${a['id']}/end/'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: (a['items'] as List).isEmpty
                  ? const PdEmpty('No supplements in this plan yet.')
                  : Column(children: [
                      for (final it in (a['items'] as List).cast<Map>())
                        AppRow(
                          leading: cpIcon(AppIcons.pill),
                          title: '${it['name']}',
                          sub: [it['timing_label'], it['dose'], if ('${it['how'] ?? ''}'.isNotEmpty) '${it['how']}'.toLowerCase()].join(' · '),
                          trailing: it['stock'] == null ? null : Text('${it['stock']['quantity']} ${it['stock']['unit']} left', style: AppText.cap),
                        ),
                    ]),
            ),
          ]),
        ),
    ], side);
  }

  Future<void> _resetSupps(Map a) async {
    final ok = await confirmAction(context,
        title: 'Reset to master?',
        body: 'Every change made for ${c.first} in ${a['plan_name']} goes away. ${c.first} takes the master supplements "${a['master_name'] ?? a['plan_name']}" again. Ticks stay.',
        confirm: 'Reset to master',
        danger: true,
        icon: AppIcons.reset);
    if (ok) await _post('clients/${c.id}/supplement-plans/${a['id']}/reset/', ok: '${c.first} follows the master again', sub: '${a['master_name'] ?? a['plan_name']}');
  }

  // ─────────────────────────────── Habits

  Widget _habits() {
    final cur = PlansData.rows(d.habits, 'current');
    final next = PlansData.rows(d.habits, 'up_next');
    final hist = PlansData.rows(d.habits, 'history');
    final week = {for (final h in (d.habitWeek?['habits'] as List?) ?? const []) '${h['id']}': h as Map};
    final all = [...cur, ...next];
    final side = [
      _upNext(
        next: null,
        name: '',
        sub: '',
        empty: next.isEmpty ? 'No next habit plan.' : '${next.length} habit${next.length == 1 ? '' : 's'} start later. ${pronounSub(c).capFirst} sees ${next.length == 1 ? 'it' : 'them'} from the start day.',
      ),
      if (all.isNotEmpty || hist.isNotEmpty)
        _history([
          for (final a in all) ('${a['habit']['name']}', '${cpDm(a['start_date'])} – now', cpParse(a['start_date'])!.isAfter(DateTime.now()) ? 'Up next' : 'Current'),
          for (final a in hist) ('${a['habit']['name']}', '${cpDm(a['start_date'])} – ${cpDm(a['ended_on'])}', 'Ended'),
        ]),
    ];
    if (all.isEmpty) return _cols([_noPlan('No habits yet', 'Pick habits from the library for ${c.first}.', 'Assign a habit plan')], side);
    final first = all.map((a) => cpParse(a['start_date'])!).reduce((a, b) => a.isBefore(b) ? a : b);
    final card = AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _planHead(
          title: 'Daily habits',
          info: [
            'Since ${cpDm(first.toIso8601String())}',
            '${all.length} habit${all.length == 1 ? '' : 's'}',
            if (next.isNotEmpty) '${next.length} habit${next.length == 1 ? '' : 's'} start${next.length == 1 ? 's' : ''} later',
          ].join(' · '),
          edited: false,
          tip: 'Habits come from the library. Adding or removing one here changes only ${c.first}’s list.',
          onEdit: () async {
            final changed = await showHabitsEditor(context, c: c, d: d);
            if (changed == true) d.reload();
          },
          menu: _menu(
            openMaster: () => _openMaster('/habits'),
            end: () async {
              final ok = await confirmAction(context,
                  title: 'End all habits?',
                  body: '${c.first} stops getting these ${all.length} habits from tomorrow. The logs stay.',
                  confirm: 'End habits',
                  danger: true,
                  icon: AppIcons.stop);
              if (!ok) return;
              try {
                for (final a in all) {
                  await Services.api.post('clients/${c.id}/habit-plan/${a['id']}/end/', const {});
                }
                if (mounted) showToast(context, 'Habits ended', sub: 'They moved to Plan history', kind: ToastKind.ok);
              } on ApiError catch (e) {
                if (mounted) showToast(context, 'Could not end the habits', sub: e.message, kind: ToastKind.info);
              }
              d.reload();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          child: Column(children: [
            for (final a in all)
              () {
                final h = a['habit'] as Map;
                final w = week['${h['id']}'];
                final start = cpParse(a['start_date'])!;
                final later = start.isAfter(DateTime.now());
                final cells = [for (final x in (w?['week'] as List?) ?? const []) '$x'];
                final done = cells.where((x) => x == 'done').length;
                final due = cells.where((x) => x != 'off').length;
                return AppRow(
                  leading: cpIcon(AppIcons.checkCircle),
                  title: '${h['name']}',
                  sub: habitFrequency(h),
                  trailing: Text(later ? 'Starts ${cpDay(a['start_date'])}' : '$done of $due this week', style: AppText.cap),
                );
              }(),
          ]),
        ),
      ]),
    );
    return _cols([card], side);
  }
}

String habitFrequency(Map h) => switch ('${h['frequency']}') {
      'daily' => h['icon'] == 'sleep' ? 'Every night' : 'Every day',
      'times_week' => '${h['times_per_week']} times a week',
      _ => 'Every ${h['frequency_label']}',
    };

/// Plan history card (`Plan history N`): name, date range, status badge. 5 rows, then `Show all`.
class _HistoryCard extends StatefulWidget {
  const _HistoryCard({required this.rows});
  final List<(String, String, String)> rows;
  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  bool _all = false;
  @override
  Widget build(BuildContext context) {
    final rows = _all ? widget.rows : widget.rows.take(5).toList();
    return CpCard(
      title: 'Plan history',
      count: widget.rows.length,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (n, s, b) in rows) AppRow(title: n, sub: s, trailing: AppBadge(b, tone: b == 'Completed' ? Tone.neutral : cpTone(b))),
        if (widget.rows.length > 5)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
            child: CpLink(_all ? 'Show less' : 'Show all ${widget.rows.length}', onTap: () => setState(() => _all = !_all)),
          ),
      ]),
    );
  }
}

/// `.cp-info` (i) with the board's tooltip.
class CpInfo extends StatelessWidget {
  const CpInfo(this.tip, {super.key});
  final String tip;
  @override
  Widget build(BuildContext context) => AppTooltip(
        message: tip,
        child: Hover(
          onTap: () => showToast(context, tip, kind: ToastKind.info),
          builder: (_, h, _) => Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: h ? AppColors.accentSoft : null, borderRadius: BorderRadius.circular(6)),
            child: AppIcon(AppIcons.info, size: 16, color: h ? AppColors.accent : AppColors.muted),
          ),
        ),
      );
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
  String get capFirst => isEmpty ? this : this[0].toUpperCase() + substring(1);
}
