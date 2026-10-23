import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../app/shell/page.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import '../../../core/widgets/tabs.dart';
import '../../../core/widgets/tooltip.dart';
import '../../trainer/client_profile/cp_content_drawers.dart' show DrSwitch;
import '../forms/forms_common.dart' show FmCheck, FmNote;
import 'emails_common.dart';

/// Admin → Emails & alerts (boards `Emails` + `EmailsMobile`, D-52). Three tabs:
/// - Client messages: the list of messages by group with a dot per channel; the editor (one tab per channel, Send by
///   switch, subject / title, message, variables, Reset to default or Delete template, Save); the preview for a sample
///   client and where the message is used. On a narrow screen the list opens the editor as its own view.
/// - Team alerts: which channels each team alert goes out on, quiet hours and the daily digest.
/// - Sender: the name, reply-to email and WhatsApp number clients see.
class EmailsScreen extends StatefulWidget {
  const EmailsScreen({super.key, this.tab});
  final String? tab;
  @override
  State<EmailsScreen> createState() => _EmailsScreenState();
}

class _EmailsScreenState extends State<EmailsScreen> {
  late String tab = switch (widget.tab) { 'alerts' => 'a', 'sender' => 's', _ => 't' };
  List<Map> tpls = [];
  List<Map> alerts = [];
  Map settings = {};
  bool loading = true;
  ApiError? error;

  // Client messages: the picked message and channel, unsaved text per message, field errors.
  String? sel;
  String ch = 'push';
  bool det = false;
  final drafts = <String, Map<String, Map<String, dynamic>>>{};
  final dirty = <String>{};
  String? headErr, bodyErr;
  bool saving = false;
  final headC = TextEditingController(), bodyC = TextEditingController();
  final headF = FocusNode(), bodyF = FocusNode();
  bool lastHead = false;

  // Sender
  final nameC = TextEditingController(), replyC = TextEditingController(), waC = TextEditingController();
  Map<String, String?> sErr = {};
  bool sSaving = false;

  @override
  void initState() {
    super.initState();
    headF.addListener(() => headF.hasFocus ? lastHead = true : null);
    bodyF.addListener(() => bodyF.hasFocus ? lastHead = false : null);
    load();
  }

  @override
  void dispose() {
    for (final c in [headC, bodyC, nameC, replyC, waC]) {
      c.dispose();
    }
    headF.dispose();
    bodyF.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await Future.wait([
        Services.api.get<List>('message-templates/'),
        Services.api.get<List>('team-alerts/'),
        Services.api.get<Map>('settings/notifications/'),
      ]);
      if (!mounted) return;
      setState(() {
        tpls = [for (final x in r[0] as List) x as Map];
        alerts = [for (final x in r[1] as List) x as Map];
        settings = r[2] as Map;
        for (final t in tpls) {
          if (!dirty.contains(t['key'])) drafts.remove(t['key']);
        }
        error = null;
        loading = false;
        if (sel == null || _tpl(sel!) == null) _pick(_defaultKey(), open: false);
        nameC.text = '${settings['sender_name'] ?? ''}';
        replyC.text = '${settings['reply_to_email'] ?? ''}';
        waC.text = '${settings['whatsapp_number'] ?? ''}';
      });
      _fill();
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          loading = false;
        });
      }
    }
  }

  // ─────────────────────────────── Client messages: state

  Map? _tpl(String key) => tpls.where((t) => t['key'] == key).firstOrNull;
  String? _defaultKey() => _tpl('checkin-reminder') != null ? 'checkin-reminder' : (tpls.isEmpty ? null : tpls.first['key'] as String);

  /// The text being edited for a message: its unsaved draft, else what is saved.
  Map<String, Map<String, dynamic>> _chans(String key) => drafts[key] ??= _copy((_tpl(key)?['channels'] as Map?) ?? const {});

  Map<String, Map<String, dynamic>> _copy(Map m) => {
        for (final c in emChannels) c: {'on': false, 'subject': '', 'title': '', 'body': '', ...Map<String, dynamic>.from((jsonDecode(jsonEncode(m[c] ?? {})) as Map))},
      };

  bool _on(String key, String c) => _chans(key)[c]?['on'] == true;

  void _pick(String? key, {bool open = true}) {
    sel = key;
    headErr = bodyErr = null;
    if (key == null) return;
    final chs = _chans(key);
    ch = chs['push']?['on'] == true ? 'push' : emChannels.firstWhere((c) => chs[c]?['on'] == true, orElse: () => 'email');
    if (open) det = true;
  }

  /// Puts the picked channel's words into the two fields.
  void _fill() {
    if (sel == null) return;
    final c = _chans(sel!)[ch]!;
    headC.text = '${c[emHeadKey(ch)] ?? ''}';
    bodyC.text = '${c['body'] ?? ''}';
  }

  void _select(String key) {
    setState(() => _pick(key));
    _fill();
  }

  void _channel(String c) {
    setState(() {
      ch = c;
      headErr = bodyErr = null;
    });
    _fill();
  }

  void _edit(String field, String v) {
    setState(() {
      _chans(sel!)[ch]![field] = v;
      dirty.add(sel!);
      if (field == 'body') bodyErr = null;
      if (field != 'body') headErr = null;
    });
  }

  void _toggleChannel(bool v) {
    final c = _chans(sel!)[ch]!;
    setState(() {
      c['on'] = v;
      dirty.add(sel!);
      headErr = bodyErr = null;
    });
    if (v && '${c['body']}'.trim().isEmpty) showToast(context, '${emChannelLabel[ch]} turned on', sub: 'Write the text and save');
  }

  void _insertVar(String v) {
    final head = lastHead && ch != 'whatsapp';
    final ctl = head ? headC : bodyC;
    final limit = head ? emSubjectLimit : emBodyLimit[ch]!;
    final add = '{{$v}}';
    final t = ctl.text, s = ctl.selection;
    final at = s.isValid ? s.start : t.length, end = s.isValid ? s.end : t.length;
    final pre = at > 0 && t[at - 1] != ' ' && t[at - 1] != '\n' ? ' ' : '';
    final next = t.replaceRange(at, end, '$pre$add');
    if (next.length > limit) {
      showToast(context, 'No room for $add', sub: '${head ? (ch == 'email' ? 'Subject' : 'Title') : 'Message'} can be $limit characters', kind: ToastKind.err);
      return;
    }
    ctl.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: at + pre.length + add.length));
    _edit(head ? emHeadKey(ch) : 'body', next);
    (head ? headF : bodyF).requestFocus();
  }

  Future<void> _save() async {
    final key = sel!, t = _tpl(key)!, chans = _chans(key);
    if (!emChannels.any((c) => chans[c]!['on'] == true)) {
      showToast(context, 'Keep one channel on', sub: 'A template needs at least one', kind: ToastKind.err);
      return;
    }
    // the first channel that is on but not written yet: open it and say what is missing
    for (final c in emChannels) {
      final x = chans[c]!;
      if (x['on'] != true) continue;
      final noHead = c == 'email' && '${x['subject']}'.trim().isEmpty;
      final noBody = '${x['body']}'.trim().isEmpty;
      if (noHead || noBody) {
        if (c != ch) _channel(c);
        setState(() {
          headErr = noHead ? 'Add a subject.' : null;
          bodyErr = noBody ? 'Write the text, or turn this channel off.' : null;
        });
        return;
      }
    }
    setState(() => saving = true);
    try {
      final r = await Services.api.patch<Map>('message-templates/${t['id']}/', {'channels': chans});
      if (!mounted) return;
      setState(() {
        tpls = [for (final x in tpls) x['key'] == key ? r : x];
        dirty.remove(key);
        drafts.remove(key);
        saving = false;
      });
      showToast(context, 'Template saved', sub: '${t['name']} · ${emChannelLabel[ch]}');
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      showToast(context, 'Could not save', sub: e.fields.values.firstOrNull?.first ?? e.message, kind: ToastKind.err);
    }
  }

  Future<void> _reset() async {
    final t = _tpl(sel!)!;
    try {
      final r = await Services.api.post<Map>('message-templates/${t['id']}/reset/');
      if (!mounted) return;
      setState(() {
        tpls = [for (final x in tpls) x['key'] == t['key'] ? r : x];
        dirty.remove(t['key']);
        drafts.remove(t['key']);
        headErr = bodyErr = null;
      });
      _fill();
      showToast(context, 'Default text restored', sub: '${t['name']}');
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not restore it', sub: e.message, kind: ToastKind.err);
    }
  }

  Future<void> _delete() async {
    final t = _tpl(sel!)!;
    final ok = await confirmAction(context,
        title: 'Delete this template?', body: '${t['name']} is removed for good. Automations cannot use it any more.', confirm: 'Delete', danger: true, icon: AppIcons.trash);
    if (!ok || !mounted) return;
    try {
      await Services.api.delete('message-templates/${t['id']}/');
      if (!mounted) return;
      setState(() {
        tpls = [for (final x in tpls) if (x['key'] != t['key']) x];
        dirty.remove(t['key']);
        drafts.remove(t['key']);
        det = false;
        _pick(_defaultKey(), open: false);
      });
      _fill();
      showToast(context, 'Template deleted', sub: '${t['name']}', action: 'Undo', onAction: () => _undoDelete(t));
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not delete it', sub: e.message, kind: ToastKind.err);
    }
  }

  Future<void> _undoDelete(Map t) async {
    final chans = t['channels'] as Map;
    try {
      final r = await Services.api.post<Map>('message-templates/', {
        'key': t['key'],
        'name': t['name'],
        'group': t['group'],
        'channels': [for (final c in emChannels) if ((chans[c] as Map?)?['on'] == true) c],
        'texts': chans,
      });
      await load();
      if (mounted) _select('${r['key']}');
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not bring it back', sub: e.message, kind: ToastKind.err);
    }
  }

  Future<void> _new() async {
    final r = await showNewTemplate(context);
    if (r == null || !mounted) return;
    setState(() => tpls = [...tpls, r]);
    _select('${r['key']}');
    showToast(context, 'Template created', sub: 'Edit the text, then add it to an automation', action: 'Undo', onAction: () async {
      try {
        await Services.api.delete('message-templates/${r['id']}/');
        if (!mounted) return;
        setState(() {
          tpls = [for (final x in tpls) if (x['key'] != r['key']) x];
          drafts.remove(r['key']);
          dirty.remove(r['key']);
          det = false;
          if (sel == r['key']) _pick(_defaultKey(), open: false);
        });
        _fill();
      } on ApiError catch (e) {
        if (mounted) showToast(context, 'Could not undo', sub: e.message, kind: ToastKind.err);
      }
    });
  }

  // ─────────────────────────────── Page

  @override
  Widget build(BuildContext context) {
    final compact = compactTop(context);
    final phoneDetail = context.isPhone && tab == 't' && det && sel != null;
    return StaffPage(
      onRefresh: load,
      header: phoneDetail
          ? null
          : PageTop(
              title: 'Emails & alerts',
              subWrap: true,
              sub: switch (tab) {
                'a' => 'Alerts for you and your trainers when something happens.',
                's' => 'Who clients see as the sender of emails and WhatsApp messages.',
                _ => 'The messages clients and trainers get, per channel. Change the words once and every send uses them.',
              },
              actions: [
                AppButton('Automations', icon: AppIcons.bolt, iconOnly: compact, tooltip: 'Automations', onPressed: () => context.go('/automations')),
                if (tab == 't') AppButton.primary('New template', icon: AppIcons.plus, iconOnly: compact, tooltip: 'New template', onPressed: _new),
              ],
            ),
      children: [
        if (!phoneDetail)
          Transform.translate(
            offset: const Offset(0, -6),
            child: UnderlineTabs<String>(
              pillCounts: true,
              gap: context.isPhone ? 20 : 24,
              items: [
                TabItem('t', 'Client messages', count: tpls.length),
                TabItem('a', 'Team alerts', count: alerts.length),
                const TabItem('s', 'Sender'),
              ],
              value: tab,
              onChanged: (v) => setState(() {
                tab = v;
                det = false;
              }),
            ),
          ),
        if (error != null && tpls.isEmpty)
          AppCard(child: EmptyState('Could not load Emails & alerts', sub: error!.message, action: AppButton('Try again', onPressed: load)))
        else if (loading && tpls.isEmpty)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)))
        else
          LayoutBuilder(
            builder: (context, box) => switch (tab) {
              'a' => _alertsTab(box.maxWidth),
              's' => _senderTab(box.maxWidth),
              _ => _messagesTab(box.maxWidth),
            },
          ),
      ],
    );
  }

  // ─────────────────────────────── Client messages

  Widget _messagesTab(double cw) {
    if (sel == null) {
      return AppCard(
        child: EmptyState('No messages yet', icon: AppIcons.mail, sub: 'Write a message once, then use it in any automation.', action: AppButton.primary('New template', icon: AppIcons.plus, onPressed: _new)),
      );
    }
    // Narrow: the list, or one message on its own with a back bar (`.em-det`).
    if (cw < 680) {
      if (!det) return _list(phone: true);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        _backBar(),
        _editor(narrow: true),
        _previewCard(),
        _usedCard(),
      ]);
    }
    if (cw >= 1040) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
        SizedBox(width: 280, child: _list()),
        Expanded(child: _editor()),
        SizedBox(width: 320, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [_previewCard(), _usedCard()])),
      ]);
    }
    // Tablet and small laptop: list beside the editor; preview and Where it is used under the editor.
    return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
      SizedBox(width: 260, child: _list()),
      Expanded(
        child: LayoutBuilder(
          builder: (context, b) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
            _editor(),
            if (b.maxWidth >= 600)
              Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 14, children: [Expanded(child: _previewCard()), Expanded(child: _usedCard())])
            else ...[
              _previewCard(),
              _usedCard(),
            ],
          ]),
        ),
      ),
    ]);
  }

  /// `.em-list`: messages by group; a green dot for each channel that is on.
  Widget _list({bool phone = false}) {
    final groups = [
      for (final g in emGroups) (g.$2, [for (final t in tpls) if (t['group'] == g.$1) t]),
    ].where((g) => g.$2.isNotEmpty).toList();
    return AppCard(
      padding: EdgeInsets.all(phone ? 4 : 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
        for (final (gi, g) in groups.indexed)
          Container(
            padding: EdgeInsets.only(top: phone && gi > 0 ? 4 : 0),
            decoration: BoxDecoration(border: phone && gi > 0 ? const Border(top: BorderSide(color: AppColors.line)) : null),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 2, children: [
              Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 4), child: Text(g.$1.toUpperCase(), style: AppText.over)),
              for (final t in g.$2) _listRow(t, phone),
            ]),
          ),
      ]),
    );
  }

  Widget _listRow(Map t, bool phone) {
    final key = '${t['key']}';
    final on = !phone && key == sel;
    return Hover(
      onTap: () => _select(key),
      builder: (_, h, _) => Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: phone ? 11 : 8),
        decoration: BoxDecoration(
          color: on ? AppColors.accentSoft : (h ? AppColors.hover : null),
          borderRadius: AppRadius.all(10),
          border: Border.all(color: on ? AppColors.hbOnLine : Colors.transparent),
        ),
        child: Row(spacing: 8, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 1, children: [
              Row(spacing: 6, children: [
                Flexible(child: CutText('${t['name']}', maxLines: 1, style: AppText.s(13, W.w7))),
                if (t['is_custom'] == true) const AppBadge('Custom', tone: Tone.info, plain: true),
              ]),
              CutText('${t['when'] ?? ''}', maxLines: 1, style: AppText.s(11.5, W.w5, color: AppColors.muted)),
            ]),
          ),
          Row(mainAxisSize: MainAxisSize.min, spacing: 3, children: [
            for (final c in emChannels)
              AppTooltip(message: '${emChannelLabel[c]} · ${_on(key, c) ? 'on' : 'off'}', child: EmDot(_on(key, c))),
          ]),
          if (phone) const Padding(padding: EdgeInsets.only(left: 4), child: AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.muted)),
        ]),
      ),
    );
  }

  /// `.em-mbar`: ‹ Messages and the message's name.
  Widget _backBar() => Row(children: [
        AppButton('Messages', icon: AppIcons.chevronLeft, kind: BtnKind.text, onPressed: () => setState(() => det = false)),
        Expanded(child: CutText('${_tpl(sel!)?['name']}', maxLines: 1, textAlign: TextAlign.center, style: AppText.s(14, W.w7))),
        const SizedBox(width: 92),
      ]);

  Widget _editor({bool narrow = false}) {
    final t = _tpl(sel!)!;
    final custom = t['is_custom'] == true;
    final c = _chans(sel!)[ch]!;
    final on = c['on'] == true;
    final label = emChannelLabel[ch]!;
    final pad = narrow ? 14.0 : 18.0;
    final headLabel = ch == 'email' ? 'Subject' : 'Title';
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // `.hb-eh`
        Container(
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: narrow ? 14 : 16),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
          child: Row(spacing: 12, children: [
            IconTile(AppIcons.mail, size: 44, radius: 11, iconSize: 22, bg: AppColors.hbTones[0].$1, fg: AppColors.hbTones[0].$2),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text('${t['name']}', style: AppText.s(16, W.w7)),
                Text('Sent: ${t['when'] ?? ''}', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
              ]),
            ),
          ]),
        ),
        // `.em-chtabs`: one tab a channel, sideways scroll when they do not fit
        Container(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(narrow ? 12 : 18, narrow ? 6 : 10, narrow ? 12 : 18, 0),
            child: Row(spacing: 4, children: [for (final x in emChannels) _chTab(x)]),
          ),
        ),
        // `.hb-eb`
        Padding(
          padding: EdgeInsets.all(pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
            DrSwitch(
              title: 'Send by $label',
              sub: on ? 'This message goes out on this channel.' : 'Off: this message is not sent on this channel.',
              value: on,
              onChanged: _toggleChannel,
            ),
            if (on) ...[
              if (ch != 'whatsapp')
                _field(
                  headLabel,
                  AppTextField(
                    controller: headC,
                    focusNode: headF,
                    error: headErr,
                    formatters: [LengthLimitingTextInputFormatter(emSubjectLimit)],
                    onChanged: (v) => _edit(emHeadKey(ch), v),
                  ),
                  '$headLabel ${headC.text.length} / $emSubjectLimit',
                  headErr,
                ),
              _field(
                'Message',
                AppTextField(
                  controller: bodyC,
                  focusNode: bodyF,
                  error: bodyErr,
                  maxLines: 12,
                  minLines: 5,
                  keyboard: TextInputType.multiline,
                  formatters: [LengthLimitingTextInputFormatter(emBodyLimit[ch])],
                  onChanged: (v) => _edit('body', v),
                ),
                'Message ${bodyC.text.length} / ${emBodyLimit[ch]}',
                bodyErr,
              ),
              Transform.translate(
                offset: const Offset(0, -6),
                child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (narrow)
                    SizedBox(width: double.infinity, child: Text('Insert a variable', style: AppText.s(12, W.w5, color: AppColors.muted)))
                  else
                    Padding(padding: const EdgeInsets.only(right: 2), child: Text('Insert a variable', style: AppText.s(12, W.w5, color: AppColors.muted))),
                  for (final v in emVariables) _varChip(v),
                ]),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Text('There is no $label text for this message yet. Turn it on to write one.',
                    textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted, h: 1.5)),
              ),
          ]),
        ),
        // `.em-foot`
        Container(
          padding: EdgeInsets.symmetric(horizontal: narrow ? 14 : 18, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColors.hbSaveBg,
            border: Border(top: BorderSide(color: AppColors.line)),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppRadius.card)),
          ),
          child: Row(spacing: 10, children: [
            if (custom)
              AppButton('Delete template', icon: AppIcons.trash, kind: BtnKind.textDanger, onPressed: _delete)
            else
              AppButton('Reset to default', icon: AppIcons.restart, kind: BtnKind.text, onPressed: _reset),
            Expanded(
              child: CutText(dirty.contains(sel) ? 'Not saved yet' : 'Saved', maxLines: 1, textAlign: TextAlign.right, style: AppText.s(12.5, W.w6, color: AppColors.muted)),
            ),
            AppButton.primary('Save', icon: AppIcons.check, loading: saving, onPressed: _save),
          ]),
        ),
      ]),
    );
  }

  Widget _field(String label, Widget input, String count, String? err) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        Text(label, style: AppText.label),
        input,
        if (err == null) Text(count, style: AppText.s(12, W.w5, color: AppColors.muted)),
      ]);

  /// `.em-ct`: channel tab with its on / off dot.
  Widget _chTab(String c) {
    final on = c == ch;
    return Hover(
      onTap: () => _channel(c),
      builder: (_, h, _) => Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: on ? AppColors.accent : Colors.transparent, width: 2))),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
          EmDot(_on(sel!, c)),
          Text(emChannelLabel[c]!, style: AppText.s(13, W.w6, color: on ? AppColors.accentText : (h ? AppColors.text : AppColors.text2))),
        ]),
      ),
    );
  }

  /// `.em-var`: tap to put the variable where the cursor is.
  Widget _varChip(String v) => Hover(
        onTap: () => _insertVar(v),
        builder: (_, h, _) => Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: h ? AppColors.accentSoft : AppColors.sub, borderRadius: AppRadius.all(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('{{$v}}', style: AppText.mono(11.5, color: h ? AppColors.accentText : AppColors.text2)),
          ]),
        ),
      );

  Widget _previewCard() {
    final c = _chans(sel!)[ch]!;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        emSideHead('Preview', end: Text(emChannelLabel[ch]!, style: AppText.s(12, W.w5, color: AppColors.muted))),
        EmPreview(
          channel: ch,
          on: c['on'] == true,
          head: '${c[emHeadKey(ch)] ?? ''}',
          body: '${c['body'] ?? ''}',
          sender: '${settings['sender_name'] ?? 'Train With Vimal'}',
          replyTo: '${settings['reply_to_email'] ?? ''}',
        ),
        Text('How Sana, a sample client, would see it. Variables are filled in for each person.', style: AppText.s(12, W.w5, color: AppColors.muted, h: 1.4)),
      ]),
    );
  }

  Widget _usedCard() {
    final t = _tpl(sel!)!;
    final used = [for (final u in (t['used_in'] as List? ?? const [])) u as Map];
    final sentBy = '${t['sent_by'] ?? ''}';
    final custom = t['is_custom'] == true;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        emSideHead('Where it is used'),
        for (final u in used) EmUsedRow(name: '${u['name']}', line: '${u['line']}', onTap: () => context.go('/automations/${u['id']}')),
        if (sentBy.isNotEmpty || (used.isEmpty && !custom)) FmNote(AppIcons.gear, sentBy.isEmpty ? 'Sent by the app.' : sentBy),
        if (used.isEmpty && custom) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
            const Padding(padding: EdgeInsets.only(top: 2), child: AppIcon(AppIcons.bolt, size: 16, color: AppColors.muted)),
            Expanded(child: Text('Not used yet. Add it to a Send message step in an automation.', style: AppText.s(13, W.w5, color: AppColors.muted, h: 1.5))),
          ]),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton('Open automation builder', icon: AppIcons.bolt, size: BtnSize.sm, onPressed: () => context.go('/automations/new')),
          ),
        ],
      ]),
    );
  }

  // ─────────────────────────────── Team alerts

  Widget _alertsTab(double cw) {
    final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
      _quietCard(),
      // Daily digest card hidden for now (Gautam 2026-10-23); it comes back with the Daily summary design.
      // _digestCard(),
    ]);
    if (cw < 820) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [_alertsCard(cw), side]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [Expanded(child: _alertsCard(cw)), SizedBox(width: 320, child: side)]);
  }

  bool get _allOn => alerts.isNotEmpty && alerts.every((a) => emChannels.every((c) => (a['channels'] as Map?)?[c] == true));

  Widget _alertsCard(double cw) {
    final phone = cw < 600;
    final cell = phone ? 50.0 : 92.0;
    final enable = AppButton(_allOn ? 'All channels on' : 'Enable all', size: BtnSize.sm, onPressed: _enableAll);
    Widget headCell(String t) => SizedBox(
          width: cell,
          child: Text(t, textAlign: TextAlign.center, maxLines: 1, softWrap: false, overflow: TextOverflow.visible, style: AppText.s(phone ? 10 : 12, W.w6, color: AppColors.text2)),
        );
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
          child: Builder(builder: (_) {
            final words = Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text('Who gets notified, where', style: AppText.s(15, W.w8)),
              Text('Goes to you and the assigned trainer. Client messages are in the first tab.', style: AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.4)),
            ]);
            // `.em-alh` wraps on a phone: the button goes under the words
            return phone
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [words, enable])
                : Row(spacing: 12, children: [Expanded(child: words), enable]);
          }),
        ),
        Container(
          color: AppColors.tableHead,
          padding: EdgeInsets.fromLTRB(phone ? 14 : 12, 9, phone ? 6 : 0, 9),
          child: Row(children: [
            Expanded(child: Text('Event', style: AppText.s(12, W.w6, color: AppColors.text2))),
            for (final c in emChannels) headCell(emChannelLabel[c]!),
          ]),
        ),
        for (final a in alerts)
          Container(
            padding: EdgeInsets.fromLTRB(phone ? 14 : 12, 8, phone ? 6 : 0, 8),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text('${a['label']}', style: AppText.s(13.5, W.w7)),
                  Text('${a['description'] ?? ''}', style: AppText.s(12, W.w5, color: AppColors.muted)),
                ]),
              ),
              for (final c in emChannels)
                SizedBox(
                  width: cell,
                  child: Center(
                    child: AppTooltip(
                      message: '${a['label']} by ${emChannelLabel[c]}',
                      child: Hover(onTap: () => _toggleAlert(a, c), builder: (_, _, _) => FmCheck(on: (a['channels'] as Map?)?[c] == true, square: true)),
                    ),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }

  Future<void> _toggleAlert(Map a, String c) async {
    final before = Map<String, dynamic>.from(a['channels'] as Map);
    final next = {...before, c: before[c] != true};
    setState(() => a['channels'] = next);
    try {
      await Services.api.patch<Map>('team-alerts/${a['id']}/', {'channels': next});
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => a['channels'] = before);
      showToast(context, 'Could not change it', sub: e.message, kind: ToastKind.err);
    }
  }

  Future<void> _enableAll() async {
    if (_allOn) return;
    try {
      final r = await Services.api.post<List>('team-alerts/enable-all/');
      if (!mounted) return;
      setState(() => alerts = [for (final x in r) x as Map]);
      showToast(context, 'All channels on');
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not change it', sub: e.message, kind: ToastKind.err);
    }
  }

  Future<void> _patchSettings(Map<String, dynamic> body) async {
    final before = Map.of(settings);
    setState(() => settings = {...settings, ...body});
    try {
      final r = await Services.api.patch<Map>('settings/notifications/', body);
      if (mounted) setState(() => settings = r);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => settings = before);
      showToast(context, 'Could not save it', sub: e.message, kind: ToastKind.err);
    }
  }

  static String _hm(String v) => v.length >= 5 ? v.substring(0, 5) : v;

  static String _clock(String hm) {
    final p = hm.split(':');
    final h = int.tryParse(p.first) ?? 0, m = p.length > 1 ? p[1] : '00';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m ${h < 12 ? 'am' : 'pm'}';
  }

  Widget _timeSelect(String label, String key) {
    final cur = _hm('${settings[key] ?? '00:00'}');
    final times = [for (var i = 0; i < 48; i++) '${(i ~/ 2).toString().padLeft(2, '0')}:${i.isEven ? '00' : '30'}'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      Text(label, style: AppText.label),
      AppSelect(_clock(cur), entries: [
        for (final t in times) MenuEntry(_clock(t), selected: t == cur, onTap: () => _patchSettings({key: t})),
      ]),
    ]);
  }

  Widget _quietCard() {
    final on = settings['quiet_hours_on'] == true;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        emSideHead('Quiet hours', end: AppTooltip(message: on ? 'Turn quiet hours off' : 'Turn quiet hours on', child: AppToggle(value: on, onChanged: (v) => _patchSettings({'quiet_hours_on': v})))),
        Text('No push or WhatsApp at night. Emails wait in a queue.', style: AppText.s(12, W.w5, color: AppColors.muted, h: 1.5)),
        if (on)
          Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
            Expanded(child: _timeSelect('From', 'quiet_start')),
            Expanded(child: _timeSelect('To', 'quiet_end')),
          ]),
      ]),
    );
  }

  // ignore: unused_element
  Widget _digestCard() {
    final d = '${settings['digest'] ?? 'off'}';
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        emSideHead('Daily digest'),
        SegmentedTabs<String>(
          expand: true,
          items: const [TabItem('off', 'Off'), TabItem('daily', 'Daily'), TabItem('weekly', 'Weekly')],
          value: d,
          onChanged: (v) => _patchSettings({'digest': v}),
        ),
        Text(
          d == 'off'
              ? 'No digest email.'
              : 'One email at 8:00 am with check-ins to review, at-risk clients and plans ending${d == 'weekly' ? ', every Monday.' : '.'}',
          style: AppText.s(12, W.w5, color: AppColors.muted, h: 1.5),
        ),
      ]),
    );
  }

  // ─────────────────────────────── Sender

  Widget _senderTab(double cw) {
    final form = AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: cw < 600 ? 14 : 18, vertical: cw < 600 ? 14 : 16),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
          child: Row(spacing: 12, children: [
            IconTile(AppIcons.send, size: 44, radius: 11, iconSize: 22, bg: AppColors.hbTones[0].$1, fg: AppColors.hbTones[0].$2),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text('Sender identity', style: AppText.s(16, W.w7)),
                Text('Shown on every email and WhatsApp message to clients', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: EdgeInsets.all(cw < 600 ? 14 : 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
            _sField(emReq('From name'), nameC, 'sender_name', 'Your gym or coaching name'),
            _sField(Text('Reply-to email', style: AppText.label), replyC, 'reply_to_email', 'Client replies to emails land here', keyboard: TextInputType.emailAddress),
            _sField(Text('WhatsApp display number', style: AppText.label), waC, 'whatsapp_number', 'Shown in the WhatsApp chat header', keyboard: TextInputType.phone),
          ]),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: cw < 600 ? 14 : 18, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColors.hbSaveBg,
            border: Border(top: BorderSide(color: AppColors.line)),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppRadius.card)),
          ),
          child: Row(children: [const Spacer(), AppButton.primary('Save', icon: AppIcons.check, loading: sSaving, onPressed: _saveSender)]),
        ),
      ]),
    );
    final see = AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        emSideHead('Clients see'),
        ListenableBuilder(
          listenable: Listenable.merge([nameC, replyC]),
          builder: (_, _) => Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.hbPhone, borderRadius: AppRadius.all(16)),
            child: EmMail(
              sender: nameC.text.trim().isEmpty ? 'Train With Vimal' : nameC.text.trim(),
              line: 'reply to ${replyC.text.trim()}',
              subject: 'Weekly check-in time, Sana',
              body: 'It takes 2 minutes: your weight, measurements and how the week went.',
            ),
          ),
        ),
      ]),
    );
    if (cw < 760) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [form, see]);
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [Expanded(child: form), SizedBox(width: 340, child: see)]),
      ),
    );
  }

  Widget _sField(Widget label, TextEditingController c, String key, String hint, {TextInputType? keyboard}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        label,
        AppTextField(controller: c, keyboard: keyboard, error: sErr[key], onChanged: (_) {
          if (sErr[key] != null) setState(() => sErr = {...sErr, key: null});
        }),
        if (sErr[key] == null) Text(hint, style: AppText.s(12, W.w5, color: AppColors.muted)),
      ]);

  Future<void> _saveSender() async {
    if (nameC.text.trim().isEmpty) return setState(() => sErr = {...sErr, 'sender_name': 'Add the name clients see.'});
    setState(() => sSaving = true);
    try {
      final r = await Services.api.patch<Map>('settings/notifications/', {
        'sender_name': nameC.text.trim(),
        'reply_to_email': replyC.text.trim(),
        'whatsapp_number': waC.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        settings = r;
        sSaving = false;
        sErr = {};
        waC.text = '${r['whatsapp_number'] ?? ''}';
      });
      showToast(context, 'Sender settings saved', sub: 'Used on every email and WhatsApp message');
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        sSaving = false;
        sErr = {for (final k in ['sender_name', 'reply_to_email', 'whatsapp_number']) k: e.fields[k]?.first};
      });
      if (sErr.values.every((v) => v == null)) showToast(context, 'Could not save', sub: e.message, kind: ToastKind.err);
    }
  }
}
