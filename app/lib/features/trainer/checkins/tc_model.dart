import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../app/services.dart';
import '../../../app/shell/app_shell.dart' show NavCounts;
import '../../../core/api/api_error.dart';

/// One row of the Check-ins list (`GET checkins/`).
class TcRow {
  TcRow(Map j)
      : id = '${j['id']}',
        clientId = '${(j['client'] as Map?)?['id'] ?? ''}',
        name = '${(j['client'] as Map?)?['full_name'] ?? ''}',
        initials = '${(j['client'] as Map?)?['initials'] ?? ''}',
        color = '${(j['client'] as Map?)?['avatar_color'] ?? 'c1'}',
        type = '${j['form_type'] ?? ''}',
        formName = '${j['form_name'] ?? ''}',
        summary = '${j['summary'] ?? ''}',
        reviewed = j['reviewed'] == true,
        reply = '${j['reply'] ?? ''}',
        week = (j['week_number'] as num?)?.toInt(),
        created = DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now(),
        reviewedAt = DateTime.tryParse('${j['reviewed_at'] ?? ''}')?.toLocal();
  final String id, clientId, name, initials, color, type, formName, summary;
  bool reviewed;
  String reply;
  final int? week;
  final DateTime created;
  DateTime? reviewedAt;

  String get first => name.split(' ').first;

  /// "Weekly check-in", "Daily check-in", "Monthly progress" (the form's own name for other kinds).
  String get kind => switch (type) { 'weekly' => 'Weekly check-in', 'daily' => 'Daily check-in', 'survey' => 'Monthly progress', _ => formName };

  /// "2 d", "6 h", "12 min" since it was sent.
  String get age {
    final d = DateTime.now().difference(created);
    if (d.inHours >= 24) return '${d.inDays} d';
    if (d.inHours >= 1) return '${d.inHours} h';
    return '${d.inMinutes.clamp(1, 59)} min';
  }

  /// Waiting 48 hours or more: the age shows in red.
  bool get late => !reviewed && DateTime.now().difference(created).inHours >= 48;
}

/// Check-ins page (boards `TrainerCheckins` + `TrainerCheckinsMobile`): To review / Reviewed / All, type chips,
/// search, a list (newest first, Show more) and the open check-in on the right (its own page on a phone).
class TcController extends ChangeNotifier {
  String tab = 'to_review', kind = 'all', search = '';
  List<TcRow> rows = [];
  Map counts = const {};
  String? next; // cursor URL of the next page
  String? selected;
  bool loading = true, more = false;
  ApiError? error;
  Timer? _debounce;
  int _seq = 0;
  final _details = <String, Future<Map>>{};

  static const tabs = [('to_review', 'To review'), ('reviewed', 'Reviewed'), ('all', 'All')];
  static const kinds = [('all', 'All types'), ('weekly', 'Weekly'), ('daily', 'Daily'), ('monthly', 'Monthly')];

  int get toReview => (counts['to_review'] as num?)?.toInt() ?? 0;
  int tabCount(String t) => (counts[t] as num?)?.toInt() ?? 0;
  int kindCount(String k) => ((((counts['kinds'] as Map?) ?? const {})[tab] as Map?)?[k] as num?)?.toInt() ?? 0;

  /// "4 to review · oldest from 2 d ago" / "All check-ins reviewed".
  String get subline {
    if (counts.isEmpty) return ' ';
    if (toReview == 0) return 'All check-ins reviewed';
    final o = DateTime.tryParse('${counts['oldest'] ?? ''}')?.toLocal();
    if (o == null) return '$toReview to review';
    final d = DateTime.now().difference(o);
    final ago = d.inHours >= 24 ? '${d.inDays} d' : (d.inHours >= 1 ? '${d.inHours} h' : '${d.inMinutes.clamp(1, 59)} min');
    return '$toReview to review · oldest from $ago ago';
  }

  TcRow? get current => rows.where((r) => r.id == selected).firstOrNull;
  int get index => rows.indexWhere((r) => r.id == selected);

  Map<String, dynamic> get _query => {'tab': tab, if (kind != 'all') 'kind': kind, if (search.isNotEmpty) 'search': search, 'page_size': 30};

  Future<void> load({bool keepSelection = false}) async {
    final seq = ++_seq;
    loading = true;
    notifyListeners();
    try {
      final r = await Future.wait([Services.api.get<Map>('checkins/', query: _query), Services.api.get<Map>('checkins/counts/')]);
      if (seq != _seq) return;
      rows = [for (final x in (r[0]['results'] as List)) TcRow(x as Map)];
      next = r[0]['next'] as String?;
      counts = r[1];
      NavCounts.set('checkins', toReview);
      if (!keepSelection || rows.every((x) => x.id != selected)) selected = rows.firstOrNull?.id;
      error = null;
    } on ApiError catch (e) {
      if (seq != _seq) return;
      error = e;
    }
    loading = false;
    notifyListeners();
  }

  /// Show more: the next page by its cursor.
  Future<void> loadMore() async {
    final n = next;
    if (n == null || more) return;
    more = true;
    notifyListeners();
    try {
      final cursor = Uri.parse(n).queryParameters['cursor'];
      final r = await Services.api.get<Map>('checkins/', query: {..._query, 'cursor': cursor});
      rows = [...rows, for (final x in (r['results'] as List)) TcRow(x as Map)];
      next = r['next'] as String?;
    } on ApiError catch (e) {
      error = e;
    }
    more = false;
    notifyListeners();
  }

  void setTab(String t) {
    tab = t;
    load();
  }

  void setKind(String k) {
    kind = k;
    load();
  }

  void setSearch(String q) {
    search = q.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), load);
  }

  void select(String id) {
    selected = id;
    notifyListeners();
  }

  /// ‹ › in the panel: the row above / below in the list.
  void step(int k) {
    final i = index + k;
    if (i >= 0 && i < rows.length) select(rows[i].id);
  }

  Future<Map> detail(String id) => _details.putIfAbsent(id, () => Services.api.get<Map>('checkins/$id/'));

  /// Mark reviewed (with the reply, if any). On To review the next one waiting opens. Returns the row for Undo.
  Future<TcRow?> review(String id, String reply) async {
    final r = await Services.api.post('checkins/$id/review/', {'reply': reply});
    final row = rows.where((x) => x.id == id).firstOrNull;
    final at = index;
    _details.remove(id);
    if (row != null) {
      row
        ..reviewed = true
        ..reply = reply
        ..reviewedAt = DateTime.now();
      if (tab == 'to_review') {
        rows.remove(row);
        selected = rows.isEmpty ? null : rows[at.clamp(0, rows.length - 1)].id;
      }
    }
    unawaited(_counts());
    notifyListeners();
    return r == null ? row : row;
  }

  /// "Mark as not reviewed" and the toast's Undo.
  Future<void> unreview(String id) async {
    await Services.api.post('checkins/$id/unreview/');
    _details.remove(id);
    await load(keepSelection: true);
    if (rows.any((x) => x.id == id)) select(id);
  }

  Future<void> _counts() async {
    try {
      counts = await Services.api.get<Map>('checkins/counts/');
      NavCounts.set('checkins', toReview);
      notifyListeners();
    } on ApiError catch (_) {}
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
