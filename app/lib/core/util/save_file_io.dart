import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String> saveFile(String name, List<int> bytes, String mime) async {
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {}
  dir ??= await getApplicationDocumentsDirectory();
  final f = File('${dir.path}${Platform.pathSeparator}$name');
  await f.writeAsBytes(bytes, flush: true);
  return f.path;
}
