import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';

// Content library (boards `Content` / `ContentMobile`): labels, sizes and the `.media` picture the cards and the
// detail drawer share.

/// Page filter tabs: All · Videos · Articles · PDFs · Images.
const ctKinds = [('', 'All'), ('video', 'Videos'), ('article', 'Articles'), ('pdf', 'PDFs'), ('image', 'Images')];

/// New / Edit content type tabs.
const ctEditKinds = [('video', 'Video'), ('article', 'Article'), ('pdf', 'PDF'), ('image', 'Image')];

String ctKindLabel(Object? k) => switch ('$k') { 'video' => 'Video', 'article' => 'Article', 'pdf' => 'PDF', 'image' => 'Image', 'link' => 'Link', _ => 'Item' };

AppIconData ctIcon(Object? k) => switch ('$k') {
      'video' => AppIcons.play,
      'image' => AppIcons.photo,
      'pdf' => AppIcons.file,
      'link' => AppIcons.link,
      _ => AppIcons.docLines,
    };

/// `.media` tone t1–t4, steady per item.
int ctTone(Map x) => '${x['id']}'.codeUnits.fold<int>(0, (a, b) => a + b) % AppColors.mediaTiles.length;

/// 27 MB · 380 KB · 4.6 GB.
String ctSize(num? bytes) {
  final b = (bytes ?? 0).toDouble();
  if (b >= 1024 * 1024 * 1024) return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')} GB';
  if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).round()} MB';
  return '${(b / 1024).round().clamp(1, 1023)} KB';
}

/// "14 Sep" (this year) or "14 Sep 2025".
String ctDm(Object? iso) {
  final t = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (t == null) return '';
  return DateFormat(t.year == DateTime.now().year ? 'd MMM' : 'd MMM y').format(t);
}

/// Card line: "0:42 · Exercise videos" (an image says "Image").
String ctMeta(Map x) {
  final len = x['kind'] == 'image' ? 'Image' : '${x['length_label'] ?? ''}';
  final cat = '${x['category_name'] ?? ''}';
  return cat.isEmpty ? len : '$len · $cat';
}

/// "Exercise: Bench press +1" and the full list for its tooltip.
(String, String)? ctUsed(Map x) {
  final uses = [for (final u in (x['uses'] as List? ?? const [])) u as Map];
  if (uses.isEmpty) return null;
  String one(Map u) => '${u['type'] == 'program' ? 'Program' : 'Exercise'}: ${u['name']}';
  return ('${one(uses.first)}${uses.length > 1 ? '  +${uses.length - 1}' : ''}', uses.map(one).join('  |  '));
}

/// `.media`: the item's picture (cover, picked frame, first frame, YouTube still), else its tinted tile with the
/// kind's icon. [badge] = the white "Video" chip top left; [length] = the dark "▸ 0:42" pill bottom right;
/// [bigPlay] = the round play button in the middle (detail drawer).
class CtMedia extends StatelessWidget {
  const CtMedia(this.x, {super.key, this.radius = BorderRadius.zero, this.badge = false, this.bigPlay = false, this.iconSize = 30});
  final Map x;
  final BorderRadius radius;
  final bool badge, bigPlay;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final (a, b) = AppColors.mediaTiles[ctTone(x)];
    // A picture is its own cover.
    final url = (x['thumb_url'] as String?) ?? (x['kind'] == 'image' ? x['file_url'] as String? : null);
    final tile = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b])),
      child: bigPlay ? null : AppIcon(ctIcon(x['kind']), size: iconSize, color: AppColors.mediaFg, stroke: 1.6),
    );
    final video = x['kind'] == 'video';
    final len = '${x['length_label'] ?? ''}';
    final edge = bigPlay ? 10.0 : 8.0;
    return ClipRRect(
      borderRadius: radius,
      child: Stack(fit: StackFit.expand, children: [
        url == null || url.isEmpty ? tile : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => tile),
        if (bigPlay && video)
          Center(
            child: Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.ctPlayBtn, shape: BoxShape.circle),
              child: const Padding(padding: EdgeInsets.only(left: 3), child: AppIcon(AppIcons.play, size: 22, color: AppColors.white, fill: true)),
            ),
          )
        else if (bigPlay)
          Center(child: AppIcon(ctIcon(x['kind']), size: 40, color: AppColors.mediaFg, stroke: 1.6)),
        if (badge)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.ctKbBg, borderRadius: AppRadius.all(6)),
              child: Text(ctKindLabel(x['kind']), style: AppText.s(11, W.w7)),
            ),
          ),
        if (video && len.isNotEmpty && len != 'Video')
          Positioned(
            right: edge,
            bottom: edge,
            child: Container(
              height: 18,
              padding: const EdgeInsets.fromLTRB(4, 0, 6, 0),
              decoration: BoxDecoration(color: AppColors.playBadge, borderRadius: AppRadius.all(9)),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
                const AppIcon(AppIcons.play, size: 10, color: AppColors.white, fill: true),
                Text(len, style: AppText.s(10, W.w7, color: AppColors.white, h: 1)),
              ]),
            ),
          ),
      ]),
    );
  }
}
