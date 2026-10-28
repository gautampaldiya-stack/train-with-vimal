// Makes web/firebase-config.js from firebase.json (both not in git) so the web push
// service worker (web/firebase-messaging-sw.js) knows the Firebase project. D-56.
// Run from app/:  dart run tool/firebase_web.dart
import 'dart:convert';
import 'dart:io';

void main() {
  final src = File('firebase.json');
  final c = src.existsSync() ? (jsonDecode(src.readAsStringSync()) as Map).cast<String, dynamic>() : <String, dynamic>{};
  String v(String k) => '${c[k] ?? ''}'.trim();
  final out = File('web/firebase-config.js');
  if (c.containsKey('flutter') && !c.containsKey('FB_PROJECT_ID')) {
    // `flutterfire configure` wrote its own firebase.json over the key file: push is off in every build (D-80).
    stderr.writeln('firebase.json was made by flutterfire, not the D-56 key file: push stays OFF.\n'
        'Copy firebase.example.json to firebase.json and fill in the FB_* keys (Firebase console → Project settings).');
  }
  if (v('FB_PROJECT_ID').isEmpty || v('FB_WEB_APP_ID').isEmpty) {
    if (out.existsSync()) out.deleteSync();
    stdout.writeln('firebase.json has no web keys: web push stays off.');
    return;
  }
  final cfg = {
    'apiKey': v('FB_WEB_API_KEY'),
    'authDomain': v('FB_AUTH_DOMAIN'),
    'projectId': v('FB_PROJECT_ID'),
    'storageBucket': v('FB_STORAGE_BUCKET'),
    'messagingSenderId': v('FB_SENDER_ID'),
    'appId': v('FB_WEB_APP_ID'),
  };
  out.writeAsStringSync('// Made by tool/firebase_web.dart from firebase.json. Not in git.\nself.TWV_FIREBASE = ${jsonEncode(cfg)};\n');
  stdout.writeln('Wrote web/firebase-config.js');
}
