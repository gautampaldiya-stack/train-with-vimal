import 'dart:js_interop';

import 'package:web/web.dart' as web;

JSFunction? _handler;

/// Web: while [on], closing or reloading the tab asks "Leave site? Changes you made may not be saved."
void warnOnTabClose(bool on) {
  if (on && _handler == null) {
    _handler = (web.BeforeUnloadEvent e) {
      e.preventDefault();
      e.returnValue = '';
    }.toJS;
    web.window.addEventListener('beforeunload', _handler);
  } else if (!on && _handler != null) {
    web.window.removeEventListener('beforeunload', _handler);
    _handler = null;
  }
}
