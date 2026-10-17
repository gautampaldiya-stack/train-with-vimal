import 'dart:convert';

import '../../../core/util/save_file.dart';
import 'cp_forms_print_io.dart' if (dart.library.js_interop) 'cp_forms_print_web.dart' as impl;

/// Forms tab → Print: the form's answers as a plain page. Web opens the browser's print dialog; the apps save an
/// HTML file (Downloads) that prints from any browser. Returns where it went (null = the print dialog).
Future<String?> printForm({required String title, required String cap, required List<(String, List<(String, String)>)> sections}) async {
  String e(String s) => const HtmlEscape().convert(s);
  final b = StringBuffer()
    ..write('<!doctype html><html><head><meta charset="utf-8"><title>${e(title)}</title><style>')
    ..write('body{font:14px/1.45 system-ui,sans-serif;color:#171717;margin:32px;}h1{font-size:20px;margin:0 0 4px}')
    ..write('.cap{color:#6b6b70;font-size:12px;margin-bottom:18px}h2{font-size:11px;letter-spacing:.08em;text-transform:uppercase;')
    ..write('color:#6b6b70;margin:18px 0 4px}table{width:100%;border-collapse:collapse}td{padding:7px 0;border-bottom:1px solid #e6e6e1;')
    ..write('vertical-align:top}td.q{color:#6b6b70;width:45%;padding-right:16px}td.a{font-weight:700}</style></head><body>')
    ..write('<h1>${e(title)}</h1><div class="cap">${e(cap)}</div>');
  for (final (t, rows) in sections) {
    b.write('<h2>${e(t)}</h2><table>');
    for (final (q, a) in rows) {
      b.write('<tr><td class="q">${e(q)}</td><td class="a">${e(a)}</td></tr>');
    }
    b.write('</table>');
  }
  b.write('<script>window.onload=function(){window.print()}</script></body></html>');
  final html = b.toString();
  if (await impl.openPrint(html)) return null;
  final name = '${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}.html';
  return saveFile(name, utf8.encode(html), mime: 'text/html');
}
