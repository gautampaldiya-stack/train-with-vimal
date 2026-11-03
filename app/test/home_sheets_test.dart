import 'package:flutter_test/flutter_test.dart';
import 'package:twv/features/client/home/home_sheets.dart' show parseSleep;

void main() {
  test('typed sleep', () {
    expect(parseSleep('7:30'), 450);
    expect(parseSleep('7.30'), 450);
    expect(parseSleep('7.5'), 450);
    expect(parseSleep('7'), 420);
    expect(parseSleep('6:05'), 365);
    expect(parseSleep('7:75'), isNull);
    expect(parseSleep('16'), isNull);
    expect(parseSleep(''), isNull);
  });
}
