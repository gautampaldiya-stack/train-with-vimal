import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/card.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/pending_screen.dart';
import '../features/auth/setup/checklist_screen.dart';
import '../features/auth/setup/done_screen.dart';
import '../features/auth/setup/setup_screen.dart';
import 'services.dart';
import 'shell/app_shell.dart';
import 'shell/page.dart';

/// Routes that work without a session (login, invite, password reset).
const _public = ['/login', '/forgot', '/reset', '/join', '/verify'];

String homeFor(Role role) => role == Role.client ? '/home' : '/dashboard';

/// Where a person lands after log in: approval wait, the setup steps, or their home.
String landingFor(Me me) {
  if (me.role != Role.client) return homeFor(me.role);
  if (me.pending) return '/pending';
  if (!me.setupComplete && !me.setupLater) return '/setup';
  return '/home';
}

/// A client waiting for approval can only see these.
const _pendingAllowed = ['/pending', '/setup'];

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
    final me = s.me!;
    if (path == '/' || isPublic) return landingFor(me);
    if (me.role == Role.client && me.pending && !_pendingAllowed.any((p) => path == p || path.startsWith('$p/'))) return '/pending';
    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (_, _) => const SizedBox()),
    GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    GoRoute(path: '/pending', builder: (_, _) => const PendingScreen()),
    // Checklist and done are separate pages, not children of /setup: a child route
    // would keep a hidden step page (and its own load) underneath.
    GoRoute(path: '/setup/checklist', builder: (_, _) => const ChecklistScreen()),
    GoRoute(path: '/setup/done', builder: (_, _) => const DoneScreen()),
    GoRoute(
      path: '/setup',
      builder: (_, st) => SetupScreen(
        key: ValueKey(st.uri.query),
        step: int.tryParse(st.uri.queryParameters['step'] ?? ''),
        edit: st.uri.queryParameters['edit'] == '1',
      ),
    ),
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
