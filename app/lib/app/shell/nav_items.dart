import '../../core/icons/app_icons.dart';
import '../services.dart';

class NavItem {
  const NavItem(this.label, this.path, this.icon, {this.group, this.badgeKey});
  final String label, path;
  final AppIconData icon;
  final String? group;

  /// Which live count shows next to it (e.g. 'approvals', 'checkins').
  final String? badgeKey;
}

/// Sidebar order from docs/design.md §2.1.
/// A trainer given "Create and edit automations" also gets Automations ([automations]).
List<NavItem> sidebarFor(Role role, {bool automations = false}) => switch (role) {
      Role.admin => const [
          NavItem('Dashboard', '/dashboard', AppIcons.dashboard),
          NavItem('Clients', '/clients', AppIcons.clients),
          NavItem('Approvals', '/approvals', AppIcons.approvals, badgeKey: 'approvals'),
          NavItem('Trainers', '/trainers', AppIcons.trainers),
          NavItem('Calendar', '/calendar', AppIcons.calendar),
          NavItem('Activity log', '/activity', AppIcons.activity),
          NavItem('Programs', '/programs', AppIcons.programs, group: 'Build'),
          NavItem('Exercises', '/exercises', AppIcons.exercises, group: 'Build'),
          NavItem('Nutrition & foods', '/nutrition', AppIcons.nutrition, group: 'Build'),
          NavItem('Habits & supplements', '/habits', AppIcons.habitsSupps, group: 'Build'),
          NavItem('Forms & check-ins', '/forms', AppIcons.forms, group: 'Build'),
          NavItem('Content library', '/content', AppIcons.content, group: 'Build'),
          NavItem('Automations', '/automations', AppIcons.automations, group: 'Engage'),
          NavItem('Emails & alerts', '/emails', AppIcons.emails, group: 'Engage'),
          NavItem('Settings', '/settings', AppIcons.settings, group: 'Workspace'),
        ],
      Role.trainer => [
          const NavItem('Dashboard', '/dashboard', AppIcons.home),
          const NavItem('My clients', '/clients', AppIcons.clientsAlt),
          const NavItem('Check-ins', '/checkins', AppIcons.clipboard, badgeKey: 'checkins'),
          const NavItem('Calendar', '/calendar', AppIcons.calendarAlt),
          const NavItem('Programs', '/programs', AppIcons.dumbbell, group: 'Library'),
          const NavItem('Exercises', '/exercises', AppIcons.exercisesAlt, group: 'Library'),
          const NavItem('Nutrition & foods', '/nutrition', AppIcons.apple, group: 'Library'),
          const NavItem('Habits & supplements', '/habits', AppIcons.checkCircle, group: 'Library'),
          const NavItem('Content library', '/content', AppIcons.library, group: 'Library'),
          if (automations) const NavItem('Automations', '/automations', AppIcons.automations, group: 'Library'),
          const NavItem('My profile', '/me', AppIcons.person, group: 'You'),
        ],
      Role.client => const [
          NavItem('Today', '/home', AppIcons.home),
          NavItem('Training', '/train', AppIcons.dumbbell),
          NavItem('Nutrition', '/food', AppIcons.food),
          NavItem('Habits', '/habits', AppIcons.target),
          NavItem('Progress', '/progress', AppIcons.progress),
          NavItem('Check-ins', '/checkins', AppIcons.clipboard),
          NavItem('Library', '/library', AppIcons.library),
          NavItem('My account', '/more', AppIcons.menu, group: 'You'),
        ],
    };

/// Phone bottom bar (5 tabs).
List<NavItem> bottomFor(Role role) => switch (role) {
      Role.admin => const [
          NavItem('Home', '/dashboard', AppIcons.home),
          NavItem('Clients', '/clients', AppIcons.clientsAlt),
          NavItem('Approvals', '/approvals', AppIcons.approvalsAlt, badgeKey: 'approvals'),
          NavItem('Calendar', '/calendar', AppIcons.calendarAlt),
          NavItem('More', '/more', AppIcons.menu),
        ],
      Role.trainer => const [
          NavItem('Home', '/dashboard', AppIcons.home),
          NavItem('Clients', '/clients', AppIcons.clientsAlt),
          NavItem('Check-ins', '/checkins', AppIcons.checkinsBadge, badgeKey: 'checkins'),
          NavItem('Calendar', '/calendar', AppIcons.calendarAlt),
          NavItem('More', '/more', AppIcons.menu),
        ],
      Role.client => const [
          NavItem('Home', '/home', AppIcons.home),
          NavItem('Train', '/train', AppIcons.dumbbell),
          NavItem('Food', '/food', AppIcons.food),
          NavItem('Progress', '/progress', AppIcons.progress),
          NavItem('More', '/more', AppIcons.menu),
        ],
    };
