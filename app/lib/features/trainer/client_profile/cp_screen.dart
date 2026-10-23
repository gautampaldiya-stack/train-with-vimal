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
import '../../admin/clients/admin_client_drawers.dart' show showChangeTrainerDrawer;
import '../clients/clients_parts.dart';
import 'cp_activity.dart';
import 'cp_common.dart';
import 'cp_content.dart';
import 'cp_forms.dart';
import 'cp_history.dart';
import 'cp_logs.dart';
import 'cp_model.dart';
import 'cp_notes.dart';
import 'cp_overview.dart';
import 'cp_plans.dart';
import 'cp_progress.dart';
import '../../../core/widgets/tooltip.dart';

/// Client profile, trainer view (boards `TrainerClientProfile` + `TrainerClientProfileMobile`): breadcrumb, header
/// with Edit profile / Assign plan / ⋯, 4 stats, 9 tabs. Only the trainer's own clients open (API 404 otherwise).
class TrainerClientProfileScreen extends StatefulWidget {
  const TrainerClientProfileScreen({super.key, required this.id, this.tab, this.admin = false});
  final String id;
  final String? tab;

  /// Admin view (board `ClientProfile`, D-47): "Clients" breadcrumb, "Trainer Aman Verma" in the header line,
  /// Change trainer in ⋯ and the Coaching card, Sign-in (new password, reset link) in Edit profile.
  final bool admin;
  @override
  State<TrainerClientProfileScreen> createState() => _TrainerClientProfileScreenState();
}

const _badges = {
  'active': ('Active', Tone.ok),
  'pending': ('Pending', Tone.warn),
  'paused': ('Paused', Tone.neutral),
  'at_risk': ('At risk', Tone.bad),
};

class _TrainerClientProfileScreenState extends State<TrainerClientProfileScreen> {
  late final c = CpController(widget.id, admin: widget.admin);

  /// The admin, or a trainer with "Assign and reassign clients".
  bool get _canAssign => widget.admin || (Services.session.me?.can('clients.assign') ?? false);

  @override
  void initState() {
    super.initState();
    if (_canAssign) c.changeTrainer = _changeTrainer;
    if (widget.tab != null && CpController.tabs.any((t) => t.$1 == widget.tab)) c.tab = widget.tab!;
    c.load();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          if (c.loading && c.detail.isEmpty) return const CpLoading();
          if (c.detail.isEmpty) {
            return StaffPage(children: [
              _crumb(),
              AppCard(
                child: EmptyState(
                  c.error?.status == 404 ? (widget.admin ? 'This client is not there any more' : 'This client is not in your list') : 'Could not open this client',
                  sub: c.error?.status == 404 ? (widget.admin ? 'They may have been deleted.' : 'Only your own clients open here.') : c.error?.message,
                  action: AppButton(c.error?.status == 404 ? (widget.admin ? 'Back to Clients' : 'Back to My clients') : 'Try again', onPressed: c.error?.status == 404 ? () => context.go('/clients') : c.load),
                ),
              ),
            ]);
          }
          final phone = context.isPhone;
          return StaffPage(
            onRefresh: c.refresh,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 12 : 14, children: [
                _crumb(),
                phone ? _headPhone() : _head(),
                phone ? _statsPhone() : _stats(),
              ]),
              UnderlineTabs<String>(
                items: [for (final (k, l) in CpController.tabs) TabItem(k, l, count: c.counts[k])],
                value: c.tab,
                onChanged: c.setTab,
              ),
              KeyedSubtree(key: ValueKey(c.tab), child: _body()),
            ],
          );
        },
      );

  Widget _body() => switch (c.tab) {
        'plans' => CpPlansTab(c),
        'logs' => CpLogsTab(c),
        'progress' => CpProgressTab(c),
        'history' => CpHistoryTab(c),
        'content' => CpContentTab(c),
        'forms' => CpFormsTab(c),
        'activity' => CpActivityTab(c),
        'notes' => CpNotesTab(c),
        _ => CpOverviewTab(c),
      };

  // ─────────────────────────────── Header

  Widget _crumb() => Row(spacing: 6, children: [
        Hover(
          onTap: () => context.go('/clients'),
          builder: (_, h, _) => Text(widget.admin ? 'Clients' : 'My clients', style: AppText.s(13, W.w5, color: h ? AppColors.text : AppColors.muted)),
        ),
        const AppIcon(AppIcons.chevronRight, size: 13, color: AppColors.chevron),
        Flexible(child: CutText(c.name.isEmpty ? 'Client' : c.name, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w6))),
      ]);

  Widget _avatar(double size) => AppAvatar(c.name,
      size: size, url: c.detail['avatar'] as String?, colors: AppColors.avatarCode('${c.detail['avatar_color'] ?? 'c1'}'), initials: '${c.detail['initials'] ?? ''}');

  Widget _badge() {
    final b = '${c.detail['badge'] ?? c.detail['status'] ?? ''}';
    final (l, t) = _badges[b] ?? (b, Tone.neutral);
    return AppBadge(l, tone: t);
  }

  /// "Fat loss · 68 kg goal | Your client since 12 Jan | Active 2 h ago" (admin: "Trainer Aman Verma").
  List<String> get _subParts {
    final goal = '${c.detail['goal_label'] ?? ''}';
    final target = c.profile['target_weight_kg'];
    final since = c.profile['start_date'] ?? c.detail['date_joined'];
    final tr = c.detail['trainer'] as Map?;
    return [
      [if (goal.isNotEmpty) goal, if (target != null) '${cpKg(target)} goal'].join(' · '),
      if (widget.admin)
        tr == null ? 'No trainer' : 'Trainer ${tr['full_name']}'
      else if (since != null)
        'Your client since ${cpDm(since)}',
      if ('${c.detail['last_active'] ?? '—'}' != '—') 'Active ${c.detail['last_active']}',
    ].where((s) => s.isNotEmpty).toList();
  }

  Widget _head() => Row(crossAxisAlignment: CrossAxisAlignment.center, spacing: 14, children: [
        _avatar(56),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
            Row(spacing: 10, children: [
              Flexible(child: CutText(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(28, W.w8, ls: -.7, h: 1.15))),
              _badge(),
            ]),
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final (i, s) in _subParts.indexed) ...[
                if (i > 0) Container(width: 1, height: 12, margin: const EdgeInsets.symmetric(horizontal: 10), color: AppColors.line2),
                Text(s, style: AppText.s(13, W.w5, color: AppColors.muted)),
              ],
            ]),
          ]),
        ),
        ..._actions(false),
      ]);

  Widget _headPhone() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
          _avatar(52),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(c.name, style: AppText.s(20, W.w8, ls: -.4, h: 1.2)),
                _badge(),
              ]),
              Text(_subParts.join(' • '), style: AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.45)),
            ]),
          ),
        ]),
        Row(spacing: 8, children: _actions(true)),
      ]);

  List<Widget> _actions(bool phone) {
    Widget grow(Widget w) => phone ? Expanded(child: w) : w;
    return [
      grow(AppButton('Edit profile', icon: AppIcons.edit, expand: phone, onPressed: _edit)),
      grow(Builder(
        builder: (b) => AppButton.primary('Assign plan', icon: AppIcons.plus, trailingIcon: AppIcons.chevronDown, expand: phone, onPressed: () => _assignMenu(b)),
      )),
      Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'More actions', onPressed: () => _moreMenu(b))),
    ];
  }

  void _assignMenu(BuildContext anchor) => showAppMenu(anchor, [
        for (final (k, l, ic) in const [
          ('workout', 'Workout plan', AppIcons.dumbbell),
          ('meal', 'Meal plan', AppIcons.apple),
          ('supplements', 'Supplement plan', AppIcons.pill),
          ('habits', 'Habit plan', AppIcons.checkCircle),
        ])
          MenuEntry(l, icon: ic, onTap: () => showAssignPlan(context, c, k)),
      ], width: 210);

  void _moreMenu(BuildContext anchor) => showAppMenu(anchor, [
        MenuEntry('Edit profile details', icon: AppIcons.edit, onTap: _edit),
        if (_canAssign) MenuEntry('Change trainer', icon: AppIcons.swap, onTap: _changeTrainer),
        MenuEntry('Assign a plan', icon: AppIcons.plus, onTap: () => Future.microtask(() {
              if (anchor.mounted) _assignMenu(anchor);
            })),
        MenuEntry('Send check-in reminder', icon: AppIcons.bell, onTap: _remind),
        MenuEntry('Full history', icon: AppIcons.activity, onTap: () => c.setTab('history')),
      ], width: 230);

  Future<void> _edit() async {
    final saved = await showClientDetailsDrawer(
      context,
      id: c.id,
      clientName: c.name,
      title: 'Edit profile',
      load: () => Services.api.get<Map>('clients/${c.id}/'),
      onSave: (data) => Services.api.patch('clients/${c.id}/', data),
      admin: widget.admin,
      onChangeTrainer: _canAssign ? _changeTrainer : null,
    );
    if (saved == true && mounted) {
      showToast(context, '${c.first}’s details saved', kind: ToastKind.ok);
      c.refresh();
    }
  }

  Future<void> _changeTrainer() async {
    final ok = await showChangeTrainerDrawer(context, id: c.id, name: c.name, gender: '${c.detail['gender'] ?? ''}');
    if (ok == true && mounted) {
      showToast(context, '${c.first} has a new trainer', kind: ToastKind.ok);
      c.refresh();
    }
  }

  Future<void> _remind() async {
    try {
      await Services.api.post('clients/${c.id}/remind/', {'message': 'Your check-in is waiting. It takes 2 minutes.'});
      if (mounted) showToast(context, 'Reminder sent', sub: '${c.first} gets it in the app and by email', kind: ToastKind.ok);
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not send the reminder', sub: e.message, kind: ToastKind.info);
    }
  }

  // ─────────────────────────────── Stats

  /// (icon, label, value, delta, up?, note)
  List<(AppIconData, String, String, String?, bool?, String?)> get _statRows {
    final s = c.stats;
    final adh = s['adherence'] as num?, adhCh = s['adherence_change'] as num?;
    final w = s['weight'] as num?, wCh = s['weight_change'] as num?;
    final target = s['target_weight'] as num?, start = c.profile['start_weight_kg'] as num?;
    // Weight going the way of the goal is good (down for a fat loss goal, up for muscle gain).
    final towardGoal = wCh == null || target == null || start == null ? null : (target < start ? wCh < 0 : wCh > 0);
    final waiting = s['checkin_waiting'] as Map?;
    return [
      (AppIcons.checkCircle, 'Adherence', adh == null ? '—' : '$adh%', adhCh == null ? null : '${adhCh >= 0 ? '+' : '−'}${adhCh.abs()}% vs last month', adhCh == null ? null : adhCh >= 0, null),
      (AppIcons.scale, 'Weight', w == null ? '—' : cpKg(w, keep: true), wCh == null ? null : '${cpSigned(wCh, 'kg')} since start', towardGoal, null),
      (AppIcons.dumbbell, 'Workouts', '${s['workouts_done'] ?? 0}/${s['workouts_planned'] ?? 0}', null, null, 'Done in last 30 days'),
      (
        AppIcons.clipboard,
        'Check-ins',
        '${s['checkins_reviewed'] ?? 0}/${s['checkins_sent'] ?? 0}',
        null,
        null,
        waiting == null ? 'All reviewed' : 'Week ${waiting['week']} waiting for review'
      ),
    ];
  }

  Widget _stats() => LayoutBuilder(builder: (context, b) {
        final rows = _statRows;
        Widget card(int i) {
          final (ic, l, v, d, up, n) = rows[i];
          final tap = switch (i) { 1 => () => c.setTab('progress'), 2 => () => c.setTab('logs'), 3 => () => c.setTab('logs'), _ => null };
          return Hover(onTap: tap, builder: (_, _, _) => StatCard(icon: ic, label: l, value: v, delta: d, deltaUp: up, note: n));
        }

        Widget sized(int i) => IntrinsicWidth(child: card(i));

        // Cards sit at their own width like the board; narrow screens share the row two by two.
        if (b.maxWidth < 900) {
          return Column(spacing: 10, children: [
            for (final r in [0, 2]) Row(spacing: 10, children: [Expanded(child: card(r)), Expanded(child: card(r + 1))]),
          ]);
        }
        return Wrap(spacing: 10, runSpacing: 10, children: [for (var i = 0; i < 4; i++) sized(i)]);
      });

  /// Phone: one card, 4 columns (`86%` over "Adherence").
  Widget _statsPhone() {
    final rows = _statRows;
    return AppCard(
      child: IntrinsicHeight(
        child: Row(children: [
          for (final (i, (_, l, v, _, _, _)) in rows.indexed) ...[
            if (i > 0) const VerticalDivider(width: 1, thickness: 1, color: AppColors.line),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 9, 6, 9),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                  FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: AppText.s(15, W.w8, tabular: true))),
                  CutText(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11, W.w5, color: AppColors.muted)),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
