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
import '../../../core/widgets/tooltip.dart';

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
  // One entry per period (Gautam 2026-10-16): no date to pick. This period's entry, or a new one for today.
  final entry = d?.measureEntry;
  if (entry != null) s.day = entry;

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
      _measureWhen(entry, today, d?.nextMeasure),
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
        PxTabs(labels: pxPoses, index: pxPoses.indexOf(p.value), onPick: (i) => p.value = pxPoses[i]),
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
        // Her own set can change on the day it was added, never after (Probid 2026-10-30).
        if (set.editableOn(c.today))
          Row(spacing: 8, children: [
            Expanded(
              child: CaButton(photo == null ? 'Add ${p.value.toLowerCase()} photo' : 'Change photo', kind: CaBtnKind.out, small: true, icon: AppIcons.camera, onPressed: () {
                Navigator.of(ctx).pop();
                showAddPhotos(context, c, pose: p.value);
              }),
            ),
            if (photo != null && photo.id > 0)
              Expanded(
                child: CaButton('Delete photo', kind: CaBtnKind.out, small: true, icon: AppIcons.trash, onPressed: () async {
                  final ok = await confirmAction(ctx, title: 'Delete this photo?', body: '${p.value} photo · ${pxDm(set.date)}. You can add a new one today.', confirm: 'Delete', danger: true);
                  if (!ok || !ctx.mounted) return;
                  Navigator.of(ctx).pop();
                  try {
                    await c.deletePhoto(photo.id);
                    if (context.mounted) showToast(context, '${p.value} photo deleted', sub: 'You can add a new one today', kind: ToastKind.del);
                  } catch (e) {
                    if (context.mounted) _failed(context, e);
                  }
                }),
              ),
          ])
        else if (!set.fromCheckin)
          fdCap('Photos can be changed only on the day they were added.', align: TextAlign.center),
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

/// A photo picked in the Add photos sheet, not saved yet.
typedef _Pick = ({String src, String image, String? file});

class _Ap extends ChangeNotifier {
  _Ap(this.pose);
  String pose;

  /// One picked photo per pose: each tab keeps its own (Probid 2026-10-30).
  final picks = <String, _Pick>{};
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

/// Add photos sheet: Front / Side / Back tabs, each with its own photo, all saved into today's set with one tap
/// (Probid 2026-10-30: no adding them one by one). A pose already in today's set is replaced.
Future<void> showAddPhotos(BuildContext context, ProgressController c, {String? pose}) {
  final d = c.data;
  final today = c.today;
  final todaySet = d?.sets.where((s) => DateUtils0.same(s.date, today)).firstOrNull;
  final s = _Ap(pose ?? pxPoses.firstWhere((p) => !(todaySet?.has(p) ?? false), orElse: () => 'Front'));
  final coach = d?.coach ?? 'your coach';
  Future<void> pick(BuildContext ctx, String name) async {
    final camera = name == 'Take photo' && ctx.isPhone;
    final p = s.pose;
    try {
      final x = await ImagePicker().pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
      if (x == null) return;
      final b = await x.readAsBytes();
      if (b.length > 10 * 1024 * 1024) {
        if (ctx.mounted) showToast(ctx, 'This photo is too big', sub: 'Photos can be up to 10 MB', kind: ToastKind.warn);
        return;
      }
      final mime = (x.mimeType ?? '').startsWith('image/') ? x.mimeType! : (x.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
      // The photo goes into the tab that was open when she picked it.
      s.set(() => s.picks[p] = (
        src: name,
        image: 'data:$mime;base64,${base64Encode(b)}',
        file: camera || x.name.isEmpty ? null : x.name.replaceFirst(RegExp('^scaled_'), ''),
      ));
    } catch (_) {
      if (ctx.mounted) showToast(ctx, 'Could not open the photos', sub: 'Allow photo access for the app in your phone settings', kind: ToastKind.warn);
    }
  }

  Future<void> save(BuildContext ctx) async {
    if (s.picks.isEmpty) {
      showToast(ctx, 'Take or choose a photo first', sub: 'Then save it to today’s set', kind: ToastKind.warn);
      return;
    }
    final poses = [for (final p in pxPoses) if (s.picks.containsKey(p)) p];
    final replaced = [for (final p in poses) if (todaySet?.has(p) ?? false) p];
    Navigator.of(ctx).pop();
    final added = <int>[];
    for (final p in poses) {
      try {
        final r = await c.addPhoto(p, s.picks[p]!.image);
        final id = (r?['id'] as num?)?.toInt();
        if (id != null && !replaced.contains(p)) added.add(id);
      } catch (e) {
        c.load();
        if (context.mounted) _failed(context, e);
        return;
      }
    }
    if (!context.mounted) return;
    final title = poses.length == 1
        ? '${poses.first} photo ${replaced.isEmpty ? 'added' : 'replaced'}'
        : '${poses.length} photos ${replaced.isEmpty ? 'added' : 'saved'}';
    showToast(
      context,
      title,
      sub: '${pxWdm(today)} · only you and $coach can see ${poses.length == 1 ? 'it' : 'them'}',
      kind: ToastKind.ok,
      // Undo takes the new photos off again. A replaced photo is gone from the server, so it has no Undo.
      action: replaced.isEmpty && added.isNotEmpty ? 'Undo' : null,
      onAction: replaced.isEmpty && added.isNotEmpty ? () => c.deletePhotos(added) : null,
    );
  }

  return showAppSheet(
    context,
    title: 'Add photos',
    sub: 'Adds to today’s set · ${pxWdm(today)}',
    webWidth: 480,
    listen: s,
    footerStretch: true,
    builder: (ctx) {
      final p = s.pose;
      final mine = s.picks[p];
      final had = todaySet?.of(p);
      final shown = mine != null
          ? PxSet.local(id: 'new', label: '', date: today, kg: null, photos: [PxPhoto.local(p, mine.image)])
          : (had != null ? todaySet : null);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        PxTabs(
          fit: false,
          labels: [for (final n in pxPoses) s.picks.containsKey(n) ? '$n ✓' : n],
          index: pxPoses.indexOf(p),
          onPick: (i) => s.set(() => s.pose = pxPoses[i]),
        ),
        Text(_poseHow[p]!, style: AppText.s(12.5, W.w4, color: AppColors.text2)),
        Row(crossAxisAlignment: CrossAxisAlignment.center, spacing: 12, children: [
          SizedBox(width: 96, child: PxTile(set: shown, pose: p, aspect: 3 / 4, noPhoto: '')),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
              for (final n in const ['Take photo', 'Choose from gallery'])
                Semantics(
                  button: true,
                  selected: mine?.src == n,
                  child: Hover(
                    onTap: () => pick(ctx, n),
                    builder: (_, h, _) => Container(
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: mine?.src == n ? AppColors.text : (h ? AppColors.outlineHover : AppColors.white),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: mine?.src == n ? AppColors.text : AppColors.line),
                      ),
                      child: Text(n, style: AppText.s(13, W.w7, color: mine?.src == n ? AppColors.white : AppColors.text)),
                    ),
                  ),
                ),
              Row(children: [
                Expanded(
                  child: CutText(
                    mine != null
                        ? '$p photo ready · ${mine.file ?? 'taken just now'}'
                        : had != null
                        ? 'Added today · a new one replaces it'
                        : 'No photo yet',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.s(12, W.w6, color: AppColors.muted),
                  ),
                ),
                if (mine != null)
                  Hover(
                    onTap: () => s.set(() => s.picks.remove(p)),
                    builder: (_, h, _) => Text('Remove', style: AppText.s(12, W.w7, color: h ? AppColors.redHover : AppColors.red)),
                  ),
              ]),
            ]),
          ),
        ]),
        fdCap('Same spot, same light, in the morning before eating. Only you and $coach can see it.'),
      ]);
    },
    footer: pxFooter((ctx) => [
      CaButton('Cancel', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
      Opacity(
        opacity: s.picks.isEmpty ? .45 : 1,
        child: CaButton(s.picks.length > 1 ? 'Save ${s.picks.length} photos' : 'Save photo', icon: AppIcons.check, onPressed: () => save(ctx)),
      ),
    ]),
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

}

/// Which entry this log goes to: "This period's entry · Wed, 14 Oct" (changes it) or "New entry · today".
Widget _measureWhen(DateTime? entry, DateTime today, DateTime? due) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(10)),
  child: Row(spacing: 10, children: [
    Icon(Icons.event_note_outlined, size: 18, color: AppColors.text2),
    Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
        Text(entry == null ? 'New entry · Today, ${pxWdm(today)}' : 'This period · logged ${pxWdm(entry)}', style: AppText.s(13, W.w7)),
        Text(
          entry == null
              ? 'One entry every period. You can change it until the next one is due.'
              : 'Changes update this entry${due == null ? '' : ' · next one due ${pxWdm(due)}'}',
          style: AppText.s(12, W.w4, color: AppColors.muted),
        ),
      ]),
    ),
  ]),
);

/// The last entries, newest first, each with its date: "Wed, 14 Oct · Chest 91, Waist 79.5, Hips 99 +3".
Widget _pastEntries(List<PxMeasure> all, List<PxMetric> metrics) {
  final rows = all.reversed.take(4).toList();
  String sum(PxMeasure m) {
    final bits = [for (final x in metrics) if (m.of(x) != null) '${x.label.replaceAll(' L · R', '')} ${x.amt(m.of(x)!)}'];
    return bits.isEmpty ? '${m.v.length} measured' : '${bits.take(3).join(', ')}${bits.length > 3 ? ' +${bits.length - 3}' : ''}';
  }

  return Container(
    padding: const EdgeInsets.only(top: 10),
    decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      pxLbl('Your entries'),
      for (final m in rows)
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          SizedBox(width: 92, child: Text(pxWdm(m.date), style: AppText.s(12.5, W.w7))),
          Expanded(child: Text(sum(m), style: AppText.s(12.5, W.w4, color: AppColors.text2))),
        ]),
    ]),
  );
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
  // One entry per period (Gautam 2026-10-16): no date to pick. This period's entry, or a new one for today.
  final entry = d?.measureEntry;
  if (entry != null) s.day = entry;
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
      _measureWhen(entry, today, d?.nextMeasure),
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
      if ((d?.measures ?? const []).isNotEmpty) _pastEntries(d!.measures, metrics),
    ]),
    footer: pxFooter((ctx) => [
      CaButton('Cancel', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
      Opacity(opacity: s.touched.isEmpty ? .45 : 1, child: CaButton('Save', icon: AppIcons.check, onPressed: () => save(ctx))),
    ]),
  );
}
