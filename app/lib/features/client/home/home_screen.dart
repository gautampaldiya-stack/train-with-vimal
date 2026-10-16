import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import 'home_model.dart';
import 'home_parts.dart';
import 'home_sheets.dart';

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
              child: Text('${dayShort(d.date)}${d.week != null && d.weeks != null ? ' · Week ${d.week} of ${d.weeks}' : ''}',
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
                  child: Stack(alignment: Alignment.center, children: [
                    const AppIcon(AppIcons.bell, size: 18, color: AppColors.white),
                    if (d.unread > 0)
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
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 8, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Hey ${d.firstName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(28, W.w8, ls: -0.56, color: AppColors.white, h: 1.2)),
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

  List<Widget> _phoneCards(HomeData d) => [
            _workout(d),
            _waterCard(d),
            _food(d),
            _habits(d),
            if (_dueSupps(d).isNotEmpty) _supps(d),
            ?_coach(d),
            if (d.coming.isNotEmpty) ...[const ChSection('Coming up'), _coming(d)],
          ];

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
                  final left = [
                    _week(d, web: true),
                    _workout(d),
                    _waterCard(d),
                    if (d.coming.isNotEmpty) ...[const ChSection('Coming up'), _coming(d)],
                  ];
                  final right = [
                    _food(d),
                    _habits(d),
                    if (_dueSupps(d).isNotEmpty) _supps(d),
                    ?_coach(d),
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
                        ...left.take(3),
                        ...right,
                        ...left.skip(3),
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
          Builder(builder: (bell) => ChBell(dot: d.unread > 0, onTap: () => web ? _notesMenu(bell) : showNoticesSheet(context, c))),
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
    final showList = !day.rest && (!past || !day.done);
    if (showList) {
      body.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, e) in day.exercises.take(4).indexed) _exRow(i, e, today ? day.exercisesDone : -1),
          if (n > 4)
            Align(
              alignment: Alignment.centerLeft,
              child: Hover(
                onTap: () => showWorkoutPreview(context, day),
                builder: (_, h, _) => Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 2),
                  child: Text('+ ${n - 4} more',
                      style: AppText.s(13, W.w7, color: AppColors.accentText).copyWith(decoration: h ? TextDecoration.underline : null, decorationColor: AppColors.accentText)),
                ),
              ),
            ),
        ]),
      ));
    }
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
      final k = day.exercisesDone.clamp(0, n);
      body.add(Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(spacing: 10, children: [
          Expanded(child: ChBar(n == 0 ? 0 : k / n, color: AppColors.okSolid)),
          Text('$k of $n done', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
        ]),
      ));
      body.add(Padding(
        padding: const EdgeInsets.only(top: 10),
        child: CaButton(k > 0 ? 'Continue workout' : 'Start workout', icon: AppIcons.play, onPressed: () => context.go('/train')),
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

  Widget _exRow(int i, ({String name, String line}) e, int done) {
    final on = done >= 0 && i < done, next = done >= 0 && i == done;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(spacing: 11, children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: on ? AppColors.okBg : (next ? AppColors.accent : AppColors.sub), borderRadius: BorderRadius.circular(8)),
          child: Text('${i + 1}', style: AppText.s(12, W.w8, color: on ? AppColors.okText : (next ? AppColors.white : AppColors.text2))),
        ),
        Expanded(child: ChTwoLine(e.name, e.line, titleStyle: AppText.s(14, W.w7, color: on ? AppColors.muted : AppColors.text))),
        if (on) const AppIcon(AppIcons.check, size: 18, color: AppColors.okSolid, stroke: 2.6),
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

  void _eat(HomeMeal m) {
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
            Flexible(child: Text(h.name, style: AppText.s(14, W.w7), overflow: TextOverflow.ellipsis)),
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
