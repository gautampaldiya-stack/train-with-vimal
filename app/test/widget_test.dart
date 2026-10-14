import 'package:flutter_test/flutter_test.dart';
import 'package:twv/app/router.dart';
import 'package:twv/app/services.dart';

void main() {
  test('role home', () {
    expect(homeFor(Role.client), '/home');
    expect(homeFor(Role.admin), '/dashboard');
    expect(homeFor(Role.trainer), '/dashboard');
  });
}
