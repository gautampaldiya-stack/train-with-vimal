import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';

/// One row of the client Library (`GET me/library/`).
class LbItem {
  LbItem(this.j);
  final Map<String, dynamic> j;
  String get id => '${j['id']}';
  String get kind => '${j['kind']}';
  String get title => '${j['title']}';
  String get description => '${j['description'] ?? ''}';
  String get length => '${j['length'] ?? ''}';
  String get by => '${j['by'] ?? ''}';
  String get source => '${j['source'] ?? ''}';
  String get note => '${j['note'] ?? ''}';
  String get noteBy => '${j['note_by'] ?? ''}';
  String get noteInitials => '${j['note_initials'] ?? ''}';
  bool get isNew => j['new'] == true;
  bool get done => j['done'] == true;
  bool get saved => j['saved'] == true;
  set isNew(bool v) => j['new'] = v;
  set done(bool v) => j['done'] = v;
  set saved(bool v) => j['saved'] = v;

  /// "Video · 3:05 · by Aman Verma".
  String get meta => '${lbKind(kind)} · $length · by $by';

  // Item sheet (`GET me/library/<id>/`)
  List<String> get body => [for (final p in (j['body'] as List? ?? const [])) '$p'];
  List<(int, String)> get chapters => [for (final c in (j['chapters'] as List? ?? const [])) (((c as List)[0] as num).toInt(), '${c[1]}')];
  List<(String, String)> get outline => [for (final p in (j['outline'] as List? ?? const [])) ('${(p as List)[0]}', '${p[1]}')];
  String get fileUrl => '${j['file_url'] ?? ''}';
  String get fileName => '${j['file_name'] ?? ''}';
  String get youtube => '${j['youtube_url'] ?? ''}';
  int get duration => (j['duration'] as num?)?.toInt() ?? 0;
}

String lbKind(String k) => const {'video': 'Video', 'pdf': 'PDF', 'image': 'Image', 'article': 'Article'}[k] ?? k;

/// "0:48".
String lbClock(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

/// Filters: id, label (board order).
const lbFilters = [('all', 'All'), ('video', 'Videos'), ('pdf', 'PDFs'), ('image', 'Images'), ('article', 'Articles'), ('saved', 'Saved')];

class LibraryController extends ChangeNotifier {
  LibraryController() {
    _rt = Services.realtime.events.where((e) => e.event == 'notification').listen((_) => load());
  }

  static const _cacheKey = 'me/library';
  late final StreamSubscription _rt;
  Timer? _debounce;
  int _seq = 0;

  String kind = 'all', q = '';
  List<LbItem>? items;
  Map<String, int> counts = const {};
  int total = 0, doneCount = 0, newCount = 0;
  String coach = 'your coach', coachInitials = 'TV';
  List<Map<String, dynamic>> notes = const [];
  ApiError? error;

  @override
  void dispose() {
    _rt.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> start() async {
    final c = await Services.cache.read(_cacheKey);
    if (c is Map && items == null) _apply(c.cast<String, dynamic>());
    await load();
  }

  void _apply(Map<String, dynamic> j) {
    items = [for (final r in (j['results'] as List? ?? const [])) LbItem((r as Map).cast<String, dynamic>())];
    counts = {for (final e in ((j['counts'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()};
    total = (j['total'] as num?)?.toInt() ?? 0;
    doneCount = (j['done'] as num?)?.toInt() ?? 0;
    newCount = (j['new'] as num?)?.toInt() ?? 0;
    coach = '${j['coach_first'] ?? 'your coach'}';
    coachInitials = '${j['coach_initials'] ?? 'TV'}';
    notes = [for (final n in (j['notes'] as List? ?? const [])) (n as Map).cast<String, dynamic>()];
    notifyListeners();
  }

  Future<void> load() async {
    final n = ++_seq;
    try {
      final j = await Services.api.get<Map<String, dynamic>>('me/library/', query: {'kind': kind, if (q.isNotEmpty) 'q': q});
      if (n != _seq) return;
      if (kind == 'all' && q.isEmpty) unawaited(Services.cache.write(_cacheKey, j));
      error = null;
      _apply(j);
    } on ApiError catch (e) {
      if (n != _seq) return;
      error = e;
      notifyListeners();
    }
  }

  void setKind(String k) {
    kind = k;
    load();
  }

  void setQuery(String v, {bool now = false}) {
    q = v.trim().toLowerCase();
    _debounce?.cancel();
    if (now) {
      load();
    } else {
      _debounce = Timer(const Duration(milliseconds: 250), load);
    }
    notifyListeners();
  }

  void reset() {
    kind = 'all';
    setQuery('', now: true);
  }

  LbItem? byId(String id) => items?.where((x) => x.id == id).firstOrNull;

  /// The item sheet's data; opening it marks the item as read.
  Future<LbItem> open(String id) async {
    final j = await Services.api.get<Map<String, dynamic>>('me/library/$id/');
    final row = byId(id);
    if (row != null && row.isNew) {
      row.isNew = false;
      newCount = (newCount - 1).clamp(0, total);
      notifyListeners();
    }
    return LbItem(j);
  }

  Future<void> _progress(String id, Map<String, dynamic> body) =>
      Services.outbox.enqueue('POST', 'me/library/$id/progress/', body, tag: 'library:progress');

  /// Save for later on / off (the row and the Saved count change at once).
  Future<void> setSaved(LbItem x, bool on) async {
    for (final r in [x, ?byId(x.id)]) {
      r.saved = on;
    }
    counts = {...counts, 'saved': ((counts['saved'] ?? 0) + (on ? 1 : -1)).clamp(0, total)};
    if (kind == 'saved' && !on) items = items?.where((r) => r.id != x.id).toList();
    notifyListeners();
    await _progress(x.id, {'saved': on});
    if (kind == 'saved' && on) unawaited(load());
  }

  /// Mark as done / Done · undo.
  Future<void> setDone(LbItem x, bool on) async {
    final was = byId(x.id)?.done ?? x.done;
    for (final r in [x, ?byId(x.id)]) {
      r.done = on;
    }
    if (was != on) doneCount = (doneCount + (on ? 1 : -1)).clamp(0, total);
    notifyListeners();
    await _progress(x.id, {'finished': on});
  }

  Future<void> watched(String id, int pct) => _progress(id, {'progress': pct.clamp(0, 100)});
}
