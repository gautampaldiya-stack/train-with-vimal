import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../core/api/api_error.dart';
import '../core/api/token_store.dart';
import '../core/offline/cache.dart';
import '../core/offline/outbox.dart';
import '../core/push/push.dart';
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
  String get pendingEmail => '${json['pending_email'] ?? ''}';

  /// More → Units & preferences, Privacy & data.
  String get unitWeight => '${json['unit_weight'] ?? 'kg'}';
  String get unitLength => '${json['unit_length'] ?? 'cm'}';
  String get unitWater => '${json['unit_water'] ?? 'l'}';
  String get weekStart => '${json['week_start'] ?? 'mon'}';
  String get theme => '${json['theme'] ?? 'light'}';
  bool get sharePhotos => json['share_photos'] != false;
  bool get usageData => json['usage_data'] == true;

  /// A client who signed up from an invite confirms the email first (board `ClientVerifyEmail`).
  bool get needsVerify => role == Role.client && (email ?? '').isNotEmpty && !emailVerified;
  Role get role => switch (json['role']) { 'admin' => Role.admin, 'trainer' => Role.trainer, _ => Role.client };
  bool get isStaff => role != Role.client;

  /// Staff access: the admin can do everything; a trainer only what their access includes (`permissions`).
  bool can(String key) => role == Role.admin || (json['permissions'] as Map?)?[key] == true;
  String get status => '${json['status'] ?? 'active'}';

  /// Client signed up from an invite link and waits in Approvals.
  bool get pending => status == 'pending';
  Map<String, dynamic> get _client => (json['client'] as Map?)?.cast<String, dynamic>() ?? const {};
  List<String> get setupDone => [for (final s in (_client['setup_done'] as List? ?? const [])) '$s'];
  int get setupTotal => (_client['setup_total'] as num?)?.toInt() ?? 9;
  bool get setupComplete => setupDone.length >= setupTotal;

  /// Chose "Finish setup later" once, so log in goes to Home instead of the setup steps.
  bool get setupLater => _client['setup_later'] == true;
  Map<String, dynamic>? get coach => (_client['coach'] as Map?)?.cast<String, dynamic>();

  /// "Aman" — the coach's first name, or "Your coach" when none is set yet.
  String get coachFirst => coach?['first_name'] as String? ?? 'Your coach';
  String get coachFull => coach?['full_name'] as String? ?? 'your coach';
  bool get hasCoach => coach != null;
}

/// App-wide singletons. Created once in main() before runApp.
class Services {
  Services._();
  static final tokens = TokenStore();
  static final api = Api(tokens);
  static final outbox = Outbox(api);
  static final cache = ReadCache();
  static final realtime = Realtime();
  static final push = Push(api);
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

  /// The API knows android / ios / web. Desktop builds count as web.
  static String get platform => kIsWeb
      ? 'web'
      : switch (defaultTargetPlatform) { TargetPlatform.android => 'android', TargetPlatform.iOS => 'ios', _ => 'web' };

  Future<void> signIn(String identifier, String password, {bool keep = true}) async {
    Services.tokens.remember = keep;
    final r = await Services.api.post<Map<String, dynamic>>(
      'auth/login/',
      {'identifier': identifier.trim(), 'password': password, 'platform': platform, 'device_name': kIsWeb ? 'Web browser' : defaultTargetPlatform.name},
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

  /// Settings changed in the app (units, privacy) show at once; the server copy follows through the outbox.
  void patchMe(Map<String, dynamic> changes) {
    final m = me;
    if (m == null) return;
    me = Me({...m.json, ...changes});
    Services.cache.write('me', me!.json);
    notifyListeners();
  }

  Future<void> refreshMe() async {
    me = Me(await Services.api.get<Map<String, dynamic>>('auth/me/'));
    await Services.cache.write('me', me!.json);
    _syncRealtime();
    notifyListeners();
  }

  StreamSubscription<RealtimeEvent>? _accessSub;

  void _afterSignIn() {
    Services.outbox.start();
    _syncRealtime();
    // Vimal changed this trainer's access: menus and buttons follow at once, no reload.
    _accessSub ??= Services.realtime.events.listen((e) {
      if (e.event == 'notification' && const ['access_changed', 'access_request_decided'].contains(e.payload['event']) && signedIn) {
        refreshMe().catchError((_) {});
      }
    });
  }

  String? _pushFor; // the account this device's push token was saved for

  /// Realtime is only for people who may use the app: the server refuses the socket while an
  /// account waits for approval, so connect once it is approved (checked on every refresh).
  void _syncRealtime() {
    final token = Services.tokens.access;
    // Phone / browser push when the app is closed (D-56), once per logged-in account. Also while the account waits
    // for approval (D-80): "You are approved" comes as a push, and the server takes the device from such accounts.
    if (token != null && me != null && _pushFor != me!.id) {
      _pushFor = me!.id;
      Services.push.start(platform);
    }
    if (token != null && me != null && !me!.pending) {
      if (!Services.realtime.active) Services.realtime.connect(Services.api.freshAccess);
    } else {
      Services.realtime.disconnect();
    }
  }

  Future<void> signOut({bool remote = true}) async {
    _pushFor = null;
    if (remote) {
      await Services.push.stop();
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
