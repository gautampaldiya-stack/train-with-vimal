import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../app/shell/page.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import '../../../core/widgets/tooltip.dart';
import '../../trainer/client_profile/cp_content_drawers.dart' show drField;
import '../../trainer/me/me_docs.dart' show DashedBox;
import 'forms_common.dart';

/// Admin → Forms & check-ins → a form (boards `FormBuilder` + `FormBuilderMobile`, D-50).
///
/// Left: Add question (9 answer types; on narrow pages the dashed Add question opens them as a sheet). Middle: the
/// questions, dragged or moved to reorder; a card opens the question editor, ⋯: Edit question, Duplicate, Move
/// up, Move down, Delete question. Right: Form details (name, type, how it is sent) and Answers so far.
/// Every change saves at once. On a published form it is kept as a draft and clients get the old version until
/// Publish; ⋯ Move back to draft starts such a draft by hand.
class FormBuilderScreen extends StatefulWidget {
  const FormBuilderScreen({super.key, required this.id});
  final String id;
  @override
  State<FormBuilderScreen> createState() => _FormBuilderScreenState();
}

class _FormBuilderScreenState extends State<FormBuilderScreen> {
  Map f = {};
  List<FmQ> qs = [];
  bool loading = true, saving = false, _again = false;
  ApiError? error, saveError;
  final name = TextEditingController();
  final _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) _rename();
    });
    load();
  }

  @override
  void dispose() {
    name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final d = await Services.api.get<Map>('forms/${widget.id}/');
      if (!mounted) return;
      setState(() {
        f = d;
        qs = [for (final q in (d['questions'] as List? ?? const [])) FmQ(q as Map)];
        name.text = '${d['name']}';
        error = null;
        loading = false;
      });
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          loading = false;
        });
      }
    }
  }

  bool get _pub => f['status'] == 'published';
  bool get _draft => f['status'] == 'draft' || f['has_draft'] == true;
  List<String> get _autos => [for (final a in (f['sent_by'] as List?) ?? const []) '$a'];
  String get _builtIn => '${f['built_in'] ?? ''}';

  // ─────────────────────────────── Saving

  /// Saves the whole list (one save at a time; a change made meanwhile saves right after).
  Future<void> _save() async {
    if (saving) {
      _again = true;
      return;
    }
    setState(() => saving = true);
    try {
      final r = await Services.api.put<Map>('forms/${widget.id}/questions/', {'questions': [for (final q in qs) q.toJson()]});
      if (!mounted) return;
      final got = (r['questions'] as List?) ?? const [];
      setState(() {
        // new questions get their ids (a draft form); the cards keep their keys
        if (got.length == qs.length && !_again) {
          for (final (i, q) in qs.indexed) {
            q.id = ((got[i] as Map)['id'] as num?)?.toInt();
          }
        }
        f = {...f, 'has_draft': r['has_draft'], 'updated_at': r['updated_at'], 'question_count': r['question_count']};
        saveError = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => saveError = e);
    } finally {
      if (mounted) setState(() => saving = false);
      if (_again) {
        _again = false;
        _save();
      }
    }
  }

  /// Changes the list, saves it, shows the toast.
  void _change(VoidCallback edit, {String? toast, String? sub, VoidCallback? undo}) {
    setState(edit);
    _save();
    if (toast != null) showToast(context, toast, sub: sub, action: undo == null ? null : 'Undo', onAction: undo);
  }

  Future<void> _patch(Map body) async {
    try {
      final r = await Services.api.patch<Map>('forms/${widget.id}/', body);
      if (mounted) setState(() => f = {...f, ...r, 'questions': f['questions'], 'stats': f['stats'], 'built_in': f['built_in'], 'sent_by': f['sent_by']});
    } on ApiError catch (e) {
      if (mounted) {
        showToast(context, 'Could not save', sub: e.fields['name']?.first ?? e.message, kind: ToastKind.err);
        name.text = '${f['name']}';
      }
    }
  }

  void _rename() {
    final n = name.text.trim();
    if (n == '${f['name']}') return;
    if (n.length < 2) {
      name.text = '${f['name']}';
      return showToast(context, 'Enter a form name', kind: ToastKind.err);
    }
    _patch({'name': n});
  }

  // ─────────────────────────────── Page

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return StaffPage(children: [
        _crumb(''),
        const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5))),
      ]);
    }
    if (error != null) {
      final gone = error!.status == 404;
      return StaffPage(children: [
        _crumb(''),
        AppCard(
          child: EmptyState(gone ? 'This form is gone' : 'Could not open this form',
              icon: AppIcons.clipboard,
              sub: gone ? 'It may have been deleted.' : error!.message,
              action: AppButton(gone ? 'Back to forms' : 'Try again', onPressed: gone ? () => context.go('/forms') : load)),
        ),
      ]);
    }
    final phone = context.isPhone;
    return StaffPage(
      onRefresh: load,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 12 : 14, children: [_crumb('${f['name']}'), _head(phone)]),
        if (saveError != null) _saveFailed(),
        LayoutBuilder(builder: (context, c) {
          final three = c.maxWidth >= 1080, two = c.maxWidth >= 760;
          final list = _questions(palette: three);
          final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [_details(), _answers()]);
          if (three) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
              SizedBox(width: 220, child: _palette()),
              Expanded(child: list),
              SizedBox(width: 320, child: side),
            ]);
          }
          if (two) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [Expanded(child: list), SizedBox(width: 300, child: side)]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [list, side]);
        }),
      ],
    );
  }

  Widget _crumb(String cur) => Row(spacing: 6, children: [
        Hover(
          onTap: () => context.go('/forms'),
          builder: (_, h, _) => Text('Forms & check-ins', style: AppText.s(13, W.w5, color: h ? AppColors.text : AppColors.muted)),
        ),
        const AppIcon(AppIcons.chevronRight, size: 13, color: AppColors.chevron),
        Flexible(child: fmCut(cur, AppText.s(13, W.w6))),
      ]);

  Widget _head(bool phone) {
    final w = MediaQuery.sizeOf(context).width;
    final size = phone ? 17.0 : (w * 0.02).clamp(20.0, 28.0);
    final how = _autos.isNotEmpty ? 'Sent by automation' : (_builtIn.isNotEmpty ? 'Sent by the app' : 'Sent by hand');
    final narrow = phone || compactTop(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
          Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${f['name']}', style: AppText.h1.copyWith(fontSize: size)),
            formBadge(f),
          ]),
          CutText('${kindLabel('${f['type']}')} · ${questionsLabel(qs.length)} · $how',
              maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.sub.copyWith(fontSize: phone ? 12 : 13)),
        ]),
      ),
      Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
        Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'More', onPressed: () => _formMenu(b))),
        AppButton('Preview', icon: AppIcons.eye, iconOnly: narrow, tooltip: 'Preview', onPressed: _preview),
        if (_draft && f['status'] != 'archived') AppButton.primary('Publish', icon: AppIcons.send, iconOnly: phone, tooltip: 'Publish', onPressed: _publish),
      ]),
    ]);
  }

  Widget _saveFailed() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: AppColors.badBg, borderRadius: AppRadius.all(8)),
        child: Row(spacing: 8, children: [
          const AppIcon(AppIcons.alert, size: 16, color: AppColors.badText),
          Expanded(child: Text('Your last change was not saved. ${saveError!.message}', style: AppText.s(12.5, W.w6, color: AppColors.badText))),
          AppButton('Try again', size: BtnSize.sm, onPressed: _save),
        ]),
      );

  // ─────────────────────────────── Add question

  /// `.fm-pal`: the 9 answer types; one opens the editor for a new question of that type.
  Widget _palette() => AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 2, children: [
          Padding(padding: const EdgeInsets.fromLTRB(6, 2, 6, 6), child: Text('ADD QUESTION', style: AppText.s(11.5, W.w7, color: AppColors.muted, ls: .6))),
          for (final (k, l) in qTypes)
            Hover(
              onTap: () => _add(k),
              builder: (_, h, _) => Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(color: h ? AppColors.hover : null, borderRadius: AppRadius.all(8)),
                child: Row(spacing: 10, children: [
                  QTypeIcon(k),
                  Expanded(child: fmCut(l, AppText.s(13, W.w6))),
                  Opacity(opacity: h ? 1 : 0, child: const AppIcon(AppIcons.plus, size: 15, color: AppColors.muted)),
                ]),
              ),
            ),
        ]),
      );

  /// The dashed Add question: next to the palette it starts a Short answer; without it, pick the type first.
  Future<void> _addAny({required bool palette}) async {
    if (palette) return _add('short');
    String? type;
    await showActionSheet(context, title: 'Add question', [for (final (k, l) in qTypes) MenuEntry(l, lead: QTypeIcon(k), onTap: () => type = k)]);
    if (type != null && mounted) _add(type!);
  }

  Future<void> _add(String type) async {
    final q = await showQuestionEditor(context, q: FmQ.blank(type), isNew: true);
    if (q == null || !mounted) return;
    _change(() => qs.add(q), toast: 'Question added', sub: 'Placed at the end of the form');
  }

  // ─────────────────────────────── Questions

  Widget _questions({required bool palette}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (qs.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: AppCard(child: EmptyState('No questions yet', icon: AppIcons.clipboard, sub: 'Pick an answer type to write the first question.')),
          ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: qs.length,
          proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
          onReorderItem: (a, b) => _change(() => qs.insert(b, qs.removeAt(a))),
          itemBuilder: (_, i) => Padding(key: qs[i].key, padding: const EdgeInsets.only(bottom: 10), child: _card(i)),
        ),
        _addButton(palette),
      ]);

  /// `.mb-addm`: dashed full-width button.
  Widget _addButton(bool palette) => Builder(
        builder: (b) => Hover(
          onTap: () => _addAny(palette: palette),
          builder: (_, h, _) => CustomPaint(
            painter: DashedBox(color: h ? AppColors.accent : AppColors.line2, radius: AppRadius.card),
            child: Container(
              height: 46,
              decoration: BoxDecoration(color: h ? AppColors.hover : null, borderRadius: AppRadius.all(AppRadius.card)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
                AppIcon(AppIcons.plus, size: 16, color: h ? AppColors.accentText : AppColors.text2),
                Text('Add question', style: AppText.s(13.5, W.w7, color: h ? AppColors.accentText : AppColors.text2)),
              ]),
            ),
          ),
        ),
      );

  /// `.fm-q`: drag handle, number, question, type · options · help, Required / Optional, ⋯.
  Widget _card(int i) {
    final q = qs[i];
    final phone = context.isPhone;
    final meta = [qTypeLabel(q.type), if (q.optionsLine.isNotEmpty) q.optionsLine, if (q.help.isNotEmpty) q.help].join(' · ');
    return Hover(
      onTap: () => _edit(i),
      builder: (_, h, _) => Container(
        padding: phone ? const EdgeInsets.fromLTRB(4, 10, 6, 10) : const EdgeInsets.fromLTRB(6, 9, 8, 9),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppRadius.all(AppRadius.card),
          border: Border.all(color: h ? AppColors.line2 : AppColors.line),
        ),
        child: Row(spacing: phone ? 8 : 10, children: [
          ReorderableDragStartListener(
            index: i,
            child: const AppTooltip(
              message: 'Drag to reorder',
              child: MouseRegion(cursor: SystemMouseCursors.grab, child: Padding(padding: EdgeInsets.all(2), child: AppIcon(AppIcons.dragDots, size: 16, color: AppColors.fmDrag))),
            ),
          ),
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: AppRadius.all(6)),
            child: Text('${i + 1}', style: AppText.s(11.5, W.w8, color: AppColors.infoText)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              fmCut(q.text, AppText.s(13.5, W.w7, h: 1.35)),
              Row(spacing: 4, children: [
                QTypeIcon(q.type, small: true),
                Expanded(child: fmCut(meta, AppText.s(12, W.w6, color: AppColors.muted))),
              ]),
            ]),
          ),
          Text(q.required ? 'Required' : 'Optional', style: AppText.s(11.5, W.w7, color: q.required ? AppColors.badText : AppColors.muted)),
          Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'Question options', small: true, ghost: true, onPressed: () => _qMenu(b, i))),
        ]),
      ),
    );
  }

  void _qMenu(BuildContext anchor, int i) => showAppMenu(anchor, width: 220, [
        MenuEntry.header('Question ${i + 1}'),
        MenuEntry('Edit question', icon: AppIcons.edit, onTap: () => _edit(i)),
        MenuEntry('Duplicate', icon: AppIcons.copy, onTap: () => _change(() => qs.insert(i + 1, qs[i].copy(asNew: true)), toast: 'Question duplicated')),
        if (i > 0) MenuEntry('Move up', icon: AppIcons.chevronUpAlt, onTap: () => _change(() => qs.insert(i - 1, qs.removeAt(i)))),
        if (i < qs.length - 1) MenuEntry('Move down', icon: AppIcons.chevronDown, onTap: () => _change(() => qs.insert(i + 1, qs.removeAt(i)))),
        const MenuEntry.separator(),
        MenuEntry('Delete question', icon: AppIcons.trash, danger: true, onTap: () => _remove(i)),
      ]);

  Future<void> _edit(int i) async {
    final q = await showQuestionEditor(context, q: qs[i], isNew: false, index: i, total: qs.length);
    if (q == null || !mounted) return;
    _change(() => qs[i] = q, toast: 'Question saved');
  }

  void _remove(int i) {
    final before = [...qs];
    final q = qs[i];
    _change(() => qs.removeAt(i), toast: 'Question deleted', sub: q.text, undo: () => _change(() => qs = before));
  }

  // ─────────────────────────────── Form details

  Widget _side(String title, {Widget? end, required List<Widget> children}) => AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          Row(spacing: 8, children: [Expanded(child: Text(title, style: AppText.s(14.5, W.w8))), ?end]),
          ...children,
        ]),
      );

  Widget _hint(String s) => Text(s, style: AppText.s(12, W.w5, color: AppColors.muted, h: 1.5));

  Widget _details() {
    final last = fmWhen(f['updated_at']);
    final drafted = _pub && f['has_draft'] == true;
    return _side('Form details', end: formBadge(f), children: [
      drField('Name', AppTextField(controller: name, focusNode: _nameFocus, onSubmitted: (_) => _rename())),
      drField(
        'Type',
        AppSelect(kindLabel('${f['type']}'), entries: [
          for (final k in formKinds)
            MenuEntry(k.$2, lead: AppIcon(kindIcon(k.$1), size: 15, color: kindTone(k.$1).$2), selected: f['type'] == k.$1, onTap: () {
              if (f['type'] != k.$1) _patch({'type': k.$1});
            }),
        ]),
      ),
      drField(
        'How it is sent',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          for (final a in _autos) _auto(a, onTap: () => context.go('/automations')),
          if (_autos.isEmpty && _builtIn.isNotEmpty) _auto(_builtIn),
          if (_autos.isEmpty && _builtIn.isEmpty) _hint('No automation sends this form yet.'),
          _hint('Schedule and reminders are set in the automation.'),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton('Open automations', icon: AppIcons.bolt, size: BtnSize.sm, onPressed: () => context.go('/automations')),
          ),
        ]),
      ),
      FmNote(
        AppIcons.checkCircle,
        saving
            ? 'Saving…'
            : drafted
                ? 'Changes are saved as a draft. Clients get the published version until you publish. Last change: $last'
                : 'Changes are saved automatically. Last change: $last',
      ),
    ]);
  }

  /// `.fm-au`: bolt, how it is sent, › (opens Automations).
  Widget _auto(String line, {VoidCallback? onTap}) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(borderRadius: AppRadius.all(8), border: Border.all(color: h && onTap != null ? AppColors.line2 : AppColors.line)),
          child: Row(spacing: 8, children: [
            const AppIcon(AppIcons.bolt, size: 15, color: AppColors.fmBolt),
            Expanded(child: Text(line, style: AppText.s(13, W.w6, color: h && onTap != null ? AppColors.accentText : AppColors.text))),
            if (onTap != null) const AppIcon(AppIcons.chevronRight, size: 15, color: AppColors.muted),
          ]),
        ),
      );

  // ─────────────────────────────── Answers so far

  Widget _answers() {
    final s = (f['stats'] as Map?) ?? const {};
    final latest = s['latest'] as Map?;
    final rate = s['rate'] as num?;
    final cells = [('${s['sent'] ?? 0}', 'sent this month'), ('${s['answered'] ?? 0}', 'answered'), (rate == null ? '—' : '$rate%', 'answer rate')];
    return _side('Answers so far', children: [
      Container(
        decoration: BoxDecoration(borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.line)),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, c) in cells.indexed)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(border: i == 0 ? null : const Border(left: BorderSide(color: AppColors.line))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                    fmCut(c.$1, AppText.s(18, W.w8, tabular: true)),
                    Text(c.$2, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
                  ]),
                ),
              ),
          ]),
        ),
      ),
      _hint('Each answer shows in the client profile under Forms.'),
      if (latest != null)
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton("See ${latest['first_name']}'s answers",
              icon: AppIcons.usersAlt, kind: BtnKind.text, onPressed: () => context.go('/clients/${latest['id']}?tab=forms')),
        ),
    ]);
  }

  // ─────────────────────────────── Form actions

  Future<void> _preview() => showFormPreview(context, name: '${f['name']}', questions: qs);

  void _formMenu(BuildContext anchor) => showAppMenu(anchor, width: 240, [
        MenuEntry.header('${f['name']}'),
        MenuEntry('Duplicate form', icon: AppIcons.copy, onTap: _duplicate),
        if (_pub && f['has_draft'] != true) MenuEntry('Move back to draft', icon: AppIcons.restart, onTap: _toDraft),
        if (f['status'] != 'archived') MenuEntry('Archive form', icon: AppIcons.formArchive, onTap: _archive),
      ]);

  Future<Map?> _post(String path, String failed, [Object? body]) async {
    try {
      return await Services.api.post<Map>('forms/${widget.id}/$path', body);
    } on ApiError catch (e) {
      if (mounted) showToast(context, failed, sub: e.message, kind: ToastKind.err);
      return null;
    }
  }

  Future<void> _duplicate() async {
    final r = await _post('duplicate/', 'Could not duplicate the form');
    if (r == null || !mounted) return;
    context.go('/forms/${r['id']}');
    showToast(context, 'Form duplicated', sub: 'You are editing the copy now');
  }

  Future<void> _toDraft() async {
    final r = await _post('draft/', 'Could not move it back to draft');
    if (r == null || !mounted) return;
    setState(() => f = {...f, 'has_draft': r['has_draft']});
    showToast(context, 'Moved back to draft', sub: 'Clients get the old version until you publish', action: 'Undo', onAction: _discard);
  }

  Future<void> _discard() async {
    final r = await _post('discard/', 'Could not undo');
    if (r != null && mounted) load();
  }

  Future<void> _archive() async {
    final r = await _post('archive/', 'Could not archive the form');
    if (r == null || !mounted) return;
    setState(() => f = {...f, 'status': 'archived'});
    showToast(context, 'Form archived', sub: 'It is no longer sent to clients', action: 'Undo', onAction: () async {
      if (await _post('unarchive/', 'Could not undo', {'status': r['previous_status']}) != null && mounted) load();
    });
  }

  Future<void> _publish() async {
    if (qs.isEmpty) return showToast(context, 'Add a question first', sub: 'An empty form cannot be published', kind: ToastKind.err);
    final ok = await confirmAction(context,
        title: 'Publish this form?',
        body: 'The next check-in goes out with ${questionsLabel(qs.length)}. Answers already sent stay as they are.',
        confirm: 'Publish',
        icon: AppIcons.send);
    if (!ok || !mounted) return;
    if (saving) await Future.doWhile(() => Future.delayed(const Duration(milliseconds: 80), () => saving));
    final r = await _post('publish/', 'Could not publish the form');
    if (r == null || !mounted) return;
    await load();
    if (mounted) showToast(context, 'Form published', sub: 'Clients get it on the next send', kind: ToastKind.ok);
  }
}
