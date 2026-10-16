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
import '../home/home_model.dart' show inNum, mealTime;
import 'food_model.dart';
import 'food_parts.dart';

/// Sheets of the Food page (board `ClientMealNutrition`): calories, the meal menu, swap, edit portions and the
/// details of a food-log row.

void fdError(BuildContext context, Object e) {
  if (!context.mounted) return;
  final m = e is ApiError ? e.message : 'Please try again';
  showToast(context, 'Could not save this', sub: m, kind: ToastKind.err);
}

/// A photo of the meal (phone: camera or gallery; web: a file), as a data URL. Null when nothing was picked.
Future<String?> pickMealPhoto(BuildContext context, String meal) async {
  ImageSource? src = ImageSource.gallery;
  if (context.isPhone) {
    src = null;
    await showActionSheet(context, title: '$meal photo', [
      MenuEntry('Take a photo', icon: AppIcons.camera, onTap: () => src = ImageSource.camera),
      MenuEntry('Choose from gallery', icon: AppIcons.photo, onTap: () => src = ImageSource.gallery),
    ]);
    if (src == null) return null;
  }
  try {
    final x = await ImagePicker().pickImage(source: src!, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
    if (x == null) return null;
    final b = await x.readAsBytes();
    if (b.length > 10 * 1024 * 1024) {
      if (context.mounted) showToast(context, 'This photo is too big', sub: 'Photos can be up to 10 MB', kind: ToastKind.warn);
      return null;
    }
    final mime = (x.mimeType ?? '').startsWith('image/') ? x.mimeType! : (x.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
    return 'data:$mime;base64,${base64Encode(b)}';
  } catch (_) {
    if (context.mounted) showToast(context, 'Could not open the photos', sub: 'Allow photo access for the app in your phone settings', kind: ToastKind.warn);
    return null;
  }
}

/// A square meal photo that opens full size.
class FdPhoto extends StatelessWidget {
  const FdPhoto(this.src, {super.key, required this.name, this.size = 34});
  final String src, name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final img = photoImage(src);
    return Semantics(
      button: true,
      label: 'Open $name photo',
      child: Hover(
        onTap: () => showPhotoViewer(context, [(name, src)], 0),
        builder: (_, h, _) => Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size > 40 ? 10 : 8),
            border: Border.all(color: h ? AppColors.accent : AppColors.line),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppColors.figBg),
          ),
          child: img == null
              ? const Center(child: AppIcon(AppIcons.photo, size: 15, color: AppColors.figText))
              : Image(
                  image: img,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const Center(child: AppIcon(AppIcons.photo, size: 15, color: AppColors.figText)),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────── Calories

/// "Today's calories" / "Mon's calories" / "Sun's plan".
String calHead(FoodDay d, DateTime today) {
  final wd = fdWd[d.date.weekday - 1];
  if (d.isToday) return 'Today’s calories';
  return d.date.isAfter(today) ? '$wd’s plan' : '$wd’s calories';
}

Future<void> showCaloriesSheet(BuildContext context, FoodController c) {
  final d = c.data!;
  final t = d.target, e = d.eaten, p = d.planned;
  final future = d.date.isAfter(c.today);
  final left = t[0] - e[0], over = left < 0;
  final ahead = d.meals.where((m) => m.open).fold(0, (a, m) => a + m.kcal);
  String g(double v, double tg) => '${v.round()} / ${tg.round()} g';
  final rows = future
      ? [('Planned', '${inNum(p[0])} kcal'), ('Protein', g(p[1], t[1])), ('Carbs', g(p[2], t[2])), ('Fat', g(p[3], t[3]))]
      : [
          ('Eaten', '${inNum(e[0])} kcal'),
          (d.isToday ? (over ? 'Over' : 'Left') : 'Against target', '${inNum(left.abs())} kcal${d.isToday ? '' : (over ? ' over' : ' under')}'),
          ('Still ahead', d.isToday ? '${inNum(ahead)} kcal' : '—'),
          ('Protein', g(e[1], t[1])),
          ('Carbs', g(e[2], t[2])),
          ('Fat', g(e[3], t[3])),
        ];
  return showAppSheet(
    context,
    title: calHead(d, c.today),
    sub: 'Target ${inNum(t[0])} kcal · set by ${d.coach}',
    webWidth: 440,
    footerStretch: true,
    builder: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      fdKv(rows),
      fdCap('Workout calories are not added back. Your plan already accounts for training.'),
    ]),
    footer: (ctx) => [CaButton('Got it', onPressed: () => Navigator.of(ctx).pop())],
  );
}

// ─────────────────────────────── Meal menu (☰)

Future<void> showMealMenu(
  BuildContext context,
  FoodController c,
  FMeal m, {
  required VoidCallback onSwap,
  required VoidCallback onEdit,
  required VoidCallback onSkip,
  required VoidCallback onPhoto,
  required VoidCallback onRemovePhoto,
}) {
  final swap = c.data!.allowSwaps && m.canSwap && m.open;
  return showAppSheet(
    context,
    title: '${m.name} · ${mealTime(m.timeRaw)}',
    sub: '${inNum(m.kcal)} kcal planned',
    webWidth: 440,
    builder: (ctx) {
      void go(VoidCallback f) {
        Navigator.of(ctx).pop();
        f();
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (swap) FdMenuItem(first: true, icon: AppIcons.swap, title: 'Swap a food', sub: 'Similar macros, different dish', onTap: () => go(onSwap)),
        FdMenuItem(first: !swap, icon: AppIcons.edit, title: 'Edit portions', sub: 'Change grams, pieces or katori', onTap: () => go(onEdit)),
        if (m.logged)
          FdMenuItem(
            icon: AppIcons.camera,
            title: m.photo == null ? 'Add a photo' : 'Change photo',
            sub: m.photo == null ? 'A picture of what you ate' : 'Take or pick another picture',
            onTap: () => go(onPhoto),
          ),
        if (m.logged && m.photo != null) FdMenuItem(icon: AppIcons.trash, title: 'Remove photo', sub: 'The meal stays logged', danger: true, onTap: () => go(onRemovePhoto)),
        FdMenuItem(icon: AppIcons.search, title: 'Log something different', sub: 'Ate outside the plan? No stress', onTap: () => go(() => context.go('/food/log?meal=${Uri.encodeComponent(m.name)}'))),
        if (!m.skipped) FdMenuItem(icon: AppIcons.close, title: 'Skip meal', sub: 'It will not count towards today', danger: true, onTap: () => go(onSkip)),
      ]);
    },
  );
}

// ─────────────────────────────── Swap

/// "100 g" or "1 plate" when the grams are a neat number of one of the food's units.
String amtGrams(Map<String, dynamic> food, num grams) {
  for (final u in (food['units'] as List? ?? [])) {
    final ug = (u['grams'] as num?)?.toDouble() ?? 0;
    if (ug <= 0) continue;
    final q = grams / ug;
    if (q >= .5 && ((q * 2).roundToDouble() - q * 2).abs() < .04) return amtOf('${u['name']}', (q * 2).round() / 2);
  }
  return '${grams.round()} g';
}

class _Swap extends ChangeNotifier {
  _Swap(this.meal, this.item);
  final FMeal meal;
  FItem item;
  Map<String, dynamic>? data;
  String? error;
  String? pick; // food id; the planned food's id = back to plan
  bool busy = false;

  String get planned => '${data?['planned']?['id'] ?? ''}';
  String get current => item.food;
  bool get changed => data != null && pick != null && pick != current;

  void choose(String id) {
    pick = id;
    notifyListeners();
  }

  Future<void> load(FoodController c) async {
    data = null;
    error = null;
    notifyListeners();
    try {
      data = await c.swaps(item.item);
      pick = current;
    } on ApiError catch (e) {
      error = e.message;
    }
    notifyListeners();
  }
}

Future<void> showSwapSheet(BuildContext context, FoodController c, FMeal m, FItem it) {
  final s = _Swap(m, it)..load(c);
  final coach = c.data!.coach;
  List<double> mac(Map<String, dynamic> f) {
    final g = (f['grams'] as num? ?? 0).toDouble() / 100;
    return [for (final k in ['kcal', 'protein', 'carbs', 'fat']) (f[k] as num? ?? 0).toDouble() * g];
  }

  String line(Map<String, dynamic> f) {
    final x = mac(f);
    return '${amtGrams(f, f['grams'] as num? ?? 0)} · ${inNum(x[0])} kcal · ${x[1].round()} g P';
  }

  return showAppSheet(
    context,
    listen: s,
    webWidth: 480,
    footerStretch: true,
    titleOf: () => 'Swap from ${m.name}',
    subOf: () {
      final p = s.data?['planned'] as Map<String, dynamic>?;
      return p == null ? s.item.name : '${p['name']} · ${line(p)}';
    },
    builder: (ctx) {
      final d = s.data;
      final foods = m.items.where((i) => i.swaps > 0).toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        if (foods.length > 1)
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final f in foods)
              FdChip(f.name, on: f.item == s.item.item, onTap: () {
                if (f.item == s.item.item) return;
                s.item = f;
                s.load(c);
              }),
          ]),
        Row(spacing: 6, children: [
          const AppIcon(AppIcons.check, size: 14, color: AppColors.okText, stroke: 2.6),
          Expanded(child: Text('Approved by $coach · portions matched to your plan', style: AppText.s(12.5, W.w6, color: AppColors.okText))),
          const Tooltip(
            message: 'Each option is portioned to match the planned food. Match % compares calories, protein and fat.',
            child: AppIcon(AppIcons.info, size: 15, color: AppColors.muted),
          ),
        ]),
        if (d == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: s.error == null
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                  : Text(s.error!, style: AppText.s(13, W.w5, color: AppColors.muted)),
            ),
          )
        else
          Column(spacing: 6, children: [
            for (final o in [d['planned'] as Map<String, dynamic>, ...[for (final x in d['options'] as List) x as Map<String, dynamic>]])
              _SwapOpt(
                name: '${o['name']}',
                sub: line(o),
                planned: o == d['planned'],
                match: o['match'] as num?,
                on: s.pick == '${o['id']}',
                onTap: () => s.choose('${o['id']}'),
              ),
          ]),
        FdElse('Search any other food', icon: AppIcons.search, small: true, onTap: () {
          Navigator.of(ctx).pop();
          context.go('/food/log?meal=${Uri.encodeComponent(m.name)}');
        }),
      ]);
    },
    footer: (ctx) {
      final p = s.data?['planned'] as Map<String, dynamic>?;
      final back = s.pick == s.planned && s.current != s.planned;
      return [
        Text('Applies to today’s plan only', textAlign: TextAlign.center, style: AppText.s(12, W.w6, color: AppColors.muted)),
        CaButton(
          back && p != null ? 'Back to ${p['name']}' : 'Swap',
          icon: AppIcons.swap,
          dimmed: !s.changed,
          loading: s.busy,
          onPressed: () async {
            if (!s.changed) return;
            final d = s.data!;
            final from = '${p?['name'] ?? s.item.name}';
            final to = back ? null : [for (final x in d['options'] as List) x as Map<String, dynamic>].where((x) => '${x['id']}' == s.pick).firstOrNull;
            Navigator.of(ctx).pop();
            try {
              await c.meal(m, 'swap', {'item': s.item.item, 'food': back ? null : s.pick});
              if (!context.mounted) return;
              if (to != null) {
                final x = mac(to);
                showToast(context, 'Swapped: $from → ${to['name']}', sub: '${amtGrams(to, to['grams'] as num? ?? 0)} · ${inNum(x[0])} kcal · today only', kind: ToastKind.ok);
              } else {
                showToast(context, '$from is back in your ${m.name}', sub: 'Swap removed', kind: ToastKind.info);
              }
            } catch (e) {
              if (context.mounted) fdError(context, e);
            }
          },
        ),
      ];
    },
  );
}

/// `dr-opt` with a radio, a Planned tag and a match %.
class _SwapOpt extends StatelessWidget {
  const _SwapOpt({required this.name, required this.sub, required this.planned, required this.match, required this.on, required this.onTap});
  final String name, sub;
  final bool planned, on;
  final num? match;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    child: Hover(
      onTap: onTap,
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
            decoration: BoxDecoration(color: AppColors.white, shape: BoxShape.circle, border: Border.all(color: on ? AppColors.accent : AppColors.line2, width: on ? 5 : 1)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7))),
                if (planned) fdTag('Planned'),
              ]),
              Text(sub, style: AppText.s(12.5, W.w4, color: AppColors.text2)),
            ]),
          ),
          if (!planned && match != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: AppColors.okBg, borderRadius: BorderRadius.circular(99)),
              child: Text('$match% match', style: AppText.s(11.5, W.w7, color: AppColors.okText)),
            ),
        ]),
      ),
    ),
  );
}

// ─────────────────────────────── Edit portions

double portionStep(FItem it) => it.unit == 'g' ? 10 : (it.quantity != it.quantity.roundToDouble() || it.unit.contains('roti') ? .5 : 1);

Future<void> showPortionsSheet(BuildContext context, FoodController c, FMeal m) {
  final q = ValueNotifier<Map<int, double>>({for (final i in m.items) i.item: i.quantity});
  List<double> now() {
    final t = [0.0, 0.0, 0.0, 0.0];
    for (final i in m.items) {
      final x = i.at(q.value[i.item]!);
      for (var k = 0; k < 4; k++) {
        t[k] += x[k];
      }
    }
    return t;
  }

  return showAppSheet(
    context,
    listen: q,
    title: 'Edit portions · ${m.name}',
    sub: '${mealTime(m.timeRaw)} · ${inNum(m.kcal)} kcal now',
    webWidth: 500,
    footerStretch: true,
    builder: (_) {
      final n = now();
      final diff = (n[0] - m.kcal).round();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        Column(children: [
          for (final (k, it) in m.items.indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(border: k == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
              child: Row(spacing: 10, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(it.name, style: AppText.s(14, W.w7)),
                    Builder(builder: (_) {
                      final x = it.at(q.value[it.item]!);
                      return Text('${inNum(x[0])} kcal · ${x[1].round()} g P', style: AppText.s(12, W.w4, color: AppColors.muted));
                    }),
                  ]),
                ),
                NumStepper(
                  value: q.value[it.item]!,
                  step: portionStep(it),
                  min: portionStep(it) == 10 ? 5 : .5,
                  max: it.unit == 'g' ? 2000 : 50,
                  decimals: it.unit != 'g',
                  name: '${it.name} amount',
                  label: (v) => amtOf(it.unit, v),
                  onChanged: (v) => q.value = {...q.value, it.item: v},
                ),
              ]),
            ),
        ]),
        fdTotal(mline(n[0], n[1], n[2], n[3]), diff == 0 ? 'Same as now' : '${diff > 0 ? '+' : '−'}${diff.abs()} kcal'),
        fdCap('Calories and macros follow your portions. This changes today only.'),
      ]);
    },
    footer: (ctx) => [
      Row(spacing: 8, children: [
        Expanded(child: CaButton('Cancel', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop())),
        Expanded(
          child: CaButton('Save portions', onPressed: () async {
            final before = {for (final i in m.items) '${i.item}': i.quantity};
            final n = now();
            Navigator.of(ctx).pop();
            try {
              await c.meal(m, 'portions', {'portions': {for (final e in q.value.entries) '${e.key}': e.value}});
              if (!context.mounted) return;
              showToast(context, '${m.name} portions saved', sub: 'Now ${inNum(n[0])} kcal · ${n[1].round()} g protein', kind: ToastKind.ok, action: 'Undo', onAction: () {
                final again = c.data?.meals.where((x) => x.id == m.id).firstOrNull;
                if (again != null) c.meal(again, 'portions', {'portions': before}).catchError((_) {});
              });
            } catch (e) {
              if (context.mounted) fdError(context, e);
            }
          }),
        ),
      ]),
    ],
  );
}

// ─────────────────────────────── Food-log row details

/// One row of the food log: a whole plan meal, or one food added outside it.
class FdLogRow {
  FdLogRow.meal(FMeal this.meal, List<FEntry> rows)
    : entry = null,
      time = meal.loggedAt ?? (rows.isEmpty ? DateTime.now() : rows.first.time),
      title = meal.name,
      sub = meal.foods,
      kcal = rows.isEmpty ? meal.kcal : rows.fold(0, (a, e) => a + e.kcal),
      photo = meal.photo;
  FdLogRow.entry(FEntry this.entry)
    : meal = null,
      time = entry.time,
      title = entry.name,
      sub = '${entry.mealName}${entry.otherTime ? ' · other time' : ''} · ${entry.amount}${entry.source == 'off_plan' ? ' · off-plan${entry.reason.isEmpty ? '' : ' (${entry.reason.toLowerCase()})'}' : ''}',
      kcal = entry.kcal,
      photo = entry.photo;
  final FMeal? meal;
  final FEntry? entry;
  final DateTime time;
  final String title, sub;
  final int kcal;
  final String? photo;
}

/// The food log of one day: every plan meal as one row, every other food on its own, by time.
List<FdLogRow> logRows(FoodDay d) {
  final rows = <FdLogRow>[];
  for (final m in d.meals) {
    if (m.logged) rows.add(FdLogRow.meal(m, d.log.where((e) => e.meal == m.id && e.fromPlan).toList()));
  }
  for (final e in d.log) {
    if (e.fromPlan && e.meal != null && d.meals.any((m) => m.id == e.meal)) continue;
    rows.add(FdLogRow.entry(e));
  }
  rows.sort((a, b) => a.time.compareTo(b.time));
  return rows;
}

Future<void> showEntrySheet(BuildContext context, FoodController c, FdLogRow r, {required VoidCallback onEdit, required VoidCallback onUneat}) {
  final d = c.data!;
  final today = d.isToday;
  final m = r.meal, e = r.entry;
  final mac = m != null ? [m.kcal.toDouble(), m.protein, m.carbs, m.fat] : [e!.kcal.toDouble(), e.protein, e.carbs, e.fat];
  final tg = d.target[0];
  final where = e?.otherTime ?? false ? 'other time, outside the plan' : switch (e?.source) { 'off_plan' => 'outside the plan', 'quick_add' => 'quick add', _ => 'extra food' };
  final sub = m != null
      ? 'Logged ${fdClock(r.time)} · planned for ${mealTime(m.timeRaw)} · from your plan'
      : 'Logged ${fdClock(r.time)} · ${e!.mealName} · $where';
  Widget food(String n, String amt, int k, bool first) => Container(
    padding: const EdgeInsets.symmetric(vertical: 7),
    decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: AppColors.line))),
    child: Row(spacing: 8, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(n, style: AppText.s(13.5, W.w7)),
          Text(amt, style: AppText.s(12, W.w4, color: AppColors.muted)),
        ]),
      ),
      Text('${inNum(k)} kcal', style: AppText.s(12, W.w7, color: AppColors.text2)),
    ]),
  );
  return showAppSheet(
    context,
    title: r.title,
    sub: sub,
    webWidth: 480,
    builder: (ctx) {
      void go(VoidCallback f) {
        Navigator.of(ctx).pop();
        f();
      }

      final items = <Widget>[
        if (m != null && today) ...[
          FdMenuItem(first: true, icon: AppIcons.edit, title: 'Edit portions', sub: 'Change grams, pieces or katori', onTap: () => go(onEdit)),
          FdMenuItem(icon: AppIcons.close, title: 'Mark as not eaten', sub: 'Removes it from today’s totals', danger: true, onTap: () => go(onUneat)),
        ],
        if (e != null && today)
          FdMenuItem(
            first: true,
            icon: AppIcons.plus,
            title: 'Log more to ${e.mealName}',
            sub: 'Search and add another food',
            onTap: () => go(() => context.go('/food/log?meal=${Uri.encodeComponent(e.mealName)}${e.otherTime ? '&at=${e.time.hour}:${'${e.time.minute}'.padLeft(2, '0')}' : ''}')),
          ),
        if (e != null && today)
          FdMenuItem(
            icon: AppIcons.trash,
            title: 'Delete entry',
            sub: 'You can undo this',
            danger: true,
            onTap: () => go(() async {
              await c.deleteEntry(e);
              if (!context.mounted) return;
              showToast(context, 'Entry deleted', sub: '${e.name} · ${inNum(e.kcal)} kcal', kind: ToastKind.del, action: 'Undo', onAction: () => c.restore(e).catchError((_) {}));
            }),
          ),
      ];
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (m != null)
            for (final (i, it) in m.items.indexed) food(it.name, it.amount + (it.swappedFrom.isEmpty ? '' : ' · swapped from ${it.swappedFrom}'), it.kcal, i == 0)
          else
            food(e!.name, e.amount, e.kcal, true),
        ]),
        if (r.photo != null)
          Row(spacing: 10, children: [
            FdPhoto(r.photo!, name: r.title, size: 56),
            Expanded(child: Text('Your photo of this meal · tap to open', style: AppText.s(12.5, W.w6, color: AppColors.muted))),
          ]),
        fdKv([
          ('Calories', '${inNum(mac[0])} kcal'),
          ('Protein', '${mac[1].round()} g'),
          ('Carbs', '${mac[2].round()} g'),
          ('Fat', '${mac[3].round()} g'),
          if (tg > 0) ('Share of ${today ? 'today' : 'the day'}', '${(mac[0] / tg * 100).round()}% of ${inNum(tg)} kcal'),
        ]),
        if (items.isNotEmpty) Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items),
      ]);
    },
  );
}
