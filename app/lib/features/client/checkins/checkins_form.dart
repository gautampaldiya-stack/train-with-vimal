import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/shell/back_nav.dart';
import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tooltip.dart';
import '../home/home_model.dart' show clock, dayShort;
import 'checkins_model.dart';
import 'checkins_parts.dart';
import 'checkins_weekly.dart' show chSmall;

/// A form the coach sent (boards ClientForm / ClientFormWeb, `isForm`): one question a page, a review page,
/// then "Sent to Aman". `/checkins/forms/<request id>`. Answers are kept as a draft on the phone until sent.
class ClientFormScreen extends StatefulWidget {
  const ClientFormScreen({super.key, required this.id});
  final String id;
  @override
  State<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends State<ClientFormScreen> {
  Map<String, dynamic>? _j;
  ApiError? _error;
  CkForm? _f;
  final _v = <String, Object?>{};
  final _photos = <String, Map<String, String>>{}; // question id → slot key → data URL
  final _texts = <int, TextEditingController>{};
  int _step = 0;
  bool _busy = false;

  /// Sent now (id null while it waits offline) or before: {id, sent_at, answers}.
  Map<String, dynamic>? _sent;

  String get _id => widget.id;
  List<CkQ> get qs => _f!.questions;
  String get coach => '${_j?['from'] ?? 'Your coach'}';
  String get name => '${_j?['name'] ?? 'Form'}';
  DateTime? get _due => DateTime.tryParse('${_j?['due_at']}')?.toLocal();
  String get _cacheKey => 'me/forms/$_id';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final t in _texts.values) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final cached = await Services.cache.read(_cacheKey);
    if (cached is Map && _j == null) await _take(cached.cast<String, dynamic>());
    try {
      final j = await Services.api.get<Map<String, dynamic>>('me/forms/$_id/');
      await Services.cache.write(_cacheKey, j);
      await _take(j);
      _error = null;
    } on ApiError catch (e) {
      _error = e;
    }
    if (mounted) setState(() {});
  }

  Future<void> _take(Map<String, dynamic> j) async {
    final first = _f == null;
    _j = j;
    _f = CkForm(j['form'] as Map<String, dynamic>? ?? {});
    _sent = (j['submission'] as Map?)?.cast<String, dynamic>() ?? (_sent?['id'] == null ? _sent : null);
    if (!first) return;
    final dr = await formDraft(_id);
    if (dr != null) {
      _v.addAll((dr['answers'] as Map? ?? {}).cast<String, Object?>());
      for (final e in (dr['photos'] as Map? ?? {}).entries) {
        _photos[e.key as String] = (e.value as Map).cast<String, String>();
      }
      _step = ((dr['step'] as num?)?.toInt() ?? 0).clamp(0, qs.length);
    }
    for (final q in qs) {
      if (q.type == 'short' || q.type == 'long' || q.type == 'number') _texts[q.id] = TextEditingController(text: '${_v['${q.id}'] ?? ''}');
    }
  }

  // ─────────────────────────────── Answers

  List<String> _slotKeys(CkQ q) => [for (final n in q.slots) n.toLowerCase()];

  String? _ans(CkQ q) {
    if (q.type == 'photo') {
      final n = _photos['${q.id}']?.length ?? 0;
      return n == 0 ? null : (n == 1 ? '1 photo' : '$n photos');
    }
    return q.show(_v['${q.id}']);
  }

  int get _answered => qs.where((q) => _ans(q) != null).length;

  void _save() => saveFormDraft(_id, {'answers': _v, 'photos': _photos, 'step': _step, 'answered': _answered});

  void _set(CkQ q, Object? v) {
    setState(() => _v['${q.id}'] = v);
    _save();
  }

  void _go(int n) {
    setState(() => _step = n);
    _save();
  }

  void _exit() {
    if (_sent == null && _answered > 0) {
      _save();
      showToast(
        context,
        'Draft saved',
        sub: '$_answered of ${qs.length} answered${_due == null ? '' : ' · finish by ${dayShort(_due!)}'}',
        kind: ToastKind.info,
      );
    }
    context.go('/checkins');
  }

  bool _badNumber(CkQ q) => q.type == 'number' && _v['${q.id}'] != null && double.tryParse('${_v['${q.id}']}'.replaceAll(',', '.')) == null;

  void _next() {
    if (_step >= qs.length) {
      _send();
      return;
    }
    final q = qs[_step];
    if (q.required && _ans(q) == null) {
      showToast(context, 'Pick an answer to continue', sub: 'This question is required', kind: ToastKind.warn);
      return;
    }
    if (_badNumber(q)) {
      showToast(context, 'Enter a number', sub: 'Only digits, like 72', kind: ToastKind.warn);
      return;
    }
    _go(_step + 1);
  }

  Future<void> _send() async {
    final miss = [
      for (final q in qs)
        if (q.required && _ans(q) == null) q,
    ];
    if (miss.isNotEmpty) {
      showToast(context, 'Answer “${miss.first.text}” first', sub: 'Only the questions marked Optional can be skipped', kind: ToastKind.warn);
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    final answers = {
      for (final q in qs)
        if (q.type != 'photo' && _v['${q.id}'] != null && _v['${q.id}'] != '')
          '${q.id}': q.type == 'number' ? double.parse('${_v['${q.id}']}'.replaceAll(',', '.')) : _v['${q.id}'],
    };
    final photos = {
      for (final e in _photos.entries)
        if (e.value.isNotEmpty) e.key: Map.of(e.value),
    };
    try {
      final r = await Services.outbox.enqueue('POST', 'me/submissions/', {
        'request': _id,
        'answers': answers,
        if (photos.isNotEmpty) 'photos': photos,
      }, tag: 'form');
      await saveFormDraft(_id, null);
      if (!mounted) return;
      final now = DateTime.now();
      setState(() => _sent = {'id': r is Map ? r['id'] : null, 'sent_at': now.toIso8601String(), 'answers': answers});
      final off = r == null;
      showToast(
        context,
        '$name sent',
        sub: off ? 'Saved on this phone · it goes to $coach when you are online' : '$coach reads every answer',
        kind: ToastKind.ok,
        action: off ? null : 'Undo',
        onAction: off ? null : () => _undo('${r['id']}'),
      );
    } catch (e) {
      if (mounted) showToast(context, 'Could not send it', sub: '$e', kind: ToastKind.err);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo(String subId) async {
    final r = await Services.outbox.enqueue('DELETE', 'me/submissions/$subId/', {}, tag: 'form:undo');
    if (!mounted) return;
    setState(() => _sent = null);
    _save();
    if (r != null) _load();
  }

  // ─────────────────────────────── Build

  /// The phone's back button = the page's own back: saves a draft, then Check-ins (Phase 4).
  @override
  Widget build(BuildContext context) => BackIntercept(
    onBack: () {
      if (_f == null) return false;
      _exit();
      return true;
    },
    child: Builder(builder: _page),
  );

  Widget _page(BuildContext context) {
    if (_f == null) {
      return Center(
        child: _error == null
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 10,
                  children: [
                    Text(_error!.offline ? 'You are offline' : 'Could not open this form', style: AppText.s(15, W.w7)),
                    Text(
                      _error!.offline ? 'Connect to the internet to open it' : _error!.message,
                      textAlign: TextAlign.center,
                      style: AppText.s(13, W.w4, color: AppColors.muted),
                    ),
                    CaButton('Back to check-ins', kind: CaBtnKind.out, expand: false, onPressed: () => context.go('/checkins')),
                  ],
                ),
              ),
      );
    }
    final web = !context.isPhone;
    final sent = _sent;
    return CkPage(
      web: web,
      header: [
        CkTop(
          title: name,
          sub: 'From $coach${_due == null ? '' : ' · due ${dayShort(_due!)}'}',
          onBack: _exit,
          backLabel: sent == null ? 'Save and exit' : 'Back to check-ins',
        ),
        if (sent == null && qs.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 6,
            children: [
              Text(
                _step < qs.length ? 'Question ${_step + 1} of ${qs.length}' : 'Review · all ${qs.length} questions',
                style: AppText.s(12, W.w7, color: AppColors.muted),
              ),
              CkBar((_step + 1).clamp(1, qs.length) / qs.length),
            ],
          ),
      ],
      children: sent != null ? [_done(sent)] : [_card(), _nav()],
    );
  }

  Widget _card() {
    final review = _step >= qs.length;
    final q = review ? null : qs[_step];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(review ? 'Check your answers' : '${_step + 1}. ${q!.text}', style: AppText.s(17, W.w8, h: 1.3)),
                  if (q != null && !q.required)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(5)),
                      child: Text('Optional', style: AppText.s(10.5, W.w7, color: AppColors.text2)),
                    ),
                ],
              ),
              if (review || q!.help.isNotEmpty)
                Text(review ? 'Tap Edit to change one. $coach gets it as soon as you send.' : q!.help, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
            ],
          ),
          if (review) _review() else ..._answer(q!),
        ],
      ),
    );
  }

  List<Widget> _answer(CkQ q) {
    final v = _v['${q.id}'];
    if (q.type == 'scale') return [CkScale(labels: q.labels, value: q.scaleOf(v), onPick: (n) => _set(q, n), lg: true)];
    if (q.type == 'multiple') {
      final sel = [...((v as List?) ?? const [])];
      return [
        Column(
          children: [
            for (final (i, o) in q.options.indexed)
              _Check(
                o,
                on: sel.contains(o),
                first: i == 0,
                onTap: () {
                  // "None" / "None of these" clears the others, and the others clear it.
                  bool none(Object? x) => '$x'.toLowerCase().startsWith('none');
                  if (sel.contains(o)) {
                    sel.remove(o);
                  } else if (none(o)) {
                    sel
                      ..clear()
                      ..add(o);
                  } else {
                    sel
                      ..removeWhere(none)
                      ..add(o);
                  }
                  _set(q, sel.isEmpty ? null : sel);
                },
              ),
          ],
        ),
      ];
    }
    if (q.isChoice) {
      final cur = v == null ? null : (q.type == 'yes_no' ? ((v as bool) ? 'Yes' : 'No') : '$v');
      return [
        Column(
          spacing: 8,
          children: [
            for (final o in q.options) _Opt(o, on: cur == o, onTap: () => _set(q, q.type == 'yes_no' ? o == 'Yes' : o)),
          ],
        ),
      ];
    }
    if (q.type == 'photo') return _photosQ(q);
    final t = _texts[q.id] ??= TextEditingController(text: '${v ?? ''}');
    void changed() {
      _v['${q.id}'] = t.text.trim().isEmpty ? null : t.text.trim();
      setState(() {});
      _save();
    }

    return [
      CkInput(
        controller: t,
        hint: q.type == 'number' ? 'Type a number' : 'Type your answer',
        area: q.type == 'long',
        keyboard: q.type == 'number' ? const TextInputType.numberWithOptions(decimal: true) : null,
        onChanged: changed,
      ),
    ];
  }

  // ─────────────────────────────── Photos

  List<Widget> _photosQ(CkQ q) {
    final names = q.slots, keys = _slotKeys(q);
    final got = _photos['${q.id}'] ?? const {};
    final per = keys.length == 1 ? 2 : (keys.length == 4 ? 2 : 3);
    final web = CaWeb.of(context);
    return [
      for (var r = 0; r < keys.length; r += per)
        Row(
          spacing: 8,
          children: [
            for (var i = r; i < r + per; i++)
              Expanded(
                child: i < keys.length
                    ? AspectRatio(aspectRatio: web ? 4 / 3 : 3 / 4, child: _slot(q, names[i], keys[i], got[keys[i]]))
                    : const SizedBox(),
              ),
          ],
        ),
      Text('Only $coach sees your photos.', style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.45)),
    ];
  }

  Widget _slot(CkQ q, String name, String key, String? url) {
    final has = url != null;
    final bytes = dataBytes(url);
    final inner = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 3,
      children: [
        Container(
          width: 34,
          height: 34,
          margin: const EdgeInsets.only(bottom: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: has ? AppColors.okSolid : AppColors.white,
            shape: BoxShape.circle,
            border: Border.all(color: has ? AppColors.okSolid : AppColors.line),
          ),
          child: AppIcon(has ? AppIcons.check : AppIcons.camera, size: 17, color: has ? AppColors.white : AppColors.text2, stroke: has ? 2.6 : 1.8),
        ),
        CutText(
          name,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.s(13, W.w8, color: has && bytes != null ? AppColors.white : AppColors.text),
        ),
        Text(
          has ? 'Added · tap to remove' : 'Tap to add',
          textAlign: TextAlign.center,
          style: AppText.s(10.5, W.w6, color: has && bytes != null ? AppColors.white.withValues(alpha: .9) : AppColors.muted),
        ),
      ],
    );
    return Semantics(
      button: true,
      label: '$name photo',
      child: Hover(
        onTap: () => has ? _removePhoto(q, name, key) : _addPhoto(q, name, key),
        builder: (_, h, _) => has
            ? Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.slotOnLine, width: 1.5),
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppColors.slotOn),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (bytes != null) ...[
                      Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
                      const DecoratedBox(decoration: BoxDecoration(color: Color(0x59000000))),
                    ],
                    Padding(padding: const EdgeInsets.all(6), child: inner),
                  ],
                ),
              )
            : DashedBox(
                color: h ? AppColors.accent : AppColors.tickRing,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: AppColors.caWebBg, borderRadius: BorderRadius.circular(12)),
                  child: inner,
                ),
              ),
      ),
    );
  }

  Future<void> _addPhoto(CkQ q, String name, String key) async {
    ImageSource? src = ImageSource.gallery;
    if (context.isPhone) {
      src = null;
      await showActionSheet(context, title: '$name photo', [
        MenuEntry('Take a photo', icon: AppIcons.camera, onTap: () => src = ImageSource.camera),
        MenuEntry('Choose from gallery', icon: AppIcons.photo, onTap: () => src = ImageSource.gallery),
      ]);
      if (src == null) return;
    }
    try {
      final x = await ImagePicker().pickImage(source: src!, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
      if (x == null || !mounted) return;
      final b = await x.readAsBytes();
      if (b.length > 10 * 1024 * 1024) {
        if (mounted) showToast(context, 'This photo is too big', sub: 'Photos can be up to 10 MB', kind: ToastKind.warn);
        return;
      }
      final mime = (x.mimeType ?? '').startsWith('image/') ? x.mimeType! : (x.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
      setState(() => (_photos['${q.id}'] ??= {})[key] = 'data:$mime;base64,${base64Encode(b)}');
      _save();
      if (mounted) showToast(context, '$name photo added', kind: ToastKind.ok);
    } catch (_) {
      if (mounted) showToast(context, 'Could not open the photos', sub: 'Allow photo access for the app in your phone settings', kind: ToastKind.warn);
    }
  }

  void _removePhoto(CkQ q, String name, String key) {
    final was = _photos['${q.id}']![key]!;
    setState(() => _photos['${q.id}']!.remove(key));
    _save();
    showToast(
      context,
      '$name photo removed',
      kind: ToastKind.del,
      action: 'Undo',
      onAction: () {
        if (!mounted) return;
        setState(() => (_photos['${q.id}'] ??= {})[key] = was);
        _save();
      },
    );
  }

  // ─────────────────────────────── Review, nav, sent

  Widget _review() => Column(
    children: [
      for (final (i, q) in qs.indexed)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            spacing: 10,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 1,
                  children: [
                    Text('${i + 1}. ${q.text}', style: AppText.s(11.5, W.w6, color: AppColors.muted)),
                    Builder(
                      builder: (_) {
                        final a = _ans(q);
                        return Text(
                          a ?? (q.required ? 'Not answered · required' : 'Skipped'),
                          style: AppText.s(
                            13.5,
                            a == null && !q.required ? W.w6 : W.w7,
                            color: a != null ? AppColors.text : (q.required ? AppColors.badText : AppColors.muted),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(height: 30, child: chSmall('Edit', () => _go(i))),
            ],
          ),
        ),
    ],
  );

  Widget _nav() {
    final review = _step >= qs.length;
    final q = review ? null : qs[_step];
    final label = review
        ? 'Send to $coach'
        : _step == qs.length - 1
        ? 'Review'
        : (q != null && !q.required && _ans(q) == null ? 'Skip' : 'Next');
    return Row(
      spacing: 8,
      children: [
        Expanded(
          child: Opacity(
            opacity: _step == 0 ? .4 : 1,
            child: CaButton('Back', kind: CaBtnKind.out, icon: AppIcons.chevronLeft, onPressed: _step == 0 ? () {} : () => _go(_step - 1)),
          ),
        ),
        Expanded(
          flex: 2,
          child: CaButton(
            label,
            trailingIcon: review ? null : AppIcons.chevronRight,
            dimmed: q != null && q.required && _ans(q) == null,
            loading: _busy,
            onPressed: _next,
          ),
        ),
      ],
    );
  }

  Widget _done(Map<String, dynamic> s) {
    final at = DateTime.tryParse('${s['sent_at']}')?.toLocal() ?? DateTime.now();
    final got = (s['answers'] as Map?)?.cast<String, dynamic>() ?? const {};
    // The photos she sent, as pictures (not "Sent"); offline, before the server has them, the rows still say Sent.
    final photos = [for (final p in (s['photos'] as List? ?? const [])) ('${(p as Map)['label']}', '${p['image']}')];
    return CkDone(
      title: 'Sent to $coach',
      sub: s['id'] == null ? 'Saved on this phone · it goes to $coach when you are online' : '${dayShort(at)}, ${clock(at)} · $coach reads every answer',
      rows: [
        for (final q in qs)
          if (q.type != 'photo' || photos.isEmpty)
            (q.text, q.type == 'photo' ? (_ans(q) ?? 'Sent') : (q.show(got['${q.id}'] ?? _v['${q.id}']) ?? 'Skipped')),
      ],
      photos: photos,
      buttons: CaButton('Back to check-ins', onPressed: () => context.go('/checkins')),
    );
  }
}

/// `dr-opt sm`: a radio row.
class _Opt extends StatelessWidget {
  const _Opt(this.label, {required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    child: Hover(
      onTap: onTap,
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: on ? AppColors.pickBg : AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? AppColors.accent : (h ? AppColors.lineHover : AppColors.line2)),
          boxShadow: on ? const [BoxShadow(color: AppColors.accentSoft, spreadRadius: 3)] : null,
        ),
        child: Row(
          spacing: 12,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.white,
                shape: BoxShape.circle,
                border: Border.all(color: on ? AppColors.accent : AppColors.line2, width: on ? 5 : 1.5),
              ),
            ),
            Expanded(child: Text(label, style: AppText.s(13.5, W.w7))),
          ],
        ),
      ),
    ),
  );
}

/// `fl-off` with `fl-cb`: a checkbox row (pick all that apply).
class _Check extends StatelessWidget {
  const _Check(this.label, {required this.on, required this.first, required this.onTap});
  final String label;
  final bool on, first;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    child: Hover(
      onTap: onTap,
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: AppColors.line))),
        child: Row(
          spacing: 10,
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.accent : AppColors.white,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: on ? AppColors.accent : (h ? AppColors.lineHover : AppColors.line2), width: 1.5),
              ),
              child: on ? const AppIcon(AppIcons.check, size: 12, color: AppColors.white, stroke: 3) : null,
            ),
            Expanded(child: Text(label, style: AppText.s(13.5, W.w7))),
          ],
        ),
      ),
    ),
  );
}
