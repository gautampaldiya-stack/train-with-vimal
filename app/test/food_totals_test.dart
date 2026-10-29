import 'package:flutter_test/flutter_test.dart';
import 'package:twv/features/client/food/food_model.dart';

// Phase 1 (D-82): the phone shows the server's totals (worked out from unrounded entries) and only adds what
// changed on the phone since, so 3 × 7 g almonds (40.53 kcal each) show 122, not 3 × 41 = 123.
void main() {
  Map<String, dynamic> entry(String id, num kcal) =>
      {'id': id, 'kcal': kcal, 'protein': 1.5, 'carbs': 0.6, 'fat': 3.5, 'source': 'off_plan'};

  test('day total is the server total, not the sum of the rounded rows', () {
    final d = FoodDay({
      'macros': {'kcal': 122.0, 'protein': 4.4, 'carbs': 1.7, 'fat': 10.5},
      'log': [entry('1', 41), entry('2', 41), entry('3', 41)],
    });
    expect(d.eaten, [122.0, 4.4, 1.7, 10.5]);
  });

  test('a food logged on the phone is added on top of the server total', () {
    final d = FoodDay({
      'macros': {'kcal': 122.0, 'protein': 4.4, 'carbs': 1.7, 'fat': 10.5},
      'log': [entry('1', 41), entry('2', 41), entry('3', 41)],
    });
    d.log.add(FEntry(entry('local-1', 260)));
    expect(d.eaten[0], 382.0);
    d.log.removeLast();
    expect(d.eaten[0], 122.0);
  });

  test('meal total is the server meal total', () {
    final d = FoodDay({
      'meals': [
        {
          'id': 1, 'name': 'Breakfast', 'kcal': 520, 'protein': 30.2, 'carbs': 60.1, 'fat': 15.4,
          'items': [
            {'item': 1, 'kcal': 174, 'protein': 10.1, 'carbs': 20.0, 'fat': 5.1},
            {'item': 2, 'kcal': 174, 'protein': 10.1, 'carbs': 20.0, 'fat': 5.1},
            {'item': 3, 'kcal': 174, 'protein': 10.1, 'carbs': 20.0, 'fat': 5.2},
          ],
        },
      ],
    });
    expect(d.meals.first.kcal, 520); // 3 × 173.3 = 519.9 → 520, not 3 × 174 = 522
    expect(d.meals.first.protein, 30.2);
  });

  test('without server totals the rows are added up (older server)', () {
    final d = FoodDay({'log': [entry('1', 41), entry('2', 41)]});
    expect(d.eaten[0], 82.0);
  });
}
