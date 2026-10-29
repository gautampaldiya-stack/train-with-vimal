import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Phase 4 root cause: tabs open with `go`, so the router holds one page and Android back had nothing to pop, which
// closed the app. A PopScope in the shell (as in AppShell) gets the back press instead. Same route shape as router.dart.
void main() {
  testWidgets('back in a ShellRoute page reaches the shell PopScope, not the system', (tester) async {
    final backs = <String>[];
    late GoRouter router;
    router = GoRouter(initialLocation: '/food', routes: [
      ShellRoute(
        builder: (context, state, child) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            backs.add(state.uri.path);
            if (state.uri.path != '/home') router.go('/home');
          },
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/:section',
            pageBuilder: (_, st) => NoTransitionPage(child: Text(st.pathParameters['section']!)),
            routes: [GoRoute(path: ':id', pageBuilder: (_, st) => NoTransitionPage(child: Text(st.pathParameters['id']!)))],
          ),
        ],
      ),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(find.text('food'), findsOneWidget);

    final handled = await tester.binding.handlePopRoute(); // Android back
    await tester.pumpAndSettle();
    expect(backs, ['/food']);
    expect(find.text('home'), findsOneWidget); // went to Home
    expect(handled, isTrue);

    await tester.binding.handlePopRoute(); // on Home: the shell decides (exit sheet), the app is not closed by the router
    await tester.pumpAndSettle();
    expect(backs, ['/food', '/home']);
    expect(find.text('home'), findsOneWidget);
  });
}
