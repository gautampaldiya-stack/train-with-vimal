import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Services.session.restore();
  runApp(const TwvApp());
}
