import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../app/shell/app_shell.dart' show NavCounts;
import '../../../core/api/api_error.dart';

/// One sign-up (`GET approvals/`): the person, who invited them, where from, setup steps, waiting time and, in
/// History, the decision.
class ApRow {
  ApRow(this.j)
      : id = '${j['id']}',
        client = (j['client'] as Map?) ?? const {},
        invitedBy = j['invited_by'] as Map?,
        decidedBy = j['decided_by'] as Map?,
        assigned = j['assigned_trainer'] as Map?,
        status = '${j['status'] ?? ''}',
        from = '${j['signed_up_from_label'] ?? j['signed_up_from'] ?? ''}',
        setupDone = (j['setup_done'] as num?)?.toInt() ?? 0,
        healthNote = j['has_health_note'] == true,
        hours = (j['waiting_hours'] as num?)?.toInt() ?? 0,
        movedBack = j['moved_back'] == true,
        created = DateTime.tryParse('${j['created_at'] ?? ''}')?.toLocal(),
        decided = DateTime.tryParse('${j['decided_at'] ?? ''}')?.toLocal();
  final Map j, client;
  final Map? invitedBy, decidedBy, assigned;
  final String id, status, from;
  final int setupDone, hours;
  final bool healthNote, movedBack;
  final DateTime? created, decided;

  String get name => '${client['full_name'] ?? ''}';
  String get first => name.split(' ').first;
  String get email => '${client['email'] ?? ''}';
  String get gender => '${client['gender'] ?? ''}';

  /// "+91 99300 45612".
  String get phone {
    final p = '${client['phone'] ?? ''}';
    final d = p.replaceAll(RegExp(r'[^0-9]'), '');
    if (p.startsWith('+91') && d.length == 12) return '+91 ${d.substring(2, 7)} ${d.substring(7)}';
    return p.isEmpty ? '—' : p;
  }

  /// "40 min", "5 h", "1 day", "2 days" (from the sign-up time, so it is exact under an hour).
  String get wait {
    final mins = created == null ? hours * 60 : DateTime.now().difference(created!).inMinutes;
    if (mins < 60) return '${mins.clamp(1, 59)} min';
    if (mins < 24 * 60) return '${mins ~/ 60} h';
    final d = mins ~/ (24 * 60);
    return '$d day${d == 1 ? '' : 's'}';
  }

  /// Amber after 1 day, red after 2 days.
  bool get old => hours >= 24 && hours < 48;
  bool get late => hours >= 48;

  /// "Signed up Wed, 7 Oct, 9:15 am" / "Signed up today, 11:40 am" / "Signed up yesterday, 8:10 pm".
  String get signedUp {
    final c = created;
    if (c == null) return 'Signed up';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day), day = DateTime(c.year, c.month, c.day);
    final t = DateFormat('h:mm a').format(c).toLowerCase();
    final d = day == today ? 'today' : (day == today.subtract(const Duration(days: 1)) ? 'yesterday' : DateFormat('EEE, d MMM').format(c));
    return 'Signed up $d, $t';
  }

  String get decision => status == 'approved' ? 'Approved' : (status == 'rejected' ? 'Rejected' : 'Waiting');

  /// History "Trainer or reason": "Trainer Neha Joshi" / "Already has an account" (+ their message).
  String get why {
    if (status == 'approved') return assigned == null ? 'Approved' : 'Trainer ${assigned!['full_name']}';
    final r = '${j['reject_reason_label'] ?? ''}';
    final m = '${j['message'] ?? ''}'.trim();
    if (j['reject_reason'] == 'other' && m.isNotEmpty) return m;
    return r;
  }
}

/// A Filter group: query key, label, options (value, label); the first option means "any".
class ApFilter {
  const ApFilter(this.key, this.label, this.options);
  final String key, label;
  final List<(String, String)> options;
}

/// Approvals (boards `Approvals` + `ApprovalsMobile`): Waiting and History tabs, search, Filter with chips,
/// 20 a page. Waiting is oldest first, people moved back on top.
class ApprovalsController extends ChangeNotifier {
  static const pageSize = 20;

  String tab = 'waiting', search = '';
  final filters = <String, String>{};
  List<ApRow> rows = [];
  Map<String, int> counts = {};
  List<(String, String)> staff = [];
  int count = 0, page = 1;
  bool loading = true;
  ApiError? error;
  Timer? _debounce;
  int _seq = 0;

  /// Sub line: "oldest waiting 2 days" (from `approvals/counts/`, so it is right on every page).
  String get oldest {
    final h = counts['oldest_hours'];
    if (h == null) return '';
    if (h < 1) return 'under an hour';
    if (h < 24) return '$h h';
    final d = h ~/ 24;
    return '$d day${d == 1 ? '' : 's'}';
  }

  int get activeFilters => filters.values.where((v) => v.isNotEmpty).length;

  List<ApFilter> get groups => tab == 'history'
      ? [
          const ApFilter('decision', 'Decision', [('', 'Any'), ('approved', 'Approved'), ('rejected', 'Rejected')]),
          ApFilter('decided_by', 'Decided by', [('', 'Anyone'), ...staff]),
          const ApFilter('when', 'When', [('', 'All time'), ('7d', 'Last 7 days'), ('30d', 'Last 30 days')]),
        ]
      : [
          ApFilter('invited_by', 'Invited by', [('', 'Anyone'), ...staff]),
          const ApFilter('setup', 'Profile setup', [('', 'Any'), ('done', 'All 5 done'), ('not_finished', 'Not finished')]),
          const ApFilter('waiting', 'Waiting', [('', 'Any time'), ('1d', 'Over 1 day'), ('2d', 'Over 2 days')]),
          const ApFilter('health_note', 'Health note', [('', 'Any'), ('yes', 'Has a health note'), ('no', 'No health note')]),
          const ApFilter('signed_up_from', 'Signed up from', [('', 'Any'), ('web', 'Web'), ('android', 'Android app'), ('ios', 'iPhone app')]),
        ];

  /// "Invited by: Vimal" chips under the tools.
  List<(String, String)> get chips => [
        for (final g in groups)
          if ((filters[g.key] ?? '').isNotEmpty) (g.key, '${g.label}: ${g.options.firstWhere((o) => o.$1 == filters[g.key], orElse: () => ('', filters[g.key]!)).$2}'),
      ];

  Future<void> loadStaff() async {
    try {
      final r = await Services.api.get<Map>('trainers/', query: {'page_size': 100});
      staff = [for (final t in (r['results'] as List? ?? const [])) ('${(t as Map)['id']}', '${t['full_name']}')];
      notifyListeners();
    } on ApiError catch (_) {}
  }

  Future<void> load() async {
    final seq = ++_seq;
    loading = true;
    notifyListeners();
    try {
      final res = await Future.wait([
        Services.api.get<Map>('approvals/', query: {'tab': tab, 'q': search, ...filters, 'page': page, 'page_size': pageSize}),
        Services.api.get<Map>('approvals/counts/'),
      ]);
      if (seq != _seq) return;
      rows = [for (final r in res[0]['results'] as List) ApRow(r as Map)];
      count = (res[0]['count'] as num?)?.toInt() ?? rows.length;
      counts = {for (final e in res[1].entries) if (e.value is num) '${e.key}': (e.value as num).toInt()};
      NavCounts.set('approvals', counts['waiting'] ?? 0);
      error = null;
    } on ApiError catch (e) {
      if (seq != _seq) return;
      if (e.status == 404 && page > 1) {
        page = 1;
        return load();
      }
      error = e;
    }
    loading = false;
    notifyListeners();
  }

  void setTab(String t) {
    if (t == tab) return;
    tab = t;
    filters.clear();
    page = 1;
    load();
  }

  void setSearch(String q) {
    search = q.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      page = 1;
      load();
    });
  }

  void setFilter(String key, String value) {
    filters[key] = value;
    page = 1;
    load();
  }

  void clearFilters() {
    filters.clear();
    page = 1;
    load();
  }

  void goPage(int p) {
    page = p;
    load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
