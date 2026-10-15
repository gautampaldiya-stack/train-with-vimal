import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';

/// Data of the client Home (`GET me/home/`) and every write it makes. Writes change the
/// numbers on screen at once and go through the outbox, so they also work offline.
class HomeController extends ChangeNotifier {
  HomeController() {
    _sub = Services.realtime.events.where((e) => _reloadOn.contains(e.event)).listen((_) => load());
    // A check-in, workout or meal sent from another page: refresh the cards.
    _synced = Services.outbox.results.where((r) => r.error == null && !r.tag.startsWith('home:')).listen((_) => load());
  }

  static const _cacheKey = 'me/home';
  static const _reloadOn = {'notification', 'checkin_reviewed', 'session_booked', 'plan_updated'};
  StreamSubscription? _sub, _synced;

  HomeData? data;
  ApiError? error;
  bool _busy = false;

  @override
  void dispose() {
    _sub?.cancel();
    _synced?.cancel();
    super.dispose();
  }

  Future<void> start() async {
    final c = await Services.cache.read(_cacheKey);
    if (c is Map && data == null) {
      data = HomeData(c.cast<String, dynamic>());
      notifyListeners();
    }
    await load();
  }

  Future<void> load() async {
    if (_busy) return;
    _busy = true;
    try {
      final j = await Services.api.get<Map<String, dynamic>>('me/home/');
      unawaited(Services.cache.write(_cacheKey, j));
      data = HomeData(j);
      error = null;
    } on ApiError catch (e) {
      error = e;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void changed() => notifyListeners();

  String get _day => DateFormat('yyyy-MM-dd').format(data!.date);

  Future<void> _send(String path, Map<String, dynamic> body, {bool reload = false}) async {
    try {
      await Services.outbox.enqueue('POST', path, {...body, 'date': _day}, tag: 'home:$path');
      if (reload) unawaited(load());
    } on ApiError catch (_) {
      unawaited(load()); // the server said no: show its numbers again
    }
  }

  // Water: 250 ml a glass. The water habit follows it on the server too.
  void addWater(int ml) {
    final d = data!;
    d.waterMl = (d.waterMl + ml).clamp(0, 10000);
    for (final h in d.habits.where((h) => h.isWater)) {
      h.value = h.unit == 'ml' ? d.waterMl : d.waterMl ~/ 250;
      h.done = h.target > 0 && h.value >= h.target;
    }
    changed();
    _send('me/food-log/water/', {'ml': ml});
  }

  void setMeal(HomeMeal m, bool eaten) {
    final d = data!;
    final sign = eaten ? 1 : -1;
    m.pill = eaten ? 'logged' : 'to_log';
    d.eaten = [for (final (i, v) in d.eaten.indexed) v + sign * [m.kcal, m.protein, m.carbs, m.fat][i]];
    changed();
    _send('me/food/meals/${m.id}/${eaten ? 'eat' : 'unlog'}/', {}, reload: true);
  }

  void setHabit(HomeHabit h, {int? value, bool? done}) {
    if (value != null) {
      h.value = value;
      h.done = h.target > 0 && value >= h.target;
    }
    if (done != null) h.done = done;
    changed();
    _send('me/habits/${h.id}/log/', h.counter ? {'value': h.value} : {'done': h.done});
  }

  void setSupplement(HomeSupplement s, bool taken) {
    s.taken = taken;
    changed();
    _send('me/supplements/${s.id}/', {'taken': taken});
  }

  void readAll() {
    for (final n in data!.notices) {
      n.read = true;
    }
    data!.unread = 0;
    changed();
    _send('notifications/read_all/', {});
  }
}

DateTime _date(dynamic v) => DateTime.parse('$v');
DateTime? _dateOr(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

class HomeData {
  HomeData(this.json)
      : date = _date(json['date']),
        week = json['week'] as int?,
        weeks = json['weeks'] as int?,
        firstName = '${json['first_name'] ?? ''}',
        initials = '${json['initials'] ?? ''}',
        goal = '${json['goal'] ?? ''}',
        strip = [for (final d in (json['strip'] as List? ?? const [])) HomeDay(d as Map<String, dynamic>)],
        waterMl = _n((json['water'] as Map?)?['ml']).toInt(),
        waterGoal = _n((json['water'] as Map?)?['goal_ml'] ?? 3000).toInt(),
        meals = [for (final m in (json['meals'] as List? ?? const [])) HomeMeal(m as Map<String, dynamic>)],
        target = _macros(json['macros_target']),
        eaten = _macros(json['eaten']),
        habits = [for (final h in (json['habits'] as List? ?? const [])) HomeHabit(h as Map<String, dynamic>)],
        soon = [
          for (final h in (json['habits_soon'] as List? ?? const [])) (name: '${h['name']}', starts: _date(h['starts'])),
        ],
        supplements = [for (final s in (json['supplements'] as List? ?? const [])) HomeSupplement(s as Map<String, dynamic>)]
          ..sort((a, b) => a.order.compareTo(b.order)),
        coming = [for (final c in (json['coming_up'] as List? ?? const [])) (c as Map).cast<String, dynamic>()],
        notices = [for (final n in (json['notices'] as List? ?? const [])) HomeNotice(n as Map<String, dynamic>)],
        unread = _n(json['unread']).toInt(),
        session = json['session'] == null ? null : HomeSession(json['session'] as Map<String, dynamic>),
        coach = (json['trainer'] as Map?)?.cast<String, dynamic>(),
        note = (json['trainer_note'] as Map?)?.cast<String, dynamic>();

  final Map<String, dynamic> json;
  final DateTime date;
  final int? week, weeks;
  final String firstName, initials, goal;
  final List<HomeDay> strip;
  int waterMl;
  final int waterGoal;
  final List<HomeMeal> meals;
  final List<num>? target;
  List<num> eaten;
  final List<HomeHabit> habits;
  final List<({String name, DateTime starts})> soon;
  final List<HomeSupplement> supplements;
  final List<Map<String, dynamic>> coming;
  final List<HomeNotice> notices;
  int unread;
  final HomeSession? session;
  final Map<String, dynamic>? coach, note;

  static List<num> _macros(dynamic m) => m is Map ? [for (final k in ['kcal', 'protein', 'carbs', 'fat']) _n(m[k])] : [0, 0, 0, 0];

  String get coachFirst => '${coach?['full_name'] ?? 'Your coach'}'.split(' ').first;
  int get todayIndex => strip.indexWhere((d) => d.today);
}

class HomeDay {
  HomeDay(Map<String, dynamic> j)
      : date = _date(j['date']),
        today = j['today'] == true,
        rest = j['is_rest'] == true,
        name = '${j['name'] ?? ''}',
        cardio = j['kind'] == 'cardio',
        minutes = _n(j['minutes']).toInt(),
        exercises = [for (final e in (j['exercises'] as List? ?? const [])) (name: '${e['name']}', line: '${e['line']}')],
        done = j['done'] == true,
        exercisesDone = _n(j['exercises_done']).toInt(),
        doneLine = '${j['done_line'] ?? ''}';
  final DateTime date;
  final bool today, rest, cardio, done;
  final String name, doneLine;
  final int minutes, exercisesDone;
  final List<({String name, String line})> exercises;
}

class HomeMeal {
  HomeMeal(Map<String, dynamic> j)
      : id = _n(j['id']).toInt(),
        name = '${j['name']}',
        time = '${j['time'] ?? ''}',
        pill = '${j['pill'] ?? ''}',
        foods = '${j['foods'] ?? ''}',
        kcal = _n(j['kcal']),
        protein = _n(j['protein']),
        carbs = _n(j['carbs']),
        fat = _n(j['fat']);
  final int id;
  final String name, time, foods;
  String pill;
  final num kcal, protein, carbs, fat;
  bool get eaten => pill == 'logged';
  bool get open => pill != 'logged' && pill != 'skipped';
}

class HomeHabit {
  HomeHabit(Map<String, dynamic> j)
      : id = '${j['id']}',
        name = '${j['name']}',
        counter = j['kind'] == 'counter',
        target = _n(j['target']).toInt(),
        unit = '${j['unit'] ?? ''}',
        icon = '${j['icon'] ?? 'habit'}',
        value = _n(j['value']).toInt(),
        done = j['done'] == true;
  final String id, name, unit, icon;
  final bool counter;
  final int target;
  int value;
  bool done;
  bool get isWater => icon == 'water' && counter;
  bool get isSleep => icon == 'sleep' && counter;
  double get ratio => counter ? (target > 0 ? value / target : 0) : (done ? 1 : 0);
}

class HomeSupplement {
  HomeSupplement(Map<String, dynamic> j)
      : id = _n(j['id']).toInt(),
        name = '${j['name']}',
        dose = '${j['dose'] ?? ''}',
        timing = '${j['timing'] ?? ''}',
        due = j['due'] != false,
        taken = j['taken'] == true;
  final int id;
  final String name, dose, timing;
  final bool due;
  bool taken;

  static const _order = ['breakfast', 'morning', 'post_workout', 'any', 'night', 'before_bed'];
  int get order => _order.indexOf(timing);

  /// "1 tablet · night, before bed", like the board.
  String get line {
    final when = switch (timing) {
      'breakfast' => 'with breakfast',
      'morning' => 'morning',
      'post_workout' => 'after training',
      'night' => 'night',
      'before_bed' => 'night, before bed',
      _ => 'any time',
    };
    return dose.isEmpty ? when : '${dose.split(' · ').first} · $when';
  }
}

class HomeNotice {
  HomeNotice(Map<String, dynamic> j)
      : title = '${j['title']}',
        body = '${j['body'] ?? ''}',
        at = _dateOr(j['created_at']) ?? DateTime.now(),
        read = j['read'] == true,
        event = '${j['event'] ?? ''}',
        route = '${(j['data'] as Map?)?['route'] ?? ''}';
  final String title, body, event, route;
  final DateTime at;
  bool read;
}

class HomeSession {
  HomeSession(Map<String, dynamic> j)
      : start = _dateOr(j['start'])!,
        end = _dateOr(j['end'])!,
        place = '${j['place'] ?? ''}',
        isCall = j['is_call'] == true,
        coach = '${(j['trainer'] as Map?)?['full_name'] ?? ''}'.split(' ').first;
  final DateTime start, end;
  final String place, coach;
  final bool isCall;
  int get minutes => end.difference(start).inMinutes;
}

// ─────────────────────────────── Text helpers (board wording)

final _inNum = NumberFormat.decimalPattern('en_IN');
String inNum(num v) => _inNum.format(v.round());

/// 1500 → "1.5 L", 3000 → "3 L", 1750 → "1.75 L".
String litres(int ml) {
  final dec = ml % 1000 == 0 ? 0 : (ml % 500 == 0 ? 1 : 2);
  var s = (ml / 1000).toStringAsFixed(dec);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return '$s L';
}

String glasses(int n) => '$n ${n == 1 ? 'glass' : 'glasses'}';
String dayShort(DateTime d) => DateFormat('EEE, d MMM').format(d);
String clock(DateTime t) => DateFormat('h:mm a').format(t).toLowerCase();

/// "08:00:00" → "8:00 am".
String mealTime(String hms) {
  final p = hms.split(':');
  if (p.length < 2) return hms;
  return clock(DateTime(2000, 1, 1, int.tryParse(p[0]) ?? 0, int.tryParse(p[1]) ?? 0));
}

/// 440 → "7 h 20 min".
String hoursMin(int m) => '${m ~/ 60} h${m % 60 > 0 ? ' ${m % 60} min' : ''}';

/// "2 h", "Mon", "3 Oct" for lists; [ago] adds " ago" to the short ones.
String since(DateTime t, {bool ago = false}) {
  final d = DateTime.now().difference(t);
  final tail = ago ? ' ago' : '';
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes} min$tail';
  if (d.inHours < 24) return '${d.inHours} h$tail';
  if (d.inDays < 7) return DateFormat('EEE').format(t);
  return DateFormat('d MMM').format(t);
}
