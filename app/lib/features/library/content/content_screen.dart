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
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tabs.dart';
import '../../../core/widgets/tooltip.dart';
import '../lib_common.dart' show SearchTabsRow;
import 'content_drawers.dart';
import 'ct_common.dart';

/// Content library (boards `Content` / `ContentMobile`): categories rail with counts and the storage bar, search,
/// All · Videos · Articles · PDFs · Images, picture cards 8 to a page, and the item drawer. [open] opens one item
/// (`/content/<id>`); [newKind] opens New content on that type (`/content?new=video`, from "Upload to library").
class ContentScreen extends StatefulWidget {
  const ContentScreen({super.key, this.open, this.newKind});
  final String? open, newKind;
  @override
  State<ContentScreen> createState() => _ContentScreenState();
}

const _pageSize = 8;

class _ContentScreenState extends State<ContentScreen> {
  Map summary = const {};
  List<Map> cats = const [], rows = const [];
  int count = 0, page = 1;
  String kind = '', q = '';
  String? cat;
  bool loading = true;
  ApiError? error;
  Timer? _debounce;
  int _req = 0;

  bool get canManage => (summary['can'] as Map?)?['manage'] == true;
  bool get canEveryone => (summary['can'] as Map?)?['everyone'] == true;
  int get pages => count == 0 ? 1 : (count + _pageSize - 1) ~/ _pageSize;

  @override
  void initState() {
    super.initState();
    _first();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _first() async {
    await Future.wait([_loadMeta(), _load()]);
    if (!mounted) return;
    if (widget.open != null) {
      _openItem(widget.open!);
    } else if (widget.newKind != null && canManage) {
      _new(type: widget.newKind);
    }
  }

  Future<void> _loadMeta() async {
    try {
      final r = await Future.wait([Services.api.get<Map>('content/summary/'), Services.api.get<List>('content-categories/')]);
      if (!mounted) return;
      setState(() {
        summary = r[0] as Map;
        cats = [for (final c in r[1] as List) c as Map];
      });
    } on ApiError {
      // the rail keeps what it had; the grid shows its own error
    }
  }

  Future<void> _load() async {
    final req = ++_req;
    setState(() => loading = rows.isEmpty);
    try {
      final r = await Services.api.get<Map>('content/', query: {
        'page': page,
        'page_size': _pageSize,
        if (kind.isNotEmpty) 'kind': kind,
        if (cat != null) 'category': cat,
        if (q.isNotEmpty) 'search': q,
      });
      if (req != _req || !mounted) return;
      setState(() {
        rows = [for (final x in r['results'] as List) x as Map];
        count = (r['count'] as num?)?.toInt() ?? rows.length;
        error = null;
        loading = false;
      });
    } on ApiError catch (e) {
      if (req != _req || !mounted) return;
      // a page past the end (after a delete) goes back to the last one
      if (e.status == 404 && page > 1) {
        page = 1;
        return _load();
      }
      setState(() {
        error = e;
        loading = false;
      });
    }
  }

  Future<void> _reload() => Future.wait([_loadMeta(), _load()]);

  void _filter(VoidCallback f) {
    setState(() {
      f();
      page = 1;
    });
    _load();
  }

  void _search(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _filter(() => q = v.trim()));
  }

  // ─────────────────────────────── actions

  Future<void> _openItem(String id) async {
    final r = await showContentDetail(context, id, canManage: canManage);
    if (!mounted || r == null) return;
    if (r.startsWith('go:')) {
      context.go(r.substring(3));
      return;
    }
    Map item;
    try {
      item = await Services.api.get<Map>('content/$id/');
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not open it', sub: e.message, kind: ToastKind.err);
      return;
    }
    if (!mounted) return;
    switch (r) {
      case 'edit':
        _edit(item);
      case 'assign':
        showContentAssign(context, item, canEveryone: canEveryone, onSaved: _reload);
      case 'delete':
        _delete(item);
    }
  }

  Future<void> _new({String? type}) async {
    final r = await showContentEditor(context, cats: cats, cat: cat, kind: type, canEveryone: canEveryone);
    if (r == null || !mounted) return;
    showToast(context, 'Added to the library', sub: r['share_everyone'] == true ? 'Shared with everyone' : 'Not assigned to anyone yet', kind: ToastKind.ok);
    setState(() {
      cat = null;
      kind = '';
      page = 1;
    });
    _reload();
  }

  Future<void> _edit(Map item) async {
    final r = await showContentEditor(context, item: item, cats: cats, canEveryone: canEveryone);
    if (r == null || !mounted) return;
    showToast(context, 'Changes saved', sub: '${r['title']}', kind: ToastKind.ok);
    _reload();
  }

  Future<void> _delete(Map item) async {
    if (await deleteContent(context, item, onUndo: () {
      if (mounted) _reload();
    })) {
      _reload();
    }
  }

  Future<void> _newCategory() async {
    final c = await showNewCategory(context);
    if (c == null || !mounted) return;
    await _loadMeta();
    _filter(() => cat = '${c['id']}');
  }

  void _menu(BuildContext anchor, Map x) {
    showAppMenu(anchor, width: 210, [
      MenuEntry.header('${x['title']}'),
      MenuEntry('Open', icon: AppIcons.eye, onTap: () => _openItem('${x['id']}')),
      if (canManage) ...[
        MenuEntry('Edit', icon: AppIcons.edit, onTap: () => _edit(x)),
        MenuEntry('Assign to clients', icon: AppIcons.assign, onTap: () => showContentAssign(context, x, canEveryone: canEveryone, onSaved: _reload)),
        const MenuEntry.separator(),
        MenuEntry('Delete', icon: AppIcons.trash, danger: true, onTap: () => _delete(x)),
      ],
    ]);
  }

  // ─────────────────────────────── build

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    return StaffPage(
      onRefresh: _reload,
      header: PageTop(
        title: 'Content library',
        sub: 'Videos, articles, PDFs and images. Use them in exercises, programs and meal plans, or share them with clients.',
        actions: [
          if (canManage) ...[
            AppButton('New category', icon: AppIcons.plus, iconOnly: phone, onPressed: _newCategory),
            AppButton.primary('New content', icon: AppIcons.importFile, iconOnly: phone, onPressed: _new),
          ],
        ],
      ),
      children: [
        LayoutBuilder(builder: (context, b) {
          final rail = !phone && b.maxWidth >= 760;
          if (rail) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
              SizedBox(width: 220, child: _rail()),
              Expanded(child: _main(phone)),
            ]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            _chips(),
            _storeLine(),
            _main(phone),
          ]);
        }),
      ],
    );
  }

  int get _total => (summary['total'] as num?)?.toInt() ?? 0;

  (double, String) get _storage {
    final s = summary['storage'] as Map? ?? const {};
    final used = (s['used'] as num?) ?? 0, limit = (s['limit'] as num?) ?? 1;
    return (used / (limit == 0 ? 1 : limit), 'Storage: ${used == 0 ? '0 GB' : ctSize(used)} of ${ctSize(limit)} used');
  }

  /// `.ct-rail`: Categories, All content + each category with its count, New category, storage bar.
  Widget _rail() {
    final (frac, label) = _storage;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 2, children: [
        Padding(padding: const EdgeInsets.fromLTRB(8, 2, 8, 6), child: Text('CATEGORIES', style: AppText.over)),
        _CatRow('All content', _total, on: cat == null, onTap: () => _filter(() => cat = null)),
        for (final c in cats) _CatRow('${c['name']}', (c['count'] as num?)?.toInt() ?? 0, on: cat == '${c['id']}', onTap: () => _filter(() => cat = '${c['id']}')),
        if (canManage)
          Padding(
            padding: const EdgeInsets.only(left: 10, top: 2),
            child: Align(alignment: Alignment.centerLeft, child: AppButton('New category', kind: BtnKind.text, icon: AppIcons.plus, onPressed: _newCategory)),
          ),
        Container(
          margin: const EdgeInsets.fromLTRB(8, 12, 8, 2),
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
            ProgressBar(value: frac == 0 ? 0 : frac.clamp(.02, 1), height: 5),
            Text(label, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
          ]),
        ),
      ]),
    );
  }

  /// Phone: the categories as a row of chips that scrolls sideways.
  Widget _chips() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(spacing: 6, children: [
          _CatChip('All content', _total, on: cat == null, onTap: () => _filter(() => cat = null)),
          for (final c in cats) _CatChip('${c['name']}', (c['count'] as num?)?.toInt() ?? 0, on: cat == '${c['id']}', onTap: () => _filter(() => cat = '${c['id']}')),
        ]),
      );

  Widget _storeLine() {
    final (frac, label) = _storage;
    return Row(spacing: 10, children: [
      SizedBox(width: 72, child: ProgressBar(value: frac == 0 ? 0 : frac.clamp(.02, 1), height: 5)),
      Expanded(child: Text(label, style: AppText.s(11.5, W.w6, color: AppColors.muted))),
    ]);
  }

  Widget _main(bool phone) => LayoutBuilder(builder: (context, b) {
        final w = b.maxWidth;
        final search = AppSearchField(placeholder: 'Search the library', icon: AppIcons.search, onChanged: _search);
        final tabs = SegmentedTabs<String>(
          items: [for (final (k, l) in ctKinds) TabItem(k, l)],
          value: kind,
          onChanged: (v) => _filter(() => kind = v),
        );
        final gap = phone ? 10.0 : 14.0;
        final cols = phone ? 2 : ((w + gap) / (190 + gap)).floor().clamp(2, 4);
        final cw = (w - gap * (cols - 1)) / cols;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 12 : 14, children: [
          if (w >= 640)
            SearchTabsRow(search: search, tabs: tabs, searchWidth: 300)
          else ...[
            search,
            Align(alignment: Alignment.centerLeft, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: tabs)),
          ],
          if (loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)))
          else if (error != null)
            AppCard(child: EmptyState('Could not load the library', sub: error!.message, action: AppButton('Try again', onPressed: _load)))
          else if (rows.isEmpty)
            AppCard(
              child: EmptyState(
                q.isNotEmpty ? 'Nothing matches “$q”' : 'Nothing in this category yet',
                icon: AppIcons.content,
                sub: q.isNotEmpty ? 'Try another word.' : 'Add a video, article, PDF or image.',
                action: canManage && q.isEmpty ? AppButton.primary('New content', icon: AppIcons.importFile, onPressed: _new) : null,
              ),
            )
          else
            Wrap(spacing: gap, runSpacing: gap, children: [
              for (final x in rows)
                SizedBox(
                  width: cw,
                  child: _CtCard(x, phone: phone, onOpen: () => _openItem('${x['id']}'), onMenu: (a) => _menu(a, x)),
                ),
            ]),
          if (!loading && error == null && count > 0) _pager(),
        ]);
      });

  /// `.pager`: "1–8 of 25 items" and previous / next.
  Widget _pager() {
    final from = (page - 1) * _pageSize + 1, to = (page * _pageSize).clamp(0, count);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(spacing: 6, children: [
        Expanded(child: Text('$from–$to of $count ${count == 1 ? 'item' : 'items'}', style: AppText.s(12.5, W.w6, color: AppColors.muted))),
        AppIconButton(AppIcons.chevronLeft, tooltip: 'Previous page', small: true, onPressed: page > 1 ? () => _go(page - 1) : null),
        AppIconButton(AppIcons.chevronRight, tooltip: 'Next page', small: true, onPressed: page < pages ? () => _go(page + 1) : null),
      ]),
    );
  }

  void _go(int p) {
    setState(() => page = p);
    _load();
  }
}

/// `.ct-cat`: a rail row, name and count; picked = blue.
class _CatRow extends StatelessWidget {
  const _CatRow(this.label, this.n, {required this.on, required this.onTap});
  final String label;
  final int n;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: on ? AppColors.accentSoft : (h ? AppColors.hover : null), borderRadius: AppRadius.all(8)),
          child: Row(spacing: 8, children: [
            Expanded(
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w6, color: on ? AppColors.accentText : (h ? AppColors.text : AppColors.text2))),
            ),
            Text('$n', style: AppText.s(11.5, W.w7, color: AppColors.muted)),
          ]),
        ),
      );
}

/// Phone `.ct-cat` chip: 32 high, round; picked = black.
class _CatChip extends StatelessWidget {
  const _CatChip(this.label, this.n, {required this.on, required this.onTap});
  final String label;
  final int n;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: on ? AppColors.text : (h ? AppColors.hover : AppColors.card),
            borderRadius: AppRadius.all(16),
            border: Border.all(color: on ? AppColors.text : AppColors.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
            Text(label, style: AppText.s(13, W.w6, color: on ? AppColors.white : AppColors.text2)),
            Text('$n', style: AppText.s(11.5, W.w7, color: on ? AppColors.ctChipOnN : AppColors.muted)),
          ]),
        ),
      );
}

/// `.ct-c`: picture with the kind and length, title (two lines kept so cards line up), "0:42 · Category", where it
/// is used, who has it and ⋯.
class _CtCard extends StatelessWidget {
  const _CtCard(this.x, {required this.phone, required this.onOpen, required this.onMenu});
  final Map x;
  final bool phone;
  final VoidCallback onOpen;
  final void Function(BuildContext) onMenu;

  @override
  Widget build(BuildContext context) {
    final used = ctUsed(x);
    final who = '${x['who'] ?? 'Not assigned'}';
    final whoColor = who == 'Everyone' ? AppColors.okText : (who == 'Not assigned' ? AppColors.muted : AppColors.text2);
    return Hover(
      onTap: onOpen,
      builder: (_, h, _) => Container(
        decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: h ? AppColors.line2 : AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: CtMedia(x, badge: true, radius: BorderRadius.vertical(top: Radius.circular(AppRadius.card - 1)), iconSize: phone ? 26 : 30),
          ),
          Padding(
            padding: phone ? const EdgeInsets.fromLTRB(10, 8, 10, 2) : const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 3, children: [
              SizedBox(
                height: 36.5,
                child: Text('${x['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7, h: 1.35)),
              ),
              Text(ctMeta(x), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted)),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: used == null ? const _UsedChip('Not used yet', none: true) : AppTooltip(message: used.$2, child: _UsedChip(used.$1)),
                ),
              ),
            ]),
          ),
          Padding(
            padding: phone ? const EdgeInsets.fromLTRB(10, 4, 4, 6) : const EdgeInsets.fromLTRB(12, 6, 6, 8),
            child: Row(spacing: 5, children: [
              AppIcon(AppIcons.clients, size: 14, color: who == 'Everyone' ? AppColors.okText : AppColors.muted),
              Expanded(child: Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w6, color: whoColor))),
              Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'Content options', small: true, ghost: true, fill: true, onPressed: () => onMenu(b))),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// `.ct-u`: blue "Exercise: Bench press +1", or grey "Not used yet".
class _UsedChip extends StatelessWidget {
  const _UsedChip(this.label, {this.none = false});
  final String label;
  final bool none;
  @override
  Widget build(BuildContext context) => Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(color: none ? AppColors.sub : AppColors.accentSoft, borderRadius: AppRadius.all(6)),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
          if (!none) const AppIcon(AppIcons.link, size: 12, color: AppColors.accentText),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w7, color: none ? AppColors.muted : AppColors.accentText, h: 1))),
        ]),
      );
}
