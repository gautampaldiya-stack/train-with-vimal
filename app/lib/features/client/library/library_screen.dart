import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/responsive.dart';
import '../food/food_parts.dart' show FdChip;
import '../home/home_parts.dart';
import '../progress/progress_screen.dart' show pxLoading;
import 'library_model.dart';
import 'library_sheet.dart';

/// Library (boards `ClientLibrary` phone and `ClientLibraryWeb`): what the coach shared, with search, type filters,
/// New / Done / Saved, the coach's notes, and an item sheet per kind (video, PDF, image, article).
/// `/library/<id>` opens that item's sheet (the "New in your library" notification links there).
class ClientLibraryScreen extends StatefulWidget {
  const ClientLibraryScreen({super.key, this.id});
  final String? id;
  @override
  State<ClientLibraryScreen> createState() => _ClientLibraryScreenState();
}

class _ClientLibraryScreenState extends State<ClientLibraryScreen> {
  final c = LibraryController();
  final _q = TextEditingController();

  static const _tries = ['squat', 'eating out', 'protein', 'check-in'];

  @override
  void initState() {
    super.initState();
    c.start();
    final id = widget.id;
    if (id != null) WidgetsBinding.instance.addPostFrameCallback((_) => _open(id));
  }

  @override
  void dispose() {
    c.dispose();
    _q.dispose();
    super.dispose();
  }

  Future<void> _open(String id) async {
    await showLibraryItem(context, c, id);
    if (mounted && widget.id != null) context.go('/library');
  }

  void _setQ(String v) {
    _q.text = v;
    c.setQuery(v, now: true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          if (c.items == null) return pxLoading(c.error, c.load, 'your library');
          return context.isPhone ? _phone() : _web();
        },
      );

  // ─────────────────────────────── Layouts

  Widget _phone() => RefreshIndicator(
        onRefresh: c.load,
        color: AppColors.accent,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            Row(spacing: 10, children: [
              CaIconBtn(AppIcons.chevronLeft, tooltip: 'Back to More', onTap: () => context.go('/more')),
              Expanded(child: _title()),
            ]),
            _progress(),
            ..._search(),
            _filters(phone: true),
            _list(),
          ]),
        ),
      );

  Widget _web() => CaWeb(
        web: true,
        child: RefreshIndicator(
          onRefresh: c.load,
          color: AppColors.accent,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 72),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: LayoutBuilder(builder: (context, box) {
                  final side = box.maxWidth >= 860;
                  // Cards are ~200 wide on the board: 3 across from a 600 px left column.
                  final leftW = side ? box.maxWidth - 340 : box.maxWidth;
                  final cols = leftW >= 600 ? 3 : (leftW >= 380 ? 2 : 1);
                  final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
                    ..._search(),
                    _filters(phone: false),
                    _grid(cols),
                  ]);
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
                    _title(),
                    if (side)
                      Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
                        Expanded(child: left),
                        SizedBox(width: 320, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [_progress(), if (c.notes.isNotEmpty) _notes()])),
                      ])
                    else ...[
                      _progress(),
                      left,
                      if (c.notes.isNotEmpty) _notes(),
                    ],
                  ]);
                }),
              ),
            ),
          ),
        ),
      );

  // ─────────────────────────────── Parts

  Widget _title() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Library', style: AppText.s(26, W.w8, ls: -0.26, h: 1.2)),
        Text('Videos, PDFs and guides from ${c.coach}', style: AppText.s(13, W.w5, color: AppColors.muted)),
      ]);

  /// `lb-prog`: "3 of 8 done" · "2 new from Aman" + bar.
  Widget _progress() => ChCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), gap: 8, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Expanded(child: Text('${c.doneCount} of ${c.total} done', style: AppText.s(14, W.w8))),
          Text(c.newCount > 0 ? '${c.newCount} new from ${c.coach}' : 'All caught up', style: AppText.s(12, W.w7, color: AppColors.accentText)),
        ]),
        ChBar(c.total == 0 ? 0 : c.doneCount / c.total, color: AppColors.accent),
      ]);

  List<Widget> _search() => [
        Container(
          height: 44,
          padding: const EdgeInsets.only(left: 12, right: 6),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
          child: Row(spacing: 8, children: [
            const AppIcon(AppIcons.search, size: 17, color: AppColors.muted),
            Expanded(
              child: TextField(
                controller: _q,
                onChanged: c.setQuery,
                textInputAction: TextInputAction.search,
                style: AppText.s(13.5, W.w6),
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Search videos, PDFs and articles',
                  hintStyle: AppText.s(13.5, W.w4, color: AppColors.muted),
                ),
              ),
            ),
            if (c.q.isNotEmpty) CaIconBtn(AppIcons.close, tooltip: 'Clear search', onTap: () => _setQ('')),
          ]),
        ),
        Pull(
          top: 4,
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 6, children: [
            Text('Try', style: AppText.s(12, W.w6, color: AppColors.muted)),
            for (final t in _tries) FdChip(t, height: 26, on: c.q == t, onTap: () => _setQ(c.q == t ? '' : t)),
          ]),
        ),
      ];

  /// `lb-filt`: phone = six equal chips, no counts; web = chips with counts.
  Widget _filters({required bool phone}) {
    Widget chip((String, String) f, {bool expand = false}) {
      final on = c.kind == f.$1;
      return Semantics(
        button: true,
        selected: on,
        child: Hover(
          onTap: () => c.setKind(f.$1),
          builder: (_, h, _) => Container(
            height: 30,
            padding: EdgeInsets.symmetric(horizontal: expand ? 0 : 10),
            decoration: BoxDecoration(
              color: on ? AppColors.text : AppColors.white,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: on ? AppColors.text : (h ? AppColors.line2 : AppColors.line)),
            ),
            child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, spacing: 5, children: [
              Flexible(child: Text(f.$2, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: AppText.s(phone ? 12 : 12.5, W.w6, color: on ? AppColors.white : AppColors.text2))),
              if (!phone) Text('${c.counts[f.$1] ?? 0}', style: AppText.s(11, W.w7, color: on ? const Color(0xFFC9C9C9) : AppColors.muted)),
            ]),
          ),
        ),
      );
    }

    if (phone) {
      return Row(spacing: 4, children: [for (final f in lbFilters) Expanded(child: chip(f, expand: true))]);
    }
    return Wrap(spacing: 6, runSpacing: 6, children: [for (final f in lbFilters) chip(f)]);
  }

  String get _countLine {
    final n = c.items!.length;
    if (c.q.isNotEmpty) return '$n ${n == 1 ? 'result' : 'results'} for “${c.q}”';
    final what = switch (c.kind) {
      'saved' => 'Saved for later',
      'all' => 'Everything ${c.coach} shared with you',
      _ => lbFilters.firstWhere((f) => f.$1 == c.kind).$2,
    };
    return '$what · $n';
  }

  Widget _empty() {
    final saved = c.kind == 'saved' && c.q.isEmpty;
    return ChCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22), gap: 6, children: [
      Text(saved ? 'Nothing saved yet' : 'Nothing found', textAlign: TextAlign.center, style: AppText.s(15, W.w8)),
      Text(saved ? 'Open an item and tap Save for later. It will show up here.' : 'Try another word or another type.',
          textAlign: TextAlign.center, style: AppText.s(13, W.w4, color: AppColors.muted)),
      if (!saved) Center(child: Padding(padding: const EdgeInsets.only(top: 4), child: chSm('Show everything', () {
        _q.clear();
        c.reset();
      }))),
    ]);
  }

  Widget _list() {
    final items = c.items!;
    if (items.isEmpty) return _empty();
    return ChCard(padding: const EdgeInsets.fromLTRB(14, 10, 14, 4), gap: 0, children: [
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_countLine, style: AppText.s(12, W.w7, color: AppColors.muted))),
      for (final x in items) _row(x),
    ]);
  }

  Widget _row(LbItem x) => Semantics(
        button: true,
        label: x.title,
        child: Hover(
          onTap: () => _open(x.id),
          builder: (_, h, _) => Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            child: Row(spacing: 11, children: [
              LbThumb(x),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: x.title),
                      if (x.isNew)
                        const WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(padding: EdgeInsets.only(left: 6), child: SizedBox(width: 7, height: 7, child: DecoratedBox(decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)))),
                        ),
                    ]),
                    style: AppText.s(14, W.w7, h: 1.3, color: h ? AppColors.accentText : AppColors.text),
                  ),
                  Text(x.meta, style: AppText.s(12, W.w4, color: AppColors.muted)),
                  Text(x.source, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
                  if (x.note.isNotEmpty) LbNoteTag(x.noteBy.isEmpty ? c.coach : x.noteBy),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, spacing: 6, children: [
                if (x.isNew) const CaPill('New', tone: CaTone.blue) else if (x.done) const LbDonePill(),
                LbMark(on: x.saved, onTap: () => lbToggleSave(context, c, x)),
              ]),
            ]),
          ),
        ),
      );

  Widget _grid(int cols) {
    final items = c.items!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      Text(_countLine, style: AppText.s(12.5, W.w6, color: AppColors.muted)),
      if (items.isEmpty)
        _empty()
      else
        for (var i = 0; i < items.length; i += cols)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
              for (var k = 0; k < cols; k++) Expanded(child: i + k < items.length ? _card(items[i + k]) : const SizedBox()),
            ]),
          ),
    ]);
  }

  Widget _card(LbItem x) {
    final (bg, fg) = lbTone(x);
    return Semantics(
      button: true,
      label: x.title,
      child: Hover(
        onTap: () => _open(x.id),
        builder: (_, h, _) => Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: h ? AppColors.line2 : AppColors.line),
            boxShadow: h ? const [BoxShadow(color: Color(0x0F171717), blurRadius: 10, offset: Offset(0, 2))] : null,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 96,
              color: bg,
              child: Stack(children: [
                Center(child: AppIcon(lbIcon(x.kind), size: 28, color: fg)),
                if (x.isNew || x.done) Positioned(left: 8, top: 8, child: x.isNew ? const CaPill('New', tone: CaTone.blue) : const LbDonePill()),
                if (x.kind == 'video') Positioned(right: 8, bottom: 8, child: _len(x.length, 11, 6)),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                  Text(x.title, style: AppText.s(14, W.w7, h: 1.3, color: h ? AppColors.accentText : AppColors.text)),
                  Text(x.meta, style: AppText.s(12, W.w4, color: AppColors.muted)),
                  if (x.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: LbNoteTag(x.noteBy.isEmpty ? c.coach : x.noteBy)),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(spacing: 8, children: [
                      Expanded(child: Text(x.source, style: AppText.s(11.5, W.w6, color: AppColors.muted))),
                      LbMark(on: x.saved, onTap: () => lbToggleSave(context, c, x)),
                    ]),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _len(String t, double size, double padH) => Container(
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: 2),
        decoration: BoxDecoration(color: AppColors.white.withValues(alpha: .9), borderRadius: BorderRadius.circular(5)),
        child: Text(t, style: AppText.s(size, W.w8)),
      );

  /// Web `lb-notes`: every coach note, tap → that item.
  Widget _notes() => ChCard(padding: const EdgeInsets.fromLTRB(14, 12, 14, 4), gap: 0, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(spacing: 10, children: [
            ChAvatar(c.coachInitials, green: true),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Notes from ${c.coach}', style: AppText.s(15, W.w8)),
                Text('On the content shared with you', style: AppText.s(12.5, W.w4, color: AppColors.muted)),
              ]),
            ),
          ]),
        ),
        for (final n in c.notes)
          Hover(
            onTap: () => _open('${n['id']}'),
            builder: (_, h, _) => Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text('${n['title']}', style: AppText.s(13, W.w7, color: h ? AppColors.accentText : AppColors.text)),
                Text('${n['note']}', style: AppText.s(12.5, W.w4, color: AppColors.text2, h: 1.45)),
              ]),
            ),
          ),
      ]);
}
