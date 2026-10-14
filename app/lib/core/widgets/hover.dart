import 'package:flutter/material.dart';

/// Tracks hover + press for custom-drawn controls (web hover states from the canvas).
class Hover extends StatefulWidget {
  const Hover({super.key, required this.builder, this.onTap, this.cursor, this.enabled = true});
  final Widget Function(BuildContext context, bool hovered, bool pressed) builder;
  final VoidCallback? onTap;
  final MouseCursor? cursor;
  final bool enabled;

  @override
  State<Hover> createState() => _HoverState();
}

class _HoverState extends State<Hover> {
  bool _h = false, _p = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && widget.onTap != null;
    return MouseRegion(
      cursor: active ? (widget.cursor ?? SystemMouseCursors.click) : MouseCursor.defer,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = _p = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: active ? (_) => setState(() => _p = true) : null,
        onTapUp: active ? (_) => setState(() => _p = false) : null,
        onTapCancel: active ? () => setState(() => _p = false) : null,
        onTap: active ? widget.onTap : null,
        child: widget.builder(context, _h && widget.enabled, _p),
      ),
    );
  }
}
