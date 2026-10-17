import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web: the browser's file picker for a PDF, JPG or PNG. Returns (file name, bytes).
Future<(String, Uint8List)?> pickDocument() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.pdf,.jpg,.jpeg,.png,application/pdf,image/jpeg,image/png';
  final done = Completer<(String, Uint8List)?>();
  input.onchange = (web.Event _) {
    final f = input.files?.item(0);
    if (f == null) {
      done.complete(null);
      return;
    }
    f.arrayBuffer().toDart.then((b) => done.complete((f.name, b.toDart.asUint8List())), onError: (_) => done.complete(null));
  }.toJS;
  input.oncancel = (web.Event _) {
    if (!done.isCompleted) done.complete(null);
  }.toJS;
  input.click();
  return done.future;
}
