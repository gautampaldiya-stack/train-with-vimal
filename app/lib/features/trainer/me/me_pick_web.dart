import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web: the browser's file picker for a PDF, JPG or PNG, or the [ext] given. Returns (file name, bytes).
Future<(String, Uint8List)?> pickDocument({List<String>? ext}) async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = ext == null ? '.pdf,.jpg,.jpeg,.png,application/pdf,image/jpeg,image/png' : ext.map((e) => '.$e').join(',');
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

/// Web: while the upload modal is open, a file dragged anywhere over the page is caught here (the browser would
/// otherwise open it in a new tab). [onOver] says whether a file is being dragged over; [onFile] gets the first
/// dropped file. Returns a function that stops listening.
void Function() watchDrops({required void Function(bool over) onOver, required void Function((String, Uint8List) file) onFile}) {
  var depth = 0;
  bool hasFiles(web.DragEvent e) => e.dataTransfer?.types.toDart.any((t) => t.toDart == 'Files') ?? false;
  final enter = (web.DragEvent e) {
    if (!hasFiles(e)) return;
    e.preventDefault();
    if (depth++ == 0) onOver(true);
  }.toJS;
  final over = (web.DragEvent e) {
    if (!hasFiles(e)) return;
    e.preventDefault();
    e.dataTransfer?.dropEffect = 'copy';
  }.toJS;
  final leave = (web.DragEvent e) {
    if (!hasFiles(e)) return;
    if (depth > 0 && --depth == 0) onOver(false);
  }.toJS;
  final drop = (web.DragEvent e) {
    if (!hasFiles(e)) return;
    e.preventDefault();
    e.stopPropagation();
    depth = 0;
    onOver(false);
    final f = e.dataTransfer?.files.item(0);
    if (f == null) return;
    f.arrayBuffer().toDart.then((b) => onFile((f.name, b.toDart.asUint8List())));
  }.toJS;
  web.window.addEventListener('dragenter', enter, true.toJS);
  web.window.addEventListener('dragover', over, true.toJS);
  web.window.addEventListener('dragleave', leave, true.toJS);
  web.window.addEventListener('drop', drop, true.toJS);
  return () {
    web.window.removeEventListener('dragenter', enter, true.toJS);
    web.window.removeEventListener('dragover', over, true.toJS);
    web.window.removeEventListener('dragleave', leave, true.toJS);
    web.window.removeEventListener('drop', drop, true.toJS);
  };
}
