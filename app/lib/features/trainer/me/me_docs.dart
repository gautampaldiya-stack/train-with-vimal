import 'dart:typed_data';

import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/media.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import 'me_common.dart';
import 'me_model.dart';
import 'me_pick.dart';

/// Documents tab: "Certificates and documents" + Upload document, cards grouped Certificates / ID and contract.
/// A card opens the viewer (zoom, previous / next, Replace file, Delete). Only Vimal marks a file verified.
class MeDocsTab extends StatelessWidget {
  const MeDocsTab(this.c, {super.key});
  final MeController c;

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final all = [...c.certs, ...c.otherDocs];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.end, runSpacing: 10, spacing: 12, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 2, children: [
          Text('Certificates and documents', style: AppText.s(15.5, W.w7, ls: -0.15)),
          Text(c.docs.isEmpty ? 'Nothing uploaded yet' : c.docSummary, style: AppText.cap),
        ]),
        AppButton.primary('Upload document', icon: AppIcons.upload, expand: phone, onPressed: () => showUploadDocument(context, c)),
      ]),
      const SizedBox(height: 4),
      if (c.docs.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: AppCard(
            child: EmptyState('No documents yet',
                sub: 'Upload your certificates, ID proof and contract. Clients see certificates after Vimal verifies them.',
                action: AppButton.primary('Upload document', icon: AppIcons.upload, onPressed: () => showUploadDocument(context, c))),
          ),
        ),
      for (final (name, items) in [('Certificates', c.certs), ('ID and contract', c.otherDocs)])
        if (items.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            child: Row(spacing: 6, children: [
              Text(name.toUpperCase(), style: AppText.s(11.5, W.w6, color: AppColors.muted, ls: .46)),
              Text('·', style: AppText.s(11.5, W.w5, color: AppColors.muted)),
              Text('${items.length}', style: AppText.s(11.5, W.w5, color: AppColors.muted)),
            ]),
          ),
          LayoutBuilder(builder: (context, b) {
            final cols = b.maxWidth < 560 ? 1 : (b.maxWidth < 900 ? 2 : 3);
            final gap = cols == 3 ? 16.0 : 12.0;
            final w = (b.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(spacing: gap, runSpacing: gap, children: [
              for (final d in items) SizedBox(width: w, child: _DocCard(d, onOpen: () => showDocViewer(context, c, all.indexOf(d)))),
            ]);
          }),
        ],
    ]);
  }
}

String _validTill(Map d) => d['expires_on'] == null ? 'No end date' : (d['kind'] == 'contract' ? meDmy(d['expires_on']) : meMy(d['expires_on']));
String _issued(Map d) => d['issued_on'] == null ? '—' : (d['kind'] == 'contract' ? meDmy(d['issued_on']) : meMy(d['issued_on']));
bool _clientsSee(Map d) => d['visibility'] == 'admins_clients' && d['kind'] == 'certificate';

/// `.card.tp-doc`.
class _DocCard extends StatelessWidget {
  const _DocCard(this.d, {required this.onOpen});
  final Map<String, dynamic> d;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final warn = d['status'] == 'expires_soon' || d['status'] == 'expired';
    final cl = _clientsSee(d);
    return Hover(
      onTap: onOpen,
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppRadius.all(AppRadius.card),
          border: Border.all(color: h ? AppColors.line2 : AppColors.line),
          boxShadow: h ? const [BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2))] : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          Row(spacing: 10, children: [
            meDocIcon('${d['kind']}'),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text('${d['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w6, h: 1.3)),
                if ('${d['issuer'] ?? ''}'.isNotEmpty) Text('${d['issuer']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w4, color: AppColors.muted)),
              ]),
            ),
          ]),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            child: Row(children: [
              for (final (l, v, wv) in [('Issued', _issued(d), false), ('Valid till', _validTill(d), warn)])
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                    Text(l, style: AppText.s(11.5, W.w4, color: AppColors.muted)),
                    Text(v, style: AppText.s(12.5, W.w6, color: wv ? AppColors.warnText : AppColors.text)),
                  ]),
                ),
            ]),
          ),
          Row(spacing: 10, children: [
            AppBadge(meDocBadge(d), tone: meDocTone(d), plain: true),
            Expanded(
              child: Row(spacing: 4, children: [
                AppIcon(cl ? AppIcons.eye : AppIcons.lock, size: 13, color: cl ? AppColors.okText : AppColors.muted),
                Flexible(child: Text(cl ? 'Clients see it' : 'Admins only', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: cl ? AppColors.okText : AppColors.muted))),
              ]),
            ),
            MeTextBtn('View', onTap: onOpen),
          ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────── Upload a document

/// "Upload a document" modal. With [replace] it is "Replace file" for that document: the form is filled in and
/// a new file is optional (sent again, the admin checks it again).
Future<void> showUploadDocument(BuildContext context, MeController c, {Map<String, dynamic>? replace}) async {
  final f = _UpForm(replace);
  final saved = await showAppModal<Map<String, dynamic>>(
    context,
    title: replace == null ? 'Upload a document' : 'Replace file',
    body: replace == null ? 'Certificates, ID proof or contract. PDF or photo, up to 10 MB.' : '${replace['name']}. Vimal checks the new file again.',
    icon: AppIcons.upload,
    wide: true,
    content: (ctx) => ListenableBuilder(listenable: f, builder: (ctx, _) => f.build(ctx)),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      ListenableBuilder(
        listenable: f,
        builder: (_, _) => AppButton.primary(replace == null ? 'Upload' : 'Save', expand: ctx.isPhone, loading: f.saving, onPressed: () async {
          final r = await f.submit();
          if (r != null && ctx.mounted) Navigator.of(ctx).pop(r);
        }),
      ),
    ],
  );
  f.dispose();
  if (saved == null) return;
  c.putDoc(saved);
  if (context.mounted) {
    showToast(context, replace == null ? 'Document uploaded' : 'Document saved', sub: 'Vimal gets a notice to check it', kind: ToastKind.ok);
  }
}

class _UpForm extends ChangeNotifier {
  _UpForm(this.old) {
    final o = old;
    if (o != null) {
      kind = '${o['kind']}';
      name.text = '${o['name'] ?? ''}';
      issuer.text = '${o['issuer'] ?? ''}';
      issued = meParse(o['issued_on']);
      expires = meParse(o['expires_on']);
      clients = o['visibility'] == 'admins_clients';
      remind = o['remind_before_expiry'] != false;
    }
  }
  final Map<String, dynamic>? old;
  String kind = 'certificate';
  final name = TextEditingController(), issuer = TextEditingController();
  DateTime? issued, expires;
  bool clients = true, remind = true, saving = false;
  (String, Uint8List)? file;
  String? fileErr, nameErr, expErr, formErr;

  @override
  void dispose() {
    name.dispose();
    issuer.dispose();
    super.dispose();
  }

  void _set(VoidCallback f) {
    f();
    notifyListeners();
  }

  Future<void> pick() async {
    final r = await pickDocument();
    if (r == null) return;
    final ext = r.$1.split('.').last.toLowerCase();
    _set(() {
      if (!['pdf', 'jpg', 'jpeg', 'png'].contains(ext)) {
        fileErr = 'Upload a PDF, JPG or PNG.';
      } else if (r.$2.length > 10 * 1024 * 1024) {
        fileErr = 'This file is over 10 MB. Pick a smaller one.';
      } else {
        file = r;
        fileErr = null;
        if (name.text.trim().isEmpty) name.text = r.$1.replaceFirst(RegExp(r'\.[^.]+$'), '').replaceAll(RegExp(r'[-_]+'), ' ');
      }
    });
  }

  Future<Map<String, dynamic>?> submit() async {
    _set(() {
      nameErr = name.text.trim().isEmpty ? 'Enter the name on the document.' : null;
      fileErr = old == null && file == null ? 'Pick a file to upload.' : fileErr;
      expErr = issued != null && expires != null && expires!.isBefore(issued!) ? 'Valid till is before the issue date.' : null;
      formErr = null;
    });
    if (nameErr != null || fileErr != null || expErr != null) return null;
    _set(() => saving = true);
    final fmt = DateFormat('yyyy-MM-dd');
    final data = <String, dynamic>{
      'kind': kind,
      'name': name.text.trim(),
      'issuer': issuer.text.trim(),
      'issued_on': issued == null ? '' : fmt.format(issued!),
      'expires_on': expires == null ? '' : fmt.format(expires!),
      'visibility': clients && kind == 'certificate' ? 'admins_clients' : 'admins',
      'remind_before_expiry': remind,
      if (file != null) 'file': MultipartFile.fromBytes(file!.$2, filename: file!.$1),
    };
    try {
      final fd = FormData.fromMap(data);
      final r = old == null
          ? await Services.api.post<Map>('trainers/me/documents/', fd)
          : await Services.api.patch<Map>('trainers/me/documents/${old!['id']}/', fd);
      return Map<String, dynamic>.from(r);
    } on ApiError catch (e) {
      _set(() {
        saving = false;
        nameErr = e.field('name');
        expErr = e.field('expires_on') ?? e.field('issued_on');
        fileErr = e.field('file');
        formErr = (nameErr ?? expErr ?? fileErr) == null ? e.message : null;
      });
      return null;
    }
  }

  Widget build(BuildContext context) {
    final picked = file;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
      Hover(
        onTap: pick,
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: h ? AppColors.hover : AppColors.sub,
            borderRadius: AppRadius.all(12),
            border: Border.all(color: fileErr != null ? AppColors.badText : AppColors.line2, width: 1.5),
          ),
          child: Column(spacing: 4, children: [
            AppIcon(picked == null ? AppIcons.upload : AppIcons.file, size: 22, color: AppColors.accent),
            if (picked == null)
              Text.rich(
                TextSpan(text: old == null ? 'Pick a file or ' : 'Keep the file or ', style: AppText.s(13, W.w7), children: [
                  TextSpan(text: 'browse', style: AppText.s(13, W.w7).copyWith(decoration: TextDecoration.underline)),
                ]),
                textAlign: TextAlign.center,
              )
            else
              Text(picked.$1, textAlign: TextAlign.center, style: AppText.s(13, W.w7)),
            Text(picked == null ? 'PDF, JPG or PNG' : '${_size(picked.$2.length)} · tap to pick another', style: AppText.s(12, W.w5, color: AppColors.muted)),
          ]),
        ),
      ),
      if (fileErr != null) Text(fileErr!, style: AppText.s(12, W.w6, color: AppColors.badText)),
      MeGrid2([
        meField('Type', AppSelect(meDocKind(kind), entries: [
          for (final (k, l) in meDocKinds) MenuEntry(l, selected: k == kind, onTap: () => _set(() => kind = k)),
        ])),
        meField('Name', AppTextField(controller: name, placeholder: 'Kettlebell Level 1', onChanged: (_) {
          if (nameErr != null) _set(() => nameErr = null);
        }), error: nameErr, req: true),
        meField('Issued by', AppTextField(controller: issuer, placeholder: 'StrongFirst')),
        meField(
            'Issued on',
            MeDateBox(
              value: issued,
              placeholder: 'Pick a date',
              last: DateTime.now(),
              format: (d) => DateFormat('d MMM yyyy').format(d),
              onPick: (d) => _set(() => issued = d),
              onClear: () => _set(() => issued = null),
            )),
        meField(
            'Valid till',
            MeDateBox(
              value: expires,
              placeholder: 'No end date',
              first: issued,
              format: (d) => DateFormat('d MMM yyyy').format(d),
              onPick: (d) => _set(() {
                expires = d;
                expErr = null;
              }),
              onClear: () => _set(() => expires = null),
            ),
            error: expErr),
        meField(
          'Who can see it',
          kind == 'certificate'
              ? AppSelect(clients ? 'Admins and clients' : 'Admins only', entries: [
                  MenuEntry('Admins and clients', selected: clients, onTap: () => _set(() => clients = true)),
                  MenuEntry('Admins only', selected: !clients, onTap: () => _set(() => clients = false)),
                ])
              : const AppSelect('Admins only', entries: []),
          hint: kind == 'certificate' ? 'Clients see it after the admin verifies it' : 'ID and contracts stay with the admins',
        ),
      ]),
      MeSwitch(title: 'Remind me before it expires', sub: '30 days before, on the Dashboard', value: remind, onChanged: (v) => _set(() => remind = v)),
      if (formErr != null) Text(formErr!, style: AppText.s(12.5, W.w6, color: AppColors.badText)),
    ]);
  }
}

String _size(int n) => n >= 1048576 ? '${(n / 1048576).toStringAsFixed(1)} MB' : '${(n / 1024).round().clamp(1, 1024)} KB';

// ─────────────────────────────── Viewer

/// `.modal.tp-viewer`: the file on the left (zoom 50–150 %, download), details on the right with previous / next,
/// Replace file and Delete. Phone: a tall sheet, file on top.
Future<void> showDocViewer(BuildContext context, MeController c, int start) => showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Document',
      barrierColor: AppColors.scrimModal,
      pageBuilder: (ctx, _, _) => _Viewer(c, start: start),
    );

class _Viewer extends StatefulWidget {
  const _Viewer(this.c, {required this.start});
  final MeController c;
  final int start;
  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late int i = widget.start;
  int zoom = 100;

  List<Map<String, dynamic>> get all => [...widget.c.certs, ...widget.c.otherDocs];

  void _go(int d) => setState(() {
        i = (i + d + all.length) % all.length;
        zoom = 100;
      });

  Future<void> _delete(Map<String, dynamic> d) async {
    final ok = await confirmAction(context, title: 'Delete this document?', body: '${d['name']} is removed for good. Clients stop seeing it.', confirm: 'Delete', danger: true, icon: AppIcons.trash);
    if (!ok || !mounted) return;
    try {
      await Services.api.delete('trainers/me/documents/${d['id']}/');
      widget.c.dropDoc('${d['id']}');
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context, 'Document deleted', sub: '${d['name']}', kind: ToastKind.del);
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not delete it', sub: e.message, kind: ToastKind.err);
    }
  }

  Future<void> _replace(Map<String, dynamic> d) async {
    await showUploadDocument(context, widget.c, replace: d);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final docs = all;
    if (docs.isEmpty) return const SizedBox.shrink();
    if (i >= docs.length) i = docs.length - 1;
    final d = docs[i];
    final phone = context.isPhone;
    final size = MediaQuery.sizeOf(context);
    final stage = _stage(d);
    final side = _side(d, docs.length);
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: phone ? size.width : (size.width - 48).clamp(320.0, 980.0),
          height: phone ? size.height * .92 : (size.height - 48).clamp(320.0, 640.0),
          margin: phone ? EdgeInsets.only(top: size.height * .08) : null,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.modal), boxShadow: AppShadows.modal),
          child: phone
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [SizedBox(height: size.height * .38, child: stage), Expanded(child: side)])
              : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: stage), SizedBox(width: 320, child: side)]),
        ),
      ),
    );
  }

  Widget _stage(Map d) {
    final url = '${d['file_url'] ?? ''}';
    final ext = '${(d['file_info'] as Map?)?['ext'] ?? ''}'.toLowerCase();
    final img = ['jpg', 'jpeg', 'png'].contains(ext);
    final fname = Uri.tryParse(url)?.pathSegments.lastOrNull ?? '';
    final dark = AppColors.text;
    return Container(
      color: dark,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(spacing: 4, children: [
            Expanded(child: Text(fname, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.white))),
            if (img) ...[
              _dk(AppIcons.zoomOut, 'Zoom out', zoom > 50 ? () => setState(() => zoom -= 25) : null),
              SizedBox(width: 44, child: Text('$zoom%', textAlign: TextAlign.center, style: AppText.s(12, W.w6, color: AppColors.white))),
              _dk(AppIcons.zoomIn, 'Zoom in', zoom < 150 ? () => setState(() => zoom += 25) : null),
            ],
            _dk(AppIcons.download, 'Download', url.isEmpty ? null : () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)),
          ]),
        ),
        Expanded(
          child: url.isEmpty
              ? const SizedBox()
              : img
                  ? ClipRect(
                      child: InteractiveViewer(
                        child: Center(child: Transform.scale(scale: zoom / 100, child: NetImage(url, fit: BoxFit.contain))),
                      ),
                    )
                  : Center(
                      child: Container(
                        width: 220,
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.all(6)),
                        child: Column(mainAxisSize: MainAxisSize.min, spacing: 10, children: [
                          meDocIcon('${d['kind']}', size: 44),
                          Text('${d['name']}', textAlign: TextAlign.center, style: AppText.s(13.5, W.w7)),
                          Text('PDF file', style: AppText.s(12, W.w5, color: AppColors.muted)),
                          AppButton('Open file', size: BtnSize.sm, onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)),
                        ]),
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _dk(AppIconData ic, String tip, VoidCallback? onTap) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Tooltip(
          message: tip,
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: h && onTap != null ? AppColors.white.withValues(alpha: .12) : null, borderRadius: AppRadius.all(6)),
            child: AppIcon(ic, size: 16, color: AppColors.white.withValues(alpha: onTap == null ? .35 : 1)),
          ),
        ),
      );

  Widget _side(Map<String, dynamic> d, int n) {
    final warn = d['status'] == 'expires_soon' || d['status'] == 'expired';
    final info = (d['file_info'] as Map?)?['label'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
        child: Row(spacing: 8, children: [
          meDocIcon('${d['kind']}'),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text('${d['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7)),
              Text('${i + 1} of $n · ${meDocKind(d['kind'])}', style: AppText.s(12, W.w5, color: AppColors.muted)),
            ]),
          ),
          AppIconButton(AppIcons.prev, tooltip: 'Previous', ghost: true, small: true, onPressed: n > 1 ? () => _go(-1) : null),
          AppIconButton(AppIcons.next, tooltip: 'Next', ghost: true, small: true, onPressed: n > 1 ? () => _go(1) : null),
          AppIconButton(AppIcons.close, tooltip: 'Close', ghost: true, small: true, onPressed: () => Navigator.of(context).pop()),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            Align(alignment: Alignment.centerLeft, child: AppBadge(meDocBadge(d), tone: meDocTone(d), plain: true)),
            MeKv(padding: EdgeInsets.zero, columns: 1, [
              ('Type', MeKv.text(meDocKind(d['kind']))),
              ('Issued by', MeKv.text('${d['issuer'] ?? ''}')),
              ('Issued on', MeKv.text(_issued(d))),
              ('Valid till', MeKv.text(_validTill(d), color: warn ? AppColors.warnText : null)),
              ('Who can see it', MeKv.text(_clientsSee(d) ? 'Clients see it' : 'Admins only')),
              ('Uploaded', MeKv.text(meDmy(d['created_at']))),
              ('File', MeKv.text('${info ?? '—'}')),
            ]),
            if (d['status'] == 'not_checked')
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(8)),
                child: Text('Waiting for Vimal to check it. Clients see it only after it is verified.', style: AppText.s(12.5, W.w5, color: AppColors.text2, h: 1.45)),
              ),
          ]),
        ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
        child: Row(children: [
          AppButton('Replace file', icon: AppIcons.replace, onPressed: () => _replace(d)),
          const Spacer(),
          MeTextBtn('Delete', danger: true, onTap: () => _delete(d)),
        ]),
      ),
    ]);
  }
}
