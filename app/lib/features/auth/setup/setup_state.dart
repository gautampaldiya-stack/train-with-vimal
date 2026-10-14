import 'package:flutter/foundation.dart';

import '../../../app/services.dart';

/// Profile setup answers (5 steps). Loaded from / saved to `me/onboarding/` (decision D-14).
/// Defaults are what the board shows before the client picks anything.
class SetupState extends ChangeNotifier {
  SetupState._();
  static final instance = SetupState._();

  static const keys = ['goal', 'about', 'schedule', 'health', 'food'];
  static const titles = ['Your goal', 'About you', 'Training days', 'Health & injuries', 'Food preferences'];
  static const shorts = ['Goal', 'About you', 'Schedule', 'Health', 'Food'];
  static const subs = [
    'Main goal and training experience',
    'Age, height, weight, where you train',
    'Days, session length, wake-up time',
    'Injuries, daily activity, doctor clearance',
    'Diet, meals per day, foods you avoid',
  ];

  // Options exactly as on the board, with the values the API takes.
  static const goals = [
    ('fat_loss', 'Lose fat', 'Lean down, keep muscle', 'Calorie deficit with strength training: lose fat, keep muscle.'),
    ('muscle_gain', 'Build muscle', 'Size & shape', 'A small surplus with progressive overload: size and shape.'),
    ('strength', 'Get stronger', 'Hit new PRs', 'Low reps and heavy compound lifts to beat your records.'),
    ('recomp', 'Recomp', 'Lose fat + gain muscle', 'Slow and steady: fat down, muscle up.'),
    ('general', 'Fitness & health', 'Energy, stamina', 'Focus on stamina, energy and daily movement.'),
    ('event', 'Event prep', 'Wedding, shoot, trek', 'A plan built around a date, so you peak before your event.'),
  ];
  static const levels = [('beginner', 'Beginner', '0–6 months'), ('intermediate', 'Intermediate', '6 months – 2 yrs'), ('advanced', 'Advanced', '2+ years')];
  static const places = [('gym', 'Gym', 'Full equipment'), ('home', 'Home', 'Little or none'), ('both', 'Both', 'Mix of the two')];
  static const days = [('mon', 'Mon'), ('tue', 'Tue'), ('wed', 'Wed'), ('thu', 'Thu'), ('fri', 'Fri'), ('sat', 'Sat'), ('sun', 'Sun')];
  static const lengths = [30, 45, 60, 75];
  static const wakes = [('05:30', '5:30 am'), ('06:30', '6:30 am'), ('07:30', '7:30 am'), ('08:30', '8:30 am')];
  static const injuries = [('none', 'None'), ('knee', 'Knee'), ('lower_back', 'Lower back'), ('shoulder', 'Shoulder'), ('neck', 'Neck'), ('wrist', 'Wrist'), ('ankle', 'Ankle')];
  static const injuryNotes = {
    'knee': ['Right knee hurts on deep squats', 'Left knee hurts on stairs'],
    'lower_back': ['Lower back stiff after sitting'],
    'shoulder': ['Shoulder pain on overhead press'],
    'neck': ['Neck stiff from desk work'],
    'wrist': ['Wrist pain on push-ups'],
    'ankle': ['Ankle rolled last year'],
  };
  static const activities = [('desk', 'Desk job', 'Mostly sitting, under 5,000 steps'), ('on_feet', 'On my feet', 'Walking or standing a lot'), ('very_active', 'Very active', 'Physical work or sport most days')];
  static const diets = [
    ('veg', 'Vegetarian', 'No meat, fish or eggs', 0),
    ('egg', 'Eggetarian', 'Vegetarian + eggs', 1),
    ('non_veg', 'Non-veg', 'Eats meat and fish', 2),
    ('vegan', 'Vegan', 'No animal products', 0),
    ('jain', 'Jain', 'No root vegetables', 0),
  ];
  static const avoids = [('eggs', 'Eggs'), ('mushrooms', 'Mushrooms'), ('onion_garlic', 'Onion & garlic'), ('dairy', 'Dairy'), ('peanuts', 'Peanuts'), ('gluten', 'Gluten')];
  static const remindChoices = [('tonight', 'Tonight', 'tonight, 8 pm'), ('tomorrow', 'Tomorrow', 'tomorrow, 9 am'), ('3days', 'In 3 days', 'in 3 days, 9 am'), ('off', 'Off', '')];

  bool loaded = false;
  Set<int> done = {};
  String? remind; // tonight / tomorrow / 3days / off, null = never picked

  // Step 1
  String? goal;
  String level = 'intermediate';
  // Step 2 (age, height, weight, target)
  List<double> body = [29, 162, 78, 68];
  static const bodyStep = [1.0, 1.0, 0.5, 0.5], bodyMin = [14.0, 120.0, 35.0, 35.0], bodyMax = [80.0, 220.0, 200.0, 200.0];
  String place = 'gym';
  // Step 3
  List<String> trainDays = ['mon', 'tue', 'thu', 'fri'];
  int sessionMin = 45;
  String wake = '06:30';
  // Step 4
  List<String> injury = [];
  String note = '';
  String activity = 'desk';
  bool doctorOk = true;
  // Step 5
  String? diet;
  int meals = 5;
  List<String> avoid = [];
  bool homeCooked = true;

  int get firstTodo => List.generate(5, (i) => i).firstWhere((i) => !done.contains(i), orElse: () => -1);

  void reset() {
    loaded = false;
    done = {};
    remind = null;
  }

  Future<void> load({bool force = false}) async {
    if (loaded && !force) return;
    final r = await Services.api.get<Map<String, dynamic>>('me/onboarding/');
    _apply(r);
    loaded = true;
    notifyListeners();
  }

  void _apply(Map<String, dynamic> r) {
    final a = (r['answers'] as Map?)?.cast<String, dynamic>() ?? {};
    done = {for (final k in (r['done'] as List? ?? const [])) keys.indexOf('$k')}..remove(-1);
    final rm = (r['remind'] as Map?)?.cast<String, dynamic>();
    remind = rm?['choice'] as String?;
    Map<String, dynamic> m(String k) => (a[k] as Map?)?.cast<String, dynamic>() ?? const {};
    final g = m('goal'), b = m('about'), s = m('schedule'), h = m('health'), f = m('food');
    goal = g['goal'] as String? ?? goal;
    level = g['level'] as String? ?? level;
    double n(Object? v, double d) => v is num ? v.toDouble() : (double.tryParse('$v') ?? d);
    if (b.isNotEmpty) body = [n(b['age'], body[0]), n(b['height_cm'], body[1]), n(b['weight_kg'], body[2]), n(b['target_weight_kg'], body[3])];
    place = b['place'] as String? ?? place;
    if (s['days'] is List) trainDays = [for (final d in s['days'] as List) '$d'];
    sessionMin = (s['session_min'] as num?)?.toInt() ?? sessionMin;
    wake = s['wake_time'] as String? ?? wake;
    if (h['injuries'] is List) injury = [for (final d in h['injuries'] as List) '$d'];
    note = h['notes'] as String? ?? note;
    activity = h['activity'] as String? ?? activity;
    doctorOk = h['doctor_ok'] as bool? ?? doctorOk;
    diet = f['diet'] as String? ?? diet;
    meals = (f['meals_per_day'] as num?)?.toInt() ?? meals;
    if (f['avoid'] is List) avoid = [for (final d in f['avoid'] as List) '$d'];
    homeCooked = f['home_cooked'] as bool? ?? homeCooked;
  }

  void changed() => notifyListeners();

  /// What the step is missing (board `NEED`), as a toast (title, sub). Null = ok to save.
  (String, String)? need(int step) => switch (step) {
        0 when goal == null => ('Pick your main goal', '${Services.session.me?.coachFirst ?? 'Your coach'} builds your plan around it'),
        2 when trainDays.length < 2 => ('Pick at least 2 days', 'Tap the days you can train'),
        3 when injury.isEmpty => ('Tell us about injuries', 'Pick None if nothing hurts'),
        4 when diet == null => ('Pick your food preference', 'Your meal plan only uses foods you eat'),
        _ => null,
      };

  Map<String, dynamic> data(int step) => switch (step) {
        0 => {'goal': goal, 'level': level},
        1 => {'age': body[0].round(), 'height_cm': body[1], 'weight_kg': body[2], 'target_weight_kg': body[3], 'place': place},
        2 => {'days': trainDays, 'session_min': sessionMin, 'wake_time': wake},
        3 => {'injuries': injury, 'activity': activity, 'doctor_ok': doctorOk, if (note.trim().isNotEmpty) 'notes': note.trim()},
        _ => {'diet': diet, 'meals_per_day': meals, 'avoid': avoid, 'home_cooked': homeCooked},
      };

  Future<void> save(int step) async {
    final r = await Services.api.post<Map<String, dynamic>>('me/onboarding/', {'step': keys[step], 'data': data(step)});
    _apply(r);
    notifyListeners();
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

  // ── Summary lines for the "You're all set" card.
  static String f1(double x) => x.toStringAsFixed(1);
  String fmtBody(int k) => switch (k) { 0 => '${body[0].round()} yrs', 1 => '${body[1].round()} cm', _ => '${f1(body[k])} kg' };
  List<String> get sortedDayLabels => [for (final d in days) if (trainDays.contains(d.$1)) d.$2];

  List<(String, String)> get summary {
    final g = goals.where((x) => x.$1 == goal).firstOrNull;
    final lv = levels.firstWhere((x) => x.$1 == level, orElse: () => levels[1]).$2;
    final pl = switch (place) { 'home' => 'Home', 'both' => 'Gym and home', _ => 'Gym' };
    final real = [for (final i in injury) if (i != 'none') injuries.firstWhere((x) => x.$1 == i).$2];
    final act = activities.firstWhere((x) => x.$1 == activity, orElse: () => activities[0]).$2;
    final dt = diets.where((x) => x.$1 == diet).firstOrNull;
    final av = [for (final a in avoids) if (avoid.contains(a.$1)) a.$2.toLowerCase()];
    return [
      ('Goal', '${g?.$2 ?? '—'} · $lv'),
      ('About you', '${fmtBody(0)} · ${fmtBody(1)} · ${f1(body[2])} → ${f1(body[3])} kg'),
      ('Training', '${trainDays.length} days · ${sortedDayLabels.join(', ')} · $sessionMin min · $pl'),
      ('Health', '${real.isEmpty ? 'No injuries' : real.join(', ')} · $act'),
      ('Food', '${dt?.$2 ?? '—'} · $meals meals${av.isEmpty ? '' : ' · avoids ${av.join(', ')}'}'),
    ];
  }

  @visibleForTesting
  void applyForTest(Map<String, dynamic> r) => _apply(r);
}
