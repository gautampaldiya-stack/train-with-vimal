import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../home/home_model.dart' show inNum, mealTime;
import '../train/train_parts.dart' show TwoTabs;
import 'food_model.dart';
import 'food_parts.dart';
import 'food_sheets.dart' show fdError;

/// Log food (boards `ClientFoodLog` phone and `ClientFoodLogWeb`, route `/food/log?meal=`): search the coach's
/// foods and yours, + adds one to the picked meal at once (through the outbox, so it works offline). Quick add
/// takes just the numbers; Create custom food saves one to My foods. Every number can be typed.
class FoodLogScreen extends StatefulWidget {
  const FoodLogScreen({super.key, this.meal});
  final String? meal;
  @override
  State<FoodLogScreen> createState() => _FoodLogScreenState();
}

/// A food from `me/foods/`: kcal and macros per 100 g, its units and the default serving.
class FdFood {
  FdFood(this.j);
  final Map<String, dynamic> j;
  String get id => '${j['id']}';
  String get name => '${j['name']}';
  bool get mine => j['mine'] == true;
  List<double> get per100 => [for (final k in ['kcal', 'protein', 'carbs', 'fat']) ((j[k] as num?) ?? 0).toDouble()];
  List<({int id, String name, double grams})> get units => [
    for (final u in (j['units'] as List? ?? [])) (id: (u['id'] as num).toInt(), name: '${u['name']}', grams: ((u['grams'] as num?) ?? 0).toDouble()),
  ];
  ({int id, String name, double grams})? get unit {
    final d = j['default_unit'] as Map?;
    return d == null ? null : (id: (d['id'] as num).toInt(), name: '${d['name']}', grams: ((d['grams'] as num?) ?? 0).toDouble());
  }

  double get qty => ((j['default_quantity'] as num?) ?? 1).toDouble();

  /// Grams of [q] of [u] (null = grams).
  double grams(({int id, String name, double grams})? u, double q) => u == null ? q : q * u.grams;
  List<double> mac(double grams) => [for (final v in per100) v * grams / 100];
  double get defGrams => unit == null ? 100 : grams(unit, qty);
  String get defAmt => unit == null ? '100 g' : amtOf(unit!.name, qty);
  String get line {
    final m = mac(defGrams);
    return '$defAmt · ${inNum(m[0])} kcal · ${m[1].round()} g P';
  }
}

class _FoodLogScreenState extends State<FoodLogScreen> {
  final day = FoodController();
  final _q = TextEditingController();
  Timer? _debounce;
  String _tab = 'All';
  bool _all = false;
  String? _meal;
  bool _off = false;
  String _why = '';

  // The list
  final List<FdFood> _foods = [];
  int _count = 0, _page = 1, _seq = 0;
  bool _hasNext = false, _loading = true, _loadingMore = false;
  String? _error;
  int _libCount = 0; // "40 foods in Aman's library and yours"

  // Added while offline (not in the day view yet)
  final List<FEntry> _pending = [];

  // Quick add
  final _qa = [0.0, 0.0, 0.0, 0.0];
  static const _qaSteps = [25.0, 1.0, 1.0, 1.0];
  static const _qaLabels = ['Calories', 'Protein (g)', 'Carbs (g)', 'Fat (g)'];

  @override
  void initState() {
    super.initState();
    _meal = widget.meal;
    day.addListener(_onDay);
    day.start();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    day.removeListener(_onDay);
    day.dispose();
    _q.dispose();
    super.dispose();
  }

  void _onDay() {
    final d = day.data;
    if (d == null) return;
    // The server has caught up with the foods added offline.
    _pending.removeWhere((p) => d.log.any((e) => e.name == p.name && e.mealName == p.mealName && (e.time.difference(p.time).inSeconds).abs() < 120));
    if (mounted) setState(() {});
  }

  // ─────────────────────────────── Meals

  List<String> get _mealNames {
    final ms = day.data?.meals ?? const <FMeal>[];
    if (ms.isEmpty) return const ['Breakfast', 'Lunch', 'Snack', 'Dinner'];
    return [for (final m in ms) m.name];
  }

  FMeal? _mealOf(String name) => day.data?.meals.where((m) => m.name == name).firstOrNull;

  String get meal {
    if (_meal != null && _mealNames.contains(_meal)) return _meal!;
    final ms = day.data?.meals ?? const <FMeal>[];
    final open = ms.where((m) => m.open).firstOrNull;
    return open?.name ?? (ms.isNotEmpty ? ms.last.name : (_meal ?? 'Snack'));
  }

  /// Foods added to [name] today outside the plan's own rows.
  List<FEntry> _added(String name) => [
    for (final e in day.data?.log ?? const <FEntry>[])
      if (e.mealName == name && !(e.fromPlan && e.meal != null)) e,
    for (final e in _pending)
      if (e.mealName == name) e,
  ];

  // ─────────────────────────────── Search

  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      _all = false;
      _search();
    });
    setState(() {});
  }

  void _setQuery(String q) {
    _q.text = q;
    _q.selection = TextSelection.collapsed(offset: q.length);
    _all = false;
    _search();
  }

  Future<void> _search({bool more = false}) async {
    final n = ++_seq;
    final q = _q.text.trim();
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      if (_tab == 'Recent') {
        final r = await Services.api.get<List<dynamic>>('me/foods/recent/');
        if (n != _seq) return;
        final all = [for (final x in r) FdFood((x as Map).cast<String, dynamic>())];
        final hits = q.isEmpty ? all : all.where((f) => f.name.toLowerCase().contains(q.toLowerCase())).toList();
        _foods
          ..clear()
          ..addAll(hits);
        _count = hits.length;
        _hasNext = false;
      } else {
        final page = more ? _page + 1 : 1;
        final r = await Services.api.get<Map<String, dynamic>>('me/foods/', query: {
          if (q.isNotEmpty) 'search': q,
          if (_tab == 'My foods') 'group': 'mine',
          'page': page,
        });
        if (n != _seq) return;
        final list = [for (final x in (r['results'] as List? ?? [])) FdFood((x as Map).cast<String, dynamic>())];
        if (!more) _foods.clear();
        _foods.addAll(list);
        _page = page;
        _count = (r['count'] as num?)?.toInt() ?? _foods.length;
        _hasNext = r['next'] != null;
        if (_tab == 'All' && q.isEmpty) _libCount = _count;
      }
      _error = null;
    } on ApiError catch (e) {
      if (n != _seq) return;
      _error = e.offline ? 'You are offline. Search works again once you are back online. Quick add works now.' : e.message;
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  // ─────────────────────────────── Writes

  Future<void> _log(Map<String, dynamic> body, {required String title, required String sub}) async {
    final m = meal;
    final full = {'meal_name': m, 'off_plan': _off, 'reason': _off ? _why : '', 'date': ymd(day.today), ...body};
    try {
      final send = {...full}..removeWhere((k, _) => k.startsWith('_'));
      final r = await Services.outbox.enqueue('POST', 'me/food-log/', send, tag: 'food:log:add');
      if (!mounted) return;
      FEntry? added;
      if (r is Map) {
        final j = r.cast<String, dynamic>();
        added = FEntry({...j, 'time': j['logged_at'], 'unit': j['unit_name']});
      } else {
        // Offline: show it now, it is sent when the phone is back online.
        added = FEntry({
          'id': 'local-${DateTime.now().microsecondsSinceEpoch}',
          'time': DateTime.now().toUtc().toIso8601String(),
          'meal_name': m,
          'name': body['name'] ?? title.replaceFirst(RegExp(r' added to .*$'), ''),
          'quantity': body['quantity'] ?? 1,
          'unit': body['unit_name'] ?? 'serving',
          'kcal': body['_kcal'] ?? body['kcal'] ?? 0,
          'protein': body['_protein'] ?? body['protein'] ?? 0,
          'carbs': 0,
          'fat': 0,
          'source': _off ? 'off_plan' : 'quick_add',
          'reason': _off ? _why : '',
          'food': body['food'],
        });
        _pending.add(added);
      }
      setState(() {});
      final e = added;
      showToast(context, title, sub: sub, kind: ToastKind.ok, action: 'Undo', onAction: () => _remove(e, toast: false));
      await day.load();
    } on ApiError catch (e) {
      if (mounted) fdError(context, e);
    }
  }

  Future<void> _remove(FEntry e, {bool toast = true}) async {
    _pending.remove(e);
    day.data?.log.remove(e);
    setState(() {});
    if (!e.id.startsWith('local-')) {
      try {
        await Services.outbox.enqueue('DELETE', 'me/food-log/${e.id}/', {}, tag: 'food:log:remove');
      } on ApiError {
        // Already gone.
      }
    }
    if (toast && mounted) {
      showToast(context, '${e.name} removed', sub: 'Taken out of ${e.mealName}', kind: ToastKind.del, action: 'Undo', onAction: () {
        Services.outbox.enqueue('POST', 'me/food-log/', {...e.again(), 'date': ymd(day.today)}, tag: 'food:log:add').then((_) => day.load(), onError: (_) {});
      });
    }
    await day.load();
  }

  void _add(FdFood f, {({int id, String name, double grams})? unit, double? qty, bool useDefault = true}) {
    final u = useDefault ? f.unit : unit;
    final q = useDefault ? (f.unit == null ? 100.0 : f.qty) : qty!;
    final g = f.grams(u, q);
    final m = f.mac(g);
    final amt = u == null ? amtOf('g', q) : amtOf(u.name, q);
    _log(
      {'food': f.id, 'quantity': q, if (u != null) 'unit': u.id, 'name': f.name, '_kcal': m[0].round(), '_protein': m[1], 'unit_name': u?.name ?? 'g'},
      title: '${f.name} added to $meal',
      sub: '$amt · ${inNum(m[0])} kcal${_off ? ' · marked off-plan' : ''}',
    );
  }

  void _toggle(FdFood f) {
    final has = _added(meal).where((e) => '${e.j['food']}' == f.id).lastOrNull;
    if (has != null) {
      _remove(has);
    } else {
      _add(f);
    }
  }

  void _quickAdd() {
    if (_qa[0] <= 0) {
      showToast(context, 'Enter the calories first', sub: 'Protein, carbs and fat are optional', kind: ToastKind.warn);
      return;
    }
    final v = [..._qa];
    _log(
      {'name': 'Quick add', 'kcal': v[0].round(), 'protein': v[1], 'carbs': v[2], 'fat': v[3]},
      title: 'Quick add · ${inNum(v[0])} kcal to $meal',
      sub: '${v[1].round()} g protein',
    );
    setState(() => _qa.setAll(0, [0, 0, 0, 0]));
  }

  // ─────────────────────────────── Build

  @override
  Widget build(BuildContext context) => context.isPhone ? _phone() : _web();

  Widget _phone() => SingleChildScrollView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      _top(),
      ..._searchPart(),
      _addedCard(),
      _exCard(),
    ]),
  );

  /// Web: the header, search and tabs stay put; only the food list (and the right column) scroll.
  Widget _web() => CaWeb(
    web: true,
    child: LayoutBuilder(builder: (context, page) {
      final inner = (page.maxWidth - 64).clamp(0.0, 1080.0);
      final two = inner >= 720 && page.maxHeight >= 520;
      Widget frame(Widget child, {double bottom = 72}) => Padding(
        padding: EdgeInsets.fromLTRB(32, 32, 32, bottom),
        child: Align(alignment: Alignment.topCenter, child: SizedBox(width: inner, child: child)),
      );
      if (!two) {
        return SingleChildScrollView(
          child: frame(Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            _top(),
            ..._searchPart(),
            _addedCard(),
            _exCard(),
          ])),
        );
      }
      return frame(
        bottom: 24,
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _top(),
          const SizedBox(height: 16),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
              Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: _searchPart(scroll: true))),
              Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [_addedCard(), _exCard()]),
                ),
              ),
            ]),
          ),
        ]),
      );
    }),
  );

  Widget _top() => Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
    Padding(padding: const EdgeInsets.only(top: 2), child: CaIconBtn(AppIcons.chevronLeft, tooltip: 'Back to meal plan', onTap: () => context.go('/food'))),
    Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Log food', style: AppText.s(12, W.w6, color: AppColors.muted)),
        Builder(
          builder: (bc) => Semantics(
            button: true,
            label: 'Change the meal',
            child: Hover(
              onTap: () => _mealMenu(bc),
              builder: (_, h, _) => Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                Flexible(child: Text('Add to $meal', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(20, W.w8, color: h ? AppColors.accentText : AppColors.text))),
                const AppIcon(AppIcons.chevronDown, size: 16, color: AppColors.muted),
              ]),
            ),
          ),
        ),
      ]),
    ),
  ]);

  String _mealSub(String name) {
    final add = _added(name);
    if (add.isNotEmpty) return '${inNum(add.fold(0, (a, e) => a + e.kcal))} kcal added now';
    final m = _mealOf(name);
    return m == null ? 'Nothing added yet' : 'Plan: ${m.foods}';
  }

  Future<void> _mealMenu(BuildContext anchor) async {
    final names = _mealNames;
    String label(String n) {
      final m = _mealOf(n);
      return m == null ? n : '$n · ${mealTime(m.timeRaw)}';
    }

    if (anchor.isPhone) {
      await showAppSheet(
        context,
        title: 'Add to',
        builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, n) in names.indexed) _mealItem(ctx, label(n), _mealSub(n), n == meal, first: i == 0, () => setState(() => _meal = n)),
        ]),
      );
      return;
    }
    final box = anchor.findRenderObject() as RenderBox;
    final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox;
    final at = box.localToGlobal(Offset.zero, ancestor: overlay);
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'menu',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 90),
      transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      pageBuilder: (ctx, _, _) => Stack(children: [
        Positioned(
          left: at.dx.clamp(8, overlay.size.width - 308),
          top: at.dy + box.size.height + 6,
          width: 300,
          child: Material(
            color: Colors.transparent,
            child: CaWeb(
              web: true,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.menu), border: Border.all(color: AppColors.line), boxShadow: AppShadows.menu),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                    child: Text('ADD TO', style: AppText.s(11, W.w7, color: AppColors.muted, ls: .55)),
                  ),
                  for (final n in names) _mealItem(ctx, label(n), _mealSub(n), n == meal, menu: true, () => setState(() => _meal = n)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _mealItem(BuildContext ctx, String title, String sub, bool on, VoidCallback pick, {bool menu = false, bool first = false}) => Semantics(
    button: true,
    selected: on,
    child: Hover(
      onTap: () {
        Navigator.of(ctx).pop();
        pick();
      },
      builder: (_, h, _) => Container(
        padding: EdgeInsets.symmetric(horizontal: menu ? 10 : 4, vertical: menu ? 7 : 10),
        decoration: BoxDecoration(
          color: menu && h ? AppColors.sub : null,
          borderRadius: menu ? AppRadius.all(AppRadius.item) : null,
          border: menu || first ? null : const Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(spacing: 10, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppText.s(menu ? 13.5 : 14.5, on ? W.w7 : W.w6)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w5, color: AppColors.muted)),
            ]),
          ),
          if (on) const AppIcon(AppIcons.check, size: 15, color: AppColors.accent, stroke: 2.2),
        ]),
      ),
    ),
  );

  // ─────────────────────────────── Search, tabs, list

  List<Widget> _searchPart({bool scroll = false}) {
    final q = _q.text.trim();
    return [
      Container(
        height: 44,
        padding: const EdgeInsets.only(left: 12, right: 6),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
        child: Row(spacing: 8, children: [
          const AppIcon(AppIcons.search, size: 17, color: AppColors.muted),
          Expanded(
            child: TextField(
              controller: _q,
              autofocus: !context.isPhone,
              onChanged: _onQuery,
              textInputAction: TextInputAction.search,
              style: AppText.s(13.5, W.w6),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search food, e.g. paneer, dal, roti',
                hintStyle: AppText.s(13.5, W.w4, color: AppColors.muted),
              ),
            ),
          ),
          if (q.isNotEmpty) CaIconBtn(AppIcons.close, tooltip: 'Clear search', onTap: () => _setQuery('')),
        ]),
      ),
      if (q.isEmpty)
        Pull(
          top: 4,
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 6, children: [
            Text('Try', style: AppText.s(12, W.w6, color: AppColors.muted)),
            for (final t in const ['paneer', 'dal', 'roti', 'rajma']) FdChip(t, height: 26, onTap: () => _setQuery(t)),
          ]),
        ),
      TwoTabs(
        fit: !context.isPhone,
        labels: const ['All', 'Recent', 'My foods'],
        index: const ['All', 'Recent', 'My foods'].indexOf(_tab),
        onPick: (i) {
          _tab = const ['All', 'Recent', 'My foods'][i];
          _all = false;
          _search();
        },
      ),
      if (scroll) Flexible(child: _listCard(scroll: true)) else _listCard(),
    ];
  }

  Widget _listCard({bool scroll = false}) {
    final q = _q.text.trim();
    final coach = day.data?.coach ?? 'your coach';
    final String cnt;
    if (q.isNotEmpty) {
      cnt = '$_count ${_count == 1 ? 'result' : 'results'} for “$q”';
    } else if (_tab == 'Recent') {
      cnt = 'Foods you logged lately';
    } else if (_tab == 'My foods') {
      cnt = 'Foods you created';
    } else {
      cnt = '${_libCount > 0 ? _libCount : _count} foods in $coach’s library and yours';
    }
    // In the scrolling web list every loaded food shows; elsewhere the first 8, then Show all.
    final showAll = scroll || _all || q.isNotEmpty;
    final rows = showAll ? _foods : _foods.take(8).toList();
    final added = _added(meal);
    final body = <Widget>[
        if (_loading && _foods.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))),
          )
        else if (_error != null)
          Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!, textAlign: TextAlign.center, style: AppText.s(13, W.w4, color: AppColors.muted)))
        else if (_foods.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              q.isNotEmpty ? 'Nothing found. Try Quick add or create a custom food.' : (_tab == 'My foods' ? 'You have not created a food yet.' : 'No foods here yet.'),
              textAlign: TextAlign.center,
              style: AppText.s(13, W.w4, color: AppColors.muted),
            ),
          )
        else
          for (final f in rows) _foodRow(f, added.any((e) => '${e.j['food']}' == f.id)),
        if (!showAll && _count > 8 && _error == null)
          _more('Show all $_count foods', () => setState(() => _all = true))
        else if (showAll && _hasNext && _error == null)
          _more(_loadingMore ? 'Loading…' : 'Show more foods', _loadingMore ? null : () => _search(more: true)),
    ];
    final head = Padding(padding: const EdgeInsets.fromLTRB(0, 8, 0, 4), child: Text(cnt, style: AppText.s(11.5, W.w7, color: AppColors.muted)));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: scroll
          ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              head,
              Flexible(
                child: SingleChildScrollView(
                  key: PageStorageKey('fl-$_tab'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
                ),
              ),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [head, ...body]),
    );
  }

  Widget _more(String label, VoidCallback? onTap) => Hover(
    onTap: onTap,
    builder: (_, h, _) => Container(
      height: 38,
      alignment: Alignment.center,
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      child: Text(label, style: AppText.s(13, W.w7, color: h ? AppColors.accentHover : AppColors.accentText)),
    ),
  );

  Widget _foodRow(FdFood f, bool on) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
    child: Row(spacing: 10, children: [
      Expanded(
        child: Semantics(
          button: true,
          label: 'Pick the amount of ${f.name}',
          child: Hover(
            onTap: () => _portion(f),
            builder: (_, h, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Row(children: [
                Flexible(child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(14, W.w7, color: h ? AppColors.accentText : AppColors.text))),
                if (f.mine) fdTag('Mine'),
              ]),
              Text(f.line, style: AppText.s(12, W.w4, color: AppColors.muted)),
            ]),
          ),
        ),
      ),
      Semantics(
        button: true,
        label: on ? 'Remove ${f.name}' : 'Add ${f.name}',
        child: Hover(
          onTap: () => _toggle(f),
          builder: (_, h, _) => AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.okSolid : (h ? AppColors.accentSoft : AppColors.white),
              shape: BoxShape.circle,
              border: Border.all(color: on ? AppColors.okSolid : (h ? AppColors.accent : AppColors.line)),
            ),
            child: AppIcon(on ? AppIcons.check : AppIcons.plus, size: 16, color: on ? AppColors.white : AppColors.accent, stroke: on ? 2.6 : 1.8),
          ),
        ),
      ),
    ]),
  );

  // ─────────────────────────────── Added to the meal

  Widget _addedCard() {
    final m = meal, pm = _mealOf(m);
    final add = _added(m);
    final k = add.fold(0, (a, e) => a + e.kcal);
    return ChCardLite(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(pm == null ? m : '$m · ${mealTime(pm.timeRaw)}', style: AppText.s(15, W.w8)),
            if (pm != null) Text('Plan: ${pm.foods} · ${inNum(pm.kcal)} kcal', style: AppText.s(12, W.w4, color: AppColors.muted)),
          ]),
        ),
        if (add.isNotEmpty) Text('+${inNum(k)} kcal', style: AppText.s(14, W.w8, color: AppColors.accentText)),
      ]),
      if (add.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text('Nothing added yet. Tap + on a food.', textAlign: TextAlign.center, style: AppText.s(13, W.w4, color: AppColors.muted)),
        )
      else ...[
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final e in add)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
              child: Row(spacing: 8, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7))),
                      if (e.source == 'off_plan') fdTag('Off-plan', amber: true),
                    ]),
                    Text(
                      '${e.amount} · ${inNum(e.kcal)} kcal · ${e.protein.round()} g P${e.reason.isEmpty ? '' : ' · ${e.reason}'}',
                      style: AppText.s(12, W.w4, color: AppColors.muted),
                    ),
                  ]),
                ),
                CaIconBtn(AppIcons.close, tooltip: 'Remove', onTap: () => _remove(e)),
              ]),
            ),
        ]),
        CaButton('Done · back to meal plan', onPressed: () => context.go('/food')),
      ],
    ]);
  }

  // ─────────────────────────────── Can't find the exact food?

  Widget _exCard() => ChCardLite(gap: 10, children: [
    Text('Can’t find the exact food?', style: AppText.s(15, W.w8)),
    Pull(top: -4, child: fdCap('Quick add the numbers, or save a custom food for next time.')),
    _boxes(_qa, (k, v) => setState(() => _qa[k] = v)),
    Row(spacing: 8, children: [
      Expanded(child: LayoutBuilder(builder: (_, b) => fdBtn('Create custom food', _customFood, icon: b.maxWidth >= 178 ? AppIcons.plus : null))),
      Expanded(child: fdBtn('Quick add', _quickAdd, kind: CaBtnKind.dark)),
    ]),
    Semantics(
      button: true,
      checked: _off,
      child: Hover(
        onTap: () => setState(() {
          _off = !_off;
          _why = '';
        }),
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.only(top: 10),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: CaCheckBox(_off)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text('Off-plan meal', style: AppText.s(13.5, W.w7)),
                Text('Party or eating out: what you add is marked off-plan for ${day.data?.coach ?? 'your coach'}.', style: AppText.s(12, W.w4, color: AppColors.muted)),
              ]),
            ),
          ]),
        ),
      ),
    ),
    if (_off)
      Padding(
        padding: const EdgeInsets.only(left: 28),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in const ['Ate out', 'Party', 'Travelling'])
            FdChip(t, height: 28, amber: true, on: _why == t, onTap: () => setState(() => _why = _why == t ? '' : t)),
        ]),
      ),
  ]);

  /// `fl-qs`: Calories / Protein / Carbs / Fat, each with − + and a number you can type.
  Widget _boxes(List<double> v, void Function(int, double) set) => LayoutBuilder(builder: (_, b) {
    final w = (b.maxWidth - 8) / 2;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (var k = 0; k < 4; k++)
        Container(
          width: w,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: AppColors.caWebBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
            Text(_qaLabels[k], style: AppText.s(11.5, W.w7, color: AppColors.muted)),
            NumStepper(
              value: v[k],
              step: _qaSteps[k],
              max: k == 0 ? 10000 : 1000,
              spread: true,
              btn: 28,
              decimals: k != 0,
              name: _qaLabels[k].toLowerCase(),
              label: (x) => x == x.roundToDouble() ? '${x.round()}' : '${(x * 10).round() / 10}',
              onChanged: (x) => set(k, x),
            ),
          ]),
        ),
    ]);
  });

  // ─────────────────────────────── Portion sheet

  void _portion(FdFood f) {
    final st = ValueNotifier<({({int id, String name, double grams})? unit, double q})>((unit: f.unit, q: f.unit == null ? 100 : f.qty));
    showAppSheet(
      context,
      listen: st,
      title: f.name,
      sub: 'Default ${f.defAmt} · ${inNum(f.mac(f.defGrams)[0])} kcal',
      webWidth: 460,
      footerStretch: true,
      builder: (_) {
        final s = st.value;
        final g = f.grams(s.unit, s.q);
        final m = f.mac(g);
        final step = s.unit == null ? 10.0 : .5;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(spacing: 2, children: [
              NumStepper(
                value: s.q,
                step: step,
                min: step,
                max: s.unit == null ? 5000 : 100,
                big: true,
                decimals: s.unit != null,
                name: 'amount',
                label: (q) => s.unit == null ? amtOf('g', q) : amtOf(s.unit!.name, q),
                onChanged: (q) => st.value = (unit: s.unit, q: q),
              ),
              SizedBox(height: 16, child: Text(s.unit == null ? '' : '= ${g.round()} g', style: AppText.s(12, W.w6, color: AppColors.muted))),
            ]),
          ),
          Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
            for (final u in [null, ...f.units])
              FdChip(u == null ? 'grams' : u.name.replaceFirst(RegExp(r'^1 '), ''), on: s.unit?.id == u?.id, onTap: () {
                if (s.unit?.id == u?.id) return;
                final nq = u == null ? ((g / 10).round() * 10).toDouble().clamp(10.0, 5000.0) : ((g / u.grams * 2).round() / 2).clamp(.5, 100.0);
                st.value = (unit: u, q: nq.toDouble());
              }),
          ]),
          Row(spacing: 6, children: [
            for (final (l, v) in [('kcal', inNum(m[0])), ('Protein', '${m[1].round()} g'), ('Carbs', '${m[2].round()} g'), ('Fat', '${m[3].round()} g')])
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  decoration: BoxDecoration(color: AppColors.caWebBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
                  child: Column(children: [
                    Text(v, style: AppText.s(15, W.w8)),
                    Text(l, style: AppText.s(11, W.w6, color: AppColors.muted)),
                  ]),
                ),
              ),
          ]),
        ]);
      },
      footer: (ctx) => [
        CaButton('Add to $meal', onPressed: () {
          Navigator.of(ctx).pop();
          final s = st.value;
          _add(f, unit: s.unit, qty: s.q, useDefault: false);
        }),
      ],
    );
  }

  // ─────────────────────────────── Create custom food

  void _customFood() {
    final name = TextEditingController(), serving = TextEditingController(text: '1 serving');
    final v = ValueNotifier<List<double>>([0, 0, 0, 0]);
    final err = ValueNotifier<String?>(null);
    final busy = ValueNotifier<bool>(false);
    showAppSheet(
      context,
      listen: Listenable.merge([v, err, busy]),
      title: 'Create custom food',
      sub: 'Saved to My foods, only you see it',
      webWidth: 480,
      footerStretch: true,
      builder: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        CaField(label: 'Name', controller: name, hint: 'e.g. Mom’s veg upma', error: err.value, autofocus: true, action: TextInputAction.next),
        CaField(label: 'Serving', controller: serving, hint: 'e.g. 1 katori'),
        _boxes(v.value, (k, x) => v.value = [for (var i = 0; i < 4; i++) i == k ? x : v.value[i]]),
      ]),
      footer: (ctx) => [
        Row(spacing: 8, children: [
          Expanded(child: CaButton('Cancel', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop())),
          Expanded(
            child: CaButton('Save food', loading: busy.value, onPressed: () async {
              final n = name.text.trim();
              if (n.isEmpty) {
                err.value = 'Enter the food’s name';
                return;
              }
              if (v.value[0] <= 0) {
                showToast(context, 'Enter the calories first', sub: 'Protein, carbs and fat are optional', kind: ToastKind.warn);
                return;
              }
              busy.value = true;
              try {
                await Services.api.post<Map<String, dynamic>>('me/foods/', {
                  'name': n,
                  'serving': serving.text.trim().isEmpty ? '1 serving' : serving.text.trim(),
                  'kcal': v.value[0].round(),
                  'protein': v.value[1],
                  'carbs': v.value[2],
                  'fat': v.value[3],
                });
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (!mounted) return;
                _q.text = '';
                _tab = 'My foods';
                _all = false;
                _search();
                showToast(context, '$n saved to My foods', sub: 'Tap + to log it', kind: ToastKind.ok);
              } on ApiError catch (e) {
                busy.value = false;
                if (e.fields.containsKey('name')) {
                  err.value = '${e.fields['name']}';
                } else if (mounted) {
                  showToast(context, e.offline ? 'You are offline' : 'Could not save this food',
                      sub: e.offline ? 'Use Quick add for now, or save it when you are back online' : e.message, kind: ToastKind.err);
                }
              }
            }),
          ),
        ]),
      ],
    ).whenComplete(() {
      name.dispose();
      serving.dispose();
    });
  }
}

/// `ca-card` with 12/14 padding (`fl-added`, `fl-ex`).
class ChCardLite extends StatelessWidget {
  const ChCardLite({super.key, required this.children, this.gap = 8});
  final List<Widget> children;
  final double gap;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: gap, children: children),
  );
}
