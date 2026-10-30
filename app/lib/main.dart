import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app/app.dart';
import 'app/router.dart';
import 'app/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Real paths (/join/AMAN-4821, /reset-password?token=…) so links in emails open the right page.
  // The web server must send every unknown path to index.html.
  usePathUrlStrategy();
  await _portraitOnPhones();
  Services.push.onOpen = (route) => appRouter.go(route); // tapped push → its page
  await Services.session.restore();
  runApp(const TwvApp());
}

/// Phones stay upright: turning the phone does not turn the app (Probid 2026-10-30). Tablets (shortest side 600 dp
/// and up) and the web still turn, their layouts are built for both.
Future<void> _portraitOnPhones() async {
  if (kIsWeb) return;
  final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
  if (view == null) return;
  final size = view.physicalSize / view.devicePixelRatio;
  if (size.shortestSide >= 600) return;
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
}
