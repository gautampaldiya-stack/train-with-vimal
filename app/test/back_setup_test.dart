import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Probid 2026-11-04: back on the onboarding closed the app. /setup sits outside the ShellRoute, so the shell's
// PopScope never saw the press; the setup pages now have their own PopScope (same shape as below).
void main() {
  testWidgets('back on a page outside the shell reaches its PopScope, the app stays open', (tester) async {
    var backs = 0;
    final router = GoRouter(initialLocation: '/setup', routes: [
      GoRoute(
        path: '/setup',
        builder: (_, _) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) backs++;
          },
          child: const Text('setup'),
        ),
      ),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    final handled = await tester.binding.handlePopRoute(); // Android back
    await tester.pumpAndSettle();
    expect(handled, isTrue); // not passed on to the system (which would close the app)
    expect(backs, 1);
    expect(find.text('setup'), findsOneWidget);
  });
}
