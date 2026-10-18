import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Phone / desktop: the system file picker for a PDF, JPG or PNG (files, not only photos). Returns (file name, bytes).
Future<(String, Uint8List)?> pickDocument() async {
  final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png']);
  if (files.isEmpty) return null;
  final f = files.first;
  return (f.name, await f.xFile.readAsBytes());
}

/// Phone / desktop: drops come through `DropTarget` (desktop_drop); nothing to watch here.
void Function() watchDrops({required void Function(bool over) onOver, required void Function((String, Uint8List) file) onFile}) => () {};
