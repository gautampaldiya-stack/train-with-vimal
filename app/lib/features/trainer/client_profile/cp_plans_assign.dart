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
import '../../../core/widgets/tabs.dart';
import 'cp_common.dart';
import 'cp_model.dart';
import 'cp_plans_model.dart';
import 'cp_plans_parts.dart';

/// Header `Assign plan ▾`, ⋯ `Assign a plan`, `Assign new plan`, `Replace with another plan`, Up next `Change` /
/// `Choose next plan`: the plan picker drawer (`assign`, board `TrainerClientProfile`) for one slot
/// (`workout` · `meal` · `supplements` · `habits`): 1. Pick a plan (filter, search, `Duplicate current`), Preview,
/// 2. When does it start?, 3. Options, footer summary + `Assign plan`. Calls `c.refresh()` after assigning.
Future<void> showAssignPlan(BuildContext context, CpController c, String slot, {bool replace = false, bool next = false}) {
  final s = _Assign(c, slot, replace: replace, next: next)..load();
  final search = TextEditingController();
  return showAppDrawer(
    context,
    title: s.title,
    sub: '${s.source}. ${c.first} gets ${pronoun(c)} own copy; the master is not changed.',
    wide: true,
    icon: AppIcons.clipboard,
    builder: (ctx) => ListenableBuilder(
      listenable: s,
      builder: (ctx, _) {
        if (s.loading) return const CpLoading();
        if (s.error != null) return EmptyState('Could not load the plans', sub: s.error, action: AppButton('Try again', onPressed: s.load));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sec(
            '1. Pick a plan',
            action: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
              if (s.filters.isNotEmpty)
                Builder(
                  builder: (b) => AppButton('Filter${s.filterCount == 0 ? '' : ' · ${s.filterCount}'}', icon: AppIcons.filter, size: BtnSize.sm, onPressed: () => s.openFilter(b)),
                ),
              if (slot == 'workout' && s.current.isNotEmpty)
                AppButton('Duplicate current', icon: AppIcons.copy, size: BtnSize.sm, onPressed: () {
                  Navigator.of(ctx).pop();
                  PlanEvents.instance.send(PlanEvent(c.id, 'dup'));
                }),
            ]),
            children: [
              AppSearchField(controller: search, placeholder: s.searchHint, onChanged: s.setQuery),
              _options(ctx, s),
            ],
          ),
          if (s.picked.isNotEmpty) _sec('Preview', children: [_preview(s)]),
          _sec('2. When does it start?', children: [
            SegmentedTabs<String>(items: [for (final (k, l, _) in s.modes) TabItem(k, l)], value: s.when, onChanged: s.setWhen, expand: true),
            Text(s.modes.firstWhere((m) => m.$1 == s.when).$3, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
            _two(
              ctx,
              _field('Start date', _box(DateFormat('EEE, d MMM').format(s.start), icon: AppIcons.calendar, onTap: () => s.pickDate(ctx))),
              _field('Length', _box(s.length)),
            ),
          ]),
          _sec('3. Options', last: true, children: [
            if (s.canEditAfter)
              _switch('Edit ${c.first}’s copy before ${pronounSub(c)} sees it', 'Opens the editor right after you assign.', s.editAfter, (v) => s.set(() => s.editAfter = v)),
            _switch('Tell ${c.first} in the app', 'Push notice: "${Services.session.me?.firstName ?? 'Your coach'} added a new plan for you"', s.notify,
                (v) => s.set(() => s.notify = v)),
          ]),
        ]);
      },
    ),
    footer: (ctx) => [
      ListenableBuilder(
        listenable: s,
        builder: (_, _) {
          final t = Text(s.summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cap);
          return ctx.isPhone ? t : Expanded(child: t);
        },
      ),
      if (!ctx.isPhone) AppButton('Cancel', onPressed: () => Navigator.of(ctx).pop()),
      ListenableBuilder(
        listenable: s,
        builder: (_, _) => AppButton.primary('Assign plan',
            icon: AppIcons.check, expand: ctx.isPhone, loading: s.busy, onPressed: s.picked.isEmpty || s.busy ? null : () => s.save(ctx)),
      ),
    ],
  ).whenComplete(() => disposeLater([s, search]));
}

Widget _sec(String title, {Widget? action, required List<Widget> children, bool last = false}) => Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        Row(children: [Expanded(child: Text(title, style: AppText.s(13.5, W.w8))), ?action]),
        ...children,
      ]),
    );

Widget _two(BuildContext ctx, Widget a, Widget b) => ctx.isPhone
    ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [a, b])
    : Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [Expanded(child: a), Expanded(child: b)]);

Widget _field(String label, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [Text(label, style: AppText.label), child]);

Widget _box(String text, {AppIconData? icon, VoidCallback? onTap}) => Hover(
      onTap: onTap,
      builder: (_, h, _) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: onTap == null ? AppColors.sub : AppColors.white,
          borderRadius: AppRadius.all(AppRadius.input),
          border: Border.all(color: h && onTap != null ? AppColors.lineHover : AppColors.line2),
        ),
        child: Row(spacing: 8, children: [
          Expanded(child: Text(text, style: AppText.s(14, W.w6, color: onTap == null ? AppColors.muted : AppColors.text))),
          if (icon != null) AppIcon(icon, size: 16, color: AppColors.muted),
        ]),
      ),
    );

Widget _switch(String t, String s, bool v, ValueChanged<bool> on) => Hover(
      onTap: () => on(!v),
      builder: (_, _, _) => Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: AppToggle(value: v, onChanged: on)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(t, style: AppText.s(13.5, W.w7)),
            Text(s, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
          ]),
        ),
      ]),
    );

/// The plan list (`.dr-opts.joined`): radio (checkbox for habits), name + `Current` / tip badges, sub, clients.
Widget _options(BuildContext ctx, _Assign s) {
  final list = s.visible;
  if (list.isEmpty) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: EmptyState(s.all.isEmpty ? 'Nothing in the library yet' : 'No plans match', sub: s.all.isEmpty ? 'Add one in the library first.' : 'Try another search or clear the filters.'),
    );
  }
  return Container(
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: AppColors.line2)),
    child: Column(children: [
      for (final (i, p) in list.indexed)
        () {
          final id = '${p['id']}';
          final on = s.picked.contains(id);
          final cur = s.isCurrent(id);
          return Hover(
            onTap: cur ? null : () => s.toggle(id),
            builder: (_, h, _) => Opacity(
              opacity: cur ? .6 : 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: on ? AppColors.pickBg : (h && !cur ? AppColors.outlineHover : null),
                  border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line)),
                ),
                child: Row(spacing: 12, children: [
                  s.multi ? AppCheckbox(value: on || cur, size: 18) : AppRadio(selected: on),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                      Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(s.name(p), style: AppText.s(13.5, W.w7)),
                        if (cur) const AppBadge('Current', plain: true),
                        if (s.tip(p) != null) AppBadge(s.tip(p)!, tone: Tone.info, plain: true),
                      ]),
                      Text(s.sub(p), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
                    ]),
                  ),
                  if (p['client_count'] != null) Text('${p['client_count']} clients', style: AppText.cap),
                ]),
              ),
            ),
          );
        }(),
    ]),
  );
}

/// Preview (`.pvw`): name, note, `Open in library`, the 3–4 numbers, each week / each day, what changes vs now.
Widget _preview(_Assign s) => FutureBuilder<_Pv>(
      future: s.preview(),
      builder: (ctx, snap) {
        final pv = snap.data;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: AppColors.tableHeadDt, borderRadius: BorderRadius.circular(12)),
          child: pv == null
              ? const CpLoading()
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                        Text(pv.name, style: AppText.s(14.5, W.w8)),
                        if (pv.note.isNotEmpty) Text(pv.note, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
                      ]),
                    ),
                  ]),
                  Container(
                    padding: const EdgeInsets.only(bottom: 10),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
                    child: LayoutBuilder(builder: (context, b) {
                      final n = pv.kpis.length;
                      final w = (b.maxWidth / (n == 4 && b.maxWidth < 420 ? 2 : n)).floorToDouble();
                      return Wrap(runSpacing: 10, children: [
                        for (final (i, (k, v)) in pv.kpis.indexed)
                          Container(
                            width: w,
                            padding: EdgeInsets.only(left: i == 0 ? 0 : 12),
                            decoration: BoxDecoration(border: i == 0 ? null : const Border(left: BorderSide(color: AppColors.line))),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                              Text(k, style: AppText.s(12, W.w5, color: AppColors.muted)),
                              Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(14, W.w8)),
                            ]),
                          ),
                      ]);
                    }),
                  ),
                  Text(pv.rowsTitle.toUpperCase(), style: AppText.over),
                  Column(children: [
                    for (final (i, (k, v, m, rest)) in pv.rows.indexed)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
                        child: Row(spacing: 12, children: [
                          SizedBox(width: 64, child: Text(k, style: AppText.s(12.5, W.w5, color: AppColors.muted))),
                          Expanded(child: Text(v, style: AppText.s(13.5, rest ? W.w5 : W.w7, color: rest ? AppColors.text2 : AppColors.text))),
                          Text(m, style: AppText.cap),
                        ]),
                      ),
                    if (pv.rows.isEmpty) Text('Nothing in it yet.', style: AppText.sub),
                  ]),
                  if (pv.diff.isNotEmpty) ...[
                    Text('COMPARED TO ${pronoun(s.c).toUpperCase()} CURRENT PLAN', style: AppText.over),
                    for (final t in pv.diff)
                      Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                        const Padding(padding: EdgeInsets.only(top: 2), child: AppIcon(AppIcons.swap, size: 14, color: AppColors.accent)),
                        Expanded(child: Text(t, style: AppText.s(13, W.w5, color: AppColors.text2))),
                      ]),
                  ],
                ]),
        );
      },
    );

class _Pv {
  _Pv(this.name, this.note, this.kpis, this.rowsTitle, this.rows, this.diff);
  final String name, note, rowsTitle;
  final List<(String, String)> kpis;
  final List<(String, String, String, bool)> rows;
  final List<String> diff;
}

class _Assign extends ChangeNotifier {
  _Assign(this.c, this.slot, {required this.replace, required this.next});
  final CpController c;
  final String slot;
  final bool replace, next;

  bool loading = true, busy = false, notify = true, editAfter = false;
  String? error;
  List<Map> all = [];
  Map mine = const {};
  Set<String> picked = {};
  String query = '';
  String when = 'now';
  DateTime start = _today();
  final Map<String, String> filter = {};
  final Map<String, Future<Map>> _detail = {};

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  void set(VoidCallback f) {
    f();
    notifyListeners();
  }

  bool get multi => slot == 'habits';

  String get title => switch (slot) {
        'meal' => 'Assign a meal plan',
        'supplements' => 'Assign a supplement plan',
        'habits' => 'Assign a habit plan',
        _ => 'Assign a workout plan',
      };
  String get source => switch (slot) {
        'meal' => 'Meal plans from the library',
        'supplements' => 'Supplement plans from the library',
        'habits' => 'Habits from the library',
        _ => 'Programs from the library',
      };
  String get searchHint => switch (slot) {
        'meal' => 'Search meal plans',
        'supplements' => 'Search supplement plans',
        'habits' => 'Search habits',
        _ => 'Search workout plans',
      };

  String get _base => switch (slot) {
        'meal' => 'clients/${c.id}/meal-plans/',
        'supplements' => 'clients/${c.id}/supplement-plans/',
        'habits' => 'clients/${c.id}/habit-plan/',
        _ => 'clients/${c.id}/programs/',
      };

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final lib = switch (slot) {
        'meal' => Services.api.get<Map>('meal-plans/', query: {'page_size': 100}).then((r) => r['results'] as List),
        'supplements' => Services.api.get<List>('supplement-plans/'),
        'habits' => Services.api.get<List>('habits/'),
        _ => Services.api.get<Map>('programs/', query: {'page_size': 100}).then((r) => r['results'] as List),
      };
      final r = await Future.wait([lib, Services.api.get<Map>(_base)]);
      all = [for (final x in r[0] as List) x as Map];
      mine = r[1] as Map;
      when = modes.first.$1;
      if (replace && modes.any((m) => m.$1 == 'now')) when = 'now';
      if (next && current.isNotEmpty) when = modes.any((m) => m.$1 == 'next') && slot == 'workout' ? 'next' : 'date';
      _syncStart();
      final first = visible.where((p) => !isCurrent('${p['id']}')).firstOrNull;
      if (first != null && !multi) picked = {'${first['id']}'};
    } on ApiError catch (e) {
      error = e.message;
    }
    loading = false;
    notifyListeners();
  }

  List<Map> get current => PlansData.rows(mine, 'current');
  List<Map> get upNext => PlansData.rows(mine, 'up_next');

  String _curId(Map a) => '${switch (slot) { 'habits' => (a['habit'] as Map)['id'], 'workout' => a['program'], _ => a['plan'] }}';
  bool isCurrent(String id) => current.any((a) => _curId(a) == id);
  String get curName => current.isEmpty
      ? ''
      : switch (slot) {
          'workout' => '${current.first['program_name']}',
          'habits' => 'the current habits',
          _ => '${current.first['plan_name']}',
        };

  String name(Map p) => '${p['name']}';
  String? tip(Map p) => slot == 'meal' && p['status'] != 'published' ? 'Draft' : null;
  String sub(Map p) => switch (slot) {
        'meal' => [
            '${const {'veg': 'Veg', 'egg': 'Eggetarian', 'nonveg': 'Non-veg', 'vegan': 'Vegan'}[p['diet']] ?? p['diet']}',
            '${NumberFormat.decimalPattern('en_IN').format(p['kcal_target'] ?? 0)} kcal',
            '${p['meal_count'] ?? 0} meals a day',
          ].join(' · '),
        'supplements' => [for (final i in (p['items'] as List?) ?? const []) '${i['name']}'].join(', ').ifEmpty('No items yet'),
        'habits' => '${p['frequency_label']}${'${p['why'] ?? ''}'.isEmpty ? '' : ' · ${p['why']}'}',
        _ => ['${p['weeks']} weeks', '${p['days_per_week']} days a week', if ('${p['goal_line'] ?? ''}'.isNotEmpty) '${p['goal_line']}'].join(' · '),
      };

  // ── filter + search
  List<(String, List<(String, String)>)> get filters => switch (slot) {
        'workout' => [
            ('Days a week', [('', 'Any'), ('2', '2'), ('3', '3'), ('4', '4'), ('5', '5'), ('6', '6')]),
          ],
        'meal' => [
            ('Diet', [('', 'Any'), ('veg', 'Veg'), ('egg', 'Eggetarian'), ('nonveg', 'Non-veg'), ('vegan', 'Vegan')]),
            ('Calories', [('', 'Any'), ('lo', 'Under 1,600'), ('mid', '1,600–1,900'), ('hi', 'Over 1,900')]),
          ],
        _ => const [],
      };
  int get filterCount => filter.values.where((v) => v.isNotEmpty).length;

  void openFilter(BuildContext anchor) => showFilterMenu(anchor, [
        for (final (g, opts) in filters)
          MenuGroup(g, value: opts.firstWhere((o) => o.$1 == (filter[g] ?? ''), orElse: () => opts.first).$2, options: [
            for (final (v, l) in opts) MenuEntry(l, selected: (filter[g] ?? '') == v, onTap: () => set(() => filter[g] = v)),
          ]),
      ], onClear: () => set(filter.clear));

  void setQuery(String q) => set(() => query = q.trim().toLowerCase());

  List<Map> get visible => all.where((p) {
        if (query.isNotEmpty && !'${p['name']}'.toLowerCase().contains(query)) return false;
        final days = filter['Days a week'] ?? '';
        if (days.isNotEmpty && '${p['days_per_week']}' != days) return false;
        final diet = filter['Diet'] ?? '';
        if (diet.isNotEmpty && p['diet'] != diet) return false;
        final k = (p['kcal_target'] as num?) ?? 0;
        switch (filter['Calories'] ?? '') {
          case 'lo' when k >= 1600:
          case 'mid' when k < 1600 || k > 1900:
          case 'hi' when k <= 1900:
            return false;
        }
        return true;
      }).toList();

  void toggle(String id) => set(() {
        if (multi) {
          picked = picked.contains(id) ? ({...picked}..remove(id)) : {...picked, id};
        } else {
          picked = {id};
        }
      });

  Map? get _sel => all.where((p) => picked.contains('${p['id']}')).firstOrNull;

  // ── when
  DateTime? get _curEnd => slot == 'workout' && current.isNotEmpty ? planEnd(current.first) : null;

  /// (key, tab label, hint under the tabs)
  List<(String, String, String)> get modes {
    final has = current.isNotEmpty;
    const date = ('date', 'Pick a date', 'Starts on the date you pick, up to 3 months ahead.');
    final now = has
        ? ('now', 'Replace current', 'Starts today. $curName ends today and moves to Plan history.')
        : ('now', 'Start today', 'Starts today.');
    return switch (slot) {
      'workout' => [
          if (has) ('next', 'After current ends', 'Starts when $curName ends on ${DateFormat('EEE, d MMM').format(_curEnd!)}. It shows as Up next till then.'),
          now,
          date,
        ],
      'meal' => [now, date],
      _ => [
          has ? ('next', 'Next to current', 'Starts today. Both plans run together.') : ('next', 'Start today', 'Starts today.'),
          if (has) now,
          date,
        ],
    };
  }

  void setWhen(String w) => set(() {
        when = w;
        _syncStart();
      });

  void _syncStart() {
    final t = _today();
    if (when == 'next' && _curEnd != null) {
      start = _curEnd!.add(const Duration(days: 1));
    } else if (when == 'date') {
      if (!start.isAfter(t)) start = t.add(const Duration(days: 1));
    } else {
      start = t;
    }
    if (when != 'now' && when != 'next' || (when == 'next' && slot == 'workout')) editAfter = false;
  }

  Future<void> pickDate(BuildContext ctx) async {
    final t = _today();
    final v = await showDatePicker(context: ctx, initialDate: start.isBefore(t) ? t : start, firstDate: t, lastDate: t.add(const Duration(days: 92)));
    if (v == null) return;
    set(() {
      when = v == t && modes.any((m) => m.$1 == 'now') ? 'now' : 'date';
      start = v;
      if (when == 'date') editAfter = false;
    });
  }

  String get length => slot == 'workout' && _sel != null ? '${_sel!['weeks']} weeks' : 'Ongoing';

  bool get canEditAfter => slot == 'workout' && when == 'now';

  String get summary {
    if (picked.isEmpty) return multi ? 'Pick the habits to add' : 'Pick a plan';
    final n = multi ? '${picked.length} habit${picked.length == 1 ? '' : 's'}' : name(_sel ?? const {});
    final t = _today();
    return '$n · ${start == t ? 'from today' : 'from ${DateFormat('EEE, d MMM').format(start)}'}';
  }

  // ── preview
  Future<_Pv> preview() async {
    final f = NumberFormat.decimalPattern('en_IN');
    if (multi) {
      final hs = all.where((p) => picked.contains('${p['id']}')).toList();
      return _Pv(hs.length == 1 ? '${hs.first['name']}' : '${hs.length} habits', 'Checked by ${c.first} in the app', [
        ('Habits', '${hs.length}'),
        ('Length', 'Ongoing'),
        ('Check', 'Daily'),
      ], 'Each day', [
        for (final h in hs) ('${h['frequency_label']}', '${h['name']}', h['kind'] == 'counter' ? '${f.format(h['target'] ?? 0)} ${h['unit']}' : 'yes / no', false),
      ], [
        if (current.isNotEmpty) when == 'now' ? 'Replaces the ${current.length} habits ${c.first} has now' : 'Runs next to the ${current.length} habits ${c.first} has now',
      ]);
    }
    final p = _sel!;
    final id = '${p['id']}';
    switch (slot) {
      case 'supplements':
        final items = [for (final i in (p['items'] as List?) ?? const []) i as Map];
        const t = {'breakfast': 'Breakfast', 'morning': 'Morning', 'post_workout': 'After workout', 'any': 'Any time', 'night': 'Night', 'before_bed': 'Before bed'};
        final cur = current.isEmpty ? <String>{} : {for (final i in (current.first['items'] as List)) '${i['name']}'};
        final now = {for (final i in items) '${i['name']}'};
        return _Pv('${p['name']}', '${p['note'] ?? ''}'.ifEmpty('${p['client_count'] ?? 0} clients on it'), [
          ('Items', '${items.length}'),
          ('When', {for (final i in items) t['${i['timing']}'] ?? ''}.join(', ').ifEmpty('–')),
        ], 'Each day', [
          for (final i in items) (t['${i['timing']}'] ?? '', '${i['name']}', '${i['dose']}', false),
        ], [
          if (now.difference(cur).isNotEmpty && cur.isNotEmpty) 'Adds ${now.difference(cur).join(', ')}',
          if (cur.difference(now).isNotEmpty && when == 'now') 'Drops ${cur.difference(now).join(', ')}',
          if (cur.isNotEmpty && when == 'next') 'Runs next to $curName, does not replace it',
        ]);
      case 'meal':
        final m = await _detail.putIfAbsent(id, () => Services.api.get<Map>('meal-plans/$id/'));
        final meals = [for (final x in (m['meals'] as List?) ?? const []) x as Map];
        final cur = current.firstOrNull;
        final dk = cur == null ? 0 : ((m['kcal_target'] as num) - (cur['kcal'] as num)).toInt();
        final dm = cur == null ? 0 : meals.length - ((cur['meals'] as num?) ?? 0).toInt();
        return _Pv('${m['name']}', '${const {'veg': 'Vegetarian', 'egg': 'Eggetarian', 'nonveg': 'Non-veg', 'vegan': 'Vegan'}[m['diet']] ?? ''} · ${m['client_count'] ?? 0} clients on it', [
          ('Calories', '${f.format(m['kcal_target'] ?? 0)} kcal'),
          ('Protein', '${m['protein_g']} g'),
          ('Meals', '${meals.length} a day'),
          ('Diet', const {'veg': 'Veg', 'egg': 'Egg', 'nonveg': 'Non-veg', 'vegan': 'Vegan'}[m['diet']] ?? ''),
        ], 'Each day', [
          for (final x in meals) (mealTime(x['time']), '${x['name']}', '${mealKcal(x).round()} kcal', false),
        ], [
          if (dk != 0) dk < 0 ? '${f.format(-dk)} kcal less a day' : '${f.format(dk)} kcal more a day',
          if (dm != 0) dm > 0 ? '$dm more meal${dm == 1 ? '' : 's'} a day' : '${-dm} fewer meal${dm == -1 ? '' : 's'} a day',
        ]);
      default:
        final m = await _detail.putIfAbsent(id, () => Services.api.get<Map>('programs/$id/'));
        final w1 = weekOf(m, 1);
        final days = [for (var i = 0; i < 7; i++) dayOf(w1, i)];
        final train = days.where((d) => !isRest(d)).toList();
        final mins = train.isEmpty ? 0 : (train.fold<int>(0, (a, d) => a + dayMinutes(d)) / train.length).round();
        final cur = current.firstOrNull;
        return _Pv('${m['name']}', ['${m['goal_line'] ?? ''}', '${m['client_count'] ?? p['client_count'] ?? 0} clients on it'].where((x) => x.isNotEmpty).join(' · '), [
          ('Days', '${m['days_per_week']} a week'),
          ('Length', '${m['weeks']} weeks'),
          ('Time', mins == 0 ? '–' : '~$mins min'),
          ('Goal', '${m['goal_line'] ?? ''}'.split(' · ').first.ifEmpty('–')),
        ], 'Each week', [
          for (var i = 0; i < 7; i++)
            (weekdayShort[i], isRest(days[i]) ? 'Rest' : '${days[i]?['name'] ?? ''}'.ifEmpty('Workout'), isRest(days[i]) ? '${days[i]?['rest_note'] ?? ''}'.split('.').first : '${exercisesOf(days[i]).length} exercises', isRest(days[i])),
        ], [
          if (cur != null && cur['days_per_week'] != m['days_per_week']) '${m['days_per_week']} days a week instead of ${cur['days_per_week']}',
          if (cur != null && cur['days_per_week'] == m['days_per_week']) 'Still ${m['days_per_week']} days a week, so ${pronoun(c)} routine stays the same',
          if (cur != null && cur['weeks'] != m['weeks']) '${m['weeks']} weeks long, ${cur['program_name']} is ${cur['weeks']}',
        ]);
    }
  }

  // ── save
  Future<void> save(BuildContext ctx) async {
    set(() => busy = true);
    final ds = DateFormat('yyyy-MM-dd').format(start);
    final sel = _sel;
    try {
      switch (slot) {
        case 'meal':
          await Services.api.post(_base, {'plan': sel!['id'], 'start_date': ds, 'notify': notify});
        case 'supplements':
          await Services.api.post(_base, {'plan': sel!['id'], 'when': when, 'start_date': ds, 'notify': notify});
        case 'habits':
          await Services.api.post(_base, {'habits': picked.toList(), 'when': when, 'start_date': ds, 'notify': notify});
        default:
          // One Up next at a time: `Change` swaps it.
          if (when != 'now' && upNext.isNotEmpty) await Services.api.post('$_base${upNext.first['id']}/end/', const {});
          await Services.api.post(_base, {
            'program': sel!['id'],
            'when': when == 'next' ? 'after_current' : 'now',
            'start_date': when == 'next' ? null : ds,
            'notify': notify,
          });
      }
      if (!ctx.mounted) return;
      Navigator.of(ctx).pop();
      showToast(ctx, slot == 'habits' ? 'Habits assigned' : 'Plan assigned', sub: '$summary · ${c.first}', kind: ToastKind.ok);
      await c.refresh();
      if (editAfter) PlanEvents.instance.send(PlanEvent(c.id, 'edit'));
    } on ApiError catch (e) {
      set(() => busy = false);
      if (ctx.mounted) showToast(ctx, 'Could not assign the plan', sub: e.message, kind: ToastKind.info);
    }
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
