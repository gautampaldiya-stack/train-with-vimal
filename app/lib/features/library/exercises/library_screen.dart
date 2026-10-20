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
import '../../../core/widgets/select.dart';
import '../lib_common.dart';
import 'ex_common.dart';
import 'ex_sheets.dart';

/// Exercise library (boards `ExerciseLibrary` / `ExerciseLibraryMobile`): picture-first cards, search, the
/// Muscle · Equipment · Level · Source filter (several options each), chips, Sort, New exercise.
class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({super.key});
  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

const _sorts = [('name', 'Name A–Z'), ('-name', 'Name Z–A'), ('-n_programs', 'Most used'), ('-created_at', 'Newest')];

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final picked = ValueNotifier<LibPicked>({});
  String q = '', sort = 'name';
  List<Map> rows = [];
  Map facets = const {};
  int count = 0;
  String? next;
  bool loading = true, more = false;
  ApiError? error;
  Timer? _debounce;
  int _req = 0;

  bool get canCreate => (facets['can'] as Map?)?['create'] == true;
  int get total => ((facets['builtin'] as num?) ?? 0).toInt() + ((facets['custom'] as num?) ?? 0).toInt();

  @override
  void initState() {
    super.initState();
    picked.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    picked.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _query => {
        'search': q,
        'ordering': sort,
        'page_size': 40,
        for (final e in picked.value.entries)
          if (e.value.isNotEmpty) e.key: e.value.join(','),
      };

  Future<void> _load() async {
    final req = ++_req;
    setState(() => loading = rows.isEmpty);
    try {
      final r = await Future.wait([
        Services.api.get<Map>('exercises/', query: _query),
        Services.api.get<Map>('exercises/facets/', query: {'search': q}),
      ]);
      if (req != _req || !mounted) return;
      setState(() {
        rows = [for (final x in r[0]['results'] as List) x as Map];
        count = (r[0]['count'] as num?)?.toInt() ?? rows.length;
        next = r[0]['next'] as String?;
        facets = r[1];
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
      final page = Uri.parse(n).queryParameters['page'];
      final r = await Services.api.get<Map>('exercises/', query: {..._query, 'page': page});
      if (!mounted) return;
      setState(() {
        rows = [...rows, for (final x in r['results'] as List) x as Map];
        next = r['next'] as String?;
      });
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not load more', sub: e.message, kind: ToastKind.err);
    }
    if (mounted) setState(() => more = false);
  }

  void _search(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      q = v.trim();
      _load();
    });
  }

  List<LibFacet> get _facets => [
        for (final (k, l) in const [('muscle', 'Muscle'), ('equipment', 'Equipment'), ('level', 'Level'), ('source', 'Source')])
          LibFacet(k, l, [
            for (final o in (facets[k] as List? ?? const []))
              // options nobody uses (Band, Advanced…) only show while picked
              if (((o as Map)['count'] as num? ?? 0) > 0 || (picked.value[k] ?? const {}).contains(o['value'])) ('${o['value']}', '${o['label']}', (o['count'] as num).toInt()),
          ]),
      ];

  void _menu(BuildContext anchor, Map e) {
    final edit = e['can_edit'] == true;
    showAppMenu(anchor, width: 210, [
      MenuEntry('Open', icon: AppIcons.open, onTap: () => context.go('/exercises/${e['id']}')),
      if (edit) MenuEntry('Edit', icon: AppIcons.edit, onTap: () => context.go('/exercises/${e['id']}?edit=1')),
      if (canCreate && !edit) MenuEntry('Duplicate to edit', icon: AppIcons.copy, onTap: () => duplicateExercise(context, e)),
      MenuEntry('Add to program', icon: AppIcons.plus, onTap: () => showAddToProgram(context, e)),
      if (edit) const MenuEntry.separator(),
      if (edit)
        MenuEntry('Delete', icon: AppIcons.trash, danger: true, onTap: () async {
          if (await deleteExercise(context, e, onUndo: _load)) _load();
        }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final custom = ((facets['custom'] as num?) ?? 0).toInt();
    return StaffPage(
      onRefresh: _load,
      header: PageTop(
        title: 'Exercise library',
        sub: facets.isEmpty ? null : '${(facets['builtin'] as num?)?.toInt() ?? 0} built-in · $custom custom by your team',
        actions: [
          if (canCreate)
            phone
                ? AppButton.primary('New exercise', icon: AppIcons.plus, iconOnly: true, onPressed: () => context.go('/exercises/new'))
                : AppButton.primary('New exercise', icon: AppIcons.plus, onPressed: () => context.go('/exercises/new')),
        ],
      ),
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 10 : 12, children: [
          _tools(phone),
          ValueListenableBuilder(
            valueListenable: picked,
            builder: (_, p, _) => pickedCount(p) == 0
                ? const SizedBox.shrink()
                : LibFilterChips(
                    facets: _facets,
                    picked: picked,
                    trailing: Padding(padding: const EdgeInsets.only(top: 7), child: Text('$count of $total exercises', style: AppText.cap)),
                  ),
          ),
        ]),
        if (loading)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)))
        else if (error != null)
          AppCard(child: EmptyState('Could not load exercises', sub: error!.message, action: AppButton('Try again', onPressed: _load)))
        else if (rows.isEmpty)
          AppCard(
            child: EmptyState(
              q.isNotEmpty || pickedCount(picked.value) > 0 ? 'No exercise matches' : 'No exercises yet',
              icon: AppIcons.dumbbell,
              sub: q.isNotEmpty || pickedCount(picked.value) > 0 ? 'Try another name or clear the filters.' : 'Add the moves your team uses.',
              action: pickedCount(picked.value) > 0 ? AppButton('Clear filters', onPressed: () => picked.value = {}) : null,
            ),
          )
        else ...[
          LayoutBuilder(builder: (context, b) {
            final gap = phone ? 10.0 : 14.0;
            final cols = phone ? 2 : ((b.maxWidth + gap) / (200 + gap)).floor().clamp(2, 5);
            final w = (b.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(spacing: gap, runSpacing: gap, children: [
              for (final e in rows) SizedBox(width: w, child: _ExCard(e, phone: phone, onMenu: (a) => _menu(a, e))),
            ]);
          }),
          if (next != null) Center(child: AppButton(more ? 'Loading…' : 'Show more', onPressed: more ? null : _more)),
        ],
      ],
    );
  }

  Widget _tools(bool phone) {
    final search = AppSearchField(placeholder: 'Search exercises', icon: AppIcons.search, onChanged: _search);
    final filter = ValueListenableBuilder(
      valueListenable: picked,
      builder: (_, p, _) => LibFilterButton(count: pickedCount(p), onTap: (a) => showLibFilter(a, facets: _facets, picked: picked)),
    );
    final sortSel = SizedBox(
      width: 172,
      child: AppSelect(
        _sorts.firstWhere((s) => s.$1 == sort).$2,
        lead: 'Sort',
        entries: [
          for (final (v, l) in _sorts)
            MenuEntry(l, selected: v == sort, onTap: () {
              if (v == sort) return;
              setState(() => sort = v);
              _load();
            }),
        ],
      ),
    );
    if (phone) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        search,
        Row(children: [filter, const Spacer(), sortSel]),
      ]);
    }
    return Row(spacing: 8, children: [SizedBox(width: 340, child: search), filter, const Spacer(), sortSel]);
  }
}

/// `.ex-c` card: cover, name, "Chest · Barbell", then level badge, "2 programs" and ⋯.
class _ExCard extends StatelessWidget {
  const _ExCard(this.e, {required this.phone, required this.onMenu});
  final Map e;
  final bool phone;
  final void Function(BuildContext) onMenu;

  @override
  Widget build(BuildContext context) => Hover(
        onTap: () => context.go('/exercises/${e['id']}'),
        builder: (_, h, _) => Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: h ? AppColors.line2 : AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AspectRatio(aspectRatio: phone ? 16 / 9 : 16 / 10, child: ExCover(e, radius: 0)),
            Padding(
              padding: phone ? const EdgeInsets.fromLTRB(10, 8, 10, 8) : const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 3 : 4, children: [
                SizedBox(
                  height: phone ? 34 : null,
                  child: Text('${e['name']}',
                      maxLines: phone ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.s(phone ? 13 : 13.5, W.w7, color: h ? AppColors.accentText : AppColors.text, h: 1.3)),
                ),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: exMuscleLabel(e), style: AppText.s(phone ? 11.5 : 12.5, W.w6, color: AppColors.text2)),
                    TextSpan(text: '  ·  ${exEquipLabel(e)}'),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.s(phone ? 11.5 : 12.5, W.w5, color: AppColors.muted),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: EdgeInsets.only(top: phone ? 6 : 8),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                  child: Row(spacing: phone ? 6 : 8, children: [
                    AppBadge(exLevelLabel(e), tone: levelTone('${e['level']}'), plain: true),
                    Expanded(child: Text(usedLabel(e['programs']), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted))),
                    Builder(builder: (b) => SizedBox(height: 22, child: AppIconButton(AppIcons.dots, tooltip: 'More actions', small: true, ghost: true, onPressed: () => onMenu(b)))),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      );
}
