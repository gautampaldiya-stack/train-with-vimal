import 'package:flutter/material.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import 'cp_common.dart';
import 'cp_model.dart';

/// Client profile → Notes tab (`clients/<id>/notes/`): composer "Write a note about Riya…" with "Mark as a flag
/// (shows in Needs attention)" and Save note; flagged notes on top in the amber box, then the rest, newest first.
/// Each note the trainer wrote (Vimal: every note) has ⋯ → Edit / Delete; Delete has Undo (`restore/`).
/// Staff only: the client never sees these.
class CpNotesTab extends StatefulWidget {
  const CpNotesTab(this.c, {super.key});
  final CpController c;
  @override
  State<CpNotesTab> createState() => _CpNotesTabState();
}

class _CpNotesTabState extends State<CpNotesTab> {
  static const _size = 20;
  CpController get c => widget.c;
  final _body = TextEditingController();
  List<Map> notes = [];
  int count = 0, page = 1;
  bool loading = true, more = false, flag = false, saving = false, loadingMore = false;
  ApiError? error;
  String? editing; // note id being edited in place
  int _seen = -1;

  @override
  void initState() {
    super.initState();
    _body.addListener(() => setState(() {}));
    _load();
  }

  @override
  void didUpdateWidget(CpNotesTab old) {
    super.didUpdateWidget(old);
    if (_seen != c.version) _load();
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _load({bool next = false}) async {
    _seen = c.version;
    final p = next ? page + 1 : 1;
    if (next) setState(() => loadingMore = true);
    try {
      final r = await Services.api.get<Map>('clients/${c.id}/notes/', query: {'page': p, 'page_size': _size});
      if (!mounted) return;
      final rows = [for (final x in (r['results'] as List? ?? const [])) x as Map];
      setState(() {
        notes = next ? [...notes, ...rows] : rows;
        count = (r['count'] as num?)?.toInt() ?? notes.length;
        page = p;
        more = r['next'] != null;
        error = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e);
    }
    if (mounted) setState(() => loading = loadingMore = false);
  }

  bool _canChange(Map n) {
    final me = Services.session.me;
    return me != null && (me.role == Role.admin || '${(n['author'] as Map?)?['id']}' == me.id);
  }

  Future<void> _save() async {
    final text = _body.text.trim();
    if (text.isEmpty || saving) return;
    setState(() => saving = true);
    try {
      await Services.api.post('clients/${c.id}/notes/', {'body': text, 'is_flag': flag});
      final wasFlag = flag;
      _body.clear();
      flag = false;
      if (mounted) showToast(context, 'Note saved', sub: wasFlag ? 'It shows in Needs attention' : null);
      await c.refresh(); // Overview's Latest note / Needs attention, the tab count, and this list
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not save the note', sub: e.message);
    }
    if (mounted) setState(() => saving = false);
  }

  Future<void> _delete(Map n) async {
    try {
      await Services.api.delete('clients/${c.id}/notes/${n['id']}/');
      if (!mounted) return;
      showToast(context, 'Note deleted', action: 'Undo', onAction: () async {
        try {
          await Services.api.post('clients/${c.id}/notes/${n['id']}/restore/');
          await c.refresh(); // reloads this tab through [CpController.version]
        } on ApiError catch (e) {
          if (mounted) showToast(context, 'Could not bring it back', sub: e.message);
        }
      });
      await c.refresh();
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not delete the note', sub: e.message);
    }
  }

  Future<void> _update(Map n, String body, bool isFlag) async {
    try {
      await Services.api.patch('clients/${c.id}/notes/${n['id']}/', {'body': body, 'is_flag': isFlag});
      setState(() => editing = null);
      if (mounted) showToast(context, 'Note saved');
      await c.refresh();
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not save the note', sub: e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const AppCard(child: CpLoading());
    if (error != null && notes.isEmpty) return CpError(error!.message, onRetry: _load);
    final flagged = [for (final n in notes) if (n['is_flag'] == true) n];
    final rest = [for (final n in notes) if (n['is_flag'] != true) n];
    return CpCard(
      title: 'Notes',
      sub: 'Staff only. ${c.first} never sees these.',
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _composer(context),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (notes.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Text('No notes yet. Write what the team should know about ${c.first}: injuries, likes, what you agreed.',
                    style: AppText.sub),
              ),
            for (final n in flagged) Padding(padding: const EdgeInsets.only(bottom: 6), child: _flag(n)),
            for (final (i, n) in rest.indexed) _note(n, first: i == 0),
            if (more)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Center(child: AppButton('Show more', size: BtnSize.sm, loading: loadingMore, onPressed: () => _load(next: true))),
              ),
          ]),
        ),
      ]),
    );
  }

  // `.cp-compose`: textarea, then the flag box and Save note (phone: the button under the box).
  Widget _composer(BuildContext context) {
    final phone = context.isPhone;
    final box = _Tap(
      onTap: () => setState(() => flag = !flag),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
        AppCheckbox(value: flag, onChanged: (v) => setState(() => flag = v)),
        Flexible(child: Text('Mark as a flag (shows in Needs attention)', style: AppText.cap)),
      ]),
    );
    final btn = AppButton.primary('Save note', loading: saving, onPressed: _body.text.trim().isEmpty ? null : _save);
    return Padding(
      padding: EdgeInsets.fromLTRB(phone ? 16 : 20, 0, phone ? 16 : 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        AppTextField(controller: _body, placeholder: 'Write a note about ${c.first}…', maxLines: 5, minLines: 3),
        if (phone)
          Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [box, btn])
        else
          Row(children: [Expanded(child: Align(alignment: Alignment.centerLeft, child: box)), btn]),
      ]),
    );
  }

  String _author(Map n) => '${(n['author'] as Map?)?['full_name'] ?? 'Staff'}';

  Widget _menu(Map n, {Color color = AppColors.muted}) => !_canChange(n)
      ? const SizedBox.shrink()
      : Builder(
          builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'More actions', small: true, ghost: true, fill: true, color: color, onPressed: () => showAppMenu(b, [
                MenuEntry('Edit', icon: AppIcons.edit, onTap: () => setState(() => editing = '${n['id']}')),
                MenuEntry('Delete', icon: AppIcons.trash, danger: true, onTap: () => _delete(n)),
              ])),
        );

  // `.cp-flag`: amber box, flag icon, the note and "Flag · Vimal · 12 Sep".
  Widget _flag(Map n) {
    if (editing == '${n['id']}') return _NoteEditor(n, onCancel: () => setState(() => editing = null), onSave: (b, f) => _update(n, b, f));
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(color: AppColors.warnBg, borderRadius: AppRadius.all(AppRadius.item)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
        const Padding(padding: EdgeInsets.only(top: 1), child: AppIcon(AppIcons.flag, size: 16, color: AppColors.warnText)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text('${n['body']}', style: AppText.s(13, W.w6, color: AppColors.warnText, h: 1.4)),
            Text('Flag · ${_author(n)} · ${cpDm(n['created_at'])}', style: AppText.s(12, W.w5, color: AppColors.warnText)),
          ]),
        ),
        _menu(n, color: AppColors.warnText),
      ]),
    );
  }

  // `.cp-note`: the note, "Aman Verma · 2 days ago", a line between notes.
  Widget _note(Map n, {required bool first}) {
    if (editing == '${n['id']}') return _NoteEditor(n, onCancel: () => setState(() => editing = null), onSave: (b, f) => _update(n, b, f));
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: AppColors.line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
            Text('${n['body']}', style: AppText.s(13.5, W.w5, h: 1.5)),
            Text('${_author(n)} · ${cpAgo(n['created_at'])}', style: AppText.s(12, W.w6, color: AppColors.muted)),
          ]),
        ),
        _menu(n),
      ]),
    );
  }
}

/// Edit in place: the text, the flag box, Cancel and Save.
class _NoteEditor extends StatefulWidget {
  const _NoteEditor(this.n, {required this.onCancel, required this.onSave});
  final Map n;
  final VoidCallback onCancel;
  final Future<void> Function(String body, bool flag) onSave;
  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final _t = TextEditingController(text: '${widget.n['body']}');
  late bool flag = widget.n['is_flag'] == true;
  bool busy = false;

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
          AppTextField(controller: _t, maxLines: 5, minLines: 2, autofocus: true),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _Tap(
              onTap: () => setState(() => flag = !flag),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
                AppCheckbox(value: flag, onChanged: (v) => setState(() => flag = v)),
                Text('Mark as a flag (shows in Needs attention)', style: AppText.cap),
              ]),
            ),
            const SizedBox(width: 8),
            AppButton('Cancel', size: BtnSize.sm, onPressed: widget.onCancel),
            AppButton.primary('Save', size: BtnSize.sm, loading: busy, onPressed: () async {
              if (_t.text.trim().isEmpty) return;
              setState(() => busy = true);
              await widget.onSave(_t.text.trim(), flag);
              if (mounted) setState(() => busy = false);
            }),
          ]),
        ]),
      );
}

/// A tappable label row with a click cursor.
class _Tap extends StatelessWidget {
  const _Tap({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: child));
}
