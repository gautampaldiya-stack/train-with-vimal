import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/util/input_rules.dart';

/// One question of the setup steps, as `me/onboarding/` sends it (`fields`): the gym's coaching form (D-36).
/// The admin can edit the onboarding form, so the words, the required mark and which questions are asked come from
/// the server; the app only knows how to draw each kind.
class SetupField {
  SetupField(Map j)
      : key = '${j['key']}',
        step = '${j['step']}',
        kind = '${j['kind']}',
        label = '${j['label'] ?? ''}',
        help = '${j['help'] ?? ''}',
        required = j['required'] == true,
        other = j['other'] as String?,
        min = (j['min'] as num?)?.toDouble(),
        max = (j['max'] as num?)?.toDouble(),
        maxLen = (j['max_len'] as num?)?.toInt() ?? 2000,
        options = [for (final o in (j['options'] as List? ?? const [])) ('${o['value']}', '${o['label']}', o['line'] as String?)];
  final String key, step, kind, label, help;
  final bool required;
  final String? other;
  final double? min, max;
  final int maxLen;
  final List<(String, String, String?)> options;

  String optLabel(Object? v) => options.where((o) => o.$1 == '$v').firstOrNull?.$2 ?? '$v';
  bool isOption(Object? v) => options.any((o) => o.$1 == '$v');
}

/// An extra question the admin added to the onboarding form (no profile field): asked on the last step.
class SetupExtra {
  SetupExtra(Map j)
      : id = '${j['id']}',
        text = '${j['text']}',
        type = '${j['type']}',
        help = '${j['help'] ?? ''}',
        required = j['required'] == true,
        options = [for (final o in (j['options'] as List? ?? const [])) '$o'],
        scale = [for (final o in (j['scale_labels'] as List? ?? const [])) '$o'];
  final String id, text, type, help;
  final bool required;
  final List<String> options, scale;
}

/// Profile setup answers (9 steps). Loaded from / saved to `me/onboarding/` (decisions D-14, D-36).
class SetupState extends ChangeNotifier {
  SetupState._();
  static final instance = SetupState._();

  static const keys = ['goal', 'about', 'training', 'health', 'food', 'meals', 'supplements', 'body', 'agree'];
  static const titles = ['Your goal', 'About you', 'Training', 'Health & injuries', 'Food & lifestyle', 'Your day of eating', 'Supplements & medicines', 'Measurements & photos', 'Last step'];
  static const shorts = ['Goal', 'About you', 'Training', 'Health', 'Food', 'Meals', 'Supplements', 'Measurements', 'Last step'];
  static const subs = [
    'Main goal and training experience',
    'Plan length, contact, birthday, body',
    'Days, place, time, activity level',
    'Injuries, surgeries, conditions, stress',
    'Diet, usual foods, allergies, smoking',
    'What you eat at each meal now',
    'What you take and how often',
    'Body measurements in cm, 3 photos',
    'A note for your coach, terms',
  ];
  static int get count => keys.length;

  // Goal cards and diet marks as on the board; the words come from the server.
  static const goals = [
    ('fat_loss', 'Lose fat', 'Lean down, keep muscle', 'Calorie deficit with strength training: lose fat, keep muscle.'),
    ('muscle_gain', 'Build muscle', 'Size & shape', 'A small surplus with progressive overload: size and shape.'),
    ('strength', 'Get stronger', 'Hit new PRs', 'Low reps and heavy compound lifts to beat your records.'),
    ('recomp', 'Recomp', 'Lose fat + gain muscle', 'Slow and steady: fat down, muscle up.'),
    ('general', 'Fitness & health', 'Energy, stamina', 'Focus on stamina, energy and daily movement.'),
    ('event', 'Event prep', 'Wedding, shoot, trek', 'A plan built around a date, so you peak before your event.'),
  ];
  static const dietMarks = {'non_veg': 2, 'veg': 0, 'egg': 1, 'vegan': 0, 'jain': 0};
  static const dietLines = {'non_veg': 'Eats meat and fish', 'veg': 'No meat, fish or eggs', 'egg': 'Vegetarian + eggs', 'vegan': 'No animal products', 'jain': 'No root vegetables'};
  static const poses = {'photo_front': 'front', 'photo_side': 'side', 'photo_back': 'back'};
  static const remindChoices = [('tonight', 'Tonight', 'tonight, 8 pm'), ('tomorrow', 'Tomorrow', 'tomorrow, 9 am'), ('3days', 'In 3 days', 'in 3 days, 9 am'), ('off', 'Off', '')];

  bool loaded = false;
  Set<int> done = {};
  String? remind; // tonight / tomorrow / 3days / off, null = never picked

  List<SetupField> fields = [];
  List<SetupExtra> extra = [];

  /// Answers by field key (text fields hold what is typed until saved).
  Map<String, dynamic> v = {};
  Map<String, dynamic> extraAnswers = {};

  /// Start photos already saved (pose → url) and the ones picked now (pose → data URL).
  Map<String, String> photos = {}, newPhotos = {};
  String terms = '', agreeText = '';

  /// "Other" picked on a choice with the client's own words (the text box shows).
  final Set<String> otherOpen = {};

  /// Field key (or `q<id>` for an extra question) → the message under it.
  Map<String, String> errors = {};

  int get firstTodo => List.generate(count, (i) => i).firstWhere((i) => !done.contains(i), orElse: () => -1);

  List<SetupField> fieldsOf(int step) => [for (final f in fields) if (f.step == keys[step]) f];
  SetupField? field(String key) => fields.where((f) => f.key == key).firstOrNull;
  bool asks(String key) => field(key) != null;

  void reset() {
    loaded = false;
    done = {};
    remind = null;
    v = {};
    newPhotos = {};
    otherOpen.clear();
    errors = {};
  }

  Future<void> load({bool force = false}) async {
    if (loaded && !force) return;
    final r = await Services.api.get<Map<String, dynamic>>('me/onboarding/');
    _apply(r);
    loaded = true;
    notifyListeners();
  }

  void _apply(Map<String, dynamic> r) {
    done = {for (final k in (r['done'] as List? ?? const [])) keys.indexOf('$k')}..remove(-1);
    final rm = (r['remind'] as Map?)?.cast<String, dynamic>();
    remind = rm?['choice'] as String?;
    fields = [for (final f in (r['fields'] as List? ?? const [])) SetupField(f as Map)];
    extra = [for (final q in (r['extra'] as List? ?? const [])) SetupExtra(q as Map)];
    v = {...((r['values'] as Map?)?.cast<String, dynamic>() ?? const {})};
    final ph = '${v['phone'] ?? ''}';
    if (ph.startsWith('+91')) v['phone'] = ph.substring(3);
    extraAnswers = {...((r['extra_answers'] as Map?)?.cast<String, dynamic>() ?? const {})};
    photos = {for (final e in ((r['photos'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'};
    newPhotos = {};
    terms = '${r['terms'] ?? ''}';
    agreeText = '${r['agree_text'] ?? ''}';
    otherOpen
      ..clear()
      ..addAll([
        for (final f in fields)
          if (f.kind == 'other' && '${v[f.key] ?? ''}'.isNotEmpty && !f.isOption(v[f.key])) f.key,
      ]);
  }

  void changed() => notifyListeners();

  void set(String key, Object? value) {
    v[key] = value;
    errors.remove(key);
    notifyListeners();
  }

  static bool empty(Object? x) => x == null || (x is String && x.trim().isEmpty) || (x is List && x.isEmpty);

  /// Checks one step before saving: marks the fields that need an answer. Returns the toast (title, sub), or null.
  (String, String)? need(int step, {bool mark = true}) {
    final e = <String, String>{};
    for (final f in fieldsOf(step)) {
      final x = v[f.key];
      if (f.kind == 'photo') {
        final pose = poses[f.key]!;
        if (f.required && !photos.containsKey(pose) && !newPhotos.containsKey(pose)) e[f.key] = 'Add this photo.';
        continue;
      }
      if (f.kind == 'agree') {
        if (x != true) e[f.key] = 'Tick the box to agree.';
        continue;
      }
      if (empty(x)) {
        if (f.required) {
          e[f.key] = otherOpen.contains(f.key)
              ? 'Write your answer.'
              : const ['goal', 'choice', 'other', 'gender', 'multi', 'yesno', 'int'].contains(f.kind)
                  ? 'Pick an option.'
                  : 'This is required.';
        }
        continue;
      }
      switch (f.kind) {
        case 'phone':
          if (!isMobile('$x')) e[f.key] = 'Enter a 10-digit mobile number.';
        case 'num' || 'measure':
          final n = double.tryParse('$x');
          if (n == null) {
            e[f.key] = 'Enter a number.';
          } else if ((f.min != null && n < f.min!) || (f.max != null && n > f.max!)) {
            e[f.key] = 'Enter a value between ${_g(f.min)} and ${_g(f.max)}.';
          }
      }
    }
    if (keys[step] == 'health' && (v['conditions'] as List? ?? const []).contains('heart') && v['doctor_ok'] != true && asks('doctor_ok')) {
      e['doctor_ok'] = 'Tick the box once your doctor clears you.';
    }
    if (keys[step] == 'supplements') {
      if (v['takes_medicines'] == true && empty(v['medicines_detail']) && asks('medicines_detail')) e['medicines_detail'] = 'List your medicines and how long you have taken them.';
      if (v['takes_supplements'] == true && empty(v['supplements_detail']) && asks('supplements_detail')) e['supplements_detail'] = 'Tell your coach what you take.';
    }
    if (keys[step] == 'agree') {
      for (final q in extra) {
        if (q.required && empty(extraAnswers[q.id])) e['q${q.id}'] = 'This is required.';
      }
    }
    if (mark) {
      errors = e;
      notifyListeners();
    }
    if (e.isEmpty) return null;
    final first = e.keys.first;
    final label = first.startsWith('q') && field(first) == null
        ? extra.where((q) => 'q${q.id}' == first).firstOrNull?.text ?? ''
        : field(first)?.label ?? '';
    return (e.length == 1 ? 'One answer needs a look' : '${e.length} answers need a look', label);
  }

  static String _g(double? d) => d == null ? '' : (d == d.roundToDouble() ? '${d.round()}' : '$d');

  Map<String, dynamic> data(int step) {
    final out = <String, dynamic>{};
    for (final f in fieldsOf(step)) {
      final x = v[f.key];
      switch (f.kind) {
        case 'photo':
          final p = newPhotos[poses[f.key]];
          if (p != null) out[f.key] = p;
        case 'num' || 'measure':
          out[f.key] = empty(x) ? null : double.tryParse('$x');
        case 'int':
          out[f.key] = empty(x) ? null : int.tryParse('$x');
        case 'phone':
          out[f.key] = '$x'.replaceAll(RegExp(r'[^0-9]'), '');
        case 'text' || 'long' || 'other':
          out[f.key] = x == null ? '' : '$x'.trim();
        default:
          out[f.key] = x;
      }
    }
    if (keys[step] == 'agree') out['extra'] = {for (final e in extraAnswers.entries) if (!empty(e.value)) e.key: e.value};
    return out;
  }

  Future<void> save(int step) async {
    try {
      final r = await Services.api.post<Map<String, dynamic>>('me/onboarding/', {'step': keys[step], 'data': data(step)});
      final keep = Map.of(v);
      _apply(r);
      // Steps not saved yet keep what was typed on them.
      for (final f in fields) {
        if (f.step != keys[step] && !done.contains(keys.indexOf(f.step)) && !empty(keep[f.key])) v[f.key] = keep[f.key];
      }
      errors = {};
      notifyListeners();
    } on ApiError catch (e) {
      if (e.fields.isNotEmpty) {
        errors = {for (final x in e.fields.entries) x.key: x.value.join(' ')};
        notifyListeners();
      }
      rethrow;
    }
    await Services.session.refreshMe();
  }

  Future<void> saveAndLeave(String choice) async {
    await Services.api.delete('me/onboarding/', {'remind': choice});
    remind = choice;
    notifyListeners();
  }

  String get remindLine {
    final c = remind ?? 'tomorrow';
    if (c == 'off') return 'Reminders are off';
    return 'We will remind you ${remindChoices.firstWhere((x) => x.$1 == c).$3}';
  }

  // ── Summary lines for the "You're all set" card (one per step).
  String label(String key) {
    final f = field(key), x = v[key];
    if (f == null || empty(x)) return '';
    if (f.kind == 'multi') return [for (final o in x as List) if (o != 'none') f.optLabel(o)].join(', ');
    return f.isOption(x) ? f.optLabel(x) : '$x';
  }

  static int? years(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return null;
    final n = DateTime.now();
    return n.year - d.year - ((n.month < d.month || (n.month == d.month && n.day < d.day)) ? 1 : 0);
  }

  static String num1(Object? x) {
    final d = double.tryParse('$x');
    if (d == null) return '';
    return d == d.roundToDouble() ? '${d.round()}' : d.toStringAsFixed(1);
  }

  List<(String, String)> get summary {
    String join(List<String> xs) => xs.where((s) => s.isNotEmpty).join(' · ').ifEmpty('—');
    final age = years(v['date_of_birth'] as String?);
    final days = v['workout_days'];
    final injuries = label('injury_areas');
    final measured = [for (final f in fields) if (f.kind == 'measure' && !empty(v[f.key])) f].length;
    final pics = photos.length + newPhotos.keys.where((k) => !photos.containsKey(k)).length;
    final meals = [for (final f in fieldsOf(5)) if (!empty(v[f.key])) f].length;
    return [
      ('Goal', join([label('goal'), label('experience')])),
      ('About you', join([if (age != null) '$age yrs', if (!empty(v['height_cm'])) '${num1(v['height_cm'])} cm', if (!empty(v['weight_kg'])) '${num1(v['weight_kg'])} kg'])),
      ('Training', join([if (days != null) '$days days a week', label('workout_place'), label('workout_time')])),
      ('Health', join([injuries.isEmpty ? 'No injuries' : injuries, label('activity_level')])),
      ('Food', join([label('diet_type'), if (v['food_allergies'] == 'no') 'no allergies' else if (label('food_allergies').isNotEmpty) 'allergies: ${label('food_allergies')}'])),
      ('Your day of eating', meals == 0 ? '—' : '$meals meals noted'),
      ('Supplements', join([v['takes_supplements'] == true ? 'Takes supplements' : 'No supplements', v['takes_medicines'] == true ? 'takes medicines' : 'no medicines'])),
      ('Measurements', join([if (measured > 0) '$measured measurements', if (pics > 0) '$pics photos'])),
      ('Last step', v['terms'] == true ? 'Terms agreed' : 'Terms not agreed yet'),
    ];
  }

  static String dobLine(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '';
    return '${DateFormat('d MMM yyyy').format(d)} · ${years(iso)} years';
  }

  @visibleForTesting
  void applyForTest(Map<String, dynamic> r) => _apply(r);
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
