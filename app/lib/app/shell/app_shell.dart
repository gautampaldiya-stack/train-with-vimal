import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/badge.dart';
import '../../core/widgets/hover.dart';
import '../../core/widgets/overlays.dart';
import '../../core/widgets/responsive.dart';
import '../../core/widgets/tooltip.dart';
import '../../features/client/train/workout_model.dart' show WorkoutController;
import '../services.dart';
import 'nav_items.dart';

/// Live counts for nav badges (approvals waiting, check-ins to review). Refreshed by screens and realtime.
class NavCounts {
  static final values = ValueNotifier<Map<String, int>>({});
  static void set(String key, int n) => values.value = {...values.value, key: n};
}

/// One shell for every role (docs/design.md §2):
/// desktop = sidebar 240 (collapsible to 68) + white rounded panel; tablet = 68 sidebar; phone = bottom bar.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child, required this.location});
  final Widget child;
  final String location;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _mini = false;
  // Pointer on the sidebar / on the edge button: the edge button only shows while either is true.
  bool _sideHover = false, _edgeHover = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _mini = p.getBool('twv.sideMini') ?? false);
    });
  }

  @override
  void didUpdateWidget(AppShell old) {
    super.didUpdateWidget(old);
    // Left Train and the workout logger: stop the workout timer (after the logger has saved).
    bool train(String p) => p == '/train' || p.startsWith('/train/');
    if (train(old.location) && !train(widget.location)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => WorkoutController.pauseLive());
    }
  }

  void _toggle() {
    setState(() => _mini = !_mini);
    SharedPreferences.getInstance().then((p) => p.setBool('twv.sideMini', _mini));
  }

  @override
  Widget build(BuildContext context) {
    final me = Services.session.me!;
    final isClient = me.role == Role.client;
    if (context.isPhone) {
      return ToastOffset(
        offset: 75,
        child: Scaffold(
          backgroundColor: isClient ? AppColors.caBg : AppColors.panel,
          body: SafeArea(bottom: false, child: widget.child),
          bottomNavigationBar: _BottomBar(items: bottomFor(me.role), location: widget.location),
        ),
      );
    }
    final mini = context.screen == ScreenSize.tablet || _mini;
    return ToastOffset(
      offset: 20,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          // The edge button sits in this Stack, above the page panel: inside the sidebar it was
          // painted under the panel and could not be clicked on its right half.
          child: Stack(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MouseRegion(
              onEnter: (_) => setState(() => _sideHover = true),
              onExit: (_) => setState(() => _sideHover = false),
              child: _Sidebar(items: sidebarFor(me.role), location: widget.location, mini: mini, me: me),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: isClient ? AppColors.caWebBg : AppColors.panel,
                  borderRadius: AppRadius.all(AppRadius.modal),
                  border: Border.all(color: AppColors.line),
                  boxShadow: AppShadows.panel,
                ),
                child: widget.child,
              ),
            ),
          ]),
          if (context.isDesktop)
            Positioned(
              top: 26,
              left: (mini ? 68 : 240) - 14,
              child: MouseRegion(
                onEnter: (_) => setState(() => _edgeHover = true),
                onExit: (_) => setState(() => _edgeHover = false),
                child: AnimatedOpacity(
                  opacity: _sideHover || _edgeHover ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: _EdgeButton(mini: mini, onTap: _toggle),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Round collapse / expand button on the sidebar edge (`.side .edge`). Its tooltip opens toward
/// the sidebar when expanded and below it when collapsed, so it never covers the page.
class _EdgeButton extends StatelessWidget {
  const _EdgeButton({required this.mini, required this.onTap});
  final bool mini;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppTooltip(
        message: mini ? 'Expand sidebar' : 'Collapse sidebar',
        side: mini ? TipSide.below : TipSide.left,
        gap: mini ? 6 : 8,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.card,
              shape: BoxShape.circle,
              border: Border.all(color: h ? AppColors.line2 : AppColors.line),
              boxShadow: const [BoxShadow(color: Color(0x14171717), blurRadius: 3, offset: Offset(0, 1))],
            ),
            alignment: Alignment.center,
            child: Transform.rotate(angle: mini ? 3.14159 : 0, child: AppIcon(AppIcons.collapse, size: 16, color: h ? AppColors.text : AppColors.text2)),
          ),
        ),
      );
}

bool _active(String location, String path) => location == path || location.startsWith('$path/');

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.items, required this.location, required this.mini, required this.me});
  final List<NavItem> items;
  final String location;
  final bool mini;
  final Me me;

  @override
  Widget build(BuildContext context) {
    final roleLine = switch (me.role) { Role.admin => 'Owner workspace', Role.trainer => 'Trainer workspace', Role.client => me.name };
    final children = <Widget>[];
    String? group;
    for (final it in items) {
      if (it.group != group) {
        group = it.group;
        children.add(mini
            ? Container(height: 1, color: AppColors.line, margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8))
            : Padding(padding: const EdgeInsets.fromLTRB(10, 14, 10, 6), child: Text(group!.toUpperCase(), style: AppText.over)));
      }
      children.add(_NavTile(item: it, on: _active(location, it.path), mini: mini));
    }
    return SizedBox(
        width: mini ? 68 : 240,
        child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: mini ? 10 : 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 2, children: [
              Padding(
                padding: mini ? const EdgeInsets.fromLTRB(0, 4, 0, 12) : const EdgeInsets.fromLTRB(8, 4, 8, 16),
                child: Row(mainAxisAlignment: mini ? MainAxisAlignment.center : MainAxisAlignment.start, spacing: 10, children: [
                  SvgPicture.asset('assets/logo.svg', width: mini ? 32 : 36, height: mini ? 32 : 36),
                  if (!mini)
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                        Text('Train With Vimal', style: AppText.s(15, W.w8, ls: -0.15), overflow: TextOverflow.ellipsis),
                        Text(roleLine, style: AppText.s(12, W.w5, color: AppColors.muted), overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                ]),
              ),
              ...children,
            ]),
          ),
        );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.on, required this.mini});
  final NavItem item;
  final bool on, mini;

  @override
  Widget build(BuildContext context) {
    final tile = Hover(
      onTap: () => context.go(item.path),
      builder: (context, h, _) => Container(
        height: 34,
        padding: mini ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: on || h ? AppColors.navActive : null,
          borderRadius: AppRadius.all(AppRadius.item),
          border: on || h ? Border.all(color: AppColors.line) : null,
          boxShadow: on ? const [BoxShadow(color: Color(0x0A171717), blurRadius: 2, offset: Offset(0, 1))] : null,
        ),
        child: ValueListenableBuilder(
          valueListenable: NavCounts.values,
          builder: (context, counts, _) {
            final n = item.badgeKey == null ? 0 : (counts[item.badgeKey] ?? 0);
            final icon = AppIcon(item.icon, size: 18, color: on ? AppColors.accent : (h ? AppColors.text : AppColors.text2));
            if (mini) {
              return Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                Center(child: icon),
                if (n > 0) Positioned(top: 3, right: 3, child: AppCount(n, size: 16)),
              ]);
            }
            return Row(spacing: 10, children: [
              icon,
              Expanded(child: Text(item.label, style: AppText.s(13.5, W.w6, color: on || h ? AppColors.text : AppColors.text2), overflow: TextOverflow.ellipsis)),
              if (n > 0) AppCount(n),
            ]);
          },
        ),
      ),
    );
    return mini ? AppTooltip(message: item.label, side: TipSide.right, gap: 10, child: tile) : tile;
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.items, required this.location});
  final List<NavItem> items;
  final String location;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(color: AppColors.white, border: Border(top: BorderSide(color: AppColors.line))),
        padding: EdgeInsets.fromLTRB(4, 4, 4, 12 + MediaQuery.paddingOf(context).bottom * .5),
        child: ValueListenableBuilder(
          valueListenable: NavCounts.values,
          builder: (context, counts, _) => Row(children: [
            for (final it in items)
              Expanded(
                child: Hover(
                  onTap: () => context.go(it.path),
                  builder: (_, h, _) {
                    final on = _active(location, it.path);
                    final c = on ? AppColors.accent : (h ? AppColors.text : AppColors.muted);
                    final n = it.badgeKey == null ? 0 : (counts[it.badgeKey] ?? 0);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(mainAxisSize: MainAxisSize.min, spacing: 3, children: [
                        Stack(clipBehavior: Clip.none, children: [
                          AppIcon(it.icon, size: 22, color: c),
                          if (n > 0)
                            Positioned(
                              top: -4,
                              left: 14,
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 16),
                                height: 16,
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: AppColors.red, borderRadius: AppRadius.all(8), border: Border.all(color: AppColors.white, width: 2)),
                                child: Text('$n', style: AppText.s(10, W.w7, color: AppColors.white, h: 1)),
                              ),
                            ),
                        ]),
                        Text(it.label, style: AppText.s(11, W.w6, color: c)),
                      ]),
                    );
                  },
                ),
              ),
          ]),
        ),
      );
}
