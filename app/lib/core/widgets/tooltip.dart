import 'package:flutter/material.dart';

import '../theme/theme.dart';

enum TipSide { above, below, left, right }

/// The board tooltip (`[data-tip]:hover::after`): white card, thin line border, soft shadow,
/// dark 12.5/600 text, no arrow. Shows while the pointer is on [child], on the given [side].
class AppTooltip extends StatefulWidget {
  const AppTooltip({super.key, required this.message, required this.child, this.side = TipSide.above, this.gap = 6, this.when});
  final String message;
  final Widget child;
  final TipSide side;
  final double gap;

  /// Shown only when this says yes for the child's size at hover time (CutText: only when the text is cut).
  final bool Function(Size size)? when;

  @override
  State<AppTooltip> createState() => _AppTooltipState();
}

class _AppTooltipState extends State<AppTooltip> {
  final _tip = OverlayPortalController();
  Rect? _target;

  void _show() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    if (widget.when != null && !widget.when!(box.size)) return;
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    final o = box.localToGlobal(Offset.zero, ancestor: overlay);
    setState(() => _target = o & box.size);
    _tip.show();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        tooltip: widget.message,
        child: MouseRegion(
          onEnter: (_) => _show(),
          onExit: (_) => _tip.hide(),
          child: OverlayPortal(
            controller: _tip,
            overlayChildBuilder: (_) => _target == null
                ? const SizedBox.shrink()
                : Positioned.fill(
                    child: IgnorePointer(
                      child: CustomSingleChildLayout(
                        delegate: _TipLayout(_target!, widget.side, widget.gap),
                        child: _TipCard(widget.message),
                      ),
                    ),
                  ),
            child: widget.child,
          ),
        ),
      );
}

/// Places the tip on its side of the target and keeps it inside the screen (8 px from every edge);
/// above / below flip when there is no room.
class _TipLayout extends SingleChildLayoutDelegate {
  _TipLayout(this.target, this.side, this.gap);
  final Rect target;
  final TipSide side;
  final double gap;
  static const _edge = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) =>
      BoxConstraints(maxWidth: (c.maxWidth - 2 * _edge).clamp(0, 320), maxHeight: c.maxHeight - 2 * _edge);

  @override
  Offset getPositionForChild(Size size, Size tip) {
    var s = side;
    if (s == TipSide.above && target.top - gap - tip.height < _edge) s = TipSide.below;
    if (s == TipSide.below && target.bottom + gap + tip.height > size.height - _edge) s = TipSide.above;
    if (s == TipSide.left && target.left - gap - tip.width < _edge) s = TipSide.right;
    if (s == TipSide.right && target.right + gap + tip.width > size.width - _edge) s = TipSide.left;
    final (x, y) = switch (s) {
      TipSide.above => (target.center.dx - tip.width / 2, target.top - gap - tip.height),
      TipSide.below => (target.center.dx - tip.width / 2, target.bottom + gap),
      TipSide.left => (target.left - gap - tip.width, target.center.dy - tip.height / 2),
      TipSide.right => (target.right + gap, target.center.dy - tip.height / 2),
    };
    return Offset(
      x.clamp(_edge, (size.width - tip.width - _edge).clamp(_edge, double.infinity)),
      y.clamp(_edge, (size.height - tip.height - _edge).clamp(_edge, double.infinity)),
    );
  }

  @override
  bool shouldRelayout(_TipLayout old) => old.target != target || old.side != side || old.gap != gap;
}

class _TipCard extends StatelessWidget {
  const _TipCard(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppRadius.all(AppRadius.input),
          border: Border.all(color: AppColors.line),
          boxShadow: const [
            BoxShadow(color: Color(0x1F171717), blurRadius: 16, offset: Offset(0, 4)),
            BoxShadow(color: Color(0x0F171717), blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
        child: Text(text, style: AppText.s(12.5, W.w6, h: 1.3)),
      );
}

/// A Text that ends in "…" when there is no room, and then shows the whole text in a tooltip on hover
/// (Gautam, 22 Oct: every cut text shows its full text on hover). Same look as Text; one line unless [maxLines].
class CutText extends StatelessWidget {
  const CutText(String this.data, {super.key, this.style, this.maxLines, this.textAlign, this.overflow = TextOverflow.ellipsis, this.softWrap}) : span = null;

  /// For a Text.rich ("Riya Sharma · Daily check-in"): the tooltip shows the plain text.
  const CutText.rich(InlineSpan this.span, {super.key, this.style, this.maxLines, this.textAlign, this.overflow = TextOverflow.ellipsis, this.softWrap}) : data = null;
  final String? data;
  final InlineSpan? span;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? textAlign;
  final TextOverflow overflow;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    // an ellipsis with no line limit still cuts at the end of the first line (Flutter), so that is 1
    final lines = maxLines ?? (overflow == TextOverflow.ellipsis || softWrap == false ? 1 : null);
    final base = DefaultTextStyle.of(context).style.merge(style);
    return AppTooltip(
      message: data ?? span!.toPlainText(),
      when: (size) {
        final tp = TextPainter(
          text: TextSpan(text: data, style: base, children: span == null ? null : [span!]),
          maxLines: lines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: size.width);
        // with a line limit: more lines than allowed; without one: taller than the room it got
        final cut = lines != null ? tp.didExceedMaxLines : tp.height > size.height + 1;
        tp.dispose();
        return cut;
      },
      child: data != null
          ? Text(data!, style: style, maxLines: maxLines, textAlign: textAlign, overflow: overflow, softWrap: softWrap)
          : Text.rich(span!, style: style, maxLines: maxLines, textAlign: textAlign, overflow: overflow, softWrap: softWrap),
    );
  }
}
