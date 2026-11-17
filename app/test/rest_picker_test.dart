import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twv/core/widgets/rest_picker.dart';

void main() {
  test('rest labels', () {
    expect(restLabel(150), '2 min 30 s');
    expect(restLabel(120), '2 min');
    expect(restLabel(45), '45 s');
  });

  testWidgets('rest field opens the minute / second wheels and saves', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    int? got = 90;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: StatefulBuilder(builder: (_, set) => RestField(value: got, sameAs: 120, onChanged: (v) => set(() => got = v)))),
    ));
    expect(find.text('1 min 30 s'), findsOneWidget);
    await t.tap(find.byType(RestField));
    await t.pumpAndSettle();
    expect(find.text('Same as Rest'), findsOneWidget);
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(got, 90);
  });

  testWidgets('same as rest clears the value', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    int? got = 30;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: StatefulBuilder(builder: (_, set) => RestField(value: got, sameAs: 120, onChanged: (v) => set(() => got = v)))),
    ));
    // The open guard counts real time: one open per 450 ms.
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await t.tap(find.byType(RestField));
    await t.pumpAndSettle();
    await t.tap(find.text('Same as Rest'));
    await t.pumpAndSettle();
    expect(got, isNull);
    expect(find.text('Same as Rest · 2 min'), findsOneWidget);
  });
}
