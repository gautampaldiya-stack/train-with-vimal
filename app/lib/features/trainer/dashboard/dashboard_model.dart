import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../app/services.dart';
import '../../../app/shell/app_shell.dart' show NavCounts;
import '../../../core/api/api_error.dart';

/// A client as the dashboard shows them: name, initials and board colour class (c1–c6).
class TdPerson {
  TdPerson(Map j)
      : id = '${j['id']}',
        name = '${j['name'] ?? j['full_name'] ?? ''}',
        initials = '${j['initials'] ?? ''}',
        color = '${j['color'] ?? j['avatar_color'] ?? 'c1'}';
  final String id, name, initials, color;
  String get first => name.split(' ').first;
}

class TdStat {
  TdStat(Map j)
      : key = '${j['key']}',
        label = '${j['label']}',
        value = '${j['value']}',
        delta = '${j['delta'] ?? ''}',
        tone = '${j['tone'] ?? ''}';
  final String key, label, value, delta, tone;
}

class TdSession {
  TdSession(Map j)
      : id = '${j['id']}',
        time = '${j['time']}',
        minutes = (j['minutes'] as num?)?.toInt() ?? 60,
        client = TdPerson(j['client'] as Map),
        what = '${j['what'] ?? ''}',
        isCall = j['is_call'] == true,
        status = '${j['status']}',
        next = j['next'] == true,
        inText = '${j['in'] ?? ''}';
  final String id, time, what, inText;
  final int minutes;
  final TdPerson client;
  final bool isCall, next;
  String status; // booked | done | missed
}

class TdNeed {
  TdNeed(Map j)
      : person = TdPerson(j),
        kind = '${j['kind']}',
        why = '${j['why'] ?? ''}',
        action = '${j['action']}',
        reminded = j['reminded'] == true;
  final TdPerson person;
  final String kind, why, action; // kind: log | miss | end | low · action: remind | plan | open
  bool reminded;
}

class TdCheckin {
  TdCheckin(Map j)
      : id = '${j['id']}',
        client = TdPerson(j['client'] as Map),
        kind = '${j['kind']}',
        line = '${j['line'] ?? ''}',
        age = '${j['age'] ?? ''}',
        tone = '${j['tone'] ?? 'neu'}';
  final String id, kind, line, age, tone;
  final TdPerson client;
}

class TdNotice {
  TdNotice(Map j)
      : id = '${j['id']}',
        title = '${j['title']}',
        when = '${j['when'] ?? ''}',
        initials = '${j['initials'] ?? ''}',
        color = '${j['color'] ?? 'c1'}',
        route = '${j['route'] ?? ''}',
        read = j['read'] == true;
  final String id, title, when, initials, color, route;
  bool read;
}

class TrainerHome {
  TrainerHome(Map j)
      : greeting = '${j['greeting']}',
        date = '${j['date']}',
        subline = '${j['subline']}',
        stats = [for (final s in j['stats'] as List) TdStat(s as Map)],
        today = [for (final s in j['today'] as List) TdSession(s as Map)],
        need = [for (final s in j['need'] as List) TdNeed(s as Map)],
        checkins = [for (final s in j['checkins'] as List) TdCheckin(s as Map)],
        checkinsTotal = (j['checkins_total'] as num?)?.toInt() ?? (j['checkins'] as List).length,
        weekRange = '${(j['week'] as Map)['range']}',
        week = [for (final r in (j['week'] as Map)['rows'] as List) ('${(r as Map)['label']}', '${r['value']}')],
        notices = [for (final s in j['notices'] as List) TdNotice(s as Map)],
        unread = (j['unread'] as num?)?.toInt() ?? 0;
  final String greeting, date, subline, weekRange;
  final List<TdStat> stats;
  final List<TdSession> today;
  final List<TdNeed> need;
  final List<TdCheckin> checkins;

  /// Everything waiting (the card lists the oldest 5); same number as the Check-ins page and the nav badge.
  int checkinsTotal;
  final List<(String, String)> week;
  final List<TdNotice> notices;
  int unread;
}

/// Trainer dashboard (boards `TrainerDashboard` + `TrainerDashboardMobile`): loads `dashboard/trainer/` and runs
/// the row actions. Reminders wait for the toast's Undo (10 s) before they go out.
class TrainerHomeController extends ChangeNotifier {
  TrainerHome? data;
  ApiError? error;
  final _pending = <String, Timer>{};

  Future<void> load() async {
    try {
      data = TrainerHome(await Services.api.get<Map>('dashboard/trainer/'));
      for (final n in data!.need) {
        if (_pending.containsKey(n.person.id)) n.reminded = true; // still waiting on Undo
      }
      error = null;
      NavCounts.set('checkins', data!.checkinsTotal);
    } on ApiError catch (e) {
      error = e;
    }
    notifyListeners();
  }

  /// Done / missed / booked (= "Mark as not done").
  Future<void> setStatus(TdSession s, String status) async {
    final old = s.status;
    s.status = status;
    notifyListeners();
    try {
      await Services.api.post('sessions/${s.id}/status/', {'status': status});
    } on ApiError {
      s.status = old;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> cancel(TdSession s) async {
    await Services.api.delete('sessions/${s.id}/');
    data?.today.remove(s);
    notifyListeners();
  }

  Future<void> restore(String id) async {
    await Services.api.post('sessions/$id/restore/');
    await load();
  }

  void remind(TdNeed n) {
    n.reminded = true;
    notifyListeners();
    _pending[n.person.id] = Timer(const Duration(seconds: 10), () => _send(n.person.id));
  }

  void undoRemind(TdNeed n) {
    _pending.remove(n.person.id)?.cancel();
    n.reminded = false;
    notifyListeners();
  }

  void _send(String id) {
    _pending.remove(id);
    Services.api.post('clients/$id/remind/', {}).ignore();
  }

  Future<void> readAll() async {
    for (final n in data?.notices ?? <TdNotice>[]) {
      n.read = true;
    }
    data?.unread = 0;
    notifyListeners();
    await Services.api.post('notifications/read_all/');
  }

  Future<Map> checkin(String id) => Services.api.get<Map>('checkins/$id/');

  Future<void> review(TdCheckin c, String reply) async {
    await Services.api.post('checkins/${c.id}/review/', {'reply': reply});
    await load(); // the next oldest one moves into the card
  }

  Future<void> unreview(String id) async {
    await Services.api.post('checkins/$id/unreview/');
    await load();
  }

  Future<List<TdPerson>> myClients() async {
    final r = await Services.api.get<Map>('clients/', query: {'page_size': 100, 'status': 'active'});
    return [for (final c in r['results'] as List) TdPerson(c as Map)];
  }

  /// Returns the new session's id (for Undo).
  Future<String> addSession({required String client, required DateTime start, required int minutes, required bool call, String note = ''}) async {
    final r = await Services.api.post<Map>('sessions/', {
      'client': client,
      'start': start.toUtc().toIso8601String(),
      'minutes': minutes,
      'is_call': call,
      'place': call ? '' : 'Gym floor',
      'title': 'Extra session',
      'note': note,
    });
    await load();
    return '${r['id']}';
  }

  Future<void> removeSession(String id) async {
    await Services.api.delete('sessions/$id/?tell_client=false');
    await load();
  }

  @override
  void dispose() {
    // Leaving the page sends the reminders still waiting on Undo.
    for (final id in _pending.keys.toList()) {
      _pending[id]!.cancel();
      _send(id);
    }
    super.dispose();
  }
}
