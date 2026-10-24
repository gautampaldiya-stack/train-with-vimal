import 'package:flutter/material.dart';

import '../core/theme/theme.dart';
import 'services.dart';
import '../core/widgets/overlays.dart';
import 'page_title.dart';
import 'router.dart';
import 'unread.dart';

class TwvApp extends StatelessWidget {
  const TwvApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        routerConfig: appRouter,
        // The tab title follows the page ("My clients · Train With Vimal"); this Title sits under the app's own, so it wins.
        builder: (context, child) => _PageTitle(child: ToastHost(child: NotificationToasts(child: child ?? const SizedBox()))),
      );
}

/// Sets the browser tab title from the current path. The router notifies while it builds, so the
/// update waits for the end of the frame instead of rebuilding the app mid-build.
class _PageTitle extends StatefulWidget {
  const _PageTitle({required this.child});
  final Widget child;

  @override
  State<_PageTitle> createState() => _PageTitleState();
}

class _PageTitleState extends State<_PageTitle> {
  // The unread count goes in front of the tab title ("(3) Clients - Train With Vimal"), so a tab in the
  // background shows that something came in.
  final _source = Listenable.merge(
      [appRouter.routerDelegate, Services.session, Services.realtime.unread, Services.realtime.connected]);
  String _title = appName;
  bool _queued = false;

  String get _now {
    final t = pageTitle(appRouter.routerDelegate.currentConfiguration.uri.path);
    final rt = Services.realtime;
    final n = Services.session.signedIn && rt.connected.value ? rt.unread.value : 0;
    return n > 0 ? '(${n > 99 ? '99+' : n}) $t' : t;
  }

  @override
  void initState() {
    super.initState();
    _source.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _apply());
  }

  void _changed() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _apply())
      ..ensureVisualUpdate();
  }

  void _apply() {
    _queued = false;
    if (!mounted) return;
    final t = _now;
    if (t != _title) setState(() => _title = t);
  }

  @override
  void dispose() {
    _source.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Title(title: _title, color: AppColors.accent, child: widget.child);
}
