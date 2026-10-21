import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/icons/app_icons.dart';
import '../core/leave/leave_guard.dart';
import '../core/widgets/button.dart';
import '../core/widgets/card.dart';
import '../core/widgets/overlays.dart';
import '../features/auth/setup/setup_state.dart';
import '../features/auth/join_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/pending_screen.dart';
import '../features/auth/permissions_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/auth/verify_email_screen.dart';
import '../features/auth/setup/checklist_screen.dart';
import '../features/auth/setup/done_screen.dart';
import '../features/auth/setup/setup_screen.dart';
import '../features/client/checkins/checkins_screen.dart';
import '../features/client/food/food_log_screen.dart';
import '../features/client/food/food_screen.dart';
import '../features/client/habits/habits_screen.dart';
import '../features/library/habits/habits_screen.dart';
import '../features/client/progress/progress_pages.dart';
import '../features/client/progress/progress_screen.dart';
import '../features/client/home/home_screen.dart';
import '../features/client/library/library_screen.dart';
import '../features/client/more/about_screen.dart';
import '../features/client/more/more_screen.dart';
import '../features/client/train/train_screen.dart';
import '../features/client/train/workout_screen.dart';
import '../features/library/content/content_screen.dart';
import '../features/library/exercises/detail_screen.dart';
import '../features/library/exercises/edit_screen.dart';
import '../features/library/exercises/library_screen.dart';
import '../features/library/nutrition/meal_builder_screen.dart';
import '../features/library/nutrition/nutrition_screen.dart';
import '../features/library/programs/builder_screen.dart';
import '../features/library/programs/programs_screen.dart';
import '../features/trainer/more/more_screen.dart';
import '../features/trainer/calendar/cal_screen.dart';
import '../features/trainer/me/me_screen.dart';
import '../features/trainer/checkins/tc_screen.dart';
import '../features/trainer/client_profile/cp_screen.dart';
import '../features/trainer/clients/clients_screen.dart';
import '../features/trainer/dashboard/dashboard_screen.dart';
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
final Map<String, Widget Function(GoRouterState)> screens = {
  '/home': (_) => const ClientHomeScreen(),
  '/habits': (_) => const ClientHabitsScreen(),
  '/food': (_) => const ClientFoodScreen(),
  '/food/:id': (st) => st.pathParameters['id'] == 'log'
      ? FoodLogScreen(key: ValueKey(st.uri.toString()), meal: st.uri.queryParameters['meal'], at: st.uri.queryParameters['at'])
      : const ClientFoodScreen(),
  '/checkins': (_) => const ClientCheckinsScreen(),
  '/checkins/:id': (st) => ClientCheckinsScreen(
        key: ValueKey(st.uri.toString()),
        id: st.pathParameters['id'],
        edit: st.uri.queryParameters['edit'] == '1',
      ),
  '/progress': (_) => const ClientProgressScreen(),
  '/progress/:id': (st) {
    final q = st.uri.queryParameters;
    return switch (st.pathParameters['id']) {
      'history' => ProgressHistoryScreen(key: ValueKey(st.uri.toString()), type: q['type'], range: q['range']),
      'photos' => const ProgressPhotosScreen(),
      'compare' => ProgressCompareScreen(key: ValueKey(st.uri.toString()), a: q['a'], b: q['b'], pose: q['pose']),
      _ => const ClientProgressScreen(),
    };
  },
  '/train': (st) => ClientTrainScreen(discarded: int.tryParse(st.uri.queryParameters['discarded'] ?? '') ?? 0),
  '/train/:id': (st) => WorkoutScreen(
        key: ValueKey(st.uri.toString()),
        start: int.tryParse(st.uri.queryParameters['start'] ?? ''),
        reopen: st.uri.queryParameters['reopen'],
        then: st.uri.queryParameters['then'],
      ),
  '/library': (_) => const ClientLibraryScreen(),
  '/library/:id': (st) => ClientLibraryScreen(key: ValueKey(st.uri.toString()), id: st.pathParameters['id']),
  '/more': (_) => const ClientMoreScreen(),
  '/more/:id': (st) => st.pathParameters['id'] == 'about'
      ? const ClientAboutScreen()
      : ClientMoreScreen(key: ValueKey(st.uri.toString()), view: st.pathParameters['id']!),
};

/// Trainer pages. Trainer and client paths overlap (/checkins, /calendar, /more, /habits), so each role has its own map.
final Map<String, Widget Function(GoRouterState)> trainerScreens = {
  '/dashboard': (_) => const TrainerDashboardScreen(),
  '/clients': (_) => const TrainerClientsScreen(),
  '/checkins': (_) => const TrainerCheckinsScreen(),
  '/checkins/:id': (st) => TrainerCheckinsScreen(id: st.pathParameters['id']),
  '/calendar': (_) => const TrainerCalendarScreen(),
  '/more': (_) => const TrainerMoreScreen(),
  '/programs': (_) => const ProgramsScreen(),
  '/programs/:id': (st) => ProgramBuilderScreen(key: ValueKey(st.uri.toString()), id: st.pathParameters['id']!, open: st.uri.queryParameters['open']),
  '/nutrition': (st) => NutritionScreen(tab: st.uri.queryParameters['tab']),
  '/nutrition/:id': (st) => MealPlanBuilderScreen(key: ValueKey(st.uri.toString()), id: st.pathParameters['id']!, open: st.uri.queryParameters['open']),
  '/habits': (st) => HabitsScreen(tab: st.uri.queryParameters['tab']),
  '/exercises': (_) => const ExerciseLibraryScreen(),
  '/content': (st) => ContentScreen(newKind: st.uri.queryParameters['new']),
  '/content/:id': (st) => ContentScreen(key: ValueKey(st.uri.toString()), open: st.pathParameters['id']),
  '/exercises/:id': (st) {
    final id = st.pathParameters['id']!;
    if (id == 'new') return ExerciseEditScreen(key: ValueKey(st.uri.toString()));
    if (st.uri.queryParameters['edit'] == '1') return ExerciseEditScreen(key: ValueKey(st.uri.toString()), id: id);
    return ExerciseDetailScreen(key: ValueKey(st.uri.toString()), id: id);
  },
  '/me': (_) => const TrainerMeScreen(key: ValueKey('me')),
  '/me/:id': (st) => TrainerMeScreen(key: const ValueKey('me'), tab: st.pathParameters['id']),
  '/clients/:id': (st) => TrainerClientProfileScreen(key: ValueKey(st.uri.toString()), id: st.pathParameters['id']!, tab: st.uri.queryParameters['tab']),
};

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
          // Library pages with an editor in the page (Habits & supplements) ask before they close too.
          onExit: (context, _) => LeaveGuard.ask(context),
          pageBuilder: (_, st) => NoTransitionPage(child: _screen('/${st.pathParameters['section']}', st)),
          routes: [
            GoRoute(
              path: ':id',
              // A page with unsaved work (program builder, exercise form) is asked before it closes (D-43).
              onExit: (context, _) => LeaveGuard.ask(context),
              pageBuilder: (_, st) => NoTransitionPage(child: _screen('/${st.pathParameters['section']}/:id', st)),
            ),
          ],
        ),
      ],
    ),
  ],
);

Widget _screen(String key, GoRouterState st) {
  final map = switch (Services.session.me?.role) { Role.trainer => trainerScreens, Role.admin => const <String, Widget Function(GoRouterState)>{}, _ => screens };
  return map[key]?.call(st) ?? _Holding(key);
}

class _Holding extends StatelessWidget {
  const _Holding(this.path);
  final String path;

  /// Settings (admin) and My profile (trainer) keep a working Log out
  /// until the full pages are built.
  static const _account = {'/settings', '/me'};

  @override
  Widget build(BuildContext context) => StaffPage(
        children: [
          EmptyState(
            'This page is on the way',
            sub: 'Being built now ($path).',
            action: _account.contains(path) ? AppButton('Log out', icon: AppIcons.logout, onPressed: () => confirmLogOut(context)) : null,
          ),
        ],
      );
}

/// "Log out?" confirm from the account boards (`ClientMore`), then sign out → log in page.
Future<void> confirmLogOut(BuildContext context) async {
  final ok = await confirmAction(context,
      title: 'Log out?',
      body: 'Everything you logged is saved. You need your password to log in again.',
      confirm: 'Log out',
      danger: true,
      icon: AppIcons.logout);
  if (!ok) return;
  SetupState.instance.reset();
  await Services.session.signOut();
}
