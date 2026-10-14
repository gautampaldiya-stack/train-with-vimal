import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/card.dart';
import 'services.dart';
import 'shell/app_shell.dart';
import 'shell/page.dart';

/// Routes that work without a session (login, invite, password reset).
const _public = ['/login', '/forgot', '/reset', '/join', '/verify'];

String homeFor(Role role) => role == Role.client ? '/home' : '/dashboard';

/// Screens register here as they get built (path -> page). Anything missing
/// shows a holding page so every nav item still opens something.
final Map<String, Widget Function(GoRouterState)> screens = {};

/// Public (signed-out) screens, same idea.
final Map<String, Widget Function(GoRouterState)> publicScreens = {};

final appRouter = GoRouter(
  initialLocation: '/',
  refreshListenable: Services.session,
  redirect: (context, state) {
    final s = Services.session;
    final path = state.uri.path;
    final isPublic = _public.any((p) => path == p || path.startsWith('$p/'));
    if (!s.signedIn) return isPublic ? null : '/login';
    if (path == '/' || path == '/login') return homeFor(s.me!.role);
    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (_, _) => const SizedBox()),
    GoRoute(path: '/login', builder: (_, st) => _public$('/login', st)),
    GoRoute(path: '/forgot', builder: (_, st) => _public$('/forgot', st)),
    GoRoute(path: '/reset/:token', builder: (_, st) => _public$('/reset', st)),
    GoRoute(path: '/join/:code', builder: (_, st) => _public$('/join', st)),
    GoRoute(path: '/verify', builder: (_, st) => _public$('/verify', st)),
    ShellRoute(
      builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(
          path: '/:section',
          pageBuilder: (_, st) => NoTransitionPage(child: _screen('/${st.pathParameters['section']}', st)),
          routes: [
            GoRoute(
              path: ':id',
              pageBuilder: (_, st) => NoTransitionPage(child: _screen('/${st.pathParameters['section']}/:id', st)),
            ),
          ],
        ),
      ],
    ),
  ],
);

Widget _public$(String key, GoRouterState st) => publicScreens[key]?.call(st) ?? const _Holding('Train With Vimal');

Widget _screen(String key, GoRouterState st) => screens[key]?.call(st) ?? _Holding(key);

class _Holding extends StatelessWidget {
  const _Holding(this.path);
  final String path;

  @override
  Widget build(BuildContext context) => StaffPage(
        children: [EmptyState('This page is on the way', sub: 'Being built now ($path).')],
      );
}
