import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../app/shell/back_nav.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tooltip.dart';
import '../home/home_parts.dart';
import 'train_model.dart';
import 'train_parts.dart';
import 'workout_model.dart';

/// Workout logger, Strong-style (tracker F, Probid 2026-11-16, built new from his screenshots): every exercise on
/// one page with SET · PREVIOUS · KG · REPS · ✓ rows, number boxes with placeholders, a phone keypad, set types
/// (W / D / F), focus metric, ⌄ to the mini bar, Cancel workout at the end and the Congratulations page.
/// [start] = program day to start (the Start sheet shows first), [reopen] = finished workout to log more sets on.
class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key, this.start, this.reopen, this.then});
  final int? start;
  final String? reopen;

  /// Opened from the Train banner ⋯: `finish` or `restart` opens that question at once.
  final String? then;

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

/// Phone: the logger lives in one panel of the app shell (Strong, Probid 17 Nov). Down, its top bar sits on the tab
/// bar; the finger drags it up to full screen and back down. The shell (WorkoutPanelHost) fills in these hooks.
abstract final class WorkoutPanel {
  /// An open asked for before the shell was there (app start from the notification, a /train/workout link).
  static String? pending;
  static void Function(String query)? show;
  static VoidCallback? collapse;
  static VoidCallback? close;
  static void Function(double dy)? dragBy;
  static void Function(double velocity)? dragEnd;
  static bool Function()? isOpen;
  static bool get here => show != null;
}

/// Opens the logger: the panel on a phone, the logger page in the panel on wider screens.
void openWorkout(BuildContext context, [String query = '']) {
  if (context.isPhone && WorkoutPanel.here) {
    WorkoutPanel.show!(query);
  } else {
    context.go('/train/workout$query');
  }
}

/// The box being typed in with the phone keypad: (exercise, set, column).
typedef _Cell = (int, int, int);

class _WorkoutScreenState extends State<WorkoutScreen> {
  final train = TrainController();
  WorkoutController? w;
  String? _err;

  /// Start sheet (before the workout exists, so its clock has not started).
  TrainData? _preview;
  bool _starting = false;

  /// Phone keypad: the active box and what was typed since it opened (the first key replaces the value).
  _Cell? act;

  /// The set whose tick shakes (empty box), and a counter so each refused tap shakes again.
  (String, int)? _shake;

  void _tryTick(WorkoutController c, int i, int k) {
    if (c.canTick(i, k)) return c.tick(i, k);
    WorkoutFeel.refused();
    setState(() => _shake = (c.sets[i][k].key, (_shake?.$2 ?? 0) + 1));
  }
  String _buf = '';
  bool _fresh = true;

  RawDialogRoute? _restRoute;
  double? _lifted;
  bool _idleUp = false;
  final _note = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final have = WorkoutController.current;
    if (have != null && have.ready && !have.finished && widget.reopen == null) {
      _attach(have);
      return;
    }
    await train.start();
    final d = train.data;
    if (!mounted) return;
    if (d == null) {
      final e = train.error;
      setState(() => _err = e == null ? 'Could not load your plan.' : (e.offline ? 'You are offline. Connect to open your workout.' : e.message));
      return;
    }
    if (widget.start != null && widget.reopen == null && d.live == null && WorkoutController.current == null) {
      setState(() => _preview = d);
      return;
    }
    await _open(d);
  }

  void _attach(WorkoutController c) {
    c.toast = _toast;
    c.addListener(_onW);
    setState(() => w = c);
    _then(c);
  }

  Future<void> _open(TrainData d) async {
    final c = WorkoutController(d)..toast = _toast;
    c.addListener(_onW);
    setState(() => w = c);
    await c.open(start: widget.start, reopen: widget.reopen);
    if (!mounted) return;
    setState(() {});
    _then(c);
  }

  void _then(WorkoutController c) {
    if (!c.ready || c.finished) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.then == 'finish') _askFinish(c);
      if (widget.then == 'restart') _askRestart(c);
    });
  }

  void _lift(double? v) {
    if (_lifted == v) return;
    _lifted = v;
    Timer.run(() {
      if (mounted) ToastHost.bottomOffset.value = v ?? (context.isPhone ? 75 : 20);
    });
  }

  @override
  void dispose() {
    if (_lifted != null) Timer.run(() => ToastHost.bottomOffset.value = 75);
    final c = w;
    if (c != null) {
      c.removeListener(_onW);
      c.detach(); // the workout goes on: mini bar, notification (F33)
    }
    train.dispose();
    _note.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toast(String title, {String? sub, ToastKind kind = ToastKind.info, VoidCallback? undo}) {
    if (!mounted) return;
    showToast(context, title, sub: sub, kind: kind, action: undo == null ? null : 'Undo', onAction: undo);
  }

  /// Opens and closes the rest dialog and the "Still working out?" sheet as the workout changes.
  void _onW() {
    final c = w;
    if (c == null || !mounted || !c.ready) return;
    final a = act;
    if (a != null && (a.$1 >= c.sets.length || a.$2 >= c.sets[a.$1].length || c.sets[a.$1][a.$2].done)) {
      setState(() => act = null);
    }
    final restUp = _restRoute != null;
    if (c.restOpen && c.rest > 0 && !restUp && !c.finished) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openRest());
    } else if (restUp && (!c.restOpen || c.rest == 0)) {
      final r = _restRoute!;
      _restRoute = null;
      if (r.isActive) r.navigator?.removeRoute(r);
    }
    if (!c.finished && !c.paused && c.elapsed - c.lastActive >= 3 * 3600) {
      // no answer for 3 hours: saved at the last set
      final at = c.lastTickAt;
      _finish(c, at: at ?? c.elapsed);
    } else if (c.idle && !_idleUp) {
      _idleUp = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _askIdle());
    }
  }

  /// ⌄, back or a swipe down: the logger goes down to the mini bar; the workout keeps running (F33).
  bool get _inPanel => context.isPhone && WorkoutPanel.here;

  void _collapse() {
    if (_inPanel) {
      WorkoutPanel.collapse!();
      return;
    }
    final to = WorkoutController.backTo;
    context.go(to.startsWith('/train/workout') ? '/train' : to);
  }

  /// Leaves the logger for another page (finished, discarded, could not open): the phone panel closes first.
  void _leave(String to) {
    if (_inPanel) WorkoutPanel.close!();
    context.go(to);
  }

  // ─────────────────────────────── Page

  @override
  Widget build(BuildContext context) => BackIntercept(
        onBack: () {
          // the panel is down: back is for the page under it
          if (_inPanel && !WorkoutPanel.isOpen!()) return false;
          if (act != null) {
            setState(() => act = null);
            return true;
          }
          final c = w;
          if (c != null && c.restOpen) {
            c.restShow(false);
            return true;
          }
          if (c != null && c.ready && !c.finished) {
            _collapse();
            return true;
          }
          return false;
        },
        child: Builder(builder: _page),
      );

  Widget _page(BuildContext context) {
    final p = _preview;
    if (p != null) return _startSheet(p);
    final c = w;
    if (_err != null || (c != null && c.failed != null)) return _problem(_err ?? c!.failed!);
    if (c == null || !c.ready) {
      return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent)));
    }
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final phone = context.isPhone;
        _lift(phone && !c.finished ? (act != null ? 300 : _cancelH + 10) : null);
        if (c.finished) return _doneView(c, phone);
        return _logger(c, phone);
      },
    );
  }

  Widget _problem(String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, spacing: 10, children: [
            Text('Could not open the workout', style: AppText.s(15, W.w7)),
            Text(msg, textAlign: TextAlign.center, style: AppText.s(13, W.w4, color: AppColors.muted)),
            CaButton('Back to Train', kind: CaBtnKind.out, expand: false, onPressed: () => _leave('/train')),
          ]),
        ),
      );

  // ─────────────────────────────── Start sheet

  /// Before the clock starts: the day, when it was last done and its exercises; Start workout starts it (F34).
  Widget _startSheet(TrainData d) {
    final web = !context.isPhone;
    final last = d.lastPerformed;
    final card = Container(
      width: web ? 460 : double.infinity,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .86),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: web ? BorderRadius.circular(18) : const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: AppShadows.dialogBig,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        Row(spacing: 10, children: [
          CaIconBtn(AppIcons.close, tooltip: 'Close', onTap: () => _inPanel ? WorkoutPanel.close!() : context.go(WorkoutController.backTo.startsWith('/train/workout') ? '/train' : WorkoutController.backTo)),
          Expanded(child: CutText(d.dayName.isEmpty ? 'Workout' : d.dayName, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(16, W.w8))),
          const SizedBox(width: 36),
        ]),
        Text(last == null ? 'First time doing this workout' : 'Last performed: ${DateFormat('d MMMM y').format(last)}',
            style: AppText.s(13, W.w5, color: AppColors.muted)),
        Flexible(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final x in d.exercises)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(spacing: 12, children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(10)),
                      child: Text(x.name.isEmpty ? '?' : x.name[0].toUpperCase(), style: AppText.s(17, W.w8, color: AppColors.text2)),
                    ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                        Text(x.kind == ExKind.cardio ? x.name : '${x.sets} × ${x.name}', style: AppText.s(14, W.w7)),
                        Text(x.muscleLabel, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
                      ]),
                    ),
                    CaIconBtn(AppIcons.help, tooltip: 'How to do it', onTap: () => showGuide(context, x, _info(d, x))),
                  ]),
                ),
            ]),
          ),
        ),
        CaButton('Start workout', icon: AppIcons.play, loading: _starting, onPressed: _starting
            ? null
            : () async {
                setState(() => _starting = true);
                final data = _preview!;
                setState(() => _preview = null);
                await _open(data);
                if (mounted) setState(() => _starting = false);
              }),
      ]),
    );
    return ColoredBox(
      color: AppColors.scrimSheet,
      child: web ? Center(child: Padding(padding: const EdgeInsets.all(24), child: card)) : Align(alignment: Alignment.bottomCenter, child: card),
    );
  }

  GuideInfo _info(TrainData d, TrainEx e) => GuideInfo(
        context: '${d.dayName} · Exercise ${e.index + 1} of ${d.exercises.length}',
        program: d.program,
        coachFirst: d.coachFirst,
        coachInitials: d.coachInitials,
      );

  // ─────────────────────────────── Logger

  Widget _logger(WorkoutController c, bool phone) {
    final keypad = phone && act != null;
    final list = ListView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(0, 10, 0, keypad ? 300 : 24),
      children: [
        Padding(padding: EdgeInsets.symmetric(horizontal: phone ? 14 : 28), child: _title(c)),
        for (var i = 0; i < c.ex.length; i++) _exercise(c, i, web: !phone),
        const SizedBox(height: 12),
      ],
    );
    final body = phone
        ? list
        : Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: list));
    final page = CaWeb(
      web: !phone,
      child: ColoredBox(color: AppColors.white, child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _top(c, phone),
          Expanded(child: GestureDetector(onTap: act == null ? null : () => setState(() => act = null), behavior: HitTestBehavior.translucent, child: body)),
          _cancelLink(c, phone),
        ]),
        if (keypad) Positioned(left: 0, right: 0, bottom: 0, child: _keypad(c)),
      ])),
    );
    return page;
  }

  /// ⌄ · rest timer · clock · FINISH. A swipe down on it collapses too.
  Widget _top(WorkoutController c, bool phone) {
    final resting = c.rest > 0;
    final p = c.restMax == 0 ? 0.0 : (c.rest / c.restMax).clamp(0.0, 1.0);
    return GestureDetector(
      // phone: the panel follows the finger (Strong); wider screens: a quick swipe down minimises
      onVerticalDragUpdate: _inPanel ? (d) => WorkoutPanel.dragBy!(d.delta.dy) : null,
      onVerticalDragEnd: (d) {
        if (_inPanel) {
          WorkoutPanel.dragEnd!(d.primaryVelocity ?? 0);
        } else if ((d.primaryVelocity ?? 0) > 250) {
          _collapse();
        }
      },
      child: Container(
        padding: EdgeInsets.fromLTRB(phone ? 8 : 20, phone ? 6 : 14, phone ? 8 : 20, 8),
        decoration: const BoxDecoration(color: AppColors.white, boxShadow: AppShadows.barDown),
        child: Row(spacing: 8, children: [
          // plain arrow like Strong, no box (Probid 17 Nov)
          AppTooltip(
            message: 'Minimise (the workout keeps running)',
            child: Semantics(
              button: true,
              label: 'Minimise (the workout keeps running)',
              child: Hover(
                onTap: _collapse,
                builder: (_, h, _) => Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: h ? AppColors.hover : null, shape: BoxShape.circle),
                  child: const AppIcon(AppIcons.chevronDown, size: 24, color: AppColors.text, stroke: 2.2),
                ),
              ),
            ),
          ),
          AppTooltip(
            message: resting ? 'Rest timer' : 'Start a rest timer',
            child: Semantics(
              button: true,
              label: resting ? 'Rest ${clockText(c.rest)}' : 'Rest timer',
              child: Hover(
                onTap: () => resting ? c.restShow(true) : _restIdle(c),
                builder: (_, h, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 38,
                    constraints: const BoxConstraints(minWidth: 48),
                    color: resting ? AppColors.accentSoft : (h ? AppColors.logFieldHover : AppColors.logField),
                    // icon in the middle of the box (Probid 17 Nov)
                    child: Stack(alignment: Alignment.center, children: [
                      if (resting) Positioned.fill(child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: p, child: Container(color: AppColors.accent))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Center(
                          widthFactor: 1,
                          child: Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
                            AppIcon(AppIcons.clockAlt, size: 20, color: resting ? AppColors.white : AppColors.text),
                            if (resting) Text(clockText(c.rest), style: AppText.s(13, W.w8, color: AppColors.white, tabular: true)),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(clockText(c.elapsed), textAlign: TextAlign.center, style: AppText.s(15, W.w5, color: c.paused ? AppColors.amberText : AppColors.text2, tabular: true)),
          ),
          Semantics(
            button: true,
            label: 'Finish workout',
            child: Hover(
              onTap: () => _askFinish(c),
              builder: (_, h, _) => Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: h ? AppColors.accentSoft : null, borderRadius: BorderRadius.circular(10)),
                child: Text('FINISH', style: AppText.s(15, W.w6, color: AppColors.accentText, ls: .8)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _title(WorkoutController c) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
          Row(spacing: 8, children: [
            Flexible(child: CutText(c.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(20, W.w7))),
            Builder(builder: (bc) => _dotsBtn(() => _workoutMenu(bc, c), 'Workout options')),
          ]),
          // no clock under the name (it is in the bar), only the state when it matters (Probid 17 Nov)
          if (c.reopened || c.paused)
            Text(
              [if (c.reopened) 'Adding sets', if (c.paused) 'Paused'].join(' · '),
              style: AppText.s(13, W.w5, color: c.paused ? AppColors.amberText : AppColors.muted),
            ),
        ]),
      );

  Widget _dotsBtn(VoidCallback onTap, String label) => Semantics(
        button: true,
        label: label,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            width: 36,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: h ? AppColors.accentSoft : AppColors.hover, borderRadius: BorderRadius.circular(8)),
            child: const AppIcon(AppIcons.dots, size: 18, color: AppColors.accent),
          ),
        ),
      );

  static const double _cancelH = 56;

  /// "Cancel workout" pinned at the bottom of the logger (Probid 2026-11-16: bottom of the screen, not in the page).
  /// Red text on a plain bar, asks first. After "Log more sets" it discards only the added sets.
  Widget _cancelLink(WorkoutController c, bool phone) => Container(
        padding: EdgeInsets.only(bottom: phone ? MediaQuery.paddingOf(context).bottom : 0),
        decoration: const BoxDecoration(color: AppColors.white, border: Border(top: BorderSide(color: AppColors.line))),
        child: SizedBox(
          height: _cancelH,
          child: Center(
            child: Semantics(
              button: true,
              label: c.reopened ? 'Discard the added sets' : 'Cancel workout',
              child: Hover(
                onTap: () => _askCancel(c),
                builder: (_, h, _) => Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: h ? AppColors.badBg : null, borderRadius: BorderRadius.circular(10)),
                  child: Text(c.reopened ? 'DISCARD ADDED SETS' : 'CANCEL WORKOUT', style: AppText.s(14, W.w8, color: AppColors.badText, ls: 1)),
                ),
              ),
            ),
          ),
        ),
      );

  // ─────────────────────────────── One exercise

  Widget _exercise(WorkoutController c, int i, {required bool web}) {
    final x = c.ex[i];
    final cols = c.cols(x);
    final f = c.focus[i];
    final sub = [
      if (x.kind == ExKind.cardio && x.bpmText.isNotEmpty) 'Target ${x.bpmText}',
      if (x.kind != ExKind.cardio) x.target,
      if (x.kind == ExKind.cardio && x.reps.isNotEmpty) x.reps,
    ].join(' · ');
    final pad = EdgeInsets.symmetric(horizontal: web ? 28 : 14);
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: pad, child: Row(spacing: 8, children: [
          Expanded(
            child: Semantics(
              button: true,
              label: 'How to do ${x.name}',
              child: Hover(
                onTap: () => _guide(c, x),
                builder: (_, h, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text(x.name, style: AppText.s(16, W.w6, color: AppColors.accentText).copyWith(decoration: h ? TextDecoration.underline : null)),
                  if (sub.isNotEmpty) Text(sub, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
                ]),
              ),
            ),
          ),
          if (x.kind == ExKind.weight)
            Builder(
              builder: (bc) => Semantics(
                button: true,
                label: 'Focus metric ${f.label}',
                child: Hover(
                  onTap: () => _focusMenu(bc, c, i),
                  builder: (_, h, _) => Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: h ? AppColors.accentRing : AppColors.accentSoft, borderRadius: BorderRadius.circular(8)),
                    child: Text(c.focusText(i, f), style: AppText.s(14, W.w6, color: AppColors.accentText, tabular: true)),
                  ),
                ),
              ),
            ),
          Builder(builder: (bc) => _dotsBtn(() => _exMenu(bc, c, i), '${x.name} options')),
        ])),
        const SizedBox(height: 10),
        Padding(padding: pad, child: _gridRow(c, x, cells: [
          _th('SET'),
          _th('PREVIOUS'),
          for (final h in cols) _th(h),
          if (x.kind == ExKind.time) const SizedBox(),
          const Center(child: AppIcon(AppIcons.check, size: 16, color: AppColors.text2, stroke: 2.4)),
        ])),
        const SizedBox(height: 4),
        for (var k = 0; k < c.sets[i].length; k++)
          KeyedSubtree(
            key: ValueKey(c.sets[i][k].key),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _row(c, i, k, web: web),
              if (_restRow(c, i, k) case final r?)
                // a done set's rest line sits inside its green row, edge to edge (Strong)
                Container(color: c.sets[i][k].done ? AppColors.logDoneRow : AppColors.white, padding: pad, child: r),
            ]),
          ),
        const SizedBox(height: 4),
        Center(
          child: Semantics(
            button: true,
            label: 'Add set to ${x.name}',
            child: Hover(
              onTap: () {
                setState(() => act = null);
                c.addSet(i);
              },
              builder: (_, h, _) => Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: h ? AppColors.accentSoft : null, borderRadius: BorderRadius.circular(10)),
                child: Text('ADD SET', style: AppText.s(14, W.w6, color: AppColors.accentText, ls: 1)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  /// SET 40 · PREVIOUS flex 5 · value boxes flex 4 each · [hold 40] · ✓ 40.
  Widget _gridRow(WorkoutController c, TrainEx x, {required List<Widget> cells}) {
    final n = c.cols(x).length;
    final out = <Widget>[];
    for (final (k, w) in cells.indexed) {
      if (k == 0) {
        out.add(SizedBox(width: 40, child: w));
      } else if (k == 1) {
        out.add(Expanded(flex: n == 1 ? 6 : 5, child: w));
      } else if (k < 2 + n) {
        out.add(Expanded(flex: 4, child: w));
      } else {
        out.add(SizedBox(width: 40, child: w));
      }
    }
    return Row(spacing: 6, children: out);
  }

  Widget _th(String t) => Text(t, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.clip, style: AppText.s(11, W.w7, color: AppColors.text, ls: 1.2));

  Widget _row(WorkoutController c, int i, int k, {required bool web}) {
    final x = c.ex[i], s = c.sets[i][k];
    final cols = c.cols(x);
    final hold = c.hold;
    final running = hold != null && hold.$1 == i && hold.$2 == k;
    final lbl = c.label(i, k);
    final labelColor = switch (s.kind) {
      SetKind.warmup => AppColors.amberText,
      SetKind.drop => AppColors.purpleText,
      SetKind.failure => AppColors.badText,
      SetKind.normal => AppColors.text,
    };
    final setCell = Builder(
      builder: (bc) => Semantics(
        button: true,
        label: 'Set $lbl options',
        child: Hover(
          onTap: () => _setMenu(bc, c, i, k),
          builder: (_, h, _) => Container(
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: h ? AppColors.logFieldHover : null, borderRadius: BorderRadius.circular(6)),
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
              Text(lbl, style: AppText.s(15, W.w6, color: labelColor)),
              if (c.isFilmed(s))
                Positioned(
                  right: -12,
                  top: -10,
                  child: Container(
                    width: 16,
                    height: 16,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle, border: Border.all(color: AppColors.white, width: 1.5)),
                    child: const AppIcon(AppIcons.camera, size: 9, color: AppColors.white),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
    final pt = c.prevText(i, k);
    final used = c.prevUsed(i, k);
    final prev = Semantics(
      button: pt.isNotEmpty && !s.done,
      label: pt.isEmpty ? 'No previous set' : 'Previous $pt',
      child: Hover(
        onTap: pt.isEmpty || s.done
            ? null
            : () {
                setState(() => act = null);
                c.usePrev(i, k);
              },
        builder: (_, h, _) => Container(
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: h && pt.isNotEmpty && !s.done ? AppColors.logFieldHover : null, borderRadius: BorderRadius.circular(6)),
          child: pt.isEmpty
              ? Container(width: 16, height: 2.5, decoration: BoxDecoration(color: AppColors.tickOff, borderRadius: BorderRadius.circular(2)))
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(pt, maxLines: 1, style: AppText.s(14, W.w4, color: used || s.done ? AppColors.valPh : AppColors.text)),
                ),
        ),
      ),
    );
    Widget tick = Semantics(
      button: true,
      label: s.done ? 'Untick set $lbl' : 'Tick set $lbl',
      child: Hover(
        onTap: () {
          setState(() => act = null);
          _tryTick(c, i, k);
        },
        builder: (_, h, _) => Container(
          width: 40,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: s.done ? AppColors.logDoneTick : (h ? AppColors.logFieldHover : AppColors.logField),
            borderRadius: BorderRadius.circular(6),
          ),
          child: AppIcon(AppIcons.check, size: 18, stroke: 2.4, color: s.done ? AppColors.white : (h ? AppColors.logDoneTick : AppColors.valPh)),
        ),
      ),
    );
    final sh = _shake;
    if (sh != null && sh.$1 == s.key) {
      tick = TweenAnimationBuilder<double>(
        key: ValueKey('shake:${sh.$2}'),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        builder: (_, v, child) => Transform.translate(offset: Offset(math.sin(v * math.pi * 6) * 6 * (1 - v), 0), child: child),
        child: tick,
      );
    }
    Widget? go;
    if (x.kind == ExKind.time) {
      go = s.done && !running
          ? const SizedBox()
          : Semantics(
              button: true,
              label: running ? 'Stop the hold timer' : 'Start the hold timer',
              child: Hover(
                onTap: () {
                  setState(() => act = null);
                  running ? c.stopHold() : c.startHold(i, k);
                },
                builder: (_, h, _) => Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: running ? AppColors.accent : (h ? AppColors.accentSoft : AppColors.logField), shape: BoxShape.circle),
                  child: AppIcon(running ? AppIcons.stop : AppIcons.play, size: 15, color: running ? AppColors.white : AppColors.accent),
                ),
              ),
            );
    }
    final row = Container(
      padding: EdgeInsets.symmetric(horizontal: web ? 28 : 14, vertical: 6),
      color: s.done ? AppColors.logDoneRow : AppColors.white,
      child: _gridRow(c, x, cells: [
        setCell,
        prev,
        for (var j = 0; j < cols.length; j++) _box(c, i, k, j, web: web, holdLeft: running && j == 0 ? hold.$3 : null),
        ?go,
        tick,
      ]),
    );
    return Dismissible(
      key: _rowKeys.putIfAbsent(s.key, GlobalKey.new),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.red,
        child: const AppIcon(AppIcons.trash, size: 20, color: AppColors.white),
      ),
      // a set with values or ticked asks first; an empty one goes at once with Undo (tracker G46)
      confirmDismiss: (_) async => !(s.touched || s.done) || await _askDeleteSet(c, i, k),
      onDismissed: (_) {
        setState(() => act = null);
        c.deleteSet(i, k);
      },
      child: row,
    );
  }

  Future<bool> _askDeleteSet(WorkoutController c, int i, int k) async {
    var yes = false;
    await _ask(
      title: 'Delete set ${c.label(i, k)}?',
      sub: '${c.ex[i].name} · ${c.setLine(i, k)}',
      body: _p(c.sets[i][k].done ? 'This set is ticked. It is removed from the workout.' : 'The values you typed are removed.'),
      buttons: (ctx) => [
        CaButton('Keep it', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
        _dangerBtn('Delete set', () {
          yes = true;
          Navigator.of(ctx).pop();
        }),
      ],
    );
    return yes;
  }

  // ─────────────────────────────── Rest under a set (tracker G45, G46)

  static String _restText(int v) => v == 0 ? 'Off' : clockText(v);

  static String _restsLine(({int work, int warmup, int drop}) r) =>
      'Work ${_restText(r.work)} · Warm-up ${_restText(r.warmup)} · Drop ${_restText(r.drop)}';

  /// The thin line under a set with its rest ("1:30"). While that rest runs it fills and counts down; after it shows
  /// what was really rested. Tap = change the rest of this set; swipe left = no rest after this set.
  Widget? _restRow(WorkoutController c, int i, int k) {
    final s = c.sets[i][k];
    final planned = c.restFor(i, k);
    final running = c.rest > 0 && c.restAt == (i, k);
    // rest removed (swipe / Off) = no line at all, even if some rest had already run (Probid 17 Nov)
    if (planned == 0 && !running) return null;
    final locked = c.ex[i].restLocked;
    final own = s.rest != null;
    // after a skip or the end it keeps showing the set's rest, not "rested 0:02" (Probid 17 Nov);
    // the real rest is still saved for history (G49)
    final label = running ? clockText(c.rest) : clockText(planned);
    final p = running && c.restMax > 0 ? (c.rest / c.restMax).clamp(0.0, 1.0) : 0.0;
    final g = s.done; // on a done set the line is part of the green row, in green (Strong)
    final text = own && !running ? '$label · this set' : label;
    final bar = Semantics(
      button: true,
      label: running ? 'Rest ${clockText(c.rest)} left, open the rest timer' : 'Rest after set ${c.label(i, k)}: $label',
      child: Hover(
        onTap: () {
          setState(() => act = null);
          if (running) {
            c.restShow(true);
          } else {
            _setRest(c, i, k);
          }
        },
        // Thin and close to the sets (Probid 16 Nov). While it runs the line itself empties from right to left.
        builder: (_, h, _) => SizedBox(
          height: g ? 24 : 18,
          width: double.infinity,
          child: Stack(alignment: Alignment.center, children: [
            Positioned(
              left: 0,
              right: 0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Stack(children: [
                  Container(height: running ? 4 : 2, color: g ? AppColors.doneValLine : (running ? AppColors.accentSoft : AppColors.accentRing)),
                  if (running) FractionallySizedBox(widthFactor: p, child: Container(height: 4, color: g ? AppColors.logDoneTick : AppColors.accent)),
                ]),
              ),
            ),
            Container(
              height: g && running ? 20 : 16,
              constraints: const BoxConstraints(minWidth: 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: g ? AppColors.logDoneRow : (running ? AppColors.accent : (h ? AppColors.accentSoft : AppColors.white)),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Center(
                widthFactor: 1,
                child: Text(text,
                    style: AppText.s(g && running ? 15 : 12, g ? W.w6 : W.w7, h: 1,
                        color: g ? AppColors.okText : (running ? AppColors.white : AppColors.accentText), tabular: true)),
              ),
            ),
          ]),
        ),
      ),
    );
    if (locked && !running) return bar;
    // Swipe left: a running rest is skipped, otherwise there is no rest after this set (Undo).
    return Dismissible(
      key: ValueKey('rest:${s.key}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: running ? AppColors.accentSoft : AppColors.badBg,
        child: Text(running ? 'Skip rest' : 'No rest', style: AppText.s(11.5, W.w7, color: running ? AppColors.accentText : AppColors.badText)),
      ),
      confirmDismiss: (_) async {
        if (running) {
          c.restSkip();
        } else {
          final before = s.rest;
          c.setSetRest(i, k, 0);
          _toast('Rest removed', sub: 'No rest after set ${c.label(i, k)}', kind: ToastKind.del, undo: () => c.setSetRest(i, k, before));
        }
        return false;
      },
      child: bar,
    );
  }

  /// Rest line tap, set menu → Rest timer for this set (G45): change this set's rest and / or start it now (Probid 16 Nov).
  void _setRest(WorkoutController c, int i, int k) {
    final s = c.sets[i][k];
    final locked = c.ex[i].restLocked;
    var v = c.restFor(i, k);
    final own = s.rest != null;
    _ask(
      title: 'Rest after set ${c.label(i, k)}',
      sub: '${c.ex[i].name} · only this set',
      body: locked
          ? _p('${c.plan.coachFirst} set this rest: ${_restText(v)}. You can start it now.')
          : StatefulBuilder(
              builder: (_, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
                _RestStepper(value: v, onChanged: (n) => set(() => v = n)),
                if (own)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Builder(
                      builder: (bc) => Hover(
                        onTap: () {
                          Navigator.of(bc).pop();
                          c.setSetRest(i, k, null);
                        },
                        builder: (_, h, _) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text('Use exercise rest (${_restText(c.restFor(i, k, own: false))})',
                              style: AppText.s(13, W.w7, color: h ? AppColors.accent : AppColors.accentText)),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
      buttons: (ctx) => [
        CaButton('Start now', kind: CaBtnKind.out, icon: AppIcons.play, onPressed: () {
          Navigator.of(ctx).pop();
          if (!locked && v != c.restFor(i, k)) c.setSetRest(i, k, v);
          c.restStart(i, k, v == 0 ? null : v);
        }),
        if (!locked)
          CaButton('Save', icon: AppIcons.check, onPressed: () {
            Navigator.of(ctx).pop();
            c.setSetRest(i, k, v);
          }),
      ],
    );
  }

  /// Top rest chip with no rest running: pick a time and start it.
  void _restIdle(WorkoutController c) {
    final i = c.cur;
    var v = c.rests[i].work > 0 ? c.rests[i].work : 90;
    _ask(
      title: 'Rest timer',
      sub: c.ex[i].name,
      body: StatefulBuilder(builder: (_, set) => _RestStepper(value: v, onChanged: (n) => set(() => v = n))),
      buttons: (ctx) => [
        CaButton('Cancel', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
        CaButton('Start', icon: AppIcons.play, onPressed: () {
          Navigator.of(ctx).pop();
          if (v > 0) c.restNow(i, v);
        }),
      ],
    );
  }

  /// Rest sheet → Change: a new length for the rest that is running.
  void _restChange(WorkoutController c) {
    var v = c.restMax;
    _ask(
      title: 'Change rest',
      sub: 'Time passed stays passed',
      body: StatefulBuilder(builder: (_, set) => _RestStepper(value: v, onChanged: (n) => set(() => v = n))),
      buttons: (ctx) => [
        CaButton('Cancel', kind: CaBtnKind.out, onPressed: () {
          Navigator.of(ctx).pop();
          if (c.rest > 0) c.restShow(true);
        }),
        CaButton('Save', icon: AppIcons.check, onPressed: () {
          Navigator.of(ctx).pop();
          c.restEdit(v);
          if (c.rest > 0) c.restShow(true);
        }),
      ],
    );
  }

  /// Exercise ⋯ → Rest timers (G44): working, warm-up and drop sets. Used from now on and next time too.
  void _restTimers(WorkoutController c, int i) {
    final x = c.ex[i];
    var r = c.rests[i];
    if (x.restLocked) {
      _ask(
        title: 'Rest timers',
        sub: x.name,
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          _p('${c.plan.coachFirst} set the rest for this exercise, so it cannot be changed here.'),
          _p(_restsLine(r)),
        ]),
        buttons: (ctx) => [CaButton('OK', onPressed: () => Navigator.of(ctx).pop())],
      );
      return;
    }
    Widget line(String t, String sub, int v, ValueChanged<int> on) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
          Row(children: [
            Expanded(child: Text(t, style: AppText.s(14, W.w7))),
            Text(sub, style: AppText.s(12, W.w5, color: AppColors.muted)),
          ]),
          _RestStepper(value: v, onChanged: on),
        ]);
    _ask(
      title: 'Rest timers',
      sub: '${x.name} · this workout and next time',
      body: StatefulBuilder(
        builder: (_, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
          line('Working sets', 'normal and failure', r.work, (n) => set(() => r = (work: n, warmup: r.warmup, drop: r.drop))),
          line('Warm-up sets', 'W', r.warmup, (n) => set(() => r = (work: r.work, warmup: n, drop: r.drop))),
          line('Drop sets', 'D', r.drop, (n) => set(() => r = (work: r.work, warmup: r.warmup, drop: n))),
        ]),
      ),
      buttons: (ctx) => [
        CaButton('Cancel', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
        CaButton('Save', icon: AppIcons.check, onPressed: () {
          Navigator.of(ctx).pop();
          c.setRests(i, work: r.work, warmup: r.warmup, drop: r.drop);
        }),
      ],
    );
  }

  /// One number box. Done: plain text on the green row. Phone: tap opens the keypad; tablet / web: a text field.
  Widget _box(WorkoutController c, int i, int k, int j, {required bool web, int? holdLeft}) {
    final x = c.ex[i], s = c.sets[i][k];
    final v = c.value(x, s, j);
    final ph = c.placeholder(i, k, j);
    final head = c.cols(x)[j];
    if (holdLeft != null) {
      return Container(
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.accent)),
        child: Text('0:${'$holdLeft'.padLeft(2, '0')}', style: AppText.s(15, W.w8, color: AppColors.accent, tabular: true)),
      );
    }
    if (s.done) {
      return SizedBox(
        height: 30,
        child: Center(child: Text(c.fmt(x, j, v ?? ph ?? 0), style: AppText.s(16, W.w5, tabular: true))),
      );
    }
    if (web) {
      return _NumBox(
        key: ValueKey('nb:${s.key}:$j'),
        value: v == null ? '' : c.fmt(x, j, v),
        hint: ph == null ? '' : c.fmt(x, j, ph),
        decimal: c.decimal(x, j),
        negative: x.kind == ExKind.weight && j == 0 && (s.bw || x.bodyweight),
        label: '$head, set ${c.label(i, k)}',
        onChanged: (t) => c.setValue(i, k, j, t.isEmpty ? null : double.tryParse(t)),
        onSubmit: () => _tryTick(c, i, k),
      );
    }
    final on = act == (i, k, j);
    final text = on && !_fresh ? _buf : (v == null ? '' : c.fmt(x, j, v));
    return Semantics(
      button: true,
      label: '$head, set ${c.label(i, k)}: ${text.isEmpty ? (ph == null ? 'empty' : c.fmt(x, j, ph)) : text}',
      child: Hover(
        onTap: () => _activate(c, (i, k, j)),
        builder: (_, h, _) => Container(
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.white : AppColors.logField,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: on ? AppColors.text : (h ? AppColors.line2 : Colors.transparent), width: on ? 1.5 : 1),
          ),
          child: on ? _editing(text, ph == null ? '' : c.fmt(x, j, ph)) : Text(
            text.isNotEmpty ? text : (ph == null ? '' : c.fmt(x, j, ph)),
            maxLines: 1,
            style: AppText.s(16, W.w5, color: text.isNotEmpty ? AppColors.text : AppColors.valPh, tabular: true),
          ),
        ),
      ),
    );
  }

  /// The box being typed in, like a real text field (Probid 17 Nov): just opened = the value is selected (the first
  /// key replaces it), then the digits with a blinking cursor after them.
  Widget _editing(String text, String hint) {
    final style = AppText.s(16, W.w5, tabular: true);
    if (_fresh && text.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        color: AppColors.accentRing,
        child: Text(text, maxLines: 1, style: style),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (text.isNotEmpty) Text(text, maxLines: 1, style: style),
      const _Caret(),
      if (text.isEmpty && hint.isNotEmpty) Text(hint, maxLines: 1, style: style.copyWith(color: AppColors.valPh)),
    ]);
  }

  // ─────────────────────────────── Phone keypad (F36)

  void _activate(WorkoutController c, _Cell cell) {
    final (i, k, j) = cell;
    final v = c.value(c.ex[i], c.sets[i][k], j);
    setState(() {
      act = cell;
      _fresh = true;
      _buf = v == null ? '' : c.fmt(c.ex[i], j, v);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(cell));
  }

  /// Keeps the active row above the keypad.
  void _reveal(_Cell cell) {
    final c = w;
    if (c == null || cell.$1 >= c.sets.length || cell.$2 >= c.sets[cell.$1].length) return;
    final ctx = _rowKeys[c.sets[cell.$1][cell.$2].key]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, alignment: .35, duration: const Duration(milliseconds: 160));
  }

  final _rowKeys = <String, GlobalKey>{};

  void _key(WorkoutController c, String key) {
    final a = act;
    if (a == null) return;
    final (i, k, j) = a;
    final x = c.ex[i];
    var b = _fresh ? '' : _buf;
    if (key == '⌫') {
      b = b.isEmpty ? '' : b.substring(0, b.length - 1);
    } else if (key == '.') {
      if (!c.decimal(x, j) || b.contains('.')) return;
      b = b.isEmpty ? '0.' : '$b.';
    } else {
      if (b.replaceAll('.', '').length >= 6) return;
      b = b == '0' ? key : '$b$key';
    }
    setState(() {
      _buf = b;
      _fresh = false;
    });
    c.setValue(i, k, j, b.isEmpty || b == '0.' ? null : double.tryParse(b));
  }

  void _step(WorkoutController c, int dir) {
    final a = act;
    if (a == null) return;
    final (i, k, j) = a;
    c.stepValue(i, k, j, dir);
    final v = c.value(c.ex[i], c.sets[i][k], j);
    setState(() {
      _fresh = true;
      _buf = v == null ? '' : c.fmt(c.ex[i], j, v);
    });
  }

  /// NEXT: the next box of this set, then the next set's first box, then the next exercise.
  void _next(WorkoutController c) {
    final a = act;
    if (a == null) return;
    var (i, k, j) = a;
    final n = c.cols(c.ex[i]).length;
    if (j + 1 < n) {
      _activate(c, (i, k, j + 1));
      return;
    }
    while (true) {
      k += 1;
      while (i < c.ex.length && k >= c.sets[i].length) {
        i += 1;
        k = 0;
      }
      if (i >= c.ex.length) {
        setState(() => act = null);
        return;
      }
      if (!c.sets[i][k].done) break;
    }
    _activate(c, (i, k, 0));
  }

  Widget _keypad(WorkoutController c) {
    final a = act!;
    final x = c.ex[a.$1];
    final dec = c.decimal(x, a.$3);
    Widget key(String t, {Widget? child, VoidCallback? onTap, String? label, bool tall = false, Color? bg, Color? fg}) => Semantics(
          button: true,
          label: label ?? t,
          child: Hover(
            onTap: onTap ?? () => _key(c, t),
            builder: (_, h, _) => Container(
              height: 50,
              margin: const EdgeInsets.all(3),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: h ? AppColors.pressed : (bg ?? Colors.transparent), borderRadius: BorderRadius.circular(10)),
              child: child ?? Text(t, style: AppText.s(22, W.w5, color: fg ?? AppColors.text)),
            ),
          ),
        );
    Widget side(Widget child) => SizedBox(width: 76, child: child);
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    final sideKeys = [
      key('', label: 'Hide the keypad', bg: AppColors.sub, onTap: () => setState(() => act = null), child: const AppIcon(AppIcons.chevronDown, size: 20, color: AppColors.text2)),
      Container(
        height: 50,
        margin: const EdgeInsets.all(3),
        child: Row(children: [
          Expanded(child: key('−', label: 'Less', onTap: () => _step(c, -1), child: const AppIcon(AppIcons.minus, size: 18, color: AppColors.text))),
          Expanded(child: key('+', label: 'More', onTap: () => _step(c, 1), child: const AppIcon(AppIcons.plus, size: 18, color: AppColors.text))),
        ]),
      ),
      key('RPE', label: 'Set RPE', bg: AppColors.sub, onTap: () => _rpe(c, a.$1, a.$2), child: Text(c.sets[a.$1][a.$2].rpe == null ? 'RPE' : 'RPE ${kg(c.sets[a.$1][a.$2].rpe!)}', style: AppText.s(13, W.w7, color: AppColors.text2))),
    ];
    return Container(
      padding: EdgeInsets.fromLTRB(8, 6, 8, 6 + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.line)), boxShadow: AppShadows.barUp),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(children: [
            for (final row in rows)
              Row(children: [for (final t in row) Expanded(child: key(t))]),
            Row(children: [
              Expanded(child: dec ? key('.') : const SizedBox(height: 56)),
              Expanded(child: key('0')),
              Expanded(child: key('⌫', label: 'Delete', child: const AppIcon(AppIcons.close, size: 20, color: AppColors.text2))),
            ]),
          ]),
        ),
        side(Column(children: [
          ...sideKeys,
          key('NEXT', label: 'Next box', bg: AppColors.accent, onTap: () => _next(c), child: Text('NEXT', style: AppText.s(14, W.w8, color: AppColors.white, ls: 1))),
        ])),
      ]),
    );
  }

  /// RPE of a set: 6 to 10 in halves (tracker: keypad RPE key).
  void _rpe(WorkoutController c, int i, int k) {
    final cur = c.sets[i][k].rpe;
    showAppSheet(
      context,
      title: 'RPE for set ${c.label(i, k)}',
      sub: 'How hard was it? 10 = no reps left',
      builder: (ctx) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (var r = 6.0; r <= 10; r += .5)
          Hover(
            onTap: () {
              Navigator.of(ctx).pop();
              c.setRpe(i, k, r);
            },
            builder: (_, h, _) => Container(
              width: 56,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cur == r ? AppColors.accent : (h ? AppColors.outlineHover : AppColors.white),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cur == r ? AppColors.accent : AppColors.line),
              ),
              child: Text(kg(r), style: AppText.s(14, W.w7, color: cur == r ? AppColors.white : AppColors.text)),
            ),
          ),
        if (cur != null)
          CaButton('Clear', kind: CaBtnKind.out, small: true, expand: false, onPressed: () {
            Navigator.of(ctx).pop();
            c.setRpe(i, k, null);
          }),
      ]),
    );
  }

  // ─────────────────────────────── Menus

  void _guide(WorkoutController c, TrainEx e) => showGuide(
        context,
        e,
        GuideInfo(context: '${c.name} · Exercise ${e.index + 1} of ${c.ex.length}', program: c.plan.program, coachFirst: c.plan.coachFirst, coachInitials: c.plan.coachInitials),
      );

  /// Title ⋯: pause / resume the clock, restart. (Cancel workout is at the end of the page.)
  void _workoutMenu(BuildContext anchor, WorkoutController c) {
    setState(() => act = null);
    _popover(anchor, width: 230, builder: (ctx, close) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _mi(c.paused ? 'Resume timer' : 'Pause timer', icon: c.paused ? AppIcons.play : AppIcons.pause, onTap: () {
            close();
            c.pauseToggle();
          }),
          _mi('Restart workout', icon: AppIcons.restart, sub: 'Untick every set, timer from 0:00', onTap: () {
            close();
            _askRestart(c);
          }),
        ]));
  }

  /// Exercise ⋯ for a client (Probid 2026-11-16): no Replace / Remove / Superset; the plan is the coach's.
  void _exMenu(BuildContext anchor, WorkoutController c, int i) {
    setState(() => act = null);
    final x = c.ex[i];
    _popover(anchor, width: 250, right: true, builder: (ctx, close) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _mi('How to do it', icon: AppIcons.help, onTap: () {
            close();
            _guide(c, x);
          }),
          _mi('Past workouts', icon: AppIcons.clock, sub: 'See and use sets from before', onTap: () {
            close();
            showExerciseHistory(context, x, onUse: (sets, from) => c.fillFrom(i, sets, from: from));
          }),
          _mi('Rest timers', icon: AppIcons.clockAlt, sub: x.restLocked ? 'Set by ${c.plan.coachFirst}' : _restsLine(c.rests[i]), onTap: () {
            close();
            _restTimers(c, i);
          }),
          if (c.rests[i].work > 0)
            _mi('Start rest timer now', icon: AppIcons.play, sub: clockText(c.rests[i].work), onTap: () {
              close();
              c.restNow(i);
            }),
          if (x.kind == ExKind.weight)
            _mi('Focus metric', icon: AppIcons.target, sub: c.focus[i].label, onTap: () {
              close();
              _focusMenu(anchor, c, i);
            }),
        ]));
  }

  /// The chip beside ⋯: what the client watches while lifting (F40). Kept for this exercise next time too.
  void _focusMenu(BuildContext anchor, WorkoutController c, int i) {
    setState(() => act = null);
    _popover(anchor, width: 260, right: true, builder: (ctx, close) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: Text('FOCUS METRIC', style: AppText.s(11, W.w8, color: AppColors.muted, ls: 1)),
          ),
          for (final f in FocusMetric.values)
            Hover(
              onTap: () {
                close();
                c.setFocus(i, f);
              },
              builder: (_, h, _) => Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: h ? AppColors.hover : null, borderRadius: BorderRadius.circular(8)),
                child: Row(spacing: 8, children: [
                  SizedBox(width: 18, child: c.focus[i] == f ? const AppIcon(AppIcons.check, size: 16, color: AppColors.accent, stroke: 2.4) : null),
                  Expanded(child: Text(f.label, style: AppText.s(13.5, W.w6))),
                  Text(c.focusText(i, f), style: AppText.s(13, W.w7, color: AppColors.text2, tabular: true)),
                ]),
              ),
            ),
        ]));
  }

  static const _kindInfo = {
    SetKind.warmup: ('Warm up', 'A light set to get ready. It is not counted in volume or personal bests.'),
    SetKind.drop: ('Drop set', 'Right after a set, lower the weight and keep going with no rest.'),
    SetKind.failure: ('Failure', 'You went until you could not do one more rep with good form.'),
  };

  /// SET box: set type (W / D / F, each with ?), use last time, bodyweight, form video, RPE, delete (F38, F39, F41).
  void _setMenu(BuildContext anchor, WorkoutController c, int i, int k) {
    setState(() => act = null);
    final x = c.ex[i], s = c.sets[i][k];
    final vid = c.videoOf(s);
    Widget kind(SetKind t, Color color) {
      final (name, info) = _kindInfo[t]!;
      final on = s.kind == t;
      return Builder(
        builder: (rowCtx) => Hover(
          onTap: () {
            Navigator.of(rowCtx).pop();
            c.setKind(i, k, t);
          },
          builder: (_, h, _) => Container(
            height: 40,
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(color: on ? AppColors.accentSoft : (h ? AppColors.hover : null), borderRadius: BorderRadius.circular(8)),
            child: Row(spacing: 10, children: [
              SizedBox(width: 16, child: Text(t.letter, textAlign: TextAlign.center, style: AppText.s(14, W.w8, color: color))),
              Expanded(child: Text(on ? '$name (tap to undo)' : name, style: AppText.s(13.5, W.w6))),
              Semantics(
                button: true,
                label: 'What is a $name?',
                child: Hover(
                  onTap: () => _tip(rowCtx, name, info),
                  builder: (_, hh, _) => Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: hh ? AppColors.pressed : null, shape: BoxShape.circle),
                    child: const AppIcon(AppIcons.help, size: 16, color: AppColors.muted),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    }

    _popover(anchor, width: 260, builder: (ctx, close) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: Text('SET TYPE', style: AppText.s(11, W.w8, color: AppColors.muted, ls: 1)),
          ),
          kind(SetKind.warmup, AppColors.amberText),
          kind(SetKind.drop, AppColors.purpleText),
          kind(SetKind.failure, AppColors.badText),
          const Divider(height: 10, color: AppColors.line),
          if (x.lastTime.isNotEmpty)
            _mi('Use last time', icon: AppIcons.undo, sub: x.lastText, onTap: () {
              close();
              c.fillFrom(i, x.lastTime);
            }),
          if (x.kind == ExKind.weight)
            _mi(s.bw ? 'Use a weight' : 'Bodyweight', icon: AppIcons.person, sub: s.bw ? 'Type the kg again' : 'Body weight + any added kg', onTap: () {
              close();
              c.toggleBw(i, k);
            }),
          if (x.kind == ExKind.weight && !s.wu)
            _mi(s.rpe == null ? 'RPE' : 'RPE ${kg(s.rpe!)}', icon: AppIcons.pulse, sub: 'How hard the set was', onTap: () {
              close();
              _rpe(c, i, k);
            }),
          if (!x.restLocked)
            _mi('Rest timer for this set', icon: AppIcons.clockAlt, sub: s.rest == null ? 'Now ${_restText(c.restFor(i, k))} (exercise rest)' : 'This set: ${_restText(s.rest!)}', onTap: () {
              close();
              _setRest(c, i, k);
            }),
          _mi(vid == null ? 'Form video' : 'Change form video', icon: AppIcons.camera, sub: vid == null ? 'Film this set for ${c.plan.coachFirst}' : vid.name, onTap: () {
            close();
            _formVideo(anchor, c, i, k);
          }),
          if (vid != null)
            _mi('Remove video', icon: AppIcons.close, onTap: () {
              close();
              c.removeVideo(vid);
            }),
          _mi('Delete set', icon: AppIcons.trash, danger: true, onTap: () {
            close();
            c.deleteSet(i, k);
          }),
        ]));
  }

  void _tip(BuildContext anchor, String title, String text) => _popover(anchor,
      width: 260,
      right: true,
      builder: (ctx, close) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
              Text(title, style: AppText.s(13.5, W.w8)),
              Text(text, style: AppText.s(12.5, W.w5, color: AppColors.text2, h: 1.45)),
            ]),
          ));

  /// Form video (F41): record or pick a clip for this set; it is sent to the coach when the workout is finished.
  void _formVideo(BuildContext anchor, WorkoutController c, int i, int k) {
    Future<void> pick(ImageSource src) async {
      try {
        final x = await ImagePicker().pickVideo(source: src, maxDuration: const Duration(seconds: 60));
        if (x == null) return;
        final size = await x.length();
        if (size > 100 * 1024 * 1024) {
          _toast('This video is too big', sub: 'Up to 100 MB. Film just one set.', kind: ToastKind.warn);
          return;
        }
        final name = x.name.contains('.') ? x.name : '${x.name}.mp4';
        if (k >= c.sets[i].length) return;
        c.pickVideo(i, k, path: x.path, name: name, bytes: kIsWeb ? await x.readAsBytes() : null);
      } catch (_) {
        _toast('Could not open the camera', sub: 'Allow camera and video access for the app in your phone settings', kind: ToastKind.warn);
      }
    }

    if (kIsWeb) {
      pick(ImageSource.gallery);
      return;
    }
    _popover(anchor, width: 240, builder: (ctx, close) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _mi('Record a video', icon: AppIcons.camera, sub: 'Up to 60 seconds', onTap: () {
            close();
            pick(ImageSource.camera);
          }),
          _mi('Choose a video', icon: AppIcons.video, sub: 'From your gallery', onTap: () {
            close();
            pick(ImageSource.gallery);
          }),
        ]));
  }

  // ─────────────────────────────── Finish, restart, cancel

  void _askFinish(WorkoutController c) {
    setState(() => act = null);
    final left = c.setsAll - c.setsDone;
    final coach = c.plan.coachFirst;
    final n = c.videos.length;
    _ask(
      title: 'Finish workout?',
      sub: '${c.setsDone} of ${c.setsAll} sets done · ${clockText(c.elapsed)}',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        _p(left == 0
            ? 'Nice, every set is done. $coach sees your workout as soon as you finish.'
            : '$left ${left == 1 ? 'set is' : 'sets are'} not ticked yet. They are saved as skipped, and $coach sees what you did.'),
        // Each exercise with its sets, so the client sees what is done here (the page behind is dimmed; Probid 16 Nov).
        Container(
          constraints: const BoxConstraints(maxHeight: 260),
          decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(12)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, x) in c.ex.indexed) _finishRow(c, i, x, last: i == c.ex.length - 1),
            ]),
          ),
        ),
        if (n > 0) _p('$n form ${n == 1 ? 'video goes' : 'videos go'} to $coach now.'),
      ]),
      buttons: (ctx) => [
        CaButton('Keep going', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
        CaButton('Finish', icon: AppIcons.check, onPressed: () {
          Navigator.of(ctx).pop();
          _finish(c);
        }),
      ],
    );
  }

  /// One line of the Finish sheet: ✓ (all done), half (some) or empty, the exercise and "2 of 4 sets".
  Widget _finishRow(WorkoutController c, int i, TrainEx x, {required bool last}) {
    final work = c.sets[i].where((s) => !s.wu).toList();
    final done = work.where((s) => s.done).length;
    final all = work.isNotEmpty && done == work.length;
    final some = done > 0 && !all;
    final vids = c.videos.where((v) => c.sets[i].any((s) => s.key == v.setKey)).length;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(spacing: 10, children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: all ? AppColors.okSolid : (some ? AppColors.amberBg : AppColors.white),
            shape: BoxShape.circle,
            border: Border.all(color: all ? AppColors.okSolid : (some ? AppColors.amberText : AppColors.line2)),
          ),
          child: all
              ? const AppIcon(AppIcons.check, size: 13, stroke: 2.8, color: AppColors.white)
              : (some ? Text('$done', style: AppText.s(11, W.w8, color: AppColors.amberText)) : null),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
            CutText(x.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(14, W.w7)),
            if (vids > 0) Text('$vids form ${vids == 1 ? 'video' : 'videos'}', style: AppText.s(12, W.w5, color: AppColors.muted)),
          ]),
        ),
        Text(done == 0 ? 'Skipped' : '$done of ${work.length} sets',
            style: AppText.s(13, W.w7, color: all ? AppColors.okText : (some ? AppColors.amberText : AppColors.muted), tabular: true)),
      ]),
    );
  }

  void _finish(WorkoutController c, {int? at}) {
    if (c.finished) return;
    setState(() => act = null);
    c.finish(at: at, read: (p) => XFile(p).readAsBytes());
    if (at != null) _toast('Workout saved', sub: 'Time set to ${clockText(at)}, your last set', kind: ToastKind.star);
  }

  void _askRestart(WorkoutController c) {
    final n = c.setsDone;
    final msg = '${n == 0 ? 'The' : (n == 1 ? 'Your 1 ticked set goes back to not done and the' : 'All $n ticked sets go back to not done and the')}'
        ' timer starts again from 0:00.';
    _ask(
      title: 'Restart workout?',
      sub: '${c.name} · ${clockText(c.elapsed)} so far',
      body: _p(msg),
      buttons: (ctx) => [
        CaButton('Keep going', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
        CaButton('Restart', icon: AppIcons.restart, onPressed: () {
          Navigator.of(ctx).pop();
          setState(() => act = null);
          c.restart();
        }),
      ],
    );
  }

  /// Cancel workout (bottom of the page): nothing is saved. After "Log more sets" only the added sets go.
  void _askCancel(WorkoutController c) {
    setState(() => act = null);
    final again = c.reopened;
    _ask(
      title: again ? 'Discard the added sets?' : 'Cancel workout?',
      sub: again ? 'Your finished workout stays as it was' : '${c.setsDone} sets ticked · ${clockText(c.elapsed)}',
      body: _p(again
          ? 'The sets you added now are not saved.'
          : 'Nothing from this workout is saved and the timer stops. ${c.plan.coachFirst} will not see it.'),
      buttons: (ctx) => [
        CaButton('Keep going', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
        _dangerBtn(again ? 'Discard sets' : 'Cancel workout', () async {
          Navigator.of(ctx).pop();
          await c.discard();
          if (mounted) _leave('/train?discarded=${again ? 2 : 1}');
        }),
      ],
    );
  }

  // ─────────────────────────────── Popovers and sheets

  Future<void> _popover(BuildContext anchor, {required double width, bool right = false, required Widget Function(BuildContext ctx, VoidCallback close) builder}) {
    final box = anchor.findRenderObject() as RenderBox;
    final overlay = Overlay.of(anchor, rootOverlay: true).context.findRenderObject() as RenderBox;
    final tl = box.localToGlobal(Offset.zero, ancestor: overlay);
    final size = overlay.size;
    final left = right ? tl.dx + box.size.width - width : tl.dx;
    final top = tl.dy + box.size.height + 6;
    return showGeneralDialog(
      context: anchor,
      barrierDismissible: true,
      barrierLabel: 'menu',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 90),
      transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      pageBuilder: (ctx, _, _) => Stack(children: [
        Positioned(
          left: left.clamp(8.0, math.max(8.0, size.width - width - 8)),
          top: top,
          width: math.min(width, size.width - 16),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(6),
              constraints: BoxConstraints(maxHeight: size.height - top - 12),
              decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line), boxShadow: AppShadows.menu),
              child: SingleChildScrollView(child: builder(ctx, () => Navigator.of(ctx).pop())),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _mi(String title, {AppIconData? icon, String? sub, bool danger = false, required VoidCallback onTap}) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: sub == null ? 7 : 8),
          decoration: BoxDecoration(color: h ? (danger ? AppColors.badBg : AppColors.hover) : null, borderRadius: BorderRadius.circular(8)),
          child: Row(crossAxisAlignment: sub == null ? CrossAxisAlignment.center : CrossAxisAlignment.start, spacing: 10, children: [
            if (icon != null) Padding(padding: EdgeInsets.only(top: sub == null ? 0 : 2), child: AppIcon(icon, size: 16, color: danger ? AppColors.badText : AppColors.text2)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text(title, style: AppText.s(13.5, W.w6, color: danger ? AppColors.badText : AppColors.text)),
                if (sub != null) Text(sub, style: AppText.s(12, W.w4, color: AppColors.muted)),
              ]),
            ),
          ]),
        ),
      );


  Widget _dangerBtn(String label, VoidCallback onTap) => Hover(
        onTap: onTap,
        builder: (ctx, h, _) {
          final web = CaWeb.of(ctx);
          return Container(
            height: web ? 40 : 44,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: h ? AppColors.badText : AppColors.red, borderRadius: BorderRadius.circular(web ? 10 : 12)),
            child: CutText(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(web ? 14 : 14.5, W.w7, color: AppColors.white)),
          );
        },
      );


  /// A question sheet: message and two buttons side by side (`cl-ebtns`).
  Future<void> _ask({required String title, String? sub, Widget? body, required List<Widget> Function(BuildContext ctx) buttons}) => showAppSheet(
        context,
        title: title,
        sub: sub,
        webWidth: 440,
        builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          ?body,
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(spacing: 8, children: [for (final b in buttons(ctx)) Expanded(child: b)]),
          ),
        ]),
      );

  Widget _p(String t) => Text(t, style: AppText.s(14, W.w4, color: AppColors.text2, h: 1.5));


  Future<void> _askIdle() async {
    final c = w;
    if (c == null || !mounted) return;
    final at = c.lastTickAt;
    final mins = (c.elapsed - c.lastActive) ~/ 60;
    var answered = false;
    await _ask(
      title: 'Still working out?',
      sub: 'No set ticked for $mins min · timer at ${clockText(c.elapsed)}',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        if (at != null)
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Your last set was at '),
              TextSpan(text: clockText(at), style: const TextStyle(fontWeight: W.w7, color: AppColors.text)),
              const TextSpan(text: '. Finish there so the extra minutes don’t count.'),
            ]),
            style: AppText.s(14, W.w4, color: AppColors.text2, h: 1.5),
          )
        else
          _p('You haven’t ticked a set yet.'),
        Text('If you don’t answer, the workout is saved at your last set after 3 hours.', style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.45)),
      ]),
      buttons: (ctx) => [
        CaButton('Keep going', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
        CaButton(at != null ? 'Finish at ${clockText(at)}' : 'Finish workout', onPressed: () {
          answered = true;
          Navigator.of(ctx).pop();
          if (at != null) {
            _finish(c, at: at);
          } else {
            c.keepGoing();
            _askFinish(c);
          }
        }),
      ],
    );
    if (!answered && !c.finished) c.keepGoing();
    _idleUp = false;
  }


  // ─────────────────────────────── Rest bar (`cl-rest`)

  // ─────────────────────────────── Rest sheet (tracker G48)

  /// Opens by itself when a set with rest is ticked. Phone: a sheet at the bottom; web: a card in the middle.
  /// X (or a tap outside, or back) only hides it: the rest goes on in the bar, the mini bar and the notification.
  void _openRest() {
    final c = w;
    if (c == null || !mounted || _restRoute != null || !c.restOpen || c.rest == 0) return;
    final web = !context.isPhone;
    final route = RawDialogRoute(
      barrierDismissible: true,
      barrierLabel: 'Rest timer',
      barrierColor: AppColors.scrimSheet,
      transitionDuration: const Duration(milliseconds: 180),
      transitionBuilder: (_, a, _, child) => web
          ? FadeTransition(opacity: a, child: child)
          : SlideTransition(
              position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
              child: child,
            ),
      pageBuilder: (ctx, _, _) => Align(
        alignment: web ? Alignment.center : Alignment.bottomCenter,
        child: Material(
          color: Colors.transparent,
          child: CaWeb(
            web: web,
            child: GestureDetector(
              onVerticalDragEnd: (d) {
                if (!web && (d.primaryVelocity ?? 0) > 250) c.restShow(false);
              },
              child: ListenableBuilder(listenable: c, builder: (ctx, _) => _restDialog(ctx, c, web: web)),
            ),
          ),
        ),
      ),
    );
    _restRoute = route;
    Navigator.of(context, rootNavigator: true).push(route).then((_) {
      if (_restRoute == route) {
        _restRoute = null;
        if (c.restOpen) c.restShow(false);
      }
    });
  }

  Widget _restDialog(BuildContext ctx, WorkoutController c, {required bool web}) {
    final at = c.restAt;
    final sub = '${c.ex[at.$1].name}${at.$2 >= 0 && at.$2 < c.sets[at.$1].length ? ' · after set ${c.label(at.$1, at.$2)}' : ''}';
    final p = c.restMax == 0 ? 0.0 : (c.rest / c.restMax).clamp(0.0, 1.0);
    Widget round(String label, String tip, VoidCallback onTap, {AppIconData? icon, bool dark = false, double size = 56}) => AppTooltip(
          message: tip,
          child: Semantics(
            button: true,
            label: tip,
            child: Hover(
              onTap: onTap,
              builder: (_, h, _) => Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: dark ? (h ? AppColors.text2 : AppColors.text) : (h ? AppColors.pressed : AppColors.sub),
                  shape: BoxShape.circle,
                ),
                child: icon != null
                    ? AppIcon(icon, size: size * .4, color: dark ? AppColors.white : AppColors.text)
                    : Text(label, style: AppText.s(15, W.w8, color: dark ? AppColors.white : AppColors.text, tabular: true)),
              ),
            ),
          ),
        );
    return Container(
      width: web ? 400 : double.infinity,
      margin: web ? const EdgeInsets.all(16) : EdgeInsets.zero,
      padding: EdgeInsets.fromLTRB(18, web ? 16 : 10, 18, 18 + (web ? 0 : MediaQuery.paddingOf(ctx).bottom)),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: web ? BorderRadius.circular(20) : const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: AppShadows.dialogBig,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, spacing: 14, children: [
        if (!web) Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.line2, borderRadius: BorderRadius.circular(4))),
        Row(spacing: 10, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.restPaused ? 'Rest · paused' : 'Rest timer', style: AppText.s(16, W.w8)),
              CutText(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
            ]),
          ),
          CaIconBtn(AppIcons.close, tooltip: 'Hide (the rest keeps running)', onTap: () => c.restShow(false)),
        ]),
        SizedBox(
          width: 220,
          height: 220,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(child: CustomPaint(painter: _Ring(p))),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(clockText(c.rest), style: AppText.s(56, W.w8, ls: -1, h: 1, tabular: true)),
              const SizedBox(height: 6),
              Text(c.restPaused ? 'Paused' : 'of ${clockText(c.restMax)}', style: AppText.s(13, W.w6, color: AppColors.muted)),
            ]),
          ]),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 14, children: [
          round('−15', 'Take off 15 seconds', c.restLess),
          round('', c.restPaused ? 'Resume' : 'Pause', c.restToggle, icon: c.restPaused ? AppIcons.play : AppIcons.pause, dark: true, size: 68),
          round('+15', 'Add 15 seconds', () => c.restMore()),
        ]),
        Row(spacing: 8, children: [
          if (!c.ex[at.$1].restLocked) Expanded(child: CaButton('Edit', kind: CaBtnKind.out, icon: AppIcons.edit, onPressed: () {
            c.restShow(false);
            _restChange(c);
          })),
          Expanded(child: CaButton('Reset', kind: CaBtnKind.out, icon: AppIcons.restart, onPressed: c.restReset)),
          Expanded(child: CaButton('Skip', icon: AppIcons.next, onPressed: c.restSkip)),
        ]),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(10)),
          child: Row(spacing: 8, children: [
            const AppIcon(AppIcons.arrowRight, size: 15, color: AppColors.muted),
            Expanded(child: Text('Next up', style: AppText.s(12.5, W.w4, color: AppColors.muted))),
            Flexible(flex: 3, child: CutText(c.nextUp, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w7))),
          ]),
        ),
      ]),
    );
  }

  // ─────────────────────────────── Congratulations (finish page, F)

  static const _quick = ['Felt easy today', 'Short on sleep', 'Had to slow down'];

  Widget _doneView(WorkoutController c, bool phone) {
    final coach = c.plan.coachFirst;
    final total = c.finalSeconds;
    final rest = math.min(c.restUsed, total), active = math.max(0, total - rest);
    final eff = c.effort;
    final effL = eff == 0 ? 'Tap a number' : '$eff of 10 · ${eff <= 3 ? 'easy' : eff <= 6 ? 'moderate' : eff <= 8 ? 'hard' : 'very hard'}';
    Widget card(List<Widget> kids, {double gap = 10}) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: gap, children: kids),
        );
    Widget q(String t) => Text(t, style: AppText.s(15, W.w8));
    final n = c.workoutNumber;
    final fmt = NumberFormat.decimalPattern('en_IN');
    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
        child: Column(spacing: 4, children: [
          Container(
            width: 64,
            height: 64,
            margin: const EdgeInsets.only(bottom: 8),
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppColors.accentSoft, spreadRadius: 8)]),
            child: const AppIcon(AppIcons.star, size: 30, color: AppColors.white),
          ),
          Text('Congratulations!', style: AppText.s(24, W.w8)),
          Text(n == null ? 'Workout saved' : 'That’s your ${_nth(n)} workout!', textAlign: TextAlign.center, style: AppText.s(14, W.w6, color: AppColors.text2)),
        ]),
      ),
      // The workout card (Strong's finish page): name, date, time, volume, bests, each exercise with its best set.
      card([
        Text(c.name, style: AppText.s(17, W.w8)),
        Text(DateFormat('EEEE, d MMMM y').format(c.date), style: AppText.s(13, W.w5, color: AppColors.muted)),
        Wrap(spacing: 16, runSpacing: 6, children: [
          _fact(AppIcons.clock, clockText(total)),
          if (c.volume > 0) _fact(AppIcons.dumbbell, '${fmt.format(c.volume.round())} kg'),
          if (c.prs > 0) _fact(AppIcons.award, '${c.prs} ${c.prs == 1 ? 'PR' : 'PRs'}'),
          _fact(AppIcons.check, '${c.setsDone}/${c.setsAll} sets'),
        ]),
        if (c.summary.isNotEmpty)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
            Row(children: [
              Expanded(child: Text('Exercise', style: AppText.s(12.5, W.w8, color: AppColors.text2))),
              Text('Best set', style: AppText.s(12.5, W.w8, color: AppColors.text2)),
            ]),
            for (final r in c.summary)
              Row(spacing: 10, children: [
                Expanded(child: CutText(r.line, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w5, color: AppColors.text2))),
                Text(r.best, style: AppText.s(13.5, W.w6, tabular: true)),
              ]),
          ]),
      ], gap: 8),
      card([
        q('Where the time went'),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: Container(
            height: 10,
            color: AppColors.sub,
            child: Row(children: [
              if (active > 0) Expanded(flex: active, child: Container(color: AppColors.accent)),
              if (rest > 0) Expanded(flex: rest, child: Container(color: AppColors.restAmber)),
              if (active + rest == 0) const Spacer(),
            ]),
          ),
        ),
        Row(spacing: 16, children: [
          _leg(AppColors.accent, 'Active', clockText(active)),
          _leg(AppColors.restAmber, 'Rest', clockText(rest)),
        ]),
        Column(children: [
          for (final (i, x) in c.ex.indexed) _exTime(c, i, x),
        ]),
        Text('$coach sees the same times with your workout.', style: AppText.s(12.5, W.w4, color: AppColors.muted)),
      ]),
      card([
        q('How hard was it?'),
        Row(spacing: 4, children: [
          for (var n = 1; n <= 10; n++)
            Expanded(
              child: Semantics(
                button: true,
                selected: eff == n,
                label: 'Effort $n of 10',
                child: Hover(
                  onTap: c.sent
                      ? null
                      : () {
                          c.effort = n;
                          c.changed(save: false);
                        },
                  builder: (_, h, _) => Container(
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: eff == n ? AppColors.accent : (h ? AppColors.outlineHover : AppColors.white),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: eff == n ? AppColors.accent : AppColors.line),
                    ),
                    child: Text('$n', style: AppText.s(14, W.w8, color: eff == n ? AppColors.white : AppColors.text)),
                  ),
                ),
              ),
            ),
        ]),
        Transform.translate(
          offset: const Offset(0, -4),
          child: Row(children: [
            Text('Easy', style: AppText.s(12, W.w6, color: AppColors.muted)),
            Expanded(child: Text(effL, textAlign: TextAlign.center, style: AppText.s(12, W.w7))),
            Text('Max', style: AppText.s(12, W.w6, color: AppColors.muted)),
          ]),
        ),
      ]),
      card([
        q('Note for $coach'),
        TextField(
          controller: _note,
          enabled: !c.sent,
          minLines: 2,
          maxLines: 5,
          maxLength: 500,
          onChanged: (v) {
            c.note = v;
            c.changed(save: false);
          },
          style: AppText.s(14, W.w6),
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            hintText: 'Add a note for $coach (optional)',
            hintStyle: AppText.s(14, W.w4, color: AppColors.muted),
            filled: true,
            fillColor: AppColors.caWebBg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line)),
            disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.accent)),
          ),
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in _quick)
            Hover(
              onTap: c.sent
                  ? null
                  : () {
                      _note.text = t;
                      c.note = t;
                      c.changed(save: false);
                    },
              builder: (_, h, _) {
                final on = c.note == t;
                return Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: on ? AppColors.text : (h ? AppColors.outlineHover : AppColors.white),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: on ? AppColors.text : AppColors.line),
                  ),
                  child: Center(widthFactor: 1, child: Text(t, style: AppText.s(12.5, W.w7, color: on ? AppColors.white : AppColors.text))),
                );
              },
            ),
        ]),
      ]),
      if (!c.sent)
        CaButton('Save and send to $coach', icon: AppIcons.send, onPressed: () => _send(c))
      else
        ChNote(
          icon: AppIcons.checkCircle,
          bg: AppColors.okBg,
          fg: AppColors.okText,
          child: Text('Sent to $coach. You will usually get a reply within a few hours.', style: AppText.s(13, W.w7, color: AppColors.okText)),
        ),
      CaButton('Back to home', kind: CaBtnKind.out, onPressed: () => _leave('/home')),
    ]);
    if (phone) return SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 24), child: content);
    return CaWeb(
      web: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 72),
        child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620), child: content)),
      ),
    );
  }

  static String _nth(int n) {
    final t = n % 100;
    final suf = (t >= 11 && t <= 13) ? 'th' : switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
    return '$n$suf';
  }

  Widget _fact(AppIconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
        AppIcon(icon, size: 15, color: AppColors.muted),
        Text(text, style: AppText.s(13, W.w6, color: AppColors.text2, tabular: true)),
      ]);

  Widget _leg(Color color, String label, String value) => Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        Text.rich(
          TextSpan(children: [TextSpan(text: '$label '), TextSpan(text: value, style: const TextStyle(fontWeight: W.w8, color: AppColors.text))]),
          style: AppText.s(13, W.w6, color: AppColors.muted),
        ),
      ]);

  Widget _exTime(WorkoutController c, int i, TrainEx x) {
    final xs = c.sets[i];
    final done = xs.where((s) => s.done).toList();
    final t = c.exTime(i);
    final machine = x.kind == ExKind.cardio && t != null ? ' · ${(done.fold(0, (a, s) => a + (s.seconds ?? 0)) / 60).round()} min on the machine' : '';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      child: Row(spacing: 10, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(x.name, style: AppText.s(14, W.w7)),
            Text('${done.length} of ${xs.length} ${xs.length == 1 ? 'set' : 'sets'}$machine', style: AppText.s(12.5, W.w4, color: AppColors.muted)),
          ]),
        ),
        t == null
            ? Text('Skipped', style: AppText.s(13, W.w6, color: AppColors.muted))
            : Text(clockText(t), style: AppText.s(15, W.w8, tabular: true)),
      ]),
    );
  }

  Future<void> _send(WorkoutController c) async {
    if (!await c.send()) {
      _toast('Pick how hard it was', sub: 'Tap a number from 1 to 10', kind: ToastKind.warn);
      return;
    }
    _toast('Sent to ${c.plan.coachFirst}', sub: 'Effort ${c.effort} of 10${c.note.trim().isNotEmpty ? ' · with your note' : ''}', kind: ToastKind.ok);
  }
}

/// A number box on tablet and web (`TextField`): placeholder in grey, Enter ticks the set.
class _NumBox extends StatefulWidget {
  const _NumBox({super.key, required this.value, required this.hint, required this.decimal, required this.negative, required this.label, required this.onChanged, required this.onSubmit});
  final String value, hint, label;
  final bool decimal, negative;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  @override
  State<_NumBox> createState() => _NumBoxState();
}

class _NumBoxState extends State<_NumBox> {
  late final _c = TextEditingController(text: widget.value);
  final _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(() {
      if (_f.hasFocus) _c.selection = TextSelection(baseOffset: 0, extentOffset: _c.text.length);
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(_NumBox old) {
    super.didUpdateWidget(old);
    // a value set from outside (Use last time, Undo, +/−) shows unless the client is typing in this box
    if (!_f.hasFocus && widget.value != _c.text) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pat = widget.decimal ? (widget.negative ? r'^-?\d{0,4}(\.\d{0,2})?$' : r'^\d{0,4}(\.\d{0,2})?$') : r'^\d{0,4}$';
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.transparent));
    return SizedBox(
      height: 32,
      child: Semantics(
        label: widget.label,
        textField: true,
        child: TextField(
          controller: _c,
          focusNode: _f,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal, signed: widget.negative),
          inputFormatters: [_Keep(RegExp(pat))],
          textInputAction: TextInputAction.done,
          onChanged: widget.onChanged,
          onSubmitted: (_) => widget.onSubmit(),
          style: AppText.s(16, W.w5, tabular: true),
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hint,
            hintStyle: AppText.s(16, W.w5, color: AppColors.valPh, tabular: true),
            filled: true,
            fillColor: _f.hasFocus ? AppColors.white : AppColors.logField,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            border: border,
            enabledBorder: border,
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
          ),
        ),
      ),
    );
  }
}

/// Keeps the old text when a paste would not match the box's number pattern.
class _Keep extends TextInputFormatter {
  _Keep(this.re);
  final RegExp re;
  @override
  TextEditingValue formatEditUpdate(TextEditingValue a, TextEditingValue b) => re.hasMatch(b.text) ? b : a;
}

/// `cr-ring`: grey track and the blue arc of rest left.
class _Ring extends CustomPainter {
  _Ring(this.p);
  final double p;
  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.width - 12) / 2;
    final c = size.center(Offset.zero);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = AppColors.track;
    canvas.drawCircle(c, r, track);
    if (p <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = AppColors.accent;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * p, false, arc);
  }

  @override
  bool shouldRepaint(_Ring old) => old.p != p;
}

/// Blinking text cursor for the logger's own number boxes.
class _Caret extends StatefulWidget {
  const _Caret();
  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();
  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        builder: (_, _) => Opacity(
          opacity: _a.value < .5 ? 1 : 0,
          child: Container(width: 2, height: 18, margin: const EdgeInsets.symmetric(horizontal: 1), color: AppColors.accent),
        ),
      );
}

/// Rest length: − 1:30 + in 15-second steps (0 = Off, up to 15:00), with quick picks (tracker G44/G45).
class _RestStepper extends StatelessWidget {
  const _RestStepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  static const _quick = [0, 30, 60, 90, 120, 180];

  @override
  Widget build(BuildContext context) {
    Widget pm(AppIconData icon, String label, int by) => Semantics(
          button: true,
          label: label,
          child: Hover(
            onTap: () => onChanged((value + by).clamp(0, 900)),
            builder: (_, h, _) => Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: h ? AppColors.pressed : AppColors.sub, borderRadius: BorderRadius.circular(12)),
              child: AppIcon(icon, size: 18, color: AppColors.text),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      Row(spacing: 10, children: [
        pm(AppIcons.minus, 'Less rest', -15),
        Expanded(
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
            child: Text(value == 0 ? 'Off' : clockText(value), style: AppText.s(20, W.w8, tabular: true)),
          ),
        ),
        pm(AppIcons.plus, 'More rest', 15),
      ]),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final q in _quick)
          Hover(
            onTap: () => onChanged(q),
            builder: (_, h, _) => Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: value == q ? AppColors.accent : (h ? AppColors.outlineHover : AppColors.white),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: value == q ? AppColors.accent : AppColors.line),
              ),
              child: Center(widthFactor: 1, child: Text(q == 0 ? 'Off' : clockText(q), style: AppText.s(12.5, W.w7, color: value == q ? AppColors.white : AppColors.text))),
            ),
          ),
      ]),
    ]);
  }
}
