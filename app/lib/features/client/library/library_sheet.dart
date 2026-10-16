import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/media.dart';
import '../../../core/widgets/overlays.dart';
import '../home/home_parts.dart' show ChAvatar;
import 'library_model.dart';

// ─────────────────────────────── Row parts shared by the list, the grid and the sheet.

/// lb-t1..t4: four tones, picked from the id so an item keeps its colour.
const _tones = [
  (AppColors.accentSoft, AppColors.accentText),
  (AppColors.okBg, AppColors.okText),
  (AppColors.icAmberBg, AppColors.icAmberText),
  (AppColors.purpleBg, AppColors.purpleText),
];

(Color, Color) lbTone(LbItem x) => _tones[x.id.codeUnits.fold<int>(0, (a, b) => a + b) % _tones.length];

AppIconData lbIcon(String kind) => switch (kind) {
      'video' => AppIcons.play,
      'pdf' => AppIcons.file,
      'image' => AppIcons.photo,
      'link' => AppIcons.link,
      _ => AppIcons.library,
    };

/// `lb-th`: 52 box in the item's tone with its kind icon; videos show their length.
class LbThumb extends StatelessWidget {
  const LbThumb(this.x, {super.key});
  final LbItem x;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = lbTone(x);
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.all(10)),
      child: Stack(children: [
        Center(child: AppIcon(lbIcon(x.kind), size: 20, color: fg)),
        if (x.kind == 'video')
          Positioned(
            right: 3,
            bottom: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: AppColors.white.withValues(alpha: .88), borderRadius: AppRadius.all(4)),
              child: Text(x.length, style: AppText.s(9.5, W.w8, h: 1.2)),
            ),
          ),
      ]),
    );
  }
}

/// `lb-nt`: "Note from Aman".
class LbNoteTag extends StatelessWidget {
  const LbNoteTag(this.coach, {super.key});
  final String coach;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
        AppIcon(AppIcons.doc, size: 13, color: AppColors.amberDeep),
        Flexible(child: Text('Note from $coach', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w7, color: AppColors.amberDeep))),
      ]);
}

/// Green "✓ Done" pill.
class LbDonePill extends StatelessWidget {
  const LbDonePill({super.key});
  @override
  Widget build(BuildContext context) => Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: AppColors.okBg, borderRadius: AppRadius.all(99)),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 3, children: [
          AppIcon(AppIcons.check, size: 12, color: AppColors.okText, stroke: 2.4),
          Text('Done', style: AppText.s(11.5, W.w7, color: AppColors.okText, h: 1)),
        ]),
      );
}

/// `lb-bm`: 30 bookmark button; on = blue soft with a filled mark.
class LbMark extends StatelessWidget {
  const LbMark({super.key, required this.on, required this.onTap});
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        label: on ? 'Remove from saved' : 'Save for later',
        button: true,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.accentSoft : AppColors.white,
              borderRadius: AppRadius.all(8),
              border: Border.all(color: on ? AppColors.accentRing : (h ? AppColors.accent : AppColors.line)),
            ),
            child: AppIcon(AppIcons.bookmark, size: 15, fill: on, color: on || h ? AppColors.accent : AppColors.muted),
          ),
        ),
      );
}

/// Bookmark tap: save / unsave with an Undo toast.
void lbToggleSave(BuildContext context, LibraryController c, LbItem x) {
  final on = !x.saved;
  c.setSaved(x, on);
  showToast(context, on ? 'Saved for later' : 'Removed from saved',
      sub: x.title, kind: on ? ToastKind.ok : ToastKind.del, action: 'Undo', onAction: () => c.setSaved(x, !on));
}

/// Mark as done / Done · undo, with the board's toasts.
void lbToggleDone(BuildContext context, LibraryController c, LbItem x) {
  final on = !x.done;
  c.setDone(x, on);
  void undo() => c.setDone(x, !on);
  if (!on) {
    showToast(context, 'Marked as not done', sub: x.title, kind: ToastKind.info, action: 'Undo', onAction: undo);
  } else if (c.total > 0 && c.doneCount >= c.total) {
    showToast(context, 'All caught up!', sub: 'You finished everything ${c.coach} shared', kind: ToastKind.star, action: 'Undo', onAction: undo);
  } else {
    showToast(context, 'Marked as done', sub: '${x.title} · ${c.doneCount} of ${c.total} done', kind: ToastKind.ok, action: 'Undo', onAction: undo);
  }
}

// ─────────────────────────────── Item sheet (`ca-sheet` with `lb-view`).

/// Opens one item: loads it (which marks it read), then shows the sheet for its kind.
Future<void> showLibraryItem(BuildContext context, LibraryController c, String id) async {
  final LbItem x;
  try {
    x = await c.open(id);
  } on ApiError catch (e) {
    if (context.mounted) {
      showToast(context, e.status == 404 ? 'This item is no longer shared' : 'Could not open this', sub: e.status == 404 ? null : e.message, kind: ToastKind.err);
    }
    return;
  }
  if (!context.mounted) return;
  await showAppSheet(
    context,
    title: x.title,
    sub: '${lbKind(x.kind)} · ${x.length} · ${x.source}',
    webWidth: 600,
    footerStretch: true,
    listen: c,
    builder: (_) => _ItemView(c: c, x: x),
    footer: (ctx) => [
      Row(spacing: 8, children: [
        Expanded(
          child: _SheetBtn(
            x.saved ? 'Saved' : 'Save for later',
            icon: AppIcons.bookmark,
            fill: x.saved,
            bg: x.saved ? AppColors.accentSoft : null,
            line: x.saved ? AppColors.accentRing : null,
            fg: x.saved ? AppColors.accentText : AppColors.text,
            iconColor: x.saved ? AppColors.accentText : AppColors.text,
            onTap: () => lbToggleSave(ctx, c, x),
          ),
        ),
        Expanded(
          child: x.done
              ? _SheetBtn('Done · undo', icon: AppIcons.check, fg: AppColors.okText, iconColor: AppColors.okSolid, stroke: 2.6, onTap: () => lbToggleDone(ctx, c, x))
              : CaButton('Mark as done', icon: AppIcons.check, onPressed: () => lbToggleDone(ctx, c, x)),
        ),
      ]),
    ],
  );
}

/// Outline `ca-btn` with its own colours (lb-on / lb-ok).
class _SheetBtn extends StatelessWidget {
  const _SheetBtn(this.label, {required this.icon, required this.onTap, this.bg, this.line, this.fg = AppColors.text, this.iconColor = AppColors.text, this.fill = false, this.stroke = 1.8});
  final String label;
  final AppIconData icon;
  final VoidCallback onTap;
  final Color? bg, line;
  final Color fg, iconColor;
  final bool fill;
  final double stroke;
  @override
  Widget build(BuildContext context) {
    final web = CaWeb.of(context);
    return Hover(
      onTap: onTap,
      builder: (_, h, _) => Container(
        height: web ? 40 : 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: bg ?? (h ? AppColors.outlineHover : AppColors.white),
          borderRadius: AppRadius.all(web ? 10 : 12),
          border: Border.all(color: line ?? AppColors.line),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 7, children: [
          AppIcon(icon, size: 17, color: iconColor, fill: fill, stroke: stroke),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(web ? 14 : 14.5, W.w7, color: fg, h: 1))),
        ]),
      ),
    );
  }
}

Future<bool> _openUrl(String url) async {
  if (url.isEmpty) return false;
  return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
}

class _ItemView extends StatelessWidget {
  const _ItemView({required this.c, required this.x});
  final LibraryController c;
  final LbItem x;

  @override
  Widget build(BuildContext context) {
    final info = [
      if (x.note.isNotEmpty) _note(),
      if (x.description.isNotEmpty) Text(x.description, style: AppText.s(13.5, W.w4, color: AppColors.text2, h: 1.5)),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: x.kind == 'video'
          ? _Video(c: c, x: x, info: info)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
              if (x.kind == 'pdf') _Pdf(x: x),
              if (x.kind == 'image') _Image(x: x),
              if (x.kind == 'link') _Link(x: x),
              ...info,
              if (x.kind == 'article' && x.body.isNotEmpty)
                Container(
                  padding: const EdgeInsets.only(top: 10),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
                    for (final p in x.body) Text(p, style: AppText.s(14, W.w4, h: 1.55)),
                  ]),
                ),
            ]),
    );
  }

  /// `lb-note`: amber box, coach avatar, "From Aman".
  Widget _note() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.moBan, borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.amberLine)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          ChAvatar(x.noteInitials.isEmpty ? 'TV' : x.noteInitials, green: true),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text('From ${x.noteBy.isEmpty ? c.coach : x.noteBy}', style: AppText.s(12.5, W.w8, color: AppColors.amberDeep)),
              Text(x.note, style: AppText.s(13.5, W.w4, h: 1.45)),
            ]),
          ),
        ]),
      );
}

// ── Video (`lb-vid` + chapters)

class _Video extends StatefulWidget {
  const _Video({required this.c, required this.x, required this.info});
  final LibraryController c;
  final LbItem x;
  final List<Widget> info;
  @override
  State<_Video> createState() => _VideoState();
}

class _VideoState extends State<_Video> {
  late final VideoCtl v = VideoCtl(x.fileUrl, fallbackSeconds: x.duration, onEnd: _finished);

  LbItem get x => widget.x;

  @override
  void dispose() {
    if (v.maxPct > 0 && v.maxPct < 100) widget.c.watched(x.id, v.maxPct);
    v.dispose();
    super.dispose();
  }

  void _finished() {
    if (!mounted) return;
    final c = widget.c;
    c.watched(x.id, 100);
    if (x.done) {
      showToast(context, 'Video finished', sub: x.title, kind: ToastKind.ok);
      return;
    }
    c.setDone(x, true);
    showToast(context, 'Video finished · marked as done', sub: x.title, kind: ToastKind.star, action: 'Undo', onAction: () => c.setDone(x, false));
  }

  /// Play with nothing playable here: YouTube link, the file in the browser, or "not uploaded".
  Future<void> _empty() async {
    if (v.failed) {
      if (!await _openUrl(x.fileUrl) && mounted) showToast(context, 'Could not open the video', sub: x.title, kind: ToastKind.err);
      return;
    }
    if (!await _openUrl(x.youtube) && mounted) showToast(context, 'Video not uploaded yet', sub: 'Ask ${widget.c.coach} to add it', kind: ToastKind.info);
  }

  int get _chapter {
    final ch = x.chapters;
    var i = 0;
    for (var k = 0; k < ch.length; k++) {
      if (ch[k].$1 <= v.pos) i = k;
    }
    return i;
  }

  String _label() {
    final ch = x.chapters;
    final name = ch.isEmpty ? '' : ' · ${ch[_chapter].$2}';
    if (v.failed) return 'Could not play here · tap to open';
    if (!v.hasFile && x.youtube.isEmpty) return 'Video not uploaded yet';
    if (!v.hasFile) return 'Watch on YouTube';
    if (v.playing) return 'Playing$name';
    if (v.finished) return 'Finished · tap to watch again';
    if (v.pos > 0) return 'Paused$name';
    return 'Tap to play';
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = lbTone(x);
    final ch = x.chapters;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      VideoBox(ctl: v, label: _label, bg: bg, fg: fg, height: CaWeb.of(context) ? 300 : 210, onTapEmpty: _empty, lengthText: x.length, poster: x.youtubeThumb),
      ...widget.info,
      if (ch.isNotEmpty) ListenableBuilder(listenable: v, builder: (_, _) => _chapters(ch)),
    ]);
  }

  /// `lb-chs`: CHAPTERS, each row jumps there and plays.
  Widget _chapters(List<(int, String)> ch) {
    final on = v.pos > 0 || v.playing ? _chapter : -1;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('CHAPTERS', style: AppText.s(12, W.w7, color: AppColors.muted, ls: .6))),
      for (var i = 0; i < ch.length; i++)
        Hover(
          onTap: () => v.seekSeconds(ch[i].$1),
          builder: (_, h, _) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            child: Row(spacing: 10, children: [
              SizedBox(width: 40, child: Text(lbClock(ch[i].$1), style: AppText.s(12, W.w7, color: i == on ? AppColors.accent : AppColors.muted, tabular: true))),
              Expanded(
                child: Text(ch[i].$2, style: AppText.s(13.5, i == on ? W.w8 : W.w6, color: i == on || h ? AppColors.accentText : AppColors.text)),
              ),
            ]),
          ),
        ),
    ]);
  }
}

// ── PDF (`lb-pdf`: one page card, pager, Download)

class _Pdf extends StatefulWidget {
  const _Pdf({required this.x});
  final LbItem x;
  @override
  State<_Pdf> createState() => _PdfState();
}

class _PdfState extends State<_Pdf> {
  int pg = 0;

  @override
  Widget build(BuildContext context) {
    final x = widget.x;
    final pics = x.pageImages;
    final count = pics.isNotEmpty ? pics.length : (x.outline.isEmpty ? 1 : x.outline.length);
    final i = pg.clamp(0, count - 1);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // lb-pdf: grey box with the page; the pager under it is white (board: margin 0 -10, white).
      Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        decoration: const BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
        child: pics.isNotEmpty ? _picture(x, pics, i) : _outline(x, i),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(spacing: 8, children: [
          Opacity(opacity: i > 0 ? 1 : .4, child: CaIconBtn(AppIcons.chevronLeft, tooltip: 'Previous page', onTap: i > 0 ? () => setState(() => pg = i - 1) : null)),
          Expanded(child: Text('Page ${i + 1} of $count', textAlign: TextAlign.center, style: AppText.s(12.5, W.w7, color: AppColors.text2))),
          Opacity(
            opacity: i < count - 1 ? 1 : .4,
            child: CaIconBtn(AppIcons.chevronRight, tooltip: 'Next page', onTap: i < count - 1 ? () => setState(() => pg = i + 1) : null),
          ),
          CaButton('Download', kind: CaBtnKind.out, small: true, expand: false, icon: AppIcons.downloadLine, onPressed: () => _download(context, x, 'Downloaded', '${x.fileName} · saved to your files')),
        ]),
      ),
    ]);
  }

  /// The real page (drawn by the server), tap for full screen with zoom and swipe.
  Widget _picture(LbItem x, List<String> pics, int i) => Semantics(
        button: true,
        label: 'Open page ${i + 1} full screen',
        child: Center(
          child: GestureDetector(
          onTap: () async {
            await showImageViewer(context, pics, start: i, title: x.title);
          },
          child: Container(
            decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.all(6), border: Border.all(color: AppColors.line), boxShadow: const [BoxShadow(color: AppColors.shadowSoft, blurRadius: 8, offset: Offset(0, 2))]),
            clipBehavior: Clip.antiAlias,
            // A whole page, but never taller than the sheet can show next to the pager.
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: CaWeb.of(context) ? 440 : 500),
              child: AspectRatio(aspectRatio: 1 / 1.414, child: NetImage(pics[i], fit: BoxFit.contain)),
            ),
          ),
        ),
        ),
      );

  /// No page pictures (file missing or unreadable): the coach's outline for that page.
  Widget _outline(LbItem x, int i) {
    final pages = x.outline.isEmpty ? [(x.title, x.description)] : x.outline;
    final (t, p) = pages[i];
    return Container(
      constraints: const BoxConstraints(minHeight: 132),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.line), boxShadow: const [BoxShadow(color: AppColors.shadowSoft, blurRadius: 8, offset: Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
        Text(x.fileName.isEmpty ? '${x.title}.pdf' : x.fileName, style: AppText.s(10.5, W.w7, color: AppColors.muted)),
        Text(t, style: AppText.s(15, W.w8)),
        if (p.isNotEmpty) Text(p, style: AppText.s(12.5, W.w4, color: AppColors.text2, h: 1.45)),
        for (final w in [1.0, 1.0, .6])
          FractionallySizedBox(widthFactor: w, child: Container(height: 6, decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(6)))),
      ]),
    );
  }
}

Future<void> _download(BuildContext context, LbItem x, String title, String sub) async {
  final ok = await _openUrl(x.fileUrl);
  if (!context.mounted) return;
  ok ? showToast(context, title, sub: sub, kind: ToastKind.ok) : showToast(context, 'File not uploaded yet', sub: x.title, kind: ToastKind.info);
}

// ── Image (`lb-img` + Save image)

class _Image extends StatelessWidget {
  const _Image({required this.x});
  final LbItem x;
  @override
  Widget build(BuildContext context) {
    final ext = x.fileName.contains('.') ? x.fileName.split('.').last.toUpperCase() : 'PNG';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.lbImgBg, borderRadius: AppRadius.all(12), border: Border.all(color: AppColors.lbImgLine)),
        child: x.fileUrl.isEmpty
            ? SizedBox(height: 120, child: Center(child: AppIcon(AppIcons.photo, size: 28, color: AppColors.okText)))
            : Semantics(
                button: true,
                label: 'Open the picture full screen',
                child: GestureDetector(
                  onTap: () => showImageViewer(context, [x.fileUrl], title: x.title),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.zoomIn,
                    child: ClipRRect(borderRadius: AppRadius.all(8), child: NetImage(x.fileUrl, fit: BoxFit.contain)),
                  ),
                ),
              ),
      ),
      Row(spacing: 8, children: [
        Expanded(child: Text('$ext image · 1 page', style: AppText.s(12.5, W.w7, color: AppColors.muted))),
        CaButton('Save image', kind: CaBtnKind.out, small: true, expand: false, icon: AppIcons.downloadLine, onPressed: () => _download(context, x, 'Image saved', 'Find it in your photos')),
      ]),
    ]);
  }
}

// ── Link (a reference web page; not on the board, Gautam 2026-10-16)

class _Link extends StatelessWidget {
  const _Link({required this.x});
  final LbItem x;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = lbTone(x);
    Future<void> open() async {
      if (!await _openUrl(x.linkUrl) && context.mounted) showToast(context, 'Could not open the link', sub: x.linkUrl, kind: ToastKind.err);
    }

    return Hover(
      onTap: open,
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.all(12), border: Border.all(color: h ? AppColors.line2 : AppColors.line)),
        child: Row(spacing: 12, children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: AppRadius.all(10)),
            child: AppIcon(AppIcons.link, size: 20, color: fg),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text(x.linkSite.isEmpty ? 'Web page' : x.linkSite, style: AppText.s(14, W.w8)),
              Text(x.linkUrl, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w4, color: AppColors.muted)),
            ]),
          ),
          CaButton('Open link', kind: CaBtnKind.out, small: true, expand: false, trailingIcon: AppIcons.external, onPressed: open),
        ]),
      ),
    );
  }
}
