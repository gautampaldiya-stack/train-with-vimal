import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
import 'dashboard_model.dart';
import 'dashboard_parts.dart';

/// Trainer Dashboard (boards `TrainerDashboard` and `TrainerDashboardMobile`): stats, today's sessions,
/// clients who need you, check-ins to review, this week. Phone = the blue hero with the stats strip over its edge.
class TrainerDashboardScreen extends StatefulWidget {
  const TrainerDashboardScreen({super.key});
  @override
  State<TrainerDashboardScreen> createState() => _TrainerDashboardScreenState();
}

class _TrainerDashboardScreenState extends State<TrainerDashboardScreen> {
  final c = TrainerHomeController();
  String _kind = 'all';
  bool _allNeed = false;

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

  void _fail(Object e) => showToast(context, e is ApiError ? e.message : 'Something went wrong', sub: 'Try again in a moment.');

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
          return context.isPhone ? _phone(d) : _web(d);
        },
      );

  // ─────────────────────────────── Layouts

  Widget _web(TrainerHome d) => StaffPage(
        onRefresh: c.load,
        header: PageTop(title: d.greeting, sub: d.subline, actions: [
          Builder(builder: (b) => AppIconButton(AppIcons.bell, tooltip: 'Notifications', dot: d.unread > 0, onPressed: () => _notes(b, d))),
          AppButton.primary('New session', icon: AppIcons.plus, iconOnly: compactTop(context), onPressed: () => _newSession(d)),
        ]),
        children: [
          _webStats(d),
          LayoutBuilder(builder: (context, box) {
            final left = [_today(d), _need(d), _week(d)], right = [_checkins(d), _activity(d)];
            if (box.maxWidth < 640) return Column(spacing: 16, crossAxisAlignment: CrossAxisAlignment.stretch, children: [...left, ...right]);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
              Expanded(flex: 14, child: Column(spacing: 16, crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
              Expanded(flex: 10, child: Column(spacing: 16, crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
            ]);
          }),
        ],
      );

  /// Phone: the hero runs under the status bar; the stats strip overlaps its bottom edge by 36.
  Widget _phone(TrainerHome d) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: RefreshIndicator(
          onRefresh: c.load,
          color: AppColors.accent,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _hero(d),
              Transform.translate(
                offset: const Offset(0, -36),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
                    _strip(d),
                    _today(d, phone: true),
                    _need(d),
                    _checkins(d),
                    _activity(d),
                    _week(d),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      );

  Widget _hero(TrainerHome d) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.fromLTRB(18, top, 18, 50),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment(-0.35, -1), end: Alignment(0.35, 1), colors: AppColors.homeHero, stops: [0, .55, 1]),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 44,
          child: Row(spacing: 8, children: [
            Expanded(
              child: Text('${d.date} · Trainer workspace', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.homeHeroSub)),
            ),
            Builder(builder: (b) => _HeroButton(AppIcons.bell, label: 'Notifications', dot: d.unread > 0, onTap: () => _notes(b, d))),
            _HeroButton(AppIcons.plus, label: 'New session', onTap: () => _newSession(d)),
            Semantics(
              label: 'My profile',
              button: true,
              child: Hover(
                onTap: () => context.go('/me'),
                builder: (_, _, _) => Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle),
                  child: Text(Services.session.me?.initials ?? '', style: AppText.s(12.5, W.w8, color: AppColors.accent)),
                ),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 8, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.greeting, style: AppText.s(24, W.w8, ls: -0.48, color: AppColors.white, h: 1.25)),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(d.subline, style: AppText.s(12.5, W.w4, color: AppColors.homeHeroSub, h: 1.45)),
                ),
              ]),
            ),
            // 124 × 104 picture with margin 0 -6 -10 0, like the client hero.
            SizedBox(
              width: 118,
              height: 94,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxWidth: 124,
                maxHeight: 104,
                child: SvgPicture.asset('assets/ill/trainer_hero.svg', width: 124, height: 104, fit: BoxFit.contain),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ─────────────────────────────── Stats

  static const _statIcons = {'clients': AppIcons.usersAlt, 'checkins': AppIcons.clipboardShort, 'workouts': AppIcons.dumbbell, 'reply': AppIcons.clock};

  /// `.stats`: content-wide cards (80 high, gap 10) that scroll sideways when the panel is narrow.
  /// `.stats`: 4 equal cards in a row (2 × 2 under 760 wide). Height follows the content (at least 80)
  /// so the number never gets clipped.
  Widget _webStats(TrainerHome d) => LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth < 760 ? 2 : 4;
        final w = (box.maxWidth - 12 * (cols - 1)) / cols;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final s in d.stats)
            Container(
              width: w,
              constraints: const BoxConstraints(minHeight: 80),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: AppColors.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 8, children: [
                Row(spacing: 8, children: [
                  IconTile(_statIcons[s.key] ?? AppIcons.info, radius: 8),
                  Expanded(child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.muted))),
                ]),
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 10, children: [
                  Text(s.value, style: AppText.stat),
                  if (s.delta.isNotEmpty)
                    Expanded(
                      child: Text(s.delta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.s(12, W.w7, color: s.tone == 'up' ? AppColors.okText : (s.tone == 'down' ? AppColors.badText : AppColors.text))),
                    ),
                ]),
              ]),
            ),
        ]);
      });

  /// Phone `.th-st`: one white strip of 4 cells (number 16/800, label 10.5/600) with a soft shadow.
  Widget _strip(TrainerHome d) => Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppRadius.all(AppRadius.card),
          border: Border.all(color: AppColors.line),
          boxShadow: const [BoxShadow(color: AppColors.weekShadow, blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, s) in d.stats.indexed)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 9),
                  decoration: BoxDecoration(border: i == 0 ? null : const Border(left: BorderSide(color: AppColors.line))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                    Text(s.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(16, W.w8, h: 1.2, tabular: true)),
                    Text(s.label, style: AppText.s(10.5, W.w6, color: AppColors.muted, h: 1.25)),
                  ]),
                ),
              ),
          ]),
        ),
      );

  // ─────────────────────────────── Today

  Widget _today(TrainerHome d, {bool phone = false}) {
    final left = d.today.where((s) => s.status == 'booked').length;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader('Today',
            padding: _hPad,
            count: Text(left > 0 ? '$left left' : 'All done', style: AppText.cap),
            action: _Link('Calendar', () => context.go('/calendar'))),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
          child: d.today.isEmpty
              ? Padding(padding: const EdgeInsets.fromLTRB(12, 14, 12, 14), child: Text('No sessions left today.', style: AppText.cap))
              : Column(spacing: 4, crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final s in d.today) _session(s, phone)]),
        ),
      ]),
    );
  }

  EdgeInsets get _hPad => context.isPhone ? const EdgeInsets.fromLTRB(16, 16, 16, 8) : const EdgeInsets.fromLTRB(20, 16, 20, 8);

  Widget _session(TdSession s, bool phone) {
    final past = s.status != 'booked';
    final now = s.next && !past;
    final time = Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
      Text(s.time, style: AppText.s(14, W.w8, color: now ? AppColors.accentText : (past ? AppColors.muted : AppColors.text), tabular: true)),
      Text('${s.minutes} min', style: AppText.s(11.5, W.w5, color: AppColors.muted)),
    ]);
    final where = Row(spacing: 5, children: [
      AppIcon(s.isCall ? AppIcons.video : AppIcons.pinAlt, size: 13, color: AppColors.muted),
      Flexible(child: Text(s.what, style: AppText.rowSub, maxLines: phone ? 2 : 1, overflow: TextOverflow.ellipsis)),
    ]);
    final name = Text(s.client.name, style: AppText.s(13.5, W.w7, color: past ? AppColors.muted : AppColors.text), maxLines: 1, overflow: TextOverflow.ellipsis);
    final status = switch (s.status) {
      'done' => const AppBadge('Done', tone: Tone.ok),
      'missed' => const AppBadge('Missed', tone: Tone.bad),
      _ => null,
    };
    final menu = Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'More actions', small: true, ghost: true, fill: true, onPressed: () => _sessionMenu(b, s)));
    final next = now && s.inText.isNotEmpty ? AppBadge(s.inText, tone: Tone.info) : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: now ? AppColors.hover : null, borderRadius: AppRadius.all(AppRadius.item)),
      child: phone
          ? Row(spacing: 10, children: [
              SizedBox(width: 44, child: time),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                  name,
                  where,
                  if (next != null) Padding(padding: const EdgeInsets.only(top: 2), child: next),
                ]),
              ),
              ?status,
              SizedBox(width: 28, child: menu),
            ])
          : Row(spacing: 10, children: [
              SizedBox(width: 52, child: time),
              _Av(s.client),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [name, where])),
              ?status,
              ?next,
              menu,
            ]),
    );
  }

  void _sessionMenu(BuildContext anchor, TdSession s) => showAppMenu(anchor, width: 210, [
        // Done lives here (Gautam, 18 Oct): the row stays short and the name has room.
        if (s.status == 'booked') MenuEntry('Mark as done', icon: AppIcons.check, onTap: () => c.setStatus(s, 'done').catchError(_fail)),
        if (s.status == 'booked') MenuEntry('Mark as missed', icon: AppIcons.missed, onTap: () => c.setStatus(s, 'missed').catchError(_fail)),
        if (s.status == 'done') MenuEntry('Mark as not done', icon: AppIcons.undo, onTap: () => c.setStatus(s, 'booked').catchError(_fail)),
        MenuEntry('Open client profile', icon: AppIcons.eye, onTap: () => context.go('/clients/${s.client.id}')),
        const MenuEntry.separator(),
        MenuEntry('Cancel session', icon: AppIcons.trash, danger: true, onTap: () => _cancel(s)),
      ]);

  Future<void> _cancel(TdSession s) async {
    try {
      await c.cancel(s);
      if (!mounted) return;
      showToast(context, 'Session cancelled', sub: '${s.client.name} gets a message in the app', action: 'Undo', onAction: () => c.restore(s.id).catchError(_fail));
    } catch (e) {
      _fail(e);
    }
  }

  // ─────────────────────────────── Clients who need you

  static const _kinds = [('all', 'All'), ('miss', 'Missed workouts'), ('log', 'Not logging'), ('end', 'Plan ending'), ('low', 'Feeling low')];
  static const _kindBadge = {'miss': ('Missed workouts', Tone.warn), 'log': ('Not logging', Tone.bad), 'end': ('Plan ending', Tone.info), 'low': ('Feeling low', Tone.neutral)};

  Widget _need(TrainerHome d) {
    final rows = d.need.where((n) => _kind == 'all' || n.kind == _kind).toList();
    final shown = _allNeed ? rows : rows.take(4).toList();
    final phone = context.isPhone;
    final chips = [
      for (final (id, t) in _kinds)
        FilterChipX(t,
            selected: _kind == id,
            count: id == 'all' ? d.need.length : d.need.where((n) => n.kind == id).length,
            onTap: () => setState(() {
                  _kind = id;
                  _allNeed = false;
                })),
    ];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader('Clients who need you', padding: _hPad, count: AppCount(d.need.length), action: Text('Only your clients', style: AppText.cap)),
        Padding(
          padding: EdgeInsets.fromLTRB(phone ? 16 : 20, 2, phone ? 0 : 20, 8),
          // One line that scrolls sideways on every width (Gautam, 18 Oct), never wraps to a second row.
          child: SingleChildScrollView(scrollDirection: Axis.horizontal, padding: EdgeInsets.only(right: phone ? 28 : 0), child: Row(spacing: 6, children: chips)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
            if (rows.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), child: Text('Nobody here right now.', style: AppText.cap)),
            for (final n in shown) _needRow(n),
            if (rows.length > 4)
              Hover(
                onTap: () => setState(() => _allNeed = !_allNeed),
                builder: (_, h, _) => Container(
                  height: 32,
                  margin: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: h ? AppColors.hover : null, borderRadius: AppRadius.all(AppRadius.item)),
                  child: Text(_allNeed ? 'Show less' : 'Show ${rows.length - 4} more', style: AppText.s(13, W.w7, color: AppColors.accentText)),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _needRow(TdNeed n) {
    final (label, tone) = _kindBadge[n.kind] ?? ('', Tone.neutral);
    final profile = '/clients/${n.person.id}';
    final Widget action = switch (n.action) {
      'remind' when n.reminded => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
            const AppIcon(AppIcons.check, size: 14, color: AppColors.muted),
            Text('Reminded', style: AppText.s(12.5, W.w7, color: AppColors.muted)),
          ]),
        ),
      'remind' => AppButton('Remind', icon: AppIcons.bell, size: BtnSize.sm, onPressed: () => _remind(n)),
      'plan' => AppButton('Plan next', icon: AppIcons.calendarAlt, size: BtnSize.sm, onPressed: () => context.go(profile)),
      _ => AppButton('Open', icon: AppIcons.eye, size: BtnSize.sm, onPressed: () => context.go(profile)),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(spacing: context.isPhone ? 10 : 12, children: [
        _Av(n.person),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Row(spacing: 8, children: [
              Flexible(child: _NameLink(n.person.name, () => context.go(profile))),
              AppBadge(label, tone: tone, plain: true),
            ]),
            Text(n.why, style: AppText.rowSub),
          ]),
        ),
        action,
      ]),
    );
  }

  void _remind(TdNeed n) {
    c.remind(n);
    showToast(context, 'Reminder sent to ${n.person.first}', sub: 'Push and WhatsApp', action: 'Undo', onAction: () => c.undoRemind(n));
  }

  // ─────────────────────────────── Check-ins to review

  Widget _checkins(TrainerHome d) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHeader('Check-ins to review',
              padding: _hPad, count: d.checkinsTotal == 0 ? null : AppCount(d.checkinsTotal), action: _Link('View all', () => context.go('/checkins'))),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
            child: d.checkins.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                    child: Row(spacing: 12, children: [
                      const AppIcon(AppIcons.checkCircle, size: 22, color: AppColors.tdOkIcon),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                          Text('All check-ins reviewed', style: AppText.s(13.5, W.w7)),
                          Text('New ones show up here as clients send them.', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
                        ]),
                      ),
                    ]),
                  )
                : Column(spacing: 4, crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final r in d.checkins) _ciRow(r)]),
          ),
        ]),
      );

  Widget _ciRow(TdCheckin r) => Hover(
        onTap: () => _review(r),
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: h ? AppColors.hover : null, borderRadius: AppRadius.all(AppRadius.item)),
          child: Row(spacing: context.isPhone ? 10 : 12, children: [
            _Av(r.client),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text.rich(
                  TextSpan(text: r.client.name, style: AppText.rowTitle, children: [
                    TextSpan(text: ' · ${r.kind}', style: AppText.s(13.5, W.w5, color: AppColors.muted)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(r.line, style: AppText.rowSub, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            AppBadge(r.age, tone: switch (r.tone) { 'bad' => Tone.bad, 'warn' => Tone.warn, _ => Tone.neutral }, plain: true),
            const AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.muted),
          ]),
        ),
      );

  Future<void> _review(TdCheckin r) async {
    final res = await showReviewDrawer(context, c, r);
    if (res == null || !mounted) return;
    if (res.profile) {
      await Future.delayed(const Duration(milliseconds: 260)); // let the drawer finish closing
      if (mounted) context.go('/clients/${r.client.id}');
      return;
    }
    showToast(context, '${r.client.first}’s check-in reviewed',
        sub: res.replied ? 'Your reply was sent' : 'Moved out of your list', action: 'Undo', onAction: () => c.unreview(r.id).catchError(_fail));
  }

  // ─────────────────────────────── This week

  Widget _week(TrainerHome d) {
    final phone = context.isPhone;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader('This week', padding: _hPad, sub: d.weekRange, action: _Link('My profile', () => context.go('/me'))),
        Padding(
          padding: EdgeInsets.fromLTRB(phone ? 16 : 20, 0, phone ? 16 : 20, 14),
          child: LayoutBuilder(
            builder: (context, box) {
              final w = (box.maxWidth - 20) / 2;
              return Wrap(spacing: 20, children: [
                for (final (k, v) in d.week)
                  Container(
                    width: w,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
                      Text(k, style: AppText.s(12, W.w6, color: AppColors.muted)),
                      Text(v, style: AppText.s(13.5, W.w7), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }

  // ─────────────────────────────── Activity

  /// What the trainer and their clients did lately (`.tp-tl` timeline): a kind dot, who + what, the
  /// client and item under it, and when. "Show more" loads the next page in place.
  Widget _activity(TrainerHome d) {
    final phone = context.isPhone;
    final rows = d.activity;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader('Activity', padding: _hPad, sub: 'You and your clients', action: _Link('View all', () => context.go('/me/activity'))),
        if (rows.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(phone ? 16 : 20, 0, phone ? 16 : 20, 16),
            child: Text('Nothing yet. Check-ins, workouts and sessions show up here.', style: AppText.s(13, W.w5, color: AppColors.muted)),
          )
        else
          Padding(
            padding: EdgeInsets.fromLTRB(phone ? 16 : 20, 0, phone ? 16 : 20, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, a) in rows.indexed) _ActRow(a, last: i == rows.length - 1, onClient: a.client.isEmpty ? null : () => context.go('/clients/${a.client}')),
            ]),
          ),
      ]),
    );
  }

  // ─────────────────────────────── Overlays

  void _notes(BuildContext anchor, TrainerHome d) => showNotesDropdown(anchor, c, onOpen: (n) {
        final id = n.route.startsWith('/checkins/') ? n.route.split('/').last : null;
        final ci = id == null ? null : d.checkins.where((x) => x.id == id).firstOrNull;
        if (ci != null) {
          _review(ci);
        } else if (n.route.isNotEmpty) {
          context.go(n.route);
        }
      });

  Future<void> _newSession(TrainerHome d) async {
    final r = await showNewSessionModal(context, c);
    if (r == null || !mounted) return;
    showToast(context, 'Session added', sub: '${r.client} · ${r.when}', action: 'Undo', onAction: () => c.removeSession(r.id).catchError(_fail));
  }
}

// ─────────────────────────────── Small pieces

/// `.av.sm` 24 with the board colour class.
class _Av extends StatelessWidget {
  const _Av(this.p);
  final TdPerson p;
  @override
  Widget build(BuildContext context) => AppAvatar(p.name, size: 24, colors: AppColors.avatarCode(p.color), initials: p.initials.isEmpty ? null : p.initials);
}

/// `.tp-tl-row`: 28 round kind dot with a line down to the next row, text, time on the right.
class _ActRow extends StatelessWidget {
  const _ActRow(this.a, {required this.last, this.onClient});
  final TdActivity a;
  final bool last;
  final VoidCallback? onClient;

  static const _tones = {
    'ci': (AppColors.tlCiBg, AppColors.tlCiFg),
    'pl': (AppColors.tlPlBg, AppColors.tlPlFg),
    'cl': (AppColors.tlClBg, AppColors.tlClFg),
    'ch': (AppColors.tlChBg, AppColors.tlChFg),
  };
  static final _icons = {
    'checkin': AppIcons.clipboard,
    'plan': AppIcons.edit,
    'workout': AppIcons.dumbbell,
    'meal': AppIcons.food,
    'body': AppIcons.scale,
    'session': AppIcons.calendar,
    'client': AppIcons.usersAlt,
  };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _tones[a.tone] ?? (AppColors.sub, AppColors.muted);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        Column(children: [
          const SizedBox(height: 5),
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: AppIcon(_icons[a.kind] ?? AppIcons.bolt, size: 14, color: fg),
          ),
          if (!last) Expanded(child: Container(width: 1.5, margin: const EdgeInsets.only(top: 4), color: AppColors.line)),
        ]),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 9, 0, 13),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: a.who, style: AppText.s(13.5, W.w6, color: AppColors.text)),
                  TextSpan(text: ' ${a.what}'),
                ]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.s(13.5, W.w4, color: AppColors.text2),
              ),
              if (a.detail.isNotEmpty)
                onClient == null
                    ? Text(a.detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted))
                    : Hover(
                        onTap: onClient,
                        builder: (_, h, _) => Text(a.detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.s(12.5, W.w5, color: h ? AppColors.accentText : AppColors.muted)),
                      ),
            ]),
          ),
        ),
        Padding(padding: const EdgeInsets.only(top: 10), child: Text(a.when, style: AppText.s(12, W.w5, color: AppColors.muted))),
      ]),
    );
  }
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

class _HeroButton extends StatelessWidget {
  const _HeroButton(this.icon, {required this.label, required this.onTap, this.dot = false});
  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  final bool dot;
  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        button: true,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: h ? AppColors.homeHeroSub.withValues(alpha: .3) : AppColors.homeHeroBtn, borderRadius: BorderRadius.circular(12)),
            child: Stack(alignment: Alignment.center, children: [
              AppIcon(icon, size: 18, color: AppColors.white),
              if (dot)
                Positioned(
                  top: 7,
                  right: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: AppColors.red, shape: BoxShape.circle, border: Border.all(color: AppColors.homeHeroDotRing, width: 2)),
                  ),
                ),
            ]),
          ),
        ),
      );
}
