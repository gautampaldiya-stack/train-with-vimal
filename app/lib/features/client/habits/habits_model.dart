import 'dart:async';

import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../home/home_model.dart' show hoursMin, inNum, litres;

/// Habits & supplements (`GET me/habits/?date=`): the picked day, its Mon–Sun week grid and every
/// write the page makes. Writes change the screen at once and go through the outbox (offline too).
class HabitsController extends ChangeNotifier {
  HabitsController() {
    _sent = () {
      if (Services.outbox.pending.value == 0 && _dirty) {
        _dirty = false;
        load();
      }
    };
    Services.outbox.pending.addListener(_sent);
  }

  static const _cacheKey = 'me/habits';
  late final VoidCallback _sent;
  bool _dirty = false;

  /// Picked day; null = today.
  DateTime? day;
  HabitsData? data;
  ApiError? error;
  bool _busy = false;

  @override
  void dispose() {
    Services.outbox.pending.removeListener(_sent);
    super.dispose();
  }

  Future<void> start() async {
    final c = await Services.cache.read(_cacheKey);
    if (c is Map && data == null) {
      data = HabitsData(c.cast<String, dynamic>());
      notifyListeners();
    }
    await load();
  }

  void pick(DateTime d) {
    day = DateUtils.isSameDay(d, DateTime.now()) ? null : DateUtils.dateOnly(d);
    _busy = false;
    load();
  }

  Future<void> load() async {
    if (_busy) return;
    _busy = true;
    final d = day;
    try {
      final j = await Services.api.get<Map<String, dynamic>>('me/habits/', query: {if (d != null) 'date': ymd(d)});
      if (d != day) return; // another day was picked meanwhile
      if (d == null) unawaited(Services.cache.write(_cacheKey, j));
      data = HabitsData(j);
      error = null;
    } on ApiError catch (e) {
      error = e;
    } finally {
      if (d == day) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _send(String path, Map<String, dynamic> body) async {
    notifyListeners();
    try {
      final r = await Services.outbox.enqueue('POST', path, {...body, 'date': ymd(data!.date)}, tag: 'habits:$path');
      if (r != null) {
        unawaited(load()); // streaks, week grid
      } else {
        _dirty = true; // offline: reload when it is sent
      }
    } on ApiError catch (_) {
      unawaited(load()); // the server said no: show its numbers again
    }
  }

  void setValue(Habit h, int value) {
    h.value = value;
    h.logged = true;
    h.done = h.target > 0 && value >= h.target;
    _send('me/habits/${h.id}/log/', {'value': value});
  }

  void setDone(Habit h, bool done) {
    h.done = done;
    h.logged = true;
    _send('me/habits/${h.id}/log/', {'done': done});
  }

  /// Water goes through the water log (the Home water card shows the same number); the server moves the habit.
  void addWater(Habit h, int ml) {
    final now = (h.ml + ml).clamp(0, 10000);
    h.value = h.unit == 'ml' ? now : (now / 250).round();
    h.logged = true;
    h.done = h.target > 0 && h.value >= h.target;
    _send('me/food-log/water/', {'ml': ml});
  }

  void setTaken(Supp s, bool taken) {
    if (s.taken == taken) return;
    s.taken = taken;
    s.takenAt = taken ? DateTime.now() : null;
    final st = s.stock;
    if (st != null) s.stock = (quantity: (st.quantity + (taken ? -1 : 1)).clamp(0, 99999), unit: st.unit);
    _send('me/supplements/${s.id}/', {'taken': taken});
  }
}

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime _date(dynamic v) => DateTime.parse('$v');
num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

class HabitsData {
  HabitsData(Map<String, dynamic> j)
      : date = _date(j['date']),
        habits = [for (final h in (j['habits'] as List? ?? const [])) Habit((h as Map).cast<String, dynamic>())],
        supps = [for (final s in (j['supplements'] as List? ?? const [])) Supp((s as Map).cast<String, dynamic>())],
        week = HabitsWeek((j['week'] as Map? ?? const {}).cast<String, dynamic>());
  final DateTime date;
  final List<Habit> habits;
  final List<Supp> supps;
  final HabitsWeek week;

  DateTime get today => DateUtils.dateOnly(DateTime.now());
  bool get isToday => DateUtils.isSameDay(date, today);
  bool get isPast => date.isBefore(today);
  bool get isFuture => date.isAfter(today);

  /// Morning, after training, any time, night (the board's groups).
  List<Supp> get suppsInOrder {
    const order = ['morning', 'training', 'any', 'night'];
    return [...supps]..sort((a, b) => order.indexOf(a.group).compareTo(order.indexOf(b.group)));
  }

  /// Habits that count on this day (started).
  List<Habit> get active => habits.where((h) => h.startsOn == null).toList();
  List<Habit> get soon => habits.where((h) => h.startsOn != null).toList();

  /// "Fat loss support · set by Aman".
  String get by {
    final s = supps.isEmpty ? null : supps.first;
    final who = habits.map((h) => h.setBy).followedBy(supps.map((s) => s.by)).whereType<String>().firstOrNull;
    return ['Daily habits', ?s?.plan, if (who != null) 'set by ${who.split(' ').first}'].join(' · ');
  }
}

class HabitsWeek {
  HabitsWeek(Map<String, dynamic> j)
      : start = j['start'] == null ? DateTime.now() : _date(j['start']),
        end = j['end'] == null ? DateTime.now() : _date(j['end']),
        days = [
          for (final d in (j['days'] as List? ?? const []))
            (date: _date((d as Map)['date']), today: d['today'] == true, future: d['future'] == true, state: '${d['state']}'),
        ],
        habitsDone = _n(j['habits_done']).toInt(),
        habitsDue = _n(j['habits_due']).toInt(),
        suppsTaken = _n(j['supps_taken']).toInt(),
        suppsDue = _n(j['supps_due']).toInt(),
        best = j['best_streak'] is Map ? (name: '${j['best_streak']['name']}', days: _n(j['best_streak']['days']).toInt()) : null;
  final DateTime start, end;
  final List<({DateTime date, bool today, bool future, String state})> days;
  final int habitsDone, habitsDue, suppsTaken, suppsDue;
  final ({String name, int days})? best;

  int get habitsPct => habitsDue == 0 ? 0 : (habitsDone * 100 / habitsDue).round();
  int get suppsPct => suppsDue == 0 ? 0 : (suppsTaken * 100 / suppsDue).round();

  /// "Mon 12 – Sun 18 Oct".
  String get range {
    final a = DateFormat('EEE d').format(start), b = DateFormat('EEE d MMM').format(end);
    return start.month == end.month ? '$a – $b' : '${DateFormat('EEE d MMM').format(start)} – $b';
  }
}

class Habit {
  Habit(Map<String, dynamic> j)
      : id = '${j['id']}',
        name = '${j['name']}',
        counter = j['kind'] == 'counter',
        target = _n(j['target']).toInt(),
        unit = '${j['unit'] ?? ''}',
        icon = '${j['icon'] ?? 'habit'}',
        often = '${j['frequency_label'] ?? 'Daily'}',
        value = _n(j['value']).toInt(),
        logged = j['logged'] == true || _n(j['value']) > 0 || j['done'] == true,
        done = j['done'] == true,
        startsOn = j['starts_on'] == null ? null : _date(j['starts_on']),
        since = j['since'] == null ? null : _date(j['since']),
        setBy = j['set_by'] as String?,
        streak = _n(j['streak']).toInt(),
        best = _n(j['best_streak']).toInt(),
        last7 = [
          for (final d in (j['last_7'] as List? ?? const []))
            (date: _date((d as Map)['date']), done: d['done'] == true, value: d['value'] == null ? null : _n(d['value']).toInt()),
        ],
        week = [for (final s in (j['week'] as List? ?? const [])) '$s'],
        weekDone = _n(j['week_done']).toInt(),
        weekDue = _n(j['week_due']).toInt();
  final String id, name, unit, icon, often;
  final bool counter;
  final int target, streak, best, weekDone, weekDue;
  final DateTime? startsOn, since;
  final String? setBy;
  final List<({DateTime date, bool done, int? value})> last7;
  final List<String> week;
  int value;
  bool logged, done;

  bool get isWater => icon == 'water' && counter;
  bool get isSleep => icon == 'sleep' && counter;
  bool get isSteps => icon == 'steps' && counter;
  int get ml => unit == 'ml' ? value : value * 250;
  int get goalMl => unit == 'ml' ? target : target * 250;
  // A day ticked done without a number (older logs) counts as full.
  double get ratio => done && value == 0 ? 1 : (counter ? (target > 0 ? value / target : 0) : (done ? 1 : 0));

  /// "Steps", "Water", "Sleep".
  String get short => isSteps ? 'Steps' : isWater ? 'Water' : isSleep ? 'Sleep' : name;

  /// One logged value: "6,240 steps", "1.5 L", "7 h 20 min".
  String fmt(int v) {
    if (isWater) return litres(unit == 'ml' ? v : v * 250);
    if (isSleep) return hoursMin(v);
    if (!counter) return v > 0 ? 'Done' : '—';
    return '${inNum(v)}${unit.isEmpty ? '' : ' $unit'}';
  }

  /// Under the name: "6,240 of 8,000 steps", "1.5 L of 3 L · 6 glasses", "7 h 20 min of 7 h".
  String get of {
    if (counter && done && value == 0) return 'Done · goal $goal';
    if (isWater) return '${litres(ml)} of ${litres(goalMl)} · ${(ml / 250).round()} glasses';
    if (isSleep) return '${hoursMin(value)} of ${hoursMin(target)}';
    if (!counter) return done ? 'Done' : 'Yes / no · tick it each evening';
    return '${inNum(value)} of ${inNum(target)}${unit.isEmpty ? '' : ' $unit'}';
  }

  /// "8,000 steps a day", "3 L a day (12 glasses)", "7 hours a night".
  String get goal {
    if (isWater) return '${litres(goalMl)} a day${unit == 'ml' ? '' : ' ($target glasses)'}';
    if (isSleep) return target % 60 == 0 ? '${target ~/ 60} hours a night' : '${hoursMin(target)} a night';
    if (!counter) return name;
    return '${inNum(target)}${unit.isEmpty ? '' : ' $unit'} a day';
  }

  /// Week grid line: "8,000 a day", "3 L a day", "7 h a night".
  String get weekLine {
    if (isWater) return '${litres(goalMl)} a day';
    if (isSleep) return '${hoursMin(target)} a night';
    if (!counter) return how;
    return '${inNum(target)} a day';
  }

  String get how => isSleep ? 'Every night' : (often == 'Daily' ? 'Every day' : often);
}

class Supp {
  Supp(Map<String, dynamic> j)
      : id = _n(j['id']).toInt(),
        name = '${j['name']}',
        plan = '${j['plan'] ?? ''}',
        planSince = j['plan_since'] == null ? null : _date(j['plan_since']),
        by = j['by'] as String?,
        dose = '${j['dose'] ?? ''}',
        how = '${j['how'] ?? ''}',
        group = '${j['group'] ?? 'any'}',
        groupName = '${j['group_name'] ?? 'Any time'}',
        groupLine = '${j['group_line'] ?? ''}',
        due = j['due'] != false,
        taken = j['taken'] == true,
        takenAt = j['taken_at'] == null ? null : DateTime.tryParse('${j['taken_at']}')?.toLocal(),
        pill = '${j['pill'] ?? ''}',
        stock = j['stock'] is Map ? (quantity: _n(j['stock']['quantity']).toInt(), unit: '${j['stock']['unit']}') : null,
        last7 = [for (final t in (j['last_7'] as List? ?? const [])) t == true],
        week = [for (final s in (j['week'] as List? ?? const [])) '$s'];
  final int id;
  final String name, plan, dose, how, group, groupName, groupLine, pill;
  final String? by;
  final DateTime? planSince;
  final bool due;
  final List<bool> last7;
  final List<String> week;
  bool taken;
  DateTime? takenAt;
  ({int quantity, String unit})? stock;

  /// "Starts Mon, 19 Oct" before the plan begins.
  String? get starts => pill.startsWith('Starts') ? pill : null;

  /// "1 scoop · 30 g · in water, after training".
  String get line => [dose, if (how.isNotEmpty) how[0].toLowerCase() + how.substring(1)].where((s) => s.isNotEmpty).join(' · ');

  /// "Morning, 8:00 am" from the group line.
  String get when {
    final t = groupLine.contains(' · ') ? groupLine.split(' · ').last : '';
    return t.isEmpty ? groupName : '$groupName, $t';
  }

  /// "10:30 pm" for a night supplement.
  String? get dueAt => groupLine.contains(' · ') ? groupLine.split(' · ').last : null;
}
