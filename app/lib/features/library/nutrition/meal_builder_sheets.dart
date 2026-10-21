import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import '../../trainer/client_profile/cp_content_drawers.dart' show DrOpt, DrScrollList;
import '../../trainer/me/me_common.dart' show meField;
import '../lib_common.dart';
import 'meal_builder_model.dart';
import 'nu_common.dart';

/// Modals and drawers of the Meal plan builder (board `MealPlanBuilder`): Edit targets, Add / Edit meal, Publish,
/// Assign to clients, Clients on this plan (version notes) and Custom version.

/// `.pg-step` with a text value ("3", "3.5"), for steppers that are not whole numbers.
class NuStep extends StatelessWidget {
  const NuStep({super.key, required this.value, required this.unit, this.onLess, this.onMore});
  final String value, unit;
  final VoidCallback? onLess, onMore;
  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(borderRadius: AppRadius.all(AppRadius.input), border: Border.all(color: AppColors.line2)),
        child: Row(spacing: 8, children: [
          AppIconButton(AppIcons.minus, tooltip: 'Less', small: true, onPressed: onLess),
          Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 5, children: [
              Text(value, style: AppText.s(16, W.w8, tabular: true)),
              if (unit.isNotEmpty) Flexible(child: Text(unit, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.muted))),
            ]),
          ),
          AppIconButton(AppIcons.plus, tooltip: 'More', small: true, onPressed: onMore),
        ]),
      );
}

/// Two fields side by side (`.pg-nrow`), one under the other on phone.
Widget _pair(BuildContext ctx, Widget a, Widget b) => ctx.isPhone
    ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [a, b])
    : Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [Expanded(child: a), Expanded(child: b)]);

/// `.nu-chk`: green when the macros give the calories (within 5 %), else red.
Widget nuCheck(String text, bool ok) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: ok ? AppColors.okBg : AppColors.badBg, borderRadius: AppRadius.all(AppRadius.item)),
      child: Row(spacing: 8, children: [
        AppIcon(ok ? AppIcons.checkCircle : AppIcons.alert, size: 15, color: ok ? AppColors.okText : AppColors.badText),
        Expanded(child: Text(text, style: AppText.s(13, W.w6, color: ok ? AppColors.okText : AppColors.badText))),
      ]),
    );

/// Edit targets: calories, protein, carbs, fat, fibre and water; "Macros add up to N kcal". Gives back the new
/// targets (water in ml).
Future<Map<String, num>?> showTargetsModal(BuildContext context, Map<String, num> now) {
  final v = ValueNotifier<Map<String, num>>({...now});
  void set(String k, num x) => v.value = {...v.value, k: x};
  Widget step(String k, String unit, num by, num lo, num hi, {double scale = 1}) => ValueListenableBuilder(
        valueListenable: v,
        builder: (_, t, _) {
          final x = t[k] ?? 0;
          final shown = x / scale;
          return NuStep(
            value: scale == 1 ? kfmt(shown) : fq(shown),
            unit: unit,
            onLess: x - by < lo ? null : () => set(k, x - by),
            onMore: x + by > hi ? null : () => set(k, x + by),
          );
        },
      );
  return showAppModal<Map<String, num>>(
    context,
    title: 'Edit targets',
    body: 'Daily targets for every client on this plan',
    icon: AppIcons.target,
    width: 500,
    content: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
      _pair(ctx, meField('Calories', step('kcal_target', 'kcal', 50, 1200, 4000)), meField('Protein', step('protein_g', 'g', 5, 30, 400))),
      _pair(ctx, meField('Carbs', step('carbs_g', 'g', 5, 20, 600)), meField('Fat', step('fat_g', 'g', 5, 20, 200))),
      _pair(ctx, meField('Fibre', step('fibre_g', 'g', 1, 10, 80)), meField('Water', step('water_ml', 'L', 500, 1000, 6000, scale: 1000))),
      ValueListenableBuilder(
        valueListenable: v,
        builder: (_, t, _) {
          final from = (t['protein_g'] ?? 0) * 4 + (t['carbs_g'] ?? 0) * 4 + (t['fat_g'] ?? 0) * 9;
          final k = (t['kcal_target'] ?? 1).toDouble();
          return nuCheck('Macros add up to ${kfmt(from)} kcal', (from - k).abs() / k <= .05);
        },
      ),
    ]),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      AppButton.primary('Update targets', icon: AppIcons.check, expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop(v.value)),
    ],
  ).whenComplete(() => disposeLater([v]));
}

/// Times for the meal time select: every 30 minutes from 5:00 am to 11:30 pm ("08:00", "8:00 am").
final mealTimes = [
  for (var m = 5 * 60; m < 24 * 60; m += 30) ('${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}', _ampm(m)),
];

String _ampm(int m) {
  final h = m ~/ 60, mm = m % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${mm.toString().padLeft(2, '0')} ${h < 12 ? 'am' : 'pm'}';
}

/// "08:00:00" → "8:00 am".
String mealTimeLabel(Object? t) {
  final p = '${t ?? ''}'.split(':');
  if (p.length < 2) return '';
  return _ampm((int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0));
}

/// Add meal / Edit meal: name, time and calorie target. Gives back {name, time, kcal_target}.
Future<Map?> showMealModal(BuildContext context, {Map? meal}) {
  final name = TextEditingController(text: '${meal?['name'] ?? ''}');
  final cur = '${meal?['time'] ?? '11:00'}';
  final time = ValueNotifier(cur.length >= 5 ? cur.substring(0, 5) : '11:00');
  final kcal = ValueNotifier(((meal?['kcal_target'] as num?) ?? 300).toInt());
  final err = ValueNotifier<String?>(null);
  void save(BuildContext ctx) {
    final v = name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (v.length < 2) {
      err.value = 'Enter the meal name, e.g. Pre-workout.';
      return;
    }
    Navigator.of(ctx).pop({'name': v.length > 60 ? v.substring(0, 60) : v, 'time': time.value, 'kcal_target': kcal.value});
  }

  return showAppModal<Map>(
    context,
    title: meal == null ? 'Add meal' : 'Edit ${'${meal['name']}'.toLowerCase()}',
    body: meal == null ? 'It starts with one empty option' : 'Name, time and calorie target',
    icon: meal == null ? AppIcons.plus : AppIcons.edit,
    width: 480,
    content: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
      ValueListenableBuilder(
        valueListenable: err,
        builder: (_, e, _) => meField('Meal name', AppTextField(controller: name, autofocus: meal == null, placeholder: 'e.g. Pre-workout', onSubmitted: (_) => save(ctx)), req: true, error: e),
      ),
      _pair(
        ctx,
        meField(
          'Time',
          ValueListenableBuilder(
            valueListenable: time,
            builder: (_, t, _) => AppSelect(
              mealTimes.where((x) => x.$1 == t).firstOrNull?.$2 ?? mealTimeLabel(t),
              entries: [for (final (k, l) in mealTimes) MenuEntry(l, selected: k == t, onTap: () => time.value = k)],
            ),
          ),
        ),
        meField(
          'Calorie target',
          ValueListenableBuilder(
            valueListenable: kcal,
            builder: (_, k, _) => LibStepper(value: k, unit: 'kcal', min: 50, max: 2000, step: 50, onChanged: (x) => kcal.value = x),
          ),
        ),
      ),
    ]),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      AppButton.primary('Save meal', icon: AppIcons.check, expand: ctx.isPhone, onPressed: () => save(ctx)),
    ],
  ).whenComplete(() => disposeLater([name, time, kcal, err]));
}

/// Publish master plan?: who gets it and what stays. True = publish.
Future<bool> showPublishModal(BuildContext context, MealBuilderModel m) async {
  final n = m.clientCount, cu = m.customCount;
  final lines = [
    cu > 0 ? '$cu custom version${cu == 1 ? ' keeps its' : 's keep their'} changes' : 'Everyone follows the master plan',
    'Meals already logged stay as they are',
    'Their trainers get a notice',
  ];
  final r = await showAppModal<bool>(
    context,
    title: 'Publish master plan?',
    body: n > 0 ? '${n == 1 ? '1 client gets' : '$n clients get'} the new version on their phone.' : 'Nobody is on this plan yet. It is saved as ready to assign.',
    icon: AppIcons.send,
    width: 480,
    content: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      for (final l in lines)
        Row(spacing: 8, children: [
          const AppIcon(AppIcons.check, size: 15, color: AppColors.okText),
          Expanded(child: Text(l, style: AppText.s(13, W.w5, color: AppColors.text2))),
        ]),
    ]),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop(false)),
      AppButton.primary('Publish', icon: AppIcons.send, expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop(true)),
    ],
  );
  return r == true;
}

/// Assign to clients: every client this person can see, ticked = on this plan; a client on another meal plan
/// moves here. Gives back (added, removed, the clients before) after saving.
Future<(int, int, List<String>)?> showMealAssignModal(BuildContext context, MealBuilderModel m) async {
  final picked = ValueNotifier<Set<String>?>(null);
  final q = ValueNotifier('');
  var before = <String>[];
  // who is on this plan now: worked out when the list arrives, not while the modal builds
  final data = Services.api.get<List>('meal-plans/assign-options/').then((all) {
    before = [for (final c in all) if ('${(c as Map)['plan']}' == m.id) '${c['id']}'];
    picked.value = before.toSet();
    return all;
  });
  var saving = false;
  final r = await showAppModal<(int, int, List<String>)>(
    context,
    title: 'Assign to clients',
    body: '${m.name} · ${kfmt(m.targets['kcal_target'] ?? 0)} kcal / day',
    icon: AppIcons.assign,
    width: 500,
    content: (ctx) => FutureBuilder<List>(
      future: data,
      builder: (ctx, s) {
        if (s.hasError) return const EmptyState('Could not load your clients');
        if (!s.hasData) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)));
        final all = [for (final x in s.data!) x as Map];
        return ListenableBuilder(
          listenable: Listenable.merge([picked, q]),
          builder: (ctx, _) {
            final rows = all.where((c) => q.value.isEmpty || '${c['full_name']}'.toLowerCase().contains(q.value)).toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
              AppSearchField(placeholder: 'Search clients', icon: AppIcons.search, onChanged: (v) => q.value = v.trim().toLowerCase()),
              if (all.isEmpty)
                Text('You have no clients yet.', style: AppText.s(13, W.w5, color: AppColors.muted))
              else if (rows.isEmpty)
                Text('No client matches.', style: AppText.s(13, W.w5, color: AppColors.muted))
              else
                DrScrollList(rows: 6, [
                  for (final c in rows)
                    () {
                      final id = '${c['id']}', sel = picked.value!.contains(id);
                      final other = c['plan'] != null && '${c['plan']}' != m.id;
                      return DrOpt(
                        title: '${c['full_name']}',
                        sub: c['plan'] == null ? 'No meal plan' : 'On ${c['plan_name']}',
                        multi: true,
                        on: sel,
                        thumb: AppAvatar('${c['full_name']}', size: 28, initials: '${c['initials'] ?? ''}', colors: AppColors.avatarCode('${c['avatar_color'] ?? 'c1'}')),
                        end: other ? 'Moves here' : null,
                        onTap: () => picked.value = sel ? ({...picked.value!}..remove(id)) : {...picked.value!, id},
                      );
                    }(),
                ]),
              Text('Clients on another meal plan move to this one. Their logged meals stay.', style: AppText.s(12, W.w5, color: AppColors.muted)),
            ]);
          },
        );
      },
    ),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      StatefulBuilder(
        builder: (bctx, set) => ValueListenableBuilder(
          valueListenable: picked,
          builder: (_, p, _) => AppButton.primary(
            p == null || p.isEmpty ? 'Save · no clients' : 'Save · ${plural(p.length, 'client')}',
            icon: AppIcons.check,
            expand: ctx.isPhone,
            loading: saving,
            onPressed: p == null
                ? null
                : () async {
                    set(() => saving = true);
                    try {
                      final res = await Services.api.post<Map>('meal-plans/${m.id}/assign/', {'clients': p.toList()});
                      if (ctx.mounted) Navigator.of(ctx).pop((((res['added'] as num?) ?? 0).toInt(), ((res['removed'] as num?) ?? 0).toInt(), before));
                    } on ApiError catch (e) {
                      set(() => saving = false);
                      if (ctx.mounted) showToast(ctx, 'Could not save it', sub: e.message, kind: ToastKind.err);
                    }
                  },
          ),
        ),
      ),
    ],
  );
  disposeLater([picked, q]);
  return r;
}

/// Custom version for X: the note of what is different for this client. Gives back the note.
Future<String?> showVersionNoteModal(BuildContext context, Map c) {
  final first = '${c['full_name']}'.split(' ').first;
  final t = TextEditingController(text: '${c['version_note'] ?? ''}');
  final err = ValueNotifier<String?>(null);
  return showAppModal<String>(
    context,
    title: 'Custom version for ${c['full_name']}',
    body: 'The master plan and the other clients stay as they are',
    icon: AppIcons.edit,
    width: 500,
    content: (ctx) => ValueListenableBuilder(
      valueListenable: err,
      builder: (_, e, _) => meField(
        'What is different for $first?',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
          AppTextField(controller: t, autofocus: true, maxLines: 4, minLines: 3, placeholder: 'e.g. Lunch: no paneer, use tofu. Dinner: 1 roti less.'),
          Text('Only for this client. The trainer and the client see it on the plan.', style: AppText.cap),
        ]),
        error: e,
      ),
    ),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      AppButton.primary('Save version note', icon: AppIcons.check, expand: ctx.isPhone, onPressed: () {
        final v = t.text.trim();
        if (v.isEmpty) {
          err.value = 'Write what is different, or use Reset to master.';
          return;
        }
        Navigator.of(ctx).pop(v);
      }),
    ],
  ).whenComplete(() => disposeLater([t, err]));
}

/// Clients on this plan (Manage): each client Master or Custom version, ⋯ version note / reset / profile / remove.
/// [changed] runs after a change so the page reloads its list. Returns true for "Assign to clients".
Future<bool?> showMealClientsDrawer(BuildContext context, MealBuilderModel m, {required VoidCallback changed}) {
  final rows = ValueNotifier<List<Map>?>(null);
  Future<void> load() async {
    try {
      rows.value = [for (final x in await Services.api.get<List>('meal-plans/${m.id}/clients/')) x as Map];
    } on ApiError catch (_) {
      rows.value ??= [];
    }
  }

  load();
  Future<void> run(BuildContext ctx, Future<void> Function() f, String done, String sub) async {
    try {
      await f();
      await load();
      changed();
      if (ctx.mounted) showToast(ctx, done, sub: sub);
    } on ApiError catch (e) {
      if (ctx.mounted) showToast(ctx, 'Could not do that', sub: e.message, kind: ToastKind.err);
    }
  }

  void menu(BuildContext ctx, BuildContext anchor, Map c) {
    final first = '${c['full_name']}'.split(' ').first;
    final custom = c['custom'] == true;
    showAppMenu(anchor, width: 240, [
      MenuEntry.header('${c['full_name']}'),
      MenuEntry(custom ? 'Edit version note' : 'Add version note', icon: AppIcons.edit, onTap: () async {
        final v = await showVersionNoteModal(ctx, c);
        if (v == null || !ctx.mounted) return;
        run(ctx, () => Services.api.put('meal-plans/${m.id}/clients/${c['id']}/version-note/', {'version_note': v}), 'Custom version saved', 'Only for $first');
      }),
      if (custom)
        MenuEntry('Reset to master', icon: AppIcons.undo, sub: 'Removes the version note', onTap: () => run(ctx, () => Services.api.post('meal-plans/${m.id}/clients/${c['id']}/reset/'), '$first follows the master again', 'Version note removed')),
      MenuEntry('Open client profile', icon: AppIcons.open, onTap: () {
        Navigator.of(ctx).pop();
        context.go('/clients/${c['id']}?tab=plans');
      }),
      const MenuEntry.separator(),
      MenuEntry('Remove from plan', icon: AppIcons.trash, danger: true, onTap: () async {
        final ok = await confirmAction(ctx,
            title: 'Remove ${c['full_name']}?', body: '$first stops following ${m.name}. Meals already logged stay.', confirm: 'Remove', danger: true, icon: AppIcons.trash);
        if (!ok || !ctx.mounted) return;
        run(ctx, () => Services.api.post('meal-plans/${m.id}/clients/${c['id']}/remove/'), 'Removed from plan', '${c['full_name']}');
      }),
    ]);
  }

  String countL(List<Map>? l) => l == null ? '' : (l.isEmpty ? 'No clients yet' : plural(l.length, 'client'));
  return showAppDrawer<bool>(
    context,
    title: 'Clients on this plan',
    sub: 'Changes to the master reach everyone',
    icon: AppIcons.clientsAlt,
    builder: (ctx) => ValueListenableBuilder(
      valueListenable: rows,
      builder: (ctx, list, _) {
        if (list == null) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 6),
          if (list.isEmpty)
            Padding(padding: const EdgeInsets.all(28), child: Text('Not assigned to anyone yet.', textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted))),
          for (final (i, c) in list.indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                Row(spacing: 10, children: [
                  AppAvatar('${c['full_name']}', size: 32, initials: '${c['initials'] ?? ''}', colors: AppColors.avatarCode('${c['avatar_color'] ?? 'c1'}')),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                      Text('${c['full_name']}', style: AppText.s(14, W.w7)),
                      Text(c['custom'] == true ? 'Has changes only for them' : 'Follows the master plan', style: AppText.s(12, W.w5, color: AppColors.muted)),
                    ]),
                  ),
                  AppBadge(c['custom'] == true ? 'Custom version' : 'Master', tone: c['custom'] == true ? Tone.warn : Tone.info, plain: true),
                  Builder(builder: (a) => AppIconButton(AppIcons.dots, tooltip: 'Client options', small: true, ghost: true, onPressed: () => menu(ctx, a, c))),
                ]),
                if ('${c['version_note'] ?? ''}'.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(left: 42),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(color: AppColors.warnBg, borderRadius: AppRadius.all(8)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                      const Padding(padding: EdgeInsets.only(top: 1), child: AppIcon(AppIcons.docLines, size: 14, color: AppColors.warnText)),
                      Expanded(child: Text('${c['version_note']}', style: AppText.s(12.5, W.w6, color: AppColors.warnText, h: 1.45))),
                    ]),
                  ),
              ]),
            ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(AppRadius.item)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              const Padding(padding: EdgeInsets.only(top: 2), child: AppIcon(AppIcons.info, size: 15, color: AppColors.muted)),
              Expanded(
                child: Text.rich(
                  const TextSpan(children: [
                    TextSpan(text: 'Master', style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: ' follows this plan as it is. '),
                    TextSpan(text: 'Custom version', style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: ' has a note with what is different for that client. The master plan and the other clients stay as they are.'),
                  ]),
                  style: AppText.s(12.5, W.w5, color: AppColors.text2, h: 1.5),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
        ]);
      },
    ),
    footer: (ctx) => [
      if (!ctx.isPhone)
        Expanded(child: ValueListenableBuilder(valueListenable: rows, builder: (_, l, _) => Text(countL(l), style: AppText.cap, maxLines: 1, overflow: TextOverflow.ellipsis))),
      AppButton('Close', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      if (m.canAssign) AppButton.primary('Assign to clients', icon: AppIcons.assign, expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop(true)),
    ],
  ).whenComplete(() => disposeLater([rows]));
}
