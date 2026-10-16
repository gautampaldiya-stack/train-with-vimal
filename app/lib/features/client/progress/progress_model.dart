import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../food/food_model.dart' show DateUtils0, ymd;

/// Client Progress tab (boards `ClientProgress` / `ClientProgressWeb`): `GET me/progress/` in one answer.
/// The weight chart's range (4 wk / 12 wk / 6 mo / All) is filtered here, so switching it needs no request.

double _n(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? 0 : 0);
double? _nn(Object? v) => v == null ? null : _n(v);
DateTime _d(Object? v) => DateTime.tryParse('$v') ?? DateUtils0.dateOnly(DateTime.now());

/// "12 Jan"
String pxDm(DateTime d) => DateFormat('d MMM').format(d);

/// "Mon, 12 Jan"
String pxWdm(DateTime d) => DateFormat('EEE, d MMM').format(d);

/// "71.2" (one decimal, always)
String pxK1(double v) => ((v * 10).round() / 10).toStringAsFixed(1);

/// "−0.4 kg" · "+15 kg" · "−10 cm" · "−5%". [unit] 'kg' keeps one decimal; 'kgs' (lifts), 'cm' and '%' drop a 0.
String pxChg(double v, String unit) {
  final r = (v * 10).round() / 10;
  final sign = r > 0 ? '+' : (r < 0 ? '−' : '±');
  return '$sign${pxAmt(r.abs(), unit)}';
}

String pxAmt(double v, String unit) {
  final r = (v * 10).round() / 10;
  final s = r == r.roundToDouble() ? '${r.round()}' : '$r';
  return switch (unit) {
    'kg' => '${pxK1(v)} kg',
    'kgs' => '$s kg',
    '%' => '$s%',
    _ => '$s $unit',
  };
}

class PxWeight {
  PxWeight(this.date, this.kg, {this.id});
  final DateTime date;
  final double kg;
  final int? id;
}

class PxMeasure {
  PxMeasure(Map<String, dynamic> j)
    : date = _d(j['date']),
      v = {for (final e in j.entries) if (e.key != 'date' && e.value is num) e.key: (e.value as num).toDouble()};
  PxMeasure.local(this.date, this.v);
  final DateTime date;
  final Map<String, double> v;

  /// The values of one measurement (two for a left / right pair); null when any is missing.
  List<double>? of(PxMetric m) {
    final out = [for (final k in m.keys) v[k]];
    return out.any((x) => x == null) ? null : out.cast<double>();
  }
}

/// One line of measurements: a single key, or a left / right pair shown together ("Bicep L · R").
class PxMetric {
  const PxMetric(this.keys, this.label, this.unit, {this.tracked = true});
  final List<String> keys;
  final String label, unit;
  final bool tracked;
  bool get pair => keys.length == 2;
  String get key => keys.first;

  /// "79.5 cm" · "28.5 · 29 cm" ([unit] false drops the unit, for tables).
  String amt(List<double> v, {bool unit = true}) =>
      pair ? '${pxAmt(v[0], '')} · ${pxAmt(v[1], '')}${unit ? ' ${this.unit}' : ''}'.replaceAll('  ', ' ').trim() : (unit ? pxAmt(v[0], this.unit) : pxAmt(v[0], '').trim());

  /// "−1 cm" · "−1 · −0.5 cm"
  String chg(List<double> a, List<double> b) =>
      pair ? '${pxChg(b[0] - a[0], '').trim()} · ${pxChg(b[1] - a[1], '').trim()} $unit' : pxChg(b[0] - a[0], unit);

  /// Sum of the change (sign for the colour).
  double delta(List<double> a, List<double> b) => [for (var i = 0; i < a.length; i++) b[i] - a[i]].fold(0.0, (x, y) => x + y);
}

/// Every measurement in board order: key, label, unit. Left / right pairs are joined in [pxGroup].
const pxMeasureKeys = [
  ('neck', 'Neck', 'cm'), ('chest', 'Chest', 'cm'), ('abdomen', 'Abdomen (navel)', 'cm'), ('waist', 'Waist', 'cm'),
  ('hips', 'Hips', 'cm'), ('bicep_l', 'Left bicep', 'cm'), ('bicep_r', 'Right bicep', 'cm'), ('thigh_l', 'Left thigh', 'cm'),
  ('thigh_r', 'Right thigh', 'cm'), ('calf_l', 'Left calf', 'cm'), ('calf_r', 'Right calf', 'cm'), ('body_fat', 'Body fat', '%'),
];
const _defaultMeasures = ['waist', 'hips', 'chest', 'bicep_l', 'bicep_r', 'body_fat'];

/// Joins `x_l` + `x_r` into one "X (L · R)" line; [keys] with their tracked flag, in board order.
List<PxMetric> pxGroup(Map<String, bool> keys) {
  final out = <PxMetric>[];
  for (final (k, l, u) in pxMeasureKeys) {
    if (!keys.containsKey(k) || k.endsWith('_r') && keys.containsKey('${k.substring(0, k.length - 2)}_l')) continue;
    if (k.endsWith('_l') && keys.containsKey('${k.substring(0, k.length - 2)}_r')) {
      final base = k.substring(0, k.length - 2);
      out.add(PxMetric([k, '${base}_r'], '${base[0].toUpperCase()}${base.substring(1)} L · R', u, tracked: keys[k]! || keys['${base}_r']!));
    } else {
      out.add(PxMetric([k], l, u, tracked: keys[k]!));
    }
  }
  return out;
}

class PxLift {
  PxLift(Map<String, dynamic> j)
    : name = '${j['name']}',
      bestKg = _n((j['best'] as Map?)?['kg']),
      bestReps = ((j['best'] as Map?)?['reps'] as num?)?.toInt(),
      ups = (j['ups'] as num?)?.toInt() ?? 0,
      note = '${j['note'] ?? ''}',
      last = _d(j['last']),
      series = [for (final s in (j['series'] as List? ?? const [])) PxWeight(_d((s as Map)['date']), _n(s['kg']))];
  final String name, note;
  final double bestKg;
  final int? bestReps;
  final int ups;
  final DateTime last;
  final List<PxWeight> series;

  String get bestSet => bestReps == null ? pxAmt(bestKg, 'kgs') : '${pxAmt(bestKg, 'kgs')} × $bestReps';
  PxWeight get first => series.first;
  double get gain => series.isEmpty ? 0 : series.last.kg - series.first.kg;
  int get weeks => series.length < 2 ? 1 : ((series.last.date.difference(series.first.date).inDays) / 7).round().clamp(1, 999);
}

class PxWeek {
  PxWeek(Map<String, dynamic> j)
    : start = _d(j['start']),
      done = (j['done'] as num?)?.toInt() ?? 0,
      planned = (j['planned'] as num?)?.toInt() ?? 0,
      pct = (j['pct'] as num?)?.toInt();
  final DateTime start;
  final int done, planned;
  final int? pct;
}

class PxAdherence {
  PxAdherence(Map<String, dynamic> j)
    : program = j['program'] as String?,
      since = j['since'] == null ? null : _d(j['since']),
      done = (j['done'] as num?)?.toInt() ?? 0,
      planned = (j['planned'] as num?)?.toInt() ?? 0,
      missed = [for (final d in (j['missed'] as List? ?? const [])) _d(d)],
      today = '${j['today'] ?? ''}',
      weeks = [for (final w in (j['weeks'] as List? ?? const [])) PxWeek((w as Map).cast<String, dynamic>())];
  final String? program;
  final DateTime? since;
  final int done, planned;
  final List<DateTime> missed;
  final String today;
  final List<PxWeek> weeks;

  int? get avg {
    final p = [for (final w in weeks) if (w.pct != null) w.pct!];
    return p.isEmpty ? null : (p.reduce((a, b) => a + b) / p.length).round();
  }
}

const pxPoses = ['Front', 'Side', 'Back'];

class PxPhoto {
  PxPhoto(Map<String, dynamic> j)
    : id = (j['id'] as num?)?.toInt() ?? 0,
      pose = _cap('${j['pose']}'),
      image = '${j['image'] ?? ''}';
  PxPhoto.local(this.pose, this.image) : id = 0;
  final int id;
  final String pose, image;
  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class PxSet {
  PxSet(Map<String, dynamic> j)
    : id = '${j['id']}',
      label = '${j['label'] ?? 'Progress photos'}',
      date = _d(j['date']),
      kg = _nn(j['weight_kg']),
      photos = [for (final p in (j['photos'] as List? ?? const [])) PxPhoto((p as Map).cast<String, dynamic>())];
  PxSet.local({required this.id, required this.label, required this.date, required this.kg, required this.photos});
  final String id, label;
  final DateTime date;
  final double? kg;
  final List<PxPhoto> photos;

  PxPhoto? of(String pose) => photos.where((p) => p.pose == pose).firstOrNull;
  bool has(String pose) => of(pose) != null;

  /// A colour per set for the placeholder tiles (`t1`–`t4` on the board), so sets read apart.
  int get tint => (date.day + date.month) % 4;
  String get shortLabel => label.replaceAll(' check-in', '');
}

class PxData {
  PxData(this.j)
    : weights = [for (final w in (j['weights'] as List? ?? const [])) PxWeight(_d((w as Map)['date']), _n(w['kg']), id: (w['id'] as num?)?.toInt())],
      measures = [for (final m in (j['measurements'] as List? ?? const [])) PxMeasure((m as Map).cast<String, dynamic>())],
      lifts = [for (final l in (j['lifts'] as List? ?? const [])) PxLift((l as Map).cast<String, dynamic>())],
      adherence = PxAdherence(((j['adherence'] as Map?) ?? const {}).cast<String, dynamic>()),
      sets = [for (final s in (j['photo_sets'] as List? ?? const [])) PxSet((s as Map).cast<String, dynamic>())];
  final Map<String, dynamic> j;
  List<PxWeight> weights;
  List<PxMeasure> measures;

  /// The lines of the Body tab: what the coach asks for plus anything already logged (`measures` from the server).
  List<PxMetric> get metrics {
    final ms = j['measures'] as List?;
    if (ms == null) return pxGroup({for (final k in _defaultMeasures) k: true});
    return pxGroup({for (final m in ms.cast<Map>()) '${m['key']}': m['tracked'] != false});
  }

  /// Only what the coach asks for (the Log measurements sheet).
  List<PxMetric> get tracked => metrics.where((m) => m.tracked).toList();
  final List<PxLift> lifts;
  final PxAdherence adherence;
  List<PxSet> sets;

  String get coach => '${j['coach'] ?? ''}'.isEmpty ? 'your coach' : '${j['coach']}';
  double? get startKg => _nn((j['start'] as Map?)?['kg']) ?? weights.firstOrNull?.kg;
  DateTime get startDate => (j['start'] as Map?)?['date'] == null ? (weights.firstOrNull?.date ?? DateTime.now()) : _d((j['start'] as Map)['date']);
  PxWeight? get last => weights.lastOrNull;
  double? get goal => _nn((j['goal'] as Map?)?['kg']);
  DateTime? get goalEta => (j['goal'] as Map?)?['eta'] == null ? null : _d((j['goal'] as Map)['eta']);
  DateTime get nextMeasure => _d((j['next_measure'] as Map?)?['date']);
  /// Photos page "Next set due": 2 weeks after the last photo set, on that week's Sunday.
  DateTime get nextPhotos => (j['next_photos'] as Map?)?['date'] == null ? nextMeasure : _d((j['next_photos'] as Map)['date']);
  int get measureEvery => (((j['next_measure'] as Map?)?['every_weeks']) as num?)?.toInt() ?? 2;
  int get nextMeasureWeek => (((j['next_measure'] as Map?)?['week']) as num?)?.toInt() ?? 1;

  /// The weigh-in on or before [d].
  PxWeight? weightAt(DateTime d) => weights.where((w) => !w.date.isAfter(d)).lastOrNull;

  /// The measurement row nearest before (or on) [d], else the first one.
  PxMeasure? measureAt(DateTime d) => measures.where((m) => !m.date.isAfter(d)).lastOrNull ?? measures.firstOrNull;
}

/// Loads `me/progress/` (cached for offline) and does the tab's writes through the outbox.
class ProgressController extends ChangeNotifier {
  ProgressController() {
    _results = Services.outbox.results.listen((r) {
      if (r.error == null && data != null && (r.tag.startsWith('progress:') || r.tag.startsWith('checkin'))) load();
    });
  }

  static const _cacheKey = 'me/progress';
  late final StreamSubscription _results;
  PxData? data;
  ApiError? error;
  int _seq = 0;

  DateTime get today => DateUtils0.dateOnly(DateTime.now());

  @override
  void dispose() {
    _results.cancel();
    super.dispose();
  }

  Future<void> start() async {
    final c = await Services.cache.read(_cacheKey);
    if (c is Map && data == null) {
      data = PxData(c.cast<String, dynamic>());
      notifyListeners();
    }
    await load();
  }

  Future<void> load() async {
    final n = ++_seq;
    try {
      final j = await Services.api.get<Map<String, dynamic>>('me/progress/');
      if (n != _seq) return;
      unawaited(Services.cache.write(_cacheKey, j));
      data = PxData(j);
      error = null;
    } on ApiError catch (e) {
      if (n != _seq) return;
      error = e;
    }
    notifyListeners();
  }

  /// Log weight sheet: one weigh-in a day, a second one replaces it. Shows at once, syncs later offline.
  Future<void> logWeight(DateTime day, double kg) async {
    final d = data;
    if (d != null) {
      d.weights = [...d.weights.where((w) => !DateUtils0.same(w.date, day)), PxWeight(day, kg)]..sort((a, b) => a.date.compareTo(b.date));
      notifyListeners();
    }
    await Services.outbox.enqueue('POST', 'me/weights/', {'date': ymd(day), 'weight_kg': (kg * 10).round() / 10}, tag: 'progress:weight');
  }

  /// Undo of a weigh-in: put the list back as it was and send the old value (or delete the new day).
  Future<void> undoWeight(List<PxWeight> before, DateTime day) async {
    final d = data;
    if (d == null) return;
    d.weights = before;
    notifyListeners();
    final old = before.where((w) => DateUtils0.same(w.date, day)).firstOrNull;
    if (old != null) {
      await Services.outbox.enqueue('POST', 'me/weights/', {'date': ymd(day), 'weight_kg': old.kg}, tag: 'progress:weight');
    } else {
      try {
        final j = await Services.api.get<List<dynamic>>('me/weights/');
        final row = j.cast<Map>().where((w) => w['date'] == ymd(day)).firstOrNull;
        if (row != null) await Services.outbox.enqueue('DELETE', 'me/weights/${row['id']}/', {}, tag: 'progress:weight');
      } on ApiError {
        // Offline: the weigh-in stays; it can be logged again.
      }
    }
  }

  /// Log measurements sheet: merges into that day's row (null takes a key off). Shows at once, syncs later offline.
  Future<void> logMeasures(DateTime day, Map<String, double?> values) async {
    final d = data;
    if (d != null) {
      final i = d.measures.indexWhere((m) => DateUtils0.same(m.date, day));
      final v = {...?(i >= 0 ? d.measures[i].v : null)};
      values.forEach((k, n) => n == null ? v.remove(k) : v[k] = n);
      final rest = [...d.measures.where((m) => !DateUtils0.same(m.date, day))];
      d.measures = [...rest, if (v.isNotEmpty) PxMeasure.local(day, v)]..sort((a, b) => a.date.compareTo(b.date));
      notifyListeners();
    }
    await Services.outbox.enqueue('POST', 'me/measurements/', {'date': ymd(day), 'values': values}, tag: 'progress:measure');
  }

  /// Add photos sheet: one pose into today's set (data URL, so it can wait in the outbox).
  Future<Map<String, dynamic>?> addPhoto(String pose, String dataUrl) async {
    final d = data;
    if (d != null) {
      final t = today;
      final i = d.sets.indexWhere((s) => DateUtils0.same(s.date, t));
      final photo = PxPhoto.local(pose, dataUrl);
      if (i >= 0) {
        final s = d.sets[i];
        d.sets[i] = PxSet.local(id: s.id, label: s.label, date: s.date, kg: s.kg, photos: [...s.photos.where((p) => p.pose != pose), photo]);
      } else {
        d.sets = [...d.sets, PxSet.local(id: 'local', label: 'Added by you', date: t, kg: d.last?.kg, photos: [photo])];
      }
      notifyListeners();
    }
    final r = await Services.outbox.enqueue('POST', 'me/photos/', {'pose': pose.toLowerCase(), 'image': dataUrl}, tag: 'progress:photo');
    return r is Map ? r.cast<String, dynamic>() : null;
  }

  Future<void> deletePhoto(int id) async {
    await Services.outbox.enqueue('DELETE', 'me/photos/?id=$id', {}, tag: 'progress:photo');
    await load();
  }
}

// ─────────────────────────────── History

class PxEntry {
  PxEntry(this.j);
  final Map<String, dynamic> j;
  String get type => '${j['type']}';
  String get title => '${j['title']}';
  String get sub => '${j['sub'] ?? ''}';
  String get badge => '${j['badge'] ?? ''}';
  String get badgeColor => '${j['badge_color'] ?? ''}';
  String get note => '${j['note'] ?? ''}';
  bool get missed => j['missed'] == true;
  List<(String, String)> get detail => [for (final r in (j['detail'] as List? ?? const [])) ('${(r as List)[0]}', '${r[1]}')];
}

class PxDay {
  PxDay(Map<String, dynamic> j)
    : date = _d(j['date']),
      score = (j['score'] as num?)?.toInt(),
      entries = [for (final e in (j['entries'] as List? ?? const [])) PxEntry((e as Map).cast<String, dynamic>())];
  final DateTime date;
  final int? score;
  final List<PxEntry> entries;
}

/// History page: `GET me/history/?range=&type=&offset=&limit=`, newest day first, 7 days then 10 more at a time.
class HistoryController extends ChangeNotifier {
  HistoryController({this.type});

  static const ranges = [('week', 'This week'), ('month', 'Month'), ('3months', '3 months')];
  static const types = [(null, 'All'), ('workout', 'Workouts'), ('meal', 'Meals'), ('checkin', 'Check-ins'), ('weight', 'Weight')];

  String range = 'week';
  String? type;
  final List<PxDay> days = [];
  Map<String, dynamic> summary = const {};
  DateTime? from, to;
  int count = 0;
  bool loading = true, loadingMore = false;
  ApiError? error;
  int _seq = 0;

  Future<void> load({bool more = false}) async {
    final n = ++_seq;
    if (more) {
      loadingMore = true;
    } else {
      loading = true;
    }
    notifyListeners();
    try {
      final j = await Services.api.get<Map<String, dynamic>>('me/history/', query: {
        'range': range,
        'type': ?type,
        'offset': more ? days.length : 0,
        'limit': more ? 10 : 7,
      });
      if (n != _seq) return;
      if (!more) days.clear();
      days.addAll([for (final d in (j['days'] as List? ?? const [])) PxDay((d as Map).cast<String, dynamic>())]);
      summary = ((j['summary'] as Map?) ?? const {}).cast<String, dynamic>();
      count = (j['count'] as num?)?.toInt() ?? days.length;
      from = _d(j['from']);
      to = _d(j['to']);
      error = null;
    } on ApiError catch (e) {
      if (n != _seq) return;
      error = e;
    }
    loading = false;
    loadingMore = false;
    notifyListeners();
  }

  void setRange(String r) {
    range = r;
    load();
  }

  void setType(String? t) {
    type = t;
    load();
  }
}
