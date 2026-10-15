import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import 'home_model.dart';
import 'home_parts.dart';

/// Sheets of the client Home board. On wide screens [showAppSheet] makes them centred 520 cards.

/// Notification row (`ch-n`), used by the sheet and the web dropdown.
class NoticeRow extends StatelessWidget {
  const NoticeRow(this.n, {super.key, required this.first, required this.onTap});
  final HomeNotice n;
  final bool first;
  final VoidCallback? onTap;

  (AppIconData, ChTone) get _look => switch (n.event) {
        'checkin_reviewed' || 'checkin_due' || 'form_sent' => (AppIcons.clipboard, ChTone.amber),
        'personal_best' || 'workout_done' => (AppIcons.dumbbell, ChTone.blue),
        'plan_updated' || 'program_assigned' || 'meal_plan_assigned' => (AppIcons.bell, ChTone.green),
        'session_booked' || 'session_moved' => (AppIcons.calendarAlt, ChTone.blue),
        _ => (AppIcons.bell, ChTone.gray),
      };

  @override
  Widget build(BuildContext context) {
    final (icon, tone) = _look;
    return ChRow(first: first, top: true, onTap: onTap, children: [
      ChIcon(icon, tone: tone),
      Expanded(child: ChTwoLine(n.title, n.body, size: 13.5, dot: !n.read)),
      Padding(padding: const EdgeInsets.only(top: 2), child: Text(since(n.at), style: AppText.s(11.5, W.w4, color: AppColors.muted))),
    ]);
  }
}

/// Where a notification goes when tapped (its `data.route`, else by event).
String? noticeRoute(HomeNotice n) {
  if (n.route.startsWith('/')) return n.route;
  return switch (n.event) {
    'checkin_reviewed' || 'checkin_due' => '/checkins',
    'personal_best' => '/progress',
    'plan_updated' || 'program_assigned' => '/train',
    'meal_plan_assigned' => '/food',
    _ => null,
  };
}

Future<void> showNoticesSheet(BuildContext context, HomeController c) => showAppSheet(
      context,
      title: 'Notifications',
      sub: c.data!.unread > 0 ? '${c.data!.unread} new' : 'All read',
      builder: (ctx) {
        final list = c.data!.notices;
        if (list.isEmpty) {
          return Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Text('No notifications yet.', textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, n) in list.indexed)
            NoticeRow(n, first: i == 0, onTap: noticeRoute(n) == null ? null : () {
              Navigator.of(ctx).pop();
              context.go(noticeRoute(n)!);
            }),
        ]);
      },
      footerStretch: true,
      footer: (ctx) => [
        CaButton('Mark all as read', kind: CaBtnKind.out, icon: AppIcons.check, onPressed: () {
          Navigator.of(ctx).pop();
          c.readAll();
          showToast(context, 'All notifications read', kind: ToastKind.ok);
        }),
      ],
    );

/// "Log food": search (opens the Food tab) and the plan's meals with "Ate it".
Future<void> showLogFoodSheet(BuildContext context, HomeController c, void Function(HomeMeal) eat) => showAppSheet(
      context,
      title: 'Log food',
      sub: 'What did you eat?',
      builder: (ctx) => ListenableBuilder(
        listenable: c,
        builder: (ctx, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
          Hover(
            onTap: () {
              Navigator.of(ctx).pop();
              context.go('/food');
            },
            builder: (_, h, _) => Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: h ? AppColors.line2 : AppColors.line)),
              child: Row(spacing: 8, children: [
                const AppIcon(AppIcons.search, color: AppColors.muted),
                Expanded(child: Text('Search foods, e.g. dal, roti, paneer', overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w4, color: AppColors.muted))),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Pull(bottom: 4, child: Text('FROM YOUR PLAN TODAY', style: AppText.s(12, W.w8, color: AppColors.muted, ls: .48))),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, m) in c.data!.meals.indexed)
              ChRow(first: i == 0, children: [
                ChIcon(AppIcons.food, tone: m.eaten ? ChTone.green : ChTone.gray),
                Expanded(child: ChTwoLine(m.foods, '${m.name}, ${mealTime(m.time)} · ${inNum(m.kcal)} kcal', size: 13.5)),
                if (m.eaten) const ChOk('Logged') else if (m.open) chSm('Ate it', () => eat(m)),
              ]),
          ]),
        ]),
      ),
    );

/// All exercises of a day (`+ N more` / `See all exercises`).
Future<void> showWorkoutPreview(BuildContext context, HomeDay d) => showAppSheet(
      context,
      title: d.name,
      sub: '${_weekday(d.date)} · ${d.exercises.length} exercises',
      builder: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, e) in d.exercises.indexed)
          ChRow(first: i == 0, children: [
            const ChIcon(AppIcons.dumbbell, tone: ChTone.blue),
            Expanded(child: ChTwoLine(e.name, e.line, size: 13.5)),
          ]),
      ]),
    );

String _weekday(DateTime d) => const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][d.weekday - 1];

/// "Add steps" (and any other counter habit): stepper, quick adds, bar, Save.
Future<void> showCounterSheet(BuildContext context, HomeController c, HomeHabit h) {
  final steps = h.icon == 'steps';
  final step = steps ? 500 : _niceStep(h.target);
  final quick = steps ? [1000, 2000, 5000, 10000] : [step, step * 2, step * 4, step * 8];
  final unit = h.unit.isEmpty ? '' : ' ${h.unit}';
  final v = ValueNotifier(h.value);
  return showAppSheet(
    context,
    title: steps ? 'Add steps' : 'Add to ${h.name}',
    sub: 'Goal ${inNum(h.target)}$unit a day',
    builder: (_) => ValueListenableBuilder(
      valueListenable: v,
      builder: (_, n, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        ChBigStepper(value: inNum(n), label: '${h.unit.isEmpty ? 'done' : h.unit} today', onMinus: () => v.value = (n - step).clamp(0, 200000), onPlus: () => v.value = (n + step).clamp(0, 200000)),
        ChQuick(items: [for (final q in quick) ('+${inNum(q)}', q)], onPick: (q) => v.value = (n + q).clamp(0, 200000)),
        Padding(padding: const EdgeInsets.only(top: 6), child: ChBar(h.target > 0 ? n / h.target : 0, color: AppColors.okSolid, height: 8)),
        Text(n >= h.target ? 'Goal reached' : '${inNum(h.target - n)}$unit to go', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
      ]),
    ),
    footerStretch: true,
    footer: (ctx) => [
      CaButton(steps ? 'Save steps' : 'Save', icon: AppIcons.check, onPressed: () {
        Navigator.of(ctx).pop();
        final before = h.value, n = v.value;
        c.setHabit(h, value: n);
        if (n >= h.target && before < h.target) {
          showToast(context, steps ? 'Step goal reached!' : 'Goal reached!', sub: '${inNum(n)}$unit today', kind: ToastKind.star);
        } else {
          showToast(context, steps ? 'Steps saved' : 'Saved', sub: '${inNum(n)} of ${inNum(h.target)} today', kind: ToastKind.ok, action: 'Undo', onAction: () => c.setHabit(h, value: before));
        }
      }),
    ],
  );
}

int _niceStep(int target) {
  final raw = (target / 16).clamp(1, 100000).toDouble();
  for (final s in [1, 2, 5, 10, 20, 25, 50, 100, 250, 500, 1000, 2500, 5000]) {
    if (s >= raw) return s;
  }
  return 5000;
}

/// "How long did you sleep?": minutes in 15 min steps, quick 5–10 h.
Future<void> showSleepSheet(BuildContext context, HomeController c, HomeHabit h) {
  final goal = h.target > 0 ? h.target : 420;
  final v = ValueNotifier(h.value);
  return showAppSheet(
    context,
    title: 'How long did you sleep?',
    sub: 'Last night · goal ${goal % 60 == 0 ? '${goal ~/ 60} hours' : hoursMin(goal)}',
    builder: (_) => ValueListenableBuilder(
      valueListenable: v,
      builder: (_, n, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        ChBigStepper(
          value: hoursMin(n),
          label: n >= goal ? 'Goal met' : '${hoursMin(goal - n)} short of ${hoursMin(goal)}',
          onMinus: () => v.value = (n - 15).clamp(0, 900),
          onPlus: () => v.value = (n + 15).clamp(0, 900),
        ),
        ChQuick(items: [for (final hr in [5, 6, 7, 8, 9, 10]) ('$hr h', hr * 60)], onPick: (m) => v.value = m, isOn: (m) => m == n),
      ]),
    ),
    footerStretch: true,
    footer: (ctx) => [
      CaButton('Save sleep', icon: AppIcons.check, onPressed: () {
        Navigator.of(ctx).pop();
        final before = h.value, n = v.value;
        c.setHabit(h, value: n);
        showToast(context, 'Sleep saved',
            sub: '${hoursMin(n)}${n >= goal ? ' · goal met' : ' · aim for ${hoursMin(goal)} tonight'}',
            kind: n >= goal ? ToastKind.ok : ToastKind.info,
            action: 'Undo',
            onAction: () => c.setHabit(h, value: before));
      }),
    ],
  );
}
