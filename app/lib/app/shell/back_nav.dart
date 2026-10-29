import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/button.dart';
import '../../core/widgets/client.dart';
import '../../core/widgets/overlays.dart';
import '../../features/client/train/workout_model.dart' show WorkoutController;
import '../services.dart';
import 'nav_items.dart';

/// The phone's back button (Android back, Phase 4). Tabs are opened with `go`, so the router keeps one page and a
/// plain back closed the app. Now back follows the app's own parents, never the app's exit, until the landing page:
/// - a sub-page goes to its section: `/food/log` → `/food`, `/train/workout` → `/train`, `/clients/<id>` → `/clients`;
/// - a bottom-bar tab goes to Home (`/home`, staff `/dashboard`);
/// - a page opened from More (Habits, Check-ins, Library, Programs…) goes to More, then Home;
/// - Home asks "Do you want to exit the app?" (with Resume workout while one is running).
/// A screen with its own steps (a check-in form, the rest panel) handles back first through [BackIntercept].
abstract final class AppBack {
  static final _intercepts = <bool Function()>[];

  /// Sub-pages whose own back button goes somewhere other than their section.
  static const _parents = {'/progress/compare': '/progress/photos'};

  /// Where back goes from [path], or null on the landing page (the exit sheet).
  static String? parentOf(String path, Role role) {
    final home = homeOf(role);
    if (path == home) return null;
    if (_parents[path] case final p?) return p;
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return home;
    if (parts.length > 1) return '/${parts.first}';
    if (bottomFor(role).any((t) => t.path == path) || path == '/more') return home;
    return '/more';
  }

  static String homeOf(Role role) => role == Role.client ? '/home' : '/dashboard';

  /// Main tabs (the bottom bar). Every other page has its own back button and no bottom bar on the phone (clients).
  static bool isTab(String path, Role role) => bottomFor(role).any((t) => t.path == path);

  static Future<void> handle(BuildContext context, String location) async {
    for (final f in _intercepts.reversed.toList()) {
      if (f()) return;
    }
    final me = Services.session.me;
    if (me == null) return;
    final to = parentOf(Uri.parse(location).path, me.role);
    if (to != null) {
      context.go(to);
      return;
    }
    await showExitSheet(context, client: me.role == Role.client);
  }

  /// "Do you want to exit the app?" Exit · Cancel, and Resume workout while a workout is running.
  static Future<void> showExitSheet(BuildContext context, {required bool client}) async {
    final live = client && await WorkoutController.hasLive();
    if (!context.mounted) return;
    // Client pages use the client buttons, staff pages the staff ones.
    Widget btn(BuildContext ctx, String label, String? result, {bool main = false, AppIconData? icon}) => client
        ? CaButton(label, icon: icon, kind: main ? CaBtnKind.dark : CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop(result))
        : AppButton(label, icon: icon, kind: main ? BtnKind.dark : BtnKind.outline, expand: true, onPressed: () => Navigator.of(ctx).pop(result));
    final go = await showAppSheet<String>(
      context,
      title: 'Do you want to exit the app?',
      sub: live ? 'Your workout is still in progress' : 'You can open it again any time.',
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        if (live) CaButton('Resume workout', icon: AppIcons.play, onPressed: () => Navigator.of(ctx).pop('resume')),
        Row(spacing: 8, children: [
          Expanded(child: btn(ctx, 'Cancel', null)),
          Expanded(child: btn(ctx, 'Exit', 'exit', main: !live)),
        ]),
        if (live) Text('The workout timer stops when you leave. Continue workout starts it again.', textAlign: TextAlign.center, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
      ]),
    );
    if (!context.mounted) return;
    if (go == 'resume') context.go('/train/workout');
    if (go == 'exit') {
      if (live) await WorkoutController.pauseLive();
      await SystemNavigator.pop();
    }
  }
}

/// Lets a screen take the back button first (its own steps, an open panel). [onBack] returns true when it handled it.
class BackIntercept extends StatefulWidget {
  const BackIntercept({super.key, required this.onBack, required this.child});
  final bool Function() onBack;
  final Widget child;

  @override
  State<BackIntercept> createState() => _BackInterceptState();
}

class _BackInterceptState extends State<BackIntercept> {
  bool _call() => widget.onBack();

  @override
  void initState() {
    super.initState();
    AppBack._intercepts.add(_call);
  }

  @override
  void dispose() {
    AppBack._intercepts.remove(_call);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
