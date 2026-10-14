import 'package:flutter/material.dart';

import '../theme/theme.dart';

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

/// `.av` round avatar; colour comes from the name (docs/design.md §1.1).
class AppAvatar extends StatelessWidget {
  const AppAvatar(this.name, {super.key, this.size = 28, this.url, this.colors});
  final String name;
  final double size;
  final String? url;
  final (Color, Color)? colors;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = colors ?? AppColors.avatarFor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: url != null && url!.isNotEmpty
          ? Image.network(url!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => _text(fg))
          : _text(fg),
    );
  }

  Widget _text(Color fg) => Text(initialsOf(name), style: AppText.s(size * 0.36, W.w8, color: fg, ls: 0.2));
}
