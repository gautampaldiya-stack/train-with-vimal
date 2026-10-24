import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api/config.dart';

class RealtimeEvent {
  RealtimeEvent(this.event, this.payload);
  final String event;
  final Map<String, dynamic> payload;
}

/// WebSocket to /ws/notifications/ while the app is open (decision D-12). Reconnects with back-off.
class Realtime {
  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _ping, _reconnect;
  Future<String?> Function()? _token;
  int _attempt = 0;
  int _gen = 0;
  final unread = ValueNotifier<int>(0);
  final connected = ValueNotifier<bool>(false);
  final _events = StreamController<RealtimeEvent>.broadcast();
  Stream<RealtimeEvent> get events => _events.stream;

  /// Asked to stay connected (it may be between reconnects).
  bool get active => _token != null;

  /// [token] gives a fresh access token on every (re)connect: access tokens last 15 minutes, so reusing the first
  /// one made every reconnect after that (a deploy, `restart web`, wifi, a sleeping laptop) fail for good.
  void connect(Future<String?> Function() token) {
    _token = token;
    _attempt = 0;
    _open();
  }

  Future<void> _open() async {
    final get = _token;
    if (get == null) return;
    _close();
    final gen = ++_gen;
    final token = await get().catchError((_) => null);
    if (gen != _gen || _token == null) return; // disconnected or reopened meanwhile
    if (token == null) return _schedule();
    try {
      _ch = WebSocketChannel.connect(Uri.parse('${AppConfig.wsUrl}?token=$token'));
      _sub = _ch!.stream.listen(_onData, onDone: _schedule, onError: (_) => _schedule());
      // A refused handshake also fails `ready`; the stream's onError already reconnects.
      _ch!.ready.catchError((_) {});
      _ping = Timer.periodic(const Duration(seconds: 25), (_) => _ch?.sink.add(jsonEncode({'action': 'ping'})));
    } catch (_) {
      _schedule();
    }
  }

  void _onData(dynamic raw) {
    _attempt = 0;
    connected.value = true;
    final m = jsonDecode(raw as String) as Map<String, dynamic>;
    final ev = '${m['event']}';
    final payload = (m['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (ev == 'unread') unread.value = (payload['count'] as num?)?.toInt() ?? 0;
    if (ev == 'notification') unread.value = unread.value + 1;
    if (ev != 'pong') _events.add(RealtimeEvent(ev, payload));
  }

  void _schedule() {
    connected.value = false;
    _ping?.cancel();
    if (_token == null) return;
    _reconnect?.cancel();
    final secs = [2, 4, 8, 16, 30][_attempt.clamp(0, 4)];
    _attempt++;
    _reconnect = Timer(Duration(seconds: secs), _open);
  }

  void _close() {
    _ping?.cancel();
    _sub?.cancel();
    _ch?.sink.close();
    _ch = null;
  }

  void disconnect() {
    _token = null;
    _gen++;
    _reconnect?.cancel();
    _close();
    connected.value = false;
  }
}
