import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tabs.dart';
import 'cp_common.dart';
import 'cp_logs_parts.dart';

// Progress → photos: the full-screen viewer (board `pvo`: angle tabs, Compare, previous / next, the dates strip;
// Compare puts two dates side by side, each with its own date picker) and the All photos drawer (board `pall`).

/// One photo set (a date): the start photos or a check-in's photos.
class CpPhotoSet {
  CpPhotoSet(Map j)
      : id = '${j['id']}',
        label = '${j['label'] ?? ''}',
        date = cpParse(j['date']),
        kg = double.tryParse('${j['weight_kg'] ?? ''}'),
        photos = {for (final p in (j['photos'] as List? ?? const [])) '${(p as Map)['pose']}': '${p['image']}'};
  final String id, label;
  final DateTime? date;
  final double? kg;
  final Map<String, String> photos; // pose → url

  String get dm => cpDm(date);
  String get dmKg => kg == null ? dm : '$dm · ${cpKg(kg, keep: true)}';
}

const cpPoses = [('front', 'Front'), ('side', 'Side'), ('back', 'Back')];

/// Full-screen viewer over the photo sets (oldest first). [compare] opens with two dates side by side.
Future<void> showCpPhotoViewer(BuildContext context, List<CpPhotoSet> sets, {int index = -1, String pose = 'front', bool compare = false}) {
  if (sets.isEmpty) return Future.value();
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: AppColors.viewerBg,
    barrierDismissible: true,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (_, _, _) => _Viewer(sets: sets, index: index < 0 ? sets.length - 1 : index, pose: pose, compare: compare),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  ));
}

class _Viewer extends StatefulWidget {
  const _Viewer({required this.sets, required this.index, required this.pose, required this.compare});
  final List<CpPhotoSet> sets;
  final int index;
  final String pose;
  final bool compare;
  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late int i = widget.index, left = 0;
  late String pose = widget.pose;
  late bool cmp = widget.compare;

  List<CpPhotoSet> get sets => widget.sets;
  CpPhotoSet get cur => sets[i];

  String _url(CpPhotoSet s) => s.photos[pose] ?? '';

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final white = AppText.s(15, W.w8, color: AppColors.white);
    final dim = AppText.s(12.5, W.w5, color: AppColors.homeHeroSub);
    final header = Padding(
      padding: EdgeInsets.fromLTRB(phone ? 12 : 0, 12, phone ? 12 : 0, 12),
      child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 10, spacing: 12, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Progress photos', style: white),
          Text([cur.dmKg, if (cur.label.isNotEmpty) 'from ${cur.label[0].toLowerCase()}${cur.label.substring(1)}'].join(' · '), style: dim),
        ]),
        Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
          SegmentedTabs<String>(items: [for (final (k, l) in cpPoses) TabItem(k, l)], value: pose, onChanged: (p) => setState(() => pose = p)),
          _DarkBtn('Compare', icon: AppIcons.swap, on: cmp, onTap: () => setState(() => cmp = !cmp)),
          _DarkBtn('', icon: AppIcons.close, round: true, onTap: () => Navigator.of(context).pop()),
        ]),
      ]),
    );
    Widget photo(CpPhotoSet s, {required String tag}) => Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(12)),
          child: Stack(fit: StackFit.expand, children: [
            _url(s).isEmpty
                ? Center(child: Text('No $pose photo this date', style: AppText.s(13, W.w6, color: AppColors.muted)))
                : InteractiveViewer(child: Image.network(_url(s), fit: BoxFit.contain, errorBuilder: (_, _, _) => const Center(child: AppIcon(AppIcons.photo, size: 28, color: AppColors.muted)))),
            Positioned(left: 12, bottom: 12, child: _Tag(tag)),
          ]),
        );
    Widget picker(int value, ValueChanged<int> onPick, String Function(CpPhotoSet, int) label) => Builder(
          builder: (b) => Hover(
            onTap: () => showAppMenu(b, [for (final (j, s) in sets.indexed) MenuEntry(label(s, j), selected: j == value, onTap: () => onPick(j))],
                width: (b.findRenderObject() as RenderBox).size.width, alignRight: false),
            builder: (_, h, _) => Container(
              height: 34,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: h ? AppColors.darkHover : AppColors.toastStaff, borderRadius: AppRadius.all(8)),
              child: Row(children: [
                Expanded(child: Text(label(sets[value], value), style: AppText.s(13, W.w7, color: AppColors.white))),
                const AppIcon(AppIcons.chevronDown, size: 16, color: AppColors.white),
              ]),
            ),
          ),
        );
    String lab(CpPhotoSet s, int j) => j == 0 ? 'Start · ${s.dm}' : s.dm;
    final body = cmp
        ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            Expanded(child: Column(children: [Expanded(child: photo(sets[left], tag: sets[left].dmKg)), picker(left, (j) => setState(() => left = j), lab)])),
            Expanded(child: Column(children: [Expanded(child: photo(cur, tag: cur.dmKg)), picker(i, (j) => setState(() => i = j), lab)])),
          ])
        : Row(children: [
            _Nav(AppIcons.chevronLeft, 'Previous', () => setState(() => i = (i - 1 + sets.length) % sets.length)),
            Expanded(child: Center(child: AspectRatio(aspectRatio: 3 / 4, child: photo(cur, tag: cur.dmKg)))),
            _Nav(AppIcons.chevronRight, 'Next', () => setState(() => i = (i + 1) % sets.length)),
          ]);
    final strip = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
        for (final (j, s) in sets.indexed)
          GestureDetector(
            onTap: () => setState(() => i = j),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Column(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
                Container(
                  width: 56,
                  height: 64,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.sub,
                    borderRadius: AppRadius.all(8),
                    border: Border.all(color: j == i ? AppColors.white : Colors.transparent, width: 2),
                  ),
                  child: Opacity(
                    opacity: j == i ? 1 : .55,
                    child: _url(s).isEmpty ? const SizedBox() : Image.network(_url(s), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
                  ),
                ),
                Text(s.dm, style: AppText.s(11.5, W.w6, color: j == i ? AppColors.white : AppColors.homeHeroSub)),
              ]),
            ),
          ),
      ]),
    );
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: phone ? 0 : 24, vertical: 12),
              child: Column(children: [
                header,
                Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: phone ? 8 : 0), child: body)),
                const SizedBox(height: 12),
                strip,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppColors.truncTip.withValues(alpha: .8), borderRadius: AppRadius.all(6)),
        child: Text(t, style: AppText.s(12, W.w7, color: AppColors.white)),
      );
}

class _Nav extends StatelessWidget {
  const _Nav(this.icon, this.label, this.onTap);
  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: h ? AppColors.darkHover : AppColors.homeHeroBtn, shape: BoxShape.circle),
            child: AppIcon(icon, size: 18, color: AppColors.white),
          ),
        ),
      );
}

class _DarkBtn extends StatelessWidget {
  const _DarkBtn(this.label, {required this.icon, required this.onTap, this.on = false, this.round = false});
  final String label;
  final AppIconData icon;
  final VoidCallback onTap;
  final bool on, round;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label.isEmpty ? 'Close' : label,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            height: 34,
            width: round ? 34 : null,
            padding: round ? null : const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.white : (h ? AppColors.darkHover : AppColors.toastStaff),
              borderRadius: AppRadius.all(round ? 17 : 8),
              border: Border.all(color: on ? AppColors.white : AppColors.goneGray),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              AppIcon(icon, size: 15, color: on ? AppColors.text : AppColors.white),
              if (label.isNotEmpty) Text(label, style: AppText.s(13, W.w7, color: on ? AppColors.text : AppColors.white)),
            ]),
          ),
        ),
      );
}

/// All photos drawer: angle tabs, every date newest first with its photos; a photo opens the viewer there;
/// Compare two dates opens the viewer side by side.
Future<void> showCpAllPhotos(BuildContext context, {required String name, required List<CpPhotoSet> sets}) {
  final pose = ValueNotifier('front');
  final total = sets.fold<int>(0, (a, s) => a + s.photos.length);
  final count = '${sets.length} date${sets.length == 1 ? '' : 's'} · $total photo${total == 1 ? '' : 's'}';
  return showAppDrawer<void>(
    context,
    title: 'All photos',
    sub: '$name · $count',
    icon: AppIcons.camera,
    wide: true,
    builder: (ctx) => ValueListenableBuilder<String>(
      valueListenable: pose,
      builder: (ctx, p, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 16),
        Row(children: [
          SegmentedTabs<String>(height: 28, items: [for (final (k, l) in cpPoses) TabItem(k, l)], value: p, onChanged: (v) => pose.value = v),
          const Spacer(),
          Text(count, style: AppText.cap),
        ]),
        if (sets.isEmpty) const EmptyState('No progress photos yet', icon: AppIcons.camera),
        for (final (ri, s) in sets.reversed.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: s.dm, style: AppText.s(14, W.w8)),
                TextSpan(text: '   ${[if (s.kg != null) cpKg(s.kg, keep: true), if (s.label.isNotEmpty) s.label].join(' · ')}', style: AppText.cap),
              ])),
              LayoutBuilder(builder: (_, b) {
                final w = (b.maxWidth - 16) / 3;
                return Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (k, l) in cpPoses)
                    if (s.photos[k] != null)
                      SizedBox(
                        width: w,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                          CpPhoto(s.photos[k]!, height: w * 0.76, selected: k == p,
                              onTap: () => showCpPhotoViewer(ctx, sets, index: sets.length - 1 - ri, pose: k)),
                          Text(l, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
                        ]),
                      ),
                ]);
              }),
            ]),
          ),
      ]),
    ),
    footer: (ctx) => [
      if (!ctx.isPhone) Expanded(child: Text('From weekly check-ins and the start photos', style: AppText.s(12.5, W.w5, color: AppColors.muted))),
      if (!ctx.isPhone) AppButton('Close', onPressed: () => Navigator.of(ctx).pop()),
      AppButton.primary('Compare two dates', icon: AppIcons.swap, expand: ctx.isPhone,
          onPressed: sets.length < 2 ? null : () => showCpPhotoViewer(ctx, sets, pose: pose.value, compare: true)),
    ],
  ).whenComplete(() => disposeLater([pose]));
}
