import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/media.dart' show mediaClock, playVideoFull, showImageViewer;
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import 'cp_common.dart';
import 'cp_logs.dart' show cpWeeklyLine;
import 'cp_logs_parts.dart';
import 'cp_model.dart';
import '../../../core/widgets/tooltip.dart';

// The log drawer each Logs row opens (board `logd`): a workout with every set, a day's meals with macros, a daily
// or weekly check-in's answers and photos (weekly ones still to review can be replied to and marked reviewed,
// like the dashboard's review drawer), or a day's habit / supplement ticks. Previous / Next step through the rows
// of the page.

/// "her" / "his" / "their" from the client's gender (board copy says "her meals").
String cpTheir(CpController c) => switch ('${c.detail['gender']}') { 'female' => 'her', 'male' => 'his', _ => 'their' };

class _Nav extends ChangeNotifier {
  _Nav(this.rows, this.i);
  final List<Map> rows;
  int i;
  final cache = <int, Future<Map>>{};
  Map get r => rows[i];
  void step(int d) {
    i = (i + d + rows.length) % rows.length;
    notifyListeners();
  }

  void changed() => notifyListeners();
}

Future<void> openCpLog(
  BuildContext context,
  CpController c, {
  required String slot,
  required List<Map> rows,
  required int index,
  List? columns,
  required VoidCallback onChanged,
}) async {
  if (rows.isEmpty) return;
  final nav = _Nav([for (final r in rows) Map.of(r)], index);
  var dirty = false;
  void changed() {
    dirty = true;
    nav.changed();
  }

  const subs = {
    'workouts': 'Workout log',
    'meals': 'Meal log',
    'daily': 'Daily check-in',
    'weekly': 'Weekly check-in',
    'habits': 'Habit log',
    'supps': 'Supplement log',
  };
  String title() {
    final r = nav.r;
    return switch (slot) {
      'workouts' => '${cpDay(r['date'])} · ${'${r['name']}'.isEmpty ? 'Workout' : r['name']}',
      'meals' => '${cpDay(r['date'])} · meals',
      'daily' => '${cpDay(r['date'])} · daily check-in',
      'weekly' => 'Week ${r['week']} check-in · ${cpDay(r['date'])}',
      'habits' => '${cpDay(r['date'])} · habits',
      _ => '${cpDay(r['date'])} · supplements',
    };
  }

  String note() {
    final r = nav.r;
    return switch (slot) {
      'workouts' => r['id'] == null ? 'Not logged' : (r['status'] == 'in_progress' ? 'Still in progress' : ''),
      'meals' => 'Photos are added by ${c.first} when they log a meal',
      'daily' => r['id'] == null ? 'Not sent' : 'Sent at ${cpTime(r['sent_at'])}',
      'weekly' => r['id'] == null ? 'Not sent' : 'Sent ${cpDay(r['sent_at'] ?? r['date'])}, ${cpTime(r['sent_at'])}',
      _ => 'Ticked by ${c.first} in the app',
    };
  }

  Future<Map> load(String path, [Map<String, dynamic>? q]) => nav.cache[nav.i] ??= Services.api.get<Map>(path, query: q);

  Widget body(BuildContext ctx) {
    final r = nav.r;
    return KeyedSubtree(
      key: ValueKey(nav.i),
      child: switch (slot) {
        'workouts' => r['id'] == null ? _missedWorkout(r) : _future(load('clients/${c.id}/workouts/${r['id']}/'), (d) => _workout(c, r, d, nav)),
        'meals' => _future(load('clients/${c.id}/food/', {'date': '${r['date']}'}), (d) => _meals(ctx, c, r, d)),
        'daily' => _daily(c, r, nav, changed),
        'weekly' => r['id'] == null
            ? const EmptyState('Not sent', sub: 'No weekly check-in came for this week.', icon: AppIcons.clipboard)
            : _future(load('checkins/${r['id']}/'), (d) => _weekly(ctx, c, r, d, nav, changed)),
        _ => _ticks(r),
      },
    );
  }

  List<Widget> actions(BuildContext ctx) {
    final r = nav.r;
    final phone = ctx.isPhone;
    final close = AppButton('Close', expand: phone, onPressed: () => Navigator.of(ctx).pop());
    if (slot == 'weekly' && r['id'] != null && r['status'] == 'to_review') {
      return [
        if (!phone) close,
        AppButton.primary('Mark reviewed', icon: AppIcons.check, expand: phone, onPressed: () => _review(ctx, c, nav, '', changed)),
      ];
    }
    return [close];
  }

  await showCpLogDrawer<void>(
    context,
    listen: nav,
    title: title,
    sub: () => subs[slot] ?? '',
    body: body,
    note: note,
    actions: actions,
    onPrev: nav.rows.length > 1 ? () => nav.step(-1) : null,
    onNext: nav.rows.length > 1 ? () => nav.step(1) : null,
  );
  nav.dispose();
  if (dirty) onChanged();
}

Widget _future(Future<Map> f, Widget Function(Map) done) => FutureBuilder<Map>(
      future: f,
      builder: (_, s) {
        if (s.hasError) {
          return EmptyState('Could not open this', sub: s.error is ApiError ? (s.error as ApiError).message : null);
        }
        if (!s.hasData) return const CpLoading();
        return done(s.data!);
      },
    );

// ─────────────────────────────── Workout

String _setText(Map s) {
  final kg = double.tryParse('${s['weight_kg'] ?? ''}');
  final reps = s['reps'], secs = s['seconds'], km = double.tryParse('${s['distance_km'] ?? ''}');
  final bits = <String>[];
  if (km != null && km > 0) bits.add('${cpOne(km)} km');
  if (secs != null && (secs as num) > 0) bits.add(secs >= 120 ? '${(secs / 60).round()} min' : '$secs s');
  if (reps != null && (reps as num) > 0) {
    final bw = s['is_bodyweight'] == true;
    bits.add(kg != null && kg > 0 ? '${bw ? 'Body + ' : ''}${cpOne(kg)} kg × $reps' : (bw ? 'Body × $reps' : '× $reps'));
  } else if (kg != null && kg > 0) {
    bits.add('${cpOne(kg)} kg');
  }
  return bits.isEmpty ? 'Set ${s['set_number']}' : bits.join(' · ');
}

Widget _num(int i, Tone tone) => Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tone == Tone.ok ? AppColors.okBg : (tone == Tone.warn ? AppColors.warnBg : AppColors.sub), shape: BoxShape.circle),
      child: Text('$i', style: AppText.s(11.5, W.w8, color: tone == Tone.ok ? AppColors.okText : (tone == Tone.warn ? AppColors.warnText : AppColors.muted))),
    );

Widget _chip(String t, bool ok) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: ok ? AppColors.okBg : AppColors.badBg, borderRadius: BorderRadius.circular(5)),
      child: Text(t, style: AppText.s(12, W.w6, color: ok ? AppColors.okText : AppColors.badText, tabular: true)),
    );

Widget _exRow(int i, String name, Tone tone, Widget sets, String sum, {bool last = false}) => Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(spacing: 12, children: [
        _num(i, tone),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 5, children: [
            Text(name, style: AppText.s(13.5, W.w7)),
            sets,
          ]),
        ),
        Text(sum, style: AppText.cap),
      ]),
    );

Widget _missedWorkout(Map r) {
  final planned = [for (final p in (r['planned'] as List? ?? const [])) '$p'];
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    CpKpis([('Status', 'Missed'), ('Planned', '${planned.length} exercise${planned.length == 1 ? '' : 's'}'), ('Sets', '—'), ('Time', '—')]),
    for (final (i, p) in planned.indexed) _exRow(i + 1, p, Tone.neutral, Text('Not logged', style: AppText.cap), '', last: i == planned.length - 1),
    if (planned.isEmpty) const EmptyState('Nothing was logged this day'),
  ]);
}

Widget _workout(CpController c, Map r, Map d, _Nav nav) {
  final sets = [for (final s in (d['sets'] as List? ?? const [])) s as Map]..retainWhere((s) => s['is_warmup'] != true);
  final groups = <String, List<Map>>{};
  for (final s in sets) {
    groups.putIfAbsent('${s['exercise']}', () => []).add(s);
  }
  // Exercises in the order they were done.
  final order = groups.entries.toList()
    ..sort((a, b) {
      DateTime t(List<Map> xs) => xs.map((s) => cpParse(s['done_at'])).whereType<DateTime>().fold(DateTime(9999), (m, x) => x.isBefore(m) ? x : m);
      return t(a.value).compareTo(t(b.value));
    });
  final vol = sets.fold<double>(0, (a, s) => a + ((s['volume'] as num?)?.toDouble() ?? 0));
  final secs = (d['duration_seconds'] as num?)?.toInt() ?? 0;
  final note = '${d['note'] ?? ''}'.trim();
  final total = (d['sets_planned'] as num?)?.toInt() ?? 0;
  final videos = [for (final v in (d['form_videos'] as List? ?? const [])) v as Map];
  bool filmed(Map s) => videos.any((v) => '${v['exercise']}' == '${s['exercise']}' && v['set_number'] == s['set_number']);
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    CpKpis([
      ('Sets', total > 0 ? '${d['sets_done']} / $total' : '${d['sets_done']}'),
      ('Volume', vol > 0 ? '${cpNum(vol)} kg' : '—'),
      ('Time', secs > 0 ? '${(secs / 60).round()} min' : '—'),
      ('Effort', d['effort'] == null ? '—' : '${d['effort']} / 10'),
    ]),
    for (final (i, e) in order.indexed)
      () {
        final done = e.value.where((s) => s['done'] == true).length;
        final n = e.value.length;
        return _exRow(
          i + 1,
          '${e.value.first['exercise_name']}',
          done >= n ? Tone.ok : (done == 0 ? Tone.neutral : Tone.warn),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in e.value) _chip(_setText(s), s['done'] == true),
            if (e.value.any(filmed)) const AppBadge('Form video', tone: Tone.info),
          ]),
          '$done / $n sets',
          last: i == order.length - 1,
        );
      }(),
    if (order.isEmpty) const EmptyState('No sets logged'),
    if (note.isNotEmpty) cpQuote('${c.first}’s note', note),
    for (final v in videos) _FormVideoRow(v),
    CpReplyBox(
      hint: 'Comment on this workout…',
      first: c.first,
      onSend: (t) => Services.api.post('clients/${c.id}/logs/comment/', {'about': 'workout', 'date': '${r['date']}', 'text': t}),
    ),
  ]);
}

// ─────────────────────────────── Meals

/// Amount column: quantity × the serving unit. "2" of "1 piece" → "2 pieces", "1.5" of "100 g" → "150 g",
/// "2" of "1 katori" → "2 katori", "150" of "g" → "150 g". A unit other than grams also shows its weight:
/// "2 pieces (50 g)", "1 cup (240 g)"; grams alone stay "60 g".
String _qty(Map e) {
  final q = (e['quantity'] as num?)?.toDouble() ?? double.tryParse('${e['quantity']}') ?? 0;
  final unit = '${e['unit'] ?? ''}';
  final amount = cpAmount(q, unit);
  final g = (e['grams'] as num?)?.toDouble() ?? double.tryParse('${e['grams'] ?? ''}');
  final inGrams = RegExp(r'^(\d+(?:\.\d+)?\s*)?g$', caseSensitive: false).hasMatch(unit.trim()) || unit.trim().isEmpty;
  if (g == null || g <= 0 || inGrams) return amount;
  final gs = g >= 10 ? cpNum(g) : cpOne(g);
  return '$amount ($gs g)';
}

String cpAmount(double q, String unit) {
  var u = unit.trim();
  var per = 1.0;
  final m = RegExp(r'^(\d+(?:\.\d+)?)\s*(.*)$').firstMatch(u);
  if (m != null) {
    per = double.parse(m.group(1)!);
    u = m.group(2)!.trim();
  }
  final n = q * per;
  final amount = n == n.roundToDouble() ? cpNum(n) : (n * 10 == (n * 10).roundToDouble() ? cpOne(n) : n.toStringAsFixed(2));
  if (u.isEmpty) return amount;
  return '$amount ${n == 1 ? u : _plural(u)}';
}

/// "piece" → "pieces", "glass" → "glasses"; units and Indian measures (g, ml, tbsp, katori) stay as they are.
String _plural(String u) {
  final words = u.split(' ');
  final w = words.last;
  const keep = {'g', 'kg', 'ml', 'l', 'oz', 'tbsp', 'tsp', 'katori', 'medium', 'small', 'large'};
  if (keep.contains(w.toLowerCase()) || w.length < 3 || w.endsWith('s') || !RegExp(r'^[A-Za-z]+$').hasMatch(w)) return u;
  final p = RegExp(r'(sh|ch|x|ss)$').hasMatch(w) ? '${w}es' : (RegExp(r'[^aeiou]y$').hasMatch(w) ? '${w.substring(0, w.length - 1)}ies' : '${w}s');
  return [...words.sublist(0, words.length - 1), p].join(' ');
}

Widget _meals(BuildContext context, CpController c, Map r, Map d) {
  final plan = d['plan'] as Map?;
  final macros = (d['macros'] as Map?) ?? const {};
  final log = [for (final e in (d['log'] as List? ?? const [])) e as Map];
  final meals = [for (final m in (d['meals'] as List? ?? const [])) m as Map];
  final phone = context.isPhone;

  Widget mac(String k, String key, Color bar, num? target, String unit) {
    final v = (macros[key] as num?)?.toDouble() ?? 0;
    final t = target?.toDouble();
    final diff = t == null ? 0.0 : v - t;
    final hi = t != null && diff > t * .05;
    final n = t == null ? '' : (diff.abs() < .5 ? 'On target' : (diff > 0 ? '${cpNum(diff)}$unit over' : '${cpNum(-diff)}$unit left'));
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: AppColors.caWebBg, borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
        Row(spacing: 6, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: bar, shape: BoxShape.circle)),
          Text(k, style: AppText.s(12, W.w6, color: AppColors.text2)),
        ]),
        Text.rich(TextSpan(children: [
          TextSpan(text: '${cpNum(v)}$unit', style: AppText.s(16, W.w8, color: hi ? AppColors.badText : AppColors.text, tabular: true)),
          if (t != null) TextSpan(text: ' / ${cpNum(t)}$unit', style: AppText.s(12, W.w5, color: AppColors.muted)),
        ])),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: t == null || t == 0 ? 0 : (v / t).clamp(0.0, 1.0), minHeight: 4, color: bar, backgroundColor: AppColors.barTrack),
        ),
        Text(n, style: AppText.s(11.5, W.w5, color: hi ? AppColors.badText : AppColors.muted)),
      ]),
    );
  }

  final cards = [
    mac('Calories', 'kcal', AppColors.text, plan?['kcal'] as num?, ''),
    mac('Protein', 'protein', AppColors.accent, plan?['protein'] as num?, ' g'),
    mac('Carbs', 'carbs', AppColors.carbs, plan?['carbs'] as num?, ' g'),
    mac('Fat', 'fat', AppColors.fat, plan?['fat'] as num?, ' g'),
  ];

  // One block per planned meal, then food eaten outside the meal times.
  final blocks = <Widget>[];
  var logged = 0, pics = 0, off = 0;
  for (final m in meals) {
    final pill = '${m['pill']}';
    final mine = log.where((e) => '${e['meal']}' == '${m['id']}' && e['other_time'] != true).toList();
    final isLogged = pill == 'logged';
    if (isLogged) logged++;
    final photo = m['photo'] as String?;
    if (isLogged && photo != null) pics++;
    final offPlan = mine.any((e) => e['source'] != 'plan');
    final swapped = mine.where((e) => '${e['swapped_from'] ?? ''}'.isNotEmpty).toList();
    final (label, tone) = switch (pill) {
      'logged' => offPlan ? ('Off plan', Tone.bad) : (swapped.isNotEmpty ? ('Swapped', Tone.warn) : ('On plan', Tone.ok)),
      'missed' => ('Missed', Tone.bad),
      // A skipped meal counts as missed for the coach (no penalty for the client).
      'skipped' => ('Missed · skipped', Tone.warn),
      // Some foods eaten, the rest not logged yet (Phase 3): eaten next to planned.
      _ when mine.isNotEmpty => (
          'Partly eaten${m['eaten'] is Map && m['kcal'] != null ? ' · ${(m['eaten'] as Map)['kcal']} of ${m['kcal']} kcal' : ''}',
          Tone.info
        ),
      _ => ('Not logged yet', Tone.neutral),
    };
    if (isLogged && (offPlan || swapped.isNotEmpty)) off++;
    final when = isLogged ? cpTime(m['logged_at']) : _clock('${m['time']}');
    blocks.add(_mealBlock(
      context,
      name: '${m['name']}',
      time: when,
      badge: AppBadge(label, tone: tone, plain: true),
      photo: isLogged ? photo : null,
      photos: isLogged ? [for (final p in (m['photos'] as List? ?? const [])) '$p'] : const [],
      showPhotoSlot: true,
      items: isLogged || mine.isNotEmpty ? mine : const [],
      emptyLine: switch (pill) {
        'missed' => 'Not logged.',
        'skipped' => 'Skipped by ${c.first}: nothing eaten from this meal.',
        _ => isLogged ? 'Logged.' : 'Not logged yet.',
      },
      was: swapped.isEmpty ? null : swapped.map((e) => '${e['swapped_from']} (now ${e['name']})').join(', '),
      phone: phone,
    ));
  }
  final extra = log.where((e) => e['other_time'] == true || (e['meal'] == null && e['source'] != 'plan')).toList();
  if (extra.isNotEmpty) {
    blocks.add(_mealBlock(context,
        name: 'Other food',
        time: '',
        badge: const AppBadge('Off plan', tone: Tone.bad, plain: true),
        photo: null,
        showPhotoSlot: false,
        items: extra,
        emptyLine: '',
        phone: phone));
  }
  final sum = meals.isEmpty
      ? '${log.length} food${log.length == 1 ? '' : 's'} logged · no meal plan this day'
      : '$logged of ${meals.length} meals logged · $pics with a photo · $off off plan';

  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    LayoutBuilder(builder: (_, b) {
      final per = phone ? 2 : 4;
      final w = (b.maxWidth - 8 * (per - 1)) / per;
      return Wrap(spacing: 8, runSpacing: 8, children: [for (final x in cards) SizedBox(width: w, child: x)]);
    }),
    Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(sum, style: AppText.s(12.5, W.w5, color: AppColors.muted))),
    if (!phone)
      Container(
        padding: const EdgeInsets.fromLTRB(70, 10, 10, 6),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
        child: _foodRow(['Food', 'Amount', 'kcal', 'Protein', 'Carbs', 'Fat'], head: true),
      ),
    if (blocks.isEmpty) const EmptyState('Nothing logged this day'),
    ...blocks,
    CpReplyBox(
      hint: 'Comment on ${cpTheir(c)} meals for this day…',
      first: c.first,
      onSend: (t) => Services.api.post('clients/${c.id}/logs/comment/', {'about': 'meals', 'date': '${r['date']}', 'text': t}),
    ),
  ]);
}

String _clock(String hhmm) {
  final t = DateTime.tryParse('2000-01-01 $hhmm');
  return t == null ? '' : DateFormat('h:mm a').format(t).toLowerCase();
}

Widget _foodRow(List<String> cells, {bool head = false}) {
  final st = head ? AppText.s(11.5, W.w7, color: AppColors.muted, ls: .58) : AppText.s(13, W.w5, tabular: true);
  const flex = [4, 3, 1, 1, 1, 1];
  return Row(children: [
    for (final (i, t) in cells.indexed)
      Expanded(
        flex: flex[i] * (i < 2 ? 1 : 1),
        child: CutText(head ? t.toUpperCase() : t,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: i >= 2 ? TextAlign.right : TextAlign.left,
            style: i == 0 && !head ? AppText.s(13, W.w6) : st),
      ),
  ]);
}

Widget _mealBlock(
  BuildContext context, {
  required String name,
  required String time,
  required Widget badge,
  required String? photo,
  List<String> photos = const [],
  required bool showPhotoSlot,
  required List<Map> items,
  required String emptyLine,
  String? was,
  required bool phone,
}) {
  num tot(String k) => items.fold<num>(0, (a, e) => a + ((e[k] as num?) ?? 0));
  Widget pill(Color c, String l, String v) => Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        Text(l, style: AppText.s(12, W.w5, color: AppColors.muted)),
        Text(v, style: AppText.s(12, W.w7)),
      ]);
  final thumb = !showPhotoSlot
      ? null
      : photo != null
          // Up to 4 photos a meal (Phase 3): the first as the thumbnail, "+N" for the rest, all in the viewer.
          ? SizedBox(
              width: 48,
              height: 48,
              child: Stack(children: [
                Positioned.fill(child: CpPhoto(photo, height: 48, onTap: () => showImageViewer(context, photos.isEmpty ? [photo] : photos, title: name))),
                if (photos.length > 1)
                  Positioned(
                    right: 3,
                    bottom: 3,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.text.withValues(alpha: .75), borderRadius: AppRadius.all(6)),
                        child: Text('+${photos.length - 1}', style: AppText.s(10.5, W.w7, color: AppColors.white)),
                      ),
                    ),
                  ),
              ]),
            )
          : Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.line2)),
              child: Text('No\nphoto', textAlign: TextAlign.center, style: AppText.s(10.5, W.w5, color: AppColors.muted, h: 1.2)),
            );
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
        ?thumb,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
            Row(spacing: 8, children: [
              Text(name, style: AppText.s(14, W.w8)),
              if (time.isNotEmpty) Text(time, style: AppText.cap),
              const Spacer(),
              badge,
            ]),
            if (items.isNotEmpty)
              Wrap(spacing: 10, runSpacing: 4, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: cpNum(tot('kcal')), style: AppText.s(12, W.w7)),
                  TextSpan(text: ' kcal', style: AppText.s(12, W.w5, color: AppColors.muted)),
                ])),
                pill(AppColors.accent, 'Protein', cpG(tot('protein'))),
                pill(AppColors.carbs, 'Carbs', cpG(tot('carbs'))),
                pill(AppColors.fat, 'Fat', cpG(tot('fat'))),
              ])
            else
              Text(emptyLine, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
          ]),
        ),
      ]),
      if (items.isNotEmpty)
        Container(
          margin: EdgeInsets.only(left: thumb == null || phone ? 0 : 60),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: AppColors.caWebBg, borderRadius: AppRadius.all(8)),
          child: Column(children: [
            for (final e in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: phone
                    ? Row(children: [
                        Expanded(child: Text('${e['name']}', style: AppText.s(13, W.w6))),
                        Text('${_qty(e)} · ${cpNum(e['kcal'] as num?)} kcal', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
                      ])
                    : _foodRow(['${e['name']}', _qty(e), cpNum(e['kcal'] as num?), cpG(e['protein'] as num?), cpG(e['carbs'] as num?), cpG(e['fat'] as num?)]),
              ),
          ]),
        ),
      if (was != null)
        Row(spacing: 6, children: [
          const AppIcon(AppIcons.swap, size: 14, color: AppColors.muted),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: 'Plan had ', style: AppText.s(12.5, W.w7, color: AppColors.text2)),
              TextSpan(text: was, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
            ])),
          ),
        ]),
    ]),
  );
}

// ─────────────────────────────── Daily check-in

Widget _daily(CpController c, Map r, _Nav nav, VoidCallback changed) {
  String v(Object? x) => x == null || '$x'.isEmpty ? '—' : '$x';
  if (r['id'] == null) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CpKpis([('Sleep', '—'), ('Energy', '—'), ('Mood', '—'), ('Steps', r['steps'] == null ? '—' : cpNum(r['steps'] as num))]),
      Padding(padding: const EdgeInsets.only(top: 8), child: Text('${c.first} did not send a check-in this day.', style: AppText.sub)),
    ]);
  }
  final reply = '${r['reply'] ?? ''}';
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    CpKpis([
      ('Sleep', r['sleep'] == null ? '—' : '${cpOne(r['sleep'] as num)} h'),
      ('Energy', v(r['energy'])),
      ('Mood', v(r['mood'])),
      ('Steps', r['steps'] == null ? '—' : cpNum(r['steps'] as num)),
    ]),
    CpQa([
      ('Hunger', v(r['hunger'])),
      ('Water', r['water'] == null ? '—' : '${cpOne(r['water'] as num)} L'),
      ('Morning weight', r['weight'] == null ? '—' : cpKg(r['weight'], keep: true)),
      ('Note', v(r['note'])),
    ]),
    if (reply.isNotEmpty) cpQuote('Your reply', reply),
    CpReplyBox(
      hint: 'Reply to ${cpTheir(c)} check-in…',
      first: c.first,
      onSend: (t) async {
        await Services.api.post('checkins/${r['id']}/review/', {'reply': t});
        r['reply'] = t;
        r['reviewed'] = true;
        changed();
      },
    ),
  ]);
}

// ─────────────────────────────── Weekly check-in

String _answer(Map a) {
  final v = a['value'];
  return switch ('${a['question_type']}') {
    'scale' => v is num ? '$v / 5' : '$v',
    'yes_no' => v == true ? 'Yes' : (v == false ? 'No' : '$v'),
    'multiple' => v is List ? v.join(', ') : '$v',
    _ => v == null ? '—' : '$v',
  };
}

Widget _weekly(BuildContext context, CpController c, Map r, Map d, _Nav nav, VoidCallback changed) {
  final rv = (d['review'] as Map?) ?? const {};
  final kpis = [for (final k in (rv['kpis'] as List? ?? const [])) ('${(k as Map)['label']}', '${k['value']}')];
  final qa = [
    for (final a in (d['answers'] as List? ?? const []))
      if ((a as Map)['question_type'] != 'photo' && a['metric'] != 'weight' && a['value'] != null && '${a['value']}'.isNotEmpty) ('${a['question_text']}', _answer(a)),
  ];
  final photos = [
    for (final p in ((r['photos'] as List?)?.isNotEmpty == true ? r['photos'] as List : (d['photos'] as List? ?? const []))) ('${(p as Map)['image']}', '${p['label'] ?? ''}'),
  ];
  final reply = '${d['reply'] ?? r['reply'] ?? ''}';
  final reviewed = r['status'] == 'reviewed';
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    if (kpis.isNotEmpty) CpKpis(kpis),
    if (qa.isNotEmpty) CpQa(qa),
    cpDrSub('Progress photos'),
    if (photos.isEmpty) Text('No photos this week', style: AppText.sub) else CpPhotoRow(photos, title: '${c.first}’s photos · week ${r['week']}'),
    if (reply.isNotEmpty) cpQuote(reviewed && r['reviewer'] != null ? 'Reply by ${r['reviewer']}' : 'Your reply', reply),
    CpReplyBox(
      hint: 'Write your review for week ${r['week']}…',
      first: c.first,
      onSend: (t) async {
        await Services.api.post('checkins/${r['id']}/review/', {'reply': t});
        r['reply'] = t;
        r['status'] = 'reviewed';
        r['reviewer'] = Services.session.me?.name;
        nav.cache.remove(nav.i);
        changed();
      },
    ),
  ]);
}

Future<void> _review(BuildContext ctx, CpController c, _Nav nav, String reply, VoidCallback changed) async {
  final r = nav.r;
  try {
    await Services.api.post('checkins/${r['id']}/review/', {'reply': reply});
  } on ApiError catch (e) {
    if (ctx.mounted) showToast(ctx, 'Could not mark it reviewed', sub: e.message, kind: ToastKind.err);
    return;
  }
  r['status'] = 'reviewed';
  r['reviewer'] = Services.session.me?.name;
  changed();
  if (!ctx.mounted) return;
  final id = '${r['id']}';
  showToast(ctx, '${c.first}’s check-in reviewed', sub: cpWeeklyLine(r), action: 'Undo', onAction: () async {
    try {
      await Services.api.post('checkins/$id/unreview/');
      r['status'] = 'to_review';
      changed();
    } catch (_) {}
  });
}

// ─────────────────────────────── Habits / supplements

Widget _ticks(Map r) {
  final items = [for (final x in (r['items'] as List? ?? const [])) x as Map];
  if (items.isEmpty) return const EmptyState('Nothing was due this day');
  return Column(children: [
    for (final (i, t) in items.indexed)
      Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(border: i == items.length - 1 ? null : const Border(bottom: BorderSide(color: AppColors.line))),
        child: Row(spacing: 12, children: [
          cpTick(t['done'] == true),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text('${t['name']}', style: AppText.s(13.5, W.w7)),
              if ('${t['sub'] ?? ''}'.isNotEmpty) Text('${t['sub']}', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
            ]),
          ),
          Text('${t['when'] ?? ''}', style: AppText.s(12.5, W.w5, color: t['done'] == true ? AppColors.text2 : AppColors.muted)),
        ]),
      ),
  ]);
}

/// A form check the client filmed: length, which set, when it came, Watch (full screen player).
class _FormVideoRow extends StatelessWidget {
  const _FormVideoRow(this.v);
  final Map v;

  @override
  Widget build(BuildContext context) {
    final secs = (v['duration_seconds'] as num?)?.toInt();
    final what = '${v['exercise_name']}${v['set_number'] == null ? '' : ', set ${v['set_number']}'}';
    final url = '${v['url'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.line)),
      child: Row(spacing: 12, children: [
        Container(
          width: 64,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.black, borderRadius: AppRadius.all(8)),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 3, children: [
            const AppIcon(AppIcons.play, size: 11, color: AppColors.white),
            Text(secs == null ? 'Video' : mediaClock(secs), style: AppText.s(11.5, W.w7, color: AppColors.white)),
          ]),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            CutText(what, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7)),
            CutText('Form check video · sent ${cpTime(v['created_at'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cap),
            if ('${v['note'] ?? ''}'.isNotEmpty) CutText('${v['note']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.text2)),
          ]),
        ),
        AppButton('Watch', size: BtnSize.sm, icon: AppIcons.play, onPressed: url.isEmpty ? null : () => playVideoFull(context, url, title: what)),
      ]),
    );
  }
}
