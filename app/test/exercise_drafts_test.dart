import 'package:flutter_test/flutter_test.dart';
import 'package:twv/features/trainer/client_profile/cp_plans_model.dart';

/// Tracker F43: the Edit exercise drawer used to write into the live exercise on every key press.
void main() {
  test('typing in the drawer does not change the exercise behind it', () {
    final day = <Map<String, dynamic>>[
      {'id': 1, 'sets': 3, 'reps': '8–10', 'note': ''},
    ];
    final d = ExerciseDrafts(day);
    d.of(0)['sets'] = 5;
    d.of(0)['note'] = 'slow down';
    expect(day[0]['sets'], 3);
    expect(day[0]['note'], '');
  });

  test('Done writes the draft back; closing without Done drops it', () {
    final day = <Map<String, dynamic>>[
      {'id': 1, 'sets': 3, 'reps': '8–10'},
      {'id': 2, 'sets': 4, 'reps': '6'},
    ];
    final closed = ExerciseDrafts(day);
    closed.of(0)['sets'] = 6;
    // drawer closed by back / swipe / tap outside: nothing applied
    expect(day[0]['sets'], 3);

    final done = ExerciseDrafts(day);
    done.of(1)['reps'] = '8';
    done.of(0); // only looked at
    expect(done.apply(), isTrue);
    expect(day[1]['reps'], '8');
    expect(day[0]['sets'], 3);
    expect(ExerciseDrafts(day).apply(), isFalse);
  });
}
