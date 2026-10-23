import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/pager.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tooltip.dart';
import '../../../core/widgets/table_head.dart';
import 'cp_common.dart';
import 'cp_content_drawers.dart';
import 'cp_model.dart';

/// Client profile → Content tab (`clients/<id>/content/`): everything the client sees in the Library of her app
/// and why. Chips All · Assigned to Riya · From her plans · Everyone (with counts) and the info tip, Assign content
/// (drawer), and the table Title · Type · Why Riya sees it · Added by · Seen · ⋯ (Preview · Change how long ·
/// Remind her to open it · Open in library · Remove / Hide for Riya, with Undo). A row opens the preview drawer.
class CpContentTab extends StatefulWidget {
  const CpContentTab(this.c, {super.key});
  final CpController c;
  @override
  State<CpContentTab> createState() => _CpContentTabState();
}

class _CpContentTabState extends State<CpContentTab> {
  static const _size = 25;
  CpController get c => widget.c;
  final _hScroll = ScrollController();
  String why = 'all';
  int page = 1, count = 0;
  Map counts = const {};
  Map? plan;
  List<Map> rows = [];
  bool loading = true;
  ApiError? error;
  int _seen = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CpContentTab old) {
    super.didUpdateWidget(old);
    if (_seen != c.version) _load();
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _seen = c.version;
    try {
      final r = await Services.api.get<Map>('clients/${c.id}/content/', query: {'why': why, 'page': page, 'page_size': _size});
      if (!mounted) return;
      setState(() {
        rows = [for (final x in (r['results'] as List? ?? const [])) x as Map];
        count = (r['count'] as num?)?.toInt() ?? rows.length;
        counts = (r['counts'] as Map?) ?? const {};
        plan = r['plan'] as Map?;
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

  void _pick(String w) {
    setState(() {
      why = w;
      page = 1;
    });
    _load();
  }

  String get her => cpHer(c);

  // ─────────────────────────────── Actions

  Future<void> _assign() async {
    final n = await showAssignContentDrawer(context, c);
    if (n != null && n > 0 && mounted) {
      showToast(context, n == 1 ? '1 item assigned to ${c.first}' : '$n items assigned to ${c.first}', sub: 'It shows in the Library of $her app');
      await c.refresh();
    }
  }

  Future<void> _preview(Map r) async {
    final act = await showContentPreview(context, c, r);
    switch (act) {
      case 'remove':
        await _unshare(r);
      case 'remind':
        await _remind(r);
      case 'library':
        _openInLibrary(r);
    }
  }

  void _openInLibrary(Map r) => context.go('/content/${r['id']}');

  Future<void> _unshare(Map r) async {
    final hide = r['why'] != 'assigned';
    try {
      await Services.api.post('clients/${c.id}/content/${r['id']}/unshare/');
      if (!mounted) return;
      showToast(context, hide ? 'Hidden for ${c.first}' : 'Removed for ${c.first}', sub: '${r['title']}', action: 'Undo', onAction: () async {
        try {
          await Services.api.post('clients/${c.id}/content/${r['id']}/restore/');
          await c.refresh();
        } on ApiError catch (e) {
          if (mounted) showToast(context, 'Could not bring it back', sub: e.message);
        }
      });
      await c.refresh();
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not change this', sub: e.message);
    }
  }

  Future<void> _remind(Map r) async {
    try {
      await Services.api.post('clients/${c.id}/content/${r['id']}/remind/');
      if (!mounted) return;
      showToast(context, 'Reminder sent to ${c.first}', sub: '${r['title']}');
      await _load();
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not send the reminder', sub: e.message);
    }
  }

  Future<void> _howLong(Map r) async {
    final label = await showHowLongModal(context, c, r, plan);
    if (label != null && mounted) {
      showToast(context, 'Saved', sub: '${r['title']} · $label');
      await c.refresh();
    }
  }

  void _menu(BuildContext anchor, Map r) => showAppMenu(anchor, [
        MenuEntry('Preview', icon: AppIcons.eye, onTap: () => _preview(r)),
        MenuEntry('Change how long', icon: AppIcons.clock, onTap: () => _howLong(r)),
        MenuEntry('Remind ${cpHerObj(c)} to open it', icon: AppIcons.bell, onTap: () => _remind(r)),
        MenuEntry('Open in library', icon: AppIcons.external, onTap: () => _openInLibrary(r)),
        MenuEntry(r['why'] == 'assigned' ? 'Remove for ${c.first}' : 'Hide for ${c.first}', icon: AppIcons.stop, danger: true, onTap: () => _unshare(r)),
      ], width: 220);

  // ─────────────────────────────── Build

  @override
  Widget build(BuildContext context) {
    if (loading) return const AppCard(child: CpLoading());
    if (error != null) return CpError(error!.message, onRetry: _load);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _tools(context),
        if (rows.isEmpty)
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            child: why == 'all'
                ? EmptyState('Nothing in ${c.first}’s Library yet',
                    sub: 'Assign videos, guides and PDFs from the library. They show in the Library of $her app.',
                    action: AppButton('Assign content', icon: AppIcons.plus, onPressed: _assign))
                : EmptyState('Nothing here', sub: 'Nothing ${c.first} sees comes from here right now.'),
          )
        else
          _table(),
        if (count > _size)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Pager(page: page, pageSize: _size, count: count, onPage: (p) {
              setState(() => page = p);
              _load();
            }),
          ),
      ]),
    );
  }

  // `.tbl-tools`: the chips (sideways on a phone), the info tip, Assign content on the right.
  Widget _tools(BuildContext context) {
    final phone = context.isPhone;
    int n(String k) => (counts[k] as num?)?.toInt() ?? 0;
    final chips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(spacing: 6, children: [
        for (final (k, l) in [('all', 'All'), ('assigned', 'Assigned to ${c.first}'), ('plan', 'From $her plans'), ('everyone', 'Everyone')])
          FilterChipX(l, selected: why == k, count: n(k), onTap: () => _pick(k)),
      ]),
    );
    final info = AppTooltip(
      message: 'Everything ${c.first} sees in the Library of $her app, and why. Content from a plan goes away when that plan ends.',
      side: TipSide.below,
      child: Hover(
        builder: (_, h, _) => Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: h ? AppColors.accentSoft : null, borderRadius: AppRadius.all(6)),
          child: AppIcon(AppIcons.info, size: 16, color: h ? AppColors.accent : AppColors.muted),
        ),
      ),
    );
    final btn = AppButton('Assign content', icon: AppIcons.plus, onPressed: _assign);
    return Padding(
      padding: phone ? const EdgeInsets.fromLTRB(16, 14, 16, 12) : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: phone
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [chips, Row(children: [info, const Spacer(), btn])])
          : Row(spacing: 8, children: [Expanded(child: Row(spacing: 8, children: [Flexible(child: chips), info])), btn]),
    );
  }

  static const _cols = <(String, double)>[('Title', 300), ('Type', 96), ('', 250), ('Added by', 150), ('Seen', 150), ('', 56)];

  Widget _table() => LayoutBuilder(builder: (context, box) {
        final head = ['Title', 'Type', 'Why ${c.first} sees it', 'Added by', 'Seen', ''];
        final base = [for (final (i, x) in _cols.indexed) headFit(head[i], x.$2, pad: i == 0 ? 28 : 24)];
        final min = base.fold<double>(0, (a, w) => a + w);
        final extra = (box.maxWidth - min).clamp(0.0, double.infinity);
        final widths = [for (final (i, w) in base.indexed) w + (i == 0 ? extra : 0)];
        final table = SizedBox(
          width: min + extra,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 34,
              decoration: const BoxDecoration(color: AppColors.tableHeadDt, border: Border.symmetric(horizontal: BorderSide(color: AppColors.line))),
              child: Row(children: [
                for (final (i, l) in head.indexed)
                  Container(
                    width: widths[i],
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 0),
                    alignment: Alignment.centerLeft,
                    child: Text(l.toUpperCase(), maxLines: 1, softWrap: false, style: tableHeadStyle),
                  ),
              ]),
            ),
            for (final (i, r) in rows.indexed) _row(r, widths, last: i == rows.length - 1),
          ]),
        );
        if (box.maxWidth >= min) return table;
        return Scrollbar(
          controller: _hScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(controller: _hScroll, scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(bottom: 8), child: table),
        );
      });

  Widget _row(Map r, List<double> widths, {required bool last}) {
    Widget cell(int i, Widget child, {bool right = false}) => Container(
          width: widths[i],
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          child: child,
        );
    final body = AppText.s(13.5, W.w4);
    final opened = r['opened_at'];
    return Hover(
      onTap: () => _preview(r),
      builder: (_, h, _) => Container(
        height: 45,
        decoration: BoxDecoration(color: h ? AppColors.hover : null, border: last ? null : const Border(bottom: BorderSide(color: AppColors.line))),
        child: Row(children: [
          cell(
            0,
            Row(spacing: 10, children: [
              cpIcon(cpContentIcon('${r['kind']}'), size: 30),
              Expanded(child: CutText('${r['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7))),
            ]),
          ),
          cell(1, Text('${r['kind_label']}', maxLines: 1, style: body)),
          cell(2, _Fit(AppBadge('${r['why_label']}', tone: cpWhyTone('${r['why']}'), plain: true))),
          cell(3, CutText('${r['added_by']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: body)),
          cell(4, opened == null ? const AppBadge('Not opened', plain: true) : Text('Opened ${cpShortAgo(opened)}', maxLines: 1, style: AppText.cap)),
          cell(5, Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'More actions', small: true, fill: true, onPressed: () => _menu(b, r))), right: true),
        ]),
      ),
    );
  }
}

/// A badge that shrinks with its column instead of overflowing.
class _Fit extends StatelessWidget {
  const _Fit(this.child);
  final Widget child;
  @override
  Widget build(BuildContext context) => FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: child);
}
