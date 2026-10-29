import 'package:flutter/widgets.dart';

import '../theme/motion.dart';

/// A column whose rows grow in when added and fold away when removed (Phase 5, list insert / remove).
/// Every child needs its own [Key]. Rows there on the first build just show; only later changes animate,
/// and nothing moves when the phone asks for no animations.
class AnimatedRows extends StatefulWidget {
  const AnimatedRows({super.key, required this.children, this.crossAxisAlignment = CrossAxisAlignment.stretch, this.spacing = 0});
  final List<Widget> children;

  /// Space above every row but the first; it grows and folds with the row.
  final double spacing;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  State<AnimatedRows> createState() => _AnimatedRowsState();
}

class _AnimatedRowsState extends State<AnimatedRows> {
  final _seen = <Key>{};

  /// Rows on their way out: the widget as it was and where it stood.
  final _leaving = <Key, (int, Widget)>{};

  @override
  void initState() {
    super.initState();
    _seen.addAll(widget.children.map((c) => c.key!));
  }

  @override
  void didUpdateWidget(AnimatedRows old) {
    super.didUpdateWidget(old);
    final now = {for (final c in widget.children) c.key!};
    for (final (i, c) in old.children.indexed) {
      if (!now.contains(c.key) && !Motion.off(context)) _leaving[c.key!] = (i, c);
    }
    _leaving.removeWhere((k, _) => now.contains(k));
  }

  @override
  Widget build(BuildContext context) {
    // (key, child, leaving) in order; leaving rows keep the place they had
    final rows = <(Key, Widget, bool)>[for (final c in widget.children) (c.key!, c, false)];
    final out = _leaving.entries.toList()..sort((a, b) => a.value.$1.compareTo(b.value.$1));
    for (final e in out) {
      rows.insert(e.value.$1.clamp(0, rows.length), (e.key, e.value.$2, true));
    }
    final built = [
      for (final (i, (k, c, leave)) in rows.indexed)
        _Row(
          key: k,
          appear: !leave && !_seen.contains(k),
          leave: leave,
          onGone: leave ? () => setState(() => _leaving.remove(k)) : null,
          gap: i == 0 ? 0 : widget.spacing,
          child: c,
        ),
    ];
    _seen.addAll(widget.children.map((c) => c.key!));
    return Column(crossAxisAlignment: widget.crossAxisAlignment, mainAxisSize: MainAxisSize.min, children: built);
  }
}

class _Row extends StatefulWidget {
  const _Row({super.key, required this.child, required this.appear, required this.leave, required this.onGone, required this.gap});
  final Widget child;

  /// Space above the row.
  final double gap;
  final bool appear, leave;
  final VoidCallback? onGone;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> with SingleTickerProviderStateMixin {
  late final _a = AnimationController(vsync: this, duration: Motion.medium, reverseDuration: Motion.short, value: widget.appear ? 0 : 1);

  @override
  void initState() {
    super.initState();
    if (widget.appear) _a.forward();
    if (widget.leave) _go();
  }

  @override
  void didUpdateWidget(_Row old) {
    super.didUpdateWidget(old);
    if (widget.leave && !old.leave) _go();
    if (!widget.leave && old.leave) _a.forward();
  }

  void _go() => _a.reverse().whenComplete(() {
        if (mounted && widget.leave) widget.onGone?.call();
      });

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = CurvedAnimation(parent: _a, curve: Motion.curve, reverseCurve: Curves.easeIn);
    return SizeTransition(
      sizeFactor: c,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: c,
        child: IgnorePointer(
          ignoring: widget.leave,
          child: widget.gap == 0 ? widget.child : Padding(padding: EdgeInsets.only(top: widget.gap), child: widget.child),
        ),
      ),
    );
  }
}
