import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart' show confirmLogOut;
import '../../../app/services.dart';
import '../../../app/shell/page.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../trainer/more/more_screen.dart' show MoreGroup, MoreMeCard, MoreRow;

/// More tab (board `AdminMoreMobile`, phone only — wider screens have the sidebar): the owner card (→ Settings),
/// the sidebar pages the bottom bar has no room for, and Log out.
class AdminMoreScreen extends StatelessWidget {
  const AdminMoreScreen({super.key});

  static const _groups = [
    ('Pages', [
      ('Trainers', '/trainers', AppIcons.trainers, AppColors.mbBlueBg, AppColors.accent),
      ('Activity log', '/activity', AppIcons.activity, AppColors.mbTealBg, AppColors.mbTealFg),
    ]),
    ('Build', [
      ('Programs', '/programs', AppIcons.programs, AppColors.mbGreenBg, AppColors.mbGreenFg),
      ('Exercises', '/exercises', AppIcons.exercises, AppColors.mbAmberBg, AppColors.mbAmberFg),
      ('Nutrition & foods', '/nutrition', AppIcons.nutrition, AppColors.mbPinkBg, AppColors.mbPinkFg),
      ('Habits & supplements', '/habits', AppIcons.habitsSupps, AppColors.mbTealBg, AppColors.mbTealFg),
      ('Forms & check-ins', '/forms', AppIcons.forms, AppColors.mbPurpleBg, AppColors.mbPurpleFg),
      ('Content library', '/content', AppIcons.content, AppColors.mbBlueBg, AppColors.accent),
    ]),
    ('Engage', [
      ('Automations', '/automations', AppIcons.automations, AppColors.mbAmberBg, AppColors.mbAmberFg),
      ('Emails & alerts', '/emails', AppIcons.emails, AppColors.mbPurpleBg, AppColors.mbPurpleFg),
    ]),
    ('Workspace', [
      ('Notifications', '/notifications', AppIcons.bell, AppColors.mbBlueBg, AppColors.accent),
      ('Settings', '/settings', AppIcons.settings, AppColors.sub, AppColors.text2),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final me = Services.session.me!;
    return StaffPage(
      maxWidth: 560,
      header: const PageTop(title: 'More'),
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
          MoreMeCard(initials: me.initials, name: me.name.split(' ').first, sub: 'Owner · Train With Vimal', onTap: () => context.go('/me')),
          for (final (label, rows) in _groups)
            MoreGroup(label, [
              for (final (t, path, icon, bg, fg) in rows) MoreRow(t, icon: icon, bg: bg, fg: fg, onTap: () => context.go(path)),
            ]),
          MoreGroup(null, [MoreRow('Log out', icon: AppIcons.logout, red: true, onTap: () => confirmLogOut(context))]),
        ]),
      ],
    );
  }
}
