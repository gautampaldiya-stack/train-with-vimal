import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/icons/app_icons.dart';
import '../core/realtime/realtime.dart';
import '../core/widgets/overlays.dart';
import 'router.dart';
import 'services.dart';

/// Bell count: live from the socket (`unread` on connect / after reads, +1 on each `notification`);
/// the page's own number until the socket is up.
class UnreadCount extends StatelessWidget {
  const UnreadCount({super.key, required this.fallback, required this.builder});
  final int fallback;
  final Widget Function(BuildContext context, int count) builder;

  @override
  Widget build(BuildContext context) {
    final rt = Services.realtime;
    return ListenableBuilder(
      listenable: Listenable.merge([rt.unread, rt.connected]),
      builder: (context, _) => builder(context, rt.connected.value ? rt.unread.value : fallback),
    );
  }
}

/// While the app is open a new notification also shows a toast ("Open" goes to its page), on web,
/// phone and tablet alike; the push service only shows one when the app is in the background (D-58).
class NotificationToasts extends StatefulWidget {
  const NotificationToasts({super.key, required this.child});
  final Widget child;

  @override
  State<NotificationToasts> createState() => _NotificationToastsState();
}

class _NotificationToastsState extends State<NotificationToasts> {
  StreamSubscription<RealtimeEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Services.realtime.events.where((e) => e.event == 'notification').listen(_show);
  }

  void _show(RealtimeEvent e) {
    if (!mounted) return;
    final p = e.payload;
    final title = '${p['title'] ?? ''}'.trim();
    if (title.isEmpty) return;
    final body = '${p['body'] ?? ''}'.trim();
    final route = '${(p['data'] as Map?)?['route'] ?? ''}';
    showToast(context, title,
        sub: body.isEmpty ? null : body,
        kind: ToastKind.info,
        icon: AppIcons.bell,
        action: route.isEmpty ? null : 'Open',
        onAction: route.isEmpty ? null : () => appRouter.go(route));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
