import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../core/api/api_error.dart';
import '../core/api/token_store.dart';
import '../core/offline/cache.dart';
import '../core/offline/outbox.dart';
import '../core/realtime/realtime.dart';

enum Role { admin, trainer, client }

/// The signed-in person (from /auth/me/).
class Me {
  Me(this.json);
  final Map<String, dynamic> json;
  String get id => '${json['id']}';
  String get name => '${json['full_name'] ?? ''}';
  String get firstName => '${json['first_name'] ?? name.split(' ').first}';
  String get initials => '${json['initials'] ?? ''}';
  String? get email => json['email'] as String?;
  String? get phone => json['phone'] as String?;
  String? get avatar => json['avatar'] as String?;
  bool get emailVerified => json['email_verified'] == true;
  Role get role => switch (json['role']) { 'admin' => Role.admin, 'trainer' => Role.trainer, _ => Role.client };
  bool get isStaff => role != Role.client;
}

/// App-wide singletons. Created once in main() before runApp.
class Services {
  Services._();
  static final tokens = TokenStore();
  static final api = Api(tokens);
  static final outbox = Outbox(api);
  static final cache = ReadCache();
  static final realtime = Realtime();
  static final session = Session();
}

class Session extends ChangeNotifier {
  Me? me;
  bool ready = false;

  bool get signedIn => me != null;

  Future<void> restore() async {
    await Services.tokens.load();
    Services.api.onSignedOut = () => signOut(remote: false);
    if (Services.tokens.access != null) {
      try {
        me = Me(await Services.api.get<Map<String, dynamic>>('auth/me/'));
        await Services.cache.write('me', me!.json);
      } on ApiError catch (e) {
        if (e.offline) {
          final cached = await Services.cache.read('me');
          if (cached is Map) me = Me(cached.cast<String, dynamic>());
        } else {
          await Services.tokens.clear();
        }
      }
    }
    if (me != null) _afterSignIn();
    ready = true;
    notifyListeners();
  }

  Future<void> signIn(String identifier, String password) async {
    final r = await Services.api.post<Map<String, dynamic>>(
      'auth/login/',
      {'identifier': identifier.trim(), 'password': password, 'platform': defaultTargetPlatform.name, 'device_name': kIsWeb ? 'Web browser' : defaultTargetPlatform.name},
      null,
      false,
    );
    await Services.tokens.save(r['access'], r['refresh']);
    me = Me((r['user'] as Map).cast<String, dynamic>());
    await Services.cache.write('me', me!.json);
    _afterSignIn();
    notifyListeners();
  }

  /// After a password reset or login link the server hands back tokens directly.
  Future<void> adoptTokens(Map<String, dynamic> r) async {
    await Services.tokens.save(r['access'], r['refresh']);
    me = Me(r['user'] is Map ? (r['user'] as Map).cast<String, dynamic>() : await Services.api.get<Map<String, dynamic>>('auth/me/'));
    _afterSignIn();
    notifyListeners();
  }

  Future<void> refreshMe() async {
    me = Me(await Services.api.get<Map<String, dynamic>>('auth/me/'));
    notifyListeners();
  }

  void _afterSignIn() {
    Services.outbox.start();
    if (Services.tokens.access != null) Services.realtime.connect(Services.tokens.access!);
  }

  Future<void> signOut({bool remote = true}) async {
    if (remote) {
      try {
        await Services.api.post('auth/logout/', {'refresh': Services.tokens.refresh});
      } catch (_) {}
    }
    Services.realtime.disconnect();
    await Services.tokens.clear();
    await Services.cache.clear();
    await Services.outbox.clear();
    me = null;
    notifyListeners();
  }
}
