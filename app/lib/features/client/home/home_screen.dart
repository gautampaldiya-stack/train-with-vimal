import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/unread.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../train/workout_model.dart';
import '../progress/progress_parts.dart';
import 'home_model.dart';
import 'home_parts.dart';
import 'home_sheets.dart';
import '../../../core/widgets/tooltip.dart';

/// Client Home (boards `ClientHome` phone and `ClientHomeWeb`). Phone: one column of cards over
/// the bottom tabs. Wider: the web panel with two columns (one column while the panel is narrow).
class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});
  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  final c = HomeController();
  int? _day; // picked day in the week strip; null = today

  /// Edit home (D-87): the card order being edited, null outside edit mode. Cards move only in edit mode.
  List<String>? _edit;

  @override
  void initState() {
    super.initState();
    c.start();
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
          final d = c.data;
          if (d == null) {
            final e = c.error;
            return Center(
              child: e == null
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, spacing: 10, children: [
                        Text(e.offline ? 'You are offline' : 'Could not load this', style: AppText.s(15, W.w7)),
                        Text(e.offline ? 'Connect to the internet to load your day' : e.message, textAlign: TextAlign.center, style: AppText.s(13, W.w4, color: AppColors.muted)),
                        CaButton('Try again', kind: CaBtnKind.out, expand: false, onPressed: c.load),
                      ]),
                    ),
            );
          }
          return context.isPhone ? _phone(d) : _web(d);
        },
      );

  // ─────────────────────────────── Layouts

  /// Phone = board `ClientHomeHero` (Gautam picked the hero, 2026-10-16): the blue hero runs under the status
  /// bar and the week strip overlaps its bottom edge by 34.
  Widget _phone(HomeData d) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: RefreshIndicator(
          onRefresh: c.load,
          color: AppColors.accent,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _hero(d),
              Transform.translate(
                offset: const Offset(0, -34),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
                    DecoratedBox(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), boxShadow: const [BoxShadow(color: AppColors.weekShadow, blurRadius: 18, offset: Offset(0, 6))]),
                      child: _week(d, web: false),
                    ),
                    ..._phoneCards(d),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      );

  Widget _hero(HomeData d) {
    final top = MediaQuery.paddingOf(context).top;
    final today = d.todayIndex >= 0 && d.todayIndex < d.strip.length ? d.strip[d.todayIndex] : null;
    final planned = d.strip.where((x) => !x.rest).length;
    final done = d.strip.where((x) => !x.rest && x.done).length;
    final line1 = d.strip.isEmpty
        ? 'Your coach is setting up your plan.'
        : today == null || today.rest
            ? 'Rest day today.'
            : '${today.name.isEmpty ? (today.cardio ? 'Cardio' : 'Strength') : today.name} today.';
    final line2 = planned == 0 ? '' : '\n$done of $planned workout${planned == 1 ? '' : 's'} done this week.';
    return Container(
      padding: EdgeInsets.fromLTRB(18, top + 4, 18, 46),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment(-0.35, -1), end: Alignment(0.35, 1), colors: AppColors.homeHero, stops: [0, .55, 1]),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 44,
          child: Row(spacing: 8, children: [
            Expanded(
              child: CutText('${dayShort(d.date)}${d.week != null && d.weeks != null ? ' · Week ${d.week} of ${d.weeks}' : ''}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.homeHeroSub)),
            ),
            Semantics(
              label: 'Notifications',
              button: true,
              child: Hover(
                onTap: () => showNoticesSheet(context, c),
                builder: (_, h, _) => Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: h ? AppColors.homeHeroSub.withValues(alpha: .3) : AppColors.homeHeroBtn, borderRadius: BorderRadius.circular(12)),
                  child: UnreadCount(
                    fallback: d.unread,
                    builder: (_, n) => Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
                      const AppIcon(AppIcons.bell, size: 18, color: AppColors.white),
                      if (n > 0) Positioned(top: -2, right: -2, child: BellCount(n, ring: AppColors.homeHeroDotRing)),
                    ]),
                  ),
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
                CutText('Hey ${d.firstName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(28, W.w8, ls: -0.56, color: AppColors.white, h: 1.2)),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('$line1$line2', style: AppText.s(13, W.w4, color: AppColors.homeHeroSub, h: 1.45)),
                ),
              ]),
            ),
            // 128 × 116 picture with margin 0 -6 -10 0: it takes 122 of the row and hangs 6 past the edge, 10 below.
            SizedBox(
              width: 122,
              height: 106,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxWidth: 128,
                maxHeight: 116,
                child: SvgPicture.asset('assets/ill/hero_run.svg', width: 128, height: 116, fit: BoxFit.contain),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  List<Widget> _phoneCards(HomeData d) => _edit != null
      ? [_editor(d, web: false)]
      : [
          for (final k in d.layout) ?_card(k, d, web: false),
          _habits(d),
          if (_dueSupps(d).isNotEmpty) _supps(d),
          ?_coach(d),
          if (d.coming.isNotEmpty) ...[const ChSection('Coming up'), _coming(d)],
          _editBtn(d),
        ];

  // ─────────────────────────────── Edit home (D-87): the cards in the client's order, drag to move

  /// One card of the layout, or null when it is off for this client (no daily form, or no rest running on web).
  /// The Rest timer card is web only.
  Widget? _card(String k, HomeData d, {required bool web, bool editing = false}) => switch (k) {
        'workout' => _workout(d),
        'checkin' => d.checkin == null ? null : _checkinCard(d),
        'food' => _food(d),
        'progress' => _progressCard(d),
        'adherence' => _adherenceCard(d),
        'water' => _waterCard(d),
        'rest_timer' => !web ? null : (editing ? _restCard(null) : _liveRest()),
        _ => null,
      };

  /// The cards Edit home can show on this device (no Rest timer on the phone, no Check-in without a daily form).
  bool _fits(String k, HomeData d, bool web) => (k != 'rest_timer' || web) && (k != 'checkin' || d.checkin != null);

  Widget _editBtn(HomeData d) => Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: CaButton('Edit home', kind: CaBtnKind.out, expand: false, icon: AppIcons.edit, onPressed: () => setState(() => _edit = [...d.layout])),
        ),
      );

  Widget _editor(HomeData d, {required bool web}) {
    final order = _edit!.where((k) => _fits(k, d, web)).toList();
    final off = [for (final k in homeCards.keys) if (!_edit!.contains(k) && _fits(k, d, web)) k];
    List<Widget> actions() => [
          CaButton('Cancel', kind: CaBtnKind.out, expand: false, onPressed: () => setState(() => _edit = null)),
          CaButton('Done', expand: false, onPressed: () {
            final l = _edit!;
            setState(() => _edit = null);
            c.saveLayout(l);
            showToast(context, 'Home saved', sub: 'Your cards show in this order on every device', kind: ToastKind.ok);
          }),
        ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        child: Row(spacing: 8, children: [
          Expanded(child: ChTwoLine('Edit home', 'Drag a card to move it, ✕ to remove it')),
          ...actions(),
        ]),
      ),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
        onReorderItem: (a, to) => setState(() {
          final k = order[a];
          final l = [...order]..removeAt(a)..insert(to, k);
          _edit = [...l, ..._edit!.where((x) => !l.contains(x))];
        }),
        children: [
          for (final (i, k) in order.indexed)
            Padding(
              key: ValueKey(k),
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.accent, width: 1.5)),
                padding: const EdgeInsets.all(4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: const MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Padding(padding: EdgeInsets.all(8), child: AppIcon(AppIcons.drag, size: 18, color: AppColors.muted)),
                      ),
                    ),
                    Expanded(child: Text(homeCards[k]!, style: AppText.s(13, W.w7, color: AppColors.text2))),
                    CaIconBtn(AppIcons.close, tooltip: 'Remove ${homeCards[k]}', onTap: () => setState(() => _edit!.remove(k))),
                  ]),
                  IgnorePointer(child: Opacity(opacity: .75, child: _card(k, d, web: web, editing: true) ?? const SizedBox.shrink())),
                ]),
              ),
            ),
        ],
      ),
      if (off.isNotEmpty)
        Builder(
          builder: (bc) => CaButton('Add card', kind: CaBtnKind.out, icon: AppIcons.plus, onPressed: () => showActionSheet(bc, title: 'Add card', [
            for (final k in off) MenuEntry(homeCards[k]!, icon: AppIcons.plus, onTap: () => setState(() => _edit!.add(k))),
          ])),
        ),
      // Done and Cancel at the end too, so a long list needs no scroll back up.
      Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: actions()),
    ]);
  }

  // ─────────────────────────────── Check-in, Progress summary, Weekly adherence, Rest timer (D-87)

  Widget _checkinCard(HomeData d) {
    final ci = d.checkin!;
    return ChCard(children: [
      ChHead(
        lead: ChIcon(AppIcons.clipboard, tone: ci.sent ? ChTone.green : ChTone.amber),
        title: 'Daily check-in',
        sub: ci.sent
            ? 'Sent ✓${ci.at == null ? '' : ' · ${clock(ci.at!)}'}'
            : 'Not filled yet · ${ci.questions} question${ci.questions == 1 ? '' : 's'}${ci.due.isEmpty ? '' : ' · by ${ci.due}'}',
      ),
      if (!ci.sent) CaButton('Fill now', icon: AppIcons.edit, onPressed: () => context.go('/checkins/daily')),
    ]);
  }

  String _sign(num v, String unit) => '${v > 0 ? '+' : v < 0 ? '−' : '±'}${_one(v.abs().toDouble())}$unit';
  String _one(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
  double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  String _since(dynamic v) => v == null ? 'start' : DateFormat('d MMM').format(DateTime.parse('$v'));

  int _ptab = 0;

  /// Progress card (D-87): tabs Weight · Body fat · Muscle · Strength, each since the start, with where it comes from.
  Widget _progressCard(HomeData d) {
    const tabs = ['Weight', 'Body fat', 'Muscle', 'Strength'];
    Widget big(String v, String? change, bool? good) => Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 8, children: [
          Text(v, style: AppText.s(28, W.w8, ls: -0.5)),
          if (change != null)
            Flexible(child: Text(change, style: AppText.s(13, W.w7, color: good == null ? AppColors.muted : (good ? AppColors.okText : AppColors.badText)))),
        ]);
    Widget line(String t) => Text(t, style: AppText.s(13, W.w4, color: AppColors.text2));
    Widget from(String t) => Text(t, style: AppText.s(11.5, W.w4, color: AppColors.muted));
    bool? good(double ch, {required bool up}) => ch == 0 ? null : (ch > 0) == up;

    final List<Widget> body;
    switch (_ptab) {
      case 0:
        final w = d.summary('weight');
        if (w == null) {
          body = [line('No weigh-in yet'), from('Log your weight in the daily check-in or Progress')];
        } else {
          final now = _d(w['now']), start = w['start'] == null ? null : _d(w['start']), goal = w['goal'] == null ? null : _d(w['goal']);
          final ch = w['change'] == null ? null : _d(w['change']);
          final down = goal == null || start == null || goal < start;
          body = [
            big('${_one(now)} kg', ch == null ? null : '${_sign(ch, ' kg')} since start', ch == null ? null : good(ch, up: !down)),
            if (start != null) line('Start ${_one(start)} kg${goal == null ? '' : ' · Goal ${_one(goal)} kg · ${_one((now - goal).abs())} kg to go'}'),
            from('From your weigh-ins (check-ins and Progress)'),
          ];
        }
      case 1:
        final f = d.summary('body_fat');
        if (f == null) {
          body = [line('Not measured yet'), from('Log body fat in Progress → Measurements')];
        } else {
          final ch = _d(f['change']);
          body = [
            big('${_one(_d(f['now']))}%', '${_sign(ch, '%')} since ${_since(f['since'])}', good(ch, up: false)),
            line('Start ${_one(_d(f['start']))}%${f['fat_kg'] == null ? '' : ' · Fat mass ${_one(_d(f['fat_kg']))} kg${f['fat_kg_change'] == null ? '' : ' (${_sign(_d(f['fat_kg_change']), ' kg')})'}'}'),
            from('From your body measurements; fat mass = weight × body fat %'),
          ];
        }
      case 2:
        final m = d.summary('muscle');
        if (m == null) {
          body = [line('Not measured yet'), from('Needs muscle mass or body fat in Progress → Measurements')];
        } else {
          final ch = _d(m['change']);
          final est = m['estimated'] == true;
          body = [
            big('${_one(_d(m['now']))} kg', '${_sign(ch, ' kg')} since ${_since(m['since'])}', good(ch, up: true)),
            line('${est ? 'Lean mass' : 'Muscle mass'} · start ${_one(_d(m['start']))} kg'),
            from(est ? 'Worked out from weight and body fat (lean mass = weight − fat). Log muscle mass for the exact number.' : 'From your muscle mass measurements'),
          ];
        }
      default:
        final s = d.summary('strength');
        if (s == null) {
          body = [line('Shows after 2 workouts with weights'), from('From the sets you log in your workouts')];
        } else {
          final pct = _d(s['pct']);
          final lifts = [for (final l in (s['lifts'] as List? ?? const [])) (l as Map).cast<String, dynamic>()];
          body = [
            big(_sign(pct, '%'), 'overall since ${_since(s['since'])}', good(pct, up: true)),
            line('Average of ${s['exercises']} exercise${s['exercises'] == 1 ? '' : 's'}'),
            for (final l in lifts.take(3))
              Row(spacing: 8, children: [
                Expanded(child: CutText('${l['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w6))),
                Text('${_one(_d(l['start']))} → ${_one(_d(l['now']))} kg', style: AppText.s(12.5, W.w4, color: AppColors.text2)),
                SizedBox(width: 56, child: Text(_sign(_d(l['pct']), '%'), textAlign: TextAlign.right, style: AppText.s(12.5, W.w7, color: _d(l['pct']) > 0 ? AppColors.okText : AppColors.muted))),
              ]),
            from('Best estimated 1-rep max (Epley) of the first day vs the latest day, each exercise lifted on 2+ days'),
          ];
        }
    }
    return ChCard(children: [
      ChHead(
        lead: const ChIcon(AppIcons.trendUp, tone: ChTone.blue),
        title: 'Progress',
        sub: 'Since your start date',
        action: chSm('Open', () => context.go('/progress')),
      ),
      PxTabs(labels: tabs, index: _ptab, fit: false, onPick: (i) => setState(() => _ptab = i)),
      Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: body),
    ]);
  }

  Widget _adherenceCard(HomeData d) {
    final a = d.adherence;
    return ChCard(children: [
      ChHead(lead: const ChIcon(AppIcons.checkCircle, tone: ChTone.green), title: 'Weekly adherence', sub: 'Progress of this week till now'),
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 8, children: [
        Text('${a.pct}%', style: AppText.s(28, W.w8, ls: -0.5)),
        Flexible(child: Text('${a.done} of ${a.days} day${a.days == 1 ? '' : 's'} checked in', style: AppText.s(13, W.w6, color: AppColors.muted))),
      ]),
      ChBar(a.days == 0 ? 0 : a.done / a.days, color: AppColors.okSolid),
      Text('From your daily check-ins, Monday to today', style: AppText.s(11.5, W.w4, color: AppColors.muted)),
    ]);
  }

  /// Web only: shows while a rest runs in the workout (it hides when the rest is over).
  Widget _liveRest() => ValueListenableBuilder(
        valueListenable: WorkoutController.liveRest,
        builder: (_, r, _) => r == null ? const SizedBox.shrink() : _RestTicker(ends: r.ends, builder: (left) => left <= 0 ? const SizedBox.shrink() : _restCard((left, r.next, r.route))),
      );

  Widget _restCard((int, String, String)? r) => ChCard(children: [
        ChHead(
          lead: const ChIcon(AppIcons.clock, tone: ChTone.blue),
          title: 'Rest timer',
          sub: r == null ? 'Shows while a rest is running' : 'Next: ${r.$2}',
          action: r == null ? null : chSm('Back to workout', () => context.go(r.$3)),
        ),
        if (r != null) Text('${r.$1 ~/ 60}:${(r.$1 % 60).toString().padLeft(2, '0')}', style: AppText.s(30, W.w8, ls: -0.6)),
      ]);

  Widget _web(HomeData d) => CaWeb(
        web: true,
        child: RefreshIndicator(
          onRefresh: c.load,
          color: AppColors.accent,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 72),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: LayoutBuilder(builder: (context, box) {
                  if (_edit != null) {
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
                      _top(d, web: true),
                      Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: _editor(d, web: true))),
                    ]);
                  }
                  // The layout cards alternate between the two columns, in the client's order.
                  final cards = [for (final k in d.layout) ?_card(k, d, web: true)];
                  final left = [
                    _week(d, web: true),
                    for (final (i, w) in cards.indexed) if (i.isEven) w,
                    if (d.coming.isNotEmpty) ...[const ChSection('Coming up'), _coming(d)],
                  ];
                  final right = [
                    for (final (i, w) in cards.indexed) if (i.isOdd) w,
                    _habits(d),
                    if (_dueSupps(d).isNotEmpty) _supps(d),
                    ?_coach(d),
                    _editBtn(d),
                  ];
                  final two = box.maxWidth >= 680;
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
                    _top(d, web: true),
                    if (two)
                      Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: left)),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: right)),
                      ])
                    else
                      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
                        _week(d, web: true),
                        ...cards,
                        ...right.skip(cards.length ~/ 2),
                        if (d.coming.isNotEmpty) ...[const ChSection('Coming up'), _coming(d)],
                      ]),
                  ]);
                }),
              ),
            ),
          ),
        ),
      );

  // ─────────────────────────────── Top: date, Hey <name>, bell, avatar

  Widget _top(HomeData d, {required bool web}) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(spacing: 8, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text('${dayShort(d.date)}${d.week != null && d.weeks != null ? ' · Week ${d.week} of ${d.weeks}' : ''}',
                  style: AppText.s(12.5, W.w6, color: AppColors.muted)),
              Text('Hey ${d.firstName}', style: AppText.s(web ? 30 : 26, W.w8, ls: web ? -0.3 : -0.26)),
            ]),
          ),
          UnreadCount(fallback: d.unread, builder: (bell, n) => ChBell(count: n, onTap: () => web ? _notesMenu(bell) : showNoticesSheet(context, c))),
        ]),
      );

  /// Web: the bell opens a 360 wide panel under it (`.cw-notes`), not a sheet.
  Future<void> _notesMenu(BuildContext anchor) async {
    final box = anchor.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final at = box.localToGlobal(Offset.zero, ancestor: overlay);
    final right = overlay.size.width - at.dx - box.size.width;
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Notifications',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 90),
      transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      pageBuilder: (ctx, _, _) => Stack(children: [
        Positioned(
          right: right,
          top: at.dy + 46,
          width: 360,
          child: Material(
            color: Colors.transparent,
            child: ListenableBuilder(
              listenable: c,
              builder: (ctx, _) {
                final d = c.data!;
                return Container(
                  padding: const EdgeInsets.all(6),
                  constraints: BoxConstraints(maxHeight: overlay.size.height - at.dy - 70),
                  decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line), boxShadow: AppShadows.menu),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SizedBox(
                      height: 38,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                        child: Row(children: [
                          Expanded(child: Text('Notifications', style: AppText.s(14, W.w7))),
                          if (d.unread > 0)
                            CaLink('Mark all read', size: 12.5, weight: W.w6, onTap: () {
                              Navigator.of(ctx).pop();
                              c.readAll();
                              showToast(context, 'All notifications read', kind: ToastKind.ok);
                            }),
                        ]),
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                        child: d.notices.isEmpty
                            ? Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text('No notifications yet.', textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)))
                            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                for (final (i, n) in d.notices.indexed)
                                  NoticeRow(n, first: i == 0, onTap: noticeRoute(n) == null ? null : () {
                                    Navigator.of(ctx).pop();
                                    context.go(noticeRoute(n)!);
                                  }),
                              ]),
                      ),
                    ),
                  ]),
                );
              },
            ),
          ),
        ),
      ]),
    );
  }

  // ─────────────────────────────── Week strip

  Widget _week(HomeData d, {required bool web}) => LayoutBuilder(builder: (context, box) {
        // The web strip puts letter, date and mark in one line; a narrow column falls back to the phone's stacked days.
        return _weekStrip(d, web: web && (box.maxWidth - 12) / 7 >= 62);
      });

  Widget _weekStrip(HomeData d, {required bool web}) {
    final sel = _day ?? d.todayIndex;
    return Container(
      padding: EdgeInsets.all(web ? 6 : 8),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Row(spacing: 4, children: [
        for (final (i, day) in d.strip.indexed)
          Expanded(
            child: Semantics(
              button: true,
              selected: i == sel,
              label: dayShort(day.date),
              child: Hover(
                onTap: () => setState(() => _day = i),
                builder: (_, h, _) {
                  final on = i == sel;
                  final past = day.date.isBefore(d.date);
                  final letter = Text(const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][day.date.weekday - 1],
                      style: AppText.s(web ? 12 : 11, W.w6, color: on ? AppColors.daySubOn : AppColors.muted));
                  final num = Text('${day.date.day}', style: AppText.s(web ? 14 : 15, W.w8, color: on ? AppColors.white : AppColors.text));
                  final mark = _dayMark(today: day.today, done: past && day.done || day.today && day.done, rest: day.rest);
                  return Container(
                    padding: web ? const EdgeInsets.symmetric(vertical: 7) : const EdgeInsets.fromLTRB(0, 7, 0, 6),
                    decoration: BoxDecoration(color: on ? AppColors.text : (h ? AppColors.outlineHover : null), borderRadius: BorderRadius.circular(10)),
                    child: web
                        ? Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [letter, num, mark])
                        : Column(spacing: 3, children: [letter, num, mark]),
                  );
                },
              ),
            ),
          ),
      ]),
    );
  }

  Widget _dayMark({required bool today, required bool done, required bool rest}) {
    if (today) {
      return Container(width: 16, height: 16, decoration: BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle, border: Border.all(color: AppColors.accent, width: 2)));
    }
    if (rest) return const DashedCircle();
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: done ? AppColors.okSolid : AppColors.dayOff, shape: BoxShape.circle),
      child: done ? const AppIcon(AppIcons.check, size: 11, color: AppColors.white, stroke: 2.6) : null,
    );
  }

  // ─────────────────────────────── Workout card

  Widget _workout(HomeData d) {
    if (d.strip.isEmpty) {
      return ChCard(children: [
        ChHead(lead: const ChIcon(AppIcons.dumbbell, tone: ChTone.green), title: 'Workout', sub: 'Your coach is setting up your plan'),
      ]);
    }
    final sel = _day ?? d.todayIndex;
    final day = d.strip[sel < 0 ? 0 : sel];
    final today = day.today, past = day.date.isBefore(d.date), future = !today && !past;
    final s = d.session;
    final sessionHere = s != null && DateUtils.isSameDay(s.start, day.date);
    final n = day.exercises.length;
    final kids = <Widget>[];

    // Hero
    final (colors, label, icon) = day.rest
        ? (AppColors.heroGray, 'Rest day', AppIcons.moon)
        : (day.cardio ? AppColors.heroBlue : AppColors.heroGreen, today ? 'Today’s workout' : (past ? 'Workout' : 'Coming workout'), day.cardio ? AppIcons.run : AppIcons.dumbbell);
    final tags = day.rest ? ['No workout', 'Walk', 'Stretch'] : [day.cardio ? 'Cardio' : 'Strength', '$n exercises', '${day.minutes} min'];
    kids.add(Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        border: const Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
        Row(children: [
          AppIcon(icon, size: 15, color: AppColors.text2),
          const SizedBox(width: 6),
          Expanded(child: Text(label.toUpperCase(), style: AppText.s(11.5, W.w8, color: AppColors.text2, ls: .575))),
          Text(dayShort(day.date), style: AppText.s(12.5, W.w7, color: AppColors.muted)),
        ]),
        Text(day.rest ? 'Rest and recover' : day.name, style: AppText.s(22, W.w8, ls: -0.22)),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in tags)
            Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(color: AppColors.white.withValues(alpha: .85), borderRadius: BorderRadius.circular(7), border: Border.all(color: AppColors.line)),
              child: Center(widthFactor: 1, child: Text(t, style: AppText.s(12, W.w7, color: AppColors.text2))),
            ),
        ]),
      ]),
    ));

    final body = <Widget>[];
    if (day.rest) {
      body.add(Padding(
        padding: const EdgeInsets.only(top: 10),
        child: ChNote(
          top: true,
          bg: AppColors.sub,
          fg: AppColors.text2,
          child: Text('Rest helps your muscles grow. A short walk and some stretching is enough.', style: AppText.s(13, W.w4, color: AppColors.text2)),
        ),
      ));
    }
    if (sessionHere) {
      body.add(Padding(
        padding: const EdgeInsets.only(top: 10),
        child: ChNote(
          icon: AppIcons.calendarAlt,
          bg: AppColors.accentSoft,
          fg: AppColors.sessText,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Session with '),
              TextSpan(text: s.coach, style: const TextStyle(fontWeight: W.w7)),
              TextSpan(text: ' · ${clock(s.start)} · ${s.isCall ? 'Video call' : s.place}'),
            ]),
            style: AppText.s(13, W.w4, color: AppColors.sessText),
          ),
        ),
      ));
    }
    if (!day.rest && day.done && (past || today)) {
      body.add(Padding(
        padding: const EdgeInsets.only(top: 10),
        child: ChNote(icon: AppIcons.checkCircle, bg: AppColors.okBg, fg: AppColors.okText, child: Text(day.doneLine, style: AppText.s(13, W.w7, color: AppColors.okText))),
      ));
    } else if (today && !day.rest) {
      // One button (D-87): Continue once a workout has started, else Start opens the logger on today's workout.
      final going = day.inProgress || day.exercisesDone > 0;
      body.add(Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CaButton(going ? 'Continue workout' : 'Start workout', icon: AppIcons.play,
            onPressed: () => context.go(going ? '/train/workout' : '/train/workout?start=${d.dayId ?? ''}')),
      ));
    } else if (future && !day.rest) {
      body.add(Padding(
        padding: const EdgeInsets.only(top: 10),
        child: CaButton('See all exercises', kind: CaBtnKind.out, icon: AppIcons.eye, onPressed: () => showWorkoutPreview(context, day)),
      ));
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ...kids,
        if (body.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body)),
      ]),
    );
  }

  // ─────────────────────────────── Water

  void _water(int delta) {
    final d = c.data!;
    final ml = d.waterMl, goal = d.waterGoal;
    if (delta < 0 && ml <= 0) {
      showToast(context, 'Nothing to remove', sub: 'No water logged yet', kind: ToastKind.info);
      return;
    }
    final now = (ml + delta).clamp(0, 10000);
    final left = goal - now, g = (left / 250).ceil();
    c.addWater(delta);
    if (delta > 0 && ml < goal && now >= goal) {
      showToast(context, 'Water goal complete!', sub: '${litres(now)} today', kind: ToastKind.star);
    } else if (delta > 0 && now > 5000) {
      showToast(context, '${litres(now)} today, that is plenty', sub: 'Slow down: too much water at once is not good for you', kind: ToastKind.warn);
    } else if (left > 0) {
      showToast(context, delta > 0 ? '${litres(left)} to go' : 'Removed 250 ml · ${litres(now)} logged',
          sub: '${glasses(g)} more', kind: delta > 0 ? ToastKind.water : ToastKind.info);
    } else {
      showToast(context, '${litres(now)} today', sub: 'Goal complete', kind: ToastKind.water);
    }
  }

  Widget _waterCard(HomeData d) {
    final ml = d.waterMl, goal = d.waterGoal;
    final gl = (ml / 250).round(), leftG = ((goal - ml) / 250).ceil().clamp(0, 999);
    final bars = (goal / 250).round().clamp(4, 20);
    return ChCard(children: [
      ChHead(
        lead: const ChIcon(AppIcons.water, tone: ChTone.warm),
        title: 'Water',
        sub: ml >= goal ? 'Goal complete · nice work' : '${litres(goal - ml)} to go · ${glasses(leftG)} more',
      ),
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 6, children: [
        Text(litres(ml), style: AppText.s(30, W.w8, ls: -0.6)),
        Flexible(child: Text('/ ${litres(goal)} · ${glasses(gl)}', style: AppText.s(13, W.w6, color: AppColors.muted))),
      ]),
      Pull(
        top: 4,
        child: Row(spacing: 5, children: [
          for (var i = 0; i < bars; i++)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 8,
                decoration: BoxDecoration(color: i < gl ? AppColors.warm : AppColors.barTrack, borderRadius: BorderRadius.circular(8)),
              ),
            ),
        ]),
      ),
      Row(spacing: 8, children: [
        chSm('−250 ml', () => _water(-250)),
        chSm('+250 ml · 1 glass', () => _water(250), kind: CaBtnKind.dark),
      ]),
    ]);
  }

  // ─────────────────────────────── Food

  /// "Ate it" asks first (Phase 3): a meal is logged only on her Yes.
  Future<void> _eat(HomeMeal m) async {
    final ok = await confirmAction(context,
        title: 'Did you eat this?', body: '${m.name} · ${m.foods} · ${inNum(m.kcal)} kcal', confirm: 'Yes, log it', icon: AppIcons.check);
    if (!ok || !mounted) return;
    c.setMeal(m, true);
    showToast(context, '${m.name} logged', sub: '${m.foods} · ${inNum(m.kcal)} kcal', kind: ToastKind.ok, action: 'Undo', onAction: () => c.setMeal(m, false));
  }

  Widget _food(HomeData d) {
    final t = d.target ?? const [0, 0, 0, 0];
    final e = d.eaten;
    final next = d.meals.where((m) => m.open).firstOrNull;
    final hasPlan = d.target != null && t[0] > 0;
    return ChCard(children: [
      ChHead(
        lead: const ChIcon(AppIcons.food, tone: ChTone.green),
        title: 'Food',
        sub: hasPlan ? '${inNum(t[0])} kcal plan${d.goal.isEmpty ? '' : ' · ${d.goal}'}' : 'No meal plan yet',
        action: chSm('Log food', () => showLogFoodSheet(context, c, _eat), icon: AppIcons.plus),
      ),
      Row(spacing: 16, children: [
        ChRing(ratio: t[0] > 0 ? e[0] / t[0] : 0, value: inNum((t[0] - e[0]).clamp(0, 99999)), label: 'kcal left'),
        Expanded(
          child: Column(spacing: 9, children: [
            for (final (i, (name, color)) in const [('Protein', AppColors.accent), ('Carbs', AppColors.carbs), ('Fat', AppColors.fat)].indexed)
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(name, style: AppText.s(12.5, W.w6, color: AppColors.muted))),
                  Text('${e[i + 1].round()} / ${t[i + 1].round()} g', style: AppText.s(12.5, W.w7)),
                ]),
                const SizedBox(height: 4),
                ChBar(t[i + 1] > 0 ? e[i + 1] / t[i + 1] : 0, color: color),
              ]),
          ]),
        ),
      ]),
      if (next != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: AppColors.nextBg, borderRadius: BorderRadius.circular(10)),
          child: Row(spacing: 10, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Up next · ${next.name}, ${mealTime(next.time)}', style: AppText.s(12, W.w6, color: AppColors.muted)),
                Text(next.foods, style: AppText.s(13.5, W.w7)),
                Text('${inNum(next.kcal)} kcal', style: AppText.s(12, W.w4, color: AppColors.muted)),
              ]),
            ),
            if (next.locked)
              Text('Opens ${clock(next.opensAt!)}', style: AppText.s(12.5, W.w6, color: AppColors.muted))
            else
              chSm('Ate it', () => _eat(next), icon: AppIcons.check),
          ]),
        )
      else if (d.meals.isNotEmpty)
        ChNote(icon: AppIcons.checkCircle, bg: AppColors.okBg, fg: AppColors.okText, child: Text('All meals logged for today', style: AppText.s(13.5, W.w7, color: AppColors.okText))),
    ]);
  }

  // ─────────────────────────────── Habits

  Widget _habits(HomeData d) {
    final hs = d.habits;
    final met = hs.where((h) => h.ratio >= 1).length;
    return ChCard(children: [
      ChHead(
        lead: const ChIcon(AppIcons.target, tone: ChTone.amber),
        title: 'Habits',
        sub: hs.isEmpty ? 'No habits yet' : '$met of ${hs.length} done today',
        action: chSm('See all', () => context.go('/habits')),
      ),
      if (hs.isNotEmpty)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final h in hs) _habitRow(d, h),
        ]),
      if (d.soon.isNotEmpty)
        Row(spacing: 8, children: [
          const AppIcon(AppIcons.clock, size: 14, color: AppColors.muted),
          Expanded(child: Text('${d.soon.first.name} starts on ${dayShort(d.soon.first.starts)}', style: AppText.s(12.5, W.w4, color: AppColors.muted))),
        ]),
    ]);
  }

  Widget _habitRow(HomeData d, HomeHabit h) {
    final (icon, tone) = switch (h.icon) {
      'steps' => (AppIcons.steps, ChTone.green),
      'water' => (AppIcons.water, ChTone.warm),
      'sleep' => (AppIcons.moon, ChTone.purple),
      'food' => (AppIcons.food, ChTone.green),
      'timer' => (AppIcons.clock, ChTone.blue),
      'sun' => (AppIcons.sun, ChTone.amber),
      _ => (AppIcons.target, ChTone.amber),
    };
    final met = h.ratio >= 1;
    final unit = h.unit.isEmpty ? '' : ' ${h.unit}';
    final (String line, String btn, VoidCallback tap) = h.isWater
        ? ('${litres(d.waterMl)} of ${litres(h.unit == 'ml' ? h.target : h.target * 250)} · from the water card', '+250 ml', () => _water(250))
        : h.isSleep
            ? ('Last night ${hoursMin(h.value)}', 'Change', () => showSleepSheet(context, c, h))
            : h.counter
                ? ('${inNum(h.value)} of ${inNum(h.target)}$unit', h.icon == 'steps' ? 'Add steps' : 'Add', () => showCounterSheet(context, c, h))
                : (h.done ? 'Done today' : 'Not done yet', h.done ? 'Undo' : 'Done', () => _tick(h));
    return ChRow(vertical: 11, children: [
      ChIcon(icon, tone: tone),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 2, children: [
          Row(spacing: 8, children: [
            Flexible(child: CutText(h.name, style: AppText.s(14, W.w7), overflow: TextOverflow.ellipsis)),
            if (met) const ChOk('Done', icon: true),
          ]),
          Text(line, style: AppText.s(12, W.w4, color: AppColors.muted)),
          Padding(padding: const EdgeInsets.only(top: 3), child: ChBar(h.ratio, color: met ? AppColors.okSolid : AppColors.amberSolid, height: 5)),
        ]),
      ),
      chSm(btn, tap),
    ]);
  }

  void _tick(HomeHabit h) {
    final was = h.done;
    c.setHabit(h, done: !was);
    if (!was) showToast(context, '${h.name} done', sub: 'Nice, keep it going', kind: ToastKind.ok, action: 'Undo', onAction: () => c.setHabit(h, done: false));
  }

  // ─────────────────────────────── Supplements

  List<HomeSupplement> _dueSupps(HomeData d) => d.supplements.where((s) => s.due).toList();

  Widget _supps(HomeData d) {
    final list = _dueSupps(d);
    final taken = list.where((s) => s.taken).length;
    return ChCard(children: [
      ChHead(
        lead: const ChIcon(AppIcons.pill, tone: ChTone.purple),
        title: 'Supplements',
        sub: '$taken of ${list.length} taken',
        action: chSm('See all', () => context.go('/habits')),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final s in list)
          ChRow(vertical: 9, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: s.taken ? AppColors.okSolid : null,
                shape: BoxShape.circle,
                border: Border.all(color: s.taken ? AppColors.okSolid : AppColors.tickRing, width: 1.5),
              ),
              child: s.taken ? const AppIcon(AppIcons.check, size: 14, color: AppColors.white, stroke: 2.6) : null,
            ),
            Expanded(
              child: ChTwoLine(s.name, s.line,
                  titleStyle: AppText.s(14, W.w7, color: s.taken ? AppColors.muted : AppColors.text)
                      .copyWith(decoration: s.taken ? TextDecoration.lineThrough : null, decorationColor: AppColors.strike)),
            ),
            if (s.taken)
              const ChOk('Taken')
            else
              chSm('Take', () {
                c.setSupplement(s, true);
                showToast(context, '${s.name} taken', sub: s.line, kind: ToastKind.ok, action: 'Undo', onAction: () => c.setSupplement(s, false));
              }),
          ]),
      ]),
    ]);
  }

  // ─────────────────────────────── Coach's last reply

  Widget? _coach(HomeData d) {
    final n = d.note;
    if (n == null) return null;
    final by = (n['by'] as Map?) ?? d.coach ?? const {};
    final at = DateTime.tryParse('${n['at']}')?.toLocal();
    return ChCard(children: [
      Row(spacing: 10, children: [
        ChAvatar('${by['initials'] ?? ''}', green: true),
        Expanded(child: ChTwoLine('${by['full_name'] ?? 'Your coach'}', 'Your trainer${at == null ? '' : ' · ${since(at, ago: true)}'}', size: 15, subSize: 12.5, titleStyle: AppText.s(15, W.w8))),
      ]),
      Text('${n['body']}', style: AppText.s(14, W.w4, color: AppColors.text2, h: 1.5)),
    ]);
  }

  // ─────────────────────────────── Coming up

  Widget _coming(HomeData d) {
    final today = d.date;
    String when(DateTime t) {
      final diff = DateUtils.dateOnly(t).difference(today).inDays;
      return diff == 0 ? 'Today' : (diff == 1 ? 'Tomorrow' : dayShort(t));
    }

    final rows = <Widget>[];
    for (final (i, u) in d.coming.indexed) {
      final kind = '${u['kind']}';
      final date = DateTime.tryParse('${u['date']}')?.toLocal() ?? today;
      late final AppIconData icon;
      late final ChTone tone;
      late final String sub;
      late final VoidCallback tap;
      switch (kind) {
        case 'session':
          final s = d.session;
          final place = s?.isCall == true ? 'Video call' : '${u['place'] ?? ''}';
          (icon, tone) = (AppIcons.calendarAlt, ChTone.blue);
          sub = '${when(date)}, ${clock(date)}${place.isEmpty ? '' : ' · $place'} · ${u['minutes']} min';
          tap = () => showToast(context, '${u['title']}', sub: '${when(date)} ${clock(date)}${place.isEmpty ? '' : ', $place'}. ${d.coachFirst} can move it if you need.', kind: ToastKind.info);
        case 'checkin':
          final q = u['questions'] ?? 0, p = u['photos'] ?? 0;
          (icon, tone) = (AppIcons.clipboard, ChTone.amber);
          sub = '${dayShort(date)} · $q ${q == 1 ? 'question' : 'questions'}${p == 0 ? '' : ' and $p ${p == 1 ? 'photo' : 'photos'}'}';
          tap = () => context.go('/checkins');
        default:
          (icon, tone) = (AppIcons.flag, ChTone.gray);
          sub = '${dayShort(date)} · ${d.coachFirst} will set your next plan';
          tap = () => showToast(context, 'Your plan ends on ${date.day} ${dayShort(date).split(' ').last}', sub: '${d.coachFirst} is already planning the next phase', kind: ToastKind.info);
      }
      rows.add(ChRow(first: i == 0, onTap: tap, children: [
        ChIcon(icon, tone: tone),
        Expanded(child: ChTwoLine('${u['title']}', sub)),
        const AppIcon(AppIcons.chevronRight, color: AppColors.chevron),
      ]));
    }
    return ChCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4), gap: 0, children: rows);
  }
}


/// Counts down to [ends] once a second (the web Home Rest timer card).
class _RestTicker extends StatefulWidget {
  const _RestTicker({required this.ends, required this.builder});
  final DateTime ends;
  final Widget Function(int left) builder;
  @override
  State<_RestTicker> createState() => _RestTickerState();
}

class _RestTickerState extends State<_RestTicker> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(widget.ends.difference(DateTime.now()).inSeconds);
}
