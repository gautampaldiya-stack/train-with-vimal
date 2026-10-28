import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Browser: firebase-messaging-sw.js tells an open tab which page a tapped notification is about (D-80).
void listenSwRoutes(void Function(String route) open) {
  web.window.navigator.serviceWorker.addEventListener(
    'message',
    ((web.MessageEvent e) {
      final d = e.data.dartify();
      final route = d is Map ? d['twvRoute'] : null;
      if (route is String && route.startsWith('/')) open(route);
    }).toJS,
  );
}
