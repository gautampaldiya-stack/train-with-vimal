import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart' show confirmLogOut;
import '../../../app/services.dart';
import '../../../app/shell/page.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/hover.dart';

/// More tab (board `TrainerMoreMobile`, phone only — wider screens have the sidebar): the profile card
/// (→ My profile), the Library group and Log out. Settings, trainers and automations are not here (behaviour §3.7).
class TrainerMoreScreen extends StatelessWidget {
  const TrainerMoreScreen({super.key});

  static const _library = [
    ('Programs', 'Workout plans you assign', '/programs', AppIcons.dumbbell, AppColors.mbGreenBg, AppColors.mbGreenFg),
    ('Exercises', 'Moves, videos and form cues', '/exercises', AppIcons.exercisesAlt, AppColors.mbAmberBg, AppColors.mbAmberFg),
    ('Nutrition & foods', 'Meal plans and the food library', '/nutrition', AppIcons.apple, AppColors.mbPinkBg, AppColors.mbPinkFg),
    ('Habits & supplements', 'Daily habits and supplement plans', '/habits', AppIcons.checkCircle, AppColors.mbTealBg, AppColors.mbTealFg),
    ('Content library', 'Videos, PDFs and articles', '/content', AppIcons.library, AppColors.mbBlueBg, AppColors.accent),
  ];

  @override
  Widget build(BuildContext context) {
    final me = Services.session.me!;
    return StaffPage(
      maxWidth: 560,
      header: const PageTop(title: 'More'),
      children: [
        // The board spaces the More page 16 apart (other phone pages 14).
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
          MoreMeCard(initials: me.initials, name: me.name, sub: 'Trainer · My profile', onTap: () => context.go('/me')),
          MoreGroup('Library', [
            for (final (t, sub, path, icon, bg, fg) in _library) MoreRow(t, sub: sub, icon: icon, bg: bg, fg: fg, onTap: () => context.go(path)),
          ]),
          MoreGroup('You', [
            MoreRow('My profile', sub: 'Details, documents and your activity', icon: AppIcons.person, onTap: () => context.go('/me')),
            MoreRow('Calendar', sub: 'Sessions and check-in days', icon: AppIcons.calendar, bg: AppColors.mbAmberBg, fg: AppColors.mbAmberFg, onTap: () => context.go('/calendar')),
          ]),
          MoreGroup(null, [MoreRow('Log out', icon: AppIcons.logout, red: true, onTap: () => confirmLogOut(context))]),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Train With Vimal · Trainer workspace', textAlign: TextAlign.center, style: AppText.s(11.5, W.w5, color: AppColors.muted)),
          ),
        ]),
      ],
    );
  }
}

/// `.mb-me` — the account card on top of the More page.
class MoreMeCard extends StatelessWidget {
  const MoreMeCard({super.key, required this.initials, required this.name, required this.sub, required this.onTap});
  final String initials, name, sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: name,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, stops: [0, .7], colors: [AppColors.mbMeFrom, AppColors.white]),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.mbMeLine),
            ),
            child: Row(spacing: 14, children: [
              Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(begin: Alignment(-.5, -1), end: Alignment(.5, 1), colors: [AppColors.sky, AppColors.accent]),
                  boxShadow: [BoxShadow(color: AppColors.white, spreadRadius: 3), BoxShadow(color: AppColors.mbMeRing, spreadRadius: 4)],
                ),
                child: Text(initials, style: AppText.s(16, W.w8, color: AppColors.white)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(16, W.w8, ls: -0.16, color: h ? AppColors.accentText : AppColors.text)),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
                ]),
              ),
              const AppIcon(AppIcons.chevronRight, size: 18, color: AppColors.muted),
            ]),
          ),
        ),
      );
}

/// `.mb-grp` — an uppercase label over a card of rows. No label for the Log out card.
class MoreGroup extends StatelessWidget {
  const MoreGroup(this.label, this.rows, {super.key});
  final String? label;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(label!.toUpperCase(), style: AppText.s(11, W.w7, color: AppColors.muted, ls: 0.88)),
          ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1, thickness: 1, color: AppColors.line),
              rows[i],
            ],
          ]),
        ),
      ]);
}

/// `.mb-row` — 46 px row: coloured icon tile, title, chevron (no chevron on the red Log out row).
class MoreRow extends StatelessWidget {
  const MoreRow(this.title, {super.key, this.sub, required this.icon, this.bg = AppColors.accentSoft, this.fg = AppColors.accent, this.red = false, required this.onTap});
  final String title;

  /// Grey line under the title (the row grows to 58).
  final String? sub;
  final AppIconData icon;
  final Color bg, fg;
  final bool red;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: title,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            height: sub == null ? 46 : 58,
            color: h && !red ? AppColors.hover : AppColors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(spacing: 12, children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: red ? AppColors.badBg : bg, borderRadius: BorderRadius.circular(9)),
                child: AppIcon(icon, size: 18, color: red ? AppColors.mbRed : fg),
              ),
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(14, W.w6, color: red ? AppColors.mbRed : AppColors.text)),
                  if (sub != null) Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted)),
                ]),
              ),
              if (!red) const AppIcon(AppIcons.chevronRight, size: 18, color: AppColors.muted),
            ]),
          ),
        ),
      );
}
