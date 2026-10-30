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

  /// Queued writes whose caller is still waiting for the answer (see [enqueue]).
  final _waiting = <int>{};
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
    _waiting.add(id);
    await _count();
    final completer = Completer<dynamic>();
    late StreamSubscription s;
    s = results.where((r) => r.id == id).listen((r) {
      s.cancel();
      if (!completer.isCompleted) completer.complete(r.error == null ? r.data : Future.error(r.error!));
    });
    await flush();
    _waiting.remove(id);
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
          online.value = true; // the server answered, so we are back
          _done.add(OutboxResult(rec.key, '${v['tag']}', res, null, late: !_waiting.contains(rec.key)));
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
          _done.add(OutboxResult(rec.key, '${v['tag']}', null, e, late: !_waiting.contains(rec.key)));
        }
      }
    } finally {
      _flushing = false;
      await _count();
    }
  }

  Future<void> _count() async => pending.value = await _store.count(await LocalDb.open());

  /// Writes still waiting to go whose tag starts with [prefix] (a screen keeps what it showed until they are sent).
  Future<bool> hasPending(String prefix) async {
    final rows = await _store.find(await LocalDb.open());
    return rows.any((r) => '${r.value['tag']}'.startsWith(prefix));
  }

  Future<void> clear() async {
    await _store.delete(await LocalDb.open());
    await _count();
  }
}

class OutboxResult {
  OutboxResult(this.id, this.tag, this.data, this.error, {this.late = false});
  final int id;

  /// Sent after the screen that queued it had moved on (saved offline, or left from an earlier run): nobody is
  /// waiting for this answer, so a refusal has to be shown by whoever listens.
  final bool late;
  final String tag;
  final dynamic data;
  final ApiError? error;
}
