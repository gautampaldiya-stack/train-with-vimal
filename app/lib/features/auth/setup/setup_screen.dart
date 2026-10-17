import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/util/input_rules.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/media.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
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

/// One setup step (`wl-onb`): the gym's coaching form, a few questions at a time (D-36). `/setup?step=0..8`,
/// `&edit=1` when opened from the summary. The questions (words, required marks, which are asked) come from
/// `me/onboarding/`, so an edit to the onboarding form shows here; extra questions the admin added are on the last step.
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
  final _ctl = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    st.addListener(_changed);
    if (!st.loaded) {
      st.load().then((_) {
        if (!mounted) return;
        _sync();
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
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  String get coach => Services.session.me?.coachFirst ?? 'Your coach';

  String _text(String key) {
    final x = key.startsWith('q') && st.field(key) == null ? st.extraAnswers[key.substring(1)] : st.v[key];
    if (x == null) return '';
    if (x is num) return SetupState.num1(x);
    final f = st.field(key);
    if (f != null && f.kind == 'other' && f.isOption(x)) return '';
    return '$x';
  }

  /// The text box of a field (or `q<id>` for an extra question); typing writes the answer straight away.
  TextEditingController _c(String key) => _ctl.putIfAbsent(key, () {
        final c = TextEditingController(text: _text(key));
        c.addListener(() {
          if (key.startsWith('q') && st.field(key) == null) {
            st.extraAnswers[key.substring(1)] = c.text;
            st.errors.remove(key);
          } else if (st.v[key] is! String || st.v[key] != c.text) {
            final f = st.field(key);
            // An "Other" answer only takes the words while Other is picked.
            if (f != null && f.kind == 'other' && !st.otherOpen.contains(key)) return;
            st.v[key] = c.text;
            st.errors.remove(key);
          }
        });
        return c;
      });

  void _sync() {
    for (final e in _ctl.entries) {
      final t = _text(e.key);
      if (e.value.text != t) e.value.text = t;
    }
  }

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
    final last = step == SetupState.count - 1;
    final nextT = widget.edit ? 'Save changes' : (last ? 'Finish' : 'Continue · ${SetupState.shorts[step + 1]}');
    final hasBack = step > 0 && !widget.edit;
    return AuthFrame(
      wide: true,
      brand: BrandKind.steps,
      steps: setupBrand(context, current: step, fromDone: widget.edit),
      foot: [
        Row(spacing: 8, children: [
          if (hasBack) SizedBox(width: 96, child: CaButton('Back', kind: CaBtnKind.out, onPressed: _back)),
          Expanded(child: CaButton(nextT, loading: _busy, onPressed: st.loaded ? _next : null)),
        ]),
      ],
      children: [
        Row(spacing: 10, children: [
          CaIconBtn(AppIcons.chevronLeft, onTap: _back, tooltip: 'Back'),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text('STEP ${step + 1} OF ${SetupState.count}', style: AppText.s(11, W.w8, color: AppColors.accentText, ls: 0.88)),
              Text(SetupState.titles[step], style: AppText.s(17, W.w8)),
            ]),
          ),
          CaLink('Finish later', size: 13, onTap: () => showLaterSheet(context, saveStep: step)),
        ]),
        CaSegments(count: SetupState.count, isDone: st.done.contains, current: step),
        if (!st.loaded)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))),
          )
        else
          ..._step(),
      ],
    );
  }

  // ─────────────────────────────── one step, field by field

  List<Widget> _step() {
    final fs = st.fieldsOf(step);
    final out = <Widget>[];
    if (step == 1) out.add(CaCaption('Hello there! Fill every detail carefully: $coach makes your workout and meal plans from these answers.'));
    if (step == 5) out.add(const CaCaption('What you eat on a normal day now. Write None if you skip a meal.'));
    if (step == 7) {
      out.add(const CaHint('Measure in the morning, before you eat, in a resting state. Use a tape in cm.', icon: AppIcons.ruler));
    }
    for (var i = 0; i < fs.length; i++) {
      final f = fs[i];
      // Runs of numbers, measurements and photos sit in a grid.
      if (const ['num', 'measure', 'photo'].contains(f.kind)) {
        final run = <SetupField>[f];
        while (i + 1 < fs.length && fs[i + 1].kind == f.kind) {
          run.add(fs[++i]);
        }
        out.addAll(switch (f.kind) { 'photo' => _photos(run), 'measure' => _numbers(run, measure: true), _ => _numbers(run) });
        continue;
      }
      if (f.kind == 'agree') out.addAll(_extras());
      out.addAll(_one(f));
    }
    if (step == 8 && !st.asks('terms')) out.addAll(_extras());
    if (const [1, 3, 6].contains(step)) out.add(const CaCaption('Only you and your coach can see this.', icon: AppIcons.lock, pullUp: 8));
    return out;
  }

  Widget _err(String key) {
    final e = st.errors[key];
    if (e == null) return const SizedBox.shrink();
    return Pull(
      top: 8,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
        const Padding(padding: EdgeInsets.only(top: 2), child: AppIcon(AppIcons.alert, size: 14, color: AppColors.badText)),
        Expanded(child: Text(e, style: AppText.s(12.5, W.w6, color: AppColors.badText, h: 1.4))),
      ]),
    );
  }

  List<Widget> _one(SetupField f) {
    final q = _Q(f.label, req: f.required, help: f.help);
    switch (f.kind) {
      case 'goal':
        return [_Q(f.label, req: f.required, help: f.help.isEmpty ? '$coach builds your training and meals around it.' : f.help), _goals(), _err(f.key)];
      case 'choice' when f.options.every((o) => o.$3 != null) && f.options.length <= 3:
        return [
          q,
          CaSeg(options: [for (final o in f.options) (o.$2, o.$3!)], index: f.options.indexWhere((o) => o.$1 == st.v[f.key]), onPick: (i) => st.set(f.key, f.options[i].$1)),
          _err(f.key),
        ];
      case 'choice' when f.options.every((o) => o.$3 != null):
        return [
          q,
          CaRadioCards(options: [for (final o in f.options) (o.$2, o.$3!)], index: f.options.indexWhere((o) => o.$1 == st.v[f.key]), onPick: (i) => st.set(f.key, f.options[i].$1)),
          _err(f.key),
        ];
      case 'choice' || 'gender':
        return [q, _pick(f, f.options), _err(f.key)];
      case 'other':
        final open = st.otherOpen.contains(f.key);
        return [
          q,
          if (f.key == 'diet_type') _diets(f) else _pick(f, [...f.options, ('\u0000other', f.other ?? 'Other', null)]),
          if (open) _Input(controller: _c(f.key), hint: f.key == 'smoking' ? 'How many a day?' : (f.key == 'food_allergies' ? 'Which foods?' : 'Write your answer'), maxLength: f.maxLen, autofocus: true),
          _err(f.key),
        ];
      case 'multi':
        return [
          q,
          CaChips<(String, String, String?)>(
            options: f.options,
            label: (x) => x.$2,
            checkWhenOn: true,
            isOn: (x) => ((st.v[f.key] as List?) ?? const []).contains(x.$1),
            onTap: (x) {
              final cur = [for (final e in (st.v[f.key] as List?) ?? const []) '$e'];
              final n = x.$1;
              st.set(
                  f.key,
                  n == 'none'
                      ? (cur.contains('none') ? <String>[] : ['none'])
                      : (cur.contains(n) ? (List.of(cur)..remove(n)) : [...cur.where((e) => e != 'none'), n]));
            },
          ),
          if (f.key == 'conditions' && ((st.v[f.key] as List?) ?? const []).contains('heart'))
            CaHint('With a heart condition, get your doctor’s OK before you start. $coach checks this before your first session.', icon: AppIcons.heart, tone: CaTone.amber),
          _err(f.key),
        ];
      case 'yesno' when f.key == 'doctor_ok':
        final heart = ((st.v['conditions'] as List?) ?? const []).contains('heart');
        return [
          CaCheckRow(
            on: st.v[f.key] == true,
            onTap: () => st.set(f.key, st.v[f.key] != true),
            title: f.label,
            sub: heart ? 'Needed with a heart condition' : 'Tick this if you have a heart, bone or joint condition',
          ),
          _err(f.key),
        ];
      case 'yesno':
        return [
          q,
          CaChips<(String, bool)>(
            options: const [('Yes', true), ('No', false)],
            label: (x) => x.$1,
            isOn: (x) => st.v[f.key] == x.$2,
            onTap: (x) => st.set(f.key, x.$2),
          ),
          _err(f.key),
        ];
      case 'int':
        final lo = (f.min ?? 1).round(), hi = (f.max ?? 7).round();
        return [
          q,
          CaChips<int>(
            options: [for (var n = lo; n <= hi; n++) n],
            label: (n) => n == 1 ? '1 day' : '$n days',
            isOn: (n) => '${st.v[f.key]}' == '$n',
            onTap: (n) => st.set(f.key, n),
          ),
          _err(f.key),
        ];
      case 'date':
        return [_DateInput(label: f.label, req: f.required, value: st.v[f.key] as String?, error: st.errors[f.key], onPick: (d) => st.set(f.key, d))];
      case 'phone':
        return [_Input(label: f.label, req: f.required, controller: _c(f.key), keyboard: TextInputType.phone, leading: '+91', hint: '98765 43210', error: st.errors[f.key])];
      case 'agree':
        return [_terms(), CaCheckRow(on: st.v[f.key] == true, onTap: () => st.set(f.key, st.v[f.key] != true), title: st.agreeText.isEmpty ? f.label : st.agreeText), _err(f.key)];
      case 'long':
        return [q, _Input(controller: _c(f.key), lines: 3, maxLength: f.maxLen, hint: f.help.startsWith('Write None') ? 'Write None if there is nothing' : null), _err(f.key)];
      default: // text
        return [_Input(label: f.label, req: f.required, help: f.help, controller: _c(f.key), maxLength: f.maxLen, error: st.errors[f.key])];
    }
  }

  /// Single pick as chips; the `\u0000other` chip opens the client's own words.
  Widget _pick(SetupField f, List<(String, String, String?)> options) => CaChips<(String, String, String?)>(
        options: options,
        label: (x) => x.$2,
        isOn: (x) => x.$1 == '\u0000other' ? st.otherOpen.contains(f.key) : !st.otherOpen.contains(f.key) && st.v[f.key] == x.$1,
        onTap: (x) {
          if (x.$1 == '\u0000other') {
            st.otherOpen.add(f.key);
            final t = _c(f.key).text;
            st.set(f.key, t);
          } else {
            st.otherOpen.remove(f.key);
            st.set(f.key, x.$1);
          }
        },
      );

  Widget _goals() {
    final split = authSplit(context);
    final g = SetupState.goals.where((x) => x.$1 == st.v['goal']).firstOrNull;
    const icons = [AppIcons.flame, AppIcons.dumbbell, AppIcons.bolt, AppIcons.swapAlt, AppIcons.heartPulse, AppIcons.calendarAlt];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
      _Grid(columns: split ? 3 : 2, children: [
        for (var i = 0; i < SetupState.goals.length; i++)
          _PickCard(
            check: true,
            on: st.v['goal'] == SetupState.goals[i].$1,
            onTap: () => st.set('goal', SetupState.goals[i].$1),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Builder(builder: (context) {
                final on = st.v['goal'] == SetupState.goals[i].$1;
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
    ]);
  }

  Widget _diets(SetupField f) {
    final split = authSplit(context);
    final open = st.otherOpen.contains(f.key);
    Widget card(String key, String title, String line, int? mark, bool on, VoidCallback onTap) => _PickCard(
          on: on,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          onTap: onTap,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
            if (mark != null) Padding(padding: const EdgeInsets.only(top: 1.5), child: _DietDot(mark)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: AppText.s(13.5, W.w8)),
                Text(line, style: AppText.s(11.5, W.w4, color: AppColors.muted)),
              ]),
            ),
          ]),
        );
    return _Grid(columns: split ? 3 : 2, children: [
      for (final o in f.options)
        card(o.$1, o.$2, SetupState.dietLines[o.$1] ?? '', SetupState.dietMarks[o.$1], !open && st.v[f.key] == o.$1, () {
          st.otherOpen.remove(f.key);
          st.set(f.key, o.$1);
        }),
      card('other', f.other ?? 'Other', 'Tell us in your words', null, open, () {
        st.otherOpen.add(f.key);
        st.set(f.key, _c(f.key).text);
      }),
    ]);
  }

  /// Weight, height, goal weight (and other numbers): boxes with the unit, 2 a row (3 on the web).
  List<Widget> _numbers(List<SetupField> run, {bool measure = false}) {
    final split = authSplit(context);
    String unit(SetupField f) => measure || f.key.endsWith('_cm') ? 'cm' : (f.key.endsWith('_kg') ? 'kg' : '');
    final w = double.tryParse('${st.v['weight_kg'] ?? ''}'), t = double.tryParse('${st.v['target_weight_kg'] ?? ''}');
    final diff = w == null || t == null ? null : ((w - t) * 10).round() / 10;
    final line = diff == null
        ? null
        : diff > 0
            ? 'Goal: lose ${SetupState.num1(diff)} kg. A safe pace is about 0.5 kg a week, so roughly ${(diff / 0.5).ceil()} weeks.'
            : diff < 0
                ? 'Goal: gain ${SetupState.num1(-diff)} kg. $coach plans a small surplus.'
                : 'Goal: keep your weight and change your shape.';
    return [
      if (measure) const _Q('Current measurements', req: false, help: 'In cm. Same time of day each time you measure.'),
      _Grid(columns: split ? 3 : 2, children: [
        for (final f in run)
          _Input(
            label: f.label,
            req: f.required,
            controller: _c(f.key),
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            trailing: unit(f),
            error: st.errors[f.key],
          ),
      ]),
      if (!measure && run.any((f) => f.key == 'target_weight_kg') && line != null) CaHint(line, icon: AppIcons.target),
      if (!measure && run.any((f) => f.key == 'target_weight_kg' && f.help.isNotEmpty)) CaCaption(run.firstWhere((f) => f.key == 'target_weight_kg').help, pullUp: 8),
    ];
  }

  List<Widget> _photos(List<SetupField> run) => [
        const _Q('Current photos', req: true,
            help: 'Men: please wear trunks. Women: shorts or gym trousers with a sports bra or tight t-shirt. It helps compare your progress later.'),
        _Grid(columns: 3, children: [
          for (final f in run)
            _PhotoSlot(
              label: f.label,
              saved: st.photos[SetupState.poses[f.key]],
              picked: st.newPhotos[SetupState.poses[f.key]],
              bad: st.errors.containsKey(f.key),
              onPick: (data) {
                st.newPhotos[SetupState.poses[f.key]!] = data;
                st.errors.remove(f.key);
                st.changed();
              },
            ),
        ]),
        for (final f in run) _err(f.key),
        const CaCaption('Only you and your coach can see your photos.', icon: AppIcons.lock),
      ];

  Widget _terms() {
    final paras = st.terms.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return Container(
      height: 260,
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
      child: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
            for (final (i, p) in paras.indexed)
              Text(p,
                  style: i > 0 && !p.startsWith('•') && p.length < 60
                      ? AppText.s(13.5, W.w8, h: 1.45)
                      : AppText.s(13, W.w4, color: AppColors.text2, h: 1.5)),
          ]),
        ),
      ),
    );
  }

  /// Questions the admin added to the onboarding form (no profile field): asked here, kept with the answers.
  List<Widget> _extras() => [
        for (final q in st.extra) ...[
          _Q(q.text, req: q.required, help: q.help),
          switch (q.type) {
            'single' || 'dropdown' || 'multiple' || 'yes_no' || 'scale' => CaChips<String>(
                options: q.type == 'yes_no' ? const ['Yes', 'No'] : (q.type == 'scale' ? [for (var n = 1; n <= 5; n++) '$n'] : q.options),
                label: (x) => q.type == 'scale' && q.scale.length == 5 ? '$x · ${q.scale[int.parse(x) - 1]}' : x,
                checkWhenOn: q.type == 'multiple',
                isOn: (x) {
                  final a = st.extraAnswers[q.id];
                  if (q.type == 'multiple') return (a as List? ?? const []).contains(x);
                  if (q.type == 'yes_no') return a == (x == 'Yes');
                  return '$a' == x;
                },
                onTap: (x) {
                  final a = st.extraAnswers[q.id];
                  final picked = a is List ? a : const [];
                  st.extraAnswers[q.id] = switch (q.type) {
                    'multiple' => [for (final e in picked) if (e != x) e, if (!picked.contains(x)) x],
                    'yes_no' => x == 'Yes',
                    'scale' => int.parse(x),
                    _ => x,
                  };
                  st.errors.remove('q${q.id}');
                  st.changed();
                },
              ),
            'number' => _Input(controller: _c('q${q.id}'), keyboard: const TextInputType.numberWithOptions(decimal: true)),
            _ => _Input(controller: _c('q${q.id}'), lines: q.type == 'long' ? 3 : 1),
          },
          _err('q${q.id}'),
        ],
      ];
}

/// `wl-q` with a red mark on required questions and the form's help line.
class _Q extends StatelessWidget {
  const _Q(this.title, {required this.req, this.help = ''});
  final String title, help;
  final bool req;
  @override
  Widget build(BuildContext context) => Pull(
        bottom: 4,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
          Text.rich(TextSpan(text: title, children: [if (req) TextSpan(text: ' *', style: AppText.s(15.5, W.w8, color: AppColors.badText))]), style: AppText.s(15.5, W.w8)),
          if (help.isNotEmpty) Text(help, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
        ]),
      );
}

/// `wl-fld` + `wl-in`: the setup input — one line (44 high) or a few lines — with the field label, a red mark on
/// required ones, a unit or "+91" and the error line. Typing follows the app's input rules (digits, decimals…).
class _Input extends StatefulWidget {
  const _Input({required this.controller, this.label, this.req = false, this.help = '', this.hint, this.error, this.keyboard, this.leading, this.trailing, this.lines = 1, this.maxLength, this.autofocus = false});
  final TextEditingController controller;
  final String? label, hint, error, leading, trailing;
  final bool req, autofocus;
  final String help;
  final TextInputType? keyboard;
  final int lines;
  final int? maxLength;

  @override
  State<_Input> createState() => _InputState();
}

class _InputState extends State<_Input> {
  final _focus = FocusNode();
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bad = widget.error != null;
    final focused = _focus.hasFocus;
    final border = bad ? AppColors.badText : (focused || _hover ? AppColors.accent : AppColors.line2);
    final multi = widget.lines > 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 5, children: [
      if (widget.label != null)
        Text.rich(
          TextSpan(text: widget.label, children: [if (widget.req) TextSpan(text: ' *', style: AppText.s(12.5, W.w7, color: AppColors.badText))]),
          style: AppText.s(12.5, W.w7, color: AppColors.text2),
        ),
      if (widget.help.isNotEmpty) Text(widget.help, style: AppText.s(12, W.w4, color: AppColors.muted)),
      MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.text,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: BoxConstraints(minHeight: multi ? 88 : 44),
          padding: EdgeInsets.fromLTRB(12, multi ? 10 : 0, widget.trailing == null ? 12 : 10, multi ? 10 : 0),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
            boxShadow: bad
                ? const [BoxShadow(color: AppColors.badBg, spreadRadius: 3)]
                : focused
                    ? const [BoxShadow(color: AppColors.accentSoft, spreadRadius: 3)]
                    : null,
          ),
          child: Row(crossAxisAlignment: multi ? CrossAxisAlignment.start : CrossAxisAlignment.center, spacing: 8, children: [
            if (widget.leading != null)
              Container(
                padding: const EdgeInsets.only(right: 6),
                decoration: const BoxDecoration(border: Border(right: BorderSide(color: AppColors.line))),
                child: Text(widget.leading!, style: AppText.s(14.5, W.w6, color: AppColors.muted)),
              ),
            Expanded(
              child: SizedBox(
                height: multi ? null : 44,
                child: Center(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    autofocus: widget.autofocus,
                    keyboardType: multi ? TextInputType.multiline : widget.keyboard,
                    minLines: widget.lines,
                    maxLines: multi ? 8 : 1,
                    inputFormatters: [...inputRules(widget.keyboard), if (widget.maxLength != null) LengthLimitingTextInputFormatter(widget.maxLength)],
                    cursorColor: AppColors.accent,
                    style: AppText.s(14.5, W.w6, h: multi ? 1.45 : null),
                    decoration: InputDecoration.collapsed(hintText: widget.hint, hintStyle: AppText.s(14.5, W.w5, color: AppColors.muted)),
                  ),
                ),
              ),
            ),
            if (widget.trailing != null) Text(widget.trailing!, style: AppText.s(13, W.w6, color: AppColors.muted)),
          ]),
        ),
      ),
      if (bad)
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: AppIcon(AppIcons.alert, size: 14, color: AppColors.badText)),
          Expanded(child: Text(widget.error!, style: AppText.s(12.5, W.w6, color: AppColors.badText, h: 1.4))),
        ]),
    ]);
  }
}

/// Date of birth: a box like the inputs that opens the date picker (dates are picked, not typed); the age shows.
class _DateInput extends StatelessWidget {
  const _DateInput({required this.label, required this.req, required this.value, required this.onPick, this.error});
  final String label;
  final bool req;
  final String? value, error;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final d = DateTime.tryParse(value ?? '');
    final bad = error != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 5, children: [
      Text.rich(
        TextSpan(text: label, children: [if (req) TextSpan(text: ' *', style: AppText.s(12.5, W.w7, color: AppColors.badText))]),
        style: AppText.s(12.5, W.w7, color: AppColors.text2),
      ),
      Hover(
        onTap: () async {
          final now = DateTime.now();
          final v = await showDatePicker(
            context: context,
            initialDate: d ?? DateTime(now.year - 25, now.month, 1),
            firstDate: DateTime(now.year - 100),
            lastDate: DateTime(now.year - 10, now.month, now.day),
            initialEntryMode: DatePickerEntryMode.calendarOnly,
          );
          if (v != null) onPick(DateFormat('yyyy-MM-dd').format(v));
        },
        builder: (_, h, _) => Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: bad ? AppColors.badText : (h ? AppColors.accent : AppColors.line2)),
            boxShadow: bad ? const [BoxShadow(color: AppColors.badBg, spreadRadius: 3)] : null,
          ),
          child: Row(spacing: 8, children: [
            Expanded(
              child: Text(d == null ? 'Pick your date of birth' : SetupState.dobLine(value),
                  style: AppText.s(14.5, d == null ? W.w5 : W.w6, color: d == null ? AppColors.muted : AppColors.text)),
            ),
            const AppIcon(AppIcons.calendar, size: 17, color: AppColors.muted),
          ]),
        ),
      ),
      if (bad)
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: AppIcon(AppIcons.alert, size: 14, color: AppColors.badText)),
          Expanded(child: Text(error!, style: AppText.s(12.5, W.w6, color: AppColors.badText, h: 1.4))),
        ]),
    ]);
  }
}

/// One start photo (front / right side / back): tap to take or choose it; a picked or saved photo shows with Change.
class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({required this.label, required this.saved, required this.picked, required this.bad, required this.onPick});
  final String label;
  final String? saved, picked;
  final bool bad;
  final ValueChanged<String> onPick;

  Future<void> _pick(BuildContext context, bool camera) async {
    try {
      final x = await ImagePicker().pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
      if (x == null) return;
      final b = await x.readAsBytes();
      if (b.length > 10 * 1024 * 1024) {
        if (context.mounted) showToast(context, 'This photo is too big', sub: 'Photos can be up to 10 MB', kind: ToastKind.warn);
        return;
      }
      final mime = (x.mimeType ?? '').startsWith('image/') ? x.mimeType! : (x.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
      onPick('data:$mime;base64,${base64Encode(b)}');
    } catch (_) {
      if (context.mounted) showToast(context, 'Could not open the photos', sub: 'Allow photo access for the app in your phone settings', kind: ToastKind.warn);
    }
  }

  void _choose(BuildContext context) {
    if (!context.isPhone) {
      _pick(context, false);
      return;
    }
    showActionSheet(context, [
      MenuEntry('Take photo', icon: AppIcons.camera, onTap: () => _pick(context, true)),
      MenuEntry('Choose from photos', icon: AppIcons.photo, onTap: () => _pick(context, false)),
    ], title: label);
  }

  @override
  Widget build(BuildContext context) {
    final has = picked != null || saved != null;
    return Hover(
      onTap: () => _choose(context),
      builder: (_, h, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        AspectRatio(
          aspectRatio: 3 / 4,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: has ? AppColors.sub : (h ? AppColors.pickBg : AppColors.white),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: bad ? AppColors.badText : (h ? AppColors.accent : AppColors.line2)),
            ),
            child: picked != null
                ? Image.memory(base64Decode(picked!.split(',').last), fit: BoxFit.cover)
                : saved != null
                    ? NetImage(saved!, fit: BoxFit.cover)
                    : Column(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
                        const AppIcon(AppIcons.camera, size: 22, color: AppColors.muted),
                        Text('Add', style: AppText.s(12.5, W.w7, color: AppColors.text2)),
                      ]),
          ),
        ),
        Row(children: [
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w7))),
          if (has) Text('Change', style: AppText.s(12, W.w7, color: AppColors.accentText)),
        ]),
      ]),
    );
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
      if (saveStep != null && !st.done.contains(saveStep) && st.need(saveStep, mark: false) == null) await st.save(saveStep);
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
