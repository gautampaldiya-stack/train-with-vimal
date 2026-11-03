import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twv/core/widgets/overlays.dart';
import 'package:twv/features/client/food/food_parts.dart';

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
    final base = DateTime(2026, 11, 3, 9, 5);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: FdTimeInput(value: base, onChanged: (v) => got = v))));
    expect(find.text('9'), findsOneWidget);
    expect(find.text('05'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '2');
    await t.tap(find.text('PM'));
    await t.pump();
    expect(got, DateTime(2026, 11, 3, 14, 5));
    await t.enterText(find.byType(TextField).first, '13');
    await t.pump();
    expect(find.text('Hour is 1 to 12'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '12');
    await t.enterText(find.byType(TextField).last, '30');
    await t.tap(find.text('AM'));
    await t.pump();
    expect(got, DateTime(2026, 11, 3, 0, 30));
  });
}
