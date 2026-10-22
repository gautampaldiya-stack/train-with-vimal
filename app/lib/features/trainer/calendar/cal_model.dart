import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/theme/theme.dart';

// Trainer Calendar (boards `TrainerCalendar` + `TrainerCalendarMobile`): the week's own sessions, stats, working
// hours and the clients given to the trainer. Every write goes to `sessions/` and the page reloads the week.
// Admin Calendar (boards `Calendar` + `CalendarMobile`, D-48): the same page for the whole team, with the
// "All trainers" pick, the trainer on each block and per-trainer Availability.

const calMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const calWd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const calWdLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// The grid runs 6 am – 10 pm, 60 px an hour.
const calH0 = 6, calH1 = 22;
const calHourPx = 60.0;

/// Session kinds as the boards name and colour them (`k-ss`, `k-qc`, `k-rv`).
enum CalKind {
  session('one_on_one', '1:1 session', 60, AppColors.kSsBg, AppColors.kSsText, AppColors.kSsDot),
  call('quick_call', 'Quick call', 15, AppColors.kQcBg, AppColors.kQcText, AppColors.kQcDot),
  review('program_review', 'Program review', 30, AppColors.kRvBg, AppColors.kRvText, AppColors.kRvDot);

  const CalKind(this.api, this.label, this.minutes, this.bg, this.fg, this.dot);
  final String api, label;
  final int minutes;
  final Color bg, fg, dot;

  /// Quick calls and reviews are on a call unless the trainer picks In person.
  bool get onCall => this != CalKind.session;
  static CalKind of(String api) => values.firstWhere((k) => k.api == api, orElse: () => CalKind.session);
}

/// "7 am", "7:30 am".
String calFmt(int m) {
  final h = (m ~/ 60) % 24, mm = m % 60, h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12${mm != 0 ? ':${mm.toString().padLeft(2, '0')}' : ''} ${h < 12 ? 'am' : 'pm'}';
}

/// "7:00 am" (block lines).
String calFmtL(int m) {
  final h = (m ~/ 60) % 24, h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${(m % 60).toString().padLeft(2, '0')} ${h < 12 ? 'am' : 'pm'}';
}

/// "7 – 8 am", "11:30 am – 12:30 pm".
String calRange(int m, int len) {
  final a = calFmt(m), b = calFmt(m + len);
  return '${a.substring(a.length - 2) == b.substring(b.length - 2) ? a.substring(0, a.length - 3) : a} – $b';
}

/// "7:00 – 8:00 am" (block tooltip).
String calRangeL(int m, int len) {
  final a = calFmtL(m), b = calFmtL(m + len);
  return '${a.substring(a.length - 2) == b.substring(b.length - 2) ? a.substring(0, a.length - 3) : a} – $b';
}

DateTime calDay(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime calMonday(DateTime d) => calDay(d).subtract(Duration(days: d.weekday - 1));
int calMinutes(DateTime d) => d.hour * 60 + d.minute;

/// "Monday, 5 Oct".
String calDayLabel(DateTime d) => '${calWdLong[d.weekday - 1]}, ${d.day} ${calMonths[d.month - 1]}';

/// "5 – 11 Oct 2026", "28 Sep – 4 Oct 2026", "29 Dec 2026 – 4 Jan 2027".
String calWeekRange(DateTime mon) {
  final sun = mon.add(const Duration(days: 6));
  if (mon.year != sun.year) return '${mon.day} ${calMonths[mon.month - 1]} ${mon.year} – ${sun.day} ${calMonths[sun.month - 1]} ${sun.year}';
  if (mon.month == sun.month) return '${mon.day} – ${sun.day} ${calMonths[sun.month - 1]} ${sun.year}';
  return '${mon.day} ${calMonths[mon.month - 1]} – ${sun.day} ${calMonths[sun.month - 1]} ${sun.year}';
}

class CalSession {
  CalSession(Map j)
      : id = '${j['id']}',
        kind = CalKind.of('${j['kind']}'),
        clientId = '${(j['client_detail'] as Map?)?['id'] ?? j['client']}',
        client = '${(j['client_detail'] as Map?)?['full_name'] ?? ''}',
        start = DateTime.parse('${j['start']}').toLocal(),
        minutes = (j['length'] as num?)?.toInt() ?? 60,
        isCall = j['is_call'] == true,
        place = '${j['place'] ?? ''}',
        callLink = '${j['call_link'] ?? ''}',
        note = '${j['note'] ?? ''}',
        status = '${j['status'] ?? 'booked'}',
        bookedBy = '${j['booked_by_name'] ?? ''}',
        plan = '${j['client_plan'] ?? ''}',
        trainerId = '${(j['trainer_detail'] as Map?)?['id'] ?? j['trainer'] ?? ''}',
        trainer = '${(j['trainer_detail'] as Map?)?['full_name'] ?? ''}';
  final String id, clientId, client, place, callLink, note, bookedBy, plan, trainerId, trainer;
  final CalKind kind;
  final DateTime start;
  final int minutes;
  final bool isCall;
  String status;

  bool get done => status == 'done';
  int get from => calMinutes(start);
  DateTime get day => calDay(start);

  /// Board `.cal-b` line: "7:00 am · Andheri gym floor" / "On a call".
  String get where => isCall || place.isEmpty ? 'On a call' : place;

  /// "Monday, 5 Oct · 7 – 8 am".
  String get when => '${calDayLabel(start)} · ${calRange(from, minutes)}';

  /// "Sat 10 Oct · 8 – 9 am" (toasts).
  String get shortWhen => '${calWd[start.weekday - 1]} ${start.day} ${calMonths[start.month - 1]} · ${calRange(from, minutes)}';
}

/// One weekday of My working hours: open or a day off, from – to in minutes.
class CalAvDay {
  CalAvDay(this.weekday, this.open, this.from, this.to);
  CalAvDay.fromJson(Map j)
      : weekday = (j['weekday'] as num).toInt(),
        open = j['is_working'] == true,
        from = _min('${j['start']}', 390),
        to = _min('${j['end']}', 1200);
  final int weekday;
  bool open;
  int from, to;

  CalAvDay copy() => CalAvDay(weekday, open, from, to);
  Map<String, Object> toJson() => {'weekday': weekday, 'is_working': open, 'start': _hm(from), 'end': _hm(to)};

  static int _min(String s, int or) {
    final p = s.split(':');
    if (p.length < 2) return or;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  static String _hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// A client given to the trainer (New session → Client), with the goal on the right ("Fat loss").
class CalClient {
  CalClient(Map j)
      : id = '${j['id']}',
        name = '${j['full_name'] ?? j['name'] ?? ''}',
        goal = '${j['goal_label'] ?? ''}',
        trainerId = '${(j['trainer'] as Map?)?['id'] ?? ''}';
  final String id, name, goal, trainerId;
}

/// Live check under the form (`sessions/check/`).
class CalCheck {
  CalCheck(Map j)
      : state = '${j['state']}',
        withName = '${j['with'] ?? ''}',
        clashFrom = j['start'] == null ? null : DateTime.parse('${j['start']}').toLocal(),
        clashTo = j['end'] == null ? null : DateTime.parse('${j['end']}').toLocal(),
        hours = j['hours'] is Map ? (CalAvDay._min('${j['hours']['start']}', 0), CalAvDay._min('${j['hours']['end']}', 0)) : null;
  final String state; // free | clash | outside | day_off
  final String withName;
  final DateTime? clashFrom, clashTo;
  final (int, int)? hours;
}

class CalendarController extends ChangeNotifier {
  CalendarController({required bool phone, this.admin = false}) : view = phone ? 'day' : 'week' {
    final now = DateTime.now();
    week = calMonday(now);
    day = now.weekday - 1;
  }

  /// Monday of the week on screen, the picked day (0 = Mon) and `week` / `day`.
  late DateTime week;
  late int day;
  String view;

  /// Admin: whose sessions show ('' = All trainers) and the active trainers for the picks (id, name).
  final bool admin;
  String trainer = '';
  List<(String, String)> trainers = [];

  /// Sessions this week by trainer (from the All trainers stats), for the counts in the trainer menu.
  Map<String, int> byTrainer = {};
  String _hoursOf = '';

  String get trainerName => trainers.where((t) => t.$1 == trainer).firstOrNull?.$2 ?? '';

  List<CalSession> sessions = [];
  Map stats = {};
  List<CalAvDay> hours = [];
  List<CalClient>? clients;
  bool loading = true;
  ApiError? error;
  int _ticket = 0;
  DateTime? _loaded;

  String get myId => Services.session.me?.id ?? '';

  DateTime dateOf(int i) => week.add(Duration(days: i));
  bool isToday(int i) => calDay(DateTime.now()) == dateOf(i);
  List<CalSession> on(int i) => sessions.where((s) => s.day == dateOf(i)).toList()..sort((a, b) => a.start.compareTo(b.start));

  int get workingDays => hours.where((d) => d.open).length;
  CalAvDay? hoursOn(int i) => i < hours.length ? hours[i] : null;

  /// In-person place for a new session: the trainer's latest place this week, else "Gym floor".
  String get defaultPlace {
    for (final s in sessions.reversed) {
      if (!s.isCall && s.place.isNotEmpty) return s.place;
    }
    return 'Gym floor';
  }

  Future<void> load() async {
    final t = ++_ticket;
    if (_loaded != week) {
      // Another week: drop the old numbers so they never show under the new range.
      sessions = [];
      stats = {};
    }
    loading = true;
    notifyListeners();
    final q = _q;
    // Shading follows one trainer: yours, or the admin's pick (none for All trainers).
    final who = admin ? trainer : myId;
    if (who != _hoursOf) {
      hours = [];
      _hoursOf = who;
    }
    try {
      final res = await Future.wait([
        Services.api.get<List>('sessions/', query: q),
        Services.api.get<Map>('sessions/stats/', query: q),
        if (hours.isEmpty && who.isNotEmpty) Services.api.get<Map>('availability/', query: {if (admin) 'trainer': who}),
        if (admin && trainers.isEmpty) Services.api.get<Map>('trainers/', query: {'tab': 'active', 'page_size': 100}),
      ]);
      if (t != _ticket) return;
      sessions = [for (final s in res[0] as List) CalSession(s as Map)];
      _loaded = week;
      stats = res[1] as Map;
      for (final x in res.skip(2)) {
        final m = x as Map;
        if (m['days'] is List) hours = [for (final d in m['days'] as List) CalAvDay.fromJson(d as Map)];
        if (m['results'] is List) trainers = [for (final t in m['results'] as List) ('${(t as Map)['id']}', '${t['full_name']}')];
      }
      if (admin && trainer.isEmpty) {
        byTrainer = {for (final b in (stats['by_trainer'] as List?) ?? const []) '${(b as Map)['trainer_id']}': (b['n'] as num).toInt()};
      }
      error = null;
    } on ApiError catch (e) {
      if (t != _ticket) return;
      error = e;
    }
    loading = false;
    notifyListeners();
  }

  /// The week, and whose sessions: always yours for a trainer, the pick (or everyone) for the admin.
  Map<String, Object> get _q => {
        'from': _iso(week),
        'to': _iso(week.add(const Duration(days: 6))),
        if (!admin) 'trainer': myId else if (trainer.isNotEmpty) 'trainer': trainer,
      };

  /// Admin: show one trainer's sessions ('' = All trainers).
  void setTrainer(String id) {
    if (id == trainer) return;
    trainer = id;
    load();
  }

  static String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ─────────────────────────────── Navigation (‹ › Today, Week / Day, header and strip taps)

  void prev() {
    if (view == 'day') {
      if (day == 0) {
        week = week.subtract(const Duration(days: 7));
        day = 6;
      } else {
        day--;
        notifyListeners();
        return;
      }
    } else {
      week = week.subtract(const Duration(days: 7));
    }
    load();
  }

  void next() {
    if (view == 'day') {
      if (day == 6) {
        week = week.add(const Duration(days: 7));
        day = 0;
      } else {
        day++;
        notifyListeners();
        return;
      }
    } else {
      week = week.add(const Duration(days: 7));
    }
    load();
  }

  void today() {
    final now = DateTime.now(), w = calMonday(now);
    day = now.weekday - 1;
    if (w != week) {
      week = w;
      load();
    } else {
      notifyListeners();
    }
  }

  void setView(String v) {
    view = v;
    notifyListeners();
  }

  void openDay(int i) {
    day = i;
    view = 'day';
    notifyListeners();
  }

  void pickDay(int i) {
    day = i;
    notifyListeners();
  }

  /// A week date (for the form) → jump the calendar there so the new block shows.
  void show(DateTime d) {
    final w = calMonday(d);
    day = d.weekday - 1;
    if (w != week) {
      week = w;
      load();
    } else {
      load();
    }
  }

  // ─────────────────────────────── Data for the drawers

  Future<List<CalClient>> myClients() async {
    if (clients != null) return clients!;
    // The admin's list is every active client; the trainer's is their own (the server filters).
    final r = await Services.api.get<Map>('clients/', query: {'page_size': 100, 'status': 'active'});
    return clients = [for (final c in r['results'] as List) CalClient(c as Map)];
  }

  Future<CalCheck> check(DateTime start, int minutes, {String? exclude, String? trainer}) async =>
      CalCheck(await Services.api.get<Map>('sessions/check/', query: {
        'start': start.toUtc().toIso8601String(),
        'minutes': minutes,
        'exclude': ?exclude,
        'trainer': ?trainer,
      }));

  /// New (no [id]) or move / edit. Returns the saved session.
  Future<CalSession> save({
    String? id,
    required String client,
    required CalKind kind,
    required DateTime start,
    required int minutes,
    required bool call,
    required String place,
    required String link,
    required String note,
    required bool tell,
    String? trainer,
  }) async {
    final body = {
      'client': client,
      'trainer': ?trainer,
      'kind': kind.api,
      'start': start.toUtc().toIso8601String(),
      'minutes': minutes,
      'is_call': call,
      'place': call ? '' : place,
      'call_link': call ? link : '',
      'note': note,
      'tell_client': tell,
    };
    final r = id == null ? await Services.api.post<Map>('sessions/', body) : await Services.api.patch<Map>('sessions/$id/', body);
    return CalSession(r);
  }

  /// Undo of a booking: cancel it quietly.
  Future<void> unbook(String id) async {
    await Services.api.delete('sessions/$id/?tell_client=false');
    await load();
  }

  /// Undo of a move: put it back where it was, quietly.
  Future<void> moveBack(CalSession old) async {
    await Services.api.patch('sessions/${old.id}/', {
      'start': old.start.toUtc().toIso8601String(),
      'minutes': old.minutes,
      'tell_client': false,
    });
    await load();
  }

  Future<void> setStatus(CalSession s, String status) async {
    final old = s.status;
    s.status = status;
    notifyListeners();
    try {
      await Services.api.post('sessions/${s.id}/status/', {'status': status});
      final r = await Services.api.get<Map>('sessions/stats/', query: _q);
      stats = r;
      notifyListeners();
    } on ApiError {
      s.status = old;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> cancel(CalSession s, {required bool tell}) async {
    await Services.api.delete('sessions/${s.id}/?tell_client=$tell');
    sessions.remove(s);
    notifyListeners();
    load();
  }

  Future<void> restore(String id) async {
    await Services.api.post('sessions/$id/restore/');
    await load();
  }

  /// Admin Availability: one trainer's working hours.
  Future<List<CalAvDay>> hoursOf(String id) async {
    final r = await Services.api.get<Map>('availability/', query: {'trainer': id});
    return [for (final d in r['days'] as List) CalAvDay.fromJson(d as Map)];
  }

  Future<void> saveHours(List<CalAvDay> days, {String? trainer}) async {
    final r = await Services.api.put<Map>('availability/', {'days': [for (final d in days) d.toJson()], 'trainer': ?trainer});
    final saved = [for (final d in r['days'] as List) CalAvDay.fromJson(d as Map)];
    // The shading shows the hours of the trainer on screen only.
    if (trainer == null || trainer == _hoursOf) hours = saved;
    notifyListeners();
  }
}
