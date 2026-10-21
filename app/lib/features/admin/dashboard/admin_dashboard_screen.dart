import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart' show confirmLogOut;
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
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import '../../../core/widgets/tooltip.dart';
import '../../trainer/dashboard/dashboard_parts.dart' show showNotesDropdown;
import 'admin_dashboard_model.dart';

/// Admin Dashboard (boards `AdminDashboard` / `AdminDashboardMobile`): 4 stats, 6 "at a glance" tiles, then
/// Needs action + Trainer performance (left) and At-risk clients + Recent activity (right). One column ≤ 900;
/// phone = KPI strip, glance as one list card, the table as rows.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final c = AdminHomeController();
  String _kind = '';
  bool _allNeeds = false, _allTrainers = false, _allRisk = false;

  @override
  void initState() {
    super.initState();
    c.load();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  void _fail(Object e) => showToast(context, e is ApiError ? e.message : 'Something went wrong', sub: 'Try again in a moment.', kind: ToastKind.err);

  bool get _phone => context.isPhone;
  EdgeInsets get _hPad => _phone ? const EdgeInsets.fromLTRB(16, 16, 16, 8) : const EdgeInsets.fromLTRB(20, 16, 20, 8);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final d = c.data;
          if (d == null) {
            final e = c.error;
            return Center(
              child: e == null
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))
                  : EmptyState(e.offline ? 'You are offline' : 'Could not load your dashboard',
                      sub: e.offline ? 'Connect to the internet and try again.' : e.message, action: AppButton('Try again', onPressed: c.load)),
            );
          }
          final cols = MediaQuery.sizeOf(context).width > 900;
          final left = [_needs(d), _perf(d)], right = [_risk(d), _activity(d)];
          return StaffPage(
            onRefresh: c.load,
            header: _phone ? _phoneTop(d) : PageTop(title: d.greeting, sub: d.subline, actions: _actions(d)),
            children: [
              _phone ? _strip(d) : _stats(d),
              _phone ? _glanceList(d) : _glance(d),
              if (!cols)
                ...[...left, ...right]
              else
                Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
                  Expanded(flex: 14, child: Column(spacing: 16, crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
                  Expanded(flex: 10, child: Column(spacing: 16, crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
                ]),
            ],
          );
        },
      );

  // ─────────────────────────────── Header

  List<Widget> _actions(AdminHome d) => [
        AppIconButton(AppIcons.search, tooltip: 'Search', onPressed: _search),
        Builder(builder: (b) => AppIconButton(AppIcons.bell, tooltip: 'Notifications', dot: d.unread > 0, onPressed: () => _notes(b))),
        AppButton.primary('Add client', icon: AppIcons.plus, iconOnly: compactTop(context), onPressed: _addClient),
        Builder(builder: (b) => _Profile(onTap: () => _account(b))),
      ];

  /// Phone `.top`: title and the buttons on one line, the date line under both (2 lines max).
  Widget _phoneTop(AdminHome d) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 2, children: [
        Row(spacing: 10, children: [
          Expanded(child: Text(d.greeting, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.h1.copyWith(fontSize: 17))),
          Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: _actions(d)),
        ]),
        Text(d.subline, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.sub.copyWith(fontSize: 12, height: 1.4)),
      ]);

  void _addClient() => context.go('/clients?add=1');

  void _notes(BuildContext anchor) => showNotesDropdown(anchor, c, onOpen: (n) {
        if (n.route.isNotEmpty) context.go(n.route);
      });

  void _account(BuildContext anchor) {
    final me = Services.session.me;
    showAppMenu(anchor, width: 220, [
      MenuEntry.header('${me?.name ?? 'Vimal'} · Admin'),
      MenuEntry('Settings', icon: AppIcons.settings, onTap: () => context.go('/settings')),
      const MenuEntry.separator(),
      MenuEntry('Log out', icon: AppIcons.logout, danger: true, onTap: () => confirmLogOut(context)),
    ]);
  }

  Future<void> _search() async {
    final id = await showAppModal<String>(context, title: 'Search clients', icon: AppIcons.search, content: (ctx) => _ClientSearch(c));
    if (id != null && mounted) context.go('/clients/$id');
  }

  // ─────────────────────────────── Stats

  static String _pct(num? v) => v == null ? '—' : '$v%';

  /// "+3% vs last week" (green), "−2% vs last week" (red), "Same as last week".
  static (String, Color) _vs(num? delta) {
    if (delta == null) return ('No data last week', AppColors.muted);
    if (delta == 0) return ('Same as last week', AppColors.muted);
    return delta > 0 ? ('+$delta% vs last week', AppColors.okText) : ('−${delta.abs()}% vs last week', AppColors.badText);
  }

  List<(AppIconData, String, String, String, Color, bool)> _statRows(AdminHome d) {
    final fresh = d.stat('active_clients', 'new_this_month') ?? 0;
    final oldest = DateTime.tryParse('${(d.stats['pending_approvals'] as Map?)?['oldest_at'] ?? ''}');
    final days = oldest == null ? null : DateTime.now().difference(oldest).inDays;
    final (rate, rateC) = _vs(d.stat('checkin_rate', 'delta'));
    final (adh, adhC) = _vs(d.stat('adherence', 'delta'));
    return [
      (AppIcons.client, 'Active clients', '${d.stat('active_clients') ?? 0}', fresh > 0 ? '+$fresh this month' : 'None new this month',
          fresh > 0 ? AppColors.okText : AppColors.muted, fresh > 0),
      (
        AppIcons.approvals,
        'Pending approvals',
        '${d.stat('pending_approvals') ?? 0}',
        days == null ? 'Nobody waiting' : (days < 1 ? 'Oldest waiting since today' : 'Oldest waiting $days day${days == 1 ? '' : 's'}'),
        AppColors.muted,
        false
      ),
      (AppIcons.clipboardShort, 'Check-in rate', _pct(d.stat('checkin_rate')), rate, rateC, false),
      (AppIcons.programs, 'Avg adherence', _pct(d.stat('adherence')), adh, adhC, false),
    ];
  }

  /// `.stats`: content-wide cards on one line (gap 10) that scroll sideways when the page is narrow.
  Widget _stats(AdminHome d) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(spacing: 10, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (icon, label, value, delta, color, trend) in _statRows(d))
            Container(
              height: 80,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: AppColors.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
                  IconTile(icon, radius: 8),
                  Text(label, style: AppText.s(12.5, W.w6, color: AppColors.muted)),
                ]),
                Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 10, children: [
                  Text(value, style: AppText.stat),
                  Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
                    if (trend) AppIcon(AppIcons.trendUp, size: 14, color: color),
                    Text(delta, style: AppText.s(12, W.w7, color: color)),
                  ]),
                ]),
              ]),
            ),
        ]),
      );

  /// Phone: one white strip of 4 cells (number 16/800 over a 10.5/600 label).
  Widget _strip(AdminHome d) => Container(
        decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(12), border: Border.all(color: AppColors.line)),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, s) in _statRows(d).indexed)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 9),
                  decoration: BoxDecoration(border: i == 0 ? null : const Border(left: BorderSide(color: AppColors.line))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                    Text(s.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(16, W.w8, h: 1.2, tabular: true)),
                    Text(s.$2, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(10.5, W.w6, color: AppColors.muted, h: 1.25)),
                  ]),
                ),
              ),
          ]),
        ),
      );

  // ─────────────────────────────── At a glance

  List<_Gl> _glanceRows(AdminHome d) {
    final over = d.glanceOf('trainers', 'over_capacity'), late = d.glanceOf('checkins_to_review', 'over_48h');
    final onb = d.glanceOf('onboarding_pending'), forms = d.glanceOf('onboarding_pending', 'forms_missing');
    return [
      _Gl(AppIcons.clients, d.glanceOf('clients'), 'Clients',
          '${d.glanceOf('clients', 'active')} active · ${d.glanceOf('clients', 'paused')} paused', '/clients'),
      _Gl(AppIcons.trainers, d.glanceOf('trainers'), 'Trainers', over > 0 ? '$over over capacity' : 'All within capacity', '/trainers', warn: over > 0),
      _Gl(AppIcons.forms, d.glanceOf('checkins_to_review'), 'Check-ins to review',
          late > 0 ? '$late waiting over 48 h' : 'None waiting over 48 h', '/checkins', warn: late > 0),
      _Gl(AppIcons.personAdd, onb, 'Onboarding pending',
          onb == 0 ? 'Everyone is set up' : (forms > 0 ? '$forms form${forms == 1 ? '' : 's'} not complete' : 'Setup steps left'),
          '/clients?onboarding=in_progress'),
      _Gl(AppIcons.nutrition, d.glanceOf('nutrition_pending'), 'Nutrition plans pending', 'Clients without a meal plan', '/nutrition'),
      _Gl(AppIcons.programs, d.glanceOf('programs_ending'), 'Programs ending', 'This week · plan what is next', '/programs'),
    ];
  }

  /// `.glance`: 6 tiles in a row (3 under 1200 wide).
  Widget _glance(AdminHome d) {
    final per = MediaQuery.sizeOf(context).width > 1200 ? 6 : 3;
    final rows = _glanceRows(d);
    return Column(spacing: 10, children: [
      for (var i = 0; i < rows.length; i += per)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            for (final g in rows.skip(i).take(per)) Expanded(child: _GlTile(g, onTap: () => context.go(g.route))),
          ]),
        ),
    ]);
  }

  /// Phone: one card of compact rows (icon · title over sub · number · chevron).
  Widget _glanceList(AdminHome d) {
    final rows = _glanceRows(d);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(14), border: Border.all(color: AppColors.line)),
      child: Column(children: [
        for (final (i, g) in rows.indexed)
          Hover(
            onTap: () => context.go(g.route),
            builder: (_, h, _) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: h ? AppColors.hover : null,
                border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(spacing: 10, children: [
                _GlIcon(g),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(g.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w7)),
                    Text(g.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w5, color: g.warn ? AppColors.warnText : AppColors.muted)),
                  ]),
                ),
                Text('${g.n}', style: AppText.s(17, W.w8, tabular: true)),
                const AppIcon(AppIcons.chevronRight, size: 14, color: AppColors.line2),
              ]),
            ),
          ),
      ]),
    );
  }

  // ─────────────────────────────── Needs action

  static const _kinds = [('approvals', 'Approvals'), ('clients', 'Clients'), ('checkins', 'Check-ins'), ('trainers', 'Trainers'), ('programs', 'Programs')];
  static final _kindIcon = {
    'approvals': (AppIcons.approvals, 'c4'),
    'clients': (AppIcons.client, 'c1'),
    'checkins': (AppIcons.clock, 'c3'),
    'trainers': (AppIcons.trainers, 'c5'),
    'programs': (AppIcons.programs, 'c6'),
  };

  Widget _needs(AdminHome d) {
    final all = d.needs;
    final kind = all.any((n) => n.kind == _kind) ? _kind : '';
    final list = all.where((n) => kind.isEmpty || n.kind == kind).toList();
    final shown = _allNeeds ? list : list.take(5).toList();
    final chips = [
      FilterChipX('All', selected: kind.isEmpty, count: all.length, onTap: () => setState(() => _kind = '')),
      for (final (k, label) in _kinds)
        if (all.any((n) => n.kind == k))
          FilterChipX(label,
              selected: kind == k,
              count: all.where((n) => n.kind == k).length,
              onTap: () => setState(() {
                    _kind = k;
                    _allNeeds = false;
                  })),
    ];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader('Needs action', padding: _hPad, count: AppCount(all.length), action: Text('Oldest first', style: AppText.cap)),
        if (all.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(_phone ? 16 : 20, 2, _phone ? 0 : 20, 8),
            child: _phone
                ? SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(right: 28), child: Row(spacing: 6, children: chips))
                : Wrap(spacing: 6, runSpacing: 6, children: chips),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
            if (all.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(12, 14, 12, 14), child: Text('All clear. Nothing needs you right now.', style: AppText.cap)),
            for (final n in shown) _needRow(n),
            if (list.length > 5) _More(_allNeeds ? 'Show less' : 'Show all ${list.length}', () => setState(() => _allNeeds = !_allNeeds)),
          ]),
        ),
      ]),
    );
  }

  Widget _needRow(AdNeed n) {
    final (icon, color) = _kindIcon[n.kind] ?? (AppIcons.info, 'c1');
    final (bg, fg) = AppColors.avatarCode(color);
    return Hover(
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: h && !_phone ? AppColors.hover : null, borderRadius: AppRadius.all(AppRadius.item)),
        child: Row(spacing: _phone ? 10 : 12, children: [
          IconTile(icon, size: 32, bg: bg, fg: fg, radius: 10, iconSize: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text(n.title, style: AppText.rowTitle),
              if (n.sub.isNotEmpty) Text(n.sub, style: AppText.rowSub),
            ]),
          ),
          AppButton(n.cta, size: BtnSize.sm, onPressed: () => context.go(n.route)),
          Opacity(
            opacity: h || _phone ? 1 : 0,
            child: AppIconButton(AppIcons.close, tooltip: 'Dismiss', small: true, ghost: true, onPressed: () => _dismiss(n)),
          ),
        ]),
      ),
    );
  }

  void _dismiss(AdNeed n) {
    c.dismiss(n).catchError(_fail);
    showToast(context, 'Removed from Needs action', sub: n.title);
  }

  // ─────────────────────────────── Trainer performance

  Widget _perf(AdminHome d) {
    final all = d.trainers;
    final shown = _allTrainers ? all : all.take(5).toList();
    // AppSelect fills its width, so it gets one here (the card header gives it none).
    final select = SizedBox(
      width: 128,
      height: 32,
      child: AppSelect(c.period == 'month' ? 'This month' : 'This week', entries: [
        MenuEntry('This week', selected: c.period == 'week', onTap: () => c.setPeriod('week').catchError(_fail)),
        MenuEntry('This month', selected: c.period == 'month', onTap: () => c.setPeriod('month').catchError(_fail)),
      ]),
    );
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader('Trainer performance', padding: _hPad, sub: 'Lowest adherence first', action: select),
        if (all.isEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), child: Text('No active trainers yet.', style: AppText.cap))
        else if (_phone)
          Column(children: [for (final (i, t) in shown.indexed) _perfRowPhone(t, first: i == 0)])
        else
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: const BoxDecoration(color: AppColors.tableHead, border: Border(bottom: BorderSide(color: AppColors.line), top: BorderSide(color: AppColors.line))),
                child: _cells([
                  for (final h in ['Trainer', 'Clients', 'Adherence', 'Avg reply']) Text(h, style: AppText.s(12, W.w7, color: AppColors.muted)),
                ]),
              ),
              for (final (i, t) in shown.indexed) _perfRow(t, last: i == shown.length - 1 && all.length <= 5),
            ]),
          ),
        if (all.length > 5)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: _More(_allTrainers ? 'Show less' : 'Show all ${all.length} trainers', () => setState(() => _allTrainers = !_allTrainers)),
          ),
      ]),
    );
  }

  /// Table columns: Trainer · Clients · Adherence · Avg reply (right).
  Widget _cells(List<Widget> w) => Row(spacing: 14, children: [
        Expanded(flex: 26, child: w[0]),
        Expanded(flex: 12, child: w[1]),
        Expanded(flex: 20, child: w[2]),
        Expanded(flex: 9, child: Align(alignment: Alignment.centerRight, child: w[3])),
      ]);

  Widget _perfRow(AdTrainer t, {required bool last}) => Hover(
        onTap: () => context.go('/trainers/${t.id}'),
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(color: h ? AppColors.hover : null, border: last ? null : const Border(bottom: BorderSide(color: AppColors.line))),
          child: _cells([
            Row(spacing: 10, children: [
              _Av(t.name, t.initials, t.color),
              Flexible(child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7))),
            ]),
            Text(t.load, style: t.over ? AppText.s(13.5, W.w7, color: AppColors.badText, tabular: true) : AppText.s(13.5, W.w5, tabular: true)),
            Row(spacing: 8, children: [
              ProgressBar(value: (t.adherence ?? 0) / 100, width: 90),
              Text(t.adherence == null ? '—' : '${t.adherence}%', style: AppText.cap),
            ]),
            Text(t.replyLabel, style: AppText.s(13.5, W.w5, tabular: true)),
          ]),
        ),
      );

  Widget _perfRowPhone(AdTrainer t, {required bool first}) => Hover(
        onTap: () => context.go('/trainers/${t.id}'),
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(color: h ? AppColors.hover : null, border: Border(top: first ? const BorderSide(color: AppColors.line) : BorderSide.none, bottom: const BorderSide(color: AppColors.line))),
          child: Row(spacing: 12, children: [
            _Av(t.name, t.initials, t.color),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(14, W.w7)),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: t.load, style: t.over ? AppText.s(12.5, W.w7, color: AppColors.badText) : null),
                    TextSpan(text: ' clients · Avg reply ${t.replyLabel}'),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.s(12.5, W.w5, color: AppColors.muted),
                ),
              ]),
            ),
            ProgressBar(value: (t.adherence ?? 0) / 100, width: 56),
            SizedBox(width: 34, child: Text(t.adherence == null ? '—' : '${t.adherence}%', textAlign: TextAlign.right, style: AppText.s(12, W.w5, color: AppColors.muted))),
          ]),
        ),
      );

  // ─────────────────────────────── At-risk clients

  Widget _risk(AdminHome d) {
    final shown = _allRisk ? d.risk : d.risk.take(3).toList();
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader('At-risk clients',
            padding: _hPad,
            count: AppCount(d.riskCount),
            action: d.riskCount == 0 ? null : _Link('Remind all', () => _remindAll(d))),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
            if (d.risk.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), child: Text('Nobody at risk right now.', style: AppText.cap)),
            for (final r in shown) _riskRow(r),
            if (d.riskCount > 3)
              _allRisk && d.riskCount > d.risk.length
                  ? _More('Open all ${d.riskCount} in Clients', () => context.go('/clients?badge=at_risk'))
                  : _More(_allRisk ? 'Show less' : 'Show all ${d.riskCount}', () => setState(() => _allRisk = !_allRisk)),
          ]),
        ),
      ]),
    );
  }

  Widget _riskRow(AdRisk r) => Hover(
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: h && !_phone ? AppColors.hover : null, borderRadius: AppRadius.all(AppRadius.item)),
          child: Row(spacing: 10, children: [
            _Av(r.name, r.initials, r.color),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                _NameLink(r.name, () => context.go('/clients/${r.id}')),
                if (r.why.isNotEmpty) Text(r.why, style: AppText.rowSub),
              ]),
            ),
            r.reminded
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
                      const AppIcon(AppIcons.check, size: 14, color: AppColors.muted),
                      Text('Reminded', style: AppText.s(12.5, W.w7, color: AppColors.muted)),
                    ]),
                  )
                : AppButton('Remind', size: BtnSize.sm, onPressed: () => _remind(r)),
          ]),
        ),
      );

  void _remind(AdRisk r) {
    c.remind(r);
    showToast(context, 'Reminder sent to ${r.first}', sub: 'Push and WhatsApp · their trainer is copied', action: 'Undo', onAction: () => c.undoRemind(r));
  }

  Future<void> _remindAll(AdminHome d) async {
    final skip = ValueNotifier(d.remindedRecently > 0);
    final ok = await showAppModal<bool>(
      context,
      title: 'Remind ${d.riskCount} at-risk client${d.riskCount == 1 ? '' : 's'}?',
      body: "Each client gets a push and WhatsApp message to log today's workout. Their trainer is copied.",
      icon: AppIcons.bell,
      content: (ctx) => ValueListenableBuilder(
        valueListenable: skip,
        builder: (_, on, _) => Hover(
          onTap: () => skip.value = !on,
          builder: (_, _, _) => Row(spacing: 8, children: [
            AppCheckbox(value: on, onChanged: (v) => skip.value = v),
            Flexible(child: Text('Skip clients reminded in the last 24 hours (${d.remindedRecently})', style: AppText.s(12, W.w6, color: AppColors.text2))),
          ]),
        ),
      ),
      actions: (ctx) => [
        AppButton('Cancel', onPressed: () => Navigator.of(ctx).pop(false), expand: ctx.isPhone),
        ValueListenableBuilder(
          valueListenable: skip,
          builder: (_, on, _) {
            final n = d.riskCount - (on ? d.remindedRecently : 0);
            final b = AppButton.primary('Remind $n client${n == 1 ? '' : 's'}', onPressed: n <= 0 ? null : () => Navigator.of(ctx).pop(true));
            return ctx.isPhone ? Expanded(child: b) : b;
          },
        ),
      ],
    );
    if (ok != true || !mounted) return;
    try {
      final n = await c.remindAll(skipRecent: skip.value);
      if (!mounted) return;
      showToast(context, 'Reminded $n client${n == 1 ? '' : 's'}', sub: 'Push and WhatsApp · their trainers are copied');
    } catch (e) {
      _fail(e);
    }
  }

  // ─────────────────────────────── Recent activity

  Widget _activity(AdminHome d) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHeader('Recent activity', padding: _hPad, action: _Link('View all', () => context.go('/activity'))),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
              if (d.activity.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), child: Text('Nothing yet today.', style: AppText.cap)),
              for (final a in d.activity)
                AppTooltip(
                  message: '${a.who} ${a.what}',
                  child: Hover(
                    builder: (_, h, _) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: h && !_phone ? AppColors.hover : null, borderRadius: AppRadius.all(AppRadius.item)),
                      child: Row(spacing: 10, children: [
                        _Av(a.who, a.initials, a.color),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [TextSpan(text: a.who, style: AppText.s(13, W.w7)), TextSpan(text: ' ${a.what}')]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.s(13, W.w5, color: AppColors.text2),
                          ),
                        ),
                        Text(a.ago, style: AppText.s(12, W.w5, color: AppColors.muted)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      );
}

// ─────────────────────────────── Pieces

class _Gl {
  _Gl(this.icon, this.n, this.label, this.sub, this.route, {this.warn = false});
  final AppIconData icon;
  final num n;
  final String label, sub, route;
  final bool warn;
}

class _GlIcon extends StatelessWidget {
  const _GlIcon(this.g);
  final _Gl g;
  @override
  Widget build(BuildContext context) =>
      IconTile(g.icon, size: 28, radius: 8, iconSize: 15, bg: g.warn ? AppColors.warnBg : AppColors.sub, fg: g.warn ? AppColors.warnText : AppColors.text2);
}

/// `.gl` tile: icon, number over label over sub (both cut with …, full text in the tooltip), chevron.
class _GlTile extends StatelessWidget {
  const _GlTile(this.g, {required this.onTap});
  final _Gl g;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => AppTooltip(
        message: '${g.label} · ${g.sub}',
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: h ? AppColors.line2 : AppColors.line)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
              _GlIcon(g),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${g.n}', style: AppText.s(18, W.w8, h: 1.15, tabular: true)),
                  Text(g.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w7)),
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(g.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w5, color: g.warn ? AppColors.warnText : AppColors.muted)),
                  ),
                ]),
              ),
              Padding(padding: const EdgeInsets.only(top: 7), child: AppIcon(AppIcons.chevronRight, size: 14, color: h ? AppColors.accent : AppColors.line2)),
            ]),
          ),
        ),
      );
}

/// `.av.sm` 26 with the board colour class.
class _Av extends StatelessWidget {
  const _Av(this.name, this.initials, this.color);
  final String name, initials, color;
  @override
  Widget build(BuildContext context) => AppAvatar(name, size: 26, colors: AppColors.avatarCode(color), initials: initials.isEmpty ? null : initials);
}

/// `.na-more`: centred blue 13/700 button, 32 high.
class _More extends StatelessWidget {
  const _More(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          height: 32,
          margin: const EdgeInsets.fromLTRB(4, 2, 4, 0),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: h ? AppColors.hover : null, borderRadius: AppRadius.all(AppRadius.item)),
          child: Text(label, style: AppText.s(13, W.w7, color: AppColors.accentText)),
        ),
      );
}

class _Link extends StatelessWidget {
  const _Link(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Text(label, style: AppText.s(13, W.w7, color: h ? AppColors.linkHover : AppColors.accentText)),
      );
}

class _NameLink extends StatelessWidget {
  const _NameLink(this.name, this.onTap);
  final String name;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Text(name,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle.copyWith(decoration: h ? TextDecoration.underline : null)),
      );
}

/// `.profile`: round 36 "V" (account menu), ring on hover.
class _Profile extends StatelessWidget {
  const _Profile({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => AppTooltip(
        message: '${Services.session.me?.name ?? ''} · Admin',
        child: Semantics(
          button: true,
          label: 'Account menu',
          child: Hover(
            onTap: onTap,
            builder: (_, h, _) => Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.meAvBg,
                shape: BoxShape.circle,
                boxShadow: h ? const [BoxShadow(color: AppColors.accentSoft, spreadRadius: 3)] : null,
              ),
              child: Text((Services.session.me?.name ?? 'V').characters.first, style: AppText.s(13, W.w8, color: AppColors.accentText)),
            ),
          ),
        ),
      );
}

/// Header search: clients by name, email or phone (300 ms after typing). Picking one closes with its id.
class _ClientSearch extends StatefulWidget {
  const _ClientSearch(this.c);
  final AdminHomeController c;
  @override
  State<_ClientSearch> createState() => _ClientSearchState();
}

class _ClientSearchState extends State<_ClientSearch> {
  Timer? _t;
  String _q = '';
  List<Map>? _rows;
  bool _err = false;

  void _changed(String v) {
    _t?.cancel();
    _q = v.trim();
    if (_q.isEmpty) {
      setState(() => _rows = null);
      return;
    }
    _t = Timer(const Duration(milliseconds: 300), () async {
      final q = _q;
      try {
        final r = await widget.c.searchClients(q);
        if (mounted && q == _q) {
          setState(() {
            _rows = r;
            _err = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _err = true);
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      AppTextField(placeholder: 'Search name, email or phone', prefix: const AppIcon(AppIcons.search, size: 16, color: AppColors.muted), autofocus: true, onChanged: _changed),
      if (_err)
        Text('Could not search right now. Try again.', style: AppText.cap)
      else if (rows == null)
        Text('Type a name to find a client.', style: AppText.cap)
      else if (rows.isEmpty)
        Text('No client matches "$_q".', style: AppText.cap)
      else
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 2, children: [
          for (final r in rows)
            Hover(
              onTap: () => Navigator.of(context).pop('${r['id']}'),
              builder: (_, h, _) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(color: h ? AppColors.hover : null, borderRadius: AppRadius.all(AppRadius.item)),
                child: Row(spacing: 10, children: [
                  _Av('${r['full_name']}', '${r['initials'] ?? ''}', '${r['avatar_color'] ?? 'c1'}'),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                      Text('${r['full_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle),
                      Text(
                        [if ((r['trainer'] as Map?)?['full_name'] != null) '${(r['trainer'] as Map)['full_name']}', '${r['email'] ?? r['phone'] ?? ''}']
                            .where((s) => s.isNotEmpty)
                            .join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.rowSub,
                      ),
                    ]),
                  ),
                  if (r['status'] != 'active') AppBadge(switch (r['status']) { 'pending' => 'Pending', 'paused' => 'Paused', _ => 'Inactive' }, plain: true),
                ]),
              ),
            ),
        ]),
    ]);
  }
}
