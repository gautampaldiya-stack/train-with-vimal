import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons/app_icons.dart';
import '../theme/theme.dart';
import 'hover.dart';

/// A photo from the server (a link) or one still on this phone (a data URL).
ImageProvider? photoImage(String? src) {
  if (src == null || src.isEmpty) return null;
  if (src.startsWith('data:')) {
    final i = src.indexOf(',');
    if (i < 0) return null;
    try {
      return MemoryImage(base64Decode(src.substring(i + 1)));
    } on FormatException {
      return null;
    }
  }
  return NetworkImage(src);
}

/// A small photo that opens full size when tapped.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({super.key, required this.photos, required this.index, this.size = 56, this.radius = 8, this.label = true});
  final List<(String, String)> photos; // (label, src)
  final int index;
  final double size, radius;
  final bool label;

  @override
  Widget build(BuildContext context) {
    final (name, src) = photos[index];
    final img = photoImage(src);
    return Semantics(
      button: true,
      label: 'Open $name photo',
      child: Hover(
        onTap: () => showPhotoViewer(context, photos, index),
        builder: (_, h, _) => Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 3,
          children: [
            Container(
              width: size,
              height: size * 4 / 3,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: h ? AppColors.accent : AppColors.line),
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppColors.figBg),
              ),
              child: img == null
                  ? const Center(child: AppIcon(AppIcons.photo, size: 18, color: AppColors.figText))
                  : Image(
                      image: img,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Center(child: AppIcon(AppIcons.photo, size: 18, color: AppColors.figText)),
                    ),
            ),
            if (label)
              SizedBox(
                width: size,
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.s(11, W.w6, color: AppColors.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A row of [PhotoThumb]s.
Widget photoThumbs(List<(String, String)> photos, {double size = 56}) => Wrap(
  spacing: 8,
  runSpacing: 8,
  children: [for (var i = 0; i < photos.length; i++) PhotoThumb(photos: photos, index: i, size: size)],
);

/// Full-size photos on a dark screen: swipe or use the arrows, pinch to zoom, Esc or × to close.
Future<void> showPhotoViewer(BuildContext context, List<(String, String)> photos, int start) => showGeneralDialog(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close',
  barrierColor: AppColors.viewerBg,
  pageBuilder: (ctx, _, _) => _Viewer(photos: photos, start: start),
);

class _Viewer extends StatefulWidget {
  const _Viewer({required this.photos, required this.start});
  final List<(String, String)> photos;
  final int start;
  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late final _pc = PageController(initialPage: widget.start);
  late int _at = widget.start;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _go(int d) {
    final j = _at + d;
    if (j < 0 || j >= widget.photos.length) return;
    _pc.animateToPage(j, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  Widget _btn(AppIconData icon, String tip, VoidCallback onTap) => Semantics(
    button: true,
    label: tip,
    child: Hover(
      onTap: onTap,
      builder: (_, h, _) => Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: h ? AppColors.viewerBtnHover : AppColors.viewerBtn, shape: BoxShape.circle),
        child: AppIcon(icon, size: 20, color: AppColors.white),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final n = widget.photos.length;
    return Material(
      type: MaterialType.transparency,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
        },
        child: Focus(
          autofocus: true,
          child: SafeArea(
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pc,
                  itemCount: n,
                  onPageChanged: (i) => setState(() => _at = i),
                  itemBuilder: (_, i) {
                    final img = photoImage(widget.photos[i].$2);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 64, 16, 24),
                      child: InteractiveViewer(
                        maxScale: 4,
                        child: Center(
                          child: img == null
                              ? Text('This photo could not be opened', style: AppText.s(14, W.w6, color: AppColors.white))
                              : Image(
                                  image: img,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => Text('This photo could not be opened', style: AppText.s(14, W.w6, color: AppColors.white)),
                                ),
                        ),
                      ),
                    );
                  },
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: 12,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          n > 1 ? '${widget.photos[_at].$1} · ${_at + 1} of $n' : widget.photos[_at].$1,
                          style: AppText.s(15, W.w7, color: AppColors.white),
                        ),
                      ),
                      _btn(AppIcons.close, 'Close', () => Navigator.of(context).pop()),
                    ],
                  ),
                ),
                if (n > 1 && _at > 0)
                  Positioned(left: 12, top: 0, bottom: 0, child: Center(child: _btn(AppIcons.chevronLeft, 'Previous photo', () => _go(-1)))),
                if (n > 1 && _at < n - 1)
                  Positioned(right: 12, top: 0, bottom: 0, child: Center(child: _btn(AppIcons.chevronRight, 'Next photo', () => _go(1)))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
