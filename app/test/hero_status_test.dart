import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twv/core/widgets/hero_status.dart';

void main() {
  testWidgets('status bar turns dark with a backdrop once the hero has scrolled away', (t) async {
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
        child: HeroStatus(
          bg: Colors.white,
          builder: (s) => ListView(controller: s, children: [for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('$i'))]),
        ),
      ),
    ));
    SystemUiOverlayStyle style() => t.widget<AnnotatedRegion<SystemUiOverlayStyle>>(find.byType(AnnotatedRegion<SystemUiOverlayStyle>)).value;
    double backdrop() => t.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
    expect(style(), SystemUiOverlayStyle.light);
    expect(backdrop(), 0);
    await t.drag(find.byType(ListView), const Offset(0, -400));
    await t.pumpAndSettle();
    expect(style().statusBarIconBrightness, Brightness.dark);
    expect(backdrop(), 1);
    await t.drag(find.byType(ListView), const Offset(0, 600));
    await t.pumpAndSettle();
    expect(style(), SystemUiOverlayStyle.light);
  });
}
