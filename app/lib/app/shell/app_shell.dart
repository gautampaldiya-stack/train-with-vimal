import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:twv/core/widgets/twv_logo.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/badge.dart';
import '../../core/widgets/hover.dart';
import '../../core/widgets/overlays.dart';
import '../../core/widgets/responsive.dart';
import '../../core/widgets/tooltip.dart';
import '../../core/live/live_notice.dart';
import '../../features/client/train/train_model.dart' show clockText;
import '../../features/client/train/workout_model.dart' show WorkoutController, WorkoutFeel;
import '../../features/client/train/workout_screen.dart' show WorkoutPanel, WorkoutScreen, openWorkout;
import '../services.dart';
import 'back_nav.dart';
import 'nav_items.dart';

/// A page can hide the phone bottom bar for a while (Home → Edit home shows its own bar there).
final hideBottomBar = ValueNotifier<bool>(false);

/// Live counts for nav badges (approvals waiting, check-ins to review). Refreshed by screens and realtime.
class NavCounts {
  static final values = ValueNotifier<Map<String, int>>({});
  static void set(String key, int n) => values.value = {...values.value, key: n};

  /// Whose counts these are: a new log in (another user on the same device) starts empty.
  static String? owner;
  static void claim(String userId) {
    if (owner == userId) return;
    owner = userId;
    values.value = {};
  }
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
  double _barH = 0; // the phone bottom bar's height, for the toast
  // Pointer on the sidebar / on the edge button: the edge button only shows while either is true.
  bool _sideHover = false, _edgeHover = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _mini = p.getBool('twv.sideMini') ?? false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCounts()); // not during build: it notifies the badges
    hideBottomBar.addListener(_barChanged);
    if (Services.session.me?.role == Role.client) {
      // A workout running on this phone comes back after an app restart: mini bar, clock, notification (F33).
      WorkoutController.revive();
      WorkoutFeel.load(); // My account and the logger show the saved sound / vibration choice
      LiveNotice.onOpen = () {
        if (mounted) openWorkout(context);
      };
    }
    ToastHost.sheets.addListener(_barChanged); // any bottom sheet open hides the tabs (Probid 2026-11-03, A1)
    // A change saved offline that the server refused later: say so, it is not kept (before it went silently).
    _refused = Services.outbox.results.where((r) => r.late && r.error != null && !r.error!.offline).listen((r) {
      if (mounted) showToast(context, 'A change you made offline was not saved', sub: r.error!.message, kind: ToastKind.err);
    });
  }

  StreamSubscription? _refused;

  void _barChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    hideBottomBar.removeListener(_barChanged);
    ToastHost.sheets.removeListener(_barChanged);
    _refused?.cancel();
    super.dispose();
  }

  /// The trainer's Check-ins badge (and the admin's Approvals badge) shows on every page (board TrainerMoreMobile), not only after
  /// Dashboard or Check-ins loaded. Those pages keep it fresh afterwards.
  Future<void> _loadCounts() async {
    final me = Services.session.me;
    if (me == null) return;
    NavCounts.claim(me.id);
    if (me.role == Role.admin && !NavCounts.values.value.containsKey('approvals')) {
      try {
        final c = await Services.api.get<Map>('approvals/counts/');
        if (!NavCounts.values.value.containsKey('approvals')) NavCounts.set('approvals', (c['waiting'] as num?)?.toInt() ?? 0);
      } catch (_) {}
      return;
    }
    if (me.role != Role.trainer || NavCounts.values.value.containsKey('checkins')) return;
    try {
      final c = await Services.api.get<Map>('checkins/counts/');
      if (!NavCounts.values.value.containsKey('checkins')) NavCounts.set('checkins', (c['to_review'] as num?)?.toInt() ?? 0);
    } catch (_) {
      // Offline or signed out: the badge simply waits for the next page load.
    }
  }

  @override
  void didUpdateWidget(AppShell old) {
    super.didUpdateWidget(old);
    // The logger's ⌄ goes back to the page it was opened from. Leaving it no longer stops the clock: the workout
    // keeps running under the mini bar (Strong-style, tracker F33).
    if (widget.location.startsWith('/train/workout') && !old.location.startsWith('/train/workout')) {
      WorkoutController.backTo = old.location;
    }
  }

  void _toggle() {
    setState(() => _mini = !_mini);
    SharedPreferences.getInstance().then((p) => p.setBool('twv.sideMini', _mini));
  }

  @override
  Widget build(BuildContext context) => PopScope(
        // The phone's back button follows the app's parents and ends at the exit sheet (Phase 4, back_nav.dart).
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) AppBack.handle(context, widget.location);
        },
        // Status bar (Phase 5): dark icons on every page by default. Only pages with a blue hero (client Home, the
        // trainer dashboard) set light icons, inside this region, so leaving them brings the dark icons back. Before,
        // nothing set it here and the phone kept Home's white icons on white pages.
        child: AnnotatedRegion<SystemUiOverlayStyle>(value: _statusDark, child: _build(context)),
      );

  static const _statusDark = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark, // Android
    statusBarBrightness: Brightness.light, // iOS: light background → dark text
  );

  Widget _build(BuildContext context) {
    // a frame while the session is not there (app start, signing out on the way to /login): a plain page, never a
    // grey error box (seen on the phone 18 Nov)
    final me = Services.session.me;
    if (me == null) return const ColoredBox(color: AppColors.caBg, child: SizedBox.expand());
    final isClient = me.role == Role.client;
    if (context.isPhone) {
      // Client: the bottom bar only on the main tabs; sub-pages and the workout logger have their own back button.
      final bar = (!isClient || AppBack.isTab(widget.location, me.role)) && !hideBottomBar.value && ToastHost.sheets.value == 0;
      // Toasts sit 10 above the bar, measured (it grows with the phone's bottom inset); the host adds that inset
      // itself, so it is taken off here. Before, a fixed 75 left a gap that changed from phone to phone.
      final inset = MediaQuery.paddingOf(context).bottom;
      // The status bar inset is kept by each page itself (router `_page`), not here: when it changed with the location,
      // the page sliding out to Home jumped up under the status bar (Probid 18 Nov).
      const top = false;
      if (isClient) {
        // Client phone: the workout logger is one panel over the page, under the tab bar (Strong, Probid 17 Nov).
        return Scaffold(
          backgroundColor: AppColors.caBg,
          body: _WorkoutPanelHost(
            bar: bar,
            tab: AppBack.isTab(widget.location, me.role),
            nav: _BottomBar(items: bottomFor(me.role), location: widget.location),
            page: (bottomSafe) => SafeArea(bottom: bottomSafe, top: top, child: widget.child),
          ),
        );
      }
      return ToastOffset(
        offset: _barH > 0 ? _barH - inset + 10 : (bar ? 75 : 20),
        child: Scaffold(
          backgroundColor: AppColors.panel,
          // The trainer dashboard has a blue hero that runs under the status bar, so it keeps the top inset itself.
          body: SafeArea(bottom: !bar, top: top, child: widget.child),
          bottomNavigationBar: _Measure(
            onHeight: (h) => h != _barH ? setState(() => _barH = h) : null,
            child: bar ? _BottomBar(items: bottomFor(me.role), location: widget.location) : const SizedBox.shrink(),
          ),
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
              child: _Sidebar(items: sidebarFor(me.role, automations: me.can('automations.manage')), location: widget.location, mini: mini, me: me),
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
                child: isClient
                    ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(child: widget.child),
                        WorkoutMiniBar(location: widget.location, safeBottom: false),
                      ])
                    : widget.child,
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
                  TwvLogo(size: mini ? 32 : 36),
                  if (!mini)
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                        CutText('Train With Vimal', style: AppText.s(15, W.w8, ls: -0.15), overflow: TextOverflow.ellipsis),
                        CutText(roleLine, style: AppText.s(12, W.w5, color: AppColors.muted), overflow: TextOverflow.ellipsis),
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
              Expanded(child: CutText(item.label, style: AppText.s(13.5, W.w6, color: on || h ? AppColors.text : AppColors.text2), overflow: TextOverflow.ellipsis)),
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
                    // Pages opened from More (Habits, Check-ins…) keep More lit, like the boards.
                    final on = _active(location, it.path) || (it.path == '/more' && !items.any((x) => _active(location, x.path)));
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

/// Reports its child's height after each layout.
class _Measure extends StatelessWidget {
  const _Measure({required this.onHeight, required this.child});
  final void Function(double) onHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = context.size?.height;
      if (h != null && context.mounted) onHeight(h);
    });
    return child;
  }
}

/// The running workout, collapsed (Strong-style mini bar, tracker F33): on every client page except the logger.
/// Shows the workout's name with its clock, or the rest left; a tap (or a swipe up) opens the logger again.
class WorkoutMiniBar extends StatelessWidget {
  const WorkoutMiniBar({super.key, required this.location, required this.safeBottom});
  final String location;
  final bool safeBottom;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<WorkoutController?>(
        valueListenable: WorkoutController.live,
        builder: (context, c, _) {
          if (c == null || location.startsWith('/train/workout')) return const SizedBox.shrink();
          return ListenableBuilder(
            listenable: c,
            builder: (context, _) {
              if (!c.ready || c.finished) return const SizedBox.shrink();
              final resting = c.rest > 0;
              final p = c.restMax == 0 ? 0.0 : (c.rest / c.restMax).clamp(0.0, 1.0);
              final phone = context.isPhone;
              // push, so minimising pops and slides the logger down over this page
              void open() => openWorkout(context);
              return Semantics(
                button: true,
                label: 'Open the workout ${c.name}',
                child: GestureDetector(
                  onVerticalDragEnd: (d) {
                    if ((d.primaryVelocity ?? 0) < -250) open();
                  },
                  child: Hover(
                    onTap: open,
                    builder: (_, h, _) => Container(
                      padding: EdgeInsets.fromLTRB(16, 6, 16, 10 + (safeBottom ? MediaQuery.paddingOf(context).bottom : 0)),
                      decoration: BoxDecoration(
                        color: h ? AppColors.hover : AppColors.card,
                        borderRadius: phone ? const BorderRadius.vertical(top: Radius.circular(16)) : null,
                        border: const Border(top: BorderSide(color: AppColors.line)),
                        boxShadow: phone ? AppShadows.barUp : null,
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                        Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.line2, borderRadius: BorderRadius.circular(4))),
                        Row(spacing: 10, children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                              Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(14.5, W.w8)),
                              Text(
                                [clockText(c.elapsed), if (c.paused) 'paused', c.setsDone == c.setsAll ? 'all sets done' : c.e.name].join(' · '),
                                style: AppText.s(12.5, W.w5, color: c.paused ? AppColors.amberText : AppColors.muted, tabular: true),
                              ),
                            ]),
                          ),
                          if (resting)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                height: 34,
                                width: 84,
                                color: AppColors.accentSoft,
                                child: Stack(children: [
                                  Positioned.fill(child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: p, child: Container(color: AppColors.accent))),
                                  Center(child: Text('Rest ${clockText(c.rest)}', style: AppText.s(12.5, W.w8, color: AppColors.white, tabular: true))),
                                ]),
                              ),
                            )
                          else
                            const AppIcon(AppIcons.chevronUp, size: 20, color: AppColors.text2),
                        ]),
                      ]),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
}


/// Phone, client: the page, the workout panel and the tab bar in one stack (Strong, Probid 17 Nov).
/// Down: only the panel's top bar shows, right on the tab bar (name, clock, rest). The finger drags it up to full
/// screen (the tab bar slides away under it) and back down (the logger goes behind the tab bar, its top bar turns
/// back into the small bar). The logger stays built the whole time, so nothing is lost going up and down.
class _WorkoutPanelHost extends StatefulWidget {
  const _WorkoutPanelHost({required this.bar, required this.tab, required this.nav, required this.page});
  final bool bar;

  /// A main page (a bottom tab): only these show the small workout bar; an inner page shows the panel only while it
  /// is up (Probid 18 Nov).
  final bool tab;
  final Widget nav;
  final Widget Function(bool bottomSafe) page;

  @override
  State<_WorkoutPanelHost> createState() => _WorkoutPanelHostState();
}

class _WorkoutPanelHostState extends State<_WorkoutPanelHost> with SingleTickerProviderStateMixin {
  static const _head = 62.0; // the panel's top bar when it is down
  late final _t = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  String? _req; // what opened it (Start / Continue / ⋯ Finish …), null = only the running workout
  double _navH = 0, _travel = 1;

  bool get _live {
    final c = WorkoutController.live.value;
    return c != null && c.ready && !c.finished;
  }

  /// Only a running workout (or one just opened) keeps the panel. A finished one waiting for its rating does not
  /// keep a bar any more: the "Rate it" button on Train opens the rating (Probid 18 Nov, was 17 Nov's bar).
  bool get _shown => (_req != null || _live) && (widget.tab || _up);

  /// The panel is up or on its way up / down (opened from anywhere); false once it is fully down.
  bool _up = false;

  @override
  void initState() {
    super.initState();
    WorkoutPanel.show = _show;
    WorkoutPanel.collapse = _down;
    WorkoutPanel.close = _close;
    WorkoutPanel.dragBy = _dragBy;
    WorkoutPanel.dragEnd = _dragEnd;
    WorkoutPanel.isOpen = () => _t.value > .5;
    WorkoutController.live.addListener(_changed);
    final p = WorkoutPanel.pending;
    if (p != null) {
      WorkoutPanel.pending = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _show(p));
    }
  }

  @override
  void dispose() {
    if (WorkoutPanel.show == _show) {
      WorkoutPanel.show = WorkoutPanel.collapse = WorkoutPanel.close = null;
      WorkoutPanel.dragBy = WorkoutPanel.dragEnd = null;
      WorkoutPanel.isOpen = null;
    }
    WorkoutController.live.removeListener(_changed);
    _t.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    // a workout that ended elsewhere (Train ⋯ Discard): nothing left to show
    if (!_shown) _t.value = 0;
  }

  void _show(String q) {
    if (!mounted) return;
    setState(() {
      if (q.isNotEmpty || _req == null) _req = q;
      _up = true;
    });
    _t.animateTo(1, curve: Curves.easeOutCubic);
  }

  void _down() => _t.animateTo(0, curve: Curves.easeOutCubic).then((_) {
        if (!mounted || _t.value != 0) return;
        setState(() {
          _up = false;
          if (!_live) _req = null;
        });
      });

  void _close() {
    _t.value = 0;
    if (mounted) {
      setState(() {
        _req = null;
        _up = false;
      });
    }
  }

  void _dragBy(double dy) {
    if (!_up) setState(() => _up = true);
    _t.value = (_t.value - dy / _travel).clamp(0.0, 1.0);
  }

  void _dragEnd(double v) {
    if (v < -400 || (v.abs() <= 400 && _t.value > .5)) {
      _t.animateTo(1, curve: Curves.easeOutCubic);
    } else {
      _down();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final inset = mq.padding.bottom;
    // the phone's status bar height, read from the window too (a parent may have taken it off the padding)
    final statusH = math.max(mq.padding.top, MediaQueryData.fromView(View.of(context)).padding.top);
    final shown = _shown;
    final c = WorkoutController.live.value;
    final head = _head + (widget.bar ? 0 : inset);
    final navH = widget.bar ? _navH : 0.0;
    final q = Uri.parse('x${_req ?? ''}').queryParameters;
    final double below = (widget.bar && _navH > 0 ? _navH - inset : 0.0) + (shown ? head : 0) + 10;
    return AnimatedBuilder(
      animation: Listenable.merge([_t, WorkoutPanel.lift]),
      // panel up: toasts sit where the logger asks (above Cancel workout / the keypad), not above the hidden tabs
      builder: (_, child) => ToastOffset(offset: shown && _t.value > .5 ? (WorkoutPanel.lift.value ?? 10) : below, child: child!),
      child: LayoutBuilder(builder: (context, box) {
        final h = box.maxHeight;
        _travel = math.max(1, h - navH - head);
        return Stack(children: [
          Positioned(left: 0, right: 0, top: 0, bottom: navH + (shown ? head : 0), child: widget.page(!widget.bar && !shown)),
          if (shown)
            AnimatedBuilder(
              animation: _t,
              builder: (context, child) {
                final t = _t.value;
                return Positioned(
                  left: 0,
                  right: 0,
                  top: (h - navH - head) * (1 - t),
                  height: h,
                  // dark status bar icons over the white logger (the page under it may be Home's blue hero, whose
                  // light icons made the time / network invisible, Probid 17 Nov)
                  child: AnnotatedRegion<SystemUiOverlayStyle>(
                    value: _AppShellState._statusDark,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    // the status bar stays clear: the logger starts under it (it went into it before)
                    Container(height: statusH * t, color: AppColors.white),
                    Expanded(
                      child: Stack(children: [
                        // opaque: the page under it never shows through (the finish page had no background)
                        Positioned.fill(child: ColoredBox(color: AppColors.white, child: child!)),
                        // the small bar stays in the tree the whole way: removing it mid-drag lost the drag and the
                        // panel stuck half way with the tab bar half gone (Probid 17 Nov)
                        if (c != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            child: IgnorePointer(
                              ignoring: t > .3,
                              child: Opacity(opacity: (1 - t / .3).clamp(0.0, 1.0), child: _PanelHead(c: c, height: head, onOpen: () => _show(''), onDrag: _dragBy, onEnd: _dragEnd)),
                            ),
                          ),
                      ]),
                    ),
                  ]),
                  ),
                );
              },
              child: TickerMode(
                enabled: true,
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: WorkoutScreen(
                    key: ValueKey(_req ?? ''),
                    start: int.tryParse(q['start'] ?? ''),
                    reopen: q['reopen'],
                    review: q['review'],
                    then: q['then'],
                  ),
                ),
              ),
            ),
          if (widget.bar)
            AnimatedBuilder(
              animation: _t,
              builder: (_, child) => Positioned(left: 0, right: 0, bottom: shown ? -_navH * _t.value : 0, child: child!),
              child: _Measure(onHeight: (v) => v != _navH ? setState(() => _navH = v) : null, child: widget.nav),
            ),
        ]);
      }),
    );
  }
}

/// The panel's top bar when it is down: workout name, clock and exercise, rest left; tap or drag up opens it.
class _PanelHead extends StatelessWidget {
  const _PanelHead({required this.c, required this.height, required this.onOpen, required this.onDrag, required this.onEnd});
  final WorkoutController c;
  final double height;
  final VoidCallback onOpen;
  final void Function(double) onDrag;
  final void Function(double) onEnd;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final resting = c.rest > 0;
          final p = c.restMax == 0 ? 0.0 : (c.rest / c.restMax).clamp(0.0, 1.0);
          return Semantics(
            button: true,
            label: 'Open the workout ${c.name}',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
              onVerticalDragEnd: (d) => onEnd(d.primaryVelocity ?? 0),
              onVerticalDragCancel: () => onEnd(0),
              child: Container(
                height: height,
                alignment: Alignment.topCenter,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                decoration: const BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                  border: Border(top: BorderSide(color: AppColors.line)),
                  boxShadow: AppShadows.barUp,
                ),
                child: Column(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
                  Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.line2, borderRadius: BorderRadius.circular(4))),
                  // Strong: the day name and the workout time in the middle; while resting the rest time sits next
                  // to the workout time with a thin progress line under it (Probid 17 Nov).
                  Text(c.ready ? c.name : 'Workout', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: AppText.s(14.5, W.w7)),
                  if (c.ready)
                    Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
                      Flexible(
                        child: Text(
                          // finished: the clock stops at the saved time; it says what is left to do
                          c.finished
                              ? 'Finished · ${clockText(c.finalSeconds)} · ${c.sent ? 'sent to ${c.plan.coachFirst}' : 'rate it for ${c.plan.coachFirst}'}'
                              : [clockText(c.elapsed), if (c.paused) 'paused'].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.s(12.5, W.w5, color: c.paused ? AppColors.amberText : AppColors.muted, tabular: true, h: 1.2),
                        ),
                      ),
                      if (resting)
                        Column(mainAxisSize: MainAxisSize.min, spacing: 3, children: [
                          Text(clockText(c.rest), style: AppText.s(12.5, W.w7, color: AppColors.accentText, tabular: true, h: 1.2)),
                          SizedBox(
                            width: 36,
                            height: 3,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: Stack(children: [
                                Container(color: AppColors.accentSoft),
                                FractionallySizedBox(widthFactor: p, child: Container(color: AppColors.accent)),
                              ]),
                            ),
                          ),
                        ]),
                    ]),
                ]),
              ),
            ),
          );
        },
      );
}
