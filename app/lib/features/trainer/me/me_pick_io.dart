import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Phone / desktop: the system file picker for a PDF, JPG or PNG (files, not only photos), or the [ext] given
/// (e.g. xlsx, xls, csv for the food import). Returns (file name, bytes).
Future<(String, Uint8List)?> pickDocument({List<String> ext = const ['pdf', 'jpg', 'jpeg', 'png']}) async {
  final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ext);
  if (files.isEmpty) return null;
  final f = files.first;
  return (f.name, await f.xFile.readAsBytes());
}

/// Phone / desktop: drops come through `DropTarget` (desktop_drop); nothing to watch here.
void Function() watchDrops({required void Function(bool over) onOver, required void Function((String, Uint8List) file) onFile}) => () {};
