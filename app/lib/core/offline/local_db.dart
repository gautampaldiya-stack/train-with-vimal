import 'package:sembast/sembast.dart';

import 'local_db_io.dart' if (dart.library.js_interop) 'local_db_web.dart' as impl;

/// One local database (IndexedDB on web, a file on phones) for the outbox and the read cache.
class LocalDb {
  static Database? _db;
  static Future<Database> open() async => _db ??= await impl.openDb();
}
