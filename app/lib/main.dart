import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app/app.dart';
import 'app/router.dart';
import 'app/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Real paths (/join/AMAN-4821, /reset-password?token=…) so links in emails open the right page.
  // The web server must send every unknown path to index.html.
  usePathUrlStrategy();
  Services.push.onOpen = (route) => appRouter.go(route); // tapped push → its page
  await Services.session.restore();
  runApp(const TwvApp());
}
