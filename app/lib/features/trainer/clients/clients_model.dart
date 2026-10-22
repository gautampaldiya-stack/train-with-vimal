import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';

/// One row of My clients (`GET clients/`).
class McRow {
  McRow(Map j)
      : id = '${j['id']}',
        name = '${j['full_name'] ?? ''}',
        email = '${j['email'] ?? ''}',
        phone = '${j['phone'] ?? ''}',
        initials = '${j['initials'] ?? ''}',
        color = '${j['avatar_color'] ?? 'c1'}',
        badge = '${j['badge'] ?? j['status'] ?? ''}',
        goal = '${j['goal_label'] ?? ''}',
        onbDone = ((j['onboarding'] as Map?)?['done'] as num?)?.toInt() ?? 0,
        onbTotal = ((j['onboarding'] as Map?)?['total'] as num?)?.toInt() ?? 1,
        next = '${j['next_checkin'] ?? '—'}',
        lastActive = '${j['last_active'] ?? '—'}',
        status = '${j['status'] ?? ''}',
        gender = '${j['gender'] ?? ''}',
        trainerId = (j['trainer'] as Map?)?['id']?.toString(),
        trainerName = '${(j['trainer'] as Map?)?['full_name'] ?? ''}',
        joined = DateTime.tryParse('${j['date_joined'] ?? ''}')?.toLocal();
  final String id, name, email, phone, initials, color, badge, goal, next, lastActive, status, gender, trainerName;
  final String? trainerId;
  final DateTime? joined;
  final int onbDone, onbTotal;

  /// `.bar` fill and its caption: "Done", "40%", "Not started" (the account step alone is not a start).
  double get onb => onbTotal == 0 ? 0 : onbDone / onbTotal;
  String get onbText => onbDone >= onbTotal ? 'Done' : (onbDone <= 1 ? 'Not started' : '${(onb * 100).round()}%');

  /// "+91 98201 11234" from "+919820111234".
  String get phoneText {
    final d = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.startsWith('+91') && d.length == 12) return '+91 ${d.substring(2, 7)} ${d.substring(7)}';
    return phone.isEmpty ? '—' : phone;
  }
}

/// A Filter group: query key, label, options as (value, label); the first option means "any".
class McFilter {
  const McFilter(this.key, this.label, this.options);
  final String key, label;
  final List<(String, String)> options;
}

const mcFilters = [
  McFilter('goal', 'Goal', [('', 'Any'), ('fat_loss', 'Fat loss'), ('muscle_gain', 'Muscle gain'), ('strength', 'Strength'), ('recomp', 'Recomp'), ('general', 'General fitness')]),
  McFilter('onboarding', 'Onboarding', [('', 'Any'), ('done', 'Done'), ('not_started', 'Not started'), ('in_progress', 'In progress')]),
  McFilter('next_checkin', 'Next check-in', [('', 'Any'), ('today', 'Today'), ('week', 'This week'), ('overdue', 'Overdue')]),
  McFilter('joined', 'Joined', [('', 'Any time'), ('30d', 'Last 30 days'), ('year', 'This year')]),
];

/// My clients (boards `TrainerClients` + `TrainerClientsMobile`): tabs with counts, search, Filter, 8 a page,
/// selection for Export.
class MyClientsController extends ChangeNotifier {
  static const pageSize = 8;

  List<McRow> rows = [];
  Map<String, int> counts = {};
  int count = 0, page = 1;
  String tab = 'all', search = '';
  final filters = <String, String>{};
  final selected = <String>{};
  bool loading = true;
  ApiError? error;
  Timer? _debounce;
  int _seq = 0;

  int get pages => count == 0 ? 1 : ((count + pageSize - 1) ~/ pageSize);
  int get activeFilters => filters.values.where((v) => v.isNotEmpty).length;

  Map<String, dynamic> get _query => {'tab': tab == 'all' ? null : tab, 'search': search, ...filters};

  Future<void> load() async {
    final seq = ++_seq;
    loading = true;
    notifyListeners();
    try {
      final res = await Future.wait([
        Services.api.get<Map>('clients/', query: {..._query, 'page': page, 'page_size': pageSize}),
        Services.api.get<Map>('clients/counts/'),
      ]);
      if (seq != _seq) return; // a newer search or tab already asked
      rows = [for (final r in res[0]['results'] as List) McRow(r as Map)];
      count = (res[0]['count'] as num?)?.toInt() ?? rows.length;
      counts = {for (final e in res[1].entries) '${e.key}': (e.value as num).toInt()};
      error = null;
    } on ApiError catch (e) {
      if (seq != _seq) return;
      if (e.status == 404 && page > 1) {
        page = 1; // the filter made the list shorter than this page
        return load();
      }
      error = e;
    }
    loading = false;
    notifyListeners();
  }

  void setTab(String t) {
    tab = t;
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
    page = p.clamp(1, pages);
    load();
  }

  void toggle(String id) {
    selected.contains(id) ? selected.remove(id) : selected.add(id);
    notifyListeners();
  }

  /// Header box: all rows of this page on or off.
  void toggleAll() {
    final ids = rows.map((r) => r.id);
    final all = ids.every(selected.contains);
    all ? selected.removeAll(ids) : selected.addAll(ids);
    notifyListeners();
  }

  /// CSV of the list as filtered now, or of the selected clients.
  Future<List<int>> export({bool onlySelected = false}) async {
    final r = await Services.api.download('clients/export/', query: onlySelected ? {'ids': selected.join(',')} : _query);
    return r.data ?? const [];
  }

  Future<Map> detail(String id) => Services.api.get<Map>('clients/$id/');

  Future<void> save(String id, Map<String, dynamic> data) async {
    await Services.api.patch('clients/$id/', data);
    await load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
