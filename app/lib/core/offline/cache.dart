import 'package:sembast/sembast.dart';

import 'local_db.dart';

/// Last good answer for each GET, so screens open offline (stale-while-revalidate).
class ReadCache {
  final _store = stringMapStoreFactory.store('cache');

  Future<dynamic> read(String key) async {
    final r = await _store.record(key).get(await LocalDb.open());
    return r?['v'];
  }

  Future<void> write(String key, dynamic value) async =>
      _store.record(key).put(await LocalDb.open(), {'v': value, 't': DateTime.now().toIso8601String()});

  Future<void> clear() async => _store.delete(await LocalDb.open());
}
