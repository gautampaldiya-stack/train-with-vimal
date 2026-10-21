import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../trainer/client_profile/cp_content_drawers.dart' show DrOpt, DrScrollList;
import '../lib_common.dart';

/// Actions an exercise card and the Exercise page share: Add to program, Duplicate to edit, Delete.

/// "Add to program": pick one of the programs you may change, then a workout day. The exercise goes to the end of
/// that day in every week, with its default sets and reps (`POST programs/<id>/add-exercise/`). Days that already
/// have it show "Added" and cannot be picked, so a day never gets the same exercise twice.
Future<void> showAddToProgram(BuildContext context, Map e) async {
  // program id → weekdays that already have this exercise (`exercises/<id>/used-in/`)
  final usedOn = Services.api.get<List>('exercises/${e['id']}/used-in/').then((r) => {
        for (final u in r) '${(u as Map)['id']}': {for (final d in (u['weekdays'] as List? ?? const [])) (d as num).toInt()},
      }).catchError((_) => <String, Set<int>>{});
  final programs = Services.api.get<Map>('programs/', query: {'tab': 'active', 'page_size': 100}).then((r) => [
        for (final p in r['results'] as List)
          if ((p as Map)['can_edit'] == true) p,
      ]);
  final data = Future.wait<Object>([programs, usedOn]);
  final prog = ValueNotifier<Map?>(null);
  final days = ValueNotifier<List<Map>?>(null);
  final day = ValueNotifier<int?>(null);
  var saving = false;

  Future<void> pick(Map p) async {
    prog.value = p;
    days.value = null;
    day.value = null;
    try {
      final d = await Services.api.get<Map>('programs/${p['id']}/');
      final w1 = [for (final w in d['program_weeks'] as List) w as Map].firstWhere((w) => w['number'] == 1, orElse: () => const {});
      final list = [for (final x in (w1['days'] as List? ?? const [])) x as Map]..removeWhere((x) => x['is_rest'] == true);
      list.sort((a, b) => (a['weekday'] as num).compareTo(b['weekday'] as num));
      if (prog.value == p) days.value = list;
    } on ApiError catch (_) {
      if (prog.value == p) days.value = const [];
    }
  }

  final r = await showAppModal<Map>(
    context,
    title: 'Add to program',
    body: '${e['name']} · added to the day in every week, with its default sets and reps',
    icon: AppIcons.plus,
    width: 480,
    content: (ctx) => FutureBuilder<List<Object>>(
      future: data,
      builder: (ctx, s) {
        if (s.hasError) return const EmptyState('Could not load your programs');
        if (!s.hasData) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)));
        final list = s.data![0] as List<Map>;
        final used = s.data![1] as Map<String, Set<int>>;
        if (list.isEmpty) {
          return Text('No program you can change yet. Make one, or duplicate one, on the Programs page.', style: AppText.s(13, W.w5, color: AppColors.muted));
        }
        return ListenableBuilder(
          listenable: Listenable.merge([prog, days, day]),
          builder: (ctx, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            Text('Program', style: AppText.label),
            DrScrollList(rows: 4, [
              for (final p in list)
                DrOpt(
                  title: '${p['name']}',
                  sub: '${plural((p['weeks'] as num?)?.toInt() ?? 0, 'week')} · ${p['days_per_week']} days / week'
                      '${(used['${p['id']}'] ?? const {}).isEmpty ? '' : ' · Already on ${[for (final d in (used['${p['id']}']!.toList()..sort())) weekdayShort[d]].join(', ')}'}',
                  on: prog.value?['id'] == p['id'],
                  onTap: () => pick(p),
                ),
            ]),
            if (prog.value != null) ...[
              Text('Day', style: AppText.label),
              if ((used['${prog.value!['id']}'] ?? const {}).isNotEmpty)
                Text('Days marked Added already have this exercise.', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
              if (days.value == null)
                const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)))
              else if (days.value!.isEmpty)
                Text('This program has no workout days.', style: AppText.s(13, W.w5, color: AppColors.muted))
              else
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final d in days.value!)
                    () {
                      final wd = (d['weekday'] as num).toInt(), on = day.value == wd;
                      final n = '${d['name'] ?? ''}'.trim();
                      final has = (used['${prog.value!['id']}'] ?? const {}).contains(wd);
                      final chip = ChoiceChipX('${weekdayShort[wd]} · ${n.isEmpty ? 'Workout' : n}${has ? ' · Added' : ''}',
                          on: on, done: has, onTap: () => day.value = wd);
                      return has ? Tooltip(message: '${e['name']} is already on this day', child: chip) : chip;
                    }(),
                ]),
            ],
          ]),
        );
      },
    ),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      StatefulBuilder(
        builder: (bctx, set) => ListenableBuilder(
          listenable: Listenable.merge([prog, day]),
          builder: (_, _) => AppButton.primary(
            'Add to program',
            icon: AppIcons.check,
            expand: ctx.isPhone,
            loading: saving,
            onPressed: prog.value == null || day.value == null
                ? null
                : () async {
                    set(() => saving = true);
                    try {
                      final res = await Services.api.post<Map>('programs/${prog.value!['id']}/add-exercise/', {'exercise': e['id'], 'weekday': day.value});
                      if (ctx.mounted) Navigator.of(ctx).pop({...res, 'weekday': day.value});
                    } on ApiError catch (er) {
                      set(() => saving = false);
                      if (ctx.mounted) showToast(ctx, 'Could not add it', sub: er.message, kind: ToastKind.err);
                    }
                  },
          ),
        ),
      ),
    ],
  );
  disposeLater([prog, days, day]);
  if (r == null || !context.mounted) return;
  final weeks = (r['weeks'] as num?)?.toInt() ?? 0;
  final router = GoRouter.of(context);
  showToast(context, 'Added to ${r['name']}', sub: '${weekdayNames[r['weekday'] as int]} · ${weeks == 1 ? '1 week' : 'every week ($weeks)'}',
      action: 'Open', onAction: () => router.go('/programs/${r['program']}'));
}

/// "Duplicate to edit": an editable copy, opened in the edit page.
Future<void> duplicateExercise(BuildContext context, Map e) async {
  try {
    final c = await Services.api.post<Map>('exercises/${e['id']}/duplicate/');
    if (!context.mounted) return;
    context.go('/exercises/${c['id']}?edit=1');
    showToast(context, 'Copy made', sub: 'Now editing ${c['name']}');
  } on ApiError catch (er) {
    if (context.mounted) showToast(context, 'Could not duplicate it', sub: er.message, kind: ToastKind.err);
  }
}

/// Delete a custom exercise (confirm, then Undo on the toast). Programs that use it keep it.
Future<bool> deleteExercise(BuildContext context, Map e, {VoidCallback? onUndo}) async {
  final n = (e['programs'] as num?)?.toInt() ?? 0;
  final ok = await confirmAction(context,
      title: 'Delete this exercise?',
      body: '${e['name']} leaves the library${n > 0 ? '. The ${plural(n, 'program')} that use it keep it' : ''}. Workouts already logged stay safe.',
      confirm: 'Delete',
      danger: true,
      icon: AppIcons.trash);
  if (!ok || !context.mounted) return false;
  try {
    await Services.api.delete('exercises/${e['id']}/');
    if (context.mounted) {
      showToast(context, 'Exercise deleted', sub: '${e['name']}', action: 'Undo', onAction: () async {
        try {
          await Services.api.post('exercises/${e['id']}/restore/');
          onUndo?.call();
        } on ApiError catch (_) {}
      });
    }
    return true;
  } on ApiError catch (er) {
    if (context.mounted) showToast(context, 'Could not delete it', sub: er.message, kind: ToastKind.err);
    return false;
  }
}

/// `.chip`-like pick (one of a few): outlined, blue when picked.
class ChoiceChipX extends StatelessWidget {
  const ChoiceChipX(this.label, {super.key, required this.on, required this.onTap, this.tick = false, this.done = false});
  final String label;
  final bool on, tick;

  /// Already there: greyed with a tick, cannot be picked.
  final bool done;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => done
      ? Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(AppRadius.chip), border: Border.all(color: AppColors.line)),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
            const AppIcon(AppIcons.check, size: 13, color: AppColors.okText, stroke: 2.2),
            Text(label, style: AppText.s(13, W.w6, color: AppColors.muted)),
          ]),
        )
      : GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: on ? (tick ? AppColors.accentSoft : AppColors.accent) : AppColors.card,
              borderRadius: AppRadius.all(AppRadius.chip),
              border: Border.all(color: on ? AppColors.accent : AppColors.line2),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
              if (on && tick) const AppIcon(AppIcons.check, size: 13, color: AppColors.accentText, stroke: 2.2),
              Text(label, style: AppText.s(13, W.w6, color: on ? (tick ? AppColors.accentText : AppColors.white) : AppColors.text)),
            ]),
          ),
        ),
      );
}
