import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import '../../../core/widgets/tooltip.dart';
import 'cp_common.dart';
import 'cp_content_drawers.dart';
import 'cp_model.dart';

/// Answer types the per-client editor offers (a choice question keeps its own type and options).
const cpAnswerTypes = [
  ('short', 'Short text'),
  ('long', 'Text'),
  ('number', 'Number'),
  ('scale', 'Scale 1–5'),
  ('yes_no', 'Yes / no'),
  ('photo', 'Photo'),
];
const _choiceLabels = {'single': 'One choice', 'multiple': 'Choices', 'dropdown': 'Dropdown'};

class _Q {
  _Q(Map j)
      : id = (j['id'] as num?)?.toInt(),
        text = TextEditingController(text: '${j['text'] ?? ''}'),
        type = '${j['type'] ?? 'short'}',
        required = j['required'] == true,
        options = [for (final o in (j['options'] as List? ?? const [])) '$o'],
        change = '${j['change'] ?? ''}',
        key = UniqueKey();
  final int? id;
  final TextEditingController text;
  String type;
  bool required;
  final List<String> options;
  final String change;
  final Key key;
  String? error;

  Map<String, dynamic> toJson() => {if (id != null) 'id': id, 'text': text.text.trim(), 'type': type, 'required': required, 'options': options};
}

/// What the Send a form drawer passes to "Edit her copy before sending".
class CpSendOpts {
  const CpSendOpts(this.body);
  final Map<String, dynamic> body; // mode, send, answer_days, every, weekday, month_day, time, until, by, remind
}

/// The per-client form editor of the Forms tab, two ways (as on the board):
/// * `Edit Weekly check-in for Riya` ([dup] false): her copy changes; the master and other clients stay the same.
/// * `New form for Riya: copy of …` ([dup] true): Form name · First send · Instead of, then Send copy.
/// [source] is a list key of the tab (`weekly`, `req:<id>` …) or, from Send a form, a library form id in [formId].
class CpFormEditor extends StatefulWidget {
  const CpFormEditor({
    super.key,
    required this.c,
    required this.dup,
    this.source,
    this.formId,
    required this.name,
    this.sendOpts,
    this.sending = const [],
    required this.onDone,
    required this.onCancel,
  });
  final CpController c;
  final bool dup;
  final String? source, formId;
  final String name;
  final CpSendOpts? sendOpts;

  /// (key, name) of the forms she gets now, for "Instead of".
  final List<(String, String)> sending;
  final ValueChanged<String?> onDone;
  final VoidCallback onCancel;

  @override
  State<CpFormEditor> createState() => _CpFormEditorState();
}

class _CpFormEditorState extends State<CpFormEditor> {
  CpController get c => widget.c;
  final _hScroll = ScrollController();
  late final _name = TextEditingController(text: '${widget.name} · ${widget.c.first}');
  List<_Q> qs = [];
  Map sched = const {};
  String changes = '', master = '';
  bool loading = true, busy = false, weekly = false;
  ApiError? error;
  String? nameError, listError;
  DateTime? firstSend;
  late String insteadOf = widget.source != null && widget.sending.any((s) => s.$1 == widget.source) ? widget.source! : '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    firstSend = DateTime(now.year, now.month, now.day).add(Duration(days: (7 - now.weekday) % 7 == 0 ? 7 : (7 - now.weekday) % 7));
    _load();
  }

  @override
  void dispose() {
    _hScroll.dispose();
    _name.dispose();
    for (final q in qs) {
      q.text.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final Map r;
      if (widget.source != null) {
        r = await Services.api.get<Map>('clients/${c.id}/forms/${widget.source}/questions/');
        sched = (r['schedule'] as Map?) ?? const {};
        changes = '${r['changes'] ?? ''}';
        master = '${r['master_name'] ?? r['name'] ?? ''}';
      } else {
        r = await Services.api.get<Map>('forms/${widget.formId}/');
        master = '${r['name'] ?? ''}';
        changes = 'no changes yet';
      }
      weekly = '${r['type'] ?? ''}' == 'weekly' || widget.source == 'weekly';
      qs = [for (final q in (r['questions'] as List? ?? const [])) _Q(q as Map)];
      error = null;
    } on ApiError catch (e) {
      error = e;
    }
    if (mounted) setState(() => loading = false);
  }

  String _sendLine() {
    final o = widget.sendOpts?.body;
    if (o == null) return '';
    return o['mode'] == 'repeat' ? 'Repeats' : (o['send'] == 'now' ? 'Now' : 'Once');
  }

  bool _check() {
    var ok = true;
    for (final q in qs) {
      q.error = q.text.text.trim().isEmpty ? 'Enter the question.' : null;
      if (q.error != null) ok = false;
    }
    listError = qs.isEmpty ? 'Keep at least one question.' : null;
    nameError = widget.dup && _name.text.trim().length < 2 ? 'Enter a form name.' : null;
    setState(() {});
    return ok && listError == null && nameError == null;
  }

  Future<void> _save() async {
    if (!_check()) return;
    setState(() => busy = true);
    final qsJson = [for (final q in qs) q.toJson()];
    try {
      if (widget.dup) {
        final r = await Services.api.post<Map>('clients/${c.id}/forms/duplicate/', {
          ...?widget.sendOpts?.body,
          if (widget.source != null) 'source': widget.source else 'form': widget.formId,
          'name': _name.text.trim(),
          'questions': qsJson,
          if (!weekly && firstSend != null && widget.sendOpts == null) 'first_send': DateFormat('yyyy-MM-dd').format(firstSend!),
          'instead_of': insteadOf,
        });
        if (!mounted) return;
        showToast(context, 'New form sent to ${c.first}', sub: _name.text.trim());
        widget.onDone('${r['key'] ?? ''}');
      } else {
        await Services.api.put('clients/${c.id}/forms/${widget.source}/questions/', {'questions': qsJson});
        if (!mounted) return;
        showToast(context, 'Saved for ${c.first}', sub: 'The master form stays the same');
        widget.onDone(widget.source);
      }
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          nameError = e.field('name');
        });
        if (e.field('name') == null) showToast(context, 'Could not save', sub: e.message);
      }
    }
  }

  Future<void> _reset() async {
    final ok = await confirmAction(context,
        title: 'Reset to master?',
        body: 'Every change made for ${c.first} goes away. ${cpShe(c)[0].toUpperCase()}${cpShe(c).substring(1)} gets the master form again. Answers already sent are kept.',
        confirm: 'Reset to master',
        danger: true,
        icon: AppIcons.reset);
    if (!ok || !mounted) return;
    try {
      final r = await Services.api.post<Map>('clients/${c.id}/forms/${widget.source}/reset/');
      if (!mounted) return;
      showToast(context, '${r['message'] ?? 'Reset to master'}');
      widget.onDone(widget.source);
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not reset', sub: e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const AppCard(child: CpLoading());
    if (error != null) return CpError(error!.message, onRetry: _load);
    final phone = context.isPhone;
    final first = c.first;
    final copy = changes.isNotEmpty && changes != 'no changes' && changes != 'no changes yet';
    final tip = widget.dup
        ? 'A new form only for $first. The form ${cpShe(c)} has now keeps going until you stop it. The master stays the same.'
        : 'Only $first’s copy changes. The master form and other clients stay the same. Answers ${cpShe(c)} already sent are kept.';
    final bar = Row(spacing: 8, children: [
      AppButton(phone ? 'Back' : 'Back to form', icon: AppIcons.chevronLeft, onPressed: widget.onCancel),
      const Spacer(),
      if (!widget.dup && copy && !phone) AppButton('Reset to master', kind: BtnKind.text, icon: AppIcons.reset, onPressed: _reset),
      if (!phone) AppButton('Cancel', onPressed: widget.onCancel),
      AppButton.primary(widget.dup ? 'Send copy' : 'Save for $first', icon: widget.dup ? AppIcons.send : AppIcons.check, loading: busy, onPressed: _save),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      bar,
      Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
        Row(spacing: 6, children: [
          Flexible(child: Text(widget.dup ? 'New form for $first: copy of $master' : 'Edit ${widget.name} for $first', style: AppText.h3)),
          AppTooltip(message: tip, side: TipSide.below, child: const AppIcon(AppIcons.info, size: 16, color: AppColors.muted)),
        ]),
        Text(widget.dup ? 'Change the questions and schedule, then send.' : 'From master "$master" · ${changes.isEmpty ? 'no changes yet' : changes}', style: AppText.cap),
      ]),
      if (!widget.dup && copy && phone) Align(alignment: Alignment.centerLeft, child: AppButton('Reset to master', kind: BtnKind.text, icon: AppIcons.reset, onPressed: _reset)),
      if (widget.dup) _dupBar(context),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sendRow(),
          _table(),
          if (listError != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 6), child: Text(listError!, style: AppText.s(12, W.w6, color: AppColors.badText))),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppButton('Add question', kind: BtnKind.text, icon: AppIcons.plus, onPressed: () => setState(() => qs.add(_Q(const {'type': 'short', 'required': false})))),
            ),
          ),
        ]),
      ),
    ]);
  }

  // `.cp-dupbar`: Form name · First send · Instead of.
  Widget _dupBar(BuildContext context) {
    final fields = [
      drField('Form name', AppTextField(controller: _name), error: nameError),
      drField(
        'First send',
        weekly
            ? AppSelect(DateFormat('EEE, d MMM').format(firstSend!), entries: const [])
            : (widget.sendOpts != null ? AppSelect(_sendLine(), entries: const []) : DrDateBox(firstSend, onPick: (d) => setState(() => firstSend = d))),
      ),
      drField(
        'Instead of',
        AppSelect(
          insteadOf.isEmpty ? 'Nothing, send both' : widget.sending.firstWhere((s) => s.$1 == insteadOf, orElse: () => (insteadOf, insteadOf)).$2,
          entries: [
            MenuEntry('Nothing, send both', selected: insteadOf.isEmpty, onTap: () => setState(() => insteadOf = '')),
            for (final (k, n) in widget.sending) MenuEntry(n, selected: insteadOf == k, onTap: () => setState(() => insteadOf = k)),
          ],
        ),
      ),
    ];
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: context.isPhone
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: fields)
          : Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [for (final f in fields) Expanded(child: f)]),
    );
  }

  // `.cp-edday`: Send · Every Sunday · 6:00 pm · Push + WhatsApp.
  Widget _sendRow() {
    Widget box(String t, double w) => Container(
          width: w,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.input), border: Border.all(color: AppColors.line2)),
          child: CutText(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w6)),
        );
    final o = widget.sendOpts?.body;
    final label = weekly
        ? 'Every Sunday'
        : (o != null ? (o['mode'] == 'repeat' ? 'Repeats' : 'Once') : '${sched['label'] ?? 'Once'}');
    final time = weekly ? '6:00 pm' : '${sched['time'] ?? ''}';
    final by = '${sched['by'] ?? 'Push'}';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Send', style: AppText.s(12, W.w7)),
        box(label, 150),
        if (time.isNotEmpty && !widget.dup) box(time, 90),
        if (!widget.dup) box(by, 170),
      ]),
    );
  }

  static const _cols = <(String, double)>[('', 36), ('Question', 300), ('Answer type', 150), ('Required', 120), ('', 48)];

  Widget _table() => LayoutBuilder(builder: (context, b) {
        final min = _cols.fold<double>(0, (a, x) => a + x.$2);
        final extra = (b.maxWidth - min).clamp(0.0, double.infinity);
        final w = [for (final (i, x) in _cols.indexed) x.$2 + (i == 1 ? extra : 0)];
        Widget cell(int i, Widget child) => Container(width: w[i], padding: EdgeInsets.symmetric(horizontal: i == 0 ? 6 : 8), alignment: Alignment.centerLeft, child: child);
        final table = SizedBox(
          width: min + extra,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 34,
              decoration: const BoxDecoration(color: AppColors.tableHeadDt, border: Border.symmetric(horizontal: BorderSide(color: AppColors.line))),
              child: Row(children: [for (final (i, x) in _cols.indexed) cell(i, Text(x.$1.toUpperCase(), style: AppText.s(11.5, W.w7, color: AppColors.muted, ls: .58)))]),
            ),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (a, b2) => setState(() => qs.insert(b2, qs.removeAt(a))),
              children: [
                for (final (i, q) in qs.indexed)
                  Container(
                    key: q.key,
                    color: AppColors.card,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: null,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      cell(0, ReorderableDragStartListener(
                          index: i,
                          child: const MouseRegion(cursor: SystemMouseCursors.grab, child: Padding(padding: EdgeInsets.only(top: 8), child: AppIcon(AppIcons.drag, size: 16, color: AppColors.muted))))),
                      cell(
                        1,
                        Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
                          Row(spacing: 6, children: [
                            _Dot(on: q.change.isNotEmpty),
                            Expanded(child: AppTextField(controller: q.text, placeholder: 'Write the question', height: 34)),
                          ]),
                          if (q.error != null) Text(q.error!, style: AppText.s(12, W.w6, color: AppColors.badText)),
                          if (q.change.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 13), child: Text(q.change, style: AppText.cap)),
                        ]),
                      ),
                      cell(
                        2,
                        AppSelect(
                          _choiceLabels[q.type] ?? cpAnswerTypes.firstWhere((t) => t.$1 == q.type, orElse: () => (q.type, q.type)).$2,
                          entries: [
                            if (_choiceLabels.containsKey(q.type)) MenuEntry(_choiceLabels[q.type]!, selected: true),
                            for (final (v, l) in cpAnswerTypes) MenuEntry(l, selected: q.type == v, onTap: () => setState(() => q.type = v)),
                          ],
                        ),
                      ),
                      cell(
                        3,
                        Padding(
                          padding: const EdgeInsets.only(top: 9),
                          child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
                            AppToggle(value: q.required, onChanged: (v) => setState(() => q.required = v)),
                            Text('Required', style: AppText.s(13, W.w5, color: AppColors.text2)),
                          ]),
                        ),
                      ),
                      cell(4, Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: AppIconButton(AppIcons.trash, tooltip: 'Remove', small: true, ghost: true, onPressed: () => setState(() => qs.removeAt(i))),
                      )),
                    ]),
                  ),
              ],
            ),
          ]),
        );
        if (b.maxWidth >= min) return table;
        return Scrollbar(
          controller: _hScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(controller: _hScroll, scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(bottom: 8), child: table),
        );
      });
}

/// `.cp-chd`: 7px accent dot on a question changed for this client (empty when not).
class _Dot extends StatelessWidget {
  const _Dot({required this.on});
  final bool on;
  @override
  Widget build(BuildContext context) => Container(width: 7, height: 7, decoration: BoxDecoration(color: on ? AppColors.accent : null, shape: BoxShape.circle));
}

/// Same dot for the read-only question list.
Widget cpChangeDot(bool on) => _Dot(on: on);
