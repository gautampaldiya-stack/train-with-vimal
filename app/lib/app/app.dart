import 'package:flutter/material.dart';

import '../core/theme/theme.dart';
import '../core/widgets/overlays.dart';
import 'router.dart';

class TwvApp extends StatelessWidget {
  const TwvApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Train With Vimal',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        routerConfig: appRouter,
        builder: (context, child) => ToastHost(child: child ?? const SizedBox()),
      );
}
