import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/shell/back_nav.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../home/home_model.dart' show clock, dayShort;
import '../progress/progress_model.dart' show pxAmt, pxDm;
import '../progress/progress_parts.dart' show MeasureField;
import 'checkins_model.dart';
import 'checkins_parts.dart';
import '../../../core/widgets/tooltip.dart';

/// Weekly check-in: every question in one list (Probid 2026-10-31, no more one question a page), then
/// "Week N check-in sent". Answers are kept as a draft on the phone until it is sent. Edit answers works only on
/// the day it was sent.
class WeeklyCheckin extends StatefulWidget {
  const WeeklyCheckin({super.key, required this.c});
  final CheckinsController c;
  @override
  State<WeeklyCheckin> createState() => _WeeklyCheckinState();
}

class _WeeklyCheckinState extends State<WeeklyCheckin> {
  CheckinsController get c => widget.c;
  final _v = <String, Object?>{};
  final _photos = <String, String>{}; // slot ("front", "meal"…) → data URL
  final _texts = <int, TextEditingController>{};
  bool _noPhotos = false, _filled = false, _busy = false;
  CkRow? _sent;

  /// Edit answers of the check-in sent today (photos stay as sent).
  bool _editing = false;

  /// Her own words for Other on a choice question, by question id.

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
  CkRow? get sent => _sent ?? w.sent ?? CheckinsController.queuedWeekly;

  /// The photos the photo question asks for: names and keys ("Front" → "front").
  List<String> get _slotNames => qs.where((q) => q.type == 'photo').firstOrNull?.slots ?? const [];
  bool get _canSkipPhotos => qs.where((q) => q.type == 'photo').firstOrNull?.allowSkip ?? true;
  List<String> get _slotKeys => [for (final n in _slotNames) n.toLowerCase()];
  List<(String, String)> get _thumbs => [
    for (final (i, k) in _slotKeys.indexed)
      if (_photos[k] != null) (_slotNames[i], _photos[k]!),
  ];

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
      if (_noPhotos && _canSkipPhotos) return 'No photos this week';
      final n = _thumbs.length, all = _slotKeys.length;
      if (n == 0) return null;
      if (all == 1) return '1 photo';
      final miss = [
        for (final (i, k) in _slotKeys.indexed)
          if (!_photos.containsKey(k)) _slotNames[i].toLowerCase(),
      ];
      return '$n of $all photos${miss.isEmpty ? '' : ' (${miss.join(', ')} missing)'}';
    }
    final v = _v['${q.id}'];
    if (q.type == 'measures') {
      final need = [for (final m in q.measures) if (m['required'] == true) '${m['key']}'];
      return v is Map && v.isNotEmpty && need.every(v.containsKey) ? q.show(v, short: true) : null;
    }
    if (q.metric == 'weight' && v is num) {
      final last = w.lastWeight;
      return kg(v.toDouble()) + (last != null && v < last ? ' (${kgChange(v - last)})' : '');
    }
    return q.show(v);
  }

  int get _answered => qs.where((q) => _ans(q) != null).length;

  void _save() {
    if (_editing) return;
    c.saveDraft(w.week, {'answers': _v, 'photos': _photos, 'no_photos': _noPhotos});
  }

  void _set(CkQ q, Object? v) {
    setState(() => _v['${q.id}'] = v);
    _save();
  }

  /// Leaving with answers but not sent asks: save and continue later, or discard (E32).
  Future<void> _exit() async {
    if (_editing) {
      setState(() => _editing = false);
      return;
    }
    if (sent == null && _answered > 0) {
      final keep = await ckAskLeave(context);
      if (keep == null || !mounted) return;
      if (keep) {
        _save();
        showToast(context, 'Draft saved', sub: '$_answered of ${qs.length} answered · finish by ${w.due}', kind: ToastKind.info);
      } else {
        await c.saveDraft(w.week, null);
        if (!mounted) return;
        showToast(context, 'Check-in discarded', kind: ToastKind.info);
      }
    }
    if (mounted) context.go('/checkins');
  }

  Future<void> _send() async {
    final miss = [
      for (final q in _shown)
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
    if (_editing) {
      final row = sent!;
      final answers = {
        for (final q in qs)
          if (q.type != 'photo' && _v['${q.id}'] != null && _v['${q.id}'] != '') '${q.id}': _v['${q.id}'],
      };
      try {
        await c.edit(f, row.id!, answers);
        if (!mounted) return;
        row.j['answers'] = answers;
        setState(() => _editing = false);
        showToast(context, 'Check-in updated', sub: '$coach sees your new answers', kind: ToastKind.ok);
      } catch (e) {
        if (mounted) showToast(context, 'Could not save it', sub: '$e', kind: ToastKind.err);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
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

  /// The phone's back button = Save and exit (Phase 4).
  @override
  Widget build(BuildContext context) => BackIntercept(
    onBack: () {
      if (c.data == null || w.form == null) return false;
      _exit();
      return true;
    },
    child: Builder(builder: _page),
  );

  Widget _page(BuildContext context) => ListenableBuilder(
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
      return CkPage(
        web: web,
        header: [
          CkTop(
            title: _editing ? 'Edit weekly check-in' : 'Weekly check-in',
            sub: 'Week ${w.week} · due ${w.due}',
            onBack: _exit,
            backLabel: _editing ? 'Cancel' : 'Back',
          ),
          if (sent == null || _editing)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 6,
              children: [
                Text('$_answered of ${_shown.length} answered', style: AppText.s(12, W.w7, color: AppColors.muted)),
                CkBar(_shown.isEmpty ? 0 : _answered / _shown.length),
              ],
            ),
        ],
        children: sent != null && !_editing
            ? [_done()]
            : !w.open
            // Only from its due day (E23).
            ? [ckInfo('Your weekly check-in opens ${w.due}. You can fill it that day and the 2 days after.', icon: AppIcons.lock)]
            : [for (final (i, q) in _shown.indexed) _card(i, q), _sendBtn()],
      );
    },
  );

  /// The questions on the page: in Edit answers the photos stay as sent, so the photo question is left out.
  List<CkQ> get _shown => _editing ? qs.where((q) => q.type != 'photo').toList() : qs;

  Widget _card(int i, CkQ q) => Container(
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
            Text.rich(
              TextSpan(
                text: '${i + 1}. ${q.text}',
                children: [if (!q.required) TextSpan(text: ' · optional', style: AppText.s(12.5, W.w6, color: AppColors.muted))],
              ),
              style: AppText.s(16, W.w8, h: 1.3),
            ),
            if (q.help.isNotEmpty) Text(q.help, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
          ],
        ),
        ..._answer(q),
      ],
    ),
  );

  Widget _sendBtn() => CaButton(
    _editing ? 'Save changes' : 'Send to $coach',
    icon: _editing ? AppIcons.check : AppIcons.send,
    loading: _busy,
    dimmed: _shown.any((q) => q.required && _ans(q) == null),
    onPressed: _send,
  );

  /// Edit answers (only on the day it was sent): the sent answers back in the list.
  void _startEdit(CkRow row) {
    setState(() {
      _v
        ..clear()
        ..addAll(row.answers.cast<String, Object?>());
      for (final q in qs) {
        if (q.type == 'short' || q.type == 'long') _texts[q.id] = TextEditingController(text: '${_v['${q.id}'] ?? ''}');
      }
      _editing = true;
    });
  }

  List<Widget> _answer(CkQ q) {
    final v = _v['${q.id}'];
    if (q.type == 'number' && q.asField) {
      // a plain number box (the coach chose Field)
      final t = _texts[q.id] ??= TextEditingController(text: v == null ? '' : '$v');
      return [
        CkInput(
          controller: t,
          hint: 'Type a number',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          onChanged: () => _set(q, double.tryParse(t.text.trim().replaceAll(',', '.'))),
        ),
        ?_quickPick(q, (v as num?)?.toDouble()),
      ];
    }
    if (q.type == 'number') {
      final x = (v as num?)?.toDouble() ?? q.last ?? q.min ?? 0;
      double fit(double n) => n.clamp(q.min ?? -1e9, q.max ?? 1e9).toDouble();
      final st = q.step;
      final last = w.lastWeight;
      final isW = q.metric == 'weight';
      final d = last == null ? null : ((x - last) * 10).round() / 10;
      final diff = d == null || !isW ? null : (d == 0 ? 'Same as last week' : '${kgChange(d)} since last week');
      return [
        CkStepper(
          value: x.toStringAsFixed(1),
          suffix: isW ? 'kg' : null,
          onMinus: () => _set(q, fit(((x - st) * 100).round() / 100)),
          onPlus: () => _set(q, fit(((x + st) * 100).round() / 100)),
          onType: (n) => _set(q, n),
          under: diff == null
              ? null
              : Text(diff, style: AppText.s(12.5, W.w7, color: d! < 0 ? AppColors.okText : (d > 0 ? AppColors.amberText : AppColors.muted))),
        ),
        ?_quickPick(q, x),
        if (isW && !q.quick && (_todayWeight != null || last != null))
          CkTry(
            lead: 'Quick',
            items: [if (_todayWeight != null) 'This morning, ${_todayWeight!.toStringAsFixed(1)}', if (last != null) 'Last week, ${last.toStringAsFixed(1)}'],
            onPick: (t) => _set(q, double.parse(t.split(', ').last)),
          ),
      ];
    }
    if (q.type == 'scale') {
      return [CkScale(labels: q.labels, value: q.scaleOf(v), onPick: (n) => _set(q, n), lg: true)];
    }
    if (q.isChoice || q.type == 'multiple') {
      return [CkChoice(q: q, value: v, onChanged: (x) => _set(q, x))];
    }
    if (q.type == 'photo') return _photosQ();
    if (q.type == 'measures') return _measuresQ(q);
    final t = _texts[q.id] ??= TextEditingController(text: '${v ?? ''}');
    void changed() {
      _v['${q.id}'] = t.text.trim().isEmpty ? null : t.text.trim();
      setState(() {});
      _save();
    }

    return [
      CkInput(controller: t, hint: q.suggestions.isEmpty ? 'Type your answer' : 'Type your answer, or tap a suggestion below', area: q.type == 'long', onChanged: changed),
      // The coach's own chips; none = no chips (Probid 2026-10-31).
      if (q.suggestions.isNotEmpty)
        CkTry(
          lead: 'Tap to add',
          items: q.suggestions,
          onPick: (s) {
            final n = t.text.trim();
            t.text = n.isNotEmpty && !n.contains(s) ? '$n. $s' : (n.contains(s) ? n : s);
            changed();
          },
        ),
    ];
  }

  // ─────────────────────────────── Body measurements (photo weeks, D-24)


  /// Every row starts at the last value; only the ones changed are sent, and they also land on Progress.
  List<Widget> _measuresQ(CkQ q) {
    final got = ((_v['${q.id}'] as Map?) ?? const {}).cast<String, dynamic>();
    void put(String k, double? n) {
      final next = {...got};
      n == null ? next.remove(k) : next[k] = n;
      _set(q, next.isEmpty ? null : next);
    }

    return [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, m) in q.measures.indexed) _measureRow(m, got, put, first: i == 0),
      ]),
      Text(
        got.isEmpty ? 'Skip this step if you did not measure this week.' : '${got.length} measured · they also go on your Progress page',
        style: AppText.s(12, W.w5, color: got.isEmpty ? AppColors.muted : AppColors.okText),
      ),
    ];
  }

  Widget _measureRow(Map<String, dynamic> m, Map<String, dynamic> got, void Function(String, double?) put, {required bool first}) {
    final k = '${m['key']}', unit = '${m['unit']}';
    final last = (m['last'] as num?)?.toDouble();
    final lastOn = m['last_date'] == null ? null : DateTime.tryParse('${m['last_date']}');
    final on = got.containsKey(k);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: AppColors.line))),
      child: Row(spacing: 10, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
            Text('${m['label']}${m['required'] == true ? ' *' : ''}', style: AppText.s(13.5, W.w7, color: on ? AppColors.text : AppColors.text2)),
            Text(
              on ? 'Will be saved' : (last == null ? 'Not measured yet' : 'Last ${pxAmt(last, unit)}${lastOn == null ? '' : ' · ${pxDm(lastOn)}'}'),
              style: AppText.s(12, W.w4, color: on ? AppColors.okText : AppColors.muted),
            ),
          ]),
        ),
        // A plain number box (E29); empty = not measured this week.
        MeasureField(value: (got[k] as num?)?.toDouble(), hint: last, unit: unit, name: '${m['label']}', onChanged: (n) => put(k, n)),
      ]),
    );
  }

  /// Quick pick: chips around her last answer, the coach's step apart (Probid 2026-11-02).
  Widget? _quickPick(CkQ q, double? now) {
    final l = q.last;
    if (!q.quick || l == null) return null;
    final s = q.quickStep;
    String f(double n) => n == n.roundToDouble() ? '${n.round()}' : n.toStringAsFixed(s < .1 ? 2 : 1);
    final vals = [for (var i = -2; i <= 2; i++) ((l + i * s) * 100).round() / 100]
        .where((n) => (q.min == null || n >= q.min!) && (q.max == null || n <= q.max!))
        .toList();
    return CkTry(lead: 'Last ${f(l)}', items: [for (final n in vals) f(n)], onPick: (t) {
      final n = double.parse(t);
      final c = _texts[q.id];
      if (c != null) c.text = t;
      _set(q, n);
    });
  }

  /// Other on a choice question the coach allows it on: her own words, saved as "Other: …" (Probid 2026-10-31).
  // ─────────────────────────────── Photos

  List<Widget> _photosQ() {
    final web = CaWeb.of(context);
    final keys = _slotKeys;
    // Up to 3 a row; one photo gets a wider slot.
    final per = keys.length == 1 ? 2 : (keys.length == 4 ? 2 : 3);
    return [
      for (var r = 0; r < keys.length; r += per)
        Row(
          spacing: 8,
          children: [
            for (var i = r; i < r + per; i++)
              Expanded(
                child: i < keys.length ? AspectRatio(aspectRatio: web ? 4 / 3 : 3 / 4, child: _slot(i, keys[i])) : const SizedBox(),
              ),
          ],
        ),
      if (_canSkipPhotos) Hover(
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
    final name = _slotNames[i];
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
      await showActionSheet(context, title: '${_slotNames[i]} photo', [
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
      if (mounted) showToast(context, '${_slotNames[i]} photo added', sub: _slotKeys.length == 1 ? null : '${_thumbs.length} of ${_slotKeys.length} photos', kind: ToastKind.ok);
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
      '${_slotNames[i]} photo removed',
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

  Widget _done() {
    final row = sent!;
    final at = row.sentAt ?? DateTime.now();
    final wt = row.weight ?? (_v['${qs.where((q) => q.metric == 'weight').firstOrNull?.id}'] as num?)?.toDouble();
    final last = w.lastWeight;
    final thumbs = row.thumbs.isNotEmpty ? row.thumbs : _thumbs;
    // Every question with its full text, like the past check-in sheet.
    final rows = <(String, String)>[
      for (final q in qs)
        if (q.metric == 'weight' && wt != null) ...[
          ('Weight', kg(wt)),
          if (last != null) ('Change', kgChange(wt - last)),
        ] else if (q.type == 'photo')
          ('Photos', thumbs.isNotEmpty ? (thumbs.length == 1 ? '1 photo' : '${thumbs.length} photos') : (row.photos > 0 ? '${row.photos} photos' : 'Skipped'))
        else
          (q.text, q.show(row.answers['${q.id}'] ?? _v['${q.id}']) ?? 'Skipped'),
    ];
    return CkDone(
      title: 'Week ${row.week ?? w.week} check-in sent',
      sub: row.id == null
          ? 'Saved on this phone · it goes to $coach when you are online'
          : '${dayShort(at)}, ${clock(at)} · $coach usually replies within a day',
      rows: rows,
      photos: thumbs,
      buttons: row.id != null && DateUtils.isSameDay(row.date, DateTime.now())
          ? Row(
              spacing: 8,
              children: [
                Expanded(child: CaButton('Edit answers', kind: CaBtnKind.out, icon: AppIcons.edit, onPressed: () => _startEdit(row))),
                Expanded(child: CaButton('Back to check-ins', onPressed: () => context.go('/checkins'))),
              ],
            )
          : CaButton('Back to check-ins', onPressed: () => context.go('/checkins')),
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
