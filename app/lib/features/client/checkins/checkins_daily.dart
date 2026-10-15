import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../home/home_model.dart' show clock, inNum, litres;
import 'checkins_model.dart';
import 'checkins_parts.dart';

/// Daily check-in (board ClientCheckin, `isDaily`): every question on one page, then "Sent to Aman".
/// [edit] opens today's answers to change them.
class DailyCheckin extends StatefulWidget {
  const DailyCheckin({super.key, required this.c, required this.edit});
  final CheckinsController c;
  final bool edit;
  @override
  State<DailyCheckin> createState() => _DailyCheckinState();
}

class _DailyCheckinState extends State<DailyCheckin> {
  CheckinsController get c => widget.c;
  final _note = TextEditingController();
  final _v = <int, Object?>{};
  bool _editing = false, _filled = false, _busy = false;
  CkRow? _sent; // sent from this page (shown even before the reload)

  static const _chips = ['Felt strong today', 'Knee a bit sore', 'Slept late', 'Busy day at work'];
  static const _short = {'sleep_hours': 'Sleep', 'weight': 'Morning weight'};

  @override
  void initState() {
    super.initState();
    _editing = widget.edit;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  CkDaily get d => c.data!.daily;
  CkForm get f => d.form!;
  CkRow? get today => _sent ?? d.sent ?? CheckinsController.queuedDaily;
  String get coach => c.data!.coachFirst;

  /// Fills the answers once: today's check-in when editing, else the weight to start from.
  void _fill() {
    if (_filled || c.data == null || d.form == null) return;
    _filled = true;
    final m = today?.metrics ?? const {};
    final a = today?.answers ?? const {};
    for (final q in f.questions) {
      // The answer as sent; older rows only have the numbers (metrics), so fit those to the question.
      final sent = a['${q.id}'];
      final v = sent ?? m[q.metric];
      if (q.metric == 'weight') {
        _v[q.id] = (v is num ? v.toDouble() : null) ?? d.todayWeight ?? d.lastWeight ?? 70.0;
      } else if (v == null) {
        continue;
      } else if (q.type == 'scale') {
        _v[q.id] = q.scaleOf(sent) ?? (q.metric == 'sleep_hours' && v is num ? _hoursToScale(q, v) : q.scaleOf(v));
      } else if (q.isChoice) {
        final o = v is bool ? (v ? 'Yes' : 'No') : (v is num && q.metric == 'sleep_hours' ? hrs(v) : '$v');
        if (q.options.contains(o)) _v[q.id] = q.type == 'yes_no' ? o == 'Yes' : o;
      } else if (q.type == 'number') {
        if (v is num) _v[q.id] = v.toDouble();
      } else {
        _v[q.id] = '$v';
      }
    }
    _note.text = '${m['note'] ?? ''}';
  }

  /// Sleep hours on a 5-point scale whose labels are hours ("5h" … "9h").
  int? _hoursToScale(CkQ q, num h) {
    for (final (i, l) in q.labels.indexed) {
      if (double.tryParse(l.replaceAll(RegExp(r'[^0-9.]'), '')) == h.toDouble()) return i + 1;
    }
    return q.scaleOf(h - 4);
  }

  bool _has(CkQ q) => _v[q.id] != null && _v[q.id] != '';
  List<CkQ> get _missing => [
    for (final q in f.questions)
      if (q.required && !_has(q)) q,
  ];

  void _set(CkQ q, Object? v) => setState(() => _v[q.id] = v);

  Future<void> _send() async {
    final miss = _missing;
    if (miss.isNotEmpty) {
      showToast(
        context,
        'Answer ${miss.map((q) => (_short[q.metric] ?? q.text).toLowerCase()).join(', ')} first',
        sub: 'Only the note is optional',
        kind: ToastKind.warn,
      );
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    final answers = {
      for (final q in f.questions)
        if (_has(q)) '${q.id}': _v[q.id],
    };
    final note = _note.text.trim();
    try {
      if (_editing && today?.id != null) {
        await c.edit(f, today!.id!, answers, note: note);
        if (!mounted) return;
        setState(() => _editing = false);
        showToast(context, 'Daily check-in updated', sub: '$coach will see it today', kind: ToastKind.ok);
      } else {
        final row = await c.send(f, answers, note: note);
        if (!mounted) return;
        setState(() {
          _sent = row;
          _editing = false;
        });
        final streak = c.data!.streak + (d.sent == null ? 1 : 0);
        final off = row.id == null;
        showToast(
          context,
          'Daily check-in sent',
          sub: off ? 'Saved on this phone · it goes to $coach when you are online' : '$coach will see it today · $streak-day streak',
          kind: ToastKind.ok,
          action: off ? null : 'Undo',
          onAction: off
              ? null
              : () async {
                  await c.undo(row, 'daily');
                  if (mounted) setState(() => _sent = null);
                },
        );
      }
    } catch (e) {
      if (mounted) showToast(context, 'Could not send it', sub: '$e', kind: ToastKind.err);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (c.data == null || d.form == null) {
        return Center(
          child: c.error == null && c.data == null
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))
              : Text(c.error?.message ?? 'There is no daily check-in to fill.', style: AppText.s(13, W.w5, color: AppColors.muted)),
        );
      }
      _fill();
      final web = !context.isPhone;
      final answered = f.questions.where(_has).length;
      final total = f.questions.length;
      final showForm = today == null || _editing;
      return CkPage(
        web: web,
        header: [
          CkTop(
            title: 'Daily check-in',
            sub: '${dayShortNoYear(d.date)} · $answered of $total answered',
            onBack: () => _editing && today != null ? setState(() => _editing = false) : context.go('/checkins'),
          ),
          CkBar(total == 0 ? 0 : answered / total),
        ],
        children: showForm ? _form() : [_done()],
      );
    },
  );

  List<Widget> _form() => [
    for (final q in f.questions) _question(q),
    CkQCard(
      title: 'Anything else?',
      label: 'Optional',
      children: [
        CkInput(controller: _note, hint: 'Type a note for $coach, or tap a suggestion', onChanged: () => setState(() {})),
        CkTry(
          items: _chips,
          onPick: (t) {
            final n = _note.text.trim();
            _note.text = n.isNotEmpty && !n.contains(t) ? '$n. $t' : (n.contains(t) ? n : t);
            setState(() {});
          },
        ),
      ],
    ),
    if (_autoLine() != null) ckInfo(_autoLine()!),
    CaButton('Send to $coach', icon: AppIcons.send, dimmed: _missing.isNotEmpty, loading: _busy, onPressed: _send),
  ];

  /// `ck-auto`: what the check-in takes from Habits.
  String? _autoLine() {
    final st = d.steps == null ? null : 'Steps (${inNum(d.steps!)})';
    final w = d.waterMl == null ? null : 'water (${litres(d.waterMl!)})';
    if (st != null && w != null) return '$st and $w come from your habits, so you do not need to add them.';
    if (st != null) return '$st come from your habits, so you do not need to add them.';
    if (w != null) return 'Water (${litres(d.waterMl!)}) comes from your habits, so you do not need to add it.';
    return null;
  }

  Widget _question(CkQ q) {
    final v = _v[q.id];
    final title = q.metric == 'weight' ? 'Morning weight' : q.text;
    if (q.metric == 'weight' || q.type == 'number') {
      final x = (v as num?)?.toDouble() ?? 0;
      final last = d.lastWeight, when = d.lastWeightDate;
      final diff = q.metric == 'weight' && last != null && when != null ? '${kgChange(x - last, zero: '±0.0 kg')} since ${dayName(when)}' : '';
      return CkQCard(
        title: title,
        label: diff,
        children: [
          CkStepper(
            value: q.metric == 'weight' ? kg(x) : x.toStringAsFixed(1),
            onMinus: () => _set(q, ((x - .1) * 10).round() / 10),
            onPlus: () => _set(q, ((x + .1) * 10).round() / 10),
          ),
        ],
      );
    }
    final label = v == null ? 'Pick one' : (q.type == 'scale' ? (q.show(v, short: true) ?? 'Pick one') : (q.show(v) ?? '$v'));
    if (q.isChoice) {
      return CkQCard(
        title: title,
        label: label,
        got: v != null,
        children: [
          CkChoiceGrid(options: q.options, value: v is bool ? (v ? 'Yes' : 'No') : v as String?, onPick: (o) => _set(q, q.type == 'yes_no' ? o == 'Yes' : o)),
        ],
      );
    }
    if (q.type == 'scale') {
      return CkQCard(
        title: title,
        label: label,
        got: v != null,
        children: [CkScale(labels: q.labels, value: q.scaleOf(v), onPick: (n) => _set(q, n))],
      );
    }
    return CkQCard(
      title: title,
      label: q.required ? 'Required' : 'Optional',
      children: [_TextAnswer(initial: '${v ?? ''}', onChanged: (t) => _v[q.id] = t.trim().isEmpty ? null : t.trim())],
    );
  }

  Widget _done() {
    final row = today!;
    final at = row.sentAt ?? DateTime.now();
    final rows = <(String, String)>[
      for (final q in f.questions)
        if (q.type != 'photo')
          (
            _short[q.metric] ?? q.text,
            q.metric == 'sleep_hours' && row.metrics['sleep_hours'] is num
                ? hrs(row.metrics['sleep_hours'] as num)
                : q.show(row.answers['${q.id}'] ?? _v[q.id] ?? row.metrics[q.metric], short: true) ?? '—',
          ),
      ('Note', '${row.metrics['note'] ?? ''}'.isEmpty ? '—' : '${row.metrics['note']}'),
    ];
    return CkDone(
      title: 'Sent to $coach',
      sub: row.id == null ? 'Saved on this phone · it goes to $coach when you are online' : 'Today at ${clock(at)} · $coach will see it today',
      rows: rows,
      photos: row.thumbs,
      buttons: Row(
        spacing: 8,
        children: [
          Expanded(
            flex: 5,
            child: CaButton(
              'Edit answers',
              kind: CaBtnKind.out,
              icon: MediaQuery.sizeOf(context).width < 420 ? null : AppIcons.edit,
              onPressed: () {
                if (row.id == null) {
                  showToast(context, 'Still sending', sub: 'You can edit it once it reaches $coach', kind: ToastKind.info);
                  return;
                }
                setState(() => _editing = true);
              },
            ),
          ),
          Expanded(flex: 6, child: CaButton('Back to check-ins', onPressed: () => context.go('/checkins'))),
        ],
      ),
    );
  }
}

class _TextAnswer extends StatefulWidget {
  const _TextAnswer({required this.initial, required this.onChanged});
  final String initial;
  final ValueChanged<String> onChanged;
  @override
  State<_TextAnswer> createState() => _TextAnswerState();
}

class _TextAnswerState extends State<_TextAnswer> {
  late final t = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CkInput(controller: t, hint: 'Type your answer', area: true, onChanged: () => widget.onChanged(t.text));
}

/// "Thu, 15 Oct"
String dayShortNoYear(DateTime d) =>
    '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1]}, ${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';

/// "Thu"
String dayName(DateTime d) => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
