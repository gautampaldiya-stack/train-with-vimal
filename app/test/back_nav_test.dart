import 'package:flutter_test/flutter_test.dart';
import 'package:twv/app/services.dart';
import 'package:twv/app/shell/back_nav.dart';

// Phase 4: the phone's back button follows the app's parents and ends at Home's exit sheet (null = exit sheet).
void main() {
  String? c(String p) => AppBack.parentOf(p, Role.client);

  test('client: tabs go to Home, Home asks to exit', () {
    expect(c('/home'), isNull);
    for (final t in ['/train', '/food', '/progress', '/more']) {
      expect(c(t), '/home', reason: t);
    }
  });

  test('client: pages opened from More go to More, then Home', () {
    for (final t in ['/habits', '/checkins', '/library']) {
      expect(c(t), '/more', reason: t);
    }
    expect(c('/more/about'), '/more');
    expect(c(c('/more/about')!), '/home');
  });

  test('client: sub-pages go to their section, never out of the app', () {
    expect(c('/food/log'), '/food');
    expect(c('/train/workout'), '/train');
    expect(c('/progress/history'), '/progress');
    expect(c('/progress/compare'), '/progress/photos');
    expect(c('/checkins/forms/12'), '/checkins');
    expect(c('/library/abc'), '/library');
  });

  test('staff: tabs to Dashboard, More pages to More, profiles to their list', () {
    expect(AppBack.parentOf('/dashboard', Role.trainer), isNull);
    expect(AppBack.parentOf('/clients', Role.trainer), '/dashboard');
    expect(AppBack.parentOf('/programs', Role.trainer), '/more');
    expect(AppBack.parentOf('/clients/42', Role.admin), '/clients');
    expect(AppBack.parentOf('/approvals', Role.admin), '/dashboard');
  });

  test('bottom bar only on the client main tabs', () {
    expect(AppBack.isTab('/food', Role.client), isTrue);
    expect(AppBack.isTab('/train/workout', Role.client), isFalse);
    expect(AppBack.isTab('/habits', Role.client), isFalse);
  });
}
