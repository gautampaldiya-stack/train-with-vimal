import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/back_nav.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/api/api_error.dart';
import '../home/home_model.dart' show clock;
import 'checkins_model.dart';
import 'checkins_parts.dart';

/// Daily check-in (board ClientCheckin, `isDaily`): every question on one page, then "Sent to Aman".
/// [edit] opens today's answers to change them.
class DailyCheckin extends StatefulWidget {
  const DailyCheckin({super.key, required this.c, required this.edit, this.back = '/checkins'});
  final CheckinsController c;
  final bool edit;

  /// Where back goes: Check-ins, or Home when it was opened from the Home card (Fill now).
  final String back;
  @override
  State<DailyCheckin> createState() => _DailyCheckinState();
}

class _DailyCheckinState extends State<DailyCheckin> {
  CheckinsController get c => widget.c;
  final _v = <int, Object?>{};
  final _texts = <int, TextEditingController>{};
  bool _editing = false, _filled = false, _busy = false;
  CkRow? _sent; // sent from this page (shown even before the reload)

  @override
  void initState() {
    super.initState();
    _editing = widget.edit;
  }

  @override
  void dispose() {
    for (final t in _texts.values) {
      t.dispose();
    }
    super.dispose();
  }

  CkDaily get d => c.data!.daily;
  CkForm get f => d.form!;

  /// Only the coach's own questions, each answered the way its type asks (E25). Photos and body measurements
  /// belong to the weekly check-in, so the daily one never asks them.
  List<CkQ> get qs => [
    for (final q in f.questions)
      if (q.type != 'photo' && q.type != 'measures') q,
  ];
  CkRow? get today => _sent ?? d.sent ?? CheckinsController.queuedDaily;
  String get coach => c.data!.coachFirst;

  /// Fills the answers once: today's check-in when editing, else the weight to start from.
  void _fill() {
    if (_filled || c.data == null || d.form == null) return;
    _filled = true;
    if (!_editing) _readDraft();
    final m = today?.metrics ?? const {};
    final a = today?.answers ?? const {};
    for (final q in qs) {
      // The answer as sent; older rows only have the numbers (metrics), so fit those to the question.
      final sent = a['${q.id}'];
      final v = sent ?? m[q.metric];
      if (q.metric == 'weight') {
        _v[q.id] = (v is num ? v.toDouble() : null) ?? d.todayWeight ?? d.lastWeight ?? 70.0;
      } else if (v == null) {
        continue;
      } else if (q.type == 'scale') {
        _v[q.id] = q.scaleOf(sent) ?? (q.metric == 'sleep_hours' && v is num ? _hoursToScale(q, v) : q.scaleOf(v));
      } else if (q.type == 'multiple') {
        if (v is List) _v[q.id] = [...v];
      } else if (q.isChoice) {
        final o = v is bool ? (v ? 'Yes' : 'No') : (v is num && q.metric == 'sleep_hours' ? hrs(v) : '$v');
        if (q.options.contains(o) || o.toLowerCase().startsWith('other:')) _v[q.id] = q.type == 'yes_no' ? o == 'Yes' : o;
      } else if (q.type == 'number') {
        if (v is num) _v[q.id] = v.toDouble();
      } else {
        _v[q.id] = '$v';
      }
    }
  }

  /// Sleep hours on a 5-point scale whose labels are hours ("5h" … "9h").
  int? _hoursToScale(CkQ q, num h) {
    for (final (i, l) in q.labels.indexed) {
      if (double.tryParse(l.replaceAll(RegExp(r'[^0-9.]'), '')) == h.toDouble()) return i + 1;
    }
    return q.scaleOf(h - 4);
  }

  bool _has(CkQ q) => _v[q.id] != null && _v[q.id] != '' && !(_v[q.id] is List && (_v[q.id] as List).isEmpty);
  List<CkQ> get _missing => [
    for (final q in qs)
      if (q.required && !_has(q)) q,
  ];

  void _set(CkQ q, Object? v) {
    setState(() => _v[q.id] = v);
    _dirty = true;
  }

  /// Answers changed on this page and not sent yet.
  bool _dirty = false;

  /// A draft saved by "Save and continue later" comes back the next time the page opens (today only).
  Future<void> _readDraft() async {
    if (today != null) return;
    final dr = await c.readDailyDraft(d.date);
    if (dr == null || !mounted) return;
    setState(() {
      for (final MapEntry(:key, :value) in ((dr['answers'] as Map?) ?? const {}).entries) {
        final id = int.tryParse('$key');
        if (id != null && value != null) _v[id] = value;
      }
      for (final t in _texts.values) {
        t.dispose();
      }
      _texts.clear();
    });
  }

  /// Back: out of Edit answers, else off the page.
  void _close() => _editing && today != null ? setState(() => _editing = false) : context.go(widget.back);

  /// Leaving with changed answers that are not sent asks (E32).
  Future<void> _leave(VoidCallback go) async {
    if (!_dirty || (today != null && !_editing)) return go();
    final keep = await ckAskLeave(context);
    if (keep == null || !mounted) return;
    if (keep && today == null) {
      await c.saveDailyDraft(d.date, {'answers': {for (final e in _v.entries) '${e.key}': e.value}});
      if (mounted) showToast(context, 'Draft saved', sub: '${qs.where(_has).length} of ${qs.length} answered · finish it today', kind: ToastKind.info);
    } else if (!keep) {
      await c.saveDailyDraft(d.date, null);
      if (_editing) {
        _filled = false;
        _v.clear();
      }
    }
    _dirty = false;
    if (mounted) go();
  }

  Future<void> _send() async {
    final miss = _missing;
    if (miss.isNotEmpty) {
      showToast(
        context,
        miss.length == 1 ? 'Answer "${miss.first.text}" first' : 'Answer ${miss.length} more questions first',
        sub: miss.length == 1 ? 'This one is required' : miss.map((q) => q.text).take(3).join(', '),
        kind: ToastKind.warn,
      );
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    final answers = {
      for (final q in qs)
        if (_has(q)) '${q.id}': _v[q.id],
    };
    // No note box any more (E25): an edit keeps the note an older check-in had.
    final note = '${today?.metrics['note'] ?? ''}';
    try {
      if (_editing && today?.id != null) {
        await c.edit(f, today!.id!, answers, note: note);
        _dirty = false;
        if (!mounted) return;
        setState(() => _editing = false);
        showToast(context, 'Daily check-in updated', sub: '$coach will see it today', kind: ToastKind.ok);
      } else {
        final row = await c.send(f, answers, note: note, day: d.date);
        _dirty = false;
        await c.saveDailyDraft(d.date, null);
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
      if (mounted) showToast(context, 'Could not send it', sub: _why(e), kind: ToastKind.err);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The server's reason, named by the question it is about ("Weight: Enter your weight in kg.").
  String _why(Object e) {
    if (e is! ApiError) return 'Try again in a moment';
    for (final MapEntry(:key, :value) in e.fields.entries) {
      final q = qs.where((q) => '${q.id}' == key).firstOrNull;
      if (q != null && value.isNotEmpty) return '${q.text}: ${value.first}';
    }
    return e.offline ? 'You are offline. Try again when you are online' : e.shown;
  }

  /// The phone's back button closes the edit first, like the page's own back (Phase 4).
  @override
  Widget build(BuildContext context) => BackIntercept(
    onBack: () {
      final closeEdit = _editing && today != null;
      if (!_dirty && !closeEdit && widget.back == '/checkins') return false;
      _leave(_close);
      return true;
    },
    child: Builder(builder: _page),
  );

  Widget _page(BuildContext context) => ListenableBuilder(
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
      final answered = qs.where(_has).length;
      final total = qs.length;
      // Older than yesterday: view only (E37, like Food). Not sent then: missed.
      if (!d.editable && today == null) {
        return CkPage(
          web: web,
          header: [CkTop(title: 'Daily check-in', sub: dayShortNoYear(d.date), onBack: () => context.go(widget.back))],
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text('Missed · this day can\'t be filled any more.\nOnly today and yesterday can be filled.',
                  textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted, h: 1.5)),
            ),
          ],
        );
      }
      final showForm = d.editable && (today == null || _editing);
      return CkPage(
        web: web,
        header: [
          CkTop(
            title: 'Daily check-in',
            sub: '${d.isYesterday ? 'Yesterday, ' : ''}${dayShortNoYear(d.date)} · $answered of $total answered',
            onBack: () => _leave(_close),
          ),
          CkBar(total == 0 ? 0 : answered / total),
        ],
        children: showForm ? _form() : [_done()],
      );
    },
  );

  List<Widget> _form() => [
    if (f.description.isNotEmpty) Text(f.description, style: AppText.s(13, W.w5, color: AppColors.text2, h: 1.45)),
    for (final q in qs) _question(q),
    // Editing a sent check-in saves the changes; a new one is sent.
    if (_editing && today?.id != null)
      CaButton('Save changes', icon: AppIcons.check, dimmed: _missing.isNotEmpty, loading: _busy, onPressed: _send)
    else
      CaButton('Send to $coach', icon: AppIcons.send, dimmed: _missing.isNotEmpty, loading: _busy, onPressed: _send),
  ];

  String _tag(CkQ q) => q.required ? 'Required' : 'Optional';

  Widget _question(CkQ q) {
    final v = _v[q.id];
    final title = q.text;
    if (q.type == 'number' && q.asField) {
      // a plain number box (the coach chose Field)
      final t = _texts[q.id] ??= TextEditingController(text: v == null ? '' : (v as num).toDouble().toStringAsFixed(1));
      return CkQCard(
        title: title,
        sub: q.help,
        label: _tag(q),
        got: v != null,
        children: [
          CkInput(
            controller: t,
            hint: 'Type a number',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            onChanged: () => _set(q, double.tryParse(t.text.trim().replaceAll(',', '.'))),
          ),
        ],
      );
    }
    if (q.type == 'number') {
      // − / + starts from her last weight (weight) or the coach's minimum, never below it (E30 submit error).
      final x = (v as num?)?.toDouble() ?? q.last ?? q.min ?? 0;
      double fit(double n) => n.clamp(q.min ?? -1e9, q.max ?? 1e9).toDouble();
      final last = d.lastWeight, when = d.lastWeightDate;
      final diff = q.metric == 'weight' && last != null && when != null ? '${kgChange(x - last, zero: '±0.0 kg')} since ${dayName(when)}' : _tag(q);
      return CkQCard(
        title: title,
        sub: q.help,
        label: diff,
        children: [
          CkStepper(
            value: x.toStringAsFixed(1),
            suffix: q.metric == 'weight' ? 'kg' : null,
            onMinus: () => _set(q, fit(((x - q.step) * 100).round() / 100)),
            onPlus: () => _set(q, fit(((x + q.step) * 100).round() / 100)),
            onType: (n) => _set(q, n),
          ),
        ],
      );
    }
    final label = v == null ? (q.required ? 'Pick one' : 'Optional') : (q.type == 'scale' ? (q.show(v, short: true) ?? 'Pick one') : (q.show(v) ?? '$v'));
    if (q.isChoice || q.type == 'multiple') {
      return CkQCard(
        title: title,
        sub: q.help,
        label: q.type == 'multiple' && v == null ? (q.required ? 'Pick one or more' : 'Optional') : label,
        got: v != null,
        children: [CkChoice(q: q, value: v, onChanged: (x) => _set(q, x))],
      );
    }
    if (q.type == 'scale') {
      return CkQCard(
        title: title,
        sub: q.help,
        label: label,
        got: v != null,
        children: [CkScale(labels: q.labels, value: q.scaleOf(v), onPick: (n) => _set(q, n))],
      );
    }
    final t = _texts[q.id] ??= TextEditingController(text: '${v ?? ''}');
    void changed() => _set(q, t.text.trim().isEmpty ? null : t.text.trim());
    return CkQCard(
      title: title,
      sub: q.help,
      label: _tag(q),
      got: v != null,
      children: [
        CkInput(controller: t, hint: 'Type your answer', area: q.type == 'long', onChanged: changed),
        // The coach's own chips; none = no chips.
        if (q.suggestions.isNotEmpty)
          CkTry(
            lead: 'Tap to add',
            items: q.suggestions,
            onPick: (x) {
              final n = t.text.trim();
              t.text = n.isNotEmpty && !n.contains(x) ? '$n. $x' : (n.contains(x) ? n : x);
              changed();
            },
          ),
      ],
    );
  }

  Widget _done() {
    final row = today!;
    final at = row.sentAt ?? DateTime.now();
    final rows = <(String, String)>[
      for (final q in qs)
          (
            q.text,
            q.metric == 'sleep_hours' && row.metrics['sleep_hours'] is num
                ? hrs(row.metrics['sleep_hours'] as num)
                : q.show(row.answers['${q.id}'] ?? _v[q.id] ?? row.metrics[q.metric], short: true) ?? '—',
          ),
      if ('${row.metrics['note'] ?? ''}'.isNotEmpty) ('Note', '${row.metrics['note']}'),
    ];
    return CkDone(
      title: 'Sent to $coach',
      sub: row.id == null ? 'Saved on this phone · it goes to $coach when you are online' : '${DateUtils.isSameDay(row.date, DateTime.now()) ? 'Today' : dayShortNoYear(row.date)}\'s check-in · sent at ${clock(at)}',
      rows: rows,
      photos: row.thumbs,
      buttons: Row(
        spacing: 8,
        children: [
          if (d.editable)
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

/// "Thu, 15 Oct"
String dayShortNoYear(DateTime d) =>
    '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1]}, ${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';

/// "Thu"
String dayName(DateTime d) => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
