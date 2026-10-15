import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../auth_frame.dart';
import 'setup_state.dart';

/// Brand side panel (desktop) for every setup page.
BrandSteps setupBrand(BuildContext context, {int? current, bool fromDone = false}) {
  final st = SetupState.instance;
  return BrandSteps(
    titles: SetupState.titles,
    subs: SetupState.subs,
    done: st.done,
    current: current,
    coachFirst: Services.session.me?.coachFirst ?? 'your coach',
    onTap: (i) {
      final ft = st.firstTodo;
      if (st.done.contains(i) || i == ft) {
        context.go('/setup?step=$i${fromDone ? '&edit=1' : ''}');
      } else {
        showToast(context, 'Finish ${SetupState.titles[ft < 0 ? 0 : ft].toLowerCase()} first', sub: 'Steps go in order', kind: ToastKind.info);
      }
    },
  );
}

/// One setup step (`wl-onb`). `/setup?step=0..4`, `&edit=1` when opened from the summary.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, this.step, this.edit = false});
  final int? step;
  final bool edit;
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final st = SetupState.instance;
  late int step = widget.step ?? 0;
  bool _busy = false;
  late final _note = TextEditingController(text: st.note);

  @override
  void initState() {
    super.initState();
    st.addListener(_changed);
    if (!st.loaded) {
      st.load().then((_) {
        if (!mounted) return;
        _note.text = st.note;
        if (widget.step == null && st.firstTodo >= 0) setState(() => step = st.firstTodo);
      }).catchError((Object e) {
        if (mounted) showToast(context, 'Could not load your answers', sub: e is ApiError ? e.message : null, kind: ToastKind.err);
      });
    }
  }

  @override
  void didUpdateWidget(SetupScreen old) {
    super.didUpdateWidget(old);
    if (widget.step != null && widget.step != old.step) step = widget.step!;
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    st.removeListener(_changed);
    _note.dispose();
    super.dispose();
  }

  String get coach => Services.session.me?.coachFirst ?? 'Your coach';

  void _back() {
    if (widget.edit) return context.go('/setup/done');
    if (step == 0) return context.go('/pending');
    setState(() => step--);
  }

  Future<void> _next() async {
    final bad = st.need(step);
    if (bad != null) return showToast(context, bad.$1, sub: bad.$2, kind: ToastKind.warn);
    setState(() => _busy = true);
    try {
      st.note = _note.text;
      await st.save(step);
      if (!mounted) return;
      if (widget.edit) {
        showToast(context, '${SetupState.titles[step]} saved', sub: '$coach sees the change right away', kind: ToastKind.ok);
        return context.go('/setup/done');
      }
      final nx = st.firstTodo;
      if (nx < 0) {
        showToast(context, 'Profile complete', sub: '$coach can now build your plan', kind: ToastKind.star);
        context.go('/setup/done');
      } else {
        setState(() => step = nx);
      }
    } on ApiError catch (e) {
      if (mounted) showToast(context, e.offline ? 'You are offline' : 'Could not save', sub: e.offline ? 'Connect to the internet to save this step' : e.message, kind: ToastKind.err);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nextT = widget.edit ? 'Save changes' : (step == 4 ? 'Finish' : 'Continue · ${SetupState.shorts[step + 1]}');
    final hasBack = step > 0 && !widget.edit;
    return AuthFrame(
      wide: true,
      brand: BrandKind.steps,
      steps: setupBrand(context, current: step, fromDone: widget.edit),
      foot: [
        Row(spacing: 8, children: [
          if (hasBack) SizedBox(width: 96, child: CaButton('Back', kind: CaBtnKind.out, onPressed: _back)),
          Expanded(child: CaButton(nextT, loading: _busy, onPressed: _next)),
        ]),
      ],
      children: [
        Row(spacing: 10, children: [
          CaIconBtn(AppIcons.chevronLeft, onTap: _back, tooltip: 'Back'),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text('STEP ${step + 1} OF 5', style: AppText.s(11, W.w8, color: AppColors.accentText, ls: 0.88)),
              Text(SetupState.titles[step], style: AppText.s(17, W.w8)),
            ]),
          ),
          CaLink('Finish later', size: 13, onTap: () => showLaterSheet(context, saveStep: step)),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 0),
          child: CaSegments(count: 5, isDone: st.done.contains, current: step),
        ),
        ...switch (step) { 0 => _goal(), 1 => _about(), 2 => _schedule(), 3 => _health(), _ => _food() },
      ],
    );
  }

  List<Widget> _goal() {
    final split = authSplit(context);
    final g = SetupState.goals.where((x) => x.$1 == st.goal).firstOrNull;
    const icons = [AppIcons.flame, AppIcons.dumbbell, AppIcons.bolt, AppIcons.swapAlt, AppIcons.heartPulse, AppIcons.calendarAlt];
    return [
      CaQuestion('What’s your main goal?', sub: '$coach builds your training and meals around it.'),
      _Grid(columns: split ? 3 : 2, children: [
        for (var i = 0; i < SetupState.goals.length; i++)
          _PickCard(
            check: true,
            on: st.goal == SetupState.goals[i].$1,
            onTap: () {
              st.goal = SetupState.goals[i].$1;
              st.changed();
            },
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Builder(builder: (context) {
                final on = st.goal == SetupState.goals[i].$1;
                return Container(
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.only(bottom: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: on ? AppColors.accent : AppColors.sub, borderRadius: BorderRadius.circular(9)),
                  child: AppIcon(icons[i], size: 17, color: on ? AppColors.white : AppColors.text2),
                );
              }),
              Text(SetupState.goals[i].$2, style: AppText.s(14, W.w8)),
              Text(SetupState.goals[i].$3, style: AppText.s(12, W.w4, color: AppColors.muted)),
            ]),
          ),
      ]),
      if (g != null) CaHint(g.$4, icon: AppIcons.star),
      const CaQuestion('Training experience'),
      CaSeg(
        options: [for (final l in SetupState.levels) (l.$2, l.$3)],
        index: SetupState.levels.indexWhere((x) => x.$1 == st.level),
        onPick: (i) {
          st.level = SetupState.levels[i].$1;
          st.changed();
        },
      ),
    ];
  }

  List<Widget> _about() {
    const labels = ['Age', 'Height', 'Weight', 'Target weight'];
    final diff = ((st.body[2] - st.body[3]) * 10).round() / 10;
    final line = diff > 0
        ? 'Goal: lose ${SetupState.f1(diff)} kg. A safe pace is about 0.5 kg a week, so roughly ${(diff / 0.5).ceil()} weeks.'
        : diff < 0
            ? 'Goal: gain ${SetupState.f1(-diff)} kg. $coach plans a small surplus.'
            : 'Goal: keep your weight and change your shape.';
    void bump(int k, int dir) {
      final v = (st.body[k] + dir * SetupState.bodyStep[k]).clamp(SetupState.bodyMin[k], SetupState.bodyMax[k]);
      st.body = [for (var j = 0; j < 4; j++) j == k ? v : st.body[j]];
      st.changed();
    }

    return [
      CaQuestion('Body basics', sub: '$coach uses this to set your calories and training load.'),
      _Grid(columns: 2, children: [
        for (var k = 0; k < 4; k++)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
              Text(labels[k], style: AppText.s(11.5, W.w7, color: AppColors.muted)),
              CaStepper(value: st.fmtBody(k), onMinus: () => bump(k, -1), onPlus: () => bump(k, 1)),
            ]),
          ),
      ]),
      CaHint(line, icon: AppIcons.target),
      const CaQuestion('Where will you train?'),
      CaSeg(
        options: [for (final p in SetupState.places) (p.$2, p.$3)],
        index: SetupState.places.indexWhere((x) => x.$1 == st.place),
        onPick: (i) {
          st.place = SetupState.places[i].$1;
          st.changed();
        },
      ),
      const CaCaption('Only you and your coach can see this.', icon: AppIcons.lock, pullUp: 8),
    ];
  }

  List<Widget> _schedule() {
    final line = st.trainDays.isEmpty
        ? 'Pick at least 2 days. Rest days are part of the plan.'
        : '${st.trainDays.length} days a week · ${st.sortedDayLabels.join(', ')}';
    return [
      CaQuestion('Which days can you train?', sub: line),
      CaCard(
        padding: const EdgeInsets.all(6),
        child: Row(spacing: 4, children: [
          for (final d in SetupState.days)
            Expanded(
              child: Builder(builder: (context) {
                final on = st.trainDays.contains(d.$1);
                return Hover(
                  onTap: () {
                    st.trainDays = on ? (List.of(st.trainDays)..remove(d.$1)) : [...st.trainDays, d.$1];
                    st.changed();
                  },
                  builder: (_, h, _) => AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(color: on ? AppColors.accentSoft : (h ? AppColors.sub : null), borderRadius: BorderRadius.circular(10)),
                    child: Column(spacing: 6, children: [
                      Text(d.$2, style: AppText.s(12, W.w7, color: on ? AppColors.accentText : AppColors.text2)),
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: on ? AppColors.accent : AppColors.dayOff, shape: BoxShape.circle),
                        child: on ? const AppIcon(AppIcons.check, size: 12, color: AppColors.white, stroke: 2.6) : null,
                      ),
                    ]),
                  ),
                );
              }),
            ),
        ]),
      ),
      const CaQuestion('How long can you train?'),
      CaChips<int>(
        options: SetupState.lengths,
        label: (m) => '$m min',
        isOn: (m) => m == st.sessionMin,
        onTap: (m) {
          st.sessionMin = m;
          st.changed();
        },
      ),
      const CaQuestion('Usual wake-up time'),
      CaChips<(String, String)>(
        options: SetupState.wakes,
        label: (w) => w.$2,
        isOn: (w) => w.$1 == st.wake,
        onTap: (w) {
          st.wake = w.$1;
          st.changed();
        },
      ),
    ];
  }

  List<Widget> _health() {
    final real = [for (final i in st.injury) if (i != 'none') i];
    final suggestions = [for (final i in real) ...?SetupState.injuryNotes[i]].take(3).toList();
    return [
      CaQuestion('Any injuries or pain?', sub: '$coach swaps exercises so nothing hurts. Pick all that apply.'),
      CaChips<(String, String)>(
        options: SetupState.injuries,
        label: (x) => x.$2,
        checkWhenOn: true,
        isOn: (x) => st.injury.contains(x.$1),
        onTap: (x) {
          final n = x.$1;
          st.injury = n == 'none'
              ? (st.injury.contains('none') ? [] : ['none'])
              : (st.injury.contains(n) ? (List.of(st.injury)..remove(n)) : [...st.injury.where((e) => e != 'none'), n]);
          st.changed();
        },
      ),
      if (real.isNotEmpty) ...[
        CaField(label: 'Tell $coach more', controller: _note, hint: 'Where does it hurt, and when?', maxLength: 2000),
        if (suggestions.isNotEmpty)
          Transform.translate(
            offset: const Offset(0, -6),
            child: CaChips<String>(
              small: true,
              options: suggestions,
              label: (s) => s,
              isOn: (s) => _note.text.trim() == s,
              onTap: (s) => setState(() => _note.text = s),
            ),
          ),
      ],
      CaQuestion('Any health conditions?', sub: '$coach plans food and training around them.'),
      CaChips<(String, String)>(
        options: SetupState.conditionOptions,
        label: (x) => x.$2,
        checkWhenOn: true,
        isOn: (x) => st.conditions.contains(x.$1),
        onTap: (x) {
          final n = x.$1;
          st.conditions = n == 'none'
              ? (st.conditions.contains('none') ? [] : ['none'])
              : (st.conditions.contains(n) ? (List.of(st.conditions)..remove(n)) : [...st.conditions.where((e) => e != 'none'), n]);
          st.changed();
        },
      ),
      if (st.conditions.contains('heart'))
        CaHint('With a heart condition, get your doctor’s OK before you start. $coach checks this before your first session.', icon: AppIcons.heart, tone: CaTone.amber),
      const CaQuestion('Daily activity', sub: 'Outside your workouts.'),
      CaRadioCards(
        options: [for (final a in SetupState.activities) (a.$2, a.$3)],
        index: SetupState.activities.indexWhere((x) => x.$1 == st.activity),
        onPick: (i) {
          st.activity = SetupState.activities[i].$1;
          st.changed();
        },
      ),
      CaCheckRow(
        on: st.doctorOk,
        onTap: () {
          st.doctorOk = !st.doctorOk;
          st.changed();
        },
        title: 'A doctor has cleared me for exercise',
        sub: st.conditions.contains('heart') ? 'Needed with a heart condition' : 'Tick this if you have a heart, bone or joint condition',
      ),
      const CaCaption('Only you and your coach can see this.', icon: AppIcons.lock, pullUp: 8),
    ];
  }

  List<Widget> _food() {
    final split = authSplit(context);
    return [
      const CaQuestion('Food preference', sub: 'Your meal plan only uses foods you eat.'),
      _Grid(columns: split ? 3 : 2, children: [
        for (final d in SetupState.diets)
          _PickCard(
            on: st.diet == d.$1,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            onTap: () {
              st.diet = d.$1;
              st.changed();
            },
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              Padding(padding: const EdgeInsets.only(top: 1.5), child: _DietDot(d.$4)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.$2, style: AppText.s(13.5, W.w8)),
                  Text(d.$3, style: AppText.s(11.5, W.w4, color: AppColors.muted)),
                ]),
              ),
            ]),
          ),
      ]),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
        child: Row(spacing: 10, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text('Meals per day', style: AppText.s(14, W.w7)),
              Text('Including snacks', style: AppText.s(12, W.w4, color: AppColors.muted)),
            ]),
          ),
          CaStepper(
            value: '${st.meals} meals',
            button: 34,
            valueWidth: 72,
            onMinus: () {
              st.meals = (st.meals - 1).clamp(2, 7);
              st.changed();
            },
            onPlus: () {
              st.meals = (st.meals + 1).clamp(2, 7);
              st.changed();
            },
          ),
        ]),
      ),
      const CaQuestion('Foods you avoid', sub: 'Allergies or simply don’t like them.'),
      CaChips<(String, String)>(
        options: SetupState.avoids,
        label: (x) => x.$2,
        checkWhenOn: true,
        isOn: (x) => st.avoid.contains(x.$1),
        onTap: (x) {
          st.avoid = st.avoid.contains(x.$1) ? (List.of(st.avoid)..remove(x.$1)) : [...st.avoid, x.$1];
          st.changed();
        },
      ),
      CaCheckRow(
        on: st.homeCooked,
        onTap: () {
          st.homeCooked = !st.homeCooked;
          st.changed();
        },
        title: 'I mostly eat home-cooked food',
        sub: '$coach plans dal, roti and sabzi style meals',
      ),
    ];
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.children});
  final int columns;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          for (var j = i; j < i + columns; j++) Expanded(child: j < children.length ? children[j] : const SizedBox()),
        ]),
      ));
    }
    return Column(spacing: 8, children: rows);
  }
}

/// `wl-goal` / `wl-dt`: selectable card with a blue ring when picked.
class _PickCard extends StatelessWidget {
  const _PickCard({required this.on, required this.onTap, required this.child, this.check = false, this.padding = const EdgeInsets.all(12)});
  final bool on, check;
  final VoidCallback onTap;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: on,
        button: true,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: padding,
            decoration: BoxDecoration(
              color: on ? AppColors.pickBg : AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: on ? AppColors.accent : (h ? AppColors.line2 : AppColors.line)),
              boxShadow: on ? const [BoxShadow(color: AppColors.accentSoft, spreadRadius: 3)] : null,
            ),
            child: Stack(clipBehavior: Clip.none, children: [
              child,
              if (check)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: on ? AppColors.accent : null,
                      border: Border.all(color: on ? AppColors.accent : AppColors.line2, width: 1.5),
                    ),
                    child: on ? const AppIcon(AppIcons.check, size: 12, color: AppColors.white, stroke: 3) : null,
                  ),
                ),
            ]),
          ),
        ),
      );
}

/// Veg / egg / non-veg mark (`wl-dot`).
class _DietDot extends StatelessWidget {
  const _DietDot(this.kind);
  final int kind; // 0 green, 1 amber, 2 red
  @override
  Widget build(BuildContext context) {
    final c = [AppColors.vegGreen, AppColors.eggAmber, AppColors.meatRed][kind];
    return Container(
      width: 14,
      height: 14,
      alignment: Alignment.center,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), border: Border.all(color: c, width: 1.5)),
      child: kind == 2
          ? CustomPaint(size: const Size(8, 7), painter: _Tri(c))
          : Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
    );
  }
}

class _Tri extends CustomPainter {
  _Tri(this.c);
  final Color c;
  @override
  void paint(Canvas canvas, Size s) => canvas.drawPath(
        Path()
          ..moveTo(s.width / 2, 0)
          ..lineTo(s.width, s.height)
          ..lineTo(0, s.height)
          ..close(),
        Paint()..color = c,
      );
  @override
  bool shouldRepaint(_Tri old) => old.c != c;
}

/// "Finish setup later?" — remind Tonight / Tomorrow / In 3 days / Off, then Save & leave.
/// [saveStep]: the step on screen; it is saved first when its answers are complete (board `lt.save`).
Future<void> showLaterSheet(BuildContext context, {int? saveStep}) {
  final st = SetupState.instance;
  final pick = ValueNotifier(st.remind ?? 'tomorrow');
  final busy = ValueNotifier(false);
  final coach = Services.session.me?.coachFirst ?? 'Your coach';
  Future<void> save(BuildContext ctx) async {
    busy.value = true;
    try {
      if (saveStep != null && !st.done.contains(saveStep) && st.need(saveStep) == null) await st.save(saveStep);
      await st.saveAndLeave(pick.value);
      if (!ctx.mounted) return;
      Navigator.of(ctx).pop();
      showToast(context, 'Progress saved', sub: pick.value == 'off' ? 'No reminder set' : st.remindLine, kind: ToastKind.ok);
      if (context.mounted) context.go('/setup/checklist');
    } on ApiError catch (e) {
      busy.value = false;
      showToast(context, 'Could not save', sub: e.message, kind: ToastKind.err);
    }
  }

  return showAppSheet<void>(
    context,
    title: 'Finish setup later?',
    sub: 'Your answers so far are saved.',
    footerStretch: true,
    // `ca-sf`: Keep going / Save & leave.
    footer: (ctx) => [
      Row(spacing: 8, children: [
        Expanded(child: CaButton('Keep going', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop())),
        Expanded(
          child: ValueListenableBuilder(valueListenable: busy, builder: (_, b, _) => CaButton('Save & leave', loading: b, onPressed: () => save(ctx))),
        ),
      ]),
    ],
    // Sheet body: Remind me (8 under it), the chips, then the caption 10 below.
    builder: (ctx) => ValueListenableBuilder(
      valueListenable: pick,
      builder: (_, p, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        const CaQuestion('Remind me', pull: 2),
        CaChips<(String, String, String)>(
          options: SetupState.remindChoices,
          label: (x) => x.$2,
          isOn: (x) => x.$1 == p,
          onTap: (x) => pick.value = x.$1,
        ),
        CaCaption('$coach can’t build your plan until setup is done. $coach can see that it is not finished yet.'),
      ]),
    ),
  );
}
