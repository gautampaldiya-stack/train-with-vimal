import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../app/services.dart';
import '../../../app/shell/app_shell.dart' show NavCounts;
import '../../../core/api/api_error.dart';
import '../../trainer/dashboard/dashboard_model.dart' show NoticesSource, TdNotice;

/// `dashboard/admin/` (boards `AdminDashboard` / `AdminDashboardMobile`).
class AdminHome {
  AdminHome(Map j)
      : greeting = '${j['greeting'] ?? ''}',
        subline = '${j['subline'] ?? ''}',
        stats = Map.of(j['stats'] as Map? ?? const {}),
        glance = Map.of(j['glance'] as Map? ?? const {}),
        needs = [for (final r in (j['needs_action'] as List? ?? const [])) AdNeed(r as Map)],
        trainers = [for (final r in (j['trainer_performance'] as List? ?? const [])) AdTrainer(r as Map)],
        risk = [for (final r in ((j['at_risk'] as Map?)?['rows'] as List? ?? const [])) AdRisk(r as Map)],
        riskCount = ((j['at_risk'] as Map?)?['count'] as num?)?.toInt() ?? 0,
        remindedRecently = ((j['at_risk'] as Map?)?['reminded_last_24h'] as num?)?.toInt() ?? 0,
        activity = [for (final r in (j['recent_activity'] as List? ?? const [])) AdEvent(r as Map)],
        notices = [for (final n in (j['notices'] as List? ?? const [])) TdNotice(n as Map)],
        unread = (j['unread'] as num?)?.toInt() ?? 0;
  final String greeting, subline;
  final Map stats, glance;
  final List<AdNeed> needs;
  final List<AdTrainer> trainers;
  final List<AdRisk> risk;
  final List<AdEvent> activity;
  final List<TdNotice> notices;
  int riskCount, remindedRecently, unread;

  num? stat(String k, [String f = 'value']) => (stats[k] as Map?)?[f] as num?;
  num glanceOf(String k, [String f = 'value']) => ((glance[k] as Map?)?[f] as num?) ?? 0;
}

/// A Needs action row: kind (approvals · clients · checkins · trainers · programs), title, sub, CTA → route.
class AdNeed {
  AdNeed(Map j)
      : key = '${j['key']}',
        kind = '${j['kind']}',
        title = '${j['title'] ?? ''}',
        sub = '${j['sub'] ?? ''}',
        cta = '${j['cta'] ?? 'Open'}',
        route = '${j['route'] ?? '/'}';
  final String key, kind, title, sub, cta, route;
}

class AdTrainer {
  AdTrainer(Map j)
      : id = '${j['id']}',
        name = '${j['full_name'] ?? ''}',
        initials = '${j['initials'] ?? ''}',
        color = '${j['avatar_color'] ?? 'c1'}',
        clients = (j['clients'] as num?)?.toInt() ?? 0,
        max = (j['max_clients'] as num?)?.toInt() ?? 0,
        adherence = (j['adherence'] as num?)?.toInt(),
        reply = (j['reply_hours'] as num?)?.toDouble();
  final String id, name, initials, color;
  final int clients, max;
  final int? adherence;
  final double? reply;
  bool get over => max > 0 && clients > max;
  String get load => '$clients / $max';
  String get replyLabel => reply == null ? '—' : '${reply!.toStringAsFixed(1)} h';
}

class AdRisk {
  AdRisk(Map j)
      : id = '${j['id']}',
        name = '${j['full_name'] ?? ''}',
        initials = '${j['initials'] ?? ''}',
        color = '${j['avatar_color'] ?? 'c1'}',
        why = [if ('${j['reason'] ?? ''}'.isNotEmpty) '${j['reason']}', if (j['trainer'] != null) '${j['trainer']}'].join(' · ');
  final String id, name, initials, color, why;
  bool reminded = false;
  String get first => name.split(' ').first;
}

/// One Recent activity line: **who** verb target, and how long ago ("14m", "3h", "2d").
class AdEvent {
  AdEvent(Map j)
      : who = '${j['actor_label'] ?? 'System'}',
        initials = '${j['actor_initials'] ?? 'S'}',
        color = '${j['actor_avatar_color'] ?? 'c4'}',
        what = ['${j['verb'] ?? ''}', '${j['target_label'] ?? ''}'].where((s) => s.isNotEmpty).join(' '),
        at = DateTime.tryParse('${j['created_at']}');
  final String who, initials, color, what;
  final DateTime? at;

  String get ago {
    if (at == null) return '';
    final d = DateTime.now().difference(at!);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

class AdminHomeController extends ChangeNotifier implements NoticesSource {
  AdminHome? data;
  ApiError? error;

  /// Trainer performance: 'week' (7-day adherence) or 'month' (30-day).
  String period = 'week';
  final _pending = <String, Timer>{};

  @override
  List<TdNotice> get notices => data?.notices ?? const [];
  @override
  int get unread => data?.unread ?? 0;

  Future<void> load() async {
    try {
      data = AdminHome(await Services.api.get<Map>('dashboard/admin/', query: {if (period == 'month') 'period': 'month'}));
      for (final r in data!.risk) {
        if (_pending.containsKey(r.id)) r.reminded = true; // still waiting on Undo
      }
      error = null;
      final waiting = data!.stat('pending_approvals');
      if (waiting != null) NavCounts.set('approvals', waiting.toInt());
    } on ApiError catch (e) {
      error = e;
    }
    notifyListeners();
  }

  Future<void> setPeriod(String p) async {
    if (p == period) return;
    period = p;
    await load();
  }

  /// × on a Needs action row: gone for good (the server keeps the key).
  Future<void> dismiss(AdNeed n) async {
    data?.needs.remove(n);
    notifyListeners();
    await Services.api.post('dashboard/dismiss/', {'key': n.key});
  }

  /// Remind waits 10 s for Undo before it is sent (same as the trainer dashboard).
  void remind(AdRisk r) {
    r.reminded = true;
    notifyListeners();
    _pending[r.id] = Timer(const Duration(seconds: 10), () => _send(r.id));
  }

  void _send(String id) {
    _pending.remove(id);
    Services.api.post('clients/$id/remind/', {}).ignore();
  }

  void undoRemind(AdRisk r) {
    _pending.remove(r.id)?.cancel();
    r.reminded = false;
    notifyListeners();
  }

  /// "Remind all": every at-risk client, minus the ones reminded in the last 24 hours when [skipRecent].
  Future<int> remindAll({required bool skipRecent}) async {
    final r = await Services.api.post<Map>('clients/remind-at-risk/', {'skip_recent_hours': skipRecent ? 24 : 0});
    await load();
    return (r['reminded'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> readAll() async {
    for (final n in notices) {
      n.read = true;
    }
    data?.unread = 0;
    notifyListeners();
    await Services.api.post('notifications/read_all/');
  }

  @override
  void dispose() {
    // Leaving the page before Undo runs out still sends the reminders.
    for (final id in [..._pending.keys]) {
      _pending[id]!.cancel();
      _send(id);
    }
    super.dispose();
  }
}
