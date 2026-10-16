import 'services.dart';
import 'shell/nav_items.dart';

const appName = 'Train With Vimal';

/// Pages outside the sidebar (sign-in flow) and deeper pages, by path.
const _named = {
  '/login': 'Log in',
  '/pending': 'Waiting for approval',
  '/setup': 'Set up your plan',
  '/setup/checklist': 'Set up your plan',
  '/setup/done': 'You’re all set',
  '/forgot': 'Reset password',
  '/reset-password': 'Reset password',
  '/join': 'Join',
  '/start': 'Log in',
  '/verify': 'Verify your email',
  '/verify-email': 'Verify your email',
  '/permissions': 'Permissions',
  '/food/log': 'Log food',
  '/progress/history': 'Progress history',
  '/progress/photos': 'Progress photos',
  '/progress/compare': 'Compare photos',
  '/more/about': 'About',
};

/// The browser tab title for [path]: "My clients · Train With Vimal". Uses the sidebar names of the person's role,
/// so the tab reads the same as the menu.
String pageTitle(String path) {
  String? name = _named[path];
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  if (name == null && parts.isNotEmpty) name = _named['/${parts.first}'];
  if (name == null && parts.isNotEmpty) {
    final role = Services.session.me?.role;
    if (role != null) {
      for (final n in sidebarFor(role)) {
        if (n.path == '/${parts.first}') {
          name = n.label;
          break;
        }
      }
    }
    if (parts.first == 'clients' && parts.length > 1) name = 'Client profile';
    if (parts.first == 'train' && parts.length > 1) name = 'Workout';
    if (parts.first == 'checkins' && parts.length > 1 && role == Role.client) name = 'Check-in';
  }
  return name == null ? appName : '$name · $appName';
}
