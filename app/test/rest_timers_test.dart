import 'package:flutter_test/flutter_test.dart';
import 'package:twv/features/client/train/train_model.dart';
import 'package:twv/features/client/train/workout_model.dart';

/// Tracker G44 / G47: which rest an exercise uses for working, warm-up and drop sets.
TrainEx _ex(Map<String, dynamic> j) => TrainEx({'id': 1, 'sets': 3, 'reps': '8', 'rest_seconds': 90, ...j}, 0);

void main() {
  test('the coach\'s rest; warm-up and drop fall back to it', () {
    expect(WorkoutController.planRest(_ex({})), (work: 90, warmup: 90, drop: 90));
    expect(WorkoutController.planRest(_ex({'rest_warmup_seconds': 30, 'rest_drop_seconds': 0})), (work: 90, warmup: 30, drop: 0));
  });

  test('the client\'s own timers win, each one on its own', () {
    final x = _ex({'rest_warmup_seconds': 30, 'rest_pref': {'work': 150, 'warmup': null, 'drop': 10}});
    expect(WorkoutController.planRest(x), (work: 150, warmup: 30, drop: 10));
  });

  test('locked by the coach: the client\'s timers are ignored', () {
    final x = _ex({'rest_locked': true, 'rest_pref': {'work': 150, 'warmup': 5, 'drop': 10}});
    expect(WorkoutController.planRest(x), (work: 90, warmup: 90, drop: 90));
  });
}
