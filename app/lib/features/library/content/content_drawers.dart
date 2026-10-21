import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import '../../../core/widgets/tabs.dart';
import '../../trainer/client_profile/cp_content_drawers.dart' show DrOpt, DrScrollList, DrSwitch;
import '../../trainer/client_profile/cp_plans_meal_edit.dart' show DangerText;
import '../../trainer/me/me_common.dart' show meField;
import '../../trainer/me/me_docs.dart' show DashedBox;
import '../../trainer/me/me_pick.dart';
import '../lib_common.dart' show plural;
import '../programs/builder_sheets.dart' show showNameModal;
import 'ct_common.dart';

// Content library drawers and modals (boards `Content` / `ContentMobile`): the item drawer, New / Edit content,
// Assign to clients, New category and Delete.

// ─────────────────────────────── Item drawer

/// Opens one item: picture, Type · Length · Added by · Updated, its file, who sees it, where it is used and how
/// many clients opened it. Gives back what the footer asked for: `edit`, `assign`, `delete`, or `go:<path>` for a
/// client / exercise / program row.
Future<String?> showContentDetail(BuildContext context, String id, {required bool canManage}) async {
  Map d;
  try {
    d = await Services.api.get<Map>('content/$id/detail/');
  } on ApiError catch (e) {
    if (context.mounted) showToast(context, 'Could not open it', sub: e.message, kind: ToastKind.err);
    return null;
  }
  if (!context.mounted) return null;
  return showAppDrawer<String>(
    context,
    title: '${d['title']}',
    sub: [ctKindLabel(d['kind']), if ('${d['category_name'] ?? ''}'.isNotEmpty) '${d['category_name']}'].join(' · '),
    icon: AppIcons.content,
    builder: (ctx) => _Detail(d),
    footer: !canManage
        ? null
        : (ctx) {
            final del = DangerText('Delete', onTap: () => Navigator.of(ctx).pop('delete'));
            final edit = AppButton('Edit', icon: AppIcons.edit, onPressed: () => Navigator.of(ctx).pop('edit'));
            final assign = AppButton.primary('Assign to clients', icon: AppIcons.assign, onPressed: () => Navigator.of(ctx).pop('assign'));
            final row = Row(spacing: 8, children: [del, const Spacer(), edit, assign]);
            return [_fill(ctx, row)];
          },
  );
}

class _Detail extends StatelessWidget {
  const _Detail(this.d);
  final Map d;

  String get kind => '${d['kind']}';

  Future<void> _play() async {
    final u = '${d['youtube_url'] ?? ''}'.isNotEmpty ? '${d['youtube_url']}' : (d['file_url'] as String? ?? d['link_url'] as String? ?? '');
    if (u.isNotEmpty) await launchUrl(Uri.parse(u), webOnlyWindowName: '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final shared = d['shared_with'] as Map? ?? const {};
    final clients = [for (final c in (shared['clients'] as List? ?? const [])) c as Map];
    final uses = [for (final u in (d['used_in'] as List? ?? const [])) u as Map];
    final st = d['stats'] as Map? ?? const {};
    final len = '${d['length_label'] ?? ''}';
    final kv = [
      ('Type', ctKindLabel(kind)),
      switch (kind) {
        'video' => ('Length', len == 'Video' ? '–' : len),
        'pdf' => ('Pages', len.split(' ').first),
        'image' => ('Format', len),
        'link' => ('Site', len),
        _ => ('Read time', len),
      },
      ('Added by', '${d['added_by'] ?? '–'}'),
      ('Updated', ctDm(d['updated_at'])),
    ];
    final hasFile = '${d['file_name'] ?? ''}'.isNotEmpty;
    final text = kind == 'article' ? '${d['body'] ?? ''}'.trim() : '${d['description'] ?? ''}'.trim();
    return Padding(
      padding: EdgeInsets.only(top: context.isPhone ? 0 : 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          Hover(
            onTap: kind == 'article' ? null : _play,
            builder: (_, _, _) => AspectRatio(aspectRatio: 16 / 9, child: CtMedia(d, radius: AppRadius.all(12), bigPlay: true)),
          ),
          _Kpis(kv),
        ]),
        if (kind == 'video')
          meField(
            'Video',
            hasFile
                ? _FileRow(icon: AppIcons.video, name: '${d['file_name']}', sub: _fileSub(d), badge: 'Plays in the app', onTap: _play)
                : _FileRow(icon: AppIcons.youtube, name: '${d['youtube_url'] ?? ''}', sub: 'YouTube link', badge: 'Plays in the app', onTap: _play),
          ),
        if ((kind == 'pdf' || kind == 'image') && hasFile)
          meField(kind == 'pdf' ? 'PDF file' : 'Image',
              _FileRow(icon: ctIcon(kind), name: '${d['file_name']}', sub: _fileSub(d), badge: 'Opens in the app', onTap: _play)),
        if (kind != 'video' && text.isNotEmpty)
          meField(
            kind == 'article' ? 'Text' : 'Description',
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: AppColors.ctTextBg, borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.line)),
              child: Text(text, maxLines: 10, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w5, color: AppColors.text2, h: 1.6)),
            ),
          ),
        meField(
          'Who can see this',
          shared['everyone'] == true
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(8)),
                  child: Row(spacing: 8, children: [
                    const AppIcon(AppIcons.globe, size: 16, color: AppColors.muted),
                    Expanded(child: Text('Everyone. All current and future clients see it in their Library.', style: AppText.s(12.5, W.w5, color: AppColors.text2))),
                  ]),
                )
              : clients.isEmpty
                  ? Text('Not assigned to anyone yet. Clients still see it inside the exercise, program or plan that uses it.',
                      style: AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.45))
                  : _LinkList([
                      for (final c in clients)
                        _LinkRow(
                          lead: AppAvatar('${c['full_name']}', size: 28, initials: '${c['initials'] ?? ''}', colors: AppColors.avatarCode('${c['avatar_color'] ?? 'c1'}')),
                          title: '${c['full_name']}',
                          sub: 'Sees it in their Library',
                          onTap: () => Navigator.of(context).pop('go:/clients/${c['id']}'),
                        ),
                    ]),
        ),
        meField(
          'Used in',
          uses.isEmpty
              ? Text('Not used in an exercise, program, meal plan or form yet.', style: AppText.s(12.5, W.w5, color: AppColors.muted))
              : _LinkList([
                  for (final u in uses)
                    _LinkRow(
                      lead: SizedBox(
                        width: 84,
                        child: Text('${u['type']}'.toUpperCase(), style: AppText.s(11.5, W.w7, color: AppColors.muted, ls: .46)),
                      ),
                      title: '${u['name']}',
                      onTap: () => Navigator.of(context).pop('go:/${u['type'] == 'program' ? 'programs' : 'exercises'}/${u['id']}'),
                    ),
                ]),
        ),
        meField('Opened by clients', _Stats([
          ('${st['opened'] ?? 0}', 'opened'),
          ('${st['finished'] ?? 0}', switch (kind) { 'video' => 'watched to the end', 'image' => 'viewed', 'pdf' => 'opened to the last page', _ => 'read to the end' }),
          (st['finish_rate'] == null ? '–' : '${st['finish_rate']}%', 'finish rate'),
        ])),
      ]),
    );
  }
}

/// "Uploaded 14 Sep · 27 MB · 1080p" (video), "6 pages · 1.2 MB · uploaded 14 Sep" (PDF), "1.2 MB · uploaded 14 Sep".
String _fileSub(Map d) {
  final size = (d['file_size'] as num?) == null ? null : ctSize(d['file_size'] as num);
  final when = ctDm(d['created_at']);
  return switch ('${d['kind']}') {
    'video' => ['Uploaded $when', ?size, if ('${d['resolution'] ?? ''}'.isNotEmpty) '${d['resolution']}'].join(' · '),
    'pdf' => ['${d['length_label']}', ?size, 'uploaded $when'].join(' · '),
    _ => [?size, 'uploaded $when'].join(' · '),
  };
}

/// `.dr-kpis` in a drawer: four cells with lines between and a line under.
class _Kpis extends StatelessWidget {
  const _Kpis(this.kv);
  final List<(String, String)> kv;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.only(bottom: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, (k, v)) in kv.indexed)
              Expanded(
                child: Container(
                  padding: EdgeInsets.fromLTRB(i == 0 ? 0 : 12, 2, 8, 2),
                  decoration: BoxDecoration(border: i == 0 ? null : const Border(left: BorderSide(color: AppColors.line))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                    Text(k, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
                    Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(14, W.w8)),
                  ]),
                ),
              ),
          ]),
        ),
      );
}

/// `.fm-stats`: three numbers in one box.
class _Stats extends StatelessWidget {
  const _Stats(this.items);
  final List<(String, String)> items;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.line)),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, (v, k)) in items.indexed)
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: context.isPhone ? 10 : 12, vertical: 10),
                  decoration: BoxDecoration(border: i == 0 ? null : const Border(left: BorderSide(color: AppColors.line))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                    Text(v, style: AppText.s(context.isPhone ? 16 : 18, W.w8)),
                    Text(k, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
                  ]),
                ),
              ),
          ]),
        ),
      );
}

/// `.ct-file`: icon, file name, grey line, and a green badge or a button on the right.
class _FileRow extends StatelessWidget {
  const _FileRow({required this.icon, required this.name, required this.sub, this.badge, this.action, this.onTap});
  final AppIconData icon;
  final String name, sub;
  final String? badge;
  final Widget? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(borderRadius: AppRadius.all(10), border: Border.all(color: h && onTap != null ? AppColors.line2 : AppColors.line)),
          child: Row(spacing: 10, children: [
            AppIcon(icon, size: 18, color: AppColors.muted),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w7)),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted)),
              ]),
            ),
            if (badge != null) AppBadge(badge!, tone: Tone.ok, plain: true),
            ?action,
          ]),
        ),
      );
}

/// `.nu-ulist`: rows in one box with lines between.
class _LinkList extends StatelessWidget {
  const _LinkList(this.rows);
  final List<Widget> rows;
  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, r) in rows.indexed)
            Container(decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))), child: r),
        ]),
      );
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.lead, required this.title, this.sub, required this.onTap});
  final Widget lead;
  final String title;
  final String? sub;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          color: h ? AppColors.outlineHover : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(spacing: 10, children: [
            lead,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7, color: h ? AppColors.accentText : AppColors.text)),
                if (sub != null) Text(sub!, style: AppText.s(12, W.w5, color: AppColors.muted)),
              ]),
            ),
            const AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.muted),
          ]),
        ),
      );
}

// ─────────────────────────────── New / Edit content

const _ext = {
  'video': ['mp4', 'mov', 'm4v', 'webm'],
  'pdf': ['pdf'],
  'image': ['jpg', 'jpeg', 'png', 'webp'],
};
const _limitMb = {'video': 500, 'pdf': 25, 'image': 10};
const _readTimes = [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30];

class _Ed extends ChangeNotifier {
  _Ed({this.old, required this.cats, String? cat, String? kind, required this.canEveryone}) {
    final o = old;
    this.kind = o != null ? '${o['kind']}' : (ctEditKinds.any((k) => k.$1 == kind) ? kind! : 'video');
    catId = o != null ? (o['category'] == null ? null : '${o['category']}') : (cat ?? (cats.isEmpty ? null : '${cats.first['id']}'));
    if (o != null) {
      title.text = '${o['title'] ?? ''}';
      desc.text = '${o['description'] ?? ''}';
      body.text = '${o['body'] ?? ''}';
      yt.text = '${o['youtube_url'] ?? ''}';
      src = '${o['file_name'] ?? ''}'.isEmpty && yt.text.isNotEmpty ? 'yt' : 'up';
      readMin = (o['read_minutes'] as num?)?.toInt() ?? 3;
      everyone = o['share_everyone'] == true;
      final f = '${o['frame'] ?? ''}';
      frame = f.isEmpty ? null : f;
    }
    _snap = _sig;
    if (kIsWeb) _unwatch = watchDrops(onOver: (v) => _set(() => dragging = v), onFile: take);
    _loadFrames();
  }

  final Map? old;
  final List<Map> cats;
  final bool canEveryone;
  late String kind;
  String src = 'up';
  String? catId, frame;
  final title = TextEditingController(), desc = TextEditingController(), body = TextEditingController(), yt = TextEditingController();
  int readMin = 3;
  bool everyone = false, dragging = false, saving = false;
  (String, Uint8List)? file;
  String? titleErr, fileErr, ytErr, bodyErr, formErr;
  List<Map> frames = const [];
  bool framesLoading = false;
  String? _framesFor;
  Timer? _ytWait;
  late String _snap;
  void Function() _unwatch = () {};

  bool get isNew => old == null;
  String get _sig => [kind, src, catId, title.text.trim(), desc.text.trim(), body.text.trim(), yt.text.trim(), readMin, everyone, frame].join('|');
  bool get dirty => file != null || _sig != _snap;
  bool get oldFile => !isNew && '${old!['file_name'] ?? ''}'.isNotEmpty && old!['kind'] == kind;
  String? get catName => cats.where((c) => '${c['id']}' == catId).map((c) => '${c['name']}').firstOrNull;

  void _set(VoidCallback f) {
    f();
    notifyListeners();
  }

  void changed() => notifyListeners();

  @override
  void dispose() {
    _unwatch();
    _ytWait?.cancel();
    for (final c in [title, desc, body, yt]) {
      c.dispose();
    }
    super.dispose();
  }

  void setKind(String k) => _set(() {
        if (k == kind) return;
        kind = k;
        file = null;
        fileErr = null;
        _loadFrames();
      });

  void setSrc(String s) => _set(() {
        src = s;
        fileErr = ytErr = null;
        _loadFrames();
      });

  void ytChanged(String _) {
    if (ytErr != null) _set(() => ytErr = null);
    _ytWait?.cancel();
    _ytWait = Timer(const Duration(milliseconds: 500), _loadFrames);
  }

  Future<void> pick() async {
    final ext = _ext[kind];
    if (ext == null) return;
    final r = await pickDocument(ext: ext);
    if (r != null) take(r);
  }

  Future<void> drop(DropDoneDetails d) async {
    _set(() => dragging = false);
    final f = d.files.whereType<DropItemFile>().firstOrNull;
    if (f == null) return;
    take((f.name, await f.readAsBytes()));
  }

  void take((String, Uint8List) r) {
    final allowed = _ext[kind];
    if (allowed == null) return; // an article has no file
    final ext = r.$1.split('.').last.toLowerCase();
    final mb = _limitMb[kind]!;
    _set(() {
      if (!allowed.contains(ext)) {
        fileErr = switch (kind) { 'video' => 'Upload an MP4 or MOV video.', 'pdf' => 'Upload a PDF.', _ => 'Upload a JPG, PNG or WebP image.' };
      } else if (r.$2.length > mb * 1024 * 1024) {
        fileErr = 'This file is over $mb MB. Pick a smaller one.';
      } else {
        file = r;
        fileErr = null;
        if (kind == 'video') src = 'up';
        if (title.text.trim().isEmpty) title.text = r.$1.replaceFirst(RegExp(r'\.[^.]+$'), '').replaceAll(RegExp(r'[-_]+'), ' ').trim();
        _loadFrames();
      }
    });
  }

  /// Stills to pick the cover from: a saved upload's frames, or a YouTube link's. A new file has none until saved.
  Future<void> _loadFrames() async {
    final link = yt.text.trim();
    final Map<String, dynamic>? q = kind != 'video'
        ? null
        : src == 'yt'
            ? (link.contains('youtu') ? {'url': link} : null)
            : (file == null && oldFile ? {'video': '${old!['id']}'} : null);
    final sig = q?.toString();
    if (sig == _framesFor) return;
    _framesFor = sig;
    if (q == null) {
      _set(() => frames = const []);
      return;
    }
    _set(() => framesLoading = true);
    try {
      final r = await Services.api.get<Map>('exercises/frames/', query: q);
      if (_framesFor != sig) return;
      _set(() => frames = [for (final f in (r['frames'] as List? ?? const [])) f as Map]);
    } on ApiError {
      if (_framesFor == sig) _set(() => frames = const []);
    }
    if (_framesFor == sig) _set(() => framesLoading = false);
  }

  Future<Map?> submit() async {
    final t = title.text.trim();
    final link = yt.text.trim();
    _set(() {
      titleErr = t.length < 2 ? 'Enter a title.' : null;
      ytErr = kind == 'video' && src == 'yt' && !(link.contains('youtube.com/') || link.contains('youtu.be/')) ? 'Paste a YouTube link, e.g. https://youtu.be/…' : null;
      fileErr = switch (kind) {
        'video' when src == 'up' && file == null && !oldFile => 'Upload a video or paste a YouTube link.',
        'pdf' || 'image' when file == null && !oldFile => 'Upload the file.',
        _ => fileErr,
      };
      bodyErr = kind == 'article' && body.text.trim().isEmpty ? 'Write what clients read.' : null;
      formErr = null;
    });
    if ((titleErr ?? ytErr ?? fileErr ?? bodyErr) != null) return null;
    _set(() => saving = true);
    final f = file;
    final data = <String, dynamic>{
      'kind': kind,
      'title': t,
      'category': catId ?? '',
      if (kind == 'video') 'youtube_url': src == 'yt' ? link : '',
      if (kind == 'video') 'frame': frame ?? '',
      if (kind == 'article') 'body': body.text.trim(),
      if (kind == 'article') 'read_minutes': readMin,
      if (kind == 'pdf' || kind == 'image') 'description': desc.text.trim(),
      if (canEveryone) 'share_everyone': everyone,
      if (f != null) 'file': MultipartFile.fromBytes(f.$2, filename: f.$1),
    };
    try {
      final fd = FormData.fromMap(data);
      final r = isNew ? await Services.api.post<Map>('content/', fd) : await Services.api.patch<Map>('content/${old!['id']}/', fd);
      _snap = _sig;
      file = null;
      return r;
    } on ApiError catch (e) {
      _set(() {
        saving = false;
        titleErr = e.field('title');
        fileErr = e.field('file');
        ytErr = e.field('youtube_url');
        bodyErr = e.field('body');
        formErr = (titleErr ?? fileErr ?? ytErr ?? bodyErr) == null ? e.message : null;
      });
      return null;
    }
  }
}

/// New content / Edit content drawer. Gives back the saved item. Closing with changes asks to discard them.
Future<Map?> showContentEditor(BuildContext context,
    {Map? item, required List<Map> cats, String? cat, String? kind, required bool canEveryone}) async {
  final e = _Ed(old: item, cats: cats, cat: cat, kind: kind, canEveryone: canEveryone);
  Map? saved;
  while (true) {
    if (!context.mounted) break;
    saved = await showAppDrawer<Map>(
      context,
      title: e.isNew ? 'New content' : 'Edit content',
      sub: e.isNew ? 'Video, article, PDF or image' : '${item!['title']}',
      icon: e.isNew ? AppIcons.importFile : AppIcons.edit,
      builder: (ctx) => ListenableBuilder(listenable: e, builder: (ctx, _) => _EdBody(e)),
      footer: (ctx) => [
        _fill(ctx, ListenableBuilder(
          listenable: e,
          builder: (_, _) {
            final note = Text(e.isNew ? (e.catName == null ? 'Not filed under a category' : 'Saved to ${e.catName}') : 'Changes reach everyone who sees it',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted));
            final cancel = AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop());
            final save = AppButton.primary(e.isNew ? 'Add to library' : 'Save changes',
                icon: AppIcons.check, expand: ctx.isPhone, loading: e.saving, onPressed: () async {
              final r = await e.submit();
              if (r != null && ctx.mounted) Navigator.of(ctx).pop(r);
            });
            if (ctx.isPhone) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                note,
                Row(spacing: 8, children: [Expanded(child: cancel), Expanded(child: save)]),
              ]);
            }
            return Row(spacing: 8, children: [Expanded(child: note), cancel, save]);
          },
        )),
      ],
    );
    if (!context.mounted) break;
    if (saved != null || !e.dirty) break;
    final drop = await confirmAction(context,
        title: 'Leave without saving?', body: 'Your changes to ${e.title.text.trim().isEmpty ? 'this content' : e.title.text.trim()} are not saved.', confirm: 'Discard', danger: true, icon: AppIcons.alert);
    if (drop) break;
  }
  disposeLater([e]);
  return saved;
}

/// A drawer footer is a Row on wide screens (fill it) and a Column on a phone.
Widget _fill(BuildContext ctx, Widget w) => ctx.isPhone ? w : Expanded(child: w);

class _EdBody extends StatelessWidget {
  const _EdBody(this.e);
  final _Ed e;

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final kind = e.kind;
    return Padding(
      padding: EdgeInsets.only(top: phone ? 0 : 14, bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
        if (e.isNew)
          meField('Type', SegmentedTabs<String>(
            items: [for (final (k, l) in ctEditKinds) TabItem(k, l)],
            value: kind,
            expand: true,
            onChanged: e.setKind,
          )),
        meField(
          'Title',
          AppTextField(
            controller: e.title,
            placeholder: 'e.g. Romanian deadlift · side view',
            formatters: [LengthLimitingTextInputFormatter(140)],
            onChanged: (_) {
              if (e.titleErr != null) e._set(() => e.titleErr = null);
              e.changed();
            },
          ),
          req: true,
          error: e.titleErr,
        ),
        meField(
          'Category',
          AppSelect(e.catName ?? 'No category', entries: [
            for (final c in e.cats) MenuEntry('${c['name']}', selected: '${c['id']}' == e.catId, onTap: () => e._set(() => e.catId = '${c['id']}')),
            MenuEntry('No category', selected: e.catId == null, onTap: () => e._set(() => e.catId = null)),
          ]),
        ),
        if (kind == 'video') ..._video(context),
        if (kind == 'pdf' || kind == 'image') ...[
          meField(kind == 'pdf' ? 'PDF file' : 'Image', _fileArea(context)),
          meField(
            null,
            AppTextField(
              controller: e.desc,
              placeholder: 'One or two lines clients see above the file',
              maxLines: 3,
              minLines: 2,
              formatters: [LengthLimitingTextInputFormatter(300)],
              onChanged: (_) => e.changed(),
            ),
          ).withLabel('Short description', optional: true),
        ],
        if (kind == 'article') ...[
          meField(
            'Text',
            AppTextField(
              controller: e.body,
              placeholder: 'What clients read. Leave an empty line between paragraphs.',
              maxLines: 12,
              minLines: 6,
              formatters: [LengthLimitingTextInputFormatter(50000)],
              onChanged: (_) {
                if (e.bodyErr != null) e._set(() => e.bodyErr = null);
                e.changed();
              },
            ),
            error: e.bodyErr,
          ),
          meField(
            'Read time',
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 160,
                child: AppSelect('${e.readMin} min read', entries: [
                  for (final m in _readTimes) MenuEntry('$m min read', selected: m == e.readMin, onTap: () => e._set(() => e.readMin = m)),
                ]),
              ),
            ),
          ),
        ],
        if (e.canEveryone)
          meField(
            'Who can see this',
            DrSwitch(
              title: 'Everyone',
              sub: 'All current and future clients. Untick to pick clients after saving.',
              value: e.everyone,
              onChanged: (v) => e._set(() => e.everyone = v),
            ),
          ),
        if (e.formErr != null) Text(e.formErr!, style: AppText.s(12.5, W.w6, color: AppColors.badText)),
      ]),
    );
  }

  List<Widget> _video(BuildContext context) => [
        meField(
          'Video',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
            SegmentedTabs<String>(
              items: const [TabItem('up', 'Upload file'), TabItem('yt', 'YouTube link')],
              value: e.src,
              expand: true,
              onChanged: e.setSrc,
            ),
            if (e.src == 'up') _fileArea(context),
          ]),
        ),
        if (e.src == 'yt')
          meField(
            'YouTube link',
            AppTextField(controller: e.yt, placeholder: 'https://youtu.be/…', keyboard: TextInputType.url, onChanged: e.ytChanged),
            hint: 'Plays inside the app. Clients do not leave it.',
            error: e.ytErr,
          ),
        meField('Cover image', _frames(context), hint: 'A frame from the video. Clients see it on the card.'),
      ];

  /// `.ct-drop` when nothing is picked, `.ct-file` with Replace when a file is (new or already saved).
  Widget _fileArea(BuildContext context) {
    final f = e.file;
    final canDrop = kIsWeb || !(defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    final Widget box;
    if (f != null || e.oldFile) {
      box = _FileRow(
        icon: ctIcon(e.kind),
        name: f?.$1 ?? '${e.old!['file_name']}',
        sub: f != null ? '${ctSize(f.$2.length)} · new, saves with the item' : 'Uploaded ${ctDm(e.old!['created_at'])}${e.old!['file_size'] == null ? '' : ' · ${ctSize(e.old!['file_size'] as num)}'}',
        action: AppButton('Replace', size: BtnSize.sm, onPressed: e.pick),
      );
    } else {
      final (t, s) = switch (e.kind) {
        'video' => (canDrop ? 'Drop a video here or click to upload' : 'Tap to upload a video', 'MP4 or MOV, up to 500 MB. It plays inside the app.'),
        'pdf' => (canDrop ? 'Drop a PDF here or click to upload' : 'Tap to upload a PDF', 'PDF up to 25 MB. Clients open it inside the app.'),
        _ => (canDrop ? 'Drop an image here or click to upload' : 'Tap to upload an image', 'JPG, PNG or WebP, up to 10 MB. Clients can zoom in.'),
      };
      box = Hover(
        onTap: e.pick,
        builder: (_, h, _) => CustomPaint(
          foregroundPainter: DashedBox(color: e.fileErr != null ? AppColors.badText : (e.dragging || h ? AppColors.accent : AppColors.line2), radius: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
            decoration: BoxDecoration(color: e.dragging ? AppColors.accentSoft : (h ? AppColors.hover : null), borderRadius: AppRadius.all(12)),
            child: Column(spacing: 4, children: [
              const AppIcon(AppIcons.importFile, size: 24, color: AppColors.accent),
              Text(e.dragging ? 'Drop it to add the file' : t, textAlign: TextAlign.center, style: AppText.s(13.5, W.w7)),
              Text(s, textAlign: TextAlign.center, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
            ]),
          ),
        ),
      );
    }
    final zone = kIsWeb
        ? box
        : DropTarget(
            onDragEntered: (_) => e._set(() => e.dragging = true),
            onDragExited: (_) => e._set(() => e.dragging = false),
            onDragDone: e.drop,
            child: box,
          );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      zone,
      if (e.fileErr != null) Text(e.fileErr!, style: AppText.s(12, W.w6, color: AppColors.badText)),
    ]);
  }

  /// `.ct-frames`: four stills in a row; the picked one has a blue edge. Tinted tiles while they load.
  Widget _frames(BuildContext context) {
    if (e.frames.isEmpty && !e.framesLoading) {
      final msg = e.src == 'yt'
          ? (e.yt.text.trim().isEmpty ? 'Paste the link first, then choose a frame from it.' : 'No frames could be taken from this link.')
          : (e.file != null ? 'You can pick a frame once the video is saved. Until then clients see its first frame.' : (e.oldFile ? 'No frames could be taken from this video.' : 'Upload a video first, then choose a frame from it.'));
      return Text(msg, style: AppText.s(12.5, W.w5, color: AppColors.muted));
    }
    final list = e.framesLoading ? <Map>[for (var i = 0; i < 4; i++) const {}] : e.frames.take(4).toList();
    final on = e.frame ?? (list.isNotEmpty && list.first.isNotEmpty ? '${list.first['key']}' : null);
    return Row(spacing: 8, children: [
      for (final (i, f) in list.indexed)
        Expanded(
          child: Hover(
            onTap: f.isEmpty ? null : () => e._set(() => e.frame = '${f['key']}'),
            builder: (_, h, _) {
              final picked = f.isNotEmpty && on == f['key'];
              final (a, b) = AppColors.mediaTiles[i % 4];
              final tile = DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b])));
              final url = f['url'] as String?;
              return AspectRatio(
                aspectRatio: 16 / 10,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.all(8),
                    border: Border.all(color: picked ? AppColors.accent : (h && f.isNotEmpty ? AppColors.line2 : Colors.transparent), width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: AppRadius.all(6),
                    child: Stack(fit: StackFit.expand, children: [
                      url == null ? tile : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => tile),
                      if (e.framesLoading)
                        const Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.mediaFg))),
                      if (f.isNotEmpty)
                        Positioned(
                          left: 4,
                          bottom: 4,
                          child: Container(
                            height: 18,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: AppColors.playBadge, borderRadius: AppRadius.all(9)),
                            child: Text('${f['label']}', style: AppText.s(10, W.w7, color: AppColors.white, h: 1)),
                          ),
                        ),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
    ]);
  }
}

extension on Widget {
  /// A [meField] with no label of its own, given "Short description  optional" on top.
  Widget withLabel(String label, {bool optional = false}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        Text.rich(TextSpan(text: label, style: AppText.label, children: [
          if (optional) TextSpan(text: '  optional', style: AppText.s(12, W.w5, color: AppColors.muted)),
        ])),
        this,
      ]);
}

// ─────────────────────────────── Assign to clients

/// Everyone (Vimal only) or a client list; gives back {everyone, clients} after saving.
Future<void> showContentAssign(BuildContext context, Map item, {required bool canEveryone, VoidCallback? onSaved}) async {
  final id = '${item['id']}';
  final picked = ValueNotifier<Set<String>?>(null);
  final all = ValueNotifier<bool>(false);
  final q = ValueNotifier('');
  var before = <String>{};
  final data = Services.api.get<Map>('content/$id/assign/').then((r) {
    final list = [for (final c in (r['clients'] as List? ?? const [])) c as Map];
    before = {for (final c in list) if (c['has_it'] == true) '${c['id']}'};
    all.value = r['everyone'] == true;
    picked.value = {...before};
    return list;
  });
  var saving = false;
  final r = await showAppModal<(bool, int)>(
    context,
    title: 'Assign to clients',
    body: '${item['title']}',
    icon: AppIcons.assign,
    width: 480,
    content: (ctx) => FutureBuilder<List<Map>>(
      future: data,
      builder: (ctx, s) {
        if (s.hasError) return const EmptyState('Could not load your clients');
        if (!s.hasData) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)));
        final list = s.data!;
        return ListenableBuilder(
          listenable: Listenable.merge([picked, q, all]),
          builder: (ctx, _) {
            final rows = list.where((c) => q.value.isEmpty || '${c['full_name']}'.toLowerCase().contains(q.value)).toList();
            final every = all.value;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
              if (canEveryone)
                DrSwitch(title: 'Everyone', sub: 'All current and future clients', value: every, onChanged: (v) => all.value = v)
              else if (every)
                Text('Vimal shares this with every client. You can still pick clients here.', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
              if (canEveryone && every)
                Text('Untick "Everyone" to pick clients one by one.', style: AppText.s(12.5, W.w5, color: AppColors.muted))
              else ...[
                AppSearchField(placeholder: 'Search clients', icon: AppIcons.search, onChanged: (v) => q.value = v.trim().toLowerCase()),
                if (list.isEmpty)
                  Text('You have no clients yet.', style: AppText.s(13, W.w5, color: AppColors.muted))
                else if (rows.isEmpty)
                  Text('No client matches.', style: AppText.s(13, W.w5, color: AppColors.muted))
                else
                  DrScrollList(rows: 6, [
                    for (final c in rows)
                      () {
                        final cid = '${c['id']}', sel = picked.value!.contains(cid);
                        return DrOpt(
                          title: '${c['full_name']}',
                          sub: before.contains(cid) ? 'Has it now' : 'Does not have it',
                          multi: true,
                          on: sel,
                          thumb: AppAvatar('${c['full_name']}', size: 28, initials: '${c['initials'] ?? ''}', colors: AppColors.avatarCode('${c['avatar_color'] ?? 'c1'}')),
                          onTap: () => picked.value = sel ? ({...picked.value!}..remove(cid)) : {...picked.value!, cid},
                        );
                      }(),
                  ]),
              ],
            ]);
          },
        );
      },
    ),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      StatefulBuilder(
        builder: (bctx, set) => ListenableBuilder(
          listenable: Listenable.merge([picked, all]),
          builder: (_, _) {
            final p = picked.value;
            final every = all.value && canEveryone;
            final n = p?.length ?? 0;
            return AppButton.primary(
              every ? 'Share with everyone' : (n == 0 ? 'Save, not assigned' : 'Assign to ${plural(n, 'client')}'),
              icon: AppIcons.check,
              expand: ctx.isPhone,
              loading: saving,
              onPressed: p == null
                  ? null
                  : () async {
                      set(() => saving = true);
                      try {
                        await Services.api.post<Map>('content/$id/assign/', {'everyone': all.value, 'clients': every ? before.toList() : p.toList()});
                        if (ctx.mounted) Navigator.of(ctx).pop((every, n));
                      } on ApiError catch (err) {
                        set(() => saving = false);
                        if (ctx.mounted) showToast(ctx, 'Could not save it', sub: err.message, kind: ToastKind.err);
                      }
                    },
            );
          },
        ),
      ),
    ],
  );
  disposeLater([picked, all, q]);
  if (r == null || !context.mounted) return;
  final (every, n) = r;
  showToast(context, every ? 'Shared with everyone' : (n > 0 ? 'Assigned to ${plural(n, 'client')}' : 'No longer assigned'), sub: '${item['title']}', kind: ToastKind.ok);
  onSaved?.call();
}

// ─────────────────────────────── New category · Delete

/// New category modal; gives back the new category.
Future<Map?> showNewCategory(BuildContext context) async {
  final name = await showNameModal(context,
      title: 'New category', sub: 'A folder to file content under', label: 'Category name', placeholder: 'e.g. Mobility', button: 'Create category', icon: AppIcons.plus);
  if (name == null || !context.mounted) return null;
  try {
    final c = await Services.api.post<Map>('content-categories/', {'name': name});
    if (context.mounted) showToast(context, 'Category created', sub: '${c['name']}', kind: ToastKind.ok);
    return c;
  } on ApiError catch (e) {
    if (context.mounted) showToast(context, 'Could not create it', sub: e.field('name') ?? e.message, kind: ToastKind.err);
    return null;
  }
}

/// "Delete this content?" naming where it is used; then a toast with Undo. True when deleted.
Future<bool> deleteContent(BuildContext context, Map item, {required VoidCallback onUndo}) async {
  final uses = [for (final u in (item['uses'] as List? ?? const [])) u as Map];
  final where = uses.map((u) => '${u['type']} ${u['name']}').join(', ');
  final ok = await confirmAction(
    context,
    title: 'Delete this content?',
    body: '${item['title']} is removed for good${uses.isEmpty ? '.' : '. It is used in $where, which will show no ${item['kind'] == 'video' ? 'video' : 'link'} after this.'}',
    confirm: 'Delete',
    danger: true,
    icon: AppIcons.trash,
  );
  if (!ok || !context.mounted) return false;
  try {
    await Services.api.delete('content/${item['id']}/');
  } on ApiError catch (e) {
    if (context.mounted) showToast(context, 'Could not delete it', sub: e.message, kind: ToastKind.err);
    return false;
  }
  if (context.mounted) {
    showToast(context, 'Content deleted', sub: '${item['title']}', action: 'Undo', onAction: () async {
      try {
        await Services.api.post('content/${item['id']}/restore/');
        onUndo();
      } on ApiError {
        // the toast is gone by now; the item stays deleted
      }
    });
  }
  return true;
}
