import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A page whose coloured hero runs under the status bar (client Home, trainer Dashboard): light status icons over
/// the hero; once the page has scrolled past it, dark icons on a [bg] backdrop, so the time and battery stay readable
/// over white cards (Probid 2026-11-03). [builder] gets the scroll controller for the page's scroll view.
class HeroStatus extends StatefulWidget {
  const HeroStatus({super.key, required this.bg, required this.builder, this.after = 110});
  final Color bg;
  final double after;
  final Widget Function(ScrollController scroll) builder;

  @override
  State<HeroStatus> createState() => _HeroStatusState();
}

class _HeroStatusState extends State<HeroStatus> {
  final _scroll = ScrollController();
  bool _past = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final p = _scroll.offset > widget.after;
      if (p != _past) setState(() => _past = p);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static const _dark = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark, // Android
    statusBarBrightness: Brightness.light, // iOS
  );

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: _past ? _dark : SystemUiOverlayStyle.light,
        child: Stack(children: [
          widget.builder(_scroll),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: MediaQuery.paddingOf(context).top,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _past ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: ColoredBox(color: widget.bg),
              ),
            ),
          ),
        ]),
      );
}
