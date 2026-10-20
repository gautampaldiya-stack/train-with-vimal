import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/page.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/stat.dart';
import '../../../core/widgets/tabs.dart';
import 'me_account.dart';
import 'me_common.dart';
import 'me_docs.dart';
import 'me_edit.dart';
import 'me_model.dart';
import 'me_overview.dart';
import 'me_tabs.dart';

/// Trainer → My profile (boards `TrainerMe` / `TrainerMeMobile`): header with Edit my details, the 4 stats
/// (same numbers as the dashboard and the admin Trainers table, D-30) and 6 tabs. `/me/<tab>` opens a tab
/// (notices link to `/me/access`).
class TrainerMeScreen extends StatefulWidget {
  const TrainerMeScreen({super.key, this.tab});
  final String? tab;
  @override
  State<TrainerMeScreen> createState() => _TrainerMeScreenState();
}

class _TrainerMeScreenState extends State<TrainerMeScreen> {
  late final c = MeController(tab: widget.tab)..load();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  void _tab(String t) {
    c.setTab(t);
    // Keep the address in step so a refresh or a shared link opens the same tab.
    final path = t == 'overview' ? '/me' : '/me/$t';
    if (GoRouterState.of(context).uri.path != path) context.go(path);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          if (c.loading && c.me.isEmpty) return const MeLoading();
          if (c.me.isEmpty) {
            return StaffPage(children: [MeError(c.error?.message ?? 'Something went wrong', onRetry: c.load)]);
          }
          final phone = context.isPhone;
          return StaffPage(
            onRefresh: c.refresh,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 12 : 16, children: [
                // Header by the room it has: one meta line when wide; on narrow tablets the meta goes on its
                // own lines (no separator left hanging at a line end) and below ~620 the button goes full width.
                if (phone)
                  _headPhone()
                else
                  LayoutBuilder(builder: (context, b) => b.maxWidth >= 820 ? _head() : b.maxWidth >= 620 ? _headMid() : _headPhone()),
                phone ? _statsPhone() : _stats(),
              ]),
              UnderlineTabs<String>(
                items: [
                  for (final (k, l) in MeController.tabs) TabItem(k, l, count: k == 'documents' && c.docs.isNotEmpty ? c.docs.length : null),
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
        'documents' => MeDocsTab(c),
        'clients-see' => MeClientsSeeTab(c),
        'access' => MeAccessTab(c),
        'activity' => MeActivityTab(c),
        'account' => MeAccountTab(c),
        _ => MeOverviewTab(c, onTab: _tab, onEdit: _edit),
      };

  Future<void> _edit() => showEditMyDetails(context, c);

  // ─────────────────────────────── Header

  Widget _avatar(double size) => AppAvatar(c.name, size: size, url: c.avatar, colors: AppColors.avatarCode(c.color), initials: c.initials);

  /// "Strength, fat loss | 6 years experience | Access Assigned clients | Last login today, 9:40 am".
  List<InlineSpan> _meta(TextStyle st, TextStyle bold) {
    final sp = c.speciality;
    final spec = sp.isEmpty ? '' : [sp.first, ...sp.skip(1).map((s) => s.toLowerCase())].join(', ');
    final login = c.lastLogin?['text'] as String?;
    return [
      if (spec.isNotEmpty) TextSpan(text: spec),
      if (c.yearsText.isNotEmpty) TextSpan(text: '${c.yearsText} experience'),
      TextSpan(children: [const TextSpan(text: 'Access '), TextSpan(text: c.accessLevel, style: bold)]),
      if (login != null) TextSpan(text: 'Last login $login'),
    ];
  }

  Widget _head() {
    final st = AppText.s(13, W.w5, color: AppColors.muted);
    final parts = _meta(st, AppText.s(13, W.w7, color: AppColors.text));
    return Row(crossAxisAlignment: CrossAxisAlignment.center, spacing: 14, children: [
      _avatar(56),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
          Row(spacing: 10, children: [
            Flexible(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(28, W.w8, ls: -.7, h: 1.15))),
            _badge(),
          ]),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 2, children: [
            for (final (i, s) in parts.indexed) ...[
              if (i > 0) Container(width: 1, height: 13, margin: const EdgeInsets.symmetric(horizontal: 10), color: AppColors.line2),
              Text.rich(s, style: st),
            ],
          ]),
        ]),
      ),
      AppButton('Edit my details', icon: AppIcons.edit, onPressed: _edit),
    ]);
  }

  /// Tablet: avatar, name and the meta on separate lines, Edit my details on the right.
  Widget _headMid() {
    final st = AppText.s(13, W.w5, color: AppColors.muted, h: 1.5);
    return Row(crossAxisAlignment: CrossAxisAlignment.center, spacing: 14, children: [
      _avatar(56),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
          Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(c.name, style: AppText.s(24, W.w8, ls: -.6, h: 1.2)),
            _badge(),
          ]),
          ..._metaPhone(st, AppText.s(13, W.w7, color: AppColors.text, h: 1.5)),
        ]),
      ),
      AppButton('Edit my details', icon: AppIcons.edit, onPressed: _edit),
    ]);
  }

  Widget _badge() => switch ('${c.me['status']}') {
        'active' => const AppBadge('Active', tone: Tone.ok),
        _ => const AppBadge('Inactive', tone: Tone.neutral),
      };

  List<Widget> _metaPhone(TextStyle st, TextStyle bold) {
    final sp = c.speciality;
    final spec = sp.isEmpty ? '' : [sp.first, ...sp.skip(1).map((s) => s.toLowerCase())].join(', ');
    final login = c.lastLogin?['text'] as String?;
    final top = [if (spec.isNotEmpty) spec, if (c.yearsText.isNotEmpty) '${c.yearsText} experience'];
    return [
      if (top.isNotEmpty) Text(top.join('  •  '), style: st),
      Text.rich(TextSpan(children: [const TextSpan(text: 'Access '), TextSpan(text: c.accessLevel, style: bold)]), style: st),
      if (login != null) Text('Last login $login', style: st),
    ];
  }

  Widget _headPhone() {
    final st = AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.55);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
        _avatar(52),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(c.name, style: AppText.s(20, W.w8, ls: -.4, h: 1.2)),
              _badge(),
            ]),
            // Phone: "Strength, fat loss • 6 years experience", then access and last login on their own
            // lines, so no line starts with a dot and nothing breaks in the middle.
            ..._metaPhone(st, AppText.s(12.5, W.w7, color: AppColors.text, h: 1.55)),
          ]),
        ),
      ]),
      AppButton('Edit my details', icon: AppIcons.edit, expand: true, onPressed: _edit),
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
  List<(AppIconData, String, String, String?, bool?, String?, VoidCallback?)> get _rows {
    final s = c.stats;
    final adh = s['adherence'] as num?, ch = s['adherence_change'] as num?;
    final reply = (c.me['reply'] as Map?) ?? const {};
    final mine = s['reply_hours'] as num?, team = s['team_reply_hours'] as num?;
    final team0 = '${reply['team'] ?? ''}';
    return [
      (AppIcons.usersAlt, 'My clients', '${s['clients'] ?? 0} / ${s['max_clients'] ?? 0}', null, null, '${s['free'] ?? 0} spots free', () => context.go('/clients')),
      (AppIcons.docLines, 'Check-ins to review', '${s['checkins_to_review'] ?? 0}', null, null, _oldest, () => context.go('/checkins')),
      (AppIcons.pulse, 'Avg adherence', adh == null ? '—' : '$adh%', ch == null ? null : '${ch >= 0 ? '+' : '−'}${ch.abs()}% vs last month', ch == null ? null : ch >= 0, null, null),
      (AppIcons.clock, 'Avg reply time', '${reply['value'] ?? '—'}', team0.isEmpty ? null : team0, mine == null || team == null ? null : mine <= team, null, null),
    ];
  }

  Widget _stats() => LayoutBuilder(builder: (context, b) {
        final rows = _rows;
        Widget card(int i) {
          final (ic, l, v, d, up, n, tap) = rows[i];
          final w = StatCard(icon: ic, label: l, value: v, delta: d, deltaUp: up, note: n);
          return tap == null ? w : GestureDetector(onTap: tap, child: MouseRegion(cursor: SystemMouseCursors.click, child: w));
        }

        if (b.maxWidth < 900) {
          return Column(spacing: 10, children: [
            for (final r in [0, 2]) Row(spacing: 10, children: [Expanded(child: card(r)), Expanded(child: card(r + 1))]),
          ]);
        }
        // Cards fill the row like the dashboard's (D-31).
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [for (var i = 0; i < 4; i++) Expanded(child: card(i))]),
        );
      });

  /// Phone: one card with the 4 numbers in a 2 × 2 grid ("10 / 30" over "My clients"); tap opens the page.
  Widget _statsPhone() {
    final rows = _rows;
    Widget cell(int i) {
      final (_, l, v, _, _, _, tap) = rows[i];
      return Expanded(
        child: GestureDetector(
          onTap: tap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(17, W.w8, tabular: true)),
              Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted)),
            ]),
          ),
        ),
      );
    }

    Widget line(int a) => IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            cell(a),
            const VerticalDivider(width: 1, thickness: 1, color: AppColors.line),
            cell(a + 1),
          ]),
        );
    return AppCard(
      child: Column(children: [line(0), const Divider(height: 1, thickness: 1, color: AppColors.line), line(2)]),
    );
  }
}
