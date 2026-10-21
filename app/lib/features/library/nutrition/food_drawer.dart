import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import '../../../core/widgets/tabs.dart';
import '../../../core/widgets/tooltip.dart';
import '../../trainer/client_profile/cp_plans.dart' show CpInfo;
import '../lib_common.dart';
import 'nu_common.dart';

/// Where a food's numbers come from (`source_note`); "" = the team typed them.
const _sources = {'': 'Your team', 'Pack label': 'Pack label', 'IFCT': 'IFCT', 'USDA': 'USDA'};

/// Create food / Edit food drawer (board `Nutrition` → food drawer): name, brand, diet, group, source, serving units
/// with the default serving, nutrition per 100 g or per serving (saved per 100 g), more nutrients, swap group,
/// the plans that use it and what a client sees in search. Returns the saved food, or null.
Future<Map?> showFoodDrawer(BuildContext context, {Map? food, required List suggestions, bool canEdit = true}) async {
  Map? full = food;
  if (food != null) {
    // The list row has everything but fresh numbers may matter (another tab edited it): load it once.
    try {
      full = await Services.api.get<Map>('foods/${food['id']}/');
    } on ApiError catch (_) {}
  }
  if (!context.mounted) return null;
  final key = GlobalKey<_FoodFormState>();
  final saved = await showAppDrawer<Map>(
    context,
    title: food == null ? 'Create food' : 'Edit food',
    sub: food == null ? 'For the team food library' : '${food['name']} · ${servingLabel(full ?? food)}',
    icon: AppIcons.bowl,
    builder: (ctx) => _FoodForm(key: key, food: full, suggestions: suggestions, canEdit: canEdit),
    footer: (ctx) => [
      if (!ctx.isPhone)
        Expanded(
          child: Text(canEdit ? 'Saved to the team food library' : 'Your access does not include changing foods',
              style: AppText.s(12.5, W.w5, color: AppColors.muted)),
        ),
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      if (canEdit)
        _SaveButton(label: food == null ? 'Save to library' : 'Save changes', expand: ctx.isPhone, onSave: () async {
          final r = await key.currentState?.save();
          if (r != null && ctx.mounted) Navigator.of(ctx).pop(r);
        }),
    ],
  );
  if (saved != null && context.mounted) {
    final used = (food?['used_in'] as List?)?.length ?? 0;
    showToast(
      context,
      food == null ? 'Saved to the food library' : 'Food updated',
      sub: food == null ? '${saved['name']} · in ${foodGroups[saved['group']] ?? 'the library'}' : (used > 0 ? 'The ${plural(used, 'plan')} using it are updated' : '${saved['name']}'),
    );
  }
  return saved;
}

class _SaveButton extends StatefulWidget {
  const _SaveButton({required this.label, required this.onSave, this.expand = false});
  final String label;
  final Future<void> Function() onSave;
  final bool expand;
  @override
  State<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<_SaveButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => AppButton.primary(widget.label, icon: AppIcons.check, expand: widget.expand, loading: busy, onPressed: () async {
        setState(() => busy = true);
        await widget.onSave();
        if (mounted) setState(() => busy = false);
      });
}

class _Unit {
  _Unit(this.name, this.grams, {this.id}) : ctl = TextEditingController(text: name);
  final int? id;
  String name;
  double grams;
  final TextEditingController ctl;
}

class _FoodForm extends StatefulWidget {
  const _FoodForm({super.key, required this.food, required this.suggestions, required this.canEdit});
  final Map? food;
  final List suggestions;
  final bool canEdit;
  @override
  State<_FoodForm> createState() => _FoodFormState();
}

class _FoodFormState extends State<_FoodForm> {
  late final Map? f = widget.food;
  late final name = TextEditingController(text: '${f?['name'] ?? ''}');
  late final brand = TextEditingController(text: '${f?['brand'] ?? ''}');
  late String diet = '${f?['diet'] ?? 'veg'}', group = '${f?['group'] ?? 'other'}', source = _sources.containsKey(f?['source_note']) ? '${f?['source_note'] ?? ''}' : '';
  late final String sourceExtra = _sources.containsKey(f?['source_note']) ? '' : '${f?['source_note'] ?? ''}';

  late final List<_Unit> units = [
    for (final u in (f?['units'] as List? ?? const [])) _Unit('${(u as Map)['name']}', nd(u['grams']), id: (u['id'] as num?)?.toInt()),
    if (f == null) _Unit('1 plate', 180),
  ];

  /// -1 = grams.
  late int def = () {
    if (f == null) return 0;
    final id = (f!['default_unit'] as Map?)?['id'];
    return id == null ? -1 : units.indexWhere((u) => u.id == id);
  }();
  late double qty = nd(f?['default_quantity'] ?? 1);

  // Per 100 g.
  static const _macroKeys = ['kcal', 'protein', 'carbs', 'fat', 'fibre'];
  static const _minKeys = ['sodium_mg', 'iron_mg', 'calcium_mg', 'potassium_mg'];
  late final Map<String, double?> per100 = {
    for (final k in [..._macroKeys, ..._minKeys]) k: f?[k] == null ? null : nd(f![k]),
  };
  late final ctl = {for (final k in [..._macroKeys, ..._minKeys]) k: TextEditingController()};
  bool perServing = false;

  late List<String> swaps = [for (final x in (f?['swaps'] as List? ?? const [])) '$x'];
  final swapNames = <String, String>{};
  List<Map> usedIn = [];
  Map<String, String> errors = {};

  double get defGrams => def < 0 ? qty : units[def].grams * qty;
  double get basisGrams => perServing ? defGrams : 100;

  @override
  void initState() {
    super.initState();
    if (def < -1 || def >= units.length) def = -1;
    _fill();
    _loadExtras();
  }

  @override
  void dispose() {
    for (final c in [name, brand, ...ctl.values, for (final u in units) u.ctl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill() {
    for (final k in ctl.keys) {
      final v = per100[k];
      ctl[k]!.text = v == null ? '' : fq(v * basisGrams / 100);
    }
  }

  Future<void> _loadExtras() async {
    final id = f?['id'];
    try {
      final r = await Future.wait([
        for (final s in swaps) Services.api.get<Map>('foods/$s/'),
        if (id != null) Services.api.get<List>('foods/$id/used-in/'),
      ]);
      if (!mounted) return;
      setState(() {
        for (final x in r.whereType<Map>()) {
          swapNames['${x['id']}'] = '${x['name']}';
        }
        if (id != null) usedIn = [for (final x in r.last as List) x as Map];
      });
    } on ApiError catch (_) {}
  }

  void _setNut(String k, String v) {
    final x = double.tryParse(v.replaceAll(',', '.'));
    per100[k] = x == null ? null : x * 100 / basisGrams;
    errors.remove(k);
    setState(() {});
  }

  String get _unitLabel => def < 0 ? '${fq(qty)} g' : (qty == 1 ? units[def].name : '${fq(qty)} × ${units[def].name}');

  void _pickDefault(int i) {
    final g = defGrams;
    setState(() {
      def = i;
      qty = i < 0 ? (g / 5).round().clamp(1, 400) * 5.0 : ((g / units[i].grams * 2).round() / 2).clamp(0.5, 50);
      if (perServing) _fill();
    });
  }

  Future<Map?> save() async {
    final n = name.text.trim();
    setState(() => errors = {});
    if (n.length < 2) {
      setState(() => errors = {'name': 'Enter the food name.'});
      return null;
    }
    if (per100['kcal'] == null) {
      setState(() => errors = {'kcal': 'Enter the calories.'});
      return null;
    }
    final body = {
      'name': n,
      'brand': brand.text.trim(),
      'diet': diet,
      'group': group,
      'source_note': source.isEmpty && sourceExtra.isNotEmpty ? sourceExtra : source,
      for (final k in [..._macroKeys, ..._minKeys]) k: per100[k] == null ? (k.endsWith('_mg') ? null : 0) : double.parse(per100[k]!.toStringAsFixed(2)),
      'units': [
        for (final u in units) {if (u.id != null) 'id': u.id, 'name': u.ctl.text.trim(), 'grams': u.grams},
      ],
      'default_unit_name': def < 0 ? '' : units[def].ctl.text.trim(),
      'default_quantity': qty,
      'swaps': swaps,
    };
    try {
      final id = f?['id'];
      return id == null ? await Services.api.post<Map>('foods/', body) : await Services.api.patch<Map>('foods/$id/', body);
    } on ApiError catch (e) {
      if (!mounted) return null;
      setState(() => errors = {for (final k in e.fields.keys) k: e.field(k) ?? e.message});
      showToast(context, 'Could not save it', sub: errors.values.isEmpty ? e.message : errors.values.first, kind: ToastKind.err);
      return null;
    }
  }

  // ─────────────────────────────── build

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    Widget two(Widget a, Widget b) => phone
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [a, b])
        : Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [Expanded(child: a), Expanded(child: b)]);
    return AbsorbPointer(
      absorbing: !widget.canEdit,
      child: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
          two(
            _field('Food name', AppTextField(controller: name, placeholder: 'e.g. Paneer bhurji', onChanged: (_) => setState(() => errors.remove('name'))), req: true, error: errors['name']),
            _field('Brand (optional)', AppTextField(controller: brand, placeholder: 'Only for packaged food')),
          ),
          _field(
            'Diet',
            Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedTabs<String>(items: [for (final d in dietKeys) TabItem(d, dietLong[d]!)], value: diet, onChanged: (v) => setState(() => diet = v)),
              ),
            ),
          ),
          two(
            _field(
              'Group in the food library',
              AppSelect(foodGroups[group] ?? group, entries: [
                for (final g in foodGroups.entries) MenuEntry(g.value, selected: g.key == group, onTap: () => setState(() => group = g.key)),
              ]),
              error: errors['group'],
            ),
            _field(
              'Source',
              AppSelect(source.isEmpty && sourceExtra.isNotEmpty ? sourceExtra : _sources[source]!, entries: [
                for (final s in _sources.entries) MenuEntry(s.value, selected: s.key == source, onTap: () => setState(() => source = s.key)),
              ]),
            ),
          ),
          _field('Serving units', _units(phone), req: true, tip: 'A unit is only its weight in grams. Pick the one clients see first with the round button.', error: errors['units']),
          _nutrition(phone),
          _field(
            'More nutrients',
            _grid([for (final k in _minKeys) _num(k, {'sodium_mg': 'Sodium', 'iron_mg': 'Iron', 'calcium_mg': 'Calcium', 'potassium_mg': 'Potassium'}[k]!, 'mg')], phone ? 2 : 4),
            extra: 'optional · ${perServing ? 'per $_unitLabel' : 'per 100 g'}',
          ),
          _swapField(),
          if (usedIn.isNotEmpty) _usedField(),
          _field('Client sees in search', _preview(), tip: 'Team foods come first when a client searches. The numbers are for the default serving.'),
          const SizedBox(height: 4),
        ]),
      ),
    );
  }

  Widget _field(String label, Widget child, {bool req = false, String? tip, String? error, String? extra, Widget? end}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        Row(children: [
          Text.rich(TextSpan(text: label, style: AppText.label, children: [
            if (req) TextSpan(text: '*', style: AppText.s(12.5, W.w7, color: AppColors.badText)),
            if (extra != null) TextSpan(text: '  $extra', style: AppText.s(12, W.w5, color: AppColors.muted)),
          ])),
          if (tip != null) Padding(padding: const EdgeInsets.only(left: 2), child: CpInfo(tip)),
          if (end != null) ...[const Spacer(), end],
        ]),
        child,
        if (error != null) Text(error, style: AppText.s(12, W.w6, color: AppColors.badText)),
      ]);

  // ─────────────────────────────── units

  Widget _units(bool phone) {
    final kcal = per100['kcal'];
    String k(double g) => kcal == null ? '— kcal' : '${(kcal * g / 100).round()} kcal';
    final head = AppText.s(11.5, W.w7, color: AppColors.muted, ls: .46);
    Widget row(int i, {required Widget unit, required Widget weight, required double grams, Widget? rm}) {
      final on = def == i;
      return Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? AppColors.accentSoft : null,
          border: const Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(spacing: 8, children: [
          SizedBox(width: 28, child: _Radio(on: on, onTap: () => _pickDefault(i))),
          Expanded(child: unit),
          SizedBox(width: phone ? 112 : 150, child: weight),
          SizedBox(width: phone ? 60 : 74, child: Text(k(grams), textAlign: TextAlign.right, style: AppText.s(12.5, W.w7, color: AppColors.text2))),
          SizedBox(width: 30, child: rm),
        ]),
      );
    }

    final used = {for (final u in units) u.ctl.text.trim().toLowerCase()};
    final sug = [
      for (final s in widget.suggestions)
        if (s is List && !used.contains('${s[0]}'.toLowerCase())) (('${s[0]}'), nd(s[1])),
    ].take(6).toList();
    return Container(
      decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: AppRadius.all(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: AppColors.tableHead, borderRadius: const BorderRadius.vertical(top: Radius.circular(10))),
          child: Row(spacing: 8, children: [
            const SizedBox(width: 28),
            Expanded(child: Text('UNIT', style: head)),
            SizedBox(width: phone ? 112 : 150, child: Text('WEIGHT', style: head)),
            SizedBox(width: phone ? 60 : 74, child: Text(phone ? 'KCAL' : 'CALORIES', textAlign: TextAlign.right, style: head)),
            const SizedBox(width: 30),
          ]),
        ),
        row(-1,
            unit: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text('Grams', style: AppText.s(13, W.w7)),
              Text('Always on', style: AppText.s(11, W.w6, color: AppColors.muted)),
            ]),
            weight: Text('1 g', style: AppText.s(13, W.w6, color: AppColors.text2)),
            grams: 1),
        for (final (i, u) in units.indexed)
          row(i,
              unit: AppTextField(controller: u.ctl, height: 32, placeholder: '1 serving', onChanged: (_) => setState(() {})),
              weight: _Step(
                value: u.grams,
                unit: 'g',
                onChanged: (v) => setState(() {
                  u.grams = v;
                  if (perServing && def == i) _fill();
                }),
                stepFor: (v) => v < 2 ? 0.1 : (v < 20 ? 1 : 5),
                min: 0.1,
                max: 2000,
              ),
              grams: u.grams,
              rm: def == i
                  ? null
                  : AppIconButton(AppIcons.close, tooltip: 'Remove unit', small: true, ghost: true, onPressed: () => setState(() {
                        units.removeAt(i);
                        if (def > i) def--;
                      }))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
          alignment: Alignment.centerLeft,
          child: Builder(
            builder: (b) => AppButton('Add unit', kind: BtnKind.text, icon: AppIcons.plus, onPressed: units.length >= 12
                ? null
                : () => showAppMenu(b, width: 230, alignRight: false, [
                      for (final s in sug) MenuEntry(s.$1, end: '${fq(s.$2)} g', onTap: () => setState(() => units.add(_Unit(s.$1, s.$2)))),
                      if (sug.isNotEmpty) const MenuEntry.separator(),
                      MenuEntry('Custom unit', onTap: () {
                        setState(() => units.add(_Unit('1 serving', 100)));
                        showToast(context, 'Unit added', sub: 'Name it and set its weight in grams');
                      }),
                    ])),
          ),
        ),
        // `.nu-def`: Default serving − n × unit + = grams · kcal
        Container(
          margin: const EdgeInsets.fromLTRB(0, 0, 0, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: const BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.vertical(bottom: Radius.circular(9))),
          child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Default serving', style: AppText.s(13, W.w7)),
            SizedBox(
              width: 210,
              child: _Step(
                value: qty,
                unit: def < 0 ? 'g' : '× ${units[def].ctl.text.trim()}',
                bg: AppColors.card,
                onChanged: (v) => setState(() {
                  qty = v;
                  if (perServing) _fill();
                }),
                stepFor: (_) => def < 0 ? 5 : 0.5,
                min: def < 0 ? 5 : 0.5,
                max: def < 0 ? 2000 : 50,
              ),
            ),
            Text(
                [if (def >= 0) '= ${fq(defGrams)} g', if (kcal != null) '${(kcal * defGrams / 100).round()} kcal'].join(' · '),
                style: AppText.s(12.5, W.w6, color: AppColors.text2)),
          ]),
        ),
      ]),
    );
  }

  // ─────────────────────────────── nutrition

  Widget _nutrition(bool phone) {
    final k = per100['kcal'], p = per100['protein'] ?? 0, c = per100['carbs'] ?? 0, fat = per100['fat'] ?? 0;
    final calc = (p * 4 + c * 4 + fat * 9).round();
    final ok = k != null && (calc - k).abs() <= (k * 0.1 > 10 ? k * 0.1 : 10);
    final tip = k == null
        ? 'Type the numbers from the pack or your sheet. They are saved per 100 g.'
        : !perServing
            ? 'Saved per 100 g. Every unit above is worked out from these numbers.'
            : 'You are typing for $_unitLabel (${fq(defGrams)} g). Saved as per 100 g: ${k.round()} kcal · P ${nf(p)} g · C ${nf(c)} g · F ${nf(fat)} g.';
    final basis = SegmentedTabs<bool>(
      items: [const TabItem(false, 'Per 100 g'), TabItem(true, 'Per $_unitLabel')],
      value: perServing,
      onChanged: (v) => setState(() {
        perServing = v;
        _fill();
      }),
    );
    final badge = k == null
        ? null
        : AppTooltip(
            message: 'Per 100 g: 4 × P + 4 × C + 9 × F = $calc kcal. You entered ${k.round()} kcal.${ok ? ' Close enough.' : ' Check the numbers on the pack.'}',
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(color: ok ? AppColors.okBg : AppColors.warnBg, borderRadius: AppRadius.all(11)),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
                AppIcon(ok ? AppIcons.checkCircle : AppIcons.alert, size: 13, color: ok ? AppColors.okText : AppColors.warnText),
                Text(ok ? 'Calories match' : 'Check calories', style: AppText.s(11.5, W.w7, color: ok ? AppColors.okText : AppColors.warnText)),
              ]),
            ),
          );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.spaceBetween, children: [
        Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
          Text('Nutrition', style: AppText.label),
          CpInfo(tip),
          if (badge != null) Padding(padding: const EdgeInsets.only(left: 6), child: badge),
        ]),
        basis,
      ]),
      _grid([
        _num('kcal', 'Calories', 'kcal'),
        _num('protein', 'Protein', 'g'),
        _num('carbs', 'Carbs', 'g'),
        _num('fat', 'Fat', 'g'),
        _num('fibre', 'Fibre', 'g'),
      ], phone ? 3 : 5),
      for (final e in ['kcal', 'protein', 'carbs', 'fat', 'fibre'])
        if (errors[e] != null) Text(errors[e]!, style: AppText.s(12, W.w6, color: AppColors.badText)),
    ]);
  }

  Widget _grid(List<Widget> cells, int cols) => LayoutBuilder(builder: (context, b) {
        const gap = 8.0;
        final w = (b.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: 8, children: [for (final c in cells) SizedBox(width: w, child: c)]);
      });

  Widget _num(String k, String label, String unit) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
        Text(label, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
        AppTextField(
          controller: ctl[k],
          placeholder: '0',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          suffix: Text(unit, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
          onChanged: (v) => _setNut(k, v),
        ),
      ]);

  // ─────────────────────────────── swaps

  Widget _swapField() => _field(
        'Swap group · alternatives',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final s in swaps)
              Container(
                height: 30,
                padding: const EdgeInsets.only(left: 10, right: 2),
                decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: AppRadius.all(8)),
                child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                  const AppIcon(AppIcons.swap, size: 14, color: AppColors.muted),
                  Text(swapNames[s] ?? '…', style: AppText.s(13, W.w6)),
                  AppIconButton(AppIcons.close, tooltip: 'Remove', small: true, ghost: true, onPressed: () => setState(() => swaps.remove(s))),
                ]),
              ),
            Builder(builder: (b) => AppButton('Add alternative', kind: BtnKind.text, icon: AppIcons.plus, onPressed: () => _pickSwap(b))),
          ]),
          if (swaps.isEmpty) Text('No swaps yet. The client has to eat this food as planned.', style: AppText.s(12, W.w5, color: AppColors.muted)),
        ]),
        tip: 'The client gets these choices when they tap Swap on this food in their meal plan. The amount is changed to give about the same calories.',
      );

  /// Pick an alternative: same group or all foods, closest protein / carbs / fat split per calorie first.
  Future<void> _pickSwap(BuildContext anchor) async {
    final picked = await showAppDrawer<Map>(
      context,
      title: 'Pick an alternative',
      sub: 'Match = how close protein, carbs and fat are, per calorie.',
      icon: AppIcons.swap,
      fixedBody: true,
      builder: (ctx) => _SwapPicker(
        self: {'id': f?['id'], 'group': group, ...per100},
        exclude: {...swaps, if (f?['id'] != null) '${f!['id']}'},
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      swaps.add('${picked['id']}');
      swapNames['${picked['id']}'] = '${picked['name']}';
    });
    showToast(context, 'Alternative added', sub: '${picked['name']}');
  }

  // ─────────────────────────────── used in, preview

  Widget _usedField() {
    final byPlan = <String, (String, List<String>)>{};
    for (final u in usedIn) {
      final e = byPlan.putIfAbsent('${u['plan']}', () => ('${u['plan_name']}', <String>[]));
      if (!e.$2.contains('${u['meal']}')) e.$2.add('${u['meal']}');
    }
    return _field(
      'Used in ${plural(byPlan.length, 'plan')}',
      Container(
        constraints: const BoxConstraints(maxHeight: 178),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: AppRadius.all(10)),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, e) in byPlan.entries.indexed)
              Hover(
                onTap: () {
                  Navigator.of(context).pop();
                  context.go('/nutrition/${e.key}');
                },
                builder: (_, h, _) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
                  decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
                  child: Row(spacing: 10, children: [
                    const AppIcon(AppIcons.apple, size: 16, color: AppColors.okText),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                        Text(e.value.$1, style: AppText.s(13.5, W.w7, color: h ? AppColors.accentText : AppColors.text)),
                        Text(e.value.$2.join(', '), style: AppText.s(12, W.w4, color: AppColors.muted)),
                      ]),
                    ),
                    const AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.muted),
                  ]),
                ),
              ),
          ]),
        ),
      ),
      tip: 'Changing the numbers updates these plans for every client on them.',
    );
  }

  Widget _preview() {
    final g = defGrams;
    double v(String k) => (per100[k] ?? 0) * g / 100;
    final n = name.text.trim().isEmpty ? 'Your food' : name.text.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.line), borderRadius: AppRadius.all(8)),
      child: Row(spacing: 10, children: [
        FoodTile(tone: groupTone(group), size: 34),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
            Row(spacing: 6, children: [
              Flexible(child: Text(n, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7))),
              const AppBadge('Team', tone: Tone.info, plain: true),
            ]),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '$_unitLabel${def < 0 ? '' : ' (${fq(g)} g)'}', style: AppText.s(12, W.w7, color: AppColors.text2)),
                TextSpan(text: ' · ${v('kcal').round()} kcal · P ${nf(v('protein'))} g · C ${nf(v('carbs'))} g · F ${nf(v('fat'))} g'),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.s(12, W.w5, color: AppColors.muted),
            ),
          ]),
        ),
        const AppIcon(AppIcons.plus, size: 18, color: AppColors.accent),
      ]),
    );
  }
}

/// `.nu-rad`: the round "show this first" button.
class _Radio extends StatelessWidget {
  const _Radio({required this.on, required this.onTap});
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => AppTooltip(
        message: 'Show this first',
        child: Semantics(
          button: true,
          selected: on,
          label: 'Default unit',
          child: Hover(
            onTap: onTap,
            builder: (_, h, _) => Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.card, shape: BoxShape.circle, border: Border.all(color: on || h ? AppColors.accent : AppColors.line2, width: 1.5)),
              child: on ? Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)) : null,
            ),
          ),
        ),
      );
}

/// `.pg-step` with decimals: − value unit +, 32 high.
class _Step extends StatelessWidget {
  const _Step({required this.value, required this.unit, required this.onChanged, required this.stepFor, required this.min, required this.max, this.bg});
  final double value, min, max;
  final String unit;
  final ValueChanged<double> onChanged;
  final double Function(double) stepFor;
  final Color? bg;

  double _round(double v) => (v * 10).round() / 10;

  @override
  Widget build(BuildContext context) => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(color: bg, border: Border.all(color: AppColors.line), borderRadius: AppRadius.all(8)),
        child: Row(children: [
          AppIconButton(AppIcons.minus, tooltip: 'Less', small: true, ghost: true, onPressed: value <= min ? null : () => onChanged(_round((value - stepFor(value - .0001)).clamp(min, max)))),
          Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 4, children: [
              Text(fq(value), style: AppText.s(14, W.w8)),
              Flexible(child: Text(unit, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w6, color: AppColors.muted))),
            ]),
          ),
          AppIconButton(AppIcons.plus, tooltip: 'More', small: true, ghost: true, onPressed: value >= max ? null : () => onChanged(_round((value + stepFor(value)).clamp(min, max)))),
        ]),
      );
}

/// The alternatives list: same group or all foods, sorted by match.
class _SwapPicker extends StatefulWidget {
  const _SwapPicker({required this.self, required this.exclude});
  final Map self;
  final Set<String> exclude;
  @override
  State<_SwapPicker> createState() => _SwapPickerState();
}

class _SwapPickerState extends State<_SwapPicker> {
  String scope = 'group', q = '';
  List<Map> rows = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<double> _split(Map f) {
    final p = nd(f['protein']), c = nd(f['carbs']), fat = nd(f['fat']);
    final k = (p * 4 + c * 4 + fat * 9).clamp(1, double.infinity);
    return [p * 4 / k, c * 4 / k, fat * 9 / k];
  }

  int _match(Map f) {
    final a = _split(widget.self), b = _split(f);
    return (100 - 50 * ((a[0] - b[0]).abs() + (a[1] - b[1]).abs() + (a[2] - b[2]).abs())).round().clamp(0, 100);
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final r = await Services.api.get<Map>('foods/', query: {'page_size': 100, 'search': q, if (scope == 'group') 'group': widget.self['group']});
      if (!mounted) return;
      final list = [
        for (final x in r['results'] as List)
          if (!widget.exclude.contains('${(x as Map)['id']}')) {...x, '_m': _match(x)},
      ]..sort((a, b) => (b['_m'] as int).compareTo(a['_m'] as int));
      setState(() {
        rows = list.take(q.isEmpty ? 8 : 30).toList();
        loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      showToast(context, 'Could not load foods', sub: e.message, kind: ToastKind.err);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 10),
          child: Row(spacing: 8, children: [
            Expanded(child: AppSearchField(placeholder: 'Search foods', icon: AppIcons.search, onChanged: (v) {
              q = v.trim();
              _load();
            })),
            SegmentedTabs<String>(
              items: const [TabItem('group', 'Same group'), TabItem('all', 'All foods')],
              value: scope,
              onChanged: (v) {
                setState(() => scope = v);
                _load();
              },
            ),
          ]),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5))
              : rows.isEmpty
                  ? Center(child: Text(scope == 'group' ? 'No other foods in this group.' : 'No foods found.', style: AppText.s(13, W.w5, color: AppColors.muted)))
                  : ListView(children: [
                      for (final f in rows)
                        Hover(
                          onTap: () => Navigator.of(context).pop(f),
                          builder: (_, h, _) {
                            final g = servingGrams(f), m = f['_m'] as int;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              decoration: BoxDecoration(color: h ? AppColors.hover : null, borderRadius: AppRadius.all(8)),
                              child: Row(spacing: 10, children: [
                                FoodTile(tone: groupTone('${f['group']}'), size: 30),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                                    Text('${f['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7)),
                                    Text('${servingLabel(f)} · ${at(f['kcal'], g).round()} kcal · P ${nf(at(f['protein'], g))} g',
                                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w4, color: AppColors.muted)),
                                  ]),
                                ),
                                AppBadge('$m% match', tone: m >= 85 ? Tone.ok : (m >= 65 ? Tone.info : Tone.neutral), plain: true),
                              ]),
                            );
                          },
                        ),
                    ]),
        ),
      ]);
}
