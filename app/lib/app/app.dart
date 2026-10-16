import 'package:flutter/material.dart';

import '../core/theme/theme.dart';
import 'services.dart';
import '../core/widgets/overlays.dart';
import 'page_title.dart';
import 'router.dart';

class TwvApp extends StatelessWidget {
  const TwvApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        routerConfig: appRouter,
        // The tab title follows the page ("My clients · Train With Vimal"); this Title sits under the app's own, so it wins.
        builder: (context, child) => ListenableBuilder(
          listenable: Listenable.merge([appRouter.routerDelegate, Services.session]),
          builder: (context, _) => Title(
            title: pageTitle(appRouter.routerDelegate.currentConfiguration.uri.path),
            color: AppColors.accent,
            child: ToastHost(child: child ?? const SizedBox()),
          ),
        ),
      );
}
