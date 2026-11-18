import 'package:flutter/widgets.dart';

import '../theme/theme.dart';

/// Grey placeholder shapes while a page loads (Probid 18 Nov: "skeleton daal sakte hai, data load ho tab tak").
/// [Skeleton] makes every [SkelBox] under it breathe softly, all together; with animations off they stay still.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child, this.onColor = false});
  final Widget child;

  /// On a coloured background (the blue Home hero): white see-through shapes instead of grey.
  final bool onColor;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.onColor ? AppColors.white.withValues(alpha: .20) : AppColors.skelBase;
    final hi = widget.onColor ? AppColors.white.withValues(alpha: .34) : AppColors.skelHi;
    final still = Motion.off(context);
    return _SkelColor(base: base, hi: hi, t: still ? null : CurvedAnimation(parent: _a, curve: Curves.easeInOut), child: widget.child);
  }
}

/// The colours and the shared pulse every [SkelBox] under a [Skeleton] uses (one clock, so they breathe together).
class _SkelColor extends InheritedWidget {
  const _SkelColor({required this.base, required this.hi, required this.t, required super.child});
  final Color base, hi;
  final Animation<double>? t;

  @override
  bool updateShouldNotify(_SkelColor old) => old.base != base || old.hi != hi || old.t != t;
}

/// One placeholder shape: a text line, an avatar, a card block.
class SkelBox extends StatelessWidget {
  const SkelBox({super.key, this.width, this.height = 12, this.radius = 6, this.circle = false});
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<_SkelColor>();
    Widget box(Color c) => Container(
          width: circle ? height : width,
          height: height,
          decoration: BoxDecoration(color: c, shape: circle ? BoxShape.circle : BoxShape.rectangle, borderRadius: circle ? null : BorderRadius.circular(radius)),
        );
    final t = s?.t;
    if (s == null || t == null) return box(s?.base ?? AppColors.skelBase);
    return AnimatedBuilder(animation: t, builder: (_, _) => box(Color.lerp(s.base, s.hi, t.value)!));
  }
}

/// A white card with a title line and [lines] text lines, the shape of most cards while they load.
class SkelCard extends StatelessWidget {
  const SkelCard({super.key, this.lines = 2, this.icon = true, this.height});
  final int lines;
  final bool icon;

  /// A fixed height block under the title (a chart, a big number) instead of text lines.
  final double? height;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          Row(spacing: 10, children: [
            if (icon) const SkelBox(height: 32, radius: 10, width: 32),
            const Expanded(child: Align(alignment: Alignment.centerLeft, child: FractionallySizedBox(widthFactor: .5, child: SkelBox(height: 14)))),
          ]),
          if (height != null)
            SkelBox(height: height!, radius: 10)
          else
            for (var i = 0; i < lines; i++) FractionallySizedBox(widthFactor: i == lines - 1 ? .6 : 1, child: const SkelBox(height: 11)),
        ]),
      );
}

/// A list row: round icon, two text lines, a short value on the right (notifications, activity).
class SkelRow extends StatelessWidget {
  const SkelRow({super.key, this.first = false});
  final bool first;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: AppColors.line))),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 11, children: [
          SkelBox(height: 32, circle: true),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 7, children: [
              FractionallySizedBox(widthFactor: .7, child: SkelBox(height: 12)),
              SkelBox(height: 10),
              FractionallySizedBox(widthFactor: .3, child: SkelBox(height: 9)),
            ]),
          ),
        ]),
      );
}
