import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/util/save_file.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tabs.dart';
import '../../trainer/me/me_pick.dart';
import '../lib_common.dart';
import 'nu_common.dart';
import 'nutrition_screen.dart' show nutritionChanged;

/// Import foods from Excel (board `Nutrition` → import drawer): 1 Upload (drop zone, what each row needs, template),
/// 2 Check and import (counts, what to do with foods already in the library, calories that do not add up, preview).
/// Nothing is saved until "Import N foods"; the toast's Undo removes what was added. Returns true when imported.
Future<bool?> showFoodImport(BuildContext context) {
  final key = GlobalKey<_ImportState>();
  return showAppDrawer<bool>(
    context,
    title: 'Import foods from Excel',
    sub: 'Upload, then check and import',
    icon: AppIcons.importFile,
    width: 780,
    builder: (ctx) => _Import(key: key),
    footer: (ctx) => [_ImportFooter(state: key)],
  );
}

class _Import extends StatefulWidget {
  const _Import({super.key});
  @override
  State<_Import> createState() => _ImportState();
}

class _ImportState extends State<_Import> {
  final step = ValueNotifier<int>(1);
  final busy = ValueNotifier<bool>(false);

  /// Ticks on every change, so the footer (outside this widget) shows the right note and button.
  final changed = ValueNotifier<int>(0);
  (String, Uint8List)? file;
  bool over = false;
  void Function()? _unwatch;

  // step 2
  Map? job;
  String dup = 'skip', filter = 'all';
  bool eggs = true;
  int page = 0;
  static const _ps = 6;

  List<Map> get rows => [for (final r in (job?['rows'] as List? ?? const [])) r as Map];
  List<Map> get okRows => rows.where((r) => (r['errors'] as List? ?? const []).isEmpty).toList();
  Map get summary => (job?['summary'] as Map?) ?? const {};

  String _status(Map r) => r['existing'] == null ? 'New' : switch (dup) { 'skip' => 'Skip', 'update' => 'Update', _ => 'New' };
  int get saving => okRows.where((r) => _status(r) != 'Skip').length;
  int get newCount => okRows.where((r) => _status(r) == 'New').length;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _unwatch = watchDrops(onOver: (o) => setState(() => over = o), onFile: _take);
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    changed.value++;
  }

  @override
  void dispose() {
    _unwatch?.call();
    step.dispose();
    busy.dispose();
    changed.dispose();
    super.dispose();
  }

  void _take((String, Uint8List) f) {
    final ext = f.$1.split('.').last.toLowerCase();
    if (!['xlsx', 'xls', 'csv'].contains(ext)) {
      showToast(context, 'Excel or CSV only', sub: f.$1, kind: ToastKind.err);
      return;
    }
    setState(() => file = f);
  }

  Future<void> _choose() async {
    final f = await pickDocument(ext: const ['xlsx', 'xls', 'csv']);
    if (f != null && mounted) _take(f);
  }

  Future<void> _template() async {
    try {
      final r = await Services.api.download('foods/import/template/');
      final where = await saveFile('food-import-template.xlsx', r.data ?? const [], mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      if (mounted) showToast(context, 'Template downloaded', sub: where);
    } catch (e) {
      if (mounted) showToast(context, 'Could not download it', sub: e is ApiError ? e.message : '$e', kind: ToastKind.err);
    }
  }

  Future<void> next() async {
    if (step.value == 1) {
      final f = file;
      if (f == null) {
        showToast(context, 'Choose a file first', sub: 'Excel or CSV');
        return;
      }
      busy.value = true;
      try {
        final r = await Services.api.post<Map>('foods/import/check/', FormData.fromMap({'file': MultipartFile.fromBytes(f.$2, filename: f.$1)}));
        if (!mounted) return;
        setState(() {
          job = r;
          page = 0;
          filter = 'all';
          eggs = true;
        });
        step.value = 2;
      } on ApiError catch (e) {
        if (mounted) showToast(context, 'Could not read the file', sub: e.field('file') ?? e.message, kind: ToastKind.err);
      }
      busy.value = false;
      return;
    }
    if (saving == 0) {
      showToast(context, 'Nothing to import', sub: 'Every row is skipped');
      return;
    }
    busy.value = true;
    final id = job!['id'];
    try {
      final r = await Services.api.post<Map>('foods/import/$id/run/', {'duplicates': dup, 'eggs_eggetarian': eggs});
      if (!mounted) return;
      final c = (r['created'] as num?)?.toInt() ?? 0, u = (r['updated'] as num?)?.toInt() ?? 0, s = (r['skipped'] as num?)?.toInt() ?? 0;
      final nav = Navigator.of(context);
      final ctx = nav.context;
      nav.pop(true);
      if (!ctx.mounted) return;
      showToast(ctx, '${plural(c, 'food')} imported',
          sub: u > 0 ? '${plural(u, 'library food')} updated' : (s > 0 ? '$s already in the library ${s == 1 ? 'was' : 'were'} skipped' : 'From ${file?.$1 ?? 'your sheet'}'),
          action: 'Undo', onAction: () async {
        try {
          await Services.api.post('foods/import/$id/undo/');
          nutritionChanged.value++;
          if (ctx.mounted) showToast(ctx, 'Import undone', sub: 'The foods it added are removed');
        } on ApiError catch (e) {
          if (ctx.mounted) showToast(ctx, 'Could not undo it', sub: e.message, kind: ToastKind.err);
        }
      });
      return;
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not import it', sub: e.message, kind: ToastKind.err);
    }
    busy.value = false;
  }

  void back() => step.value = 1;

  String get note => step.value == 1 ? (file == null ? 'Nothing is saved until the last step' : file!.$1) : '$saving of ${rows.length} rows will be saved';

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: step,
        builder: (_, s, _) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
            _steps(s),
            if (s == 1) ..._upload() else ..._check(),
          ]),
        ),
      );

  Widget _steps(int s) => Row(spacing: 6, children: [
        for (final (i, t) in const ['Upload', 'Check and import'].indexed)
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: i + 1 == s ? AppColors.accentSoft : AppColors.sub, borderRadius: AppRadius.all(10)),
              child: Row(spacing: 8, children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i + 1 == s ? AppColors.accent : (i + 1 < s ? AppColors.okBg : AppColors.card),
                    border: i + 1 == s || i + 1 < s ? null : Border.all(color: AppColors.line2),
                  ),
                  child: i + 1 < s
                      ? const AppIcon(AppIcons.check, size: 12, color: AppColors.okText)
                      : Text('${i + 1}', style: AppText.s(11.5, W.w7, color: i + 1 == s ? AppColors.white : AppColors.text2)),
                ),
                Flexible(child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w7, color: i + 1 == s ? AppColors.accentText : (i + 1 < s ? AppColors.text2 : AppColors.muted)))),
              ]),
            ),
          ),
      ]);

  // ─────────────────────────────── step 1

  List<Widget> _upload() {
    final drop = Hover(
      onTap: _choose,
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 30),
        decoration: BoxDecoration(
          color: h || over ? AppColors.hover : AppColors.tableHead,
          borderRadius: AppRadius.all(12),
          border: Border.all(color: h || over ? AppColors.accent : AppColors.line2, width: 1.5),
        ),
        child: Column(spacing: 6, children: [
          const AppIcon(AppIcons.importFile, size: 26, color: AppColors.accent),
          Text(over ? 'Drop it here' : 'Drop an Excel or CSV file here', textAlign: TextAlign.center, style: AppText.s(14, W.w7)),
          Text('or click to choose · .xlsx, .xls, .csv · up to 5,000 rows', textAlign: TextAlign.center, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
        ]),
      ),
    );
    final f = file;
    final chosen = f == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: AppRadius.all(12)),
            child: Row(spacing: 12, children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.nuXlBg, borderRadius: AppRadius.all(9)),
                child: Text(f.$1.split('.').last.toUpperCase(), style: AppText.s(11, W.w8, color: AppColors.okText)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text(f.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7)),
                  Text('${(f.$2.length / 1024).toStringAsFixed(f.$2.length < 10240 ? 1 : 0)} KB · checked in the next step', style: AppText.s(12, W.w5, color: AppColors.muted)),
                ]),
              ),
              AppButton('Change', size: BtnSize.sm, onPressed: _choose),
              AppIconButton(AppIcons.close, tooltip: 'Remove file', small: true, ghost: true, onPressed: () => setState(() => file = null)),
            ]),
          );
    const need = [
      ('Food', 'Name clients search for', true),
      ('Portion/Quantity', 'Unit name, like 1 tsp (5 g) or 1 katori', false),
      ('Portion_g', 'Weight of that serving in grams. ml counts as g.', true),
      ('Calories_kcal', 'For that serving', true),
      ('Protein, carbs, fat, fibre, minerals', 'For that serving. Blank is fine.', false),
      ('Category, Main_Category, Source', 'Food group, veg / non-veg, and where the numbers came from. Blank is fine.', false),
    ];
    final phone = context.isPhone;
    return [
      _label('Your file'),
      if (chosen != null) chosen else if (kIsWeb) drop else DropTarget(
        onDragEntered: (_) => setState(() => over = true),
        onDragExited: (_) => setState(() => over = false),
        onDragDone: (d) async {
          setState(() => over = false);
          final x = d.files.firstOrNull;
          if (x != null) _take((x.name, await x.readAsBytes()));
        },
        child: drop,
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        _label('What each row needs'),
        Container(
          decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: AppRadius.all(10)),
          child: Column(children: [
            for (final (i, n) in need.indexed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
                  SizedBox(width: phone ? 120 : 188, child: Text(n.$1, style: AppText.s(13.5, W.w7))),
                  Expanded(child: Text(n.$2, style: AppText.s(13, W.w5, color: AppColors.text2))),
                  if (n.$3) const AppBadge('Required', tone: Tone.info, plain: true),
                ]),
              ),
          ]),
        ),
        Align(alignment: Alignment.centerLeft, child: AppButton('Download the template', kind: BtnKind.text, icon: AppIcons.file, onPressed: _template)),
      ]),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(8)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
          const Padding(padding: EdgeInsets.only(top: 1), child: AppIcon(AppIcons.info, size: 15, color: AppColors.muted)),
          Expanded(
            child: Text('Write nutrition for the serving in Portion_g, like your sheet does. We turn it into per 100 g, so any unit works later.',
                style: AppText.s(12.5, W.w5, color: AppColors.text2)),
          ),
        ]),
      ),
    ];
  }

  Widget _label(String t) => Text(t, style: AppText.label);

  // ─────────────────────────────── step 2

  List<Widget> _check() {
    final s = summary;
    final there = (s['already_there'] as num?)?.toInt() ?? 0, differ = (s['kcal_differs'] as num?)?.toInt() ?? 0, errs = (s['errors'] as num?)?.toInt() ?? 0;
    final eggN = (s['egg_rows_nonveg'] as num?)?.toInt() ?? 0;
    final kpis = [
      ('${rows.length}', 'Rows in the file', null),
      ('$newCount', 'New foods', Tone.ok),
      ('$there', dup == 'skip' ? 'Skipped · already there' : (dup == 'update' ? 'Will update' : 'Added again'), null),
      ('$differ', 'Calories differ', differ > 0 ? Tone.warn : null),
    ];
    final phone = context.isPhone;
    final bad = okRows.where((r) => r['kcal_differs'] == true).toList();
    final shown = switch (filter) {
      'new' => okRows.where((r) => r['existing'] == null).toList(),
      'dup' => okRows.where((r) => r['existing'] != null).toList(),
      'chk' => bad,
      _ => okRows,
    };
    final pages = shown.isEmpty ? 1 : (shown.length + _ps - 1) ~/ _ps;
    final pg = page.clamp(0, pages - 1);
    final units = okRows.where((r) => r['unit'] != null).length;
    return [
      LayoutBuilder(builder: (context, b) {
        final cols = phone ? 2 : 4;
        final w = (b.maxWidth - 8 * (cols - 1)) / cols;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in kpis)
            Container(
              width: w,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: k.$3 == Tone.ok ? AppColors.okBg : (k.$3 == Tone.warn ? AppColors.warnBg : AppColors.sub),
                borderRadius: AppRadius.all(10),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text(k.$1, style: AppText.s(20, W.w8, color: k.$3 == Tone.ok ? AppColors.okText : (k.$3 == Tone.warn ? AppColors.warnText : AppColors.text))),
                Text(k.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w6, color: AppColors.text2)),
              ]),
            ),
        ]);
      }),
      if (there > 0)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          _label('Already in your library · $there'),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedTabs<String>(
              items: const [TabItem('skip', 'Skip them'), TabItem('update', 'Update the numbers'), TabItem('new', 'Add as new')],
              value: dup,
              onChanged: (v) => setState(() => dup = v),
            ),
          ),
          Text(
              switch (dup) {
                'skip' => 'Your library keeps its numbers. Nothing changes in meal plans.',
                'update' => 'Library foods get the numbers from your sheet. Meal plans that use them change too.',
                _ => 'You get two foods with the same name. Clients may pick the wrong one.',
              },
              style: AppText.s(12.5, W.w5, color: AppColors.muted)),
        ]),
      if (bad.isNotEmpty)
        _note(
          Tone.warn,
          AppIcons.flag,
          '${plural(bad.length, 'food')} ${bad.length == 1 ? 'has' : 'have'} calories that do not match protein, carbs and fat.',
          '${bad.map((r) => r['name']).join(', ')}. The calories from your sheet are saved. You can fix them later in the food.',
        ),
      if (errs > 0)
        _note(Tone.bad, AppIcons.alert, '${plural(errs, 'row')} can’t be imported.',
            rows.where((r) => (r['errors'] as List? ?? const []).isNotEmpty).take(6).map((r) => 'Row ${r['line']}: ${(r['errors'] as List).join(', ')}').join(' · ')),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        _label('Good to know'),
        if (units > 0) _know('${plural(units, 'serving unit')} ${units == 1 ? 'is' : 'are'} made from Portion/Quantity, like 1 tsp, 1 medium and 1 cup. Rows with only grams get Grams.'),
        _know('ml is counted as g: 1 ml = 1 g.'),
        _know('Only the exact same name counts as already in your library. Foods with a different name, like Egg (whole, raw) and Egg (whole), are both imported.'),
        if (eggN > 0)
          Hover(
            onTap: () => setState(() => eggs = !eggs),
            builder: (_, h, _) => Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              AppIcon(AppIcons.checkCircle, size: 16, color: eggs ? AppColors.okText : AppColors.muted),
              Expanded(
                child: Text('${plural(eggN, 'egg food')} marked Non-veg in the sheet ${eggN == 1 ? 'is' : 'are'} saved as Eggetarian. Tap to ${eggs ? 'keep Non-veg' : 'save as Eggetarian'}.',
                    style: AppText.s(13, W.w5, color: h ? AppColors.text : AppColors.text2)),
              ),
            ]),
          ),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
          Text.rich(TextSpan(text: 'Preview', style: AppText.label, children: [TextSpan(text: ' · per 100 g', style: AppText.s(12.5, W.w5, color: AppColors.muted))])),
          SegmentedTabs<String>(
            items: [
              TabItem('all', 'All', count: okRows.length),
              TabItem('new', 'New', count: okRows.where((r) => r['existing'] == null).length),
              TabItem('dup', 'Already there', count: there),
              TabItem('chk', 'Check', count: bad.length),
            ],
            value: filter,
            onChanged: (v) => setState(() {
              filter = v;
              page = 0;
            }),
          ),
        ]),
        _preview(shown.skip(pg * _ps).take(_ps).toList()),
        Row(spacing: 6, children: [
          Expanded(
            child: Text(shown.isEmpty ? 'Nothing here' : '${pg * _ps + 1}–${(pg * _ps + _ps).clamp(0, shown.length)} of ${shown.length}',
                style: AppText.s(12.5, W.w5, color: AppColors.text2)),
          ),
          AppIconButton(AppIcons.chevronLeft, tooltip: 'Previous page', small: true, onPressed: pg > 0 ? () => setState(() => page = pg - 1) : null),
          AppIconButton(AppIcons.chevronRight, tooltip: 'Next page', small: true, onPressed: pg < pages - 1 ? () => setState(() => page = pg + 1) : null),
        ]),
      ]),
    ];
  }

  Widget _note(Tone t, AppIconData icon, String title, String body) {
    final (bg, fg) = t == Tone.bad ? (AppColors.badBg, AppColors.badText) : (AppColors.warnBg, AppColors.warnText);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.all(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: AppIcon(icon, size: 15, color: fg)),
        Expanded(
          child: Text.rich(
            TextSpan(children: [TextSpan(text: '$title ', style: AppText.s(13, W.w7, color: fg)), TextSpan(text: body)]),
            style: AppText.s(13, W.w5, color: fg),
          ),
        ),
      ]),
    );
  }

  Widget _know(String t) => Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        const Padding(padding: EdgeInsets.only(top: 1), child: AppIcon(AppIcons.checkCircle, size: 16, color: AppColors.okText)),
        Expanded(child: Text(t, style: AppText.s(13, W.w5, color: AppColors.text2))),
      ]);

  String _diet(Map r) {
    final raw = '${r['diet_raw'] ?? ''}';
    final d = raw.isEmpty ? 'veg' : '${(summary['diet_suggestions'] as Map?)?[raw] ?? 'veg'}';
    return eggs && r['is_egg'] == true && d == 'nonveg' ? 'egg' : d;
  }

  String _group(Map r) {
    final raw = '${r['group_raw'] ?? ''}';
    final g = raw.isEmpty ? 'other' : '${(summary['group_suggestions'] as Map?)?[raw] ?? 'other'}';
    return foodGroups[g] ?? g;
  }

  Widget _preview(List<Map> list) {
    const cols = <(String, double, bool)>[
      ('Food', 150, false),
      ('Default serving', 118, false),
      ('kcal', 46, true),
      ('P', 40, true),
      ('C', 40, true),
      ('F', 40, true),
      ('Group', 80, false),
      ('Diet', 104, false),
      ('Status', 104, true),
    ];
    return LayoutBuilder(builder: (context, box) {
      final min = cols.fold<double>(0, (a, x) => a + x.$2);
      final extra = (box.maxWidth - 2 - min).clamp(0.0, double.infinity);
      final widths = [for (final (i, x) in cols.indexed) x.$2 + (i == 0 ? extra : 0)];
      Widget cell(int i, Widget c) => Container(
            width: widths[i],
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: cols[i].$3 ? Alignment.centerRight : Alignment.centerLeft,
            child: c,
          );
      final body = AppText.s(13, W.w4);
      final table = SizedBox(
        width: min + extra,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 32,
            decoration: const BoxDecoration(color: AppColors.tableHead, border: Border(bottom: BorderSide(color: AppColors.line))),
            child: Row(children: [for (final (i, c) in cols.indexed) cell(i, Text(c.$1, style: AppText.s(12, W.w7, color: AppColors.muted)))]),
          ),
          if (list.isEmpty)
            Padding(padding: const EdgeInsets.all(16), child: Text('Nothing here', textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted))),
          for (final (j, r) in list.indexed)
            Container(
              height: 37,
              decoration: BoxDecoration(border: j == list.length - 1 ? null : const Border(bottom: BorderSide(color: AppColors.line))),
              child: Row(children: () {
                final p = (r['per100'] as Map?) ?? const {};
                final u = r['unit'] as Map?;
                final st = _status(r), differs = r['kcal_differs'] == true && st != 'Skip';
                final tone = st == 'Skip' ? Tone.neutral : (differs ? Tone.warn : (st == 'Update' ? Tone.info : Tone.ok));
                final d = _diet(r);
                return [
                  cell(0, Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w6))),
                  cell(1, Text(u == null ? '100 g' : '${u['name']} · ${fq(nd(u['grams']))} g', maxLines: 1, overflow: TextOverflow.ellipsis, style: body)),
                  cell(2, Text('${nd(p['kcal']).round()}', style: body)),
                  cell(3, Text(nf(nd(p['protein'])), style: body)),
                  cell(4, Text(nf(nd(p['carbs'])), style: body)),
                  cell(5, Text(nf(nd(p['fat'])), style: body)),
                  cell(6, Text(_group(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: body)),
                  cell(7, Row(spacing: 6, children: [DietMark(d), Flexible(child: Text(dietLong[d] ?? d, maxLines: 1, overflow: TextOverflow.ellipsis, style: body))])),
                  cell(8, AppBadge(differs ? '$st · kcal differs' : st, tone: tone, plain: true)),
                ];
              }()),
            ),
        ]),
      );
      return Container(
        decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: AppRadius.all(10)),
        clipBehavior: Clip.antiAlias,
        child: box.maxWidth - 2 >= min ? table : SingleChildScrollView(scrollDirection: Axis.horizontal, child: table),
      );
    });
  }
}

/// Footer: Back (step 2), the note, Cancel and Next / Import N foods. Rebuilds with the form's step.
class _ImportFooter extends StatefulWidget {
  const _ImportFooter({required this.state});
  final GlobalKey<_ImportState> state;
  @override
  State<_ImportFooter> createState() => _ImportFooterState();
}

class _ImportFooterState extends State<_ImportFooter> {
  _ImportState? s;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  void _attach() {
    final st = widget.state.currentState;
    if (st == null || !mounted) return;
    s = st;
    st.step.addListener(_tick);
    st.busy.addListener(_tick);
    st.changed.addListener(_tick);
    setState(() {});
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    s?.step.removeListener(_tick);
    s?.busy.removeListener(_tick);
    s?.changed.removeListener(_tick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = s;
    final two = st?.step.value == 2;
    final phone = context.isPhone;
    // On a phone the sheet stacks its footer in a Column, so the row can't be Expanded there.
    final row = Row(spacing: 8, children: [
        if (two) AppButton('Back', kind: BtnKind.text, icon: AppIcons.chevronLeft, onPressed: st?.back),
        if (!phone) Expanded(child: Text(st?.note ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted))) else const Spacer(),
        AppButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        Opacity(
          opacity: !two && st?.file == null ? .5 : 1,
          child: AppButton.primary(two ? 'Import ${plural(st?.newCount ?? 0, 'food')}' : 'Next',
              icon: AppIcons.check, loading: st?.busy.value == true, onPressed: st?.next),
        ),
      ]);
    return phone ? row : Expanded(child: row);
  }
}
