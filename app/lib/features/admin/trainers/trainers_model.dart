import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';

/// One trainer row (`GET trainers/`): load, check-ins to review, adherence, access, status, joined.
class TrRow {
  TrRow(this.j)
      : id = '${j['id']}',
        name = '${j['full_name'] ?? ''}',
        n = (j['clients'] as num?)?.toInt() ?? 0,
        max = (j['max_clients'] as num?)?.toInt() ?? 0,
        review = (j['checkins_to_review'] as num?)?.toInt() ?? 0,
        adherence = (j['adherence'] as num?)?.toInt(),
        active = j['status'] == 'active',
        owner = j['is_owner'] == true;
  final Map j;
  final String id, name;
  final int n, max, review;
  final int? adherence;
  final bool active, owner;

  String get first => name.split(' ').first;
  String get initials => '${j['initials'] ?? ''}';
  String get color => '${j['avatar_color'] ?? 'c1'}';
  String? get avatar => j['avatar'] as String?;
  bool get full => active && max > 0 && n >= max;
  int get free => (max - n).clamp(0, 9999);
  double get load => max == 0 ? 0 : (n / max).clamp(0, 1).toDouble();

  /// Load bar colour on the board: full = red, 80% or more = amber, else blue.
  bool get high => !full && max > 0 && n * 100 / max >= 80;

  /// "Strength, fat loss": first speciality as written, the rest in lower case.
  String get spec {
    final s = [for (final x in (j['speciality'] as List?) ?? const []) '$x'];
    return s.isEmpty ? '' : [s.first, ...s.skip(1).map((x) => x.toLowerCase())].join(', ');
  }

  String get access => '${j['access_label'] ?? ''}';

  /// "12 Mar 2025"; the owner's row shows the month only ("Jan 2024").
  String get joined {
    final d = DateTime.tryParse('${j['joining_date'] ?? ''}');
    if (d == null) return '—';
    return DateFormat(owner ? 'MMM yyyy' : 'd MMM yyyy').format(d);
  }

  /// "You" next to the admin's own row.
  bool get isMe => id == Services.session.me?.id;
}

/// A Filter group: query key, label, options (value, label); the first option means "any".
class TrFilter {
  const TrFilter(this.key, this.label, this.options);
  final String key, label;
  final List<(String, String)> options;
}

/// Admin → Trainers (boards `Trainers` + `TrainersMobile`, D-48): sub-line and 4 stats from `trainers/summary/`,
/// tabs All / Active / Full / Inactive, search, Filter with chips, 20 a page (owner first, then by name).
class TrainersController extends ChangeNotifier {
  static const pageSize = 20;

  static const groups = [
    TrFilter('access', 'Access', [('', 'Any'), ('assigned', 'Assigned clients'), ('all', 'All clients'), ('custom', 'Custom')]),
    TrFilter('space', 'Space', [('', 'Any'), ('has_space', 'Has space'), ('full', 'Full')]),
    TrFilter('speciality', 'Speciality', [('', 'Any'), ('Fat loss', 'Fat loss'), ('Strength', 'Strength'), ('Muscle gain', 'Muscle gain'), ('Women', 'Women’s'), ('Beginners', 'Beginners')]),
    TrFilter('checkins', 'Check-ins', [('', 'Any'), ('to_review', 'Has check-ins to review'), ('reviewed', 'All reviewed')]),
  ];

  String tab = 'all', search = '';
  final filters = <String, String>{};
  List<TrRow> rows = [];
  Map<String, dynamic> summary = {};
  int count = 0, page = 1;
  bool loading = true;
  ApiError? error;
  Timer? _debounce;
  int _seq = 0;
  bool _disposed = false;

  int get activeFilters => filters.values.where((v) => v.isNotEmpty).length;
  bool get filtered => activeFilters > 0 || search.isNotEmpty;

  Map<String, int> get counts => {for (final e in ((summary['counts'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()};

  /// "Access: All clients" chips under the tools.
  List<(String, String)> get chips => [
        for (final g in groups)
          if ((filters[g.key] ?? '').isNotEmpty) (g.key, '${g.label}: ${g.options.firstWhere((o) => o.$1 == filters[g.key], orElse: () => ('', filters[g.key]!)).$2}'),
      ];

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final seq = ++_seq;
    loading = true;
    _notify();
    try {
      final res = await Future.wait([
        Services.api.get<Map>('trainers/', query: {'tab': tab, 'search': search, ...filters, 'page': page, 'page_size': pageSize}),
        Services.api.get<Map>('trainers/summary/'),
      ]);
      if (seq != _seq) return;
      rows = [for (final r in res[0]['results'] as List) TrRow(r as Map)];
      count = (res[0]['count'] as num?)?.toInt() ?? rows.length;
      summary = Map<String, dynamic>.from(res[1]);
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
    _notify();
  }

  void setTab(String t) {
    if (t == tab) return;
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
    page = p;
    load();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
