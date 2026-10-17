import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Opens the page in a new tab, which prints itself on load.
Future<bool> openPrint(String html) async {
  final blob = web.Blob([html.toJS].toJS, web.BlobPropertyBag(type: 'text/html'));
  final url = web.URL.createObjectURL(blob);
  return web.window.open(url, '_blank') != null;
}
