import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// One icon from the boards: inline SVG, 24×24, stroke 1.8, round caps (docs/design.md §1.5).
class AppIconData {
  const AppIconData(this.viewBox, this.inner, {this.fill = false});
  final String viewBox;
  final String inner;
  final bool fill;
}

class AppIcon extends StatelessWidget {
  const AppIcon(this.data, {super.key, this.size = 16, this.color, this.stroke = 1.8, this.fill = false});
  final AppIconData data;
  final double size;
  final Color? color;
  final double stroke;
  final bool fill;

  static final _cache = <String, String>{};

  String _hex(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  @override
  Widget build(BuildContext context) {
    final c = color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF171717);
    final opacity = c.a;
    final hex = _hex(c);
    final isFill = fill || data.fill;
    final key = '${data.inner.hashCode}|$hex|$stroke|$isFill';
    final svg = _cache.putIfAbsent(key, () {
      final body = data.inner.replaceAll('currentColor', hex);
      return isFill
          ? '<svg xmlns="http://www.w3.org/2000/svg" viewBox="${data.viewBox}" fill="$hex" stroke="none">$body</svg>'
          : '<svg xmlns="http://www.w3.org/2000/svg" viewBox="${data.viewBox}" fill="none" stroke="$hex" '
              'stroke-width="$stroke" stroke-linecap="round" stroke-linejoin="round">$body</svg>';
    });
    final pic = SvgPicture.string(svg, width: size, height: size);
    return opacity < 1 ? Opacity(opacity: opacity, child: pic) : pic;
  }
}
