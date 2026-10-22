import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../home/home_model.dart' show clock;
import '../home/home_parts.dart';
import 'train_model.dart';
import 'train_parts.dart';
import '../../../core/widgets/tooltip.dart';
import 'workout_model.dart' show WorkoutController;

/// Train tab (boards `ClientTrain` phone and `ClientTrainWeb`): the week, today's workout, the
/// coach's note and the exercise blocks. A running workout shows as a bar (phone) or banner (web).
class ClientTrainScreen extends StatefulWidget {
  const ClientTrainScreen({super.key, this.discarded = 0});

  /// Opened right after "Discard workout": shows the "Workout discarded" toast once
  /// (1 = whole workout, 2 = the sets added with "Log more sets").
  final int discarded;

  @override
  State<ClientTrainScreen> createState() => _ClientTrainScreenState();
}

class _ClientTrainScreenState extends State<ClientTrainScreen> {
  final c = TrainController();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    c.start();
    c.addListener(_timer);
    if (widget.discarded > 0) {
      final again = widget.discarded == 2;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showToast(context, again ? 'Extra sets discarded' : 'Workout discarded',
              sub: again ? 'Your finished workout is kept as it was' : 'Nothing was saved', kind: ToastKind.del);
        }
      });
    }
  }

  /// The running workout's clock counts here too.
  void _timer() {
    final live = c.data?.live;
    if (live != null && live.pausedAt == null) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
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
                        Text(e.offline ? 'Connect to the internet to load your plan' : e.message, textAlign: TextAlign.center, style: AppText.s(13, W.w4, color: AppColors.muted)),
                        CaButton('Try again', kind: CaBtnKind.out, expand: false, onPressed: c.load),
                      ]),
                    ),
            );
          }
          return context.isPhone ? _phone(d) : _web(d);
        },
      );

  GuideInfo _info(TrainData d, TrainEx e) => GuideInfo(
        context: '${d.dayName} · Exercise ${e.index + 1} of ${d.exercises.length}',
        program: d.program,
        coachFirst: d.coachFirst,
        coachInitials: d.coachInitials,
      );

  void _go(TrainData d) {
    if (d.live != null) {
      context.go('/train/workout');
    } else if (d.finished) {
      context.go('/train/workout?reopen=${d.completed!['id']}');
    } else {
      context.go('/train/workout?start=${d.dayId ?? ''}');
    }
  }

  // ─────────────────────────────── Layouts

  Widget _phone(TrainData d) {
    final live = d.live;
    return Stack(children: [
      RefreshIndicator(
        onRefresh: c.load,
        color: AppColors.accent,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 6, 16, live == null ? 20 : 84),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            _top(d),
            if (d.strip.isNotEmpty) _week(d, web: false),
            _today(d),
            ?_note(d, web: false),
            for (final b in d.blocks) _block(d, b),
          ]),
        ),
      ),
      if (live != null) Positioned(left: 0, right: 0, bottom: 0, child: _liveBar(d, live)),
    ]);
  }

  Widget _web(TrainData d) => CaWeb(
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
                  final two = box.maxWidth >= 680;
                  final left = [for (final b in d.blocks) _block(d, b)];
                  final right = [_today(d), ?_note(d, web: true)];
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
                    _top(d),
                    if (d.live != null) _liveBanner(d, d.live!),
                    if (d.strip.isNotEmpty) _week(d, web: (box.maxWidth - 10) / 7 >= 92),
                    // A rest day (no exercises) has nothing on the left: the day card takes the full width.
                    if (two && left.isNotEmpty)
                      Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
                        Expanded(flex: 6, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: left)),
                        Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: right)),
                      ])
                    else
                      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [...right, ...left]),
                  ]);
                }),
              ),
            ),
          ),
        ),
      );

  // ─────────────────────────────── Header

  Widget _top(TrainData d) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(spacing: 10, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text('Train', style: AppText.s(26, W.w8, ls: -0.26)),
              if (d.programLine.isNotEmpty) Text(d.programLine, style: AppText.s(13, W.w6, color: AppColors.muted)),
            ]),
          ),
          chSm('History', () => showPastWorkouts(context, thisName: d.rest || d.dayName.isEmpty ? null : d.dayName), icon: AppIcons.clock),
        ]),
      );

  // ─────────────────────────────── Week (`tn-week`)

  Widget _week(TrainData d, {required bool web}) {
    final narrow = MediaQuery.sizeOf(context).width < 1180;
    return Container(
      padding: web ? const EdgeInsets.all(5) : const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Row(spacing: web ? 4 : 2, children: [
        for (final day in d.strip) Expanded(child: _weekDay(day, web: web, narrow: narrow)),
      ]),
    );
  }

  Widget _weekDay(TrainDay day, {required bool web, required bool narrow}) =>
      Hover(onTap: () => c.pick(day.date), builder: (_, h, _) => _weekDayBox(day, web: web, narrow: narrow, hover: h));

  /// [TrainDay.today] is the day shown (picked in the strip); the ring marks the real today.
  Widget _weekDayBox(TrainDay day, {required bool web, required bool narrow, required bool hover}) {
    final today = day.today, rest = day.rest;
    final real = DateUtils.isSameDay(day.date, DateTime.now());
    final wd = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day.date.weekday - 1];
    final ink = today ? AppColors.sessText : AppColors.text;
    final size = web && !narrow ? 18.0 : 16.0;
    final Widget mark;
    if (day.done) {
      mark = Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: AppColors.okSolid, shape: BoxShape.circle),
        child: AppIcon(AppIcons.check, size: size == 18 ? 11 : 10, color: AppColors.white, stroke: 3),
      );
    } else if (real) {
      mark = Container(width: size, height: size, decoration: BoxDecoration(color: AppColors.white, shape: BoxShape.circle, border: Border.all(color: AppColors.accent, width: 2)));
    } else if (rest) {
      mark = DashedCircle(size: size);
    } else {
      mark = Container(width: size, height: size, decoration: const BoxDecoration(color: AppColors.sub, shape: BoxShape.circle));
    }
    final wdText = Text(wd, style: AppText.s(web ? 11 : 10.5, W.w6, color: today ? AppColors.sessText : AppColors.muted));
    final name = CutText(rest ? 'Rest' : (day.name.isEmpty ? '—' : day.name),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.s(web ? (narrow ? 12 : 12.5) : 10, rest ? W.w6 : W.w7, color: rest && !today ? AppColors.muted : ink));
    return Semantics(
      button: true,
      selected: today,
      label: '$wd ${rest ? 'rest' : day.name}${day.done ? ', done' : ''}${real ? ', today' : ''}',
      child: Container(
        padding: web ? EdgeInsets.symmetric(horizontal: narrow ? 6 : 10, vertical: 6) : const EdgeInsets.fromLTRB(0, 6, 0, 5),
        decoration: BoxDecoration(
          color: today ? AppColors.accentSoft : (hover ? AppColors.outlineHover : null),
          borderRadius: BorderRadius.circular(10),
          border: today && web ? Border.all(color: AppColors.accentRing) : null,
        ),
        child: web
            ? Row(spacing: narrow ? 6 : 8, children: [
                mark,
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [wdText, name])),
              ])
            : Column(children: [wdText, const SizedBox(height: 3), name, const SizedBox(height: 4), mark]),
      ),
    );
  }

  // ─────────────────────────────── Today card (`tn-sum`)

  Widget _today(TrainData d) {
    if (!d.hasPlan) {
      return ChCard(children: [
        ChHead(lead: const ChIcon(AppIcons.dumbbell, tone: ChTone.green), title: 'No plan yet', sub: '${d.coachFirst} is setting up your training plan'),
      ]);
    }
    final rest = d.rest;
    final live = d.live;
    final n = d.exercises.length;
    final doneN = d.exercisesDone;
    final s = d.session;
    final hero = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: rest ? AppColors.heroGray : AppColors.heroBlue),
        border: const Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
        Row(children: [
          AppIcon(rest ? AppIcons.moon : (d.exercises.any((e) => e.kind == ExKind.cardio) ? AppIcons.run : AppIcons.dumbbell), size: 15, color: AppColors.text2),
          const SizedBox(width: 6),
          Expanded(child: Text('${d.isToday ? 'Today · ' : ''}${dayUpper(d.date)}'.toUpperCase(), style: AppText.s(11.5, W.w8, color: AppColors.text2, ls: .575))),
          if (d.finished) CaPill(d.isToday ? 'Completed today' : 'Done', tone: CaTone.green),
        ]),
        Text(rest ? 'Rest day' : d.dayName, style: AppText.s(22, W.w8, ls: -0.22)),
        if (!rest)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Wrap(spacing: 14, runSpacing: 6, children: [
              if (d.minutes > 0) _meta(AppIcons.clock, 'About ${d.minutes} min'),
              _meta(AppIcons.dumbbell, '$n ${n == 1 ? 'exercise' : 'exercises'} · ${d.totalSets} sets'),
              if (d.kit.isNotEmpty) _meta(AppIcons.pin, d.kit),
            ]),
          ),
      ]),
    );
    final body = <Widget>[];
    if (rest) {
      body.add(ChNote(
        top: true,
        bg: AppColors.sub,
        fg: AppColors.text2,
        child: Text(d.note.isNotEmpty ? d.note : 'Rest helps your muscles grow. A short walk and some stretching is enough.', style: AppText.s(13, W.w4, color: AppColors.text2)),
      ));
    } else if (!d.isToday) {
      // Another day picked in the strip: what was done, or what is planned. Only today starts.
      final c = d.completed;
      body.add(Row(spacing: 10, children: [
        Expanded(child: ChBar(n == 0 ? 0 : doneN / n, color: AppColors.okSolid)),
        Text('$doneN of $n exercises done', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
      ]));
      body.add(ChNote(
        icon: d.finished ? AppIcons.checkCircle : AppIcons.calendarAlt,
        bg: d.finished ? AppColors.okBg : (d.isPast ? AppColors.sub : AppColors.accentSoft),
        fg: d.finished ? AppColors.okText : (d.isPast ? AppColors.text2 : AppColors.sessText),
        child: Text(
          d.finished
              ? 'Done · ${((c!['duration_seconds'] as num? ?? 0) / 60).round()} min · ${c['sets_done'] ?? 0} sets'
              : (d.isPast ? 'Not done' : 'Planned for ${dayUpper(d.date)}. You can start it on the day.'),
          style: AppText.s(13, W.w6, color: d.finished ? AppColors.okText : (d.isPast ? AppColors.text2 : AppColors.sessText)),
        ),
      ));
      body.add(CaButton('Back to today', kind: CaBtnKind.out, onPressed: () => this.c.pick(DateTime.now())));
    } else {
      final label = live != null ? 'Continue workout' : (d.finished ? 'Log more sets' : 'Start workout');
      body.addAll([
        Row(spacing: 10, children: [
          Expanded(child: ChBar(n == 0 ? 0 : doneN / n, color: AppColors.okSolid)),
          Text('$doneN of $n exercises done', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
        ]),
        CaButton(label, icon: AppIcons.play, onPressed: n == 0 ? null : () => _go(d)),
      ]);
    }
    if (s != null) {
      body.add(ChNote(
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
      ));
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        hero,
        Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: body)),
      ]),
    );
  }

  Widget _meta(AppIconData icon, String t) => Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
        AppIcon(icon, size: 14, color: AppColors.muted),
        Flexible(child: Text(t, style: AppText.s(12.5, W.w6, color: AppColors.text2))),
      ]);

  // ─────────────────────────────── Coach note (`ch-coach`)

  Widget? _note(TrainData d, {required bool web}) {
    if (d.rest || d.note.isEmpty) return null;
    return ChCard(
      padding: web ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12) : const EdgeInsets.all(14),
      gap: 10,
      children: [
        Row(spacing: 10, children: [
          ChAvatar(d.coachInitials, green: true),
          Expanded(child: ChTwoLine('Note from ${d.coachFirst}', 'For this workout', size: 15, subSize: 12.5, titleStyle: AppText.s(15, W.w8))),
        ]),
        Text(d.note, style: AppText.s(14, W.w4, color: AppColors.text2, h: 1.5)),
      ],
    );
  }

  // ─────────────────────────────── Blocks (`tn-blk`)

  Widget _block(TrainData d, TrainBlock b) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 8, children: [
            Expanded(child: Text(b.name, style: AppText.s(15, W.w8))),
            Flexible(child: Text(b.sub, textAlign: TextAlign.right, style: AppText.s(12.5, W.w6, color: AppColors.muted))),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, e) in b.items.indexed)
              Hover(
                onTap: () => showGuide(context, e, _info(d, e)),
                builder: (_, h, _) => Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                  child: Row(spacing: 12, children: [
                    ExThumb(e.kind, thumb: e.thumb, video: e.hasVideo && e.mediaKind != 'image'),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                        Text(e.name, style: AppText.s(14.5, W.w7, color: h ? AppColors.accentText : AppColors.text)),
                        Text(e.target, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
                      ]),
                    ),
                    if (e.done) const ChOk('Done', icon: true),
                    const AppIcon(AppIcons.chevronRight, size: 17, color: AppColors.muted),
                  ]),
                ),
              ),
          ]),
        ),
      ]);

  // ─────────────────────────────── Running workout

  /// Phone: white bar over the tabs (`cl-wbar`), opens the logger.
  Widget _liveBar(TrainData d, LiveWorkout live) => Hover(
        onTap: () => context.go('/train/workout'),
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 18, 10),
          decoration: BoxDecoration(
            color: h ? AppColors.outlineHover : AppColors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: const Border(top: BorderSide(color: AppColors.line), left: BorderSide(color: AppColors.line), right: BorderSide(color: AppColors.line)),
            boxShadow: AppShadows.barUp,
          ),
          child: Row(spacing: 10, children: [
            _wic(paused: live.pausedAt != null),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(live.pausedAt != null ? 'TIMER PAUSED' : 'WORKOUT IN PROGRESS', style: AppText.s(11, W.w7, color: AppColors.muted, ls: .55)),
                Text(clockText(live.elapsed), style: AppText.s(18, W.w8, tabular: true)),
              ]),
            ),
            Text('${live.setsDone} of ${live.setsTotal} sets', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
            _more(live, size: 34),
          ]),
        ),
      );

  Widget _wic({required bool paused, double size = 34, double radius = 10}) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: paused ? AppColors.amberBg : AppColors.accentSoft, borderRadius: BorderRadius.circular(radius)),
        child: AppIcon(paused ? AppIcons.pause : AppIcons.clock, size: 17, color: paused ? AppColors.amberText : AppColors.accent),
      );

  /// Web: banner card under the title (`tn-live`).
  Widget _liveBanner(TrainData d, LiveWorkout live) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        child: Row(spacing: 14, children: [
          _wic(paused: live.pausedAt != null),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(live.pausedAt != null ? 'TIMER PAUSED' : 'WORKOUT IN PROGRESS', style: AppText.s(11, W.w7, color: AppColors.muted, ls: .55)),
              CutText(live.name, overflow: TextOverflow.ellipsis, style: AppText.s(15, W.w8)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(clockText(live.elapsed), style: AppText.s(17, W.w8, tabular: true)),
            Text('${live.setsDone} of ${live.setsTotal} sets', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
          ]),
          CaButton('Continue workout', icon: AppIcons.play, expand: false, onPressed: () => context.go('/train/workout')),
          _more(live, size: 40, outline: true),
        ]),
      );

  /// ⋯ on the running workout: Pause / Resume timer, Finish, Restart, Discard.
  Widget _more(LiveWorkout live, {required double size, bool outline = false}) => Builder(
        builder: (bc) => Semantics(
          button: true,
          label: 'Workout options',
          child: Hover(
            onTap: () => _liveMenu(bc, live),
            builder: (_, h, _) => Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: h ? AppColors.sub : AppColors.white,
                borderRadius: BorderRadius.circular(10),
                border: outline ? Border.all(color: AppColors.line) : null,
              ),
              child: const AppIcon(AppIcons.dots, size: 18, fill: true, color: AppColors.text2),
            ),
          ),
        ),
      );

  void _liveMenu(BuildContext anchor, LiveWorkout live) {
    final paused = live.pausedAt != null;
    final entries = [
      MenuEntry(paused ? 'Resume timer' : 'Pause timer', icon: paused ? AppIcons.play : AppIcons.pause, onTap: () => _pause(live, !paused)),
      MenuEntry('Finish workout', icon: AppIcons.check, onTap: () => context.go('/train/workout?then=finish')),
      MenuEntry('Restart workout', icon: AppIcons.restart, onTap: () => context.go('/train/workout?then=restart')),
      const MenuEntry('', separator: true),
      MenuEntry('Discard workout', icon: AppIcons.trash, danger: true, onTap: () => _askDiscard(live)),
    ];
    if (context.isPhone) {
      showActionSheet(context, entries, title: live.name);
    } else {
      showAppMenu(anchor, entries, width: 210);
    }
  }

  Future<void> _pause(LiveWorkout live, bool pause) async {
    await WorkoutController.setPaused(live.id, pause: pause);
    await WorkoutController.drain();
    await c.load();
    final now = c.data?.live;
    if (mounted) showToast(context, pause ? 'Timer paused' : 'Timer running', sub: '${live.name} · ${clockText((now ?? live).elapsed)}', kind: ToastKind.info);
  }

  void _askDiscard(LiveWorkout live) => showAppSheet(
        context,
        title: 'Discard workout?',
        sub: '${live.name} · ${clockText(live.elapsed)} so far',
        webWidth: 440,
        builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
          Text(
            live.setsDone == 0
                ? 'Nothing is saved and the timer stops.'
                : 'Your ${live.setsDone} ticked ${live.setsDone == 1 ? 'set is' : 'sets are'} removed. Nothing is saved and the timer stops.',
            style: AppText.s(14, W.w4, color: AppColors.text2, h: 1.5),
          ),
          Row(spacing: 8, children: [
            Expanded(child: CaButton('Keep it', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop())),
            Expanded(
              child: Hover(
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await WorkoutController.discardLive(live.id);
                  await c.load();
                  if (mounted) showToast(context, 'Workout discarded', sub: 'Nothing was saved', kind: ToastKind.del);
                },
                builder: (bc, h, _) {
                  final web = CaWeb.of(bc);
                  return Container(
                    height: web ? 40 : 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: h ? AppColors.badText : AppColors.red, borderRadius: BorderRadius.circular(web ? 10 : 12)),
                    child: CutText('Discard workout', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(web ? 14 : 14.5, W.w7, color: AppColors.white)),
                  );
                },
              ),
            ),
          ]),
        ]),
      );
}
