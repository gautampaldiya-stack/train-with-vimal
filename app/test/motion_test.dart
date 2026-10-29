import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twv/core/widgets/animated_rows.dart';
import 'package:twv/core/widgets/hover.dart';

// Phase 5: list rows grow in / fold away, taps shrink a little, and nothing moves with "Remove animations" on.
Widget _app(List<String> rows, {bool noMotion = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: noMotion),
        child: Scaffold(body: AnimatedRows(children: [for (final r in rows) Text(r, key: ValueKey(r))])),
      ),
    );

double _h(WidgetTester t, String r) => t.getSize(find.ancestor(of: find.text(r), matching: find.byType(SizeTransition)).first).height;

void main() {
  testWidgets('a new row grows in, a removed row folds away', (t) async {
    await t.pumpWidget(_app(['a', 'b']));
    expect(_h(t, 'a'), greaterThan(0)); // there from the start: no animation
    await t.pumpWidget(_app(['a', 'b', 'c']));
    expect(_h(t, 'c'), 0); // starts folded
    await t.pump(const Duration(milliseconds: 125));
    final mid = _h(t, 'c');
    expect(mid, greaterThan(0));
    await t.pumpAndSettle();
    expect(_h(t, 'c'), greaterThan(mid));

    await t.pumpWidget(_app(['a', 'c']));
    expect(find.text('b'), findsOneWidget); // still on screen while it folds
    await t.pumpAndSettle();
    expect(find.text('b'), findsNothing);
  });

  testWidgets('with animations off a removed row goes at once', (t) async {
    await t.pumpWidget(_app(['a', 'b'], noMotion: true));
    await t.pumpWidget(_app(['a'], noMotion: true));
    await t.pump();
    expect(find.text('b'), findsNothing);
  });

  testWidgets('a tappable control shrinks while pressed', (t) async {
    await t.pumpWidget(MaterialApp(home: Center(child: Hover(onTap: () {}, builder: (_, _, _) => const SizedBox(width: 100, height: 40)))));
    final g = await t.startGesture(t.getCenter(find.byType(SizedBox).last));
    await t.pumpAndSettle();
    expect(t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, .97);
    await g.up();
    await t.pumpAndSettle();
    expect(t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });
}
