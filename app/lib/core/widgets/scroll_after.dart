import 'package:flutter/material.dart';

/// A list inside a card ("Assigned to", "Used in"): up to [max] rows show as they are; with more, the card shows
/// [max] rows and a bit of the next one, and the rest scroll inside it (Gautam 2026-10-23).
class ScrollAfter extends StatefulWidget {
  const ScrollAfter({super.key, required this.children, this.max = 5, this.spacing = 0});
  final List<Widget> children;
  final int max;
  final double spacing;

  @override
  State<ScrollAfter> createState() => _ScrollAfterState();
}

class _ScrollAfterState extends State<ScrollAfter> {
  final _scroll = ScrollController();
  final _col = GlobalKey();
  late List<GlobalKey> _keys;
  double? _height;

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.max + 1, (_) => GlobalKey());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The height of the first [max] rows plus 40% of the next, measured once the rows are laid out.
  void _measure() {
    if (!mounted) return;
    final col = _col.currentContext?.findRenderObject() as RenderBox?;
    final last = _keys[widget.max - 1].currentContext?.findRenderObject() as RenderBox?;
    final next = _keys[widget.max].currentContext?.findRenderObject() as RenderBox?;
    if (col == null || last == null || next == null) return;
    final bottom = last.localToGlobal(Offset(0, last.size.height), ancestor: col).dy;
    final h = bottom + widget.spacing + next.size.height * .4;
    if (_height == null || (_height! - h).abs() > .5) setState(() => _height = h);
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.children;
    if (rows.length <= widget.max) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: widget.spacing, children: rows);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: _height ?? widget.max * 44.0),
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.only(right: 10),
          child: Column(key: _col, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: widget.spacing, children: [
            for (final (i, r) in rows.indexed) i <= widget.max ? KeyedSubtree(key: _keys[i], child: r) : r,
          ]),
        ),
      ),
    );
  }
}
