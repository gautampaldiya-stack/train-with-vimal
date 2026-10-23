import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../app/shell/page.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import '../../../core/widgets/tabs.dart';
import '../../../core/widgets/tooltip.dart';
import '../../trainer/me/me_common.dart' show meField;
import '../lib_common.dart';
import '../programs/builder_sheets.dart' show showNameModal;
import 'food_drawer.dart';
import 'food_import.dart';
import 'nu_common.dart';

/// Tells the Nutrition page to reload (a plan saved in the builder, a food saved in the drawer).
final nutritionChanged = ValueNotifier<int>(0);

/// Nutrition & foods (boards `Nutrition` / `NutritionMobile`): Meal plans (cards, diet tabs, New plan, card ⋯) and
/// Food library (table with groups, per serving / per 100 g, diet, pages; Create food, Import from Excel).
/// What this person may do comes from `meal-plans/counts/` → `can` and each card's `can_edit` (D-39, D-44).
class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key, this.tab});
  final String? tab;
  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  late String tab = widget.tab == 'foods' ? 'foods' : 'plans';
  Map counts = const {};

  // plans
  String q = '', diet = 'all';
  List<Map> plans = [];
  String? next;
  bool loading = true, more = false;
  ApiError? error;

  // foods
  String fq = '', fdiet = 'any', group = 'all';
  bool per100 = false, fLoading = true;
  int page = 1, fCount = 0;
  List<Map> foods = [];
  Map fCounts = const {};
  ApiError? fError;
  static const _pageSize = 10;

  Timer? _debounce;
  int _req = 0, _freq = 0;

  Map get _can => (counts['can'] as Map?) ?? const {};
  bool get canCreate => _can['create'] == true;
  bool get canFoods => _can['foods'] == true;

  @override
  void initState() {
    super.initState();
    nutritionChanged.addListener(_reload);
    _reload();
  }

  @override
  void didUpdateWidget(NutritionScreen old) {
    super.didUpdateWidget(old);
    final t = widget.tab == 'foods' ? 'foods' : 'plans';
    if (t != tab) setState(() => tab = t);
  }

  @override
  void dispose() {
    nutritionChanged.removeListener(_reload);
    _debounce?.cancel();
    super.dispose();
  }

  void _reload() {
    _load();
    _loadFoods();
  }

  Future<void> _load() async {
    final req = ++_req;
    setState(() => loading = plans.isEmpty);
    try {
      final r = await Future.wait([
        Services.api.get<Map>('meal-plans/', query: {'search': q, 'page_size': 24, if (diet != 'all') 'diet': diet}),
        Services.api.get<Map>('meal-plans/counts/'),
      ]);
      if (req != _req || !mounted) return;
      setState(() {
        plans = [for (final x in r[0]['results'] as List) x as Map];
        next = r[0]['next'] as String?;
        counts = r[1];
        error = null;
        loading = false;
      });
    } on ApiError catch (e) {
      if (req != _req || !mounted) return;
      setState(() {
        error = e;
        loading = false;
      });
    }
  }

  Future<void> _more() async {
    final n = next;
    if (n == null || more) return;
    setState(() => more = true);
    try {
      final pg = Uri.parse(n).queryParameters['page'];
      final r = await Services.api.get<Map>('meal-plans/', query: {'search': q, 'page_size': 24, 'page': pg, if (diet != 'all') 'diet': diet});
      if (!mounted) return;
      setState(() {
        plans = [...plans, for (final x in r['results'] as List) x as Map];
        next = r['next'] as String?;
      });
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not load more', sub: e.message, kind: ToastKind.err);
    }
    if (mounted) setState(() => more = false);
  }

  Future<void> _loadFoods() async {
    final req = ++_freq;
    setState(() => fLoading = foods.isEmpty);
    final d = {if (fdiet != 'any') 'diet': fdiet};
    try {
      final r = await Future.wait([
        Services.api.get<Map>('foods/', query: {'search': fq, 'page': page, 'page_size': _pageSize, if (group != 'all') 'group': group, ...d}),
        Services.api.get<Map>('foods/counts/', query: d),
      ]);
      if (req != _freq || !mounted) return;
      setState(() {
        foods = [for (final x in r[0]['results'] as List) x as Map];
        fCount = (r[0]['count'] as num?)?.toInt() ?? foods.length;
        fCounts = r[1];
        fError = null;
        fLoading = false;
      });
    } on ApiError catch (e) {
      if (req != _freq || !mounted) return;
      // A page that no longer exists (the last food on it was deleted): go back one.
      if (e.status == 404 && page > 1) {
        page--;
        _loadFoods();
        return;
      }
      setState(() {
        fError = e;
        fLoading = false;
      });
    }
  }

  void _search(String v, {required bool food}) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (food) {
        fq = v.trim();
        page = 1;
        _loadFoods();
      } else {
        q = v.trim();
        _load();
      }
    });
  }

  void _pickTab(String v) {
    if (v == tab) return;
    setState(() => tab = v);
    context.go(v == 'foods' ? '/nutrition?tab=foods' : '/nutrition');
  }

  // ─────────────────────────────── plan actions

  Future<void> _run(Future<void> Function() f, {String fail = 'Could not do that'}) async {
    try {
      await f();
    } on ApiError catch (e) {
      if (mounted) showToast(context, fail, sub: e.message, kind: ToastKind.err);
    }
    if (mounted) _reload();
  }

  Future<void> _duplicate(Map p) async {
    if (!await confirmDuplicate(context, '"${p['name']}"', body: 'Same meals, no clients. The original stays as it is.')) return;
    await _run(() async {
        final c = await Services.api.post<Map>('meal-plans/${p['id']}/duplicate/');
        if (!mounted) return;
        showToast(context, 'Plan duplicated', sub: 'Same meals, no clients', action: 'Undo', onAction: () => _run(() => Services.api.delete('meal-plans/${c['id']}/')));
      }, fail: 'Could not duplicate it');
  }

  Future<void> _delete(Map p) async {
    int n = 0;
    try {
      n = ((await Services.api.get<Map>('meal-plans/${p['id']}/delete-preview/'))['clients'] as num?)?.toInt() ?? 0;
    } on ApiError catch (_) {}
    if (!mounted) return;
    final ok = await confirmAction(context,
        title: 'Delete this plan?',
        body: '${p['name']} is removed for good${n > 0 ? ' and taken off ${plural(n, 'client')}' : ''}. Meals they already logged stay.',
        confirm: 'Delete',
        danger: true,
        icon: AppIcons.trash);
    if (!ok) return;
    _run(() async {
      await Services.api.delete('meal-plans/${p['id']}/');
      if (!mounted) return;
      showToast(context, 'Plan deleted', sub: '${p['name']}', action: 'Undo', onAction: () => _run(() => Services.api.post('meal-plans/${p['id']}/restore/')));
    }, fail: 'Could not delete it');
  }

  Future<void> _rename(Map p) async {
    final v = await showNameModal(context,
        title: 'Rename meal plan', sub: 'Clients see the new name in their app', label: 'Plan name', initial: '${p['name']}', button: 'Save');
    if (v == null || v == p['name']) return;
    _run(() async {
      await Services.api.patch('meal-plans/${p['id']}/', {'name': v});
      if (mounted) showToast(context, 'Plan renamed', sub: v);
    }, fail: 'Could not rename it');
  }

  void _menu(BuildContext anchor, Map p) {
    final edit = p['can_edit'] == true;
    final n = (p['client_count'] as num?)?.toInt() ?? 0;
    showAppMenu(anchor, width: 240, [
      MenuEntry.header('${p['name']}'),
      MenuEntry('Open in builder', icon: AppIcons.eye, onTap: () => context.go('/nutrition/${p['id']}')),
      if (edit) MenuEntry('Rename', icon: AppIcons.edit, onTap: () => _rename(p)),
      if (_can['assign'] == true) MenuEntry('Assign to clients', icon: AppIcons.clientsAlt, onTap: () => context.go('/nutrition/${p['id']}?open=assign')),
      if (n > 0) MenuEntry('See assigned clients', icon: AppIcons.clientsAlt, sub: plural(n, 'client'), onTap: () => context.go('/nutrition/${p['id']}?open=clients')),
      if (canCreate) MenuEntry(edit ? 'Duplicate' : 'Duplicate to edit', icon: AppIcons.copy, sub: 'Same meals, no clients', onTap: () => _duplicate(p)),
      if (edit) const MenuEntry.separator(),
      if (edit) MenuEntry('Delete', icon: AppIcons.trash, danger: true, onTap: () => _delete(p)),
    ]);
  }

  // ─────────────────────────────── food actions

  Future<void> _openFood([Map? f]) async {
    final saved = await showFoodDrawer(context, food: f, suggestions: (fCounts['unit_suggestions'] as List?) ?? const [], canEdit: canFoods);
    if (saved == null || !mounted) return;
    if (f == null) {
      setState(() {
        group = 'all';
        page = 1;
      });
      if (tab != 'foods') _pickTab('foods');
    }
    _reload();
  }

  Future<void> _dupFood(Map f) async {
    if (!await confirmDuplicate(context, '"${f['name']}"')) return;
    await _run(() async {
        final c = await Services.api.post<Map>('foods/${f['id']}/duplicate/');
        if (!mounted) return;
        setState(() {
          group = 'mine';
          page = 1;
        });
        showToast(context, 'Food duplicated', sub: '${c['name']} is in My foods', action: 'Undo', onAction: () => _run(() => Services.api.delete('foods/${c['id']}/')));
      }, fail: 'Could not duplicate it');
  }

  Future<void> _delFood(Map f) async {
    final used = (f['used_in'] as List?)?.length ?? 0;
    final ok = await confirmAction(context,
        title: 'Delete this food?',
        body: '${f['name']} is removed from My foods.${used > 0 ? ' It stays in the ${plural(used, 'plan')} that use it.' : ''}',
        confirm: 'Delete',
        danger: true,
        icon: AppIcons.trash);
    if (!ok) return;
    _run(() async {
      await Services.api.delete('foods/${f['id']}/');
      if (!mounted) return;
      showToast(context, 'Food deleted', sub: '${f['name']}', action: 'Undo', onAction: () => _run(() => Services.api.post('foods/${f['id']}/restore/')));
    }, fail: 'Could not delete it');
  }

  void _foodMenu(BuildContext anchor, Map f) {
    final builtin = f['source'] == 'builtin';
    showAppMenu(anchor, width: 220, [
      MenuEntry.header('${f['name']}'),
      MenuEntry(canFoods ? 'Edit' : 'Open', icon: canFoods ? AppIcons.edit : AppIcons.eye, onTap: () => _openFood(f)),
      if (canFoods) MenuEntry('Duplicate', icon: AppIcons.copy, onTap: () => _dupFood(f)),
      if (canFoods && !builtin) const MenuEntry.separator(),
      if (canFoods && !builtin) MenuEntry('Delete', icon: AppIcons.trash, danger: true, onTap: () => _delFood(f)),
    ]);
  }

  Future<void> _import() async {
    final done = await showFoodImport(context);
    if (done == true && mounted) {
      setState(() {
        group = 'all';
        fdiet = 'any';
        page = 1;
      });
      _reload();
    }
  }

  // ─────────────────────────────── build

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final plansTab = tab == 'plans';
    return StaffPage(
      onRefresh: () async => _reload(),
      header: PageTop(
        title: 'Nutrition & foods',
        sub: plansTab
            ? 'Master meal plans. Assign one to many clients and note what is different for each.'
            : 'Foods your team uses in meal plans. Clients see team foods first when they search.',
        actions: [
          if (plansTab) ...[
            if (canFoods) AppButton('Create food', icon: AppIcons.bowl, iconOnly: phone, tooltip: phone ? 'Create food' : null, onPressed: () => _openFood()),
            if (canCreate)
              phone ? LibPlusButton(label: 'New plan', onTap: () => showNewMealPlan(context)) : AppButton.primary('New plan', icon: AppIcons.plus, onPressed: () => showNewMealPlan(context)),
          ] else if (canFoods) ...[
            AppButton('Import from Excel', icon: AppIcons.importFile, iconOnly: phone, tooltip: phone ? 'Import from Excel' : null, onPressed: _import),
            phone ? LibPlusButton(label: 'Create food', onTap: () => _openFood()) : AppButton.primary('Create food', icon: AppIcons.plus, onPressed: () => _openFood()),
          ],
        ],
      ),
      children: [
        Transform.translate(
          offset: const Offset(0, -6),
          child: UnderlineTabs<String>(
            pillCounts: true,
            gap: 24,
            items: [
              TabItem('plans', 'Meal plans', count: (counts['all'] as num?)?.toInt() ?? 0),
              TabItem('foods', 'Food library', count: (counts['foods'] as num?)?.toInt() ?? 0),
            ],
            value: tab,
            onChanged: _pickTab,
          ),
        ),
        if (plansTab) ..._plans(phone) else _foods(phone),
      ],
    );
  }

  // ─────────────────────────────── Meal plans tab

  List<Widget> _plans(bool phone) {
    final tabs = SegmentedTabs<String>(
      items: [
        TabItem('all', 'All', count: (counts['all'] as num?)?.toInt() ?? 0),
        for (final d in dietKeys) TabItem(d, dietPlan[d]!, count: (counts[d] as num?)?.toInt() ?? 0),
      ],
      value: diet,
      onChanged: (v) {
        if (v == diet) return;
        setState(() {
          diet = v;
          plans = [];
        });
        _load();
      },
    );
    final search = AppSearchField(placeholder: 'Search plans', icon: AppIcons.search, onChanged: (v) => _search(v, food: false));
    return [
      if (phone) ...[search, SingleChildScrollView(scrollDirection: Axis.horizontal, child: tabs)] else SearchTabsRow(search: search, tabs: tabs),
      if (loading)
        const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)))
      else if (error != null)
        AppCard(child: EmptyState('Could not load meal plans', sub: error!.message, action: AppButton('Try again', onPressed: _load)))
      else if (plans.isEmpty)
        AppCard(
          child: EmptyState(q.isEmpty && diet == 'all' ? 'No meal plans yet' : 'No plans found',
              icon: AppIcons.apple,
              sub: q.isEmpty && diet == 'all' ? 'Make your first master plan and assign it to clients.' : 'Try another diet, or make a new plan.'),
        )
      else ...[
        LayoutBuilder(builder: (context, b) {
          final cols = phone ? 1 : (b.maxWidth / 340).floor().clamp(1, 3);
          final gap = phone ? 10.0 : 16.0;
          final w = (b.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(spacing: gap, runSpacing: gap, children: [
            for (final p in plans) SizedBox(width: w, child: _PlanCard(p, phone: phone, onMenu: (a) => _menu(a, p))),
          ]);
        }),
        if (next != null) Center(child: AppButton(more ? 'Loading…' : 'Show more', onPressed: more ? null : _more)),
      ],
    ];
  }

  // ─────────────────────────────── Food library tab

  Widget _foods(bool phone) {
    final basis = SegmentedTabs<bool>(
      items: const [TabItem(false, 'Per serving'), TabItem(true, 'Per 100 g')],
      value: per100,
      onChanged: (v) => setState(() => per100 = v),
    );
    // AppSelect fills its width: it always needs one when it sits in a Row
    final dietSel = SizedBox(width: 172, child: AppSelect(
      fdiet == 'any' ? 'Any diet' : dietLong[fdiet]!,
      lead: 'Diet',
      entries: [
        for (final d in ['any', ...dietKeys])
          MenuEntry(d == 'any' ? 'Any diet' : dietLong[d]!, lead: DietMark(d), selected: d == fdiet, onTap: () {
            setState(() {
              fdiet = d;
              page = 1;
            });
            _loadFoods();
          }),
      ],
    ));
    final search = AppSearchField(placeholder: 'Search paneer, dal, chicken…', icon: AppIcons.search, onChanged: (v) => _search(v, food: true));
    final groups = [
      ('all', 'All', fCounts['all']),
      for (final g in foodGroups.entries)
        if (!(g.key == 'beverages' || g.key == 'other') || ((fCounts[g.key] as num?) ?? 0) > 0) (g.key, g.value, fCounts[g.key]),
      ('mine', 'My foods', fCounts['mine']),
    ];
    final chips = [
      for (final g in groups)
        _GroupChip(g.$2, count: (g.$3 as num?)?.toInt() ?? 0, on: group == g.$1, onTap: () {
          if (group == g.$1) return;
          setState(() {
            group = g.$1;
            page = 1;
          });
          _loadFoods();
        }),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: phone ? const EdgeInsets.fromLTRB(12, 12, 12, 10) : const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: phone
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
                    search,
                    Row(children: [basis, const Spacer(), dietSel]),
                  ])
                : SearchTabsRow(search: search, tabs: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [basis, dietSel])),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(phone ? 0 : 16, 0, phone ? 0 : 16, 14),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
            // One line that scrolls sideways at every width (Gautam, 22 Oct: chip rows never wrap)
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal, padding: EdgeInsets.symmetric(horizontal: phone ? 12 : 0), child: Row(spacing: 6, children: chips)),
          ),
          if (fLoading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)))
          else if (fError != null)
            EmptyState('Could not load foods', sub: fError!.message, action: AppButton('Try again', onPressed: _loadFoods))
          else if (foods.isEmpty)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(18),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.tableHead, borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.line)),
              child: Text('Nothing found. Remove a filter, or make your own food.', textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)),
            )
          else if (phone)
            _foodList()
          else
            _foodTable(),
        ]),
      ),
      if (!fLoading && fError == null) _FoodPager(page: page, count: fCount, pageSize: _pageSize, onPage: (p) {
        setState(() => page = p);
        _loadFoods();
      }),
    ]);
  }

  static const _cols = <(String, double, bool)>[
    ('Food', 250, false),
    ('', 168, false), // Default serving / Amount
    ('Calories', 78, true),
    ('Protein', 72, true),
    ('Carbs', 64, true),
    ('Fat', 58, true),
    ('Diet', 104, false),
    ('Group', 104, false),
    ('Used in', 176, false),
    ('', 44, false),
  ];

  final _hScroll = ScrollController();

  Widget _foodTable() => LayoutBuilder(builder: (context, box) {
        final min = _cols.fold<double>(0, (a, x) => a + x.$2);
        final extra = (box.maxWidth - min).clamp(0.0, double.infinity);
        final widths = [for (final (i, x) in _cols.indexed) x.$2 + (i == 0 ? extra : 0)];
        final table = SizedBox(
          width: min + extra,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 32,
              decoration: const BoxDecoration(color: AppColors.tableHead, border: Border(bottom: BorderSide(color: AppColors.line))),
              child: Row(children: [
                for (final (i, x) in _cols.indexed)
                  Container(
                    width: widths[i],
                    padding: EdgeInsets.fromLTRB(i == 0 ? 10 : 10, 0, 10, 0),
                    alignment: x.$3 ? Alignment.centerRight : Alignment.centerLeft,
                    child: Text(i == 1 ? (per100 ? 'Amount' : 'Default serving') : x.$1, maxLines: 1, style: AppText.s(12, W.w7, color: AppColors.muted)),
                  ),
              ]),
            ),
            for (final (i, f) in foods.indexed)
              _FoodRow(f, widths: widths, per100: per100, last: i == foods.length - 1, onOpen: () => _openFood(f), onMenu: (a) => _foodMenu(a, f)),
          ]),
        );
        if (box.maxWidth >= min) return table;
        return Scrollbar(
          controller: _hScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(controller: _hScroll, scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(bottom: 8), child: table),
        );
      });

  Widget _foodList() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, f) in foods.indexed) _FoodItem(f, per100: per100, last: i == foods.length - 1, onOpen: () => _openFood(f), onMenu: (a) => _foodMenu(a, f)),
      ]);
}

/// `.nu-pc`: icon, name, "Diet · 4 meals · 10 meal options", ⋯; kcal + Published / Draft; macro bar and legend;
/// meal chips; clients and Edited date.
class _PlanCard extends StatelessWidget {
  const _PlanCard(this.p, {required this.phone, required this.onMenu});
  final Map p;
  final bool phone;
  final void Function(BuildContext anchor) onMenu;

  @override
  Widget build(BuildContext context) {
    final meals = (p['meal_count'] as num?)?.toInt() ?? 0, opts = (p['option_count'] as num?)?.toInt() ?? 0;
    final pub = p['status'] == 'published';
    final pg = nd(p['protein_g']), cg = nd(p['carbs_g']), fg = nd(p['fat_g']);
    return Semantics(
      button: true,
      label: '${p['name']}',
      child: Hover(
        onTap: () => context.go('/nutrition/${p['id']}'),
        builder: (_, h, _) => Container(
          padding: phone ? const EdgeInsets.fromLTRB(16, 16, 16, 14) : const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppRadius.all(AppRadius.card),
            border: Border.all(color: h ? AppColors.line2 : AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
              const IconTile(AppIcons.apple, size: 40, radius: 10, iconSize: 18, bg: AppColors.okBg, fg: AppColors.okText),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                  CutText('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(15, W.w8, color: h ? AppColors.accentText : AppColors.text)),
                  CutText('${dietPlan[p['diet']] ?? ''} · ${plural(meals, 'meal')} · ${plural(opts, 'meal option')}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.muted)),
                ]),
              ),
              Builder(builder: (a) => AppIconButton(AppIcons.dots, tooltip: 'Plan options', small: true, ghost: true, fill: true, onPressed: () => onMenu(a))),
            ]),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.center, spacing: 6, children: [
              Text(kfmt(nd(p['kcal_target'])), style: AppText.s(24, W.w8, ls: -.24, h: 1.1)),
              Padding(padding: const EdgeInsets.only(top: 6), child: Text('kcal / day', style: AppText.s(12.5, W.w6, color: AppColors.muted))),
              const Spacer(),
              if (p['owner'] is Map) ownerTag(p['owner'] as Map),
              AppBadge(pub ? (p['has_unpublished_changes'] == true ? 'Changes not published' : 'Published') : 'Draft', tone: pub && p['has_unpublished_changes'] != true ? Tone.ok : Tone.warn, plain: true),
            ]),
            const SizedBox(height: 10),
            MacroBar(p: pg, c: cg, f: fg),
            const SizedBox(height: 10),
            MacroLegend(p: pg, c: cg, f: fg),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final m in (p['meal_names'] as List? ?? const []))
                Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(6)),
                  child: Center(widthFactor: 1, child: Text('$m', style: AppText.s(12, W.w6, color: AppColors.text2))),
                ),
            ]),
            const SizedBox(height: 12),
            const Divider1(),
            const SizedBox(height: 12),
            _foot(),
          ]),
        ),
      ),
    );
  }

  Widget _foot() {
    final n = (p['client_count'] as num?)?.toInt() ?? 0, cu = (p['custom_count'] as num?)?.toInt() ?? 0;
    final avs = [for (final c in (p['clients'] as List? ?? const [])) c as Map];
    return SizedBox(
      height: 26,
      child: Row(spacing: 8, children: [
        if (n > 0) ...[
          SizedBox(
            height: 26,
            width: 26.0 + 19 * (avs.length - 1).clamp(0, 3),
            child: Stack(children: [
              for (final (i, c) in avs.indexed)
                Positioned(
                  left: 19.0 * i,
                  child: AppTooltip(
                    message: '${c['full_name']}',
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: AppColors.card, shape: BoxShape.circle),
                      child: AppAvatar('${c['full_name']}', size: 22, initials: '${c['initials']}', colors: AppColors.avatarCode('${c['avatar_color'] ?? 'c1'}')),
                    ),
                  ),
                ),
            ]),
          ),
          Text('${plural(n, 'client')}${cu > 0 ? ' · $cu custom' : ''}', style: AppText.s(12.5, W.w7, color: AppColors.text2)),
        ] else ...[
          const AppIcon(AppIcons.clientsAlt, size: 15, color: AppColors.muted),
          Text('Not assigned yet', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
        ],
        Expanded(
          child: CutText(editedOn(p['updated_at']), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
        ),
      ]),
    );
  }
}

/// `.nu-g`: group chip, dark when on.
class _GroupChip extends StatelessWidget {
  const _GroupChip(this.label, {required this.count, required this.on, required this.onTap});
  final String label;
  final int count;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: on,
        label: '$label, $count',
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: on ? AppColors.text : AppColors.card,
              borderRadius: AppRadius.all(15),
              border: Border.all(color: on ? AppColors.text : (h ? AppColors.line2 : AppColors.line)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              Text(label, style: AppText.s(12.5, W.w6, color: on ? AppColors.white : (h ? AppColors.text : AppColors.text2))),
              Text('$count', style: AppText.s(11, W.w7, color: on ? AppColors.nuGroupOnN : AppColors.muted)),
            ]),
          ),
        ),
      );
}

/// What a food row shows: serving label, kcal and macros (per default serving, or per 100 g), sub line.
class _FoodVals {
  _FoodVals(Map f, bool per100) {
    final g = per100 ? 100.0 : servingGrams(f);
    serv = per100 ? '100 g' : servingLabel(f);
    kcal = at(f['kcal'], g).round();
    p = nf(at(f['protein'], g));
    c = nf(at(f['carbs'], g));
    fat = nf(at(f['fat'], g));
    final units = (f['units'] as List?)?.length ?? 0, swaps = (f['swaps'] as List?)?.length ?? 0;
    final src = '${f['source']}';
    sub = [
      if ('${f['brand'] ?? ''}'.isNotEmpty) '${f['brand']}',
      if ('${f['group']}' == 'other' && '${f['category'] ?? ''}'.isNotEmpty) '${f['category']}',
      if (src == 'team') 'Made by your team',
      if (src == 'imported') 'Imported${'${f['source_note'] ?? ''}'.isEmpty ? '' : ' · ${f['source_note']}'}',
      if (units > 1) plural(units, 'unit'),
      if (swaps > 0) plural(swaps, 'swap'),
    ].join(' · ');
    if (sub.isEmpty) sub = 'Built-in food';
  }
  late final String serv, p, c, fat;
  late String sub;
  late final int kcal;
}

/// `.nu-used`: blue pill with the first plan (+N), all plans and meals in the tooltip; or "Not in a plan".
Widget _usedIn(Map f) {
  final used = [for (final x in (f['used_in'] as List? ?? const [])) '$x'];
  if (used.isEmpty) return Text('Not in a plan', style: AppText.s(13.5, W.w4, color: AppColors.muted));
  final tip = [for (final x in (f['used_tip'] as List? ?? const [])) '$x'];
  return AppTooltip(
    message: (tip.isEmpty ? used : tip).join('\n'),
    child: Container(
      height: 22,
      constraints: const BoxConstraints(maxWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: AppRadius.all(6)),
      child: Center(widthFactor: 1, child: CutText('${used.first}${used.length > 1 ? ' +${used.length - 1}' : ''}',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w7, color: AppColors.accentText))),
    ),
  );
}

class _FoodRow extends StatelessWidget {
  const _FoodRow(this.f, {required this.widths, required this.per100, required this.last, required this.onOpen, required this.onMenu});
  final Map f;
  final List<double> widths;
  final bool per100, last;
  final VoidCallback onOpen;
  final void Function(BuildContext) onMenu;

  @override
  Widget build(BuildContext context) {
    final v = _FoodVals(f, per100);
    final body = AppText.s(13.5, W.w4);
    Widget cell(int i, Widget child, {bool right = false}) => Container(
          width: widths[i],
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          child: child,
        );
    Widget t(String s, {bool b = false}) => CutText(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: b ? AppText.s(13.5, W.w7) : body);
    return Hover(
      onTap: onOpen,
      builder: (_, h, _) => Container(
        height: 49,
        decoration: BoxDecoration(
          color: h ? AppColors.hover : null,
          border: last ? null : const Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(children: [
          cell(
            0,
            Row(spacing: 10, children: [
              FoodTile(tone: groupTone('${f['group']}')),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  CutText('${f['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7)),
                  CutText(v.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w4, color: AppColors.muted)),
                ]),
              ),
            ]),
          ),
          cell(1, t(v.serv)),
          cell(2, t('${v.kcal}', b: true), right: true),
          cell(3, t('${v.p} g'), right: true),
          cell(4, t('${v.c} g'), right: true),
          cell(5, t('${v.fat} g'), right: true),
          cell(6, DietLabel('${f['diet']}')),
          cell(7, t('${f['group']}' == 'other' && '${f['category'] ?? ''}'.isNotEmpty ? '${f['category']}' : (foodGroups['${f['group']}'] ?? '${f['group']}'))),
          cell(8, _usedIn(f)),
          SizedBox(
            width: widths[9],
            child: Builder(builder: (a) => AppIconButton(AppIcons.dots, tooltip: 'Food options', small: true, ghost: true, fill: true, onPressed: () => onMenu(a))),
          ),
        ]),
      ),
    );
  }
}

/// Phone row: tile, name + sub, kcal, ⋯; then serving and P / C / F, diet on the right.
class _FoodItem extends StatelessWidget {
  const _FoodItem(this.f, {required this.per100, required this.last, required this.onOpen, required this.onMenu});
  final Map f;
  final bool per100, last;
  final VoidCallback onOpen;
  final void Function(BuildContext) onMenu;

  @override
  Widget build(BuildContext context) {
    final v = _FoodVals(f, per100);
    final cap = AppText.s(12, W.w6, color: AppColors.text2);
    final mute = AppText.s(12, W.w5, color: AppColors.muted);
    return Hover(
      onTap: onOpen,
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: h ? AppColors.hover : null,
          border: last ? null : const Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          FoodTile(tone: groupTone('${f['group']}'), size: 34),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                    CutText('${f['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7)),
                    CutText(v.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: mute),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${v.kcal}', style: AppText.s(13.5, W.w8)),
                    TextSpan(text: ' kcal', style: mute),
                  ])),
                ),
                Builder(builder: (a) => Transform.translate(offset: const Offset(0, -2), child: AppIconButton(AppIcons.dots, tooltip: 'Food options', small: true, ghost: true, fill: true, onPressed: () => onMenu(a)))),
              ]),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Row(spacing: 6, children: [
                  Expanded(
                    child: CutText.rich(
                      TextSpan(children: [
                        TextSpan(text: v.serv, style: cap),
                        TextSpan(text: '   P ${v.p} g   C ${v.c} g   F ${v.fat} g'),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mute,
                    ),
                  ),
                  DietMark('${f['diet']}'),
                  Text(dietShort['${f['diet']}'] ?? '', style: AppText.s(12, W.w5)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// `.pager`: "1–10 of 41 foods" and ‹ ›.
class _FoodPager extends StatelessWidget {
  const _FoodPager({required this.page, required this.count, required this.pageSize, required this.onPage});
  final int page, count, pageSize;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) {
    final pages = count == 0 ? 1 : (count + pageSize - 1) ~/ pageSize;
    final from = count == 0 ? 0 : (page - 1) * pageSize + 1, to = (page * pageSize).clamp(0, count);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(spacing: 6, children: [
        Expanded(child: Text(count == 0 ? '0 foods' : '$from–$to of ${plural(count, 'food')}', style: AppText.s(13, W.w5, color: AppColors.text2))),
        AppIconButton(AppIcons.chevronLeft, tooltip: 'Previous page', small: true, onPressed: page > 1 ? () => onPage(page - 1) : null),
        AppIconButton(AppIcons.chevronRight, tooltip: 'Next page', small: true, onPressed: page < pages ? () => onPage(page + 1) : null),
      ]),
    );
  }
}

/// New meal plan modal: name, diet type, calories per day (1,200–4,000, step 50). Opens the builder.
Future<void> showNewMealPlan(BuildContext context) async {
  final name = TextEditingController();
  var diet = 'veg', kcal = 2000;
  var saving = false;
  final err = ValueNotifier<String?>(null);
  final id = await showAppModal<String>(
    context,
    title: 'New meal plan',
    body: 'Starts with four empty meals. You can change everything.',
    icon: AppIcons.apple,
    width: 480,
    content: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        ValueListenableBuilder(
          valueListenable: err,
          builder: (_, e, _) => meField('Plan name',
              AppTextField(controller: name, placeholder: 'e.g. Cut · Veg', autofocus: !ctx.isPhone, onChanged: (_) => err.value = null), req: true, error: e),
        ),
        meField(
          'Diet type',
          SegmentedTabs<String>(
            expand: true,
            height: 34,
            items: [for (final d in dietKeys) TabItem(d, dietPlan[d]!)],
            value: diet,
            onChanged: (v) => set(() => diet = v),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
          meField('Calories per day', LibStepper(value: kcal, unit: 'kcal', min: 1200, max: 4000, step: 50, onChanged: (v) => set(() => kcal = v))),
          Text('Breakfast, Lunch, Snack and Dinner split this target. Protein, carbs and fat can be set in the builder.',
              style: AppText.s(12, W.w5, color: AppColors.muted)),
        ]),
      ]),
    ),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      StatefulBuilder(
        builder: (bctx, set) => AppButton.primary('Create plan', icon: AppIcons.check, expand: ctx.isPhone, loading: saving, onPressed: () async {
          set(() => saving = true);
          try {
            final p = await Services.api.post<Map>('meal-plans/', {'name': name.text.trim(), 'diet': diet, 'kcal_target': kcal});
            if (ctx.mounted) Navigator.of(ctx).pop('${p['id']}');
          } on ApiError catch (e) {
            set(() => saving = false);
            if (!ctx.mounted) return;
            final f = e.field('name') ?? e.field('kcal_target');
            err.value = e.field('name');
            showToast(ctx, 'Could not create it', sub: f ?? e.message, kind: ToastKind.err);
          }
        }),
      ),
    ],
  );
  disposeLater([name, err]);
  if (id != null && context.mounted) {
    nutritionChanged.value++;
    showToast(context, 'Meal plan created', sub: 'Add foods to each meal');
    context.go('/nutrition/$id');
  }
}
