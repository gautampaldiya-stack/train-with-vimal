import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';

DateTime? _d(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
double? _n(dynamic v) => v == null ? null : (v as num).toDouble();
Map<String, dynamic> _m(dynamic v) => (v as Map?)?.cast<String, dynamic>() ?? const {};

/// "22:00:00" ↔ minutes after midnight.
int hmsToMin(String hms) {
  final p = hms.split(':');
  return (int.tryParse(p[0]) ?? 0) * 60 + (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
}

String minToHms(int m) => '${(m ~/ 60 % 24).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}:00';
String minClock(int m) => DateFormat('h:mm a').format(DateTime(2000, 1, 1, m ~/ 60 % 24, m % 60)).toLowerCase();

/// Weight / length / water in the client's units (More → Units & preferences).
String moKg(double kg, String unit, {bool sign = false}) {
  final v = unit == 'lb' ? kg * 2.20462 : kg;
  final s = '${v.abs().toStringAsFixed(1)} $unit';
  return sign ? '${v < 0 ? '+' : '−'}$s' : s;
}

String moHeight(double? cm, String unit) {
  if (cm == null) return '—';
  if (unit == 'cm') return '${cm.toStringAsFixed(cm % 1 == 0 ? 0 : 1)} cm';
  final inches = (cm / 2.54).round();
  return '${inches ~/ 12} ft ${inches % 12} in';
}

String moWater(int ml, String unit) {
  if (unit == 'oz') return '${(ml / 29.5735).round()} fl oz a day';
  final l = ml / 1000;
  return '${l.toStringAsFixed(l % 1 == 0 ? 0 : 1)} L a day';
}

/// The More page in one answer (`GET me/account/`).
class MoData {
  MoData(this.j)
      : profile = _m(j['profile']),
        coach = (j['coach'] as Map?)?.cast<String, dynamic>(),
        session = (j['next_session'] as Map?)?.cast<String, dynamic>(),
        checkin = _m(j['checkin']),
        program = (j['program'] as Map?)?.cast<String, dynamic>(),
        meal = (j['meal_plan'] as Map?)?.cast<String, dynamic>(),
        goal = (j['goal'] as Map?)?.cast<String, dynamic>(),
        stats = _m(j['stats']),
        habits = [for (final h in (_m(j['habits'])['habits'] as List? ?? const [])) '$h'],
        supps = [for (final h in (_m(j['habits'])['supplements'] as List? ?? const [])) '$h'],
        unread = (j['unread'] as num?)?.toInt() ?? 0,
        reminders = Map.of(_m(j['reminders'])),
        deletionOn = _d(j['deletion_on']),
        gym = _m(j['gym']),
        version = '${j['version'] ?? '1.0.0'}';
  final Map<String, dynamic> j, profile, checkin, stats, gym, reminders;
  final Map<String, dynamic>? coach, session, program, meal, goal;
  final List<String> habits, supps;
  int unread;
  DateTime? deletionOn;
  final String version;

  String get name => '${profile['name'] ?? ''}';
  String get initials => '${profile['initials'] ?? ''}';
  String get email => '${profile['email'] ?? ''}';
  String get pendingEmail => '${profile['pending_email'] ?? ''}';
  String get phone => '${profile['phone'] ?? ''}';
  String get city => '${profile['city'] ?? ''}';
  DateTime? get dob => _d(profile['date_of_birth']);
  int? get age => (profile['age'] as num?)?.toInt();
  double? get heightCm => _n(profile['height_cm']);
  DateTime get since => _d(profile['since']) ?? DateTime.now();
  String get coachFirst => '${coach?['first_name'] ?? 'your coach'}';
  String get coachName => '${coach?['name'] ?? 'Your coach'}';
  DateTime get nextCheckin => _d(checkin['next']) ?? DateTime.now();
  int get checkinWeek => (checkin['week'] as num?)?.toInt() ?? 1;
  bool get checkinDue => checkin['due_this_week'] == true;
  String get checkinTime => '${checkin['time'] ?? '18:00:00'}';
}

class MoNotice {
  MoNotice(Map<String, dynamic> j)
      : id = '${j['id']}',
        title = '${j['title']}',
        body = '${j['body'] ?? ''}',
        event = '${j['event'] ?? ''}',
        route = '${_m(j['data'])['route'] ?? ''}',
        at = _d(j['created_at']) ?? DateTime.now(),
        read = j['read_at'] != null;
  final String id, title, body, event, route;
  final DateTime at;
  bool read;
}

class MoAct {
  MoAct(Map<String, dynamic> j)
      : kind = '${j['k']}',
        icon = '${j['icon']}',
        color = '${j['color']}',
        title = '${j['title']}',
        sub = '${j['sub'] ?? ''}',
        time = '${j['time'] ?? ''}',
        date = _d(j['date']) ?? DateTime.now(),
        link = j['link'] as String?,
        label = j['label'] as String?,
        rows = [for (final r in (j['rows'] as List? ?? const [])) ('${(r as List)[0]}', '${r[1]}')];
  final String kind, icon, color, title, sub, time;
  final DateTime date;
  final String? link, label;
  final List<(String, String)> rows;
}

/// Reminder keys on the board, in its order: (api key, icon key, tone, title, sub).
const moReminderKeys = [
  ('workout', 'dumb', 'blue', 'Workout reminders', '1 hour before your session or planned workout'),
  ('meal', 'food', 'green', 'Meal reminders', 'At each meal time in your plan'),
  ('water', 'water', 'blue', 'Water reminders', 'Every 2 hours when you are behind'),
  ('supps', 'pill', 'purple', 'Supplement reminders', 'At the time of day each one is due'),
  ('habit', 'steps', 'green', 'Habit reminders', 'Steps and sleep nudges in the evening'),
  ('checkin', 'form', 'amber', 'Check-in reminders', 'Sunday 6:00 pm, again on Monday if not sent'),
  ('trainer_reply', 'user', 'gray', 'Coach updates', '{coach} replies or changes your plan'),
  ('progress', 'star', 'amber', 'Progress and personal bests', 'New bests, streaks and milestones'),
];

class MoreController extends ChangeNotifier {
  MoreController() {
    _rt = Services.realtime.events.where((e) => e.event == 'notification' || e.event == 'unread').listen((_) {
      load();
      if (notices != null) loadNotices();
    });
    _results = Services.outbox.results.where((r) => r.error == null && !r.tag.startsWith('more:')).listen((_) {
      if (activity != null) loadActivity(actKind);
    });
  }

  static const _cacheKey = 'me/account';
  late final StreamSubscription _rt, _results;
  MoData? data;
  ApiError? error;
  int _seq = 0;

  // Notifications page
  List<MoNotice>? notices;
  String? _next;
  bool unreadTab = false, loadingMore = false;

  // My activity page
  List<MoAct>? activity;
  String actKind = 'All';
  ApiError? actError;

  @override
  void dispose() {
    _rt.cancel();
    _results.cancel();
    super.dispose();
  }

  Future<void> start() async {
    final c = await Services.cache.read(_cacheKey);
    if (c is Map && data == null) {
      data = MoData(c.cast<String, dynamic>());
      notifyListeners();
    }
    await load();
  }

  Future<void> load() async {
    final n = ++_seq;
    try {
      final j = await Services.api.get<Map<String, dynamic>>('me/account/');
      if (n != _seq) return;
      unawaited(Services.cache.write(_cacheKey, j));
      data = MoData(j);
      error = null;
    } on ApiError catch (e) {
      if (n != _seq) return;
      error = e;
    }
    notifyListeners();
  }

  // ─────────────────────────────── Notifications

  Future<void> loadNotices({bool more = false}) async {
    if (more && (_next == null || loadingMore)) return;
    loadingMore = more;
    try {
      final j = more
          ? await Services.api.get<Map<String, dynamic>>(_next!.substring(_next!.indexOf('notifications/')))
          : await Services.api.get<Map<String, dynamic>>('notifications/', query: {'page_size': 30, if (unreadTab) 'unread': 1});
      final rows = [for (final r in (j['results'] as List)) MoNotice((r as Map).cast<String, dynamic>())];
      notices = more ? [...?notices, ...rows] : rows;
      _next = j['next'] as String?;
    } on ApiError catch (e) {
      error = e;
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  bool get hasMoreNotices => _next != null;

  void pickNoticeTab(bool unread) {
    if (unreadTab == unread) return;
    unreadTab = unread;
    notices = null;
    notifyListeners();
    loadNotices();
  }

  void _setUnread(int n) {
    final d = data;
    if (d != null) d.unread = n < 0 ? 0 : n;
  }

  Future<void> markRead(MoNotice n) async {
    if (n.read) return;
    n.read = true;
    _setUnread((data?.unread ?? 1) - 1);
    notifyListeners();
    await Services.api.post('notifications/${n.id}/read/').catchError((_) => null);
  }

  Future<void> markUnread(MoNotice n) async {
    n.read = false;
    _setUnread((data?.unread ?? 0) + 1);
    notifyListeners();
    await Services.api.post('notifications/${n.id}/unread_one/').catchError((_) => null);
  }

  /// Mark all read; returns the ids that were unread so Undo can put them back.
  Future<List<MoNotice>> readAll() async {
    final was = [for (final n in notices ?? <MoNotice>[]) if (!n.read) n];
    for (final n in was) {
      n.read = true;
    }
    _setUnread(0);
    if (unreadTab) notices = [];
    notifyListeners();
    await Services.api.post('notifications/read_all/').catchError((_) => null);
    return was;
  }

  Future<void> undoReadAll(List<MoNotice> was) async {
    for (final n in was) {
      await markUnread(n);
    }
    if (unreadTab) await loadNotices();
  }

  /// Delete waits for the toast: Undo puts the row back, otherwise it is deleted on the server.
  void removeNotice(MoNotice n) {
    notices?.remove(n);
    if (!n.read) _setUnread((data?.unread ?? 1) - 1);
    notifyListeners();
  }

  void restoreNotice(MoNotice n) {
    notices = [...?notices, n]..sort((a, b) => b.at.compareTo(a.at));
    if (!n.read) _setUnread((data?.unread ?? 0) + 1);
    notifyListeners();
  }

  Future<void> deleteNotice(MoNotice n) => Services.api.delete('notifications/${n.id}/').catchError((_) => null);

  // ─────────────────────────────── My activity

  Future<void> loadActivity(String kind) async {
    if (kind != actKind) {
      actKind = kind;
      activity = null;
      notifyListeners();
    }
    try {
      final j = await Services.api.get<Map<String, dynamic>>('me/activity/', query: {'kind': kind});
      if (kind != actKind) return;
      activity = [
        for (final d in (j['days'] as List))
          for (final a in ((d as Map)['items'] as List)) MoAct((a as Map).cast<String, dynamic>()),
      ];
      actError = null;
    } on ApiError catch (e) {
      actError = e;
    }
    notifyListeners();
  }

  // ─────────────────────────────── Settings (saved as they change, through the outbox)

  Future<void> setReminders(Map<String, dynamic> changes) async {
    data?.reminders.addAll(changes);
    notifyListeners();
    await Services.outbox.enqueue('PATCH', 'me/reminders/', changes, tag: 'more:reminders');
  }

  Future<void> resetReminders() async {
    data?.reminders.addAll(const {
      'workout': true, 'meal': true, 'water': true, 'supps': true, 'habit': false, 'checkin': true,
      'trainer_reply': true, 'progress': true, 'quiet_on': true, 'quiet_from': '22:00:00', 'quiet_to': '07:00:00',
    });
    notifyListeners();
    await Services.outbox.enqueue('POST', 'me/reminders/', {}, tag: 'more:reminders');
  }

  /// Units, theme, week start, privacy switches.
  Future<void> setPrefs(Map<String, dynamic> changes) async {
    Services.session.patchMe(changes);
    notifyListeners();
    await Services.outbox.enqueue('PATCH', 'auth/me/', changes, tag: 'more:prefs');
  }

  /// Edit profile: online, so a taken email or mobile shows on its field.
  Future<void> saveProfile(Map<String, dynamic> changes) async {
    final j = await Services.api.patch<Map<String, dynamic>>('auth/me/', changes);
    Services.session.patchMe(j);
    await load();
  }

  Future<void> resendEmail() => Services.api.post('auth/email/resend/');

  Future<void> cancelEmail() async {
    await Services.api.post('auth/email/cancel-change/');
    await load();
  }

  Future<void> requestDelete() async {
    await Services.api.post('auth/account/delete/');
    await load();
  }

  Future<void> cancelDelete() async {
    await Services.api.delete('auth/account/delete/');
    data?.deletionOn = null;
    notifyListeners();
    unawaited(load());
  }

  Future<String> exportData() async {
    final j = await Services.api.post<Map<String, dynamic>>('me/data-export/');
    return '${j['email']}';
  }

  Future<void> report(String category, String text, {String? screenshot, String page = ''}) =>
      Services.api.post('me/report/', {
        'category': category, 'text': text, 'page': page, 'app_version': data?.version ?? '',
        'screenshot': ?screenshot,
      });
}
