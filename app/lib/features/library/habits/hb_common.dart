import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tooltip.dart';
import '../../trainer/client_profile/cp_content_drawers.dart' show DrOpt, DrScrollList;
import '../lib_common.dart';

/// Shared bits of Habits & supplements (boards `Habits` / `HabitsMobile`): icons and tones, list rows, the save
/// bar, the side cards and the Assign to clients modal.

const habitIconKeys = ['water', 'steps', 'sleep', 'food', 'timer', 'sun', 'habit'];
const habitIconNames = ['Water', 'Steps', 'Sleep', 'Food', 'Timer', 'Sun', 'Habit'];

AppIconData habitIcon(String k) => switch (k) {
      'water' => AppIcons.water,
      'steps' => AppIcons.steps,
      'sleep' => AppIcons.moon,
      'food' => AppIcons.apple,
      'timer' => AppIcons.clock,
      'sun' => AppIcons.sun,
      _ => AppIcons.checkCircle,
    };

/// `.hb-ic` tone per icon (t1 blue, t2 green, t3 orange, t4 purple).
(Color, Color) habitTone(String k) => AppColors.hbTones[const {'water': 0, 'steps': 1, 'sleep': 3, 'food': 2, 'timer': 0, 'sun': 2}[k] ?? 1];

const suppTone = 3;

String hbNum(num n) => NumberFormat.decimalPattern('en_IN').format(n.round());

/// "Daily" / "Mon, Wed, Fri" / "3 times a week".
String freqLabel(Map h) => switch ('${h['frequency']}') {
      'days' => [for (final d in ((h['days'] as List?) ?? const []).cast<num>().toList()..sort()) weekdayShort[d.toInt()]].join(', '),
      'times_week' => '${h['times_per_week'] ?? 1} times a week',
      _ => 'Daily',
    };

/// "Tick" / "Counter · 12 glasses".
String kindLabel(Map h) => h['kind'] == 'counter' ? 'Counter · ${hbNum((h['target'] as num?) ?? 0)} ${h['unit'] ?? ''}'.trim() : 'Tick';

/// Supplement timings in the order the client sees them. The editor offers the board's five; morning and night
/// are older plans' values and still show.
const suppTimings = [
  ('breakfast', 'Breakfast'),
  ('morning', 'Morning'),
  ('pre_workout', 'Pre-workout'),
  ('post_workout', 'Post-workout'),
  ('any', 'Any time'),
  ('night', 'Night'),
  ('before_bed', 'Before bed'),
];
const suppPickTimings = ['breakfast', 'pre_workout', 'post_workout', 'any', 'before_bed'];

String timingLabel(Object? k) => suppTimings.firstWhere((t) => t.$1 == '$k', orElse: () => suppTimings[4]).$2;

/// "Every day" / "Mon, Tue, Thu, Fri". An empty list is every day.
String suppDays(Object? days) {
  final d = ((days as List?) ?? const []).cast<num>().map((x) => x.toInt()).toList()..sort();
  return d.isEmpty || d.length == 7 ? 'Every day' : d.map((x) => weekdayShort[x]).join(', ');
}

/// `.hb-ic`: tinted tile, 34 (30 small, 44 large).
class HbIcon extends StatelessWidget {
  const HbIcon(this.icon, this.tone, {super.key, this.size = 34});
  final AppIconData icon;
  final (Color, Color) tone;
  final double size;
  @override
  Widget build(BuildContext context) => IconTile(icon,
      size: size, bg: tone.$1, fg: tone.$2, radius: size >= 44 ? 11 : (size <= 30 ? 8 : 9), iconSize: size >= 44 ? 22 : (size <= 30 ? 16 : 18));
}

/// `.hb-li`: icon, name, grey line, clients count; picked = blue. On phone a chevron ends the row.
class HbListRow extends StatelessWidget {
  const HbListRow({super.key, required this.icon, required this.tone, required this.title, required this.sub, required this.count, required this.on, required this.onTap});
  final AppIconData icon;
  final (Color, Color) tone;
  final String title, sub;
  final int count;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    return Hover(
      onTap: onTap,
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on && !phone ? AppColors.accentSoft : (h ? AppColors.hover : null),
          borderRadius: AppRadius.all(10),
          border: Border.all(color: on && !phone ? AppColors.hbOnLine : Colors.transparent),
        ),
        child: Row(spacing: 10, children: [
          HbIcon(icon, tone, size: 30),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted)),
            ]),
          ),
          AppTooltip(
            message: count == 0 ? 'Not assigned' : plural(count, 'client'),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 3, children: [
              const AppIcon(AppIcons.clients, size: 14, color: AppColors.muted),
              Text('$count', style: AppText.s(12, count == 0 ? W.w6 : W.w7, color: count == 0 ? AppColors.muted : AppColors.text2)),
            ]),
          ),
          if (phone) const AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.text2),
        ]),
      ),
    );
  }
}

/// `.hb-eh`: large icon, name, grey line, then the header buttons.
class HbEditorHead extends StatelessWidget {
  const HbEditorHead({super.key, required this.icon, required this.tone, required this.title, required this.sub, this.actions = const []});
  final AppIconData icon;
  final (Color, Color) tone;
  final String title, sub;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: phone ? 14 : 18, vertical: phone ? 14 : 16),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(spacing: 12, children: [
        HbIcon(icon, tone, size: 44),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(title.isEmpty ? 'Untitled' : title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.h3),
            Text(sub, style: AppText.s(12.5, W.w6, color: AppColors.muted)),
          ]),
        ),
        ...actions,
      ]),
    );
  }
}

/// `.hb-save`: "Unsaved changes" + Discard + Save changes, or "All changes saved" with Save greyed.
class HbSaveBar extends StatelessWidget {
  const HbSaveBar({super.key, required this.dirty, required this.saving, required this.canEdit, this.canCopy = false, required this.onDiscard, required this.onSave});
  final bool dirty, saving, canEdit;

  /// Read-only but may duplicate (a gym item, D-45): say so instead of "ask for access".
  final bool canCopy;
  final VoidCallback onDiscard, onSave;
  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final style = AppText.s(12.5, W.w6, color: AppColors.muted);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: phone ? 14 : 18, vertical: 10),
      decoration: const BoxDecoration(color: AppColors.hbSaveBg, border: Border(top: BorderSide(color: AppColors.line))),
      child: Row(spacing: 8, children: [
        if (!canEdit) ...[
          const AppIcon(AppIcons.lock, size: 15, color: AppColors.muted),
          Expanded(
            child: Text(canCopy ? 'Only Vimal can change this one. Duplicate it from ⋯ to make your own.' : 'You can look, not change. Ask Vimal for edit access.',
                style: style),
          ),
        ] else if (dirty) ...[
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.hbDot, shape: BoxShape.circle)),
          Expanded(child: Text('Unsaved changes', maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
          AppButton('Discard', size: BtnSize.sm, onPressed: saving ? null : onDiscard),
          AppButton.primary('Save changes', icon: AppIcons.checkCircle, size: BtnSize.sm, loading: saving, onPressed: onSave),
        ] else ...[
          const AppIcon(AppIcons.checkCircle, size: 15, color: AppColors.okText),
          Expanded(child: Text('All changes saved', maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
          Opacity(opacity: .5, child: AppButton.primary('Save changes', icon: AppIcons.checkCircle, size: BtnSize.sm)),
        ],
      ]),
    );
  }
}

/// `.hb-pv` card: h3 title with an optional text button, then the body.
class HbSideCard extends StatelessWidget {
  const HbSideCard({super.key, required this.title, this.action, required this.children});
  final String title;
  final Widget? action;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          SizedBox(
            height: 30,
            child: Row(children: [Expanded(child: Text(title, style: AppText.s(14.5, W.w8))), ?action]),
          ),
          ...children,
        ]),
      );
}

/// `.hb-phone`: the grey phone frame around a preview.
class HbPhone extends StatelessWidget {
  const HbPhone({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.hbPhone, borderRadius: AppRadius.all(16)), child: child);
}

/// Assigned to: who is on it (`.mb-cl` rows open the client), Assign, or the empty line.
class HbAssignedCard extends StatelessWidget {
  const HbAssignedCard({super.key, required this.clients, required this.sub, required this.empty, this.onAssign});
  final List<Map>? clients;
  final String sub, empty;
  final VoidCallback? onAssign;
  @override
  Widget build(BuildContext context) {
    final list = clients;
    return HbSideCard(
      title: 'Assigned to',
      action: onAssign == null ? null : AppButton('Assign', kind: BtnKind.text, size: BtnSize.sm, icon: AppIcons.plus, onPressed: onAssign),
      children: [
        if (list == null)
          const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)))
        else if (list.isEmpty)
          Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
            const Padding(padding: EdgeInsets.only(top: 2), child: AppIcon(AppIcons.clients, size: 16, color: AppColors.muted)),
            Expanded(child: Text(empty, style: AppText.s(13, W.w5, color: AppColors.muted, h: 1.5))),
          ])
        else
          for (final c in list)
            Hover(
              onTap: () => context.go('/clients/${c['id']}?tab=plans'),
              builder: (_, h, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(spacing: 10, children: [
                  AppAvatar('${c['full_name']}', size: 28, initials: '${c['initials'] ?? ''}', colors: AppColors.avatarCode('${c['avatar_color'] ?? 'c1'}')),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                      Text('${c['full_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7, color: h ? AppColors.accentText : AppColors.text)),
                      Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted)),
                    ]),
                  ),
                  const AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.text2),
                ]),
              ),
            ),
      ],
    );
  }
}

/// Assign to clients (habit or supplement plan): every client this person can see, ticked = on it now. Gives back
/// the clients on it after saving.
Future<List<Map>?> showHbAssign(BuildContext context, {required String url, required String name, required String done}) async {
  final picked = ValueNotifier<Set<String>?>(null);
  final q = ValueNotifier('');
  var before = <String>{};
  final data = Services.api.get<List>('${url}assign/').then((all) {
    before = {for (final c in all) if ((c as Map)['on_it'] == true) '${c['id']}'};
    picked.value = {...before};
    return [for (final x in all) x as Map];
  });
  var saving = false;
  final r = await showAppModal<List<Map>>(
    context,
    title: 'Assign to clients',
    body: name,
    icon: AppIcons.assign,
    width: 480,
    content: (ctx) => FutureBuilder<List<Map>>(
      future: data,
      builder: (ctx, s) {
        if (s.hasError) return const EmptyState('Could not load your clients');
        if (!s.hasData) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)));
        final all = s.data!;
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
                      return DrOpt(
                        title: '${c['full_name']}',
                        sub: before.contains(id) ? 'On it now' : 'Not on it',
                        multi: true,
                        on: sel,
                        thumb: AppAvatar('${c['full_name']}', size: 28, initials: '${c['initials'] ?? ''}', colors: AppColors.avatarCode('${c['avatar_color'] ?? 'c1'}')),
                        onTap: () => picked.value = sel ? ({...picked.value!}..remove(id)) : {...picked.value!, id},
                      );
                    }(),
                ]),
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
                      await Services.api.post<Map>('${url}assign/', {'clients': p.toList()});
                      final all = await data;
                      if (ctx.mounted) Navigator.of(ctx).pop([for (final c in all) if (p.contains('${c['id']}')) c]);
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
  if (r != null && context.mounted) showToast(context, done, sub: r.isEmpty ? 'No clients' : plural(r.length, 'client'));
  return r;
}

/// The clients on a habit or plan now (for the Assigned to card).
Future<List<Map>> hbClientsOn(String url) async =>
    [for (final c in await Services.api.get<List>('${url}assign/')) if ((c as Map)['on_it'] == true) c];

/// `.hb-days`: seven 36 round day buttons; picked = blue.
class HbDays extends StatelessWidget {
  const HbDays({super.key, required this.days, required this.onTap, this.enabled = true});
  final Set<int> days;
  final ValueChanged<int> onTap;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (var d = 0; d < 7; d++)
          AppTooltip(
            message: weekdayNames[d],
            child: Hover(
              onTap: enabled ? () => onTap(d) : null,
              builder: (_, h, _) {
                final on = days.contains(d);
                return Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? AppColors.accent : AppColors.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: on ? AppColors.accent : (h ? AppColors.hbIcoHover : AppColors.line2)),
                  ),
                  child: Text(weekLetters[d], style: AppText.s(12.5, W.w7, color: on ? AppColors.white : AppColors.text2)),
                );
              },
            ),
          ),
      ]);
}

/// A label over a field (`.field label`), like the boards' editor.
Widget hbField(String label, Widget child, {String? hint, String? error, bool req = false}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      Text.rich(TextSpan(text: label, style: AppText.s(13, W.w7), children: [
        if (req) TextSpan(text: '*', style: AppText.s(13, W.w7, color: AppColors.badText)),
      ])),
      child,
      if (error != null)
        Text(error, style: AppText.s(12, W.w6, color: AppColors.badText))
      else if (hint != null)
        Text(hint, style: AppText.s(12, W.w5, color: AppColors.muted)),
    ]);
