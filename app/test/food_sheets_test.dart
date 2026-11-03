import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twv/core/widgets/overlays.dart';
import 'package:twv/features/client/food/food_parts.dart';
import 'package:twv/features/client/food/food_screen.dart' show WaterHistory;

void main() {
  testWidgets('a sheet\'s own controller is disposed only after it closes (custom food crash)', (t) async {
    late BuildContext ctx;
    final name = TextEditingController(text: 'demo');
    final tick = ValueNotifier(0);
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    showAppSheet(ctx, owns: [name, tick], listen: tick, title: 'Create custom food',
        builder: (_) => TextField(controller: name));
    await t.pumpAndSettle();
    Navigator.of(ctx).pop();
    tick.value++; // the page rebuilds the closing sheet, as Save does
    await t.pump();
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(() => name.addListener(() {}), throwsFlutterError); // freed once the sheet is gone
  });

  testWidgets('Other time: hour and minute boxes with AM / PM', (t) async {
    DateTime? got;
    bool? ok;
    final base = DateTime(2026, 11, 3, 9, 5);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: FdTimeInput(value: base, onChanged: (v) => got = v, onValid: (v) => ok = v))));
    expect(find.text('9'), findsOneWidget);
    expect(find.text('05'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '2');
    await t.tap(find.text('PM'));
    await t.pump();
    expect(got, DateTime(2026, 11, 3, 14, 5));
    await t.enterText(find.byType(TextField).first, '13');
    await t.pump();
    expect(find.text('Hour is 1 to 12'), findsOneWidget);
    expect(ok, isFalse); // Use this time stays off
    await t.enterText(find.byType(TextField).first, '');
    expect(ok, isFalse);
    await t.enterText(find.byType(TextField).first, '12');
    await t.enterText(find.byType(TextField).last, '30');
    await t.tap(find.text('AM'));
    await t.pump();
    expect(got, DateTime(2026, 11, 3, 0, 30));
    expect(ok, isTrue);
  });

  testWidgets('Water history fits a phone and folds older weeks', (t) async {
    t.view.physicalSize = const Size(360, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Map wk(String start, List<int> ml, {int fut = 0}) => {
          'start': start,
          'avg_ml': 1750,
          'total_ml': 3500,
          'goal_days': 1,
          'days': [
            for (var i = 0; i < 7; i++)
              {'date': DateTime.parse(start).add(Duration(days: i)).toIso8601String().substring(0, 10), 'ml': ml[i], 'future': i >= 7 - fut}
          ],
        };
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WaterHistory(goal: 3000, today: DateTime(2026, 11, 3), weeks: [
            wk('2026-11-02', [1500, 2000, 0, 0, 0, 0, 0], fut: 5),
            wk('2026-10-26', [0, 0, 1500, 3500, 0, 1800, 0]),
            wk('2026-10-19', [1500, 0, 1500, 1500, 1500, 1800, 0]),
          ]),
        ),
      ),
    ));
    expect(t.takeException(), isNull);
    expect(find.text('This week'), findsNothing); // inside a Text.rich
    expect(find.text('3.5'), findsOneWidget);
    expect(find.text('1.8'), findsOneWidget); // only last week's chart is open
    await t.tap(find.textContaining('19–25 Oct'));
    await t.pump();
    expect(find.text('1.8'), findsNWidgets(2));
    expect(t.takeException(), isNull);
  });
}
