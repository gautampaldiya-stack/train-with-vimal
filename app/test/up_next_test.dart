import 'package:flutter_test/flutter_test.dart';
import 'package:twv/features/client/home/home_model.dart';

HomeMeal meal(int id, String time, {String pill = 'next'}) => HomeMeal({'id': id, 'name': 'M$id', 'time': time, 'pill': pill});

// Probid 2026-11-04: Up next moves on only when a meal is logged or skipped, not by the clock.
void main() {
  test('nothing logged: the first meal', () {
    expect(upNextMeal([meal(1, '08:00', pill: 'to_log'), meal(2, '13:00'), meal(3, '20:00', pill: 'planned')])?.id, 1);
  });

  test('logged or skipped: the next meal', () {
    expect(upNextMeal([meal(1, '08:00', pill: 'logged'), meal(2, '13:00')])?.id, 2);
    expect(upNextMeal([meal(1, '08:00', pill: 'skipped'), meal(2, '13:00', pill: 'logged'), meal(3, '20:00')])?.id, 3);
  });

  test('all done: nothing', () {
    expect(upNextMeal([meal(1, '08:00', pill: 'logged'), meal(2, '13:00', pill: 'skipped')]), isNull);
    expect(upNextMeal([]), isNull);
  });
}
