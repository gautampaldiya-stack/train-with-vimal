import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../app/shell/page.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/pager.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tabs.dart';
import '../../../core/widgets/tooltip.dart';
import 'forms_common.dart';

/// Admin → Forms & check-ins (boards `Forms` + `FormsMobile`, D-50): every library form with its kind, questions,
/// how it is sent and status. Search, Form type dropdown, All / Archived. Row opens the Form builder; ⋯: Edit
/// questions, Preview, Duplicate, Archive / Restore, Delete form. `Create form` opens the modal, then the builder.
class FormsScreen extends StatefulWidget {
  const FormsScreen({super.key});
  @override
  State<FormsScreen> createState() => _FormsScreenState();
}

class _FormsScreenState extends State<FormsScreen> {
  static const pageSize = 25;
  final _hScroll = ScrollController();
  List<Map> rows = [];
  Map counts = {};
  String tab = 'all', kind = '', search = '';
  int page = 1, count = 0;
  bool loading = true;
  ApiError? error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hScroll.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final q = {'tab': tab, if (kind.isNotEmpty) 'type': kind, if (search.isNotEmpty) 'search': search, 'page': '$page'};
      final r = await Future.wait([Services.api.get<Map>('forms/', query: q), Services.api.get<Map>('forms/counts/')]);
      if (!mounted) return;
      setState(() {
        rows = [for (final x in (r[0]['results'] as List? ?? const [])) x as Map];
        count = (r[0]['count'] as num?)?.toInt() ?? rows.length;
        counts = r[1];
        error = null;
        loading = false;
      });
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          loading = false;
        });
      }
    }
  }

  void _set(VoidCallback f) {
    setState(f);
    page = 1;
    load();
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    return StaffPage(
      onRefresh: load,
      header: PageTop(
        title: 'Forms & check-ins',
        sub: 'Onboarding questionnaires, weekly and daily check-ins, surveys and waivers.',
        actions: [AppButton.primary('Create form', icon: AppIcons.plus, iconOnly: compactTop(context), tooltip: 'Create form', onPressed: _create)],
      ),
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _tools(phone),
              if (error != null && rows.isEmpty)
                EmptyState('Could not load forms', sub: error!.message, action: AppButton('Try again', onPressed: load))
              else if (loading && rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))),
                )
              else if (rows.isEmpty)
                _empty()
              else
                phone ? _list() : _table(),
            ]),
          ),
          if (count > pageSize) Pager(page: page, pageSize: pageSize, count: count, empty: 'No forms', onPage: (p) {
            setState(() => page = p);
            load();
          }),
        ]),
      ],
    );
  }

  // ─────────────────────────────── Tools: search, Form type, All / Archived

  Widget _tools(bool phone) {
    final s = AppSearchField(
      placeholder: 'Search forms',
      icon: AppIcons.search,
      onChanged: (v) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 300), () => _set(() => search = v.trim()));
      },
    );
    final tabs = SegmentedTabs<String>(
      items: [TabItem('all', 'All', count: (counts['all'] as num?)?.toInt()), TabItem('archived', 'Archived', count: (counts['archived'] as num?)?.toInt())],
      value: tab,
      onChanged: (v) => _set(() => tab = v),
    );
    if (phone) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          s,
          Row(spacing: 8, children: [Expanded(child: _kindSelect()), tabs]),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.spaceBetween, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          SizedBox(width: 320, child: s),
          SizedBox(width: 190, child: _kindSelect()),
        ]),
        tabs,
      ]),
    );
  }

  /// `.fm-ksel`: the picked kind (icon) · label · count ⌄; the menu is headed "Form type".
  Widget _kindSelect() {
    final all = (counts['all'] as num?)?.toInt() ?? 0;
    final opts = [
      ('', 'All forms', all),
      for (final k in formKinds) (k.$1, k.$4, (counts[k.$1] as num?)?.toInt() ?? 0),
    ];
    final cur = opts.firstWhere((o) => o.$1 == kind, orElse: () => opts.first);
    return Builder(
      builder: (b) => Hover(
        onTap: () => showAppMenu(b, alignRight: false, width: 240, [
          const MenuEntry.header('Form type'),
          for (final o in opts)
            MenuEntry(o.$2,
                lead: o.$1.isEmpty
                    ? const AppIcon(AppIcons.clipboard, size: 15, color: AppColors.okText)
                    : AppIcon(kindIcon(o.$1), size: 15, color: kindTone(o.$1).$2),
                end: '${o.$3}',
                selected: o.$1 == kind,
                onTap: () => _set(() => kind = o.$1)),
        ]),
        builder: (_, h, _) => Container(
          height: 36,
          padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppRadius.all(AppRadius.input),
            border: Border.all(color: h ? AppColors.lineHover : AppColors.line2),
          ),
          child: Row(spacing: 8, children: [
            if (kind.isNotEmpty) AppIcon(kindIcon(kind), size: 15, color: AppColors.muted),
            Expanded(child: fmCut(cur.$2, AppText.s(13.5, W.w6))),
            Text('${cur.$3}', style: AppText.s(11.5, W.w7, color: AppColors.muted)),
            const AppIcon(AppIcons.chevronDown, size: 16, color: AppColors.muted),
          ]),
        ),
      ),
    );
  }

  Widget _empty() {
    if (search.isNotEmpty) {
      return EmptyState('No forms match', sub: 'Try another name.', icon: AppIcons.clipboard);
    }
    return tab == 'archived'
        ? const EmptyState('Nothing archived', sub: 'Forms you archive show up here.', icon: AppIcons.clipboard)
        : const EmptyState('No forms here yet', sub: 'There is no form of this type. Create one to start.', icon: AppIcons.clipboard);
  }

  // ─────────────────────────────── Web table (`.tbl.cmp.nu-ft`)

  static const _cols = <(String, double)>[
    ('Form', 240),
    ('Questions', 110),
    ('How it is sent', 290),
    ('Status', 110),
    ('Updated', 96),
    ('', 52),
  ];

  Widget _table() => LayoutBuilder(builder: (context, box) {
        final min = _cols.fold<double>(0, (a, x) => a + x.$2);
        final extra = (box.maxWidth - min).clamp(0.0, double.infinity);
        final widths = [for (final (i, x) in _cols.indexed) x.$2 + (i == 0 ? extra * .5 : (i == 2 ? extra * .5 : 0))];
        final table = SizedBox(
          width: min + extra,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 32,
              decoration: const BoxDecoration(color: AppColors.tableHead, border: Border.symmetric(horizontal: BorderSide(color: AppColors.line))),
              child: Row(children: [
                for (final (i, x) in _cols.indexed)
                  Container(
                    width: widths[i],
                    padding: EdgeInsets.fromLTRB(i == 0 ? 12 : 10, 0, 10, 0),
                    alignment: Alignment.centerLeft,
                    child: Text(x.$1, maxLines: 1, style: AppText.s(12, W.w7, color: AppColors.muted)),
                  ),
              ]),
            ),
            for (final (i, f) in rows.indexed) _row(f, widths, i == rows.length - 1),
          ]),
        );
        if (box.maxWidth >= min) return table;
        return Scrollbar(
          controller: _hScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(controller: _hScroll, scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(bottom: 8), child: table),
        );
      });

  Widget _cell(List<double> w, int i, Widget child) =>
      Container(width: w[i], padding: EdgeInsets.fromLTRB(i == 0 ? 12 : 10, 0, i == _cols.length - 1 ? 12 : 10, 0), alignment: Alignment.centerLeft, child: child);

  Widget _name(Map f, {bool phone = false}) => Row(spacing: 10, children: [
        KindTile('${f['type']}'),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
            fmCut('${f['name']}', AppText.s(phone ? 14 : 13.5, W.w7)),
            fmCut(kindLabel('${f['type']}'), AppText.s(12, W.w5, color: AppColors.muted)),
          ]),
        ),
      ]);

  /// `.fm-send`: bolt + automation (+N more) or the app's own way; else "Sent by hand" + Set up automation.
  Widget _send(Map f, {double size = 13}) {
    final autos = [for (final a in (f['sent_by'] as List?) ?? const []) '$a'];
    final builtIn = '${f['built_in'] ?? ''}';
    if (autos.isEmpty && builtIn.isEmpty) {
      return Row(spacing: 4, children: [
        Text('Sent by hand', maxLines: 1, style: AppText.s(size, W.w5, color: AppColors.muted)),
        const SizedBox(width: 2),
        Flexible(child: AppButton('Set up automation', kind: BtnKind.text, size: BtnSize.sm, onPressed: () => context.go('/automations'))),
      ]);
    }
    final line = autos.isNotEmpty ? autos.first : builtIn;
    return Row(spacing: 6, children: [
      const AppIcon(AppIcons.bolt, size: 15, color: AppColors.fmBolt),
      Flexible(child: fmCut(line, AppText.s(size, W.w5))),
      if (autos.length > 1)
        AppTooltip(message: autos.skip(1).join('\n'), child: Text('+${autos.length - 1} more', style: AppText.s(12, W.w6, color: AppColors.muted))),
    ]);
  }

  Widget _dots(Map f) => Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'Form options', small: true, ghost: true, onPressed: () => _menu(b, f)));

  Widget _row(Map f, List<double> w, bool last) => Hover(
        onTap: () => context.go('/forms/${f['id']}'),
        builder: (_, h, _) => Container(
          height: 48,
          decoration: BoxDecoration(color: h ? AppColors.hover : null, border: last ? null : const Border(bottom: BorderSide(color: AppColors.line))),
          child: Row(children: [
            _cell(w, 0, _name(f)),
            _cell(w, 1, Text(questionsLabel((f['question_count'] as num?)?.toInt() ?? 0), maxLines: 1, style: AppText.s(13, W.w5))),
            _cell(w, 2, _send(f)),
            _cell(w, 3, formBadge(f)),
            _cell(w, 4, Text(fmWhen(f['updated_at']), maxLines: 1, style: AppText.s(13, W.w5, color: AppColors.muted))),
            _cell(w, 5, _dots(f)),
          ]),
        ),
      );

  // ─────────────────────────────── Phone list (`FormsMobile`)

  Widget _list() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final f in rows)
          Hover(
            onTap: () => context.go('/forms/${f['id']}'),
            builder: (_, h, _) => Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              decoration: BoxDecoration(color: h ? AppColors.hover : null, border: const Border(top: BorderSide(color: AppColors.line))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
                Row(spacing: 8, children: [Expanded(child: _name(f, phone: true)), formBadge(f), _dots(f)]),
                Padding(
                  padding: const EdgeInsets.only(left: 40),
                  child: Row(children: [
                    Text('${questionsLabel((f['question_count'] as num?)?.toInt() ?? 0)} · ', style: AppText.s(12, W.w6, color: AppColors.muted)),
                    Expanded(child: _send(f, size: 12)),
                  ]),
                ),
              ]),
            ),
          ),
      ]);

  // ─────────────────────────────── Actions

  Future<void> _create() async {
    final f = await showCreateForm(context);
    if (f == null || !mounted) return;
    context.go('/forms/${f['id']}');
  }

  void _menu(BuildContext anchor, Map f) {
    final archived = f['status'] == 'archived';
    showAppMenu(anchor, width: 240, [
      MenuEntry.header('${f['name']}'),
      MenuEntry('Edit questions', icon: AppIcons.edit, onTap: () => context.go('/forms/${f['id']}')),
      MenuEntry('Preview', icon: AppIcons.eye, onTap: () => _preview(f)),
      MenuEntry('Duplicate', icon: AppIcons.copy, onTap: () => _duplicate(f)),
      if (archived) MenuEntry('Restore', icon: AppIcons.restart, onTap: () => _restore(f)) else MenuEntry('Archive', icon: AppIcons.formArchive, onTap: () => _archive(f)),
      const MenuEntry.separator(),
      MenuEntry('Delete form', icon: AppIcons.trash, danger: true, onTap: () => _delete(f)),
    ]);
  }

  Future<T?> _call<T>(Future<T> Function() f, String failed) async {
    try {
      return await f();
    } on ApiError catch (e) {
      if (mounted) showToast(context, failed, sub: e.message, kind: ToastKind.err);
      return null;
    }
  }

  Future<void> _preview(Map f) async {
    final d = await _call(() => Services.api.get<Map>('forms/${f['id']}/'), 'Could not open the preview');
    if (d == null || !mounted) return;
    await showFormPreview(context, name: '${d['name']}', questions: [for (final q in (d['questions'] as List? ?? const [])) FmQ(q as Map)]);
  }

  Future<void> _duplicate(Map f) async {
    final r = await _call(() => Services.api.post<Map>('forms/${f['id']}/duplicate/'), 'Could not duplicate the form');
    if (r == null || !mounted) return;
    load();
    showToast(context, 'Form duplicated', sub: 'Saved as a draft', action: 'Undo', onAction: () async {
      await _call(() => Services.api.delete('forms/${r['id']}/'), 'Could not undo');
      load();
    });
  }

  Future<void> _archive(Map f) async {
    final r = await _call(() => Services.api.post<Map>('forms/${f['id']}/archive/'), 'Could not archive the form');
    if (r == null || !mounted) return;
    load();
    showToast(context, 'Form archived', sub: 'It is no longer sent to clients', action: 'Undo', onAction: () async {
      await _call(() => Services.api.post('forms/${f['id']}/unarchive/', {'status': r['previous_status']}), 'Could not undo');
      load();
    });
  }

  Future<void> _restore(Map f) async {
    final r = await _call(() => Services.api.post<Map>('forms/${f['id']}/unarchive/', {'status': 'published'}), 'Could not restore the form');
    if (r == null || !mounted) return;
    load();
    showToast(context, 'Form restored', sub: '${f['name']}', kind: ToastKind.ok, action: 'Undo', onAction: () async {
      await _call(() => Services.api.post('forms/${f['id']}/archive/'), 'Could not undo');
      load();
    });
  }

  Future<void> _delete(Map f) async {
    final ok = await confirmAction(context,
        title: 'Delete this form?',
        body: '${f['name']} is removed for good. Answers clients already sent stay in their profiles.',
        confirm: 'Delete',
        danger: true,
        icon: AppIcons.trash);
    if (!ok || !mounted) return;
    final r = await _call(() async {
      await Services.api.delete('forms/${f['id']}/');
      return true;
    }, 'Could not delete the form');
    if (r == null || !mounted) return;
    load();
    showToast(context, 'Form deleted', sub: '${f['name']}', action: 'Undo', onAction: () async {
      await _call(() => Services.api.post('forms/${f['id']}/restore/'), 'Could not undo');
      load();
    });
  }
}
