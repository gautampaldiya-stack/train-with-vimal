import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../home/home_model.dart' show clock, dayShort, inNum, litres;

/// Check-ins page (`GET me/checkins/?tab=&before=`): the daily and weekly cards, the numbers on top and
/// past check-ins. Sending, editing and Undo go through the outbox, so they work offline too.
class CheckinsController extends ChangeNotifier {
  CheckinsController() {
    _sent = () {
      if (Services.outbox.pending.value == 0 && _dirty) {
        _dirty = false;
        load();
      }
    };
    Services.outbox.pending.addListener(_sent);
  }

  static const _cacheKey = 'me/checkins';
  late final VoidCallback _sent;
  bool _dirty = false;

  String tab = 'weekly';
  CheckinsData? data;
  ApiError? error;
  final rows = <CkRow>[];
  bool hasMore = false, _more = false;
  String? _before;

  /// Saved in the outbox, waiting for the network (shown as sent).
  CkRow? queuedDaily, queuedWeekly;
  final _details = <String, Map<String, dynamic>>{};

  @override
  void dispose() {
    Services.outbox.pending.removeListener(_sent);
    super.dispose();
  }

  Future<void> start() async {
    final c = await Services.cache.read(_cacheKey);
    if (c is Map && data == null) {
      _take(c.cast<String, dynamic>());
      notifyListeners();
    }
    await load();
  }

  void pickTab(String t) {
    if (t == tab) return;
    tab = t;
    rows.clear();
    hasMore = false;
    notifyListeners();
    load();
  }

  void _take(Map<String, dynamic> j) {
    data = CheckinsData(j);
    rows
      ..clear()
      ..addAll([for (final r in (j['history'] as List? ?? [])) CkRow(r as Map<String, dynamic>)]);
    hasMore = j['has_more'] == true;
    _before = j['next_before'] as String?;
  }

  Future<void> load() async {
    final t = tab;
    try {
      final j = await Services.api.get<Map<String, dynamic>>('me/checkins/', query: {'tab': t});
      if (t != tab) return;
      if (t == 'weekly') unawaited(Services.cache.write(_cacheKey, j));
      _take(j);
      if (data!.daily.sent != null) queuedDaily = null;
      if (data!.weekly.sent != null) queuedWeekly = null;
      error = null;
    } on ApiError catch (e) {
      error = e;
    }
    notifyListeners();
  }

  /// Older rows when the list reaches its end.
  Future<void> loadMore() async {
    if (!hasMore || _more || _before == null) return;
    _more = true;
    final t = tab;
    try {
      final j = await Services.api.get<Map<String, dynamic>>('me/checkins/', query: {'tab': t, 'before': _before});
      if (t != tab) return;
      rows.addAll([for (final r in (j['history'] as List? ?? [])) CkRow(r as Map<String, dynamic>)]);
      hasMore = j['has_more'] == true;
      _before = j['next_before'] as String?;
      notifyListeners();
    } on ApiError {
      // Try again on the next scroll.
    } finally {
      _more = false;
    }
  }

  /// Answers and photos of one check-in (the past check-in sheet).
  Future<Map<String, dynamic>?> detail(String id) async {
    if (_details.containsKey(id)) return _details[id];
    try {
      final j = await Services.api.get<Map<String, dynamic>>('me/submissions/$id/');
      return _details[id] = j;
    } on ApiError {
      return null;
    }
  }

  Map<String, dynamic>? cachedDetail(String id) => _details[id];

  // ─────────────────────────────── Writes

  /// Sends a check-in. Returns the new row (id null while it waits offline).
  Future<CkRow> send(CkForm f, Map<String, dynamic> answers, {String note = '', Map<String, Map<String, String>>? photos}) async {
    final now = DateTime.now();
    final body = {
      'form': f.id,
      'answers': answers,
      if (note.isNotEmpty) 'note': note,
      if (photos != null && photos.isNotEmpty) 'photos': photos,
      'date': ymd(now),
    };
    final r = await Services.outbox.enqueue('POST', 'me/submissions/', body, tag: 'checkin:${f.type}');
    final metrics = _metrics(f, answers, note);
    final row = CkRow({
      'id': r is Map ? r['id'] : null,
      'kind': 'sent',
      'date': ymd(now),
      'sent_at': now.toIso8601String(),
      'week_number': data?.weekly.week,
      'metrics': r is Map ? r['metrics'] : metrics,
      'photo_count': r is Map ? r['photo_count'] : photos?.values.fold<int>(0, (n, m) => n + m.length) ?? 0,
      'reply': '',
      'reviewed': false,
    });
    if (r == null) {
      _dirty = true;
      if (f.type == 'daily') queuedDaily = row;
      if (f.type == 'weekly') queuedWeekly = row;
    } else {
      if (f.type == 'weekly') _details[row.id!] = r as Map<String, dynamic>;
      unawaited(load());
    }
    notifyListeners();
    return row;
  }

  /// Edit answers of today's daily check-in.
  Future<void> edit(CkForm f, String id, Map<String, dynamic> answers, {String note = ''}) async {
    final r = await Services.outbox.enqueue('PATCH', 'me/submissions/$id/', {'answers': answers, 'note': note}, tag: 'checkin:edit');
    final d = data?.daily;
    if (d?.sent != null && d!.sent!.id == id) d.sent!.metrics = _metrics(f, answers, note);
    _details.remove(id);
    if (r == null) {
      _dirty = true;
    } else {
      unawaited(load());
    }
    notifyListeners();
  }

  /// Undo on the "sent" toast.
  Future<void> undo(CkRow row, String type) async {
    if (type == 'daily') queuedDaily = null;
    if (type == 'weekly') queuedWeekly = null;
    if (row.id != null) {
      if (type == 'daily' && data?.daily.sent?.id == row.id) data!.daily.sent = null;
      if (type == 'weekly' && data?.weekly.sent?.id == row.id) data!.weekly.sent = null;
      notifyListeners();
      final r = await Services.outbox.enqueue('DELETE', 'me/submissions/${row.id}/', {}, tag: 'checkin:undo');
      if (r == null) _dirty = true;
    }
    unawaited(load());
  }

  Map<String, dynamic> _metrics(CkForm f, Map<String, dynamic> answers, String note) {
    final m = <String, dynamic>{};
    for (final q in f.questions) {
      final v = answers['${q.id}'];
      if (v == null || q.metric.isEmpty) continue;
      m[q.metric] = q.metric == 'sleep_hours' && v is String ? double.tryParse(v.split(' ').first) : v;
    }
    if (note.isNotEmpty) m['note'] = note;
    return m;
  }

  // ─────────────────────────────── Weekly draft (saved on the phone)

  String _draftKey(int week) => 'checkin:weekly:$week';
  Future<Map<String, dynamic>?> readDraft(int week) async {
    final d = await Services.cache.read(_draftKey(week));
    return d is Map ? d.cast<String, dynamic>() : null;
  }

  Future<void> saveDraft(int week, Map<String, dynamic>? d) async {
    await Services.cache.write(_draftKey(week), d);
    data?.weekly.draft = d;
    notifyListeners();
  }
}

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

double? _num(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

/// "−0.6 kg" / "+0.3 kg" / "No change"
String kgChange(double d, {String zero = 'No change'}) {
  final r = (d * 10).round() / 10;
  if (r == 0) return zero;
  return '${r < 0 ? '−' : '+'}${r.abs().toStringAsFixed(1)} kg';
}

String kg(double v) => '${v.toStringAsFixed(1)} kg';

/// "7 h", "6.5 h"
String hrs(num v) => '${v == v.roundToDouble() ? v.round() : v} h';

String sentStamp(DateTime t) => '${dayShort(t)}, ${clock(t)}';

class CheckinsData {
  CheckinsData(this.j) : daily = CkDaily(j['daily'] as Map<String, dynamic>? ?? {}), weekly = CkWeekly(j['weekly'] as Map<String, dynamic>? ?? {});
  final Map<String, dynamic> j;
  final CkDaily daily;
  final CkWeekly weekly;

  Map<String, dynamic>? get _coach => j['coach'] as Map<String, dynamic>?;
  String get coachFirst => (_coach?['first_name'] as String?) ?? 'Your coach';
  String get coachName => (_coach?['name'] as String?) ?? 'Your coach';
  String get coachInitials => (_coach?['initials'] as String?) ?? '';
  String get coachLower => _coach == null ? 'your coach' : coachFirst;

  /// "Aman reads every one · Fat loss · 8 weeks, week 7 of 8"
  String get sub {
    final p = j['program'] as Map<String, dynamic>?;
    final who = '$coachFirst reads every one';
    if (p == null) return who;
    return '$who · ${p['name']}, week ${p['week']} of ${p['weeks']}';
  }

  Map<String, dynamic> get _stats => j['stats'] as Map<String, dynamic>? ?? {};
  int get streak => (_stats['streak'] as num?)?.toInt() ?? 0;
  List<(String, String)> cells(bool dailySentNow) {
    final s = streak;
    final due = (_stats['weekly_due'] as num?)?.toInt() ?? 0;
    final ch = _num(_stats['last_change_kg']);
    return [
      ('$s ${s == 1 ? 'day' : 'days'}', 'Daily streak'),
      (due == 0 ? '—' : '${_stats['weekly_on_time']} of $due', 'Weekly on time'),
      (ch == null ? '—' : kgChange(ch, zero: '0.0 kg'), 'Last weekly change'),
    ];
  }
}

class CkDaily {
  CkDaily(this.j)
    : form = j['form'] == null ? null : CkForm(j['form'] as Map<String, dynamic>),
      sent = j['sent'] == null ? null : CkRow(j['sent'] as Map<String, dynamic>);
  final Map<String, dynamic> j;
  final CkForm? form;
  CkRow? sent;
  DateTime get date => DateTime.tryParse('${j['date']}') ?? DateTime.now();
  int? get steps => (j['steps'] as num?)?.toInt();
  int? get waterMl => (j['water_ml'] as num?)?.toInt();
  double? get todayWeight => _num(j['today_weight']);
  double? get lastWeight => _num((j['last_weight'] as Map?)?['kg']);
  DateTime? get lastWeightDate => DateTime.tryParse('${(j['last_weight'] as Map?)?['date']}');
}

class CkWeekly {
  CkWeekly(this.j)
    : form = j['form'] == null ? null : CkForm(j['form'] as Map<String, dynamic>),
      sent = j['sent'] == null ? null : CkRow(j['sent'] as Map<String, dynamic>);
  final Map<String, dynamic> j;
  final CkForm? form;
  CkRow? sent;
  Map<String, dynamic>? draft;
  int get week => (j['week'] as num?)?.toInt() ?? 1;
  DateTime get dueAt => (DateTime.tryParse('${j['due_at']}') ?? DateTime.now()).toLocal();
  double? get lastWeight => _num(j['last_weight']);

  /// "Sun, 18 Oct, 6:00 pm"
  String get due => '${dayShort(dueAt)}, ${clock(dueAt)}';
}

class CkForm {
  CkForm(this.j) : questions = [for (final q in (j['questions'] as List? ?? [])) CkQ(q as Map<String, dynamic>)];
  final Map<String, dynamic> j;
  final List<CkQ> questions;
  String get id => '${j['id']}';
  String get type => '${j['type']}';
  CkQ? byMetric(String m) => questions.where((q) => q.metric == m).firstOrNull;
}

class CkQ {
  CkQ(this.j);
  final Map<String, dynamic> j;
  int get id => (j['id'] as num).toInt();
  String get text => '${j['text']}';
  String get type => '${j['type']}';
  String get help => '${j['help_text'] ?? ''}';
  String get metric => '${j['metric'] ?? ''}';
  String get chip => '${j['chip'] ?? text}';
  bool get required => j['required'] == true;
  List<String> get options => type == 'yes_no' ? const ['Yes', 'No'] : [for (final o in (j['options'] as List? ?? [])) '$o'];
  List<String> get labels {
    final l = [for (final o in (j['scale_labels'] as List? ?? [])) '$o'];
    return l.length == 5 ? l : const ['', '', '', '', ''];
  }

  bool get isChoice => type == 'single' || type == 'dropdown' || type == 'yes_no';

  /// An answer as text: "4 / 5 · Good", "71.6 kg", "Yes, all week".
  String? show(Object? v, {bool short = false}) {
    if (v == null || v == '' || (v is List && v.isEmpty)) return null;
    if (type == 'scale' && v is num) {
      final l = labels[v.toInt() - 1];
      return short ? l : '${v.toInt()} / 5${l.isEmpty ? '' : ' · $l'}';
    }
    if (metric == 'weight' && v is num) return kg(v.toDouble());
    if (type == 'yes_no' && v is bool) return v ? 'Yes' : 'No';
    if (v is List) return v.join(', ');
    return '$v';
  }
}

class CkRow {
  CkRow(this.j) : metrics = (j['metrics'] as Map?)?.cast<String, dynamic>() ?? {};
  final Map<String, dynamic> j;
  Map<String, dynamic> metrics;
  String? get id => j['id'] as String?;
  bool get missed => j['kind'] == 'missed';
  DateTime get date => DateTime.tryParse('${j['date']}') ?? DateTime.now();
  DateTime? get sentAt => DateTime.tryParse('${j['sent_at']}')?.toLocal();
  int? get week => (j['week_number'] as num?)?.toInt();
  bool get reviewed => j['reviewed'] == true;
  String get reply => '${j['reply'] ?? ''}';
  DateTime? get reviewedAt => DateTime.tryParse('${j['reviewed_at']}')?.toLocal();
  int get photos => (j['photo_count'] as num?)?.toInt() ?? 0;
  double? get weight => _num(metrics['weight']);
  double? get change => _num(j['change_kg']);
  int get changeWeeks => (j['change_weeks'] as num?)?.toInt() ?? 1;
  int? get steps => (j['steps'] as num?)?.toInt();
  int? get waterMl => (j['water_ml'] as num?)?.toInt();
  String get reminder => '${j['reminder'] ?? '9:00 pm'}';
  bool get waiting => !missed && !reviewed;

  /// Weekly row: Weight, Change, Workouts, Meals on plan.
  List<(String, String)> get weekCells {
    final wd = j['workouts_done'], wp = j['workouts_planned'], mp = j['meals_pct'];
    return [
      (weight == null ? '—' : kg(weight!), 'Weight'),
      (change == null ? '—' : kgChange(change!), changeWeeks > 1 ? 'In $changeWeeks weeks' : 'Change'),
      (wp == null || wp == 0 ? '—' : '$wd / $wp', 'Workouts'),
      (mp == null ? '—' : '$mp%', 'Meals on plan'),
    ];
  }

  String get stepsText => steps == null ? '—' : inNum(steps!);
  String get waterText => waterMl == null ? '—' : litres(waterMl!);
}
