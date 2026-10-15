import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../home/home_model.dart' show clock, dayShort;
import 'checkins_model.dart';
import 'checkins_parts.dart';

/// Weekly check-in (board ClientCheckin, `isWeekly`): one question a page, a review page, then
/// "Week N check-in sent". Answers are kept as a draft on the phone until it is sent.
class WeeklyCheckin extends StatefulWidget {
  const WeeklyCheckin({super.key, required this.c});
  final CheckinsController c;
  @override
  State<WeeklyCheckin> createState() => _WeeklyCheckinState();
}

const poses = ['front', 'side', 'back'];
const poseNames = ['Front', 'Side', 'Back'];

class _WeeklyCheckinState extends State<WeeklyCheckin> {
  CheckinsController get c => widget.c;
  final _v = <String, Object?>{};
  final _photos = <String, String>{}; // pose → data URL
  final _texts = <int, TextEditingController>{};
  bool _noPhotos = false, _filled = false, _busy = false;
  int _step = 0;
  CkRow? _sent;

  static const _tips = ['Office travel next week, Tue to Thu', 'Knee felt better on box squats', 'Can I get more dinner ideas?', 'Nothing this week'];

  @override
  void dispose() {
    for (final t in _texts.values) {
      t.dispose();
    }
    super.dispose();
  }

  CkWeekly get w => c.data!.weekly;
  CkForm get f => w.form!;
  List<CkQ> get qs => f.questions;
  String get coach => c.data!.coachFirst;
  CkRow? get sent => _sent ?? w.sent ?? c.queuedWeekly;

  Future<void> _fill() async {
    if (_filled || c.data == null || w.form == null) return;
    _filled = true;
    final dr = await c.readDraft(w.week);
    if (!mounted) return;
    setState(() {
      if (dr != null) {
        _v.addAll((dr['answers'] as Map? ?? {}).cast<String, Object?>());
        _photos.addAll((dr['photos'] as Map? ?? {}).cast<String, String>());
        _noPhotos = dr['no_photos'] == true;
        _step = ((dr['step'] as num?)?.toInt() ?? 0).clamp(0, qs.length);
      }
      for (final q in qs) {
        if (q.metric == 'weight' && _v['${q.id}'] == null) _v['${q.id}'] = _todayWeight ?? w.lastWeight ?? 70.0;
        if (q.type == 'short' || q.type == 'long') _texts[q.id] = TextEditingController(text: '${_v['${q.id}'] ?? ''}');
      }
    });
  }

  double? get _todayWeight => c.data!.daily.todayWeight ?? (c.data!.daily.sent?.weight);

  /// Weight is answered once it was touched or came from a draft; everything else once set.
  String? _ans(CkQ q) {
    if (q.type == 'photo') {
      if (_noPhotos) return 'No photos this week';
      final n = _photos.length;
      if (n == 0) return null;
      final miss = [
        for (final (i, p) in poses.indexed)
          if (!_photos.containsKey(p)) poseNames[i].toLowerCase(),
      ];
      return '$n of 3 photos${miss.isEmpty ? '' : ' (${miss.join(', ')} missing)'}';
    }
    final v = _v['${q.id}'];
    if (q.metric == 'weight' && v is num) {
      final last = w.lastWeight;
      return kg(v.toDouble()) + (last != null && v < last ? ' (${kgChange(v - last)})' : '');
    }
    return q.show(v);
  }

  int get _answered => qs.where((q) => _ans(q) != null).length;

  void _save() {
    c.saveDraft(w.week, {'answers': _v, 'photos': _photos, 'no_photos': _noPhotos, 'step': _step});
  }

  void _set(CkQ q, Object? v) {
    setState(() => _v['${q.id}'] = v);
    _save();
  }

  void _go(int n) {
    setState(() => _step = n);
    _save();
  }

  void _exit() {
    if (sent == null && _answered > 0) {
      _save();
      showToast(context, 'Draft saved', sub: '$_answered of ${qs.length} answered · finish by ${w.due}', kind: ToastKind.info);
    }
    context.go('/checkins');
  }

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
    _go(_step + 1);
  }

  Future<void> _send() async {
    final miss = [
      for (final q in qs)
        if (q.required && _ans(q) == null) q,
    ];
    if (miss.isNotEmpty) {
      final req = [
        for (final (i, q) in qs.indexed)
          if (q.required) i + 1,
      ];
      showToast(
        context,
        'Answer “${miss.first.text}” first',
        sub: req.length > 1 && req.last - req.first + 1 == req.length ? 'Questions ${req.first} to ${req.last} are required' : 'This question is required',
        kind: ToastKind.warn,
      );
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    final photoQ = qs.where((q) => q.type == 'photo').firstOrNull;
    final answers = {
      for (final q in qs)
        if (q.type != 'photo' && _v['${q.id}'] != null && _v['${q.id}'] != '') '${q.id}': _v['${q.id}'],
    };
    try {
      final row = await c.send(f, answers, photos: photoQ != null && !_noPhotos && _photos.isNotEmpty ? {'${photoQ.id}': Map.of(_photos)} : null);
      await c.saveDraft(w.week, null);
      if (!mounted) return;
      setState(() => _sent = row);
      final off = row.id == null;
      showToast(
        context,
        'Week ${w.week} check-in sent',
        sub: off ? 'Saved on this phone · it goes to $coach when you are online' : '$coach usually replies within a day',
        kind: ToastKind.star,
        action: off ? null : 'Undo',
        onAction: off
            ? null
            : () async {
                await c.undo(row, 'weekly');
                if (!mounted) return;
                setState(() => _sent = null);
                _save();
              },
      );
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
      if (c.data == null || w.form == null) {
        return Center(
          child: c.error == null && c.data == null
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))
              : Text(c.error?.message ?? 'There is no weekly check-in to fill.', style: AppText.s(13, W.w5, color: AppColors.muted)),
        );
      }
      _fill();
      final web = !context.isPhone;
      final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          CkTop(title: 'Weekly check-in', sub: 'Week ${w.week} · due ${w.due}', onBack: _exit, backLabel: 'Save and exit'),
          if (sent != null)
            _done()
          else ...[
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
            _card(),
            _nav(),
          ],
        ],
      );
      return CaWeb(
        web: web,
        child: SingleChildScrollView(
          padding: web ? const EdgeInsets.fromLTRB(32, 32, 32, 72) : const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: web ? 640 : double.infinity),
              child: body,
            ),
          ),
        ),
      );
    },
  );

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
              Text(review ? 'Check your answers' : '${_step + 1}. ${q!.text}', style: AppText.s(17, W.w8, h: 1.3)),
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
    if (q.type == 'number') {
      final x = (v as num?)?.toDouble() ?? 0;
      final last = w.lastWeight;
      final isW = q.metric == 'weight';
      final d = last == null ? null : ((x - last) * 10).round() / 10;
      final diff = d == null || !isW ? null : (d == 0 ? 'Same as last week' : '${kgChange(d)} since last week');
      return [
        CkStepper(
          value: isW ? kg(x) : x.toStringAsFixed(1),
          onMinus: () => _set(q, ((x - .1) * 10).round() / 10),
          onPlus: () => _set(q, ((x + .1) * 10).round() / 10),
          under: diff == null
              ? null
              : Text(diff, style: AppText.s(12.5, W.w7, color: d! < 0 ? AppColors.okText : (d > 0 ? AppColors.amberText : AppColors.muted))),
        ),
        if (isW && (_todayWeight != null || last != null))
          CkTry(
            lead: 'Quick',
            items: [if (_todayWeight != null) 'This morning, ${_todayWeight!.toStringAsFixed(1)}', if (last != null) 'Last week, ${last.toStringAsFixed(1)}'],
            onPick: (t) => _set(q, double.parse(t.split(', ').last)),
          ),
      ];
    }
    if (q.type == 'scale') {
      return [CkScale(labels: q.labels, value: (v as num?)?.toInt(), onPick: (n) => _set(q, n), lg: true)];
    }
    if (q.isChoice || q.type == 'multiple') {
      final multi = q.type == 'multiple';
      final sel = multi ? [...((v as List?) ?? const [])] : [if (v != null) q.type == 'yes_no' ? ((v as bool) ? 'Yes' : 'No') : v];
      return [
        Column(
          spacing: 8,
          children: [
            for (final o in q.options)
              _Opt(
                o,
                on: sel.contains(o),
                onTap: () {
                  if (multi) {
                    sel.contains(o) ? sel.remove(o) : sel.add(o);
                    _set(q, sel.isEmpty ? null : sel);
                  } else {
                    _set(q, q.type == 'yes_no' ? o == 'Yes' : o);
                  }
                },
              ),
          ],
        ),
      ];
    }
    if (q.type == 'photo') return _photosQ();
    final t = _texts[q.id] ??= TextEditingController(text: '${v ?? ''}');
    void changed() {
      _v['${q.id}'] = t.text.trim().isEmpty ? null : t.text.trim();
      setState(() {});
      _save();
    }

    return [
      CkInput(controller: t, hint: 'Type your answer, or tap a suggestion below', area: true, onChanged: changed),
      if (q.type == 'long')
        CkTry(
          lead: 'Tap to add',
          items: _tips,
          onPick: (s) {
            final n = t.text.trim();
            t.text = n.isNotEmpty && !n.contains(s) ? '$n. $s' : (n.contains(s) ? n : s);
            changed();
          },
        ),
    ];
  }

  // ─────────────────────────────── Photos

  List<Widget> _photosQ() {
    final web = CaWeb.of(context);
    return [
      Row(
        spacing: 8,
        children: [
          for (final (i, p) in poses.indexed)
            Expanded(
              child: AspectRatio(aspectRatio: web ? 4 / 3 : 3 / 4, child: _slot(i, p)),
            ),
        ],
      ),
      Hover(
        onTap: () {
          setState(() {
            _noPhotos = !_noPhotos;
            if (_noPhotos) _photos.clear();
          });
          _save();
        },
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.only(top: 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              Padding(padding: const EdgeInsets.only(top: 1), child: _box(_noPhotos)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 1,
                  children: [
                    Text('No photos this week', style: AppText.s(13.5, W.w7)),
                    Text('Fine now and then. $coach compares photos every 2 weeks.', style: AppText.s(12, W.w4, color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      Text('Same spot, same light, in the morning. Only $coach sees your photos.', style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.45)),
    ];
  }

  Widget _box(bool on) => Container(
    width: 18,
    height: 18,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: on ? AppColors.accent : AppColors.white,
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: on ? AppColors.accent : AppColors.line2, width: 1.5),
    ),
    child: on ? const AppIcon(AppIcons.check, size: 12, color: AppColors.white, stroke: 3) : null,
  );

  Widget _slot(int i, String pose) {
    final url = _photos[pose];
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
        Text(poseNames[i], style: AppText.s(13, W.w8, color: has && bytes != null ? AppColors.white : AppColors.text)),
        Text(
          has ? 'Added · tap to remove' : 'Tap to add',
          textAlign: TextAlign.center,
          style: AppText.s(10.5, W.w6, color: has && bytes != null ? AppColors.white.withValues(alpha: .9) : AppColors.muted),
        ),
      ],
    );
    return Semantics(
      button: true,
      label: '${poseNames[i]} photo',
      child: Hover(
        onTap: () => has ? _removePhoto(i, pose) : _addPhoto(i, pose),
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

  Future<void> _addPhoto(int i, String pose) async {
    ImageSource? src = ImageSource.gallery;
    if (context.isPhone) {
      src = null;
      await showActionSheet(context, title: '${poseNames[i]} photo', [
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
      setState(() {
        _photos[pose] = 'data:$mime;base64,${base64Encode(b)}';
        _noPhotos = false;
      });
      _save();
      if (mounted) showToast(context, '${poseNames[i]} photo added', sub: '${_photos.length} of 3 photos', kind: ToastKind.ok);
    } catch (_) {
      if (mounted) showToast(context, 'Could not open the photos', sub: 'Allow photo access for the app in your phone settings', kind: ToastKind.warn);
    }
  }

  void _removePhoto(int i, String pose) {
    final was = _photos[pose]!;
    setState(() => _photos.remove(pose));
    _save();
    showToast(
      context,
      '${poseNames[i]} photo removed',
      kind: ToastKind.del,
      action: 'Undo',
      onAction: () {
        if (!mounted) return;
        setState(() => _photos[pose] = was);
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

  Widget _done() {
    final row = sent!;
    final at = row.sentAt ?? DateTime.now();
    final wt = row.weight ?? (_v['${qs.where((q) => q.metric == 'weight').firstOrNull?.id}'] as num?)?.toDouble();
    final last = w.lastWeight;
    final rows = <(String, String)>[
      if (wt != null) ('Weight', kg(wt)),
      if (wt != null && last != null) ('Change', kgChange(wt - last)),
      for (final q in qs.where((q) => q.type == 'scale')) (q.chip, _ans(q) ?? '—'),
      for (final q in qs.where((q) => q.type == 'photo')) ('Photos', _ans(q) ?? (row.photos > 0 ? '${row.photos} photos' : 'Skipped')),
    ];
    return CkDone(
      title: 'Week ${row.week ?? w.week} check-in sent',
      sub: row.id == null
          ? 'Saved on this phone · it goes to $coach when you are online'
          : '${dayShort(at)}, ${clock(at)} · $coach usually replies within a day',
      rows: rows,
      buttons: CaButton('Back to check-ins', onPressed: () => context.go('/checkins')),
    );
  }
}

/// `ca-btn out sm` at 30 high (review Edit).
Widget chSmall(String label, VoidCallback onTap) => Hover(
  onTap: onTap,
  builder: (_, h, _) => Container(
    height: 30,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: h ? AppColors.outlineHover : AppColors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.line),
    ),
    child: Text(label, style: AppText.s(13, W.w7)),
  ),
);

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
