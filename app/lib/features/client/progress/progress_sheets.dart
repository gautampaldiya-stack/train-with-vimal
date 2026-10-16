import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/photo_viewer.dart';
import '../../../core/widgets/responsive.dart';
import '../food/food_model.dart' show DateUtils0;
import '../food/food_parts.dart' show NumStepper, fdCap;
import 'progress_model.dart';
import 'progress_parts.dart';

/// Sheets of the Progress tab (boards `ClientProgress` / `ClientProgressWeb`): Log weight, workouts done, a lift,
/// a photo set, Add photos and a History day.

/// A write the server turned down: say why and put the page back as the server has it.
void _failed(BuildContext context, Object e) {
  showToast(context, 'Could not save this', sub: e is ApiError ? e.message : 'Please try again', kind: ToastKind.err);
}

void showPxToast(BuildContext context, String title, String sub) => showToast(context, title, sub: sub, kind: ToastKind.info);

/// `px-kvs`: label · bold value rows, lines between. [topLine] draws a line above the first row (inside a box).
Widget pxKvs(List<(String, String)> rows, {bool topLine = false}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
  for (final (i, (l, v)) in rows.indexed)
    Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(border: i == 0 && !topLine ? null : const Border(top: BorderSide(color: AppColors.line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
        Text(l, style: AppText.s(13, W.w6, color: AppColors.muted)),
        Expanded(child: Text(v, textAlign: TextAlign.right, style: AppText.s(13, W.w7))),
      ]),
    ),
]);

/// `px-lbl`
Widget pxLbl(String t) => Text(t, style: AppText.s(12, W.w7, color: AppColors.muted));

/// `cl-ebtns` in a sheet footer: buttons side by side, equal width.
/// [flex] widens a button whose label is long ("See every logged set") so it is not cut on a phone.
List<Widget> Function(BuildContext) pxFooter(List<Widget> Function(BuildContext) buttons, {List<int>? flex}) =>
    (ctx) => [Row(spacing: 8, children: [for (final (i, b) in buttons(ctx).indexed) Expanded(flex: flex?[i] ?? 1, child: b)])];

/// `ch-qs px-qs`: a row of equal choice buttons (34 high), dark when picked.
class PxQuick extends StatelessWidget {
  const PxQuick({super.key, required this.items, required this.onPick, this.on});
  final List<String> items;
  final ValueChanged<int> onPick;
  final int? on;
  @override
  Widget build(BuildContext context) => Row(spacing: 8, children: [
    for (final (i, t) in items.indexed)
      Expanded(
        child: Semantics(
          button: true,
          selected: i == on,
          child: Hover(
            onTap: () => onPick(i),
            builder: (_, h, _) => Container(
              height: 34,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: i == on ? AppColors.text : (h ? AppColors.outlineHover : AppColors.white),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: i == on ? AppColors.text : AppColors.line),
              ),
              child: FittedBox(fit: BoxFit.scaleDown, child: Text(t, maxLines: 1, style: AppText.s(12.5, W.w7, color: i == on ? AppColors.white : AppColors.text))),
            ),
          ),
        ),
      ),
  ]);
}

// ─────────────────────────────── Log weight

class _Lw extends ChangeNotifier {
  _Lw(this.kg, this.day);
  double kg;
  DateTime day;
  void set(double v) {
    kg = ((v.clamp(30, 200)) * 10).round() / 10;
    notifyListeners();
  }

  void pick(DateTime d) {
    day = d;
    notifyListeners();
  }
}

/// Log weight sheet: one weigh-in a day (a second one replaces it), today or up to 3 days back.
Future<void> showLogWeight(BuildContext context, ProgressController c, {ValueChanged<DateTime>? onSaved}) {
  final d = c.data;
  final today = c.today;
  final s = _Lw(d?.last?.kg ?? d?.startKg ?? 70, today);
  final days = [for (var o = 0; o < 4; o++) today.subtract(Duration(days: o))];

  String note() {
    final w = d?.weights ?? const <PxWeight>[];
    final ex = w.where((x) => DateUtils0.same(x.date, s.day)).firstOrNull;
    final prev = w.where((x) => x.date.isBefore(s.day)).lastOrNull;
    if (ex != null) return 'Replaces the ${pxAmt(ex.kg, 'kg')} you logged on ${pxWdm(s.day)}.';
    if (prev != null) return '${pxWdm(s.day)} · ${pxChg(s.kg - prev.kg, 'kg')} since ${pxDm(prev.date)} (${pxAmt(prev.kg, 'kg')}).';
    return 'Your first weigh-in.';
  }

  Future<void> save(BuildContext ctx) async {
    final before = [...?d?.weights];
    final existed = before.any((x) => DateUtils0.same(x.date, s.day));
    final start = d?.startKg;
    final lastBefore = before.lastOrNull?.kg;
    final day = s.day, kg = s.kg;
    Navigator.of(ctx).pop();
    try {
      await c.logWeight(day, kg);
    } catch (e) {
      c.load();
      if (context.mounted) _failed(context, e);
      return;
    }
    onSaved?.call(day);
    if (!context.mounted) return;
    final now = c.data?.last?.kg;
    final b4 = start == null || lastBefore == null ? 0 : (start - lastBefore).floor();
    final af = start == null || now == null ? 0 : (start - now).floor();
    void undo() => c.undoWeight(before, day);
    if (af > b4 && af >= 1) {
      showToast(context, 'New milestone: $af kg lost', sub: '${pxAmt(kg, 'kg')} · ${pxDm(day)} · ${d?.coach ?? 'your coach'} can see it', kind: ToastKind.star, action: 'Undo', onAction: undo);
    } else {
      showToast(context, existed ? 'Weight updated' : 'Weight logged', sub: '${pxAmt(kg, 'kg')} · ${pxWdm(day)}', kind: ToastKind.ok, action: 'Undo', onAction: undo);
    }
  }

  return showAppSheet(
    context,
    title: 'Log weight',
    sub: 'Morning, before eating, gives the steadiest numbers',
    webWidth: 460,
    listen: s,
    footerStretch: true,
    builder: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      pxLbl('Weight'),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: NumStepper(value: s.kg, onChanged: s.set, label: (v) => pxAmt(v, 'kg'), step: .1, min: 30, max: 200, big: true, name: 'weight'),
        ),
      ),
      PxQuick(items: const ['−1 kg', '−0.5 kg', '+0.5 kg', '+1 kg'], onPick: (i) => s.set(s.kg + const [-1, -.5, .5, 1][i])),
      pxLbl('Date'),
      PxQuick(
        items: [for (final (i, x) in days.indexed) i == 0 ? 'Today' : (i == 1 ? 'Yesterday' : pxWdm(x))],
        on: days.indexWhere((x) => DateUtils0.same(x, s.day)),
        onPick: (i) => s.pick(days[i]),
      ),
      Padding(padding: const EdgeInsets.only(top: 2), child: pxNote(pxScale, note())),
    ]),
    footer: pxFooter((ctx) => [
      CaButton('Cancel', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
      CaButton('Save', icon: AppIcons.check, onPressed: () => save(ctx)),
    ]),
  );
}

// ─────────────────────────────── Workouts done

Future<void> showWorkoutsSheet(BuildContext context, PxData d) {
  final a = d.adherence;
  final w = a.weeks.lastOrNull;
  final missed = a.missed.reversed.take(3).toList().reversed;
  return showAppSheet(
    context,
    title: '${a.done} ${a.done == 1 ? 'workout' : 'workouts'} done',
    sub: [if (a.since != null) 'Since ${pxDm(a.since!)}', ?a.program].join(' · '),
    webWidth: 460,
    footerStretch: true,
    builder: (_) => pxKvs([
      ('This week', '${w?.done ?? 0} of ${w?.planned ?? 0}${a.today.isEmpty ? '' : ' · ${a.today} is today'}'),
      ('Planned so far', '${a.planned}'),
      ('Missed', a.missed.isEmpty ? 'None' : '${a.missed.length} · ${missed.map(pxDm).join(', ')}'),
      ('Average adherence', a.avg == null ? '—' : '${a.avg}%'),
    ]),
    footer: pxFooter((ctx) => [
      CaButton('Close', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
      CaButton('View past logs', onPressed: () {
        Navigator.of(ctx).pop();
        context.go('/progress/history?type=workout&range=3months');
      }),
    ]),
  );
}

// ─────────────────────────────── One lift

Future<void> showLiftSheet(BuildContext context, PxLift l) {
  final f = l.series.firstOrNull;
  return showAppSheet(
    context,
    title: l.name,
    sub: 'Best ${pxAmt(l.bestKg, 'kgs')}${f == null ? '' : ' · ${pxChg(l.gain, 'kgs')} since ${pxDm(f.date)}'}',
    webWidth: 460,
    footerStretch: true,
    builder: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      pxKvs([
        if (f != null) ('Started at', '${pxAmt(f.kg, 'kgs')} · ${pxDm(f.date)}'),
        ('Best set', l.bestSet),
        ('Weight went up', '${l.ups} ${l.ups == 1 ? 'time' : 'times'}'),
        ('Last logged', pxWdm(l.last)),
      ]),
      if (l.note.isNotEmpty) fdCap(l.note),
    ]),
    footer: pxFooter((ctx) => [
      CaButton('Close', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
      CaButton('See every logged set', onPressed: () {
        Navigator.of(ctx).pop();
        context.go('/progress/history?type=workout&range=3months');
      }),
    ], flex: const [2, 3]),
  );
}

// ─────────────────────────────── A photo set

/// Photo viewer sheet: one set, Front / Side / Back tabs; the photo opens full size.
Future<void> showPhotoSheet(BuildContext context, ProgressController c, PxSet set, String pose) {
  final p = ValueNotifier(pose);
  final sets = c.data?.sets ?? [set];
  final i = sets.indexWhere((x) => x.id == set.id);
  return showAppSheet(
    context,
    titleOf: () => '${pxWdm(set.date)} · ${p.value}',
    sub: [if (set.kg != null) pxAmt(set.kg!, 'kg'), set.label].join(' · '),
    webWidth: 460,
    listen: p,
    footerStretch: true,
    builder: (ctx) {
      final photo = set.of(p.value);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        PxTabs(labels: pxPoses, index: pxPoses.indexOf(p.value), fit: !ctx.isPhone, onPick: (i) => p.value = pxPoses[i]),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250),
            child: Semantics(
              button: photo != null,
              label: photo == null ? null : 'Open ${p.value} photo',
              child: Hover(
                onTap: photo == null || photo.image.isEmpty ? null : () => showPhotoViewer(ctx, [('${pxDm(set.date)} · ${p.value}', photo.image)], 0),
                builder: (_, _, _) => PxTile(
                  set: set,
                  pose: p.value,
                  aspect: 3 / 4,
                  figure: .38,
                  label: '${pxDm(set.date)} · ${p.value}',
                  noPhoto: 'No ${p.value.toLowerCase()} photo in this set',
                ),
              ),
            ),
          ),
        ),
      ]);
    },
    footer: pxFooter((ctx) => [
      CaButton('Close', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
      CaButton('Compare with start', icon: AppIcons.photo, onPressed: () {
        Navigator.of(ctx).pop();
        if (sets.length < 2) {
          showPxToast(context, 'Add a second photo set first', 'Then compare it with your first one');
          return;
        }
        final b = i <= 0 ? sets.last : sets[i];
        context.go('/progress/compare?a=${sets.first.id}&b=${b.id}&pose=${p.value}');
      }),
    ], flex: const [2, 3]),
  );
}

// ─────────────────────────────── Add photos

class _Ap extends ChangeNotifier {
  _Ap(this.pose);
  String pose;
  String? src, image, file;
  void set(void Function() f) {
    f();
    notifyListeners();
  }
}

const _poseHow = {
  'Front': 'Face the camera, arms relaxed by your sides',
  'Side': 'Turn to your right, stand tall',
  'Back': 'Back to the camera, feet hip-width apart',
};

/// Add photos sheet: one pose at a time into today's set. A second photo of the same pose replaces it.
Future<void> showAddPhotos(BuildContext context, ProgressController c, {String? pose}) {
  final d = c.data;
  final today = c.today;
  final todaySet = d?.sets.where((s) => DateUtils0.same(s.date, today)).firstOrNull;
  final s = _Ap(pose ?? 'Front');
  final coach = d?.coach ?? 'your coach';
  final kg = d?.last?.kg;

  Future<void> pick(BuildContext ctx, String name) async {
    final camera = name == 'Take photo' && ctx.isPhone;
    try {
      final x = await ImagePicker().pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
      if (x == null) return;
      final b = await x.readAsBytes();
      if (b.length > 10 * 1024 * 1024) {
        if (ctx.mounted) showToast(ctx, 'This photo is too big', sub: 'Photos can be up to 10 MB', kind: ToastKind.warn);
        return;
      }
      final mime = (x.mimeType ?? '').startsWith('image/') ? x.mimeType! : (x.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
      s.set(() {
        s.src = name;
        s.image = 'data:$mime;base64,${base64Encode(b)}';
        s.file = camera || x.name.isEmpty ? null : x.name.replaceFirst(RegExp('^scaled_'), '');
      });
    } catch (_) {
      if (ctx.mounted) showToast(ctx, 'Could not open the photos', sub: 'Allow photo access for the app in your phone settings', kind: ToastKind.warn);
    }
  }

  Future<void> save(BuildContext ctx) async {
    final img = s.image;
    if (img == null) {
      showToast(ctx, 'Take or choose a photo first', sub: 'Then save it to today’s set', kind: ToastKind.warn);
      return;
    }
    final p = s.pose;
    final replaced = todaySet?.has(p) ?? false;
    Navigator.of(ctx).pop();
    final Map<String, dynamic>? r;
    try {
      r = await c.addPhoto(p, img);
    } catch (e) {
      c.load();
      if (context.mounted) _failed(context, e);
      return;
    }
    if (!context.mounted) return;
    final id = (r?['id'] as num?)?.toInt();
    showToast(
      context,
      '$p photo ${replaced ? 'replaced' : 'added'}',
      sub: '${pxWdm(today)} · only you and $coach can see it',
      kind: ToastKind.ok,
      // Undo takes the new photo off again. A replaced photo is gone from the server, so it has no Undo.
      action: !replaced && id != null ? 'Undo' : null,
      onAction: !replaced && id != null ? () => c.deletePhoto(id) : null,
    );
  }

  return showAppSheet(
    context,
    title: 'Add photos',
    sub: 'Adds to today’s set · ${pxWdm(today)}${kg == null ? '' : ' · ${pxAmt(kg, 'kg')}'}',
    webWidth: 480,
    listen: s,
    footerStretch: true,
    builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      pxLbl('Pose'),
      Column(spacing: 8, children: [
        for (final n in pxPoses)
          _PoseOpt(name: n, how: _poseHow[n]!, on: s.pose == n, added: todaySet?.has(n) ?? false, onTap: () => s.set(() => s.pose = n)),
      ]),
      pxLbl('Photo'),
      Row(crossAxisAlignment: CrossAxisAlignment.center, spacing: 12, children: [
        SizedBox(
          width: 84,
          child: PxTile(
            set: s.image == null ? null : PxSet.local(id: 'new', label: '', date: today, kg: null, photos: [PxPhoto.local(s.pose, s.image!)]),
            pose: s.pose,
            aspect: 3 / 4,
            noPhoto: '',
          ),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
            for (final n in const ['Take photo', 'Choose from gallery'])
              Semantics(
                button: true,
                selected: s.src == n,
                child: Hover(
                  onTap: () => pick(ctx, n),
                  builder: (_, h, _) => Container(
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: s.src == n ? AppColors.text : (h ? AppColors.outlineHover : AppColors.white),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: s.src == n ? AppColors.text : AppColors.line),
                    ),
                    child: Text(n, style: AppText.s(13, W.w7, color: s.src == n ? AppColors.white : AppColors.text)),
                  ),
                ),
              ),
            Text(
              s.image == null ? 'No photo yet' : '${s.pose} photo ready · ${s.file ?? 'taken just now'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.s(12, W.w6, color: AppColors.muted),
            ),
          ]),
        ),
      ]),
      fdCap('Same spot, same light, in the morning before eating. Only you and $coach can see it.'),
    ]),
    footer: pxFooter((ctx) => [
      CaButton('Cancel', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
      Opacity(opacity: s.image == null ? .45 : 1, child: CaButton('Save photo', icon: AppIcons.check, onPressed: () => save(ctx))),
    ]),
  );
}

/// `dr-opt sm` with an "Added today" tag.
class _PoseOpt extends StatelessWidget {
  const _PoseOpt({required this.name, required this.how, required this.on, required this.added, required this.onTap});
  final String name, how;
  final bool on, added;
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
        child: Row(spacing: 12, children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(color: AppColors.white, shape: BoxShape.circle, border: Border.all(color: on ? AppColors.accent : AppColors.line2, width: on ? 5 : 1.5)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Row(spacing: 8, children: [
                Text(name, style: AppText.s(13.5, W.w7)),
                if (added)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(5)),
                    child: Text('Added today', style: AppText.s(10.5, W.w7, color: AppColors.text2)),
                  ),
              ]),
              Text(how, style: AppText.s(12.5, W.w4, color: AppColors.text2)),
            ]),
          ),
        ]),
      ),
    ),
  );
}

// ─────────────────────────────── A history day

Future<void> showHistoryDay(BuildContext context, PxDay day) {
  final types = day.entries.map((e) => e.type).toSet();
  final (go, path) = types.contains('workout')
      ? ('Open training', '/train')
      : types.contains('checkin')
          ? ('Open check-ins', '/checkins')
          : ('Open meal plan', '/food');
  final n = day.entries.length;
  return showAppSheet(
    context,
    title: pxWdm(day.date),
    sub: '${day.score == null ? '' : '${day.score}% adherence · '}$n ${n == 1 ? 'log' : 'logs'}',
    webWidth: 480,
    footerStretch: true,
    builder: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      for (final e in day.entries)
        Container(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PxEntryRow(e, first: true),
            if (e.detail.isNotEmpty) pxKvs(e.detail, topLine: true),
            if (e.note.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: AppColors.okBg, borderRadius: BorderRadius.circular(8)),
                child: Text(e.note, style: AppText.s(12.5, W.w6, color: AppColors.okText, h: 1.4)),
              ),
          ]),
        ),
    ]),
    footer: pxFooter((ctx) => [
      CaButton('Close', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
      CaButton(go, onPressed: () {
        Navigator.of(ctx).pop();
        context.go(path);
      }),
    ]),
  );
}

// ─────────────────────────────── Log measurements

class _Lm extends ChangeNotifier {
  _Lm(this.day, this.values);
  DateTime day;
  final Map<String, double> values; // what each stepper shows (last value to start)
  final touched = <String>{}; // only these are saved
  void set(String k, double v) {
    values[k] = v;
    touched.add(k);
    notifyListeners();
  }

  void pick(DateTime d) {
    day = d;
    notifyListeners();
  }
}

/// Log measurements sheet (Body tab): the coach's measurements, each starting at its last value. Only the numbers
/// that are changed are saved, so a day never gets copies of older measurements.
Future<void> showLogMeasures(BuildContext context, ProgressController c) {
  final d = c.data;
  final today = c.today;
  final metrics = d?.tracked ?? const <PxMetric>[];
  final lastOf = <String, (double, DateTime)>{};
  for (final m in d?.measures ?? const <PxMeasure>[]) {
    m.v.forEach((k, v) => lastOf[k] = (v, m.date));
  }
  const start = {'neck': 34.0, 'chest': 90.0, 'abdomen': 85.0, 'waist': 80.0, 'hips': 98.0, 'bicep_l': 29.0, 'bicep_r': 29.0, 'thigh_l': 55.0, 'thigh_r': 55.0, 'calf_l': 36.0, 'calf_r': 36.0, 'body_fat': 25.0};
  final s = _Lm(today, {for (final m in metrics) for (final k in m.keys) k: lastOf[k]?.$1 ?? start[k] ?? 50});
  final days = [for (var o = 0; o < 4; o++) today.subtract(Duration(days: o))];
  String side(String k) => k.endsWith('_l') ? 'Left' : (k.endsWith('_r') ? 'Right' : '');

  Future<void> save(BuildContext ctx) async {
    if (s.touched.isEmpty) {
      showToast(ctx, 'Change a number first', sub: 'Tap − / + or the number to type it', kind: ToastKind.warn);
      return;
    }
    final day = s.day;
    final values = {for (final k in s.touched) k: s.values[k]};
    final before = d?.measures.where((m) => DateUtils0.same(m.date, day)).firstOrNull?.v ?? const <String, double>{};
    final undo = {for (final k in s.touched) k: before[k]};
    Navigator.of(ctx).pop();
    try {
      await c.logMeasures(day, values);
    } catch (e) {
      c.load();
      if (context.mounted) _failed(context, e);
      return;
    }
    if (!context.mounted) return;
    final names = [for (final m in metrics) if (m.keys.any(s.touched.contains)) m.label.replaceAll(' L · R', '')];
    showToast(
      context,
      'Measurements saved',
      sub: '${names.take(3).join(', ')}${names.length > 3 ? ' +${names.length - 3}' : ''} · ${pxWdm(day)}',
      kind: ToastKind.ok,
      action: 'Undo',
      onAction: () => c.logMeasures(day, undo),
    );
  }

  return showAppSheet(
    context,
    title: 'Log measurements',
    sub: 'Relaxed, tape snug but not tight. Change only what you measured.',
    webWidth: 500,
    listen: s,
    footerStretch: true,
    builder: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      pxLbl('Date'),
      PxQuick(
        items: [for (final (i, x) in days.indexed) i == 0 ? 'Today' : (i == 1 ? 'Yesterday' : pxWdm(x))],
        on: days.indexWhere((x) => DateUtils0.same(x, s.day)),
        onPick: (i) => s.pick(days[i]),
      ),
      for (final m in metrics)
        Container(
          padding: const EdgeInsets.only(top: 8),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
            for (final k in m.keys)
              Row(spacing: 10, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                    Text(m.pair ? '${m.label.replaceAll(' L · R', '')} · ${side(k)}' : m.label,
                        style: AppText.s(13.5, W.w7, color: s.touched.contains(k) ? AppColors.text : AppColors.text2)),
                    Text(
                      s.touched.contains(k)
                          ? 'Will be saved'
                          : (lastOf[k] == null ? 'Not measured yet' : 'Last ${pxAmt(lastOf[k]!.$1, m.unit)} · ${pxDm(lastOf[k]!.$2)}'),
                      style: AppText.s(12, W.w4, color: s.touched.contains(k) ? AppColors.okText : AppColors.muted),
                    ),
                  ]),
                ),
                Opacity(
                  opacity: s.touched.contains(k) ? 1 : .6,
                  child: NumStepper(
                    value: s.values[k]!,
                    onChanged: (v) => s.set(k, v),
                    label: (v) => pxAmt(v, m.unit),
                    step: .5,
                    min: m.unit == '%' ? 3 : 10,
                    max: m.unit == '%' ? 70 : 300,
                    name: m.label,
                  ),
                ),
              ]),
          ]),
        ),
      if (metrics.isEmpty) fdCap('Your coach has not picked any measurements yet.'),
    ]),
    footer: pxFooter((ctx) => [
      CaButton('Cancel', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
      Opacity(opacity: s.touched.isEmpty ? .45 : 1, child: CaButton('Save', icon: AppIcons.check, onPressed: () => save(ctx))),
    ]),
  );
}
