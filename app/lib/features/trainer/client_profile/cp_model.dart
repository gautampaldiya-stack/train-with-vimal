import 'package:flutter/foundation.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';

/// Client profile (boards `TrainerClientProfile` + `TrainerClientProfileMobile`): the header, the 4 stats and the
/// Overview come from `clients/<id>/`, `stats/` and `overview/`. Every other tab loads its own data when opened
/// and calls [refresh] after a change so the header and the counts stay right.
class CpController extends ChangeNotifier {
  CpController(this.id, {this.admin = false});
  final String id;

  /// Admin view (board `ClientProfile`, D-47): Change trainer in the ⋯ menu, Coaching card and Edit profile.
  final bool admin;

  /// Set by the screen: opens the Change trainer drawer (admin only).
  VoidCallback? changeTrainer;

  Map detail = const {}, stats = const {}, overview = const {};
  Map<String, int> counts = {};
  bool loading = true;
  ApiError? error;
  String tab = 'overview';

  /// Sub-tabs other tabs can open on: Plans (workout · meal · supplements · habits) and Logs (workouts · meals ·
  /// daily · weekly · habits · supps). Overview rows and the stats set these before switching tab.
  String planSlot = 'workout', logSlot = 'workouts';

  /// Bumped by [refresh]; tabs watch it to reload their own data.
  int version = 0;

  String get name => '${detail['full_name'] ?? ''}';
  String get first => name.split(' ').first;
  Map get profile => (detail['profile'] as Map?) ?? const {};
  Map get onboarding => (profile['onboarding'] as Map?) ?? const {};

  static const tabs = [
    ('overview', 'Overview'),
    ('plans', 'Plans'),
    ('logs', 'Logs'),
    ('progress', 'Progress'),
    ('history', 'History'),
    ('content', 'Content'),
    ('forms', 'Forms'),
    ('activity', 'Activity'),
    ('notes', 'Notes'),
  ];

  Future<void> load() async {
    try {
      final r = await Future.wait([
        Services.api.get<Map>('clients/$id/'),
        Services.api.get<Map>('clients/$id/stats/'),
        Services.api.get<Map>('clients/$id/overview/'),
        Services.api.get<Map>('clients/$id/content/', query: {'page_size': 1}),
        Services.api.get<Map>('clients/$id/forms/'),
        Services.api.get<Map>('clients/$id/notes/', query: {'page_size': 1}),
      ]);
      detail = r[0];
      stats = r[1];
      overview = r[2];
      final plans = (overview['current_plans'] as Map?) ?? const {};
      counts = {
        'plans': plans.values.where((v) => v is Map && v.isNotEmpty && (v['count'] == null || (v['count'] as num) > 0)).length,
        'content': (r[3]['count'] as num?)?.toInt() ?? 0,
        'forms': ((r[4]['sent'] as List?) ?? const []).length,
        'notes': (r[5]['count'] as num?)?.toInt() ?? 0,
      };
      error = null;
    } on ApiError catch (e) {
      error = e;
    }
    loading = false;
    notifyListeners();
  }

  /// After a change in any tab: reload the header, stats, Overview and counts; tabs reload on [version].
  Future<void> refresh() async {
    version++;
    await load();
  }

  void setTab(String t, {String? plan, String? log}) {
    if (plan != null) planSlot = plan;
    if (log != null) logSlot = log;
    tab = t;
    notifyListeners();
  }
}
