import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/card.dart';
import '../features/auth/join_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/pending_screen.dart';
import '../features/auth/permissions_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/auth/verify_email_screen.dart';
import '../features/auth/setup/checklist_screen.dart';
import '../features/auth/setup/done_screen.dart';
import '../features/auth/setup/setup_screen.dart';
import 'services.dart';
import 'shell/app_shell.dart';
import 'shell/page.dart';

/// Signed-out pages. A signed-in person is sent on to their landing page.
const _public = ['/login', '/forgot'];

/// Pages opened from a link (email, SMS, WhatsApp). They work signed in or out, and stay
/// open after they sign the person in ("Account created", "You’re in").
const _links = ['/reset-password', '/join', '/start', '/verify-email'];

String homeFor(Role role) => role == Role.client ? '/home' : '/dashboard';

/// Where a person lands after log in: approval wait, the setup steps, or their home.
String landingFor(Me me) {
  if (me.role != Role.client) return homeFor(me.role);
  if (me.needsVerify) return '/verify';
  if (me.pending) return '/pending';
  if (!me.setupComplete && !me.setupLater) return '/setup';
  return '/home';
}

/// A client waiting for approval can only see these.
const _pendingAllowed = ['/pending', '/setup', '/verify', '/permissions'];

/// A client who has not confirmed the email yet can only see these.
const _verifyAllowed = ['/verify', '/permissions'];

bool _under(String path, List<String> roots) => roots.any((p) => path == p || path.startsWith('$p/'));

/// Screens register here as they get built (path -> page). Anything missing
/// shows a holding page so every nav item still opens something.
final Map<String, Widget Function(GoRouterState)> screens = {};

final appRouter = GoRouter(
  initialLocation: '/',
  refreshListenable: Services.session,
  redirect: (context, state) {
    final s = Services.session;
    final path = state.uri.path;
    if (_under(path, _links)) return null;
    final isPublic = _under(path, _public);
    if (!s.signedIn) return isPublic ? null : '/login';
    final me = s.me!;
    if (path == '/' || isPublic) return landingFor(me);
    if (me.needsVerify && !_under(path, _verifyAllowed)) return '/verify';
    if (me.role == Role.client && me.pending && !_under(path, _pendingAllowed)) return '/pending';
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
    // Account pages (decision D-15)
    GoRoute(path: '/forgot', builder: (_, st) => ResetPasswordScreen(email: st.uri.queryParameters['email'] ?? '')),
    GoRoute(path: '/reset-password', builder: (_, st) => ResetPasswordScreen(token: st.uri.queryParameters['token'] ?? '')),
    GoRoute(path: '/join/:code', builder: (_, st) => JoinScreen(code: st.pathParameters['code']!)),
    GoRoute(path: '/start', builder: (_, st) => LoginLinkScreen(token: st.uri.queryParameters['token'] ?? '')),
    GoRoute(path: '/verify', builder: (_, _) => const VerifyEmailScreen()),
    GoRoute(path: '/verify-email', builder: (_, st) => VerifyEmailScreen(token: st.uri.queryParameters['token'] ?? '')),
    GoRoute(
      path: '/permissions',
      builder: (_, st) => PermissionsScreen(
        kind: PermKind.values.asNameMap()[st.uri.queryParameters['kind']] ?? PermKind.notifications,
        next: st.uri.queryParameters['next'],
      ),
    ),
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

Widget _screen(String key, GoRouterState st) => screens[key]?.call(st) ?? _Holding(key);

class _Holding extends StatelessWidget {
  const _Holding(this.path);
  final String path;

  @override
  Widget build(BuildContext context) => StaffPage(
        children: [EmptyState('This page is on the way', sub: 'Being built now ($path).')],
      );
}
