import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Phone: a photo of the document from the gallery (JPG / PNG). Returns (file name, bytes).
Future<(String, Uint8List)?> pickDocument() async {
  final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, maxHeight: 2400, imageQuality: 85);
  if (x == null) return null;
  return (x.name, await x.readAsBytes());
}
