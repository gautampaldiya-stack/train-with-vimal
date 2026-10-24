import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/util/save_file.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import '../../../core/widgets/tooltip.dart';
import '../../auth/account_widgets.dart' show shownUrl;
import '../../trainer/client_profile/cp_content_drawers.dart' show DrOpts, DrSwitch;

/// Invite links modal (boards Clients / Approvals `invo`): three tabs.
/// - Invite link: one link with its QR, Copy / WhatsApp / Email / Download QR, and its settings (who the
///   sign-ups go to, how long it works, how many people, whether they wait in Approvals). Changes save at once.
/// - New link: trainer, name, how long, how many, code → Create link.
/// - All links: totals, every link with ⋯ (Open link and QR, Copy, Turn off / on, Delete with Undo).
Future<void> showInviteLinksModal(BuildContext context, {String tab = 'main'}) => showAppModal<void>(
      context,
      title: 'Invite links',
      icon: AppIcons.link,
      width: 600,
      content: (ctx) => _InviteLinks(tab: tab),
    );

const _durations = [(7, '7 days'), (30, '30 days'), (90, '90 days'), (0, 'No end date')];
const _limits = [(0, 'No limit'), (10, '10 people'), (20, '20 people'), (50, '50 people'), (100, '100 people')];

class _InviteLinks extends StatefulWidget {
  const _InviteLinks({required this.tab});
  final String tab;
  @override
  State<_InviteLinks> createState() => _InviteLinksState();
}

class _InviteLinksState extends State<_InviteLinks> {
  late String tab = widget.tab, from = 'main';
  List<Map> links = [], trainers = [];
  String? openId, menuFor;
  bool loading = true;
  ApiError? error;

  // New link form
  String? newTrainer;
  final newName = TextEditingController();
  int newDays = 30, newMax = 0;
  bool newAppr = true, creating = false;
  String? newCode;
  List<String> codes = [];
  String? newErr;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    newName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([Services.api.get<List>('invite-links/'), Services.api.get<Map>('trainers/', query: {'page_size': 100})]);
      if (!mounted) return;
      setState(() {
        links = [for (final x in r[0] as List) x as Map];
        trainers = [for (final t in ((r[1] as Map)['results'] as List? ?? const [])) if ('${(t as Map)['status']}' == 'active') t];
        openId ??= (links.where((l) => l['state'] == 'on').firstOrNull ?? links.firstOrNull)?['id']?.toString();
        loading = false;
        error = null;
        if (tab == 'main' && links.isEmpty) tab = 'new';
      });
      if (tab == 'new' && codes.isEmpty) _startNew();
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e;
        });
      }
    }
  }

  Map? get _open => links.where((l) => '${l['id']}' == openId).firstOrNull;
  int get _on => links.where((l) => l['state'] == 'on').length;
  String get _sumT => '$_on of ${links.length} link${links.length == 1 ? '' : 's'} ${_on == 1 ? 'is' : 'are'} on';

  void _go(String t) {
    setState(() {
      from = tab;
      tab = t;
      menuFor = null;
    });
    if (t == 'new') _startNew();
  }

  // ─────────────────────────────── Helpers

  static String _short(String url) => url.replaceFirst(RegExp(r'^https?://'), '');
  static DateTime? _dt(Object? v) => DateTime.tryParse('${v ?? ''}')?.toLocal();
  static String _dm(DateTime d) => DateFormat('d MMM').format(d);

  /// "30 days · till 8 Nov" / "No end date".
  String _worksFor(Map l) {
    final exp = _dt(l['expires_at']), made = _dt(l['created_at']);
    if (exp == null) return 'No end date';
    final days = made == null ? null : exp.difference(made).inHours / 24;
    return '${days == null ? '' : '${days.round()} days · '}till ${_dm(exp)}';
  }

  /// "till 8 Nov", "ended 8 Oct", "no end date".
  String _till(Map l) {
    final exp = _dt(l['expires_at']);
    if (exp == null) return 'no end date';
    return '${exp.isBefore(DateTime.now()) ? 'ended' : 'till'} ${_dm(exp)}';
  }

  String _max(Map l) {
    final m = l['max_uses'] as num?;
    if (m == null) return 'No limit';
    return '$m people · ${l['joined'] ?? 0} used';
  }

  (String, Tone) _state(Map l) => switch ('${l['state']}') { 'on' => ('On', Tone.ok), 'off' => ('Off', Tone.neutral), _ => ('Ended', Tone.neutral) };

  String _trName(Map? t) => '${t?['full_name'] ?? ''}';

  Future<void> _patch(Map l, Map<String, dynamic> body, {String? done}) async {
    try {
      final r = await Services.api.patch<Map>('invite-links/${l['id']}/', body);
      if (!mounted) return;
      setState(() => links = [for (final x in links) '${x['id']}' == '${l['id']}' ? r : x]);
      if (done != null) showToast(context, done, kind: ToastKind.ok);
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not save the link', sub: e.fields.values.expand((x) => x).join(' ').isNotEmpty ? e.fields.values.expand((x) => x).join(' ') : e.message, kind: ToastKind.info);
    }
  }

  Future<void> _copy(Map l) async {
    await Clipboard.setData(ClipboardData(text: '${l['url']}'));
    if (mounted) showToast(context, 'Link copied', sub: _short('${l['url']}'), kind: ToastKind.ok);
  }

  String _shareText(Map l) => 'Join ${_trName(l['trainer'] as Map?)} at Train With Vimal: ${l['url']}';

  Future<void> _whatsapp(Map l) =>
      launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_shareText(l))}'), mode: LaunchMode.externalApplication).catchError((_) => false);

  Future<void> _email(Map l) => launchUrl(
        Uri(scheme: 'mailto', query: 'subject=${Uri.encodeComponent('Join Train With Vimal')}&body=${Uri.encodeComponent(_shareText(l))}'),
        mode: LaunchMode.externalApplication,
      ).catchError((_) => false);

  Future<void> _downloadQr(Map l) async {
    try {
      final painter = QrPainter(data: '${l['url']}', version: QrVersions.auto, gapless: true, eyeStyle: const QrEyeStyle(color: AppColors.text), dataModuleStyle: const QrDataModuleStyle(color: AppColors.text));
      final img = await painter.toImage(720);
      // white background around the code so it scans when printed
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 800, 800), Paint()..color = AppColors.white);
      canvas.drawImage(img, const Offset(40, 40), Paint());
      final out = await rec.endRecording().toImage(800, 800);
      final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
      final where = await saveFile('invite-${l['code']}.png', bytes!.buffer.asUint8List(), mime: 'image/png');
      if (mounted) showToast(context, 'QR saved', sub: where, kind: ToastKind.ok);
    } catch (_) {
      if (mounted) showToast(context, 'Could not save the QR', kind: ToastKind.info);
    }
  }

  Future<void> _delete(Map l) async {
    try {
      await Services.api.delete('invite-links/${l['id']}/');
      if (!mounted) return;
      setState(() {
        links = links.where((x) => '${x['id']}' != '${l['id']}').toList();
        if (openId == '${l['id']}') openId = links.firstOrNull?['id']?.toString();
        menuFor = null;
      });
      showToast(context, '${l['code']} deleted', sub: 'New sign-ups stop. People who joined keep their account.', action: 'Undo', onAction: () async {
        try {
          await Services.api.post('invite-links/${l['id']}/restore/');
          _load();
        } on ApiError catch (_) {}
      });
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not delete the link', sub: e.message, kind: ToastKind.info);
    }
  }

  Future<void> _startNew() async {
    final t = newTrainer ?? Services.session.me?.id ?? '';
    newTrainer = trainers.any((x) => '${x['id']}' == t) ? t : trainers.firstOrNull?['id']?.toString();
    if (newTrainer == null) return;
    try {
      // three suggestions made from the trainer's name ("AMAN-5530"); the first is picked
      final r = await Future.wait([for (var i = 0; i < 3; i++) Services.api.get<Map>('invite-links/suggest-code/', query: {'trainer': newTrainer})]);
      if (!mounted) return;
      setState(() {
        codes = {for (final x in r) '${x['code']}'}.toList();
        newCode = codes.first;
      });
    } on ApiError catch (_) {}
  }

  Future<void> _create() async {
    if (newTrainer == null || newCode == null) return;
    setState(() {
      creating = true;
      newErr = null;
    });
    try {
      final r = await Services.api.post<Map>('invite-links/', {
        'trainer_id': newTrainer,
        'label': newName.text.trim(),
        'code': newCode,
        'expires_at': newDays == 0 ? null : DateTime.now().add(Duration(days: newDays)).toUtc().toIso8601String(),
        'max_uses': newMax == 0 ? null : newMax,
        'needs_approval': newAppr,
      });
      if (!mounted) return;
      setState(() {
        links = [r, ...links];
        openId = '${r['id']}';
        tab = 'main';
        creating = false;
        newName.clear();
      });
      showToast(context, 'Link made', sub: _short('${r['url']}'), kind: ToastKind.ok);
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          creating = false;
          newErr = e.fields.values.expand((x) => x).join(' ').isNotEmpty ? e.fields.values.expand((x) => x).join(' ') : e.message;
        });
      }
    }
  }

  // ─────────────────────────────── Build

  @override
  Widget build(BuildContext context) {
    final sub = switch (tab) {
      'new' => 'For a new trainer or a campaign. The old links keep working.',
      'all' => 'Every link your team made. Open one to share it again or turn it off.',
      _ => 'Share it on WhatsApp or Instagram. People sign up and fill their own details.',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      Text(sub, style: AppText.s(13, W.w5, color: AppColors.muted, h: 1.5)),
      _tabs(),
      if (loading)
        const Padding(padding: EdgeInsets.all(30), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))))
      else if (error != null)
        EmptyState('Could not load the links', sub: error!.message, action: AppButton('Try again', onPressed: _load))
      else
        ...switch (tab) { 'new' => _newBody(), 'all' => _allBody(), _ => _mainBody() },
    ]);
  }

  Widget _tabs() => Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(spacing: 20, children: [
            for (final (k, l, n) in [('main', 'Invite link', null), ('new', 'New link', null), ('all', 'All links', links.length)])
              Hover(
                onTap: tab == k ? null : () => _go(k),
                builder: (_, h, _) => Container(
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 9),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tab == k ? AppColors.text : Colors.transparent, width: 2))),
                  child: Row(spacing: 6, children: [
                    Text(l, style: AppText.s(13, W.w6, color: tab == k || h ? AppColors.text : AppColors.muted)),
                    if (n != null && n > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(10)),
                        child: Text('$n', style: AppText.s(11, W.w7, color: AppColors.muted)),
                      ),
                  ]),
                ),
              ),
          ]),
        ),
      );

  Widget _footer(String lead, List<Widget> buttons) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: context.isPhone
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                Text(lead, style: AppText.cap),
                Row(spacing: 8, children: [for (final b in buttons) Expanded(child: b)]),
              ])
            : Row(spacing: 8, children: [Expanded(child: CutText(lead, maxLines: 1, style: AppText.cap)), ...buttons]),
      );

  Widget _done() => AppButton.primary('Done', expand: context.isPhone, onPressed: () => Navigator.of(context).pop());

  // ── Invite link

  List<Widget> _mainBody() {
    final l = _open;
    if (l == null) {
      return [EmptyState('No invite link yet', sub: 'Make one for a trainer or a campaign.', action: AppButton.primary('New link', icon: AppIcons.plus, onPressed: () => _go('new')))];
    }
    final appr = l['needs_approval'] == true;
    final tr = _trName(l['trainer'] as Map?);
    final stateWord = '${l['state']}' == 'on' ? (appr ? 'Sign-ups wait in Approvals' : 'Sign-ups join straight away') : 'This link is ${_state(l).$1.toLowerCase()}';
    final meta = '$stateWord · ${l['joined'] ?? 0} joined · ${l['waiting'] ?? 0} waiting · ${_till(l)}';
    final url = _short('${l['url']}');
    final cut = url.lastIndexOf('/') + 1;
    final phone = context.isPhone;
    final qr = Container(
      width: 96,
      height: 96,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.all(8)),
      child: QrImageView(data: '${l['url']}', padding: EdgeInsets.zero, gapless: true, eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.text), dataModuleStyle: const QrDataModuleStyle(color: AppColors.text)),
    );
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
      Text.rich(TextSpan(children: [
        TextSpan(text: url.substring(0, cut)),
        TextSpan(text: url.substring(cut), style: AppText.s(14, W.w8)),
      ]), style: AppText.s(14, W.w5, color: AppColors.text2)),
      Text(meta, style: AppText.s(12, W.w5, color: AppColors.muted)),
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        AppButton.primary('Copy link', icon: AppIcons.copy, size: BtnSize.sm, onPressed: () => _copy(l)),
        AppButton('WhatsApp', icon: AppIcons.whatsapp, size: BtnSize.sm, onPressed: () => _whatsapp(l)),
        AppButton('Email', icon: AppIcons.mail, size: BtnSize.sm, onPressed: () => _email(l)),
        AppButton('Download QR', kind: BtnKind.text, size: BtnSize.sm, onPressed: () => _downloadQr(l)),
      ]),
    ]);
    final days = _dt(l['expires_at']) == null ? 0 : null;
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.ilCard, borderRadius: AppRadius.all(12)),
        child: phone
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [qr, info])
            : Row(spacing: 14, children: [qr, Expanded(child: info)]),
      ),
      Padding(padding: const EdgeInsets.only(top: 4), child: Text('Link settings', style: AppText.s(12.5, W.w8))),
      _grid([
        _f('Clients go to', AppSelect(tr, entries: [
          for (final t in trainers)
            MenuEntry('${t['full_name']}', selected: '${t['id']}' == '${(l['trainer'] as Map?)?['id']}', onTap: () => _patch(l, {'trainer_id': '${t['id']}'}, done: 'Sign-ups now go to ${t['full_name']}')),
        ]), hint: 'This trainer sees them first'),
        _f('Link works for', AppSelect(_worksFor(l), entries: [
          for (final (d, lbl) in _durations)
            MenuEntry(d == 0 ? lbl : '$lbl · till ${_dm(DateTime.now().add(Duration(days: d)))}',
                selected: d == 0 ? days == 0 : false,
                onTap: () => _patch(l, {'expires_at': d == 0 ? null : DateTime.now().add(Duration(days: d)).toUtc().toIso8601String()}, done: 'Link time changed')),
        ])),
        _f('How many people', AppSelect(_max(l), entries: [
          for (final (n, lbl) in _limits)
            MenuEntry(lbl, selected: (l['max_uses'] as num?) == (n == 0 ? null : n), onTap: () => _patch(l, {'max_uses': n == 0 ? null : n}, done: 'Limit changed')),
        ])),
      ]),
      DrSwitch(
        title: 'New sign-ups wait in Approvals',
        sub: 'You approve each person before they can log in',
        value: appr,
        onChanged: (v) => _patch(l, {'needs_approval': v}),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: AppRadius.all(10)),
        child: DefaultTextStyle.merge(
          style: AppText.s(12.5, W.w5, color: AppColors.ilExplainFg, h: 1.45),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
            Row(spacing: 6, children: [
              const AppIcon(AppIcons.eye, size: 15, color: AppColors.ilExplainFg),
              Text('What they see when they open the link', style: AppText.s(13, W.w7, color: AppColors.ilExplainFg)),
            ]),
            _step(1, Text.rich(TextSpan(children: [
              const TextSpan(text: 'A sign-up page: '),
              TextSpan(text: 'Join $tr at Train With Vimal', style: AppText.s(12.5, W.w7, color: AppColors.ilExplainFg)),
            ]))),
            _step(2, const Text('They make an account and fill their details: goal, body, health form, food.')),
            _step(3, Text(appr ? 'They wait in Approvals. You or $tr approve them, then they can log in.' : 'They can log in straight away. $tr gets a notice.')),
          ]),
        ),
      ),
      _footer(_sumT, [_done()]),
    ];
  }

  Widget _step(int n, Widget t) => Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle),
          child: Text('$n', style: AppText.s(11, W.w7, color: AppColors.ilExplainFg)),
        ),
        Expanded(child: t),
      ]);

  Widget _f(String label, Widget child, {String? hint}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        Text(label, style: AppText.label),
        child,
        if (hint != null) Text(hint, style: AppText.s(12, W.w5, color: AppColors.muted)),
      ]);

  /// `.cp-g2`: two columns, one on phone.
  Widget _grid(List<Widget> cells) {
    if (context.isPhone) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: cells);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      for (var i = 0; i < cells.length; i += 2)
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [Expanded(child: cells[i]), Expanded(child: i + 1 < cells.length ? cells[i + 1] : const SizedBox.shrink())]),
    ]);
  }

  // ── New link

  List<Widget> _newBody() {
    final t = trainers.where((x) => '${x['id']}' == newTrainer).firstOrNull;
    return [
      _grid([
        _f('Clients go to', AppSelect(t == null ? 'Pick a trainer' : '${t['full_name']}', entries: [
          for (final x in trainers)
            MenuEntry('${x['full_name']}', selected: '${x['id']}' == newTrainer, onTap: () {
              setState(() => newTrainer = '${x['id']}');
              _startNew();
            }),
        ]), hint: 'This trainer sees them first'),
        _f('Name for the link (optional)', AppTextField(controller: newName, placeholder: 'Instagram · October', formatters: [LengthLimitingTextInputFormatter(60)]), hint: 'Only your team sees this'),
        _f('Link works for', AppSelect(newDays == 0 ? 'No end date' : '$newDays days · till ${_dm(DateTime.now().add(Duration(days: newDays)))}', entries: [
          for (final (d, lbl) in _durations)
            MenuEntry(d == 0 ? lbl : '$lbl · till ${_dm(DateTime.now().add(Duration(days: d)))}', selected: d == newDays, onTap: () => setState(() => newDays = d)),
        ])),
        _f('How many people', AppSelect(_limits.firstWhere((x) => x.$1 == newMax).$2, entries: [
          for (final (n, lbl) in _limits) MenuEntry(lbl, selected: n == newMax, onTap: () => setState(() => newMax = n)),
        ])),
        _f('Code', AppSelect(newCode ?? '…', entries: [for (final c in codes) MenuEntry(c, selected: c == newCode, onTap: () => setState(() => newCode = c))]),
            hint: 'Made from the trainer name'),
      ]),
      DrSwitch(
        title: 'New sign-ups wait in Approvals',
        sub: 'You approve each person before they can log in',
        value: newAppr,
        onChanged: (v) => setState(() => newAppr = v),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.ilCard, borderRadius: AppRadius.all(8)),
        child: Row(spacing: 8, children: [
          const AppIcon(AppIcons.link, size: 15, color: AppColors.muted),
          Expanded(
            child: Text.rich(TextSpan(children: [
              const TextSpan(text: 'The link will be '),
              TextSpan(text: shownUrl('/join/${newCode ?? '…'}'), style: AppText.s(12.5, W.w7, color: AppColors.text)),
            ]), style: AppText.s(12.5, W.w5, color: AppColors.text2)),
          ),
        ]),
      ),
      if (newErr != null) Text(newErr!, style: AppText.s(12.5, W.w6, color: AppColors.badText)),
      _footer('The old links keep working', [
        AppButton('Cancel', expand: context.isPhone, onPressed: () => setState(() => tab = from == 'all' ? 'all' : (links.isEmpty ? 'new' : 'main'))),
        AppButton.primary('Create link', icon: AppIcons.check, expand: context.isPhone, loading: creating, onPressed: creating || newCode == null ? null : _create),
      ]),
    ];
  }

  // ── All links

  List<Widget> _allBody() {
    final joined = links.fold<num>(0, (a, l) => a + ((l['joined'] as num?) ?? 0));
    final waiting = links.fold<num>(0, (a, l) => a + ((l['waiting'] as num?) ?? 0));
    final sum = [(links.length, 'links'), (_on, 'on now'), (joined, 'people joined'), (waiting, 'waiting now')];
    return [
      Container(
        decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: AppRadius.all(10)),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, (v, k)) in sum.indexed)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(border: i == 0 ? null : const Border(left: BorderSide(color: AppColors.line))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$v', style: AppText.s(18, W.w8)),
                    CutText(k, maxLines: 1, style: AppText.s(12, W.w5, color: AppColors.muted)),
                  ]),
                ),
              ),
          ]),
        ),
      ),
      if (links.isEmpty)
        EmptyState('No links yet', action: AppButton.primary('New link', icon: AppIcons.plus, onPressed: () => _go('new')))
      else
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 236),
          child: SingleChildScrollView(child: DrOpts([for (final l in links) _linkRow(l)])),
        ),
      Text('Turning a link off stops new sign-ups. People who already joined keep their account. Deleting also hides it from this list.', style: AppText.s(12, W.w5, color: AppColors.muted)),
      _footer(_sumT, [_done()]),
    ];
  }

  Widget _linkRow(Map l) {
    final (b, tone) = _state(l);
    final made = _dt(l['created_at']);
    final dis = '${l['state']}' != 'on';
    void open() => setState(() {
          openId = '${l['id']}';
          tab = 'main';
        });
    return Hover(
      onTap: open,
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        color: h ? AppColors.outlineHover : null,
        child: Row(spacing: 12, children: [
          Opacity(opacity: dis ? .55 : 1, child: IconTile(AppIcons.link, size: 30, radius: 8, iconSize: 15)),
          Expanded(
            child: Opacity(
              opacity: dis ? .7 : 1,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('${l['code']}', style: AppText.s(13.5, W.w7)),
                  AppBadge(b, tone: tone, plain: true),
                  if ('${l['label'] ?? ''}'.isNotEmpty) Text('${l['label']}', style: AppText.s(12, W.w5, color: AppColors.muted)),
                ]),
                CutText('${_trName(l['trainer'] as Map?)} · Made ${made == null ? '' : _dm(made)} · ${_till(l)}', maxLines: 1, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
              ]),
            ),
          ),
          if (!context.isPhone)
            SizedBox(
              width: 80,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${l['joined'] ?? 0} joined', style: AppText.s(12.5, W.w7)),
                Text((l['waiting'] as num? ?? 0) > 0 ? '${l['waiting']} waiting' : 'none waiting', style: AppText.s(11.5, W.w5, color: AppColors.muted)),
              ]),
            ),
          Builder(
            builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'More actions', small: true, ghost: true, fill: true, onPressed: () => showAppMenu(b, width: 200, [
                  MenuEntry('Open link and QR', icon: AppIcons.open, onTap: open),
                  MenuEntry('Copy link', icon: AppIcons.copy, onTap: () => _copy(l)),
                  if ('${l['state']}' != 'ended' || l['is_on'] == false)
                    MenuEntry(l['is_on'] == false ? 'Turn on' : 'Turn off', icon: AppIcons.pause,
                        onTap: () => _patch(l, {'is_on': l['is_on'] == false}, done: l['is_on'] == false ? '${l['code']} is on' : '${l['code']} is off')),
                  const MenuEntry.separator(),
                  MenuEntry('Delete link', icon: AppIcons.trash, danger: true, onTap: () => _delete(l)),
                ])),
          ),
        ]),
      ),
    );
  }
}
