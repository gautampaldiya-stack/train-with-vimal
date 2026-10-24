import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart' show confirmLogOut;
import '../../../app/services.dart';
import '../../../app/unread.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../home/home_model.dart' show clock, dayShort, inNum, since;
import '../home/home_parts.dart';
import '../progress/progress_screen.dart' show pxLoading;
import 'more_model.dart';
import 'more_parts.dart';
import 'more_sheets.dart';
import '../../../core/widgets/tooltip.dart';

/// More tab (boards `ClientMore` phone and `ClientMoreWeb`). Phone: `/more` is the menu, `/more/profile`,
/// `/more/notifications` and `/more/activity` are pages. Web ("My account"): Overview · Notifications ·
/// My activity tabs on the same three paths; `/more/profile` shows the Overview.
class ClientMoreScreen extends StatefulWidget {
  const ClientMoreScreen({super.key, this.view = ''});
  final String view; // '' | profile | notifications | activity
  @override
  State<ClientMoreScreen> createState() => _ClientMoreScreenState();
}

class _ClientMoreScreenState extends State<ClientMoreScreen> {
  final c = MoreController();
  final _shot = GlobalKey(); // "Attach a screenshot of this screen" in Report a problem
  final _scroll = ScrollController();

  String get _view => widget.view;

  @override
  void initState() {
    super.initState();
    c.start();
    _scroll.addListener(() {
      if (_view == 'notifications' && _scroll.position.extentAfter < 300) c.loadNotices(more: true);
    });
    _enter();
  }

  @override
  void didUpdateWidget(ClientMoreScreen old) {
    super.didUpdateWidget(old);
    if (old.view != widget.view) _enter();
  }

  void _enter() {
    if (_view == 'notifications' && c.notices == null) c.loadNotices();
    if (_view == 'activity') c.loadActivity(c.actKind);
  }

  @override
  void dispose() {
    c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([c, Services.session]),
        builder: (context, _) {
          final d = c.data;
          if (d == null) return pxLoading(c.error, c.load, 'your account');
          return RepaintBoundary(key: _shot, child: context.isPhone ? _phone(d) : _web(d));
        },
      );

  Me get _me => Services.session.me!;

  // ─────────────────────────────── Layouts

  Widget _phone(MoData d) {
    final children = switch (_view) {
      'profile' => [_pageHead('Profile', 'What ${d.coachFirst} sees about you'), _details(d), if (d.goal != null) _goalCard(d), _activityRowCard()],
      'notifications' => _noticesPage(d, web: false),
      'activity' => _activityPage(web: false),
      _ => _mainPhone(d),
    };
    // Notifications and My activity: the header with its tabs / filters stays put, only the list scrolls (Gautam).
    final fixed = _view == 'notifications' || _view == 'activity' ? 2 : 0;
    final list = RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.accent,
      child: SingleChildScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, fixed > 0 ? 2 : 8, 16, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: children.sublist(fixed)),
      ),
    );
    if (fixed == 0) return list;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: children.sublist(0, fixed)),
      ),
      Expanded(child: list),
    ]);
  }

  Future<void> _refresh() async {
    await c.load();
    if (_view == 'notifications') await c.loadNotices();
    if (_view == 'activity') await c.loadActivity(c.actKind);
  }

  Widget _webTitle(MoData d, int tab) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('My account', style: AppText.s(26, W.w8, ls: -0.26, h: 1.2)),
              Text('${d.name} · client of ${d.coachName}', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
            ]),
          ),
        ]),
        Align(
          alignment: Alignment.centerLeft,
          child: MoTabs(
            labels: ['Overview', d.unread > 0 ? 'Notifications · ${d.unread}' : 'Notifications', 'My activity'],
            index: tab,
            onPick: (i) => context.go(const ['/more', '/more/notifications', '/more/activity'][i]),
          ),
        ),
      ]);

  /// Web Notifications / My activity: title, tabs and the list's own bar stay put; only the list scrolls.
  Widget _webList(MoData d, int tab) {
    final all = tab == 1 ? _noticesPage(d, web: true) : _activityPage(web: true);
    final fixed = tab == 1 ? 1 : 2;
    Widget col(List<Widget> w, double gap) => Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: gap, children: w),
          ),
        );
    Widget wide(Widget w) => Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1080), child: w));
    return CaWeb(
      web: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 14),
          child: wide(Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [_webTitle(d, tab), col(all.sublist(0, fixed), 12)])),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.accent,
            child: SingleChildScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(32, 2, 32, 72),
              child: wide(col(all.sublist(fixed), tab == 1 ? 14 : 12)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _web(MoData d) {
    final tab = switch (_view) { 'notifications' => 1, 'activity' => 2, _ => 0 };
    if (tab != 0) return _webList(d, tab);
    return CaWeb(
      web: true,
      child: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.accent,
        child: SingleChildScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 72),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: LayoutBuilder(builder: (context, box) {
                final two = box.maxWidth >= 680;
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('My account', style: AppText.s(26, W.w8, ls: -0.26, h: 1.2)),
                        Text('${d.name} · client of ${d.coachName}', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
                      ]),
                    ),
                  ]),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: MoTabs(
                      labels: ['Overview', d.unread > 0 ? 'Notifications · ${d.unread}' : 'Notifications', 'My activity'],
                      index: tab,
                      onPick: (i) => context.go(const ['/more', '/more/notifications', '/more/activity'][i]),
                    ),
                  ),
                  ...[
                    if (d.deletionOn != null) _deletionBanner(d),
                    if (two)
                      Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: _overviewLeft(d))),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: _overviewRight(d))),
                      ])
                    else ...[
                      ..._overviewLeft(d),
                      ..._overviewRight(d),
                    ],
                  ],
                ]);
              }),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _overviewLeft(MoData d) => [
        _details(d),
        if (d.goal != null) _goalCard(d),
        Row(spacing: 12, children: [
          _logOutButton(wide: false),
          Text('Train With Vimal · Version ${d.version}', style: AppText.s(11.5, W.w6, color: AppColors.muted)),
        ]),
      ];

  List<Widget> _overviewRight(MoData d) => [
        _coachCard(d),
        ChCard(padding: const EdgeInsets.fromLTRB(14, 2, 14, 2), gap: 0, children: [moMh('Settings'), ..._settingsRows(d, web: true)]),
      ];

  // ─────────────────────────────── Phone menu

  List<Widget> _mainPhone(MoData d) => [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('More', style: AppText.s(26, W.w8, ls: -0.26, h: 1.2)),
              Text('Your account, coach and settings', style: AppText.s(13, W.w5, color: AppColors.muted)),
            ]),
          ),
          UnreadCount(fallback: d.unread, builder: (_, n) => ChBell(count: n, onTap: () => context.go('/more/notifications'))),
        ]),
        if (d.deletionOn != null) _deletionBanner(d),
        _profileCard(d),
        _coachCard(d),
        moSec('Your plan'),
        ChCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2), gap: 0, children: _planRows(d, firstLine: true)),
        moSec('Account'),
        ChCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2), gap: 0, children: [
          MoMenuRow(
            first: true,
            icon: AppIcons.bell,
            title: 'Notifications',
            sub: d.unread > 0 ? '${d.unread} unread' : 'All caught up',
            pill: d.unread > 0 ? '${d.unread} new' : null,
            onTap: () => context.go('/more/notifications'),
          ),
          ..._settingsRows(d, web: false),
        ]),
        _logOutButton(wide: true),
        Text('Train With Vimal · Version ${d.version}', textAlign: TextAlign.center, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
      ];

  Widget _profileCard(MoData d) => Semantics(
        button: true,
        label: 'Profile',
        child: Hover(
          onTap: () => context.go('/more/profile'),
          builder: (_, h, _) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
            child: Row(spacing: 12, children: [
              MoAvatar(d.initials),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                  Text(d.name, style: AppText.s(16, W.w8, color: h ? AppColors.accentText : AppColors.text)),
                  CutText('Coach ${d.coachFirst} · Profile & activity', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
                ]),
              ),
              const AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.muted),
            ]),
          ),
        ),
      );

  Widget _deletionBanner(MoData d) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.moBan, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.amberLine)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
          Row(spacing: 10, children: [
            const AppIcon(AppIcons.alert, size: 18, color: AppColors.amberDeep),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text('Account deletion on ${dayShort(d.deletionOn!)}', style: AppText.s(13.5, W.w7)),
                Text('Everything is erased on that day. You can still cancel.', style: AppText.s(12, W.w4, color: AppColors.amberDeep)),
              ]),
            ),
          ]),
          CaButton('Cancel deletion', kind: CaBtnKind.out, small: true, onPressed: () async {
            try {
              await c.cancelDelete();
              if (mounted) showToast(context, 'Deletion cancelled', sub: 'Your account stays as it is', kind: ToastKind.ok);
            } catch (_) {
              if (mounted) moFailed(context);
            }
          }),
        ]),
      );

  Widget _coachCard(MoData d) {
    final s = d.session;
    String sessionLine() {
      if (s == null) return 'No session booked';
      final start = DateTime.parse('${s['start']}').toLocal();
      final today = DateUtils.dateOnly(DateTime.now());
      final day = DateUtils.isSameDay(start, today)
          ? 'Today'
          : DateUtils.isSameDay(start, today.add(const Duration(days: 1)))
              ? 'Tomorrow'
              : dayShort(start);
      final where = s['is_call'] == true ? 'Call' : '${s['place']}'.isEmpty ? 'At the gym' : '${s['place']}';
      return '$day, ${clock(start)} · $where';
    }

    Widget row(AppIconData icon, ChTone tone, String label, String value) => Container(
          padding: const EdgeInsets.only(top: 10),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
          child: Row(spacing: 10, children: [
            MoIc(icon, tone: tone, size: 30, radius: 9),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text(label, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
                Text(value, style: AppText.s(13.5, W.w7)),
              ]),
            ),
          ]),
        );
    if (d.coach == null) {
      return ChCard(children: [
        Text('No coach yet', style: AppText.s(15, W.w8)),
        Text('Vimal assigns your coach soon. Your plan shows up here then.', style: AppText.s(12.5, W.w4, color: AppColors.muted)),
      ]);
    }
    return ChCard(gap: 10, children: [
      Row(spacing: 10, children: [
        ChAvatar('${d.coach!['initials']}', green: true),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
            Text(d.coachName, style: AppText.s(15, W.w8)),
            Text('Your trainer since ${moDate(DateTime.parse('${d.coach!['since']}'))}', style: AppText.s(12, W.w4, color: AppColors.muted)),
          ]),
        ),
        chSm('Details', () => showCoachSheet(context, c)),
      ]),
      row(AppIcons.calendarAlt, ChTone.blue, 'Next session', sessionLine()),
      row(AppIcons.clipboard, ChTone.purple, 'Daily check-in', moDailyLine(d)),
      row(AppIcons.clipboard, ChTone.amber, 'Weekly check-in', '${moCheckinWhen(d)} · next ${dayShort(d.nextCheckin)}'),
    ]);
  }

  List<Widget> _planRows(MoData d, {required bool firstLine}) {
    var hs = d.habits.take(3).join(', ');
    if (hs.isNotEmpty) hs = hs[0].toUpperCase() + hs.substring(1);
    final ss = d.supps.take(3).join(', ');
    return [
      MoMenuRow(
        first: firstLine,
        icon: AppIcons.target,
        title: 'Habits & supplements',
        sub: [if (hs.isNotEmpty) hs, if (ss.isNotEmpty) ss].join(' · ').ifEmpty('Nothing set yet'),
        onTap: () => context.go('/habits'),
      ),
      MoMenuRow(
        icon: AppIcons.clipboard,
        title: 'Check-ins',
        sub: d.checkinDue ? 'Week ${d.checkinWeek} due ${dayShort(d.nextCheckin)}' : 'This week sent · next ${dayShort(d.nextCheckin)}',
        pill: d.checkinDue ? 'Due ${DateFormat('EEE').format(d.nextCheckin)}' : null,
        pillTone: ChTone.amber,
        onTap: () => context.go('/checkins'),
      ),
      MoMenuRow(
        icon: AppIcons.food,
        title: 'Nutrition overview',
        sub: d.meal == null ? 'No meal plan yet' : '${inNum(d.meal!['kcal'] as num)} kcal · ${d.meal!['diet']} · weekly averages',
        onTap: () => context.go('/food'),
      ),
      MoMenuRow(
        icon: AppIcons.library,
        title: 'Library',
        sub: 'Guides and videos from ${d.coachFirst}',
        onTap: () => context.go('/library'),
      ),
    ];
  }

  List<Widget> _settingsRows(MoData d, {required bool web}) {
    final r = d.reminders;
    final on = moReminderKeys.where((k) => r[k.$1] == true).length;
    final quiet = r['quiet_on'] == true ? ' · quiet ${minClock(hmsToMin('${r['quiet_from']}'))} – ${minClock(hmsToMin('${r['quiet_to']}'))}' : '';
    final m = _me;
    final units = '${m.unitWeight}, ${m.unitLength}, ${m.unitWater == 'oz' ? 'fl oz' : 'litres'} · week starts ${m.weekStart == 'sun' ? 'Sun' : 'Mon'}';
    return [
      MoMenuRow(first: web, icon: AppIcons.gear, title: 'Notification settings', sub: '$on of ${moReminderKeys.length} on$quiet', onTap: () => showReminderSheet(context, c)),
      MoMenuRow(icon: AppIcons.ruler, title: 'Units & preferences', sub: units, onTap: () => showUnitsSheet(context, c)),
      MoMenuRow(icon: AppIcons.shield, title: 'Privacy & data', sub: 'Who sees your data · download · delete', onTap: () => showPrivacySheet(context, c)),
      if (!web) MoMenuRow(icon: AppIcons.pulse, title: 'My activity', sub: 'Everything you logged, newest first', onTap: () => context.go('/more/activity')),
      MoMenuRow(icon: AppIcons.help, title: 'Help & about', sub: 'Questions, report a problem, version', onTap: () => _help()),
    ];
  }

  Future<void> _help() async {
    final shot = await moCapture(_shot);
    if (mounted) await showHelpAboutSheet(context, c, screenshot: shot, page: GoRouterState.of(context).uri.path);
  }

  Widget _logOutButton({required bool wide}) => Semantics(
        button: true,
        label: 'Log out',
        child: Hover(
          onTap: () => confirmLogOut(context),
          builder: (_, h, _) => Container(
            height: wide ? 44 : 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: h ? AppColors.badBg : AppColors.white, borderRadius: BorderRadius.circular(wide ? 12 : 10), border: Border.all(color: AppColors.line)),
            child: Row(mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, spacing: 8, children: [
              const AppIcon(AppIcons.logout, size: 16, color: AppColors.badText),
              Text('Log out', style: AppText.s(wide ? 14.5 : 14, W.w7, color: AppColors.badText)),
            ]),
          ),
        ),
      );

  // ─────────────────────────────── Profile (phone page, web Overview left)

  Widget _pageHead(String title, String sub, {List<Widget> actions = const []}) => Row(spacing: 10, children: [
        CaIconBtn(AppIcons.chevronLeft, tooltip: 'Back to More', onTap: () => context.go('/more')),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(title, maxLines: 1, style: AppText.s(21, W.w8, h: 1.2))),
            CutText(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.muted)),
          ]),
        ),
        ...actions,
      ]);

  Widget _details(MoData d) {
    final m = _me;
    final p = d.program;
    final rows = [
      ('Email', d.email.ifEmpty('—')),
      ('Mobile', moPhone(d.phone)),
      ('City', d.city.ifEmpty('—')),
      ('Date of birth', d.dob == null ? 'Not added' : '${moDate(d.dob!)}${d.age == null ? '' : ' · ${d.age} years'}'),
      ('Height', moHeight(d.heightCm, m.unitLength)),
      ('Coach', d.coachName),
      if (p != null) ('Program', '${p['name']} · week ${p['week']} of ${p['weeks']}'),
      if (p != null) ('Plan dates', moRange(DateTime.parse('${p['start']}'), DateTime.parse('${p['end']}'))),
    ];
    return ChCard(gap: 8, children: [
      Row(spacing: 12, children: [
        MoAvatar(d.initials, size: 54),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(d.name, style: AppText.s(17, W.w8)),
            Text('Client since ${moDate(d.since)}', style: AppText.s(12, W.w4, color: AppColors.muted)),
          ]),
        ),
        chSm('Edit', () => showEditProfileSheet(context, c), icon: AppIcons.edit),
      ]),
      if (d.pendingEmail.isNotEmpty) _pending(d),
      moKvs(rows),
    ]);
  }

  Widget _pending(MoData d) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text('Verify your new email', style: AppText.s(13.5, W.w7, color: AppColors.infoText)),
            Text('We sent a link to ${d.pendingEmail}. Until then we use ${d.email}.', style: AppText.s(12, W.w4, color: AppColors.text2)),
          ]),
          Wrap(spacing: 6, runSpacing: 6, children: [
            chSm('Resend link', () async {
              try {
                await c.resendEmail();
                if (mounted) showToast(context, 'Verification link sent again', sub: 'To ${d.pendingEmail}', kind: ToastKind.info);
              } catch (_) {
                if (mounted) moFailed(context);
              }
            }),
            chSm('Cancel change', () async {
              final was = d.pendingEmail;
              try {
                await c.cancelEmail();
                if (!mounted) return;
                showToast(context, 'Email change cancelled', sub: 'We keep using ${d.email}', kind: ToastKind.info, action: 'Undo', onAction: () async {
                  await c.saveProfile({'email': was}).catchError((_) {});
                });
              } catch (_) {
                if (mounted) moFailed(context);
              }
            }),
          ]),
        ]),
      );

  Widget _goalCard(MoData d) {
    final g = d.goal!;
    final u = _me.unitWeight;
    final start = (g['start_kg'] as num?)?.toDouble(), now = (g['now_kg'] as num?)?.toDouble(), goal = (g['goal_kg'] as num?)?.toDouble();
    final pct = (g['pct'] as num?)?.toInt();
    final left = now != null && goal != null ? (now - goal).abs() : null;
    final eta = g['eta'] == null ? null : DateTime.parse('${g['eta']}');
    final sub = [if (eta != null) 'By ${DateFormat('MMM y').format(eta)}', if (left != null) '${moKg(left, u)} to go'].join(' · ');
    final lost = (d.stats['lost_kg'] as num?)?.toDouble();
    final p = d.program;
    final startMonth = DateFormat('MMM').format(DateTime.parse('${g['start_date']}'));
    final stats = [
      if (lost != null) (moKg(lost, u, sign: true), 'since $startMonth'),
      if (p != null) ('${p['week']} of ${p['weeks']}', 'weeks done'),
      ('${d.stats['checkins_sent'] ?? 0}', 'check-ins sent'),
    ];
    return ChCard(gap: 10, children: [
      Row(spacing: 10, children: [
        const MoIc(AppIcons.target, tone: ChTone.green),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
            Text('Goal: ${g['title']}', style: AppText.s(15, W.w8)),
            if (sub.isNotEmpty) Text(sub, style: AppText.s(12, W.w4, color: AppColors.muted)),
          ]),
        ),
        if (pct != null) MoPill('$pct% there', tone: ChTone.green),
      ]),
      if (pct != null) ChBar(pct / 100, color: AppColors.okSolid, height: 8),
      if (start != null && now != null && goal != null)
        Pull(
          top: 4,
          child: Row(children: [
            Expanded(child: Text('Start ${moKg(start, u)}', style: AppText.s(12, W.w6, color: AppColors.muted))),
            Text('Now ${moKg(now, u)}', style: AppText.s(12, W.w7)),
            Expanded(child: Text('Goal ${moKg(goal, u)}', textAlign: TextAlign.right, style: AppText.s(12, W.w6, color: AppColors.muted))),
          ]),
        ),
      Row(spacing: 6, children: [
        for (final (v, l) in stats)
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(color: AppColors.caWebBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
              child: Column(children: [
                Text(v, maxLines: 1, style: AppText.s(15, W.w8)),
                CutText(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11, W.w6, color: AppColors.muted)),
              ]),
            ),
          ),
      ]),
    ]);
  }

  Widget _activityRowCard() => ChCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2), gap: 0, children: [
        MoMenuRow(first: true, icon: AppIcons.pulse, title: 'My activity', sub: 'Everything you logged, newest first', onTap: () => context.go('/more/activity')),
      ]);

  // ─────────────────────────────── Notifications

  List<Widget> _noticesPage(MoData d, {required bool web}) {
    final list = c.notices;
    final total = list?.length ?? 0;
    final sub = d.unread > 0 ? '${d.unread} unread${c.unreadTab ? '' : ' · $total${c.hasMoreNotices ? '+' : ''} in all'}' : total > 0 && !c.unreadTab ? 'All caught up · $total${c.hasMoreNotices ? '+' : ''} in all' : 'All caught up';
    final actions = [
      Opacity(
        opacity: d.unread > 0 ? 1 : 0.45,
        child: chSm('Mark all read', () async {
          if (d.unread == 0) return;
          final n = d.unread;
          final was = await c.readAll();
          if (!mounted) return;
          showToast(context, 'All marked as read', sub: '$n notification${n == 1 ? '' : 's'}', kind: ToastKind.ok, action: 'Undo', onAction: () => c.undoReadAll(was));
        }, icon: AppIcons.check),
      ),
      SizedBox(width: 34, height: 34, child: CaIconBtn(AppIcons.gear, tooltip: 'Notification settings', onTap: () => showReminderSheet(context, c))),
    ];
    final tabs = MoTabs(
      labels: ['All', d.unread > 0 ? 'Unread · ${d.unread}' : 'Unread'],
      index: c.unreadTab ? 1 : 0,
      onPick: (i) => c.pickNoticeTab(i == 1),
    );
    final body = list == null
        ? const Padding(padding: EdgeInsets.all(30), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))))
        : list.isEmpty
            ? ChCard(children: [
                c.unreadTab
                    ? moEmpty('All caught up', 'You have read everything. New notifications show up here.', icon: AppIcons.check)
                    : moEmpty('No notifications', 'Reminders and updates from ${d.coachFirst} show up here.'),
              ])
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final (i, n) in list.indexed) _noticeRow(n, first: i == 0, last: i == list.length - 1),
                  if (c.loadingMore) const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)))),
                ]),
              );
    if (web) {
      return [
        Row(spacing: 12, children: [SizedBox(width: 280, child: tabs), const Spacer(), ...actions.expand((a) => [a, const SizedBox(width: 6)]).take(3)]),
        body,
      ];
    }
    return [_pageHead('Notifications', sub, actions: [actions[0], actions[1]]), tabs, body];
  }

  Widget _noticeRow(MoNotice n, {required bool first, required bool last}) {
    final (ic, tone) = noticeLook(n.event);
    final when = _noticeWhen(n.at);
    return Semantics(
      button: true,
      label: n.title,
      child: Hover(
        onTap: () {
          c.markRead(n);
          showNoticeSheet(context, c, n, when);
        },
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          decoration: BoxDecoration(
            color: n.read ? null : AppColors.pickBg,
            border: first ? null : const Border(top: BorderSide(color: AppColors.line)),
            borderRadius: BorderRadius.vertical(top: Radius.circular(first ? 10 : 0), bottom: Radius.circular(last ? 10 : 0)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 11, children: [
            MoIc(moIcon(ic), tone: moTone(tone), size: 32),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text(n.title, style: AppText.s(13.5, n.read ? W.w6 : W.w8, color: h ? AppColors.accentText : AppColors.text)),
                if (n.body.isNotEmpty) Text(n.body, style: AppText.s(12.5, W.w4, color: AppColors.text2, h: 1.4)),
                Text(when, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
              ]),
            ),
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(color: n.read ? Colors.transparent : AppColors.accent, shape: BoxShape.circle),
            ),
          ]),
        ),
      ),
    );
  }

  /// "2 h ago", "Today, 8:00 am", "Mon, 5 Oct".
  String _noticeWhen(DateTime t) {
    final age = DateTime.now().difference(t);
    if (age.inHours < 6) return since(t, ago: true);
    if (DateUtils.isSameDay(t, DateTime.now())) return 'Today, ${clock(t)}';
    if (DateUtils.isSameDay(t, DateTime.now().subtract(const Duration(days: 1)))) return 'Yesterday, ${clock(t)}';
    return dayShort(t);
  }

  // ─────────────────────────────── My activity

  static const _kinds = ['All', 'Training', 'Food', 'Check-ins', 'Habits', 'Account'];

  List<Widget> _activityPage({required bool web}) {
    final list = c.activity;
    final chips = MoChips(items: _kinds, on: c.actKind, onPick: (k) => c.loadActivity(k), scroll: context.isPhone);
    final out = <Widget>[
      if (web) Text('Only you can see this · last 7 days', style: AppText.s(12.5, W.w6, color: AppColors.muted)) else _pageHead('My activity', 'Only you can see this · last 7 days'),
      chips,
    ];
    if (list == null) {
      out.add(c.actError != null
          ? pxLoading(c.actError, () => c.loadActivity(c.actKind), 'your activity')
          : const Padding(padding: EdgeInsets.all(30), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent)))));
      return out;
    }
    if (list.isEmpty) {
      out.add(ChCard(children: [
        moEmpty('Nothing here yet', c.actKind == 'Account' ? 'Changes to your profile and settings show up here.' : 'Nothing logged in this filter in the last 7 days.', icon: AppIcons.pulse),
      ]));
      return out;
    }
    final days = <DateTime, List<MoAct>>{};
    for (final a in list) {
      days.putIfAbsent(a.date, () => []).add(a);
    }
    final today = DateUtils.dateOnly(DateTime.now());
    for (final MapEntry(key: day, value: items) in days.entries) {
      final label = DateUtils.isSameDay(day, today)
          ? 'Today · ${dayShort(day)}'
          : DateUtils.isSameDay(day, today.subtract(const Duration(days: 1)))
              ? 'Yesterday · ${dayShort(day)}'
              : dayShort(day);
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
        child: Pull(
          bottom: 6,
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Expanded(child: Text(label, style: AppText.s(12, W.w8, color: AppColors.text2))),
            Text('${items.length} item${items.length == 1 ? '' : 's'}', style: AppText.s(11.5, W.w6, color: AppColors.muted)),
          ]),
        ),
      ));
      out.add(ChCard(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2), gap: 0, children: [
        for (final (i, a) in items.indexed) _actRow(a, first: i == 0),
      ]));
    }
    return out;
  }

  Widget _actRow(MoAct a, {required bool first}) => Semantics(
        button: true,
        label: a.title,
        child: Hover(
          onTap: () => showActivitySheet(context, a),
          builder: (_, h, _) => Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: AppColors.line))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
              MoIc(moIcon(a.icon), tone: moTone(a.color), size: 32),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text(a.title, style: AppText.s(13.5, W.w7, color: h ? AppColors.accentText : AppColors.text)),
                  if (a.sub.isNotEmpty) Text(a.sub, style: AppText.s(12, W.w4, color: AppColors.muted)),
                ]),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: Padding(padding: const EdgeInsets.only(top: 2), child: Text(a.time, style: AppText.s(11.5, W.w6, color: AppColors.muted))),
              ),
            ]),
          ),
        ),
      );
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
