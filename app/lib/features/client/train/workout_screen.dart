import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../app/shell/back_nav.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/animated_rows.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../home/home_parts.dart';
import 'train_model.dart';
import 'train_parts.dart';
import 'workout_model.dart';
import '../../../core/widgets/tooltip.dart';

/// Workout logger (boards `ClientWorkout` phone and `ClientWorkoutWeb`): one exercise at a time,
/// sets with −/+ values and ticks, rest timer, workout timer, finish and the "Workout done" page.
/// [start] = program day to start, [reopen] = finished workout to log more sets on.
class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key, this.start, this.reopen, this.then});
  final int? start;
  final String? reopen;

  /// Opened from the Train banner ⋯: `finish` or `restart` opens that question at once.
  final String? then;

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  final train = TrainController();
  WorkoutController? w;
  String? _err;

  /// Value being changed on the current exercise: (set, column).
  (int, int)? act;
  int _actEx = -1;

  RawDialogRoute? _restRoute;

  /// Phone: toasts sit above the timer / rest bar while the logger is open.
  double? _lifted;
  bool _idleUp = false;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await train.start();
    final d = train.data;
    if (!mounted) return;
    if (d == null) {
      final e = train.error;
      setState(() => _err = e == null ? 'Could not load your plan.' : (e.offline ? 'You are offline. Connect to open your workout.' : e.message));
      return;
    }
    final c = WorkoutController(d)..toast = _toast;
    c.addListener(_onW);
    setState(() => w = c);
    await c.open(start: widget.start, reopen: widget.reopen);
    if (!mounted) return;
    setState(() {});
    if (c.ready && !c.finished) {
      if (widget.then == 'finish') _askFinish(c);
      if (widget.then == 'restart') _askRestart(c);
    }
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
    w?.removeListener(_onW);
    w?.dispose();
    train.dispose();
    _note.dispose();
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
    if (c.cur != _actEx) {
      act = null;
      _actEx = c.cur;
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
      c.finish(at: at ?? c.elapsed);
      _toast('Workout saved', sub: at == null ? '${c.setsDone} of ${c.setsAll} sets' : 'Time set to ${clockText(at)}, your last set', kind: ToastKind.star);
    } else if (c.idle && !_idleUp) {
      _idleUp = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _askIdle());
    }
  }

  // ─────────────────────────────── Page

  /// The phone's back button closes the rest panel first, then goes back to the Train overview (Phase 4).
  @override
  Widget build(BuildContext context) => BackIntercept(
    onBack: () {
      final c = w;
      if (c == null || !c.restOpen) return false;
      c.restShow(false);
      return true;
    },
    child: Builder(builder: _page),
  );

  Widget _page(BuildContext context) {
    final c = w;
    if (_err != null || (c != null && c.failed != null)) return _problem(_err ?? c!.failed!);
    if (c == null || !c.ready) {
      return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent)));
    }
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final phone = context.isPhone;
        _lift(phone && !c.finished ? 75 + 66 : null);
        if (c.finished) return _doneView(c, phone);
        return phone ? _phone(c) : _web(c);
      },
    );
  }

  Widget _problem(String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, spacing: 10, children: [
            Text('Could not open the workout', style: AppText.s(15, W.w7)),
            Text(msg, textAlign: TextAlign.center, style: AppText.s(13, W.w4, color: AppColors.muted)),
            CaButton('Back to Train', kind: CaBtnKind.out, expand: false, onPressed: () => context.go('/train')),
          ]),
        ),
      );

  Widget _phone(WorkoutController c) {
    final resting = c.rest > 0;
    return Stack(children: [
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 92),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          _top(c, web: false),
          _pager(c),
          _panel(c, web: false),
        ]),
      ),
      Positioned(left: 0, right: 0, bottom: 0, child: resting ? _restBar(c, web: false) : _timerBar(c)),
    ]);
  }

  Widget _web(WorkoutController c) => CaWeb(
        web: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 72),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: LayoutBuilder(builder: (context, box) {
                final side = box.maxWidth >= 760;
                final right = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
                  if (!side) _pager(c),
                  _panel(c, web: true),
                  if (c.rest > 0) _restBar(c, web: true),
                ]);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
                  _top(c, web: true),
                  if (side)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
                      SizedBox(width: 280, child: _sideList(c)),
                      Expanded(child: right),
                    ])
                  else
                    right,
                ]);
              }),
            ),
          ),
        ),
      );

  // ─────────────────────────────── Top bar (`cl-top`)

  Widget _top(WorkoutController c, {required bool web}) => Padding(
        padding: EdgeInsets.symmetric(vertical: web ? 4 : 0),
        child: Row(spacing: 10, children: [
          CaIconBtn(AppIcons.chevronLeft, tooltip: 'Back to overview', onTap: () => context.go('/train')),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              CutText(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(web ? 22 : 17, W.w8)),
              Row(spacing: 5, children: [
                Builder(builder: (bc) => _timeChip(c, () => web ? _timerPop(bc, c) : _timerSheet(c))),
                Flexible(child: CutText('· ${c.setsDone} of ${c.setsAll} sets', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.muted))),
              ]),
            ]),
          ),
          Builder(builder: (bc) => CaIconBtn(AppIcons.dots, tooltip: 'Workout options', onTap: () => _menu(bc, c))),
          CaButton('Finish', small: true, expand: false, onPressed: () => _askFinish(c)),
        ]),
      );

  /// `cl-time`: the running clock, opens the timer.
  Widget _timeChip(WorkoutController c, VoidCallback onTap) => Semantics(
        button: true,
        label: 'Workout timer ${clockText(c.elapsed)}',
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(color: c.paused ? AppColors.amberBg : (h ? AppColors.pressed : AppColors.sub), borderRadius: BorderRadius.circular(6)),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
              AppIcon(c.paused ? AppIcons.pause : AppIcons.clock, size: 13, color: c.paused ? AppColors.amberText : AppColors.text),
              Text(clockText(c.elapsed), style: AppText.s(12.5, W.w7, color: c.paused ? AppColors.amberText : AppColors.text, tabular: true)),
            ]),
          ),
        ),
      );

  // ─────────────────────────────── Exercise switcher

  Widget _badge(WorkoutController c, int i, {required bool on}) {
    final done = c.exDone(i);
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: done ? AppColors.okSolid : (on ? AppColors.accent : AppColors.sub), borderRadius: BorderRadius.circular(7)),
      child: done
          ? const AppIcon(AppIcons.check, size: 13, color: AppColors.white, stroke: 2.8)
          : Text('${i + 1}', style: AppText.s(12, W.w8, color: on ? AppColors.white : AppColors.text2)),
    );
  }

  /// Phone: `cl-pager` chips.
  Widget _pager(WorkoutController c) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(spacing: 6, children: [
          for (final (i, x) in c.ex.indexed)
            Hover(
              onTap: () => c.goTo(i),
              builder: (_, h, _) {
                final on = i == c.cur;
                return Container(
                  height: 36,
                  padding: const EdgeInsets.fromLTRB(6, 0, 12, 0),
                  decoration: BoxDecoration(
                    color: h && !on ? AppColors.outlineHover : AppColors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: on ? AppColors.text : AppColors.line, width: on ? 2 : 1),
                  ),
                  child: Row(spacing: 7, children: [
                    _badge(c, i, on: on),
                    Text(x.name, style: AppText.s(13, on ? W.w7 : W.w6, color: on ? AppColors.text : AppColors.text2)),
                  ]),
                );
              },
            ),
        ]),
      );

  /// Web: `cl-side` list.
  Widget _sideList(WorkoutController c) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
          for (final (i, x) in c.ex.indexed)
            Hover(
              onTap: () => c.goTo(i),
              builder: (_, h, _) {
                final on = i == c.cur;
                return Container(
                  height: 42,
                  padding: const EdgeInsets.fromLTRB(6, 0, 12, 0),
                  decoration: BoxDecoration(color: on ? AppColors.sub : (h ? AppColors.outlineHover : null), borderRadius: BorderRadius.circular(10)),
                  child: Row(spacing: 7, children: [
                    _badge(c, i, on: on),
                    Expanded(child: CutText(x.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, on ? W.w7 : W.w6, color: on ? AppColors.text : AppColors.text2))),
                  ]),
                );
              },
            ),
        ]),
      );

  // ─────────────────────────────── Exercise panel (`cl-panel`)

  String _hint(WorkoutController c, TrainEx e) {
    final each = e.reps.contains('each side') ? ' each side' : '';
    switch (e.kind) {
      case ExKind.weight:
        final vol = c.sets[c.cur].fold(0.0, (a, s) => a + c.setVolume(s));
        final bw = c.plan.bodyweight;
        return 'Volume so far ${NumberFormat.decimalPattern('en_IN').format(vol.round())} kg'
            '${bw == null ? '' : ' · BW = ${kg(bw)} kg (last weigh-in)'}. Tap BW on a set to log bodyweight; − / + adds load or assistance.';
      case ExKind.time:
        final held = c.sets[c.cur].where((s) => s.done).fold(0, (a, s) => a + (s.seconds ?? 0));
        return 'Hold so far $held s$each. Tap ▶ to time the hold: it counts down and ticks the set at 0. Or tap the time to change it and tick it yourself.';
      case ExKind.cardio:
        return 'Log the time and distance from the machine screen. Speed and incline come from ${c.plan.coachFirst}’s target.';
    }
  }

  Widget _panel(WorkoutController c, {required bool web}) {
    final e = c.e, n = c.ex.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${e.blockName} · ${c.cur + 1} of $n'.toUpperCase(), style: AppText.s(11.5, W.w8, color: AppColors.accentText, ls: .575)),
              const SizedBox(height: 2),
              Text(e.name, style: AppText.s(20, W.w8)),
            ]),
          ),
          if (e.prText.isNotEmpty)
            Container(
              height: 24,
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(color: AppColors.okBg, borderRadius: BorderRadius.circular(7)),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
                const AppIcon(AppIcons.star, size: 12, color: AppColors.okText),
                Text('PR ${e.prText}', style: AppText.s(12, W.w8, color: AppColors.okText)),
              ]),
            ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 0),
          child: Transform.translate(offset: const Offset(0, -8), child: Text('Target ${e.target}', style: AppText.s(13, W.w6, color: AppColors.text2))),
        ),
        Transform.translate(
          offset: const Offset(0, -8),
          child: Row(spacing: 6, children: [
            if (e.rest > 0) CaButton('Rest ${e.rest}s', small: true, expand: false, kind: CaBtnKind.out, icon: AppIcons.clock, onPressed: c.restNow),
            CaButton('How to do it', small: true, expand: false, kind: CaBtnKind.out, icon: AppIcons.play, onPressed: () => _guide(c, e)),
            const Spacer(),
            Builder(
              builder: (bc) => Semantics(
                button: true,
                label: 'How to log this',
                child: Hover(
                  onTap: () => _tip(bc, _hint(c, e), web: web),
                  builder: (_, h, _) => Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: h ? AppColors.sub : null, shape: BoxShape.circle),
                    child: const AppIcon(AppIcons.infoAlt, size: 17, color: AppColors.muted),
                  ),
                ),
              ),
            ),
          ]),
        ),
        Transform.translate(offset: const Offset(0, -8), child: _box(c, e, web: web)),
        _nav(c),
      ]),
    );
  }

  void _guide(WorkoutController c, TrainEx e) => showGuide(
        context,
        e,
        GuideInfo(context: '${c.name} · Exercise ${e.index + 1} of ${c.ex.length}', program: c.plan.program, coachFirst: c.plan.coachFirst, coachInitials: c.plan.coachInitials),
      );

  Widget _nav(WorkoutController c) {
    final last = c.cur == c.ex.length - 1;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(spacing: 8, children: [
        CaButton('Previous', kind: CaBtnKind.out, expand: false, icon: AppIcons.chevronLeft, dimmed: c.cur == 0, onPressed: c.cur == 0 ? null : () => c.goTo(c.cur - 1)),
        Expanded(
          child: last
              ? CaButton('Finish workout', icon: AppIcons.check, onPressed: () => _askFinish(c))
              : CaButton('Next exercise', kind: CaBtnKind.dark, trailingIcon: AppIcons.chevronRight, onPressed: () => c.goTo(c.cur + 1)),
        ),
      ]),
    );
  }

  // ─────────────────────────────── Sets box (`cl-box`)

  List<Widget> _grid(WorkoutController c, TrainEx e, {required bool web, required List<Widget> cells}) {
    // cells: set, [prev], value columns..., [go], tick
    final widths = <int?>[];
    widths.add(web ? 44 : 34);
    if (web) widths.add(84);
    final cols = c.cols(e).length;
    for (var j = 0; j < cols; j++) {
      widths.add(null);
    }
    if (e.kind == ExKind.time) widths.add(web ? 44 : 40);
    widths.add(web ? 44 : 40);
    final flex = switch (e.kind) {
      ExKind.weight => web ? [3, 2] : [1, 0],
      ExKind.cardio => [1, 1],
      ExKind.time => [1],
    };
    var fi = 0;
    return [
      for (final (i, cell) in cells.indexed)
        if (widths[i] != null)
          SizedBox(width: widths[i]!.toDouble(), child: cell)
        else if (flex[fi++] == 0)
          SizedBox(width: 92, child: cell)
        else
          Expanded(flex: flex[fi - 1], child: cell),
    ];
  }

  Widget _box(WorkoutController c, TrainEx e, {required bool web}) {
    final xs = c.sets[c.cur];
    final cols = c.cols(e);
    final allBw = xs.isNotEmpty && xs.every((s) => s.bw);
    var wn = 0;
    final rows = <Widget>[];
    for (final (k, s) in xs.indexed) {
      if (!s.wu) wn += 1;
      rows.add(KeyedSubtree(key: ValueKey(s.key), child: _setRow(c, e, k, s, s.wu ? 'W' : '$wn', s.wu ? 'Warm-up' : c.prev(e, wn - 1), web: web)));
      final a = act;
      if (!web && a != null && a.$1 == k) rows.add(KeyedSubtree(key: ValueKey('strip:${s.key}'), child: _strip(c, e, s, a.$2)));
    }
    return Container(
      padding: web ? const EdgeInsets.symmetric(horizontal: 16, vertical: 14) : const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        if (e.kind == ExKind.weight)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Expanded(child: Text('Load', style: AppText.s(13.5, W.w7))),
              _seg(['kg', 'Bodyweight'], allBw ? 1 : 0, (i) => c.loadAll(bw: i == 1)),
            ]),
          ),
        Row(spacing: 6, children: _grid(c, e, web: web, cells: [
          _th('Set', left: true),
          if (web) _th('Prev', left: true),
          for (final h in cols) _th(h),
          if (e.kind == ExKind.time) const SizedBox(),
          const SizedBox(),
        ])),
        // a set added or removed grows in / folds away (Phase 5)
        AnimatedRows(spacing: 8, children: rows),
        Row(children: [
          Hover(
            onTap: () {
              setState(() => act = null);
              c.addSet();
            },
            builder: (_, h, _) => Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: h ? AppColors.accent : AppColors.line)),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                AppIcon(AppIcons.plus, size: 16, color: h ? AppColors.accentText : AppColors.text2),
                Text('Add set', style: AppText.s(13.5, W.w7, color: h ? AppColors.accentText : AppColors.text2)),
              ]),
            ),
          ),
          const Spacer(),
          // One tap: every set not ticked yet takes last time's values, ready to change and tick.
          if (e.lastTime.isNotEmpty && xs.any((s) => !s.done && !s.wu))
            Hover(
              onTap: () {
                setState(() => act = null);
                c.fillFrom(e.lastTime);
              },
              builder: (_, h, _) => Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: h ? AppColors.accentSoft : null, borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                  const AppIcon(AppIcons.restart, size: 15, color: AppColors.accent),
                  Text('Use last time', style: AppText.s(13.5, W.w7, color: AppColors.accentText)),
                ]),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _th(String t, {bool left = false}) => Padding(
        padding: EdgeInsets.only(left: left ? 4 : 0),
        child: Text(t, textAlign: left ? TextAlign.left : TextAlign.center, maxLines: 1, style: AppText.s(11, W.w7, color: AppColors.muted)),
      );

  /// `cl-seg`: kg / Bodyweight.
  Widget _seg(List<String> labels, int on, ValueChanged<int> pick) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (i, l) in labels.indexed)
            Hover(
              onTap: () => pick(i),
              builder: (_, h, _) => Container(
                height: 30,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: i == on ? AppColors.text : null, borderRadius: BorderRadius.circular(8)),
                child: Text(l, style: AppText.s(13, i == on ? W.w7 : W.w6, color: i == on ? AppColors.white : (h ? AppColors.text : AppColors.text2))),
              ),
            ),
        ]),
      );

  Widget _setRow(WorkoutController c, TrainEx e, int k, WSet s, String lbl, String prev, {required bool web}) {
    final hold = c.hold;
    final running = hold != null && hold.$1 == c.cur && hold.$2 == k;
    final cols = c.cols(e);
    final sn = Builder(
      builder: (bc) => Semantics(
        button: true,
        label: 'Set $lbl options',
        child: Hover(
          onTap: () => _setMenu(bc, c, k),
          builder: (_, h, _) => Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: s.wu ? AppColors.amberBg : (s.done ? AppColors.avGreenBg : AppColors.sub),
              borderRadius: BorderRadius.circular(9),
              border: h ? Border.all(color: AppColors.text2, width: 1.5) : null,
            ),
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
              Text(lbl, style: AppText.s(13, W.w8, color: s.wu ? AppColors.amberText : (s.done ? AppColors.avGreenText : AppColors.text2))),
              // Form video sent for this set
              if (c.isFilmed(s))
                Positioned(
                  right: -9,
                  top: -9,
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
    Widget cell(int j) {
      final a = act;
      final on = a != null && a.$1 == k && a.$2 == j;
      final text = running ? '0:${hold.$3.toString().padLeft(2, '0')}' : c.text(s, j, e);
      final ph = !(s.touched || s.done || running) && c.value(e, s, j) == null;
      final h = web ? 42.0 : 40.0;
      Widget val;
      if (web && on) {
        val = Container(
          height: h,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
          child: Row(children: [
            _pm(AppIcons.minus, 'Less', () => c.step(k, j, -1)),
            Expanded(child: Text(text, textAlign: TextAlign.center, maxLines: 1, style: AppText.s(15, W.w8, tabular: true))),
            _pm(AppIcons.plus, 'More', () => c.step(k, j, 1)),
          ]),
        );
      } else {
        val = Semantics(
          button: true,
          label: '${cols[j]} $text',
          child: Hover(
            onTap: () => setState(() => act = on ? null : (k, j)),
            builder: (_, hv, _) => Container(
              height: h,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: running ? AppColors.accentSoft : (s.done ? AppColors.doneValBg : (on || hv ? AppColors.white : AppColors.caWebBg)),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: running || on || hv ? AppColors.accent : (s.done ? AppColors.doneValLine : AppColors.line)),
                boxShadow: on ? const [BoxShadow(color: AppColors.accentSoft, spreadRadius: 2)] : null,
              ),
              child: Text(text, maxLines: 1, style: AppText.s(15, W.w8, color: running ? AppColors.accent : (ph ? AppColors.valPh : AppColors.text), tabular: true)),
            ),
          ),
        );
      }
      if (e.kind == ExKind.weight && j == 0) {
        return Row(spacing: 5, children: [
          Semantics(
            button: true,
            label: 'Bodyweight',
            selected: s.bw,
            child: Hover(
              onTap: () {
                c.toggleBw(k);
                setState(() => act = (k, 0));
              },
              builder: (_, hv, _) => Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s.bw ? AppColors.accent : (hv ? AppColors.outlineHover : AppColors.white),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: s.bw ? AppColors.accent : AppColors.line),
                ),
                child: Text('BW', style: AppText.s(10.5, W.w8, color: s.bw ? AppColors.white : AppColors.text2)),
              ),
            ),
          ),
          Expanded(child: val),
        ]);
      }
      return val;
    }

    final tick = Semantics(
      button: true,
      label: s.done ? 'Untick set $lbl' : 'Tick set $lbl',
      child: Hover(
        onTap: () {
          setState(() => act = null);
          c.tick(k);
        },
        builder: (_, h, _) {
          final sz = web ? 44.0 : 40.0;
          return Container(
            width: sz,
            height: sz,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: s.done ? AppColors.okSolid : AppColors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: s.done || h ? AppColors.okSolid : AppColors.line, width: 1.5),
            ),
            child: AppIcon(AppIcons.check, size: 20, stroke: 2.6, color: s.done ? AppColors.white : (h ? AppColors.okSolid : AppColors.tickOff)),
          );
        },
      ),
    );

    Widget? go;
    if (e.kind == ExKind.time) {
      final sz = web ? 44.0 : 40.0;
      go = s.done && !running
          ? const SizedBox()
          : Semantics(
              button: true,
              label: running ? 'Stop the hold timer' : 'Start the hold timer',
              child: Hover(
                onTap: () {
                  setState(() => act = null);
                  running ? c.stopHold() : c.startHold(k);
                },
                builder: (_, h, _) => Container(
                  width: sz,
                  height: sz,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: running ? AppColors.accent : (h ? AppColors.accentSoft : AppColors.white),
                    shape: BoxShape.circle,
                    border: Border.all(color: running || h ? AppColors.accent : AppColors.line),
                  ),
                  child: AppIcon(running ? AppIcons.stop : AppIcons.play, size: 16, color: running ? AppColors.white : AppColors.accent),
                ),
              ),
            );
    }

    return Row(spacing: 6, children: _grid(c, e, web: web, cells: [
      Align(alignment: Alignment.centerLeft, child: sn),
      if (web)
        CutText(prev, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: s.wu ? AppColors.amberText : AppColors.muted)),
      for (var j = 0; j < cols.length; j++) cell(j),
      ?go,
      tick,
    ]));
  }

  Widget _pm(AppIconData icon, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: h ? AppColors.sub : null, borderRadius: BorderRadius.circular(8)),
            child: AppIcon(icon, size: 15, color: AppColors.text2),
          ),
        ),
      );

  /// Phone: `cl-strip` under the set being changed.
  Widget _strip(WorkoutController c, TrainEx e, WSet s, int j) {
    final k = c.sets[c.cur].indexOf(s);
    final col = c.cols(e)[j];
    final label = e.kind == ExKind.weight && j == 0 ? (s.bw ? 'BW ± kg' : 'Weight kg') : col;
    Widget round(AppIconData icon, String l, int dir) => Semantics(
          button: true,
          label: l,
          child: Hover(
            onTap: () => c.step(k, j, dir),
            builder: (_, h, _) => Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: h ? AppColors.outlineHover : AppColors.white, shape: BoxShape.circle, border: Border.all(color: AppColors.accentRing)),
              child: AppIcon(icon, size: 16, color: AppColors.text2),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(10)),
      child: Row(spacing: 8, children: [
        Expanded(child: Text(label, style: AppText.s(12.5, W.w7, color: AppColors.sessText))),
        round(AppIcons.minus, 'Less', -1),
        SizedBox(width: 56, child: Text(c.text(s, j, e), textAlign: TextAlign.center, style: AppText.s(17, W.w8, tabular: true))),
        round(AppIcons.plus, 'More', 1),
        CaButton('Done', small: true, expand: false, kind: CaBtnKind.dark, onPressed: () => setState(() => act = null)),
      ]),
    );
  }

  // ─────────────────────────────── Bottom bars

  Widget _wic(bool paused) => Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: paused ? AppColors.amberBg : AppColors.accentSoft, borderRadius: BorderRadius.circular(10)),
        child: AppIcon(paused ? AppIcons.pause : AppIcons.clock, size: 17, color: paused ? AppColors.amberText : AppColors.accent),
      );

  static const _barShape = BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    border: Border(top: BorderSide(color: AppColors.line), left: BorderSide(color: AppColors.line), right: BorderSide(color: AppColors.line)),
    boxShadow: AppShadows.barUp,
  );

  /// Phone: `cl-wbar` with the workout time, opens the timer sheet.
  Widget _timerBar(WorkoutController c) => Semantics(
        button: true,
        label: 'Workout timer',
        child: Hover(
          onTap: () => _timerSheet(c),
          builder: (_, h, _) => Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 18, 10),
            decoration: h ? _barShape.copyWith(color: AppColors.outlineHover) : _barShape,
            child: Row(spacing: 10, children: [
              _wic(c.paused),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.paused ? 'TIMER PAUSED' : 'WORKOUT TIME', style: AppText.s(11, W.w7, color: AppColors.muted, ls: .55)),
                  Text(clockText(c.elapsed), style: AppText.s(18, W.w8, tabular: true)),
                ]),
              ),
              Text('${c.setsDone} of ${c.setsAll} sets', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
              const AppIcon(AppIcons.chevronUp, size: 16, color: AppColors.muted),
            ]),
          ),
        ),
      );

  /// `cl-rest`: phone white bar over the tabs, web dark bar under the panel.
  Widget _restBar(WorkoutController c, {required bool web}) {
    final fg = web ? AppColors.white : AppColors.text;
    final lab = web ? AppColors.valPh : AppColors.muted;
    final p = c.restMax == 0 ? 0.0 : (c.rest / c.restMax).clamp(0.0, 1.0);
    Widget btn(Widget child, String label, VoidCallback onTap) => Semantics(
          button: true,
          label: label,
          child: Hover(
            onTap: onTap,
            builder: (_, h, _) => Container(
              height: web ? 32 : 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: web ? AppColors.white.withValues(alpha: h ? .22 : .12) : (h ? AppColors.pressed : AppColors.sub),
                borderRadius: BorderRadius.circular(web ? 8 : 10),
              ),
              child: child,
            ),
          ),
        );
    final row = Row(spacing: 10, children: [
      Semantics(
        button: true,
        label: 'Open the rest timer',
        child: GestureDetector(
          onTap: () => c.restShow(true),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.restPaused ? 'REST · PAUSED' : 'REST', style: AppText.s(11, W.w7, color: lab, ls: .55)),
            Text(clockText(c.rest), style: AppText.s(20, W.w8, color: fg, tabular: true)),
          ]),
        ),
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(children: [
            Container(height: 6, color: web ? AppColors.white.withValues(alpha: .15) : AppColors.track),
            FractionallySizedBox(widthFactor: p, child: Container(height: 6, color: web ? AppColors.toastInfo : AppColors.accent)),
          ]),
        ),
      ),
      btn(AppIcon(c.restPaused ? AppIcons.play : AppIcons.pause, size: 15, color: fg), c.restPaused ? 'Resume rest' : 'Pause rest', c.restToggle),
      btn(Text('+15s', style: AppText.s(13, W.w7, color: fg)), 'Add 15 seconds', c.restMore),
      btn(Text('Skip', style: AppText.s(13, W.w7, color: fg)), 'Skip rest', c.restSkip),
    ]);
    if (web) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.circular(14), boxShadow: AppShadows.restBar),
        child: row,
      );
    }
    return Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: _barShape, child: row);
  }

  // ─────────────────────────────── Rest dialog (`cr`)

  void _openRest() {
    final c = w;
    if (c == null || !mounted || _restRoute != null || !c.restOpen || c.rest == 0) return;
    final web = !context.isPhone;
    final route = RawDialogRoute(
      barrierDismissible: true,
      barrierLabel: 'Rest timer',
      barrierColor: AppColors.scrimSheet,
      transitionDuration: const Duration(milliseconds: 140),
      transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      pageBuilder: (ctx, _, _) => Center(
        child: Material(
          color: Colors.transparent,
          child: CaWeb(web: web, child: ListenableBuilder(listenable: c, builder: (ctx, _) => _restDialog(ctx, c, web: web))),
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
    final sub = '${c.ex[at.$1].name}${at.$2 >= 0 ? ' · after set ${at.$2 + 1}' : ''}';
    final p = c.restMax == 0 ? 0.0 : (c.rest / c.restMax).clamp(0.0, 1.0);
    return Container(
      width: web ? 380 : 360,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.dialogBig),
      child: Column(mainAxisSize: MainAxisSize.min, spacing: 14, children: [
        Row(spacing: 10, children: [
          CaIconBtn(AppIcons.chevronLeft, tooltip: 'Back to the workout', onTap: () => c.restShow(false)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Rest timer', style: AppText.s(15, W.w8)),
              CutText(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w4, color: AppColors.muted)),
            ]),
          ),
        ]),
        Text('REST', style: AppText.s(11.5, W.w8, color: AppColors.muted, ls: .92)),
        SizedBox(
          width: 200,
          height: 200,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(child: CustomPaint(painter: _Ring(p))),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(clockText(c.rest), style: AppText.s(48, W.w8, ls: -0.96, h: 1, tabular: true)),
              const SizedBox(height: 4),
              Text(c.restPaused ? 'Paused' : 'of ${clockText(c.restMax)}', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
            ]),
          ]),
        ),
        Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
          for (final b in [
            CaButton('−15s', kind: CaBtnKind.out, expand: false, onPressed: c.restLess),
            CaButton(c.restPaused ? 'Resume' : 'Pause', kind: CaBtnKind.dark, expand: false, icon: c.restPaused ? AppIcons.play : AppIcons.pause, onPressed: c.restToggle),
            CaButton('+15s', kind: CaBtnKind.out, expand: false, onPressed: c.restMore),
          ])
            ConstrainedBox(constraints: const BoxConstraints(minWidth: 64), child: b),
        ]),
        ConstrainedBox(constraints: const BoxConstraints(minWidth: 140), child: CaButton('Skip rest', expand: false, onPressed: c.restSkip)),
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

  // ─────────────────────────────── Popovers (menu, set menu, timer, info tip)

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

  void _menu(BuildContext anchor, WorkoutController c) => _popover(anchor, width: 220, right: true, builder: (ctx, close) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _mi('Past workouts', icon: AppIcons.clock, onTap: () {
          close();
          showExerciseHistory(context, c.e, onUse: (sets, from) {
            setState(() => act = null);
            c.fillFrom(sets, from: from);
          });
        }),
        _mi('Restart workout', icon: AppIcons.restart, onTap: () {
          close();
          _askRestart(c);
        }),
        _mi('Remove logged work', icon: AppIcons.trash, danger: true, onTap: () {
          close();
          _askRemove(c);
        }),
      ]));

  void _setMenu(BuildContext anchor, WorkoutController c, int k) {
    setState(() => act = null);
    final s = c.sets[c.cur][k];
    _popover(anchor, width: 240, builder: (ctx, close) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _mi(s.wu ? 'Make it a working set' : 'Mark as warm-up',
              icon: AppIcons.flame,
              sub: s.wu ? 'Counts towards volume again' : 'Does not count towards volume',
              onTap: () {
                close();
                c.warmup(k);
              }),
          _mi('Send a form video', icon: AppIcons.camera, sub: 'Film this set for your coach to check', onTap: () {
            close();
            _formVideo(anchor, c, k);
          }),
          _mi('Delete set', icon: AppIcons.trash, danger: true, onTap: () {
            close();
            c.deleteSet(k);
          }),
        ]));
  }

  /// Form check video (Gautam, 22 Oct: from the logger, per set): record on a phone or pick a clip, up to 100 MB.
  void _formVideo(BuildContext anchor, WorkoutController c, int k) {
    final s = c.sets[c.cur][k];
    final exName = c.ex[c.cur].name;
    Future<void> pick(ImageSource src) async {
      try {
        final x = await ImagePicker().pickVideo(source: src, maxDuration: const Duration(seconds: 60));
        if (x == null) return;
        final b = await x.readAsBytes();
        if (b.length > 100 * 1024 * 1024) {
          c.toast?.call('This video is too big', sub: 'Up to 100 MB. Film just one set.', kind: ToastKind.warn);
          return;
        }
        await c.sendFormVideo(s, exName, x.name.contains('.') ? x.name : '${x.name}.mp4', b);
      } catch (_) {
        c.toast?.call('Could not open the camera', sub: 'Allow camera and video access for the app in your phone settings', kind: ToastKind.warn);
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

  void _tip(BuildContext anchor, String text, {required bool web}) => _popover(anchor,
      width: web ? 320 : 260,
      right: true,
      builder: (ctx, close) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(text, style: AppText.s(12.5, W.w6, h: 1.45)),
          ));

  /// Web: `cl-tpop` under the time chip.
  void _timerPop(BuildContext anchor, WorkoutController c) => _popover(anchor,
      width: 250,
      builder: (ctx, close) => CaWeb(
            web: true,
            child: ListenableBuilder(
              listenable: c,
              builder: (_, _) => Padding(
                padding: const EdgeInsets.all(6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                  Text(c.paused ? 'TIMER PAUSED' : 'WORKOUT TIME', style: AppText.s(11.5, W.w7, color: AppColors.muted, ls: .575)),
                  Text(clockText(c.elapsed), style: AppText.s(30, W.w8, tabular: true)),
                  _timerBtns(c),
                  _restartLink(() {
                    close();
                    _askRestart(c);
                  }),
                ]),
              ),
            ),
          ));

  Widget _timerBtns(WorkoutController c, {double? height}) => Row(spacing: 6, children: [
        Expanded(child: _tbtn('1 min', AppIcons.minus, () => c.shift(-60), height: height)),
        Expanded(child: _tbtn(c.paused ? 'Resume' : 'Pause', c.paused ? AppIcons.play : AppIcons.pause, c.pauseToggle, height: height, dark: true)),
        Expanded(child: _tbtn('1 min', AppIcons.plus, () => c.shift(60), height: height)),
      ]);

  /// `cl-tbtns` button: like `ca-btn sm` with 8 px sides so "− 1 min" fits in the 250 wide popover.
  Widget _tbtn(String label, AppIconData icon, VoidCallback onTap, {double? height, bool dark = false}) => Semantics(
        button: true,
        label: icon == AppIcons.minus ? 'Minus $label' : (icon == AppIcons.plus ? 'Plus $label' : label),
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            height: height ?? 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: dark ? (h ? AppColors.black : AppColors.text) : (h ? AppColors.outlineHover : AppColors.white),
              borderRadius: BorderRadius.circular(height == null ? 8 : 10),
              border: Border.all(color: dark ? AppColors.text : AppColors.line),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
                AppIcon(icon, size: 14, color: dark ? AppColors.white : AppColors.text),
                Text(label, style: AppText.s(13, W.w7, color: dark ? AppColors.white : AppColors.text, h: 1)),
              ]),
            ),
          ),
        ),
      );

  Widget _restartLink(VoidCallback onTap) => Center(
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: h ? AppColors.hover : null, borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              const AppIcon(AppIcons.restart, size: 15, color: AppColors.text2),
              Text('Restart workout', style: AppText.s(13, W.w6, color: AppColors.text2)),
            ]),
          ),
        ),
      );

  /// Phone: "Workout timer" sheet (`cl-tsheet`).
  void _timerSheet(WorkoutController c) => showAppSheet(
        context,
        title: 'Workout timer',
        sub: 'Started at ${DateFormat('h:mm a').format(c.startedAt).toLowerCase()} · ${c.name}',
        builder: (ctx) => ListenableBuilder(
          listenable: c,
          builder: (_, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            Text(c.paused ? 'TIMER PAUSED' : 'WORKOUT TIME', textAlign: TextAlign.center, style: AppText.s(11.5, W.w7, color: AppColors.muted, ls: .575)),
            Text(clockText(c.elapsed), textAlign: TextAlign.center, style: AppText.s(44, W.w8, tabular: true)),
            _timerBtns(c, height: 40),
            _restartLink(() {
              Navigator.of(ctx).pop();
              _askRestart(c);
            }),
            Text('The timer stops when you finish the workout, or when you leave Train. Continue workout starts it again.', textAlign: TextAlign.center, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
            const SizedBox(height: 4),
            Row(spacing: 8, children: [
              Expanded(
                child: _dangerOut('Remove logged work', () {
                  Navigator.of(ctx).pop();
                  _askRemove(c);
                }),
              ),
              Expanded(
                child: CaButton('Finish workout', onPressed: () {
                  Navigator.of(ctx).pop();
                  _askFinish(c);
                }),
              ),
            ]),
          ]),
        ),
      );

  Widget _dangerOut(String label, VoidCallback onTap) => Hover(
        onTap: onTap,
        builder: (ctx, h, _) {
          final web = CaWeb.of(ctx);
          return Container(
            height: web ? 40 : 44,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: h ? AppColors.badBg : AppColors.white, borderRadius: BorderRadius.circular(web ? 10 : 12), border: Border.all(color: AppColors.line)),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: AppText.s(web ? 14 : 14.5, W.w7, color: AppColors.badText))),
          );
        },
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

  // ─────────────────────────────── Sheets

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

  void _askFinish(WorkoutController c) {
    final all = c.setsDone == c.setsAll;
    final coach = c.plan.coachFirst;
    _ask(
      title: 'Finish workout?',
      sub: '${c.setsDone} of ${c.setsAll} sets done',
      body: _p(all
          ? 'Nice, every set is done. $coach sees your workout as soon as you finish.'
          : '${c.setsAll - c.setsDone} sets are not ticked yet. They are saved as skipped, and $coach sees what you did.'),
      buttons: (ctx) => [
        CaButton('Keep going', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
        CaButton('Finish', icon: AppIcons.check, onPressed: () {
          Navigator.of(ctx).pop();
          _finish(c);
        }),
      ],
    );
  }

  void _finish(WorkoutController c, {int? at}) {
    c.finish(at: at);
    _toast('Workout saved',
        sub: at == null ? '${c.setsDone} of ${c.setsAll} sets' : 'Time set to ${clockText(at)}, your last set', kind: ToastKind.star);
  }

  void _askRestart(WorkoutController c) {
    final n = c.setsDone;
    final msg = '${n == 0 ? 'The' : (n == 1 ? 'Your 1 ticked set goes back to not done and the' : 'All $n ticked sets go back to not done and the')}'
        ' timer starts again from 0:00. You start from the first exercise.';
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

  void _askRemove(WorkoutController c) {
    var pick = 2;
    showAppSheet(
      context,
      title: 'Remove what you logged?',
      sub: 'Pick how much to remove',
      webWidth: 440,
      builder: (ctx) => StatefulBuilder(
        builder: (_, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          CaRadioCards(
            options: [
              ('Clear this exercise', '${c.e.name} · timer keeps going'),
              ('Clear all sets', '${c.setsDone} ticked · timer keeps going'),
              c.reopened
                  ? ('Discard the extra sets', 'Your finished workout stays as it was')
                  : ('Discard the whole workout', 'Nothing is saved · timer stops'),
            ],
            index: pick,
            onPick: (i) => set(() => pick = i),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(spacing: 8, children: [
              Expanded(child: CaButton('Keep it', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop())),
              Expanded(
                child: _dangerBtn(['Clear exercise', 'Clear all sets', c.reopened ? 'Discard extra sets' : 'Discard workout'][pick], () async {
                  Navigator.of(ctx).pop();
                  setState(() => act = null);
                  if (pick == 0) {
                    c.clearExercise();
                  } else if (pick == 1) {
                    c.clearAll();
                  } else {
                    final again = c.reopened;
                    await c.discard();
                    if (mounted) context.go('/train?discarded=${again ? 2 : 1}');
                  }
                }),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

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

  // ─────────────────────────────── Workout done (`cd`)

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
    Widget stat(String v, String l) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
            child: Column(spacing: 2, children: [
              FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: AppText.s(19, W.w8, tabular: true))),
              Text(l, style: AppText.s(12, W.w6, color: AppColors.muted)),
            ]),
          ),
        );
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
          Text('Workout done!', style: AppText.s(24, W.w8)),
          Text('${c.name} · ${DateFormat('EEE, d MMM').format(c.date)}', textAlign: TextAlign.center, style: AppText.s(13.5, W.w4, color: AppColors.muted)),
        ]),
      ),
      Row(spacing: 8, children: [
        stat(clockText(total), 'Total time'),
        stat('${c.setsDone}/${c.setsAll}', 'Sets'),
        stat('${NumberFormat.decimalPattern('en_IN').format(c.volume.round())} kg', 'Volume'),
      ]),
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
      CaButton('Back to home', kind: CaBtnKind.out, onPressed: () => context.go('/home')),
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
