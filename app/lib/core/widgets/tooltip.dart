import 'package:flutter/material.dart';

import '../theme/theme.dart';

enum TipSide { above, below, left, right }

/// The board tooltip (`[data-tip]:hover::after`): white card, thin line border, soft shadow,
/// dark 12.5/600 text, no arrow. Shows while the pointer is on [child], on the given [side].
class AppTooltip extends StatefulWidget {
  const AppTooltip({super.key, required this.message, required this.child, this.side = TipSide.above, this.gap = 6});
  final String message;
  final Widget child;
  final TipSide side;
  final double gap;

  @override
  State<AppTooltip> createState() => _AppTooltipState();
}

class _AppTooltipState extends State<AppTooltip> {
  final _link = LayerLink();
  final _tip = OverlayPortalController();

  @override
  Widget build(BuildContext context) {
    final g = widget.gap;
    final (Alignment target, Alignment follower, Offset off) = switch (widget.side) {
      TipSide.above => (Alignment.topCenter, Alignment.bottomCenter, Offset(0, -g)),
      TipSide.below => (Alignment.bottomCenter, Alignment.topCenter, Offset(0, g)),
      TipSide.left => (Alignment.centerLeft, Alignment.centerRight, Offset(-g, 0)),
      TipSide.right => (Alignment.centerRight, Alignment.centerLeft, Offset(g, 0)),
    };
    return Semantics(
      tooltip: widget.message,
      child: MouseRegion(
        onEnter: (_) => _tip.show(),
        onExit: (_) => _tip.hide(),
        child: CompositedTransformTarget(
          link: _link,
          child: OverlayPortal(
            controller: _tip,
            overlayChildBuilder: (_) => Positioned(
              left: 0,
              top: 0,
              child: CompositedTransformFollower(
                link: _link,
                targetAnchor: target,
                followerAnchor: follower,
                offset: off,
                child: IgnorePointer(child: _TipCard(widget.message)),
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
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
        child: Text(text, softWrap: false, style: AppText.s(12.5, W.w6, h: 1.2)),
      );
}
