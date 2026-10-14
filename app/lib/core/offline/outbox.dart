import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import 'local_db.dart';

/// Offline-first writes (decision D-07). Every client log goes in here first with its own
/// Idempotency-Key and the local time, then is sent in order. If the network is down it waits
/// and retries; the server replays the first answer for a repeated key, so nothing is doubled.
class Outbox {
  Outbox(this.api);
  final Api api;
  final _store = intMapStoreFactory.store('outbox');
  final pending = ValueNotifier<int>(0);
  final online = ValueNotifier<bool>(true);
  StreamSubscription? _sub;
  bool _flushing = false;
  Timer? _retry;

  /// Listeners get each answer the server sends for a queued item (for screens to refresh).
  final _done = StreamController<OutboxResult>.broadcast();
  Stream<OutboxResult> get results => _done.stream;

  Future<void> start() async {
    await _count();
    _sub = Connectivity().onConnectivityChanged.listen((r) {
      online.value = !r.contains(ConnectivityResult.none);
      if (online.value) flush();
    });
    flush();
  }

  void dispose() {
    _sub?.cancel();
    _retry?.cancel();
  }

  /// Queues a write and tries to send it now. Returns the server answer if it went through,
  /// or null if it is saved for later.
  Future<dynamic> enqueue(String method, String path, Map<String, dynamic> data, {String? tag}) async {
    final db = await LocalDb.open();
    final body = {...data, 'logged_at': data['logged_at'] ?? DateTime.now().toIso8601String()};
    final item = {
      'key': const Uuid().v4(),
      'method': method,
      'path': path,
      'data': body,
      'tag': tag ?? path,
      'created': DateTime.now().toIso8601String(),
      'tries': 0,
    };
    final id = await _store.add(db, item);
    await _count();
    final completer = Completer<dynamic>();
    late StreamSubscription s;
    s = results.where((r) => r.id == id).listen((r) {
      s.cancel();
      if (!completer.isCompleted) completer.complete(r.error == null ? r.data : Future.error(r.error!));
    });
    await flush();
    if (!completer.isCompleted) {
      s.cancel();
      return null; // saved offline, will sync later
    }
    return completer.future;
  }

  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final db = await LocalDb.open();
      while (true) {
        final rec = await _store.findFirst(db, finder: Finder(sortOrders: [SortOrder(Field.key)]));
        if (rec == null) break;
        final v = rec.value;
        try {
          final res = await api.send('${v['method']}', '${v['path']}', v['data'], '${v['key']}');
          await _store.record(rec.key).delete(db);
          _done.add(OutboxResult(rec.key, '${v['tag']}', res, null));
        } on ApiError catch (e) {
          if (e.offline || (e.status ?? 0) >= 500 || e.status == 401) {
            online.value = !e.offline ? online.value : false;
            await _store.record(rec.key).update(db, {'tries': ((v['tries'] as int?) ?? 0) + 1});
            _retry?.cancel();
            _retry = Timer(const Duration(seconds: 20), flush);
            break;
          }
          // The server said no (validation, 404, 409): drop it so the queue keeps moving, tell the screen.
          await _store.record(rec.key).delete(db);
          _done.add(OutboxResult(rec.key, '${v['tag']}', null, e));
        }
      }
    } finally {
      _flushing = false;
      await _count();
    }
  }

  Future<void> _count() async => pending.value = await _store.count(await LocalDb.open());

  Future<void> clear() async {
    await _store.delete(await LocalDb.open());
    await _count();
  }
}

class OutboxResult {
  OutboxResult(this.id, this.tag, this.data, this.error);
  final int id;
  final String tag;
  final dynamic data;
  final ApiError? error;
}
