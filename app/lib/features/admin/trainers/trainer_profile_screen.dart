import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../app/shell/page.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/stat.dart';
import '../../../core/widgets/tabs.dart';
import '../../../core/widgets/tooltip.dart';
import '../../trainer/me/me_common.dart';
import '../../trainer/me/me_docs.dart';
import '../../trainer/me/me_edit.dart';
import '../../trainer/me/me_model.dart';
import '../../trainer/me/me_overview.dart';
import '../../trainer/me/me_tabs.dart';
import 'trainer_drawers.dart';
import 'trainer_profile_tabs.dart';

/// Admin → Trainer profile (boards `TrainerProfile` / `TrainerProfileMobile`, D-48): "Trainers / Aman Verma",
/// header with Edit details, Assign clients and ⋯ (Access and permissions, Send password reset link, Move all clients
/// to another trainer, Deactivate), the 4 stats and 6 tabs. The page shares the trainer's own My profile code
/// (`MeController(id:)`): Overview, Activity, Documents and What clients see are the same widgets with admin texts;
/// Clients and Access are admin-only. `?tab=` opens a tab, `&assign=1` opens Assign clients.
class TrainerProfileScreen extends StatefulWidget {
  const TrainerProfileScreen({super.key, required this.id, this.tab, this.assign = false});
  final String id;
  final String? tab;
  final bool assign;
  @override
  State<TrainerProfileScreen> createState() => _TrainerProfileScreenState();
}

class _TrainerProfileScreenState extends State<TrainerProfileScreen> {
  late final c = MeController(id: widget.id, tab: widget.tab);

  @override
  void initState() {
    super.initState();
    c.load().then((_) {
      if (widget.assign && mounted && c.me.isNotEmpty) _assign();
    });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  void _tab(String t) {
    c.setTab(t);
    // Keep the address in step so a refresh or a shared link opens the same tab.
    final path = t == 'overview' ? '/trainers/${widget.id}' : '/trainers/${widget.id}?tab=$t';
    if (GoRouterState.of(context).uri.toString() != path) context.go(path);
  }

  bool get _active => '${c.me['status']}' == 'active';
  bool get _owner => c.profile['is_owner'] == true;
  int get _clients => (c.stats['clients'] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          if (c.loading && c.me.isEmpty) return const MeLoading();
          if (c.me.isEmpty) {
            final gone = c.error?.status == 404;
            return StaffPage(children: [
              _crumb(),
              AppCard(
                child: EmptyState(gone ? 'This trainer is not there any more' : 'Could not open this trainer',
                    sub: gone ? null : c.error?.message,
                    action: AppButton(gone ? 'Back to Trainers' : 'Try again', onPressed: gone ? () => context.go('/trainers') : c.load)),
              ),
            ]);
          }
          final phone = context.isPhone;
          return StaffPage(
            onRefresh: c.refresh,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 12 : 14, children: [
                _crumb(),
                if (phone)
                  _headPhone()
                else
                  LayoutBuilder(builder: (context, b) => b.maxWidth >= 900 ? _head() : _headMid()),
                phone ? _statsPhone() : _stats(),
              ]),
              UnderlineTabs<String>(
                items: [
                  for (final (k, l) in MeController.adminTabs)
                    TabItem(k, l, count: k == 'documents' && c.docs.isNotEmpty ? c.docs.length : (k == 'clients' && _clients > 0 ? _clients : null)),
                ],
                value: c.tab,
                onChanged: _tab,
              ),
              KeyedSubtree(key: ValueKey(c.tab), child: _body()),
            ],
          );
        },
      );

  Widget _body() => switch (c.tab) {
        'clients' => TpClientsTab(c, onAssign: _assign, onChanged: c.reloadMe),
        'access' => TpAccessTab(c),
        'activity' => MeActivityTab(c),
        'documents' => MeDocsTab(c),
        'clients-see' => MeClientsSeeTab(c),
        _ => MeOverviewTab(c, onTab: _tab, onEdit: _edit),
      };

  // ─────────────────────────────── Actions

  Future<void> _edit() async {
    if (await showEditMyDetails(context, c)) c.reloadMe();
  }

  Future<void> _assign() async {
    final n = await showAssignClients(context,
        id: widget.id, name: c.name, clients: _clients, max: (c.me['max_clients'] as num?)?.toInt() ?? 0, gender: '${c.me['gender'] ?? ''}');
    if (n == null || !mounted) return;
    await c.reloadMe();
    if (!mounted) return;
    showToast(context, '$n ${n == 1 ? 'client' : 'clients'} assigned to ${c.first}', kind: ToastKind.ok, action: 'View', onAction: () => _tab('clients'));
  }

  Future<void> _reset() async {
    final ok = await confirmAction(context,
        title: 'Send ${c.first} a password reset link?', body: '${c.first} gets a link on WhatsApp and email to set a new password.', confirm: 'Send link', icon: AppIcons.lock);
    if (!ok || !mounted) return;
    try {
      await Services.api.post('${c.api}/password-reset/', {});
      if (mounted) showToast(context, 'Reset link sent to ${c.first}', kind: ToastKind.ok);
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not send the link', sub: e.message, kind: ToastKind.err);
    }
  }

  Future<void> _move() async {
    final n = await showMoveTrainerClients(context, id: widget.id, name: c.name, clients: _clients);
    if (n == null || !mounted) return;
    await c.reloadMe();
    if (mounted) showToast(context, '$n ${n == 1 ? 'client' : 'clients'} moved', sub: 'From ${c.name}', kind: ToastKind.ok);
  }

  Future<void> _deactivate() async {
    if (!await showDeactivateTrainer(context, id: widget.id, name: c.name) || !mounted) return;
    await c.reloadMe();
    if (mounted) showToast(context, '${c.first} is deactivated', sub: 'Reactivate from ⋯ any time');
  }

  Future<void> _reactivate() async {
    try {
      await Services.api.post('${c.api}/reactivate/', {});
      await c.reloadMe();
      if (mounted) showToast(context, '${c.first} is active again', sub: 'They can log in now', kind: ToastKind.ok);
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not reactivate ${c.first}', sub: e.message, kind: ToastKind.err);
    }
  }

  void _menu(BuildContext b) => showAppMenu(b, width: 260, [
        MenuEntry('Access and permissions', icon: AppIcons.access, onTap: () => _tab('access')),
        MenuEntry('Send password reset link', icon: AppIcons.lock, onTap: _reset),
        MenuEntry('Move all clients to another trainer', icon: AppIcons.swapBoth, onTap: _move),
        if (!_owner) ...[
          const MenuEntry.separator(),
          if (_active)
            MenuEntry('Deactivate ${c.first}', icon: AppIcons.deactivate, danger: true, onTap: _deactivate)
          else
            MenuEntry('Reactivate ${c.first}', icon: AppIcons.power, onTap: _reactivate),
        ],
      ]);

  // ─────────────────────────────── Header

  Widget _crumb() => Row(spacing: 6, children: [
        Hover(
          onTap: () => context.go('/trainers'),
          builder: (_, h, _) => Text('Trainers', style: AppText.s(13, W.w5, color: h ? AppColors.text : AppColors.muted)),
        ),
        const AppIcon(AppIcons.chevronRight, size: 13, color: AppColors.chevron),
        Flexible(child: CutText(c.name.isEmpty ? 'Trainer' : c.name, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w6))),
      ]);

  Widget _avatar(double size) => AppAvatar(c.name, size: size, url: c.avatar, colors: AppColors.avatarCode(c.color), initials: c.initials);

  Widget _badge() => _active ? const AppBadge('Active', tone: Tone.ok) : const AppBadge('Inactive', tone: Tone.neutral);

  Widget _dots() => Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'More actions', onPressed: () => _menu(b)));

  List<Widget> _buttons({bool expand = false}) => [
        AppButton('Edit details', icon: AppIcons.editAlt, expand: expand, onPressed: _edit),
        AppButton.primary('Assign clients', icon: AppIcons.plus, expand: expand, onPressed: _active ? _assign : null),
      ];

  /// "Strength, fat loss | 6 years experience | Access Assigned clients | Last login today, 9:40 am".
  List<InlineSpan> _meta(TextStyle bold) {
    final sp = c.speciality;
    final spec = sp.isEmpty ? '' : [sp.first, ...sp.skip(1).map((s) => s.toLowerCase())].join(', ');
    final login = c.lastLogin?['text'] as String?;
    return [
      if (spec.isNotEmpty) TextSpan(text: spec),
      if (c.yearsText.isNotEmpty) TextSpan(text: '${c.yearsText} experience'),
      TextSpan(children: [const TextSpan(text: 'Access '), TextSpan(text: _owner ? 'Owner' : c.accessLevel, style: bold)]),
      TextSpan(text: login == null ? 'Never logged in' : 'Last login $login'),
    ];
  }

  Widget _metaWrap(TextStyle st, TextStyle bold) {
    final parts = _meta(bold);
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 2, children: [
      for (final (i, s) in parts.indexed) ...[
        if (i > 0) Container(width: 1, height: 13, margin: const EdgeInsets.symmetric(horizontal: 10), color: AppColors.line2),
        Text.rich(s, style: st),
      ],
    ]);
  }

  Widget _head() => Row(crossAxisAlignment: CrossAxisAlignment.center, spacing: 14, children: [
        _avatar(56),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
            Row(spacing: 10, children: [
              Flexible(child: CutText(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(28, W.w8, ls: -.7, h: 1.15))),
              _badge(),
            ]),
            _metaWrap(AppText.s(13, W.w5, color: AppColors.muted), AppText.s(13, W.w7, color: AppColors.text)),
          ]),
        ),
        ..._buttons(),
        _dots(),
      ]);

  /// Tablet: name and meta on the left, the buttons in a row under them.
  Widget _headMid() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, spacing: 14, children: [
          _avatar(56),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
              Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(c.name, style: AppText.s(24, W.w8, ls: -.6, h: 1.2)),
                _badge(),
              ]),
              _metaWrap(AppText.s(13, W.w5, color: AppColors.muted, h: 1.5), AppText.s(13, W.w7, color: AppColors.text, h: 1.5)),
            ]),
          ),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: [..._buttons(), _dots()]),
      ]);

  /// Phone: avatar, name + badge, meta with dots between; then Edit details | Assign clients | ⋯.
  Widget _headPhone() {
    final st = AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.55);
    final parts = _meta(AppText.s(12.5, W.w7, color: AppColors.text, h: 1.55));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
        _avatar(52),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(c.name, style: AppText.s(20, W.w8, ls: -.4, h: 1.2)),
              _badge(),
            ]),
            Text.rich(
              TextSpan(children: [
                for (final (i, s) in parts.indexed) ...[if (i > 0) const TextSpan(text: '  •  '), s],
              ]),
              style: st,
            ),
          ]),
        ),
      ]),
      Row(spacing: 8, children: [
        for (final b in _buttons(expand: true)) Expanded(child: b),
        _dots(),
      ]),
    ]);
  }

  // ─────────────────────────────── Stats

  String get _oldest {
    final n = (c.stats['checkins_to_review'] as num?) ?? 0;
    if (n == 0) return 'All reviewed';
    final t = meParse(c.stats['oldest_checkin_at']);
    if (t == null) return '';
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
    return switch (days) { 0 => 'Oldest from today', 1 => 'Oldest from yesterday', _ => 'Oldest from $days days ago' };
  }

  /// (icon, label, value, delta, up?, note, tab to open)
  List<(AppIconData, String, String, String?, bool?, String?, String?)> get _rows {
    final s = c.stats;
    final adh = s['adherence'] as num?, ch = s['adherence_change'] as num?;
    final reply = (c.me['reply'] as Map?) ?? const {};
    final mine = s['reply_hours'] as num?, team = s['team_reply_hours'] as num?;
    final team0 = '${reply['team'] ?? ''}';
    return [
      (AppIcons.team, 'Clients', '${s['clients'] ?? 0} / ${s['max_clients'] ?? 0}', null, null, '${s['free'] ?? 0} spots free', 'clients'),
      (AppIcons.clipboardShort, 'Check-ins to review', '${s['checkins_to_review'] ?? 0}', null, null, _oldest, null),
      (AppIcons.pulse, 'Avg adherence', adh == null ? '—' : '$adh%', ch == null ? null : '${ch >= 0 ? '+' : '−'}${ch.abs()}% vs last month', ch == null ? null : ch >= 0, null, null),
      (AppIcons.clock, 'Avg reply time', '${reply['value'] ?? '—'}', team0.isEmpty ? null : team0, mine == null || team == null ? null : mine <= team, null, null),
    ];
  }

  /// `.stats`: content-wide cards that wrap when narrow (the Clients card opens the Clients tab).
  Widget _stats() {
    final rows = _rows;
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final (ic, l, v, d, up, n, tab) in rows)
        if (tab == null)
          StatCard(icon: ic, label: l, value: v, delta: d, deltaUp: up, note: n, hug: true)
        else
          GestureDetector(
            onTap: () => _tab(tab),
            child: MouseRegion(cursor: SystemMouseCursors.click, child: StatCard(icon: ic, label: l, value: v, delta: d, deltaUp: up, note: n, hug: true)),
          ),
    ]);
  }

  /// Phone: one strip of 4 cells (number over label), as the board.
  Widget _statsPhone() => Container(
        decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(12), border: Border.all(color: AppColors.line)),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, s) in _rows.indexed)
              Expanded(
                child: GestureDetector(
                  onTap: s.$7 == null ? null : () => _tab(s.$7!),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 9),
                    decoration: BoxDecoration(border: i == 0 ? null : const Border(left: BorderSide(color: AppColors.line))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                      CutText(s.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(16, W.w8, h: 1.2, tabular: true)),
                      CutText(s.$2, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(10.5, W.w6, color: AppColors.muted, h: 1.25)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      );
}
