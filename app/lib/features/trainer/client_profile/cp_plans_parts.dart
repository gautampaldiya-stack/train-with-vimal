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
import '../../../core/widgets/tabs.dart';
import 'cp_common.dart';
import 'cp_model.dart';
import 'cp_plans_model.dart';

// Pieces of the Plans tab: day strip, day head and note, exercise and meal rows, the exercise and meal drawers
// and the habits drawer (with the per-client habit edit).

/// Lets the assign drawer (opened from the header too) ask the Plans tab to open the editor after assigning.
class PlanEvent {
  const PlanEvent(this.client, this.kind);
  final String client, kind; // kind: edit · dup
}

class PlanEvents extends ChangeNotifier {
  PlanEvents._();
  static final instance = PlanEvents._();
  PlanEvent? last;
  void send(PlanEvent e) {
    last = e;
    notifyListeners();
  }
}

/// `.media` tile (t1–t4) with a play icon: exercise video placeholder.
class MediaTile extends StatelessWidget {
  const MediaTile({super.key, this.tone = 0, this.size = 44, this.play = true});
  final int tone;
  final double size;
  final bool play;
  @override
  Widget build(BuildContext context) {
    final (a, b) = AppColors.mediaTiles[tone % 4];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size >= 64 ? 10 : 8),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b]),
      ),
      child: AppIcon(play ? AppIcons.play : AppIcons.dumbbell, size: size >= 64 ? 28 : 18, color: AppColors.mediaFg, stroke: 1.6),
    );
  }
}

/// `.pd-days`: 7 day buttons (day, name or kcal, blue dot when changed for the client). Narrow: scrolls sideways.
class DayStrip extends StatelessWidget {
  const DayStrip({super.key, required this.days, required this.selected, required this.onPick, this.short});
  final List<(String, String, bool, bool)> days; // (Mon, Upper A, changed, rest)
  final int selected;
  final ValueChanged<int> onPick;

  /// A short second line per day ("5 ex", "1.6k"): when given, a narrow strip (phone) shows all seven days as
  /// small cells instead of scrolling.
  final List<String>? short;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(context.isPhone ? 16 : 16, 6, 16, 4),
        child: LayoutBuilder(builder: (context, b) {
          Widget day(int i, {double? width}) {
            final (d, n, dot, rest) = days[i];
            final on = i == selected;
            return Hover(
              onTap: () => onPick(i),
              builder: (_, h, _) => Container(
                width: width,
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
                decoration: BoxDecoration(
                  color: on ? AppColors.hover : (rest ? AppColors.caWebBg : AppColors.card),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: on ? AppColors.accent : (h ? AppColors.line2 : AppColors.line)),
                ),
                child: Stack(clipBehavior: Clip.none, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                    Text(d, style: AppText.s(12.5, W.w8, color: on ? AppColors.accentText : AppColors.text)),
                    Text(n, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w6, color: on ? AppColors.accentText : AppColors.muted)),
                  ]),
                  if (dot)
                    Positioned(
                      top: 0,
                      right: -2,
                      child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
                    ),
                ]),
              ),
            );
          }

          Widget compact(int i) {
            final (d, _, dot, rest) = days[i];
            final on = i == selected;
            return Hover(
              onTap: () => onPick(i),
              builder: (_, h, _) => Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: on ? AppColors.hover : (rest ? AppColors.caWebBg : AppColors.card),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: on ? AppColors.accent : (h ? AppColors.line2 : AppColors.line)),
                ),
                child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                  Column(spacing: 1, children: [
                    Text(d, maxLines: 1, style: AppText.s(12, W.w8, color: on ? AppColors.accentText : AppColors.text)),
                    Text(short![i], maxLines: 1, overflow: TextOverflow.clip, style: AppText.s(10.5, W.w6, color: on ? AppColors.accentText : AppColors.muted, tabular: true)),
                  ]),
                  if (dot)
                    Positioned(
                      top: -2,
                      right: 4,
                      child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
                    ),
                ]),
              ),
            );
          }

          if (b.maxWidth / 7 >= 72) {
            return Row(spacing: 6, children: [for (var i = 0; i < days.length; i++) Expanded(child: day(i))]);
          }
          // Phone: all seven days fit as small cells (day over [short]), no sideways scrolling.
          if (short != null && (b.maxWidth - 24) / 7 >= 34) {
            return Row(spacing: 4, children: [for (var i = 0; i < days.length; i++) Expanded(child: compact(i))]);
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(spacing: 6, children: [for (var i = 0; i < days.length; i++) day(i, width: 92)]),
          );
        }),
      );
}

/// `.cp-subbar` of the plan editors (workout, meals, supplements): `Back to plan` on the left, `Reset to master`
/// (when the client has an own copy), `Cancel` and the save button on the right. Phone: one row: back and reset
/// as square icon buttons (tooltips), Cancel, and the save button taking the rest of the width.
class PlanEditBar extends StatelessWidget {
  const PlanEditBar({super.key, required this.onBack, required this.onCancel, required this.save, required this.onSave, this.onReset, this.busy = false});
  final VoidCallback onBack, onCancel, onSave;
  final VoidCallback? onReset;
  final String save;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cancel = AppButton('Cancel', onPressed: busy ? null : onCancel);
    final ok = AppButton.primary(save, icon: AppIcons.check, loading: busy, expand: context.isPhone, onPressed: busy ? null : onSave);
    if (context.isPhone) {
      return Row(spacing: 8, children: [
        AppButton('Back to plan', icon: AppIcons.chevronLeft, iconOnly: true, onPressed: onBack),
        if (onReset != null) AppButton('Reset to master', icon: AppIcons.reset, iconOnly: true, onPressed: busy ? null : onReset),
        cancel,
        Expanded(child: ok),
      ]);
    }
    return Wrap(alignment: WrapAlignment.spaceBetween, runSpacing: 10, spacing: 8, children: [
      AppButton('Back to plan', icon: AppIcons.chevronLeft, onPressed: onBack),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (onReset != null) AppButton('Reset to master', kind: BtnKind.text, icon: AppIcons.reset, onPressed: busy ? null : onReset),
        cancel,
        ok,
      ]),
    ]);
  }
}

/// `.pd-head`: "Tuesday · Lower A" over "6 exercises · 19 sets…", badge on the right.
class PdHead extends StatelessWidget {
  const PdHead({super.key, required this.title, required this.sub, this.badge});
  final String title, sub;
  final String? badge;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Row(spacing: 10, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text(title, style: AppText.s(14, W.w8)),
              Text(sub, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
            ]),
          ),
          if (badge != null) AppBadge(badge!, tone: Tone.info, plain: true),
        ]),
      );
}

/// `.pd-dnote`: "Coach note for this day" over the note.
class DayNote extends StatelessWidget {
  const DayNote(this.text, {super.key, this.label = 'Coach note for this day'});
  final String text, label;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: AppColors.caWebBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
          Text(label, style: AppText.s(11.5, W.w7, color: AppColors.muted)),
          Text(text, style: AppText.s(13, W.w5, color: AppColors.text2, h: 1.5)),
        ]),
      );
}

/// `.pd-empty`: dashed box with a centred line.
class PdEmpty extends StatelessWidget {
  const PdEmpty(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: AppColors.line2)),
        child: Text(text, textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)),
      );
}

/// `.cp-macros`: 4 grey boxes (1,650 / kcal a day …); 2 × 2 on phone.
class Macros extends StatelessWidget {
  const Macros(this.items, {super.key});
  final List<(String, String)> items;
  @override
  Widget build(BuildContext context) {
    Widget box((String, String) it) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
            Text(it.$1, style: AppText.s(15, W.w8)),
            Text(it.$2, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
          ]),
        );
    final pad = EdgeInsets.fromLTRB(16, 2, 16, 8);
    if (context.isPhone) {
      return Padding(
        padding: pad,
        child: Column(spacing: 8, children: [
          for (final r in [0, 2]) Row(spacing: 8, children: [Expanded(child: box(items[r])), Expanded(child: box(items[r + 1]))]),
        ]),
      );
    }
    return Padding(padding: pad, child: Row(spacing: 8, children: [for (final it in items) Expanded(child: box(it))]));
  }
}

/// `.dr-num` (1, 2) or `.dr-num.ss` (A1, A2, purple).
Widget numTag((String, bool) tag) => Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: EdgeInsets.symmetric(horizontal: tag.$2 ? 5 : 0),
      decoration: BoxDecoration(
        color: tag.$2 ? AppColors.purpleBg : AppColors.sub,
        borderRadius: BorderRadius.circular(tag.$2 ? 6 : 11),
      ),
      child: Center(widthFactor: 1, child: Text(tag.$1, style: AppText.s(11.5, W.w8, color: tag.$2 ? AppColors.purpleText : AppColors.text2))),
    );

/// `.pd-row` for one exercise: tag, video tile, name + badges, "4 × 8 · RPE 7 · …", note, chevron.
class ExerciseRow extends StatelessWidget {
  const ExerciseRow({super.key, required this.e, required this.tag, required this.tone, this.changed, required this.onTap});
  final Map e;
  final (String, bool) tag;
  final int tone;
  final String? changed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = exMeta(e);
    final note = '${e['note'] ?? ''}'.trim();
    return Hover(
      onTap: onTap,
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: h ? AppColors.hover : null, borderRadius: BorderRadius.circular(AppRadius.item)),
        child: Row(spacing: 12, children: [
          numTag(tag),
          MediaTile(tone: tone),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(exName(e), style: AppText.s(13.5, W.w7)),
                if (changed != null) _SmallBadge(changed!, Tone.info),
                if (e['edited'] == true) const _SmallBadge('Edited in program', Tone.warn),
              ]),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${e['sets']} × ${e['reps']}', style: AppText.s(12.5, W.w7, color: AppColors.text)),
                  if (meta.isNotEmpty) TextSpan(text: ' · $meta'),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.s(12.5, W.w5, color: AppColors.text2),
              ),
              if (note.isNotEmpty) Text(note, style: AppText.s(12, W.w5, color: AppColors.muted)),
            ]),
          ),
          const AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.chevron),
        ]),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge(this.label, this.tone);
  final String label;
  final Tone tone;
  @override
  Widget build(BuildContext context) => Container(
        height: 19,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(5)),
        child: Center(widthFactor: 1, child: Text(label, style: AppText.s(10.5, W.w7, color: tone.fg))),
      );
}

// ─────────────────────────────── meals

Map? defaultOption(Map meal) {
  final opts = [for (final o in (meal['options'] as List?) ?? const []) o as Map];
  return opts.where((o) => o['is_default'] == true).firstOrNull ?? opts.firstOrNull;
}

List<Map> mealItems(Map meal) => [for (final i in (defaultOption(meal)?['items'] as List?) ?? const []) i as Map];

double _m(Map it, String k) => (((it['macros'] as Map?)?[k] as num?) ?? 0).toDouble();
double mealKcal(Map meal) => mealItems(meal).fold(0, (a, it) => a + _m(it, 'kcal'));
double mealProtein(Map meal) => mealItems(meal).fold(0, (a, it) => a + _m(it, 'protein'));

String _num(Object? v) {
  final d = (v is num ? v : num.tryParse('$v') ?? 0).toDouble();
  return d == d.roundToDouble() ? '${d.round()}' : d.toStringAsFixed(1);
}

/// "1 scoop · 32 g", "2 × 1 medium · 80 g", "60 g".
String portion(Map it) {
  final f = (it['food_detail'] as Map?) ?? const {};
  final unit = [for (final u in (f['units'] as List?) ?? const []) u as Map].where((u) => u['id'] == it['unit']).firstOrNull;
  final q = _num(it['quantity']);
  if (unit == null) return '$q g';
  return '${q == '1' ? '' : '$q × '}${unit['name']} · ${_num(it['grams'])} g';
}

String mealTime(Object? t) {
  final d = DateTime.tryParse('2000-01-01 $t');
  return d == null ? '' : DateFormat('h:mm a').format(d).toLowerCase();
}

/// `.pd-row` for one meal: time, name, foods, kcal and protein.
class MealRow extends StatelessWidget {
  const MealRow({super.key, required this.meal, required this.onTap});
  final Map meal;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final items = mealItems(meal);
    return Hover(
      onTap: onTap,
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: h ? AppColors.hover : null, borderRadius: BorderRadius.circular(AppRadius.item)),
        child: Row(spacing: 12, children: [
          SizedBox(width: 64, child: Text(mealTime(meal['time']), style: AppText.s(12, W.w7, color: AppColors.muted))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text('${meal['name']}', style: AppText.s(13.5, W.w7)),
              Text(items.isEmpty ? 'No foods yet' : items.map((i) => '${(i['food_detail'] as Map?)?['name'] ?? ''}').join(', '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.text2)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${mealKcal(meal).round()} kcal', style: AppText.s(13, W.w7)),
            Text('P ${mealProtein(meal).round()} g', style: AppText.s(11.5, W.w6, color: AppColors.muted)),
          ]),
          const AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.chevron),
        ]),
      ),
    );
  }
}

// ─────────────────────────────── drawers

/// Footer note: fills the row on wide screens; on phone the footer is a column, so it stays as it is.
Widget _fnote(BuildContext ctx, Widget w) => ctx.isPhone ? w : Expanded(child: w);

/// `.dr-kpis`: label over value in even columns with a line between (4 in a row; 6 go 3 + 3), numbers tabular.
Widget _kpis(List<(String, String)> k) {
  final per = k.length <= 4 ? k.length : 3;
  Widget cell(int i) {
    final (a, b) = k[i];
    final first = i % per == 0;
    return Expanded(
      child: Container(
        padding: EdgeInsets.only(left: first ? 0 : 12, right: 6),
        decoration: BoxDecoration(border: first ? null : const Border(left: BorderSide(color: AppColors.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
          Text(a, style: AppText.s(12, W.w5, color: AppColors.muted)),
          Text(b, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(14, W.w8, tabular: true)),
        ]),
      ),
    );
  }

  return Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
    child: Column(spacing: 12, children: [
      for (var r = 0; r < k.length; r += per)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = r; i < r + per; i++) i < k.length ? cell(i) : const Expanded(child: SizedBox()),
          ]),
        ),
    ]),
  );
}

Widget _sub(String t) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 6), child: Text(t, style: AppText.s(13.5, W.w8)));

Widget _quote(String label, String text) => Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: AppColors.caWebBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
        Text(label, style: AppText.s(11.5, W.w7, color: AppColors.muted)),
        Text(text, style: AppText.s(13, W.w5, color: AppColors.text2, h: 1.5)),
      ]),
    );

/// Exercise drawer (`exd`): video, Sets / Reps / Rest / Load / RPE / Tempo, what changed, superset, notes, how to
/// do it, form cues, muscles. Prev / next walk the day. Footer: `Swap exercise` · `Edit for X` (the editor).
/// The Program builder opens it without a client ([c] null) and gives its own [footer] (the exercise at `n`).
Future<void> showExerciseDrawer(BuildContext context,
    {CpController? c,
    required List<Map> list,
    required int start,
    required String dayLabel,
    required String dayNote,
    required String program,
    required String? Function(int) was,
    VoidCallback? onEdit,
    List<Widget> Function(BuildContext ctx, int n)? footer}) {
  final i = ValueNotifier(start);
  final cache = <String, Future<Map>>{};
  Future<Map> detail(Map e) => cache.putIfAbsent('${e['exercise']}', () => Services.api.get<Map>('exercises/${e['exercise']}/'));
  final tags = tagsOf(list);
  return showAppDrawer(
    context,
    title: exName(list[start]),
    sub: dayLabel,
    icon: AppIcons.dumbbell,
    headerAction: ValueListenableBuilder(
      valueListenable: i,
      builder: (_, n, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        AppIconButton(AppIcons.chevronLeft, tooltip: 'Previous', ghost: true, small: true, onPressed: () => i.value = (n - 1 + list.length) % list.length),
        AppIconButton(AppIcons.chevronRight, tooltip: 'Next', ghost: true, small: true, onPressed: () => i.value = (n + 1) % list.length),
      ]),
    ),
    builder: (ctx) => ValueListenableBuilder(
      valueListenable: i,
      builder: (ctx, n, _) {
        final e = list[n];
        final w = was(n);
        final mate = '${e['superset_group'] ?? ''}'.isEmpty
            ? null
            : list.indexed.where((x) => x.$1 != n && x.$2['superset_group'] == e['superset_group']).map((x) => exName(x.$2)).firstOrNull;
        return FutureBuilder<Map>(
          future: detail(e),
          builder: (ctx, snap) {
            final x = snap.data ?? (e['exercise_detail'] as Map?) ?? const {};
            final ov = (e['override'] as Map?) ?? const {};
            final how = [for (final s in (ov['how_to'] as List?) ?? (x['how_to'] as List?) ?? const []) '$s'];
            final cues = [for (final s in (ov['form_cues'] as List?) ?? (x['form_cues'] as List?) ?? const []) '$s'];
            final yt = '${ov['youtube_url'] ?? x['youtube_url'] ?? ''}';
            final also = [for (final a in (x['also_works'] as List?) ?? const []) '${(a as Map)['muscle']}'];
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 14),
              Text('${exName(e)} · exercise ${n + 1} of ${list.length} · ${tags[n].$1}', style: AppText.cap),
              const SizedBox(height: 10),
              if (snap.connectionState != ConnectionState.done && snap.data == null)
                const SizedBox(height: 64, child: CpLoading())
              else
                ExMedia(key: ValueKey('${e['exercise']}'), media: x['media'] as Map?, link: yt, name: exName(e), tone: n),
              _kpis([
                ('Sets', '${e['sets']}'),
                ('Reps', '${e['reps']}'),
                ('Rest', restText(e['rest_seconds']).ifEmpty('–')),
                ('Load', loadText(e).ifEmpty('–')),
                ('RPE', '${e['rpe'] ?? '–'}'),
                ('Tempo', '${e['tempo'] ?? ''}'.ifEmpty('–')),
              ]),
              if (w != null || e['edited'] == true)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(spacing: 8, runSpacing: 6, children: [
                    if (w != null) Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [AppBadge('Changed for ${c?.first}', tone: Tone.info, plain: true), Text(w, style: AppText.cap)]),
                    if (e['edited'] == true) AppBadge('Edited in $program', tone: Tone.warn, plain: true),
                  ]),
                ),
              if (mate != null) _quote('Superset ${e['superset_group']}', 'With $mate: one set of each, then rest.'),
              if ('${e['note'] ?? ''}'.isNotEmpty) _quote(c == null ? 'Note' : 'Note for ${c.first}', '${e['note']}'),
              if (dayNote.isNotEmpty) _quote('Coach note for this day', dayNote),
              if (how.isNotEmpty) ...[
                _sub('How to do it'),
                for (final (k, s) in how.indexed) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${k + 1}. $s', style: AppText.s(13, W.w5, color: AppColors.text2, h: 1.5))),
              ],
              if (cues.isNotEmpty) ...[
                _sub('Form cues'),
                for (final s in cues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                      const Padding(padding: EdgeInsets.only(top: 2), child: AppIcon(AppIcons.check, size: 14, color: AppColors.okText)),
                      Expanded(child: Text(s, style: AppText.s(13, W.w5, color: AppColors.text2, h: 1.5))),
                    ]),
                  ),
              ],
              _sub('Muscles'),
              Wrap(spacing: 6, runSpacing: 6, children: [
                AppBadge('${x['primary_muscle'] ?? x['muscle_group'] ?? ''}'.ifEmpty('Main muscle'), tone: Tone.info),
                for (final a in also) AppBadge(a),
              ]),
              const SizedBox(height: 8),
            ]);
          },
        );
      },
    ),
    footer: footer != null
        ? (ctx) => [
              ValueListenableBuilder(
                valueListenable: i,
                builder: (_, n, _) => Row(mainAxisSize: ctx.isPhone ? MainAxisSize.max : MainAxisSize.min, spacing: 8, children: [
                  for (final w in footer(ctx, n)) ctx.isPhone ? Expanded(child: w) : w,
                ]),
              ),
            ]
        : (ctx) => [
      _fnote(
        ctx,
        ValueListenableBuilder(
          valueListenable: i,
          builder: (_, n, _) => Text(was(n) != null ? 'Changed for ${c?.first} · master is the same' : 'Same as the master plan',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cap),
        ),
      ),
      AppButton('Swap exercise', icon: AppIcons.swap, onPressed: () {
        Navigator.of(ctx).pop();
        onEdit?.call();
      }),
      AppButton.primary('Edit for ${c?.first}', icon: AppIcons.edit, onPressed: () {
        Navigator.of(ctx).pop();
        onEdit?.call();
      }),
    ],
  ).whenComplete(() => disposeLater([i]));
}

/// The exercise's video, YouTube link, picture or web link inside the drawer (the same players as the client
/// guide): a video and a YouTube video play right here, a picture opens full screen, a web link opens the
/// browser. The line under it says which one it is.
class ExMedia extends StatefulWidget {
  const ExMedia({super.key, required this.media, required this.link, required this.name, this.tone = 0, this.footer = true});
  final Map? media;
  final String link, name;
  final int tone;

  /// The "YouTube link · Open in YouTube" line under the player; off when the card header shows it.
  final bool footer;
  @override
  State<ExMedia> createState() => _ExMediaState();
}

class _ExMediaState extends State<ExMedia> {
  Map? get m => widget.media;

  /// video · image · youtube (library or the exercise's link) · web (a link that is not YouTube) · '' none.
  late final String kind = () {
    final k = '${m?['kind'] ?? ''}';
    if (k.isNotEmpty) return k;
    if (widget.link.isEmpty) return '';
    return youtubeId(widget.link).isNotEmpty ? 'youtube' : 'web';
  }();
  String get url => '${m?['url'] ?? ''}'.isNotEmpty ? '${m!['url']}' : widget.link;
  late final VideoCtl? v = kind == 'video' ? VideoCtl(url, fallbackSeconds: ((m?['duration'] as num?) ?? 0).toInt()) : null;

  @override
  void dispose() {
    v?.dispose();
    super.dispose();
  }

  String _label() {
    final c = v!;
    if (c.failed) return 'Could not play here · tap to open';
    if (c.playing) return 'Playing';
    if (c.finished) return 'Finished · tap to watch again';
    if (c.pos > 0) return 'Paused';
    return 'Tap to play';
  }

  void _open() => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    if (kind.isEmpty) {
      return Row(spacing: 12, children: [
        MediaTile(tone: widget.tone, size: 64, play: false),
        Expanded(child: Text('No video yet. Add one in the exercise library.', style: AppText.s(12.5, W.w6, color: AppColors.muted))),
      ]);
    }
    // a bare link has no title of its own (the exercise name is already on the page)
    final title = '${m?['title'] ?? ''}'.isNotEmpty ? '${m!['title']}' : '';
    final (AppIconData icon, String what) = switch (kind) {
      'video' => (AppIcons.video, 'Video'),
      'image' => (AppIcons.photo, 'Picture'),
      'youtube' => (AppIcons.video, 'YouTube link'),
      _ => (AppIcons.link, 'Web link'),
    };
    final hint = switch (kind) { 'video' => 'Plays here', 'image' => 'Tap to open', _ => 'Opens in the browser' };
    final Widget face = switch (kind) {
      'video' => VideoBox(ctl: v!, label: _label, bg: AppColors.videoDark.first, fg: AppColors.white, height: 220, radius: 0, onTapEmpty: _open),
      'image' => Semantics(
          button: true,
          label: 'Open the picture full screen',
          child: GestureDetector(
            onTap: () => showImageViewer(context, [url], title: widget.name),
            child: MouseRegion(
              cursor: SystemMouseCursors.zoomIn,
              child: Container(color: AppColors.sub, height: 220, child: NetImage(url, fit: BoxFit.contain, height: 220)),
            ),
          ),
        ),
      'youtube' => YoutubeBox(url: url, openLink: false),
      _ => Hover(
          onTap: _open,
          builder: (_, h, _) => Container(
            height: 96,
            color: h ? AppColors.hover : AppColors.sub,
            alignment: Alignment.center,
            child: Column(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              AppIcon(AppIcons.external, size: 22, color: h ? AppColors.accent : AppColors.muted),
              Text(Uri.tryParse(url)?.host ?? url, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: h ? AppColors.accentText : AppColors.text2)),
            ]),
          ),
        ),
    };
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        face,
        if (widget.footer)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(spacing: 8, children: [
            AppIcon(icon, size: 15, color: AppColors.muted),
            Expanded(
              child: Text.rich(
                TextSpan(text: what, style: AppText.s(12.5, W.w7), children: [if (title.isNotEmpty) TextSpan(text: ' · $title', style: AppText.s(12.5, W.w5, color: AppColors.text2))]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (kind == 'youtube') OpenInYoutube(url) else Text(hint, style: AppText.s(12, W.w5, color: AppColors.muted)),
          ]),
        ),
      ]),
    );
  }
}

/// Meal drawer (`mld`): Calories / Protein / Foods / Time, each food with its amount, macros and swaps, the meal total.
Future<void> showMealDrawer(BuildContext context,
    {required CpController c, required List<Map> meals, required int start, required String sub, required VoidCallback onEdit, bool custom = false}) {
  final i = ValueNotifier(start);
  return showAppDrawer(
    context,
    title: '${meals[start]['name']} · ${mealTime(meals[start]['time'])}',
    sub: sub,
    icon: AppIcons.apple,
    headerAction: Row(mainAxisSize: MainAxisSize.min, children: [
      AppIconButton(AppIcons.chevronLeft, tooltip: 'Previous', ghost: true, small: true, onPressed: () => i.value = (i.value - 1 + meals.length) % meals.length),
      AppIconButton(AppIcons.chevronRight, tooltip: 'Next', ghost: true, small: true, onPressed: () => i.value = (i.value + 1) % meals.length),
    ]),
    builder: (ctx) => ValueListenableBuilder(
      valueListenable: i,
      builder: (ctx, n, _) {
        final m = meals[n];
        final items = mealItems(m);
        double t(String k) => items.fold(0, (a, it) => a + _m(it, k));
        final opts = [for (final o in (m['options'] as List?) ?? const []) o as Map];
        Widget macros(double p, double cb, double f) => Wrap(spacing: 12, children: [
              for (final (l, v, col) in [('Protein', p, AppColors.accent), ('Carbs', cb, AppColors.carbs), ('Fat', f, AppColors.fat)])
                Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
                  Text.rich(TextSpan(text: '$l ', children: [TextSpan(text: '${_num(v)} g', style: AppText.s(12, W.w7))]), style: AppText.cap),
                ]),
            ]);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (n != start) Padding(padding: const EdgeInsets.only(top: 12), child: Text('${m['name']} · ${mealTime(m['time'])}', style: AppText.s(14, W.w8))),
          _kpis([('Calories', '${t('kcal').round()} kcal'), ('Protein', '${t('protein').round()} g'), ('Foods', '${items.length}'), ('Time', mealTime(m['time']))]),
          _sub('Foods'),
          if (items.isEmpty) Text('No foods in this meal yet.', style: AppText.sub),
          for (final it in items)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
                Row(spacing: 8, children: [
                  Expanded(child: Text('${(it['food_detail'] as Map?)?['name'] ?? ''}', style: AppText.s(13.5, W.w7))),
                  Text(portion(it), style: AppText.cap),
                  Text('${_m(it, 'kcal').round()} kcal', style: AppText.s(13, W.w7)),
                ]),
                macros(_m(it, 'protein'), _m(it, 'carbs'), _m(it, 'fat')),
              ]),
            ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
              Row(children: [Expanded(child: Text('Meal total', style: AppText.s(13.5, W.w8))), Text('${t('kcal').round()} kcal', style: AppText.s(13, W.w8))]),
              macros(t('protein'), t('carbs'), t('fat')),
            ]),
          ),
          if (opts.length > 1) _quote('Other options ${c.first} can pick', opts.where((o) => o != defaultOption(m)).map((o) => '${o['name']}').join(', ')),
          const SizedBox(height: 8),
        ]);
      },
    ),
    footer: (ctx) => [
      _fnote(ctx, Text(custom ? '${c.first}’s own copy · the master stays the same' : 'Same as the master plan', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cap)),
      if (!ctx.isPhone) AppButton('Close', onPressed: () => Navigator.of(ctx).pop()),
      AppButton.primary('Edit for ${c.first}', icon: AppIcons.edit, onPressed: () {
        Navigator.of(ctx).pop();
        onEdit();
      }),
    ],
  ).whenComplete(() => disposeLater([i]));
}

/// Habits `Edit for X`: the client's habits with their start day; remove one, or add habits from the library.
Future<bool?> showHabitsEditor(BuildContext context, {required CpController c, required PlansData d}) {
  final state = ValueNotifier<Map>(d.habits);
  var changed = false;
  Future<void> run(BuildContext ctx, Future<Map> Function() f, String ok) async {
    try {
      state.value = await f();
      changed = true;
      if (ctx.mounted) showToast(ctx, ok, sub: 'Only for ${c.first}', kind: ToastKind.ok);
    } on ApiError catch (e) {
      if (ctx.mounted) showToast(ctx, 'Could not save that', sub: e.message, kind: ToastKind.info);
    }
  }

  return showAppDrawer<bool>(
    context,
    title: 'Edit habits for ${c.first}',
    sub: 'Habits from the library · only ${c.first}’s list changes',
    icon: AppIcons.checkCircle,
    builder: (ctx) => ValueListenableBuilder(
      valueListenable: state,
      builder: (ctx, s, _) {
        final rows = [...PlansData.rows(s, 'current'), ...PlansData.rows(s, 'up_next')];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 8),
          if (rows.isEmpty) const EmptyState('No habits yet', sub: 'Add habits from the library below.'),
          for (final a in rows)
            () {
              final h = a['habit'] as Map;
              final target = h['kind'] == 'counter' && h['target'] != null ? '${NumberFormat.decimalPattern('en_IN').format(h['target'])} ${h['unit'] ?? ''}'.trim() : null;
              return AppRow(
                leading: cpIcon(AppIcons.checkCircle),
                title: '${h['name']}',
                sub: [
                  ?target,
                  '${h['frequency_label']}',
                  cpParse(a['start_date'])!.isAfter(DateTime.now()) ? 'starts ${cpDay(a['start_date'])}' : 'since ${cpDm(a['start_date'])}',
                  if (a['custom'] == true) 'changed for ${c.first}',
                ].join(' · '),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  AppIconButton(AppIcons.edit, tooltip: 'Edit', ghost: true, small: true, onPressed: () async {
                    final body = await _editHabit(ctx, c: c, a: a);
                    if (body == null || !ctx.mounted) return;
                    await run(ctx, () => Services.api.patch<Map>('clients/${c.id}/habit-plan/${a['id']}/', body), 'Saved ${h['name']}');
                  }),
                  AppIconButton(AppIcons.trash, tooltip: 'Remove', ghost: true, small: true, onPressed: () {
                    run(ctx, () => Services.api.post<Map>('clients/${c.id}/habit-plan/${a['id']}/end/', const {}), 'Removed ${h['name']}');
                  }),
                ]),
              );
            }(),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppButton('Add habit', icon: AppIcons.plus, onPressed: () async {
                final picked = await _pickHabits(ctx, have: {for (final a in rows) '${a['habit']['id']}'});
                if (picked == null || picked.isEmpty || !ctx.mounted) return;
                await run(ctx, () => Services.api.post<Map>('clients/${c.id}/habit-plan/', {'habits': picked, 'when': 'next'}),
                    picked.length == 1 ? 'Habit added' : '${picked.length} habits added');
              }),
            ),
          ),
        ]);
      },
    ),
    footer: (ctx) => [AppButton.primary('Done', onPressed: () => Navigator.of(ctx).pop(changed))],
  ).then((v) => v ?? changed).whenComplete(() => disposeLater([state]));
}

/// Edit habits → Edit: this client's target (counters), how often, which days / how many times a week, and a
/// note shown to the client. Returns the PATCH body, or null on Cancel. The library habit is not changed.
Future<Map<String, dynamic>?> _editHabit(BuildContext context, {required CpController c, required Map a}) {
  final h = a['habit'] as Map;
  final lib = (a['library'] as Map?) ?? h;
  final counter = h['kind'] == 'counter';
  final target = TextEditingController(text: h['target'] == null ? '' : '${h['target']}');
  final note = TextEditingController(text: '${a['note'] ?? ''}'.isNotEmpty ? '${a['note']}' : '${h['why'] ?? ''}');
  final freq = ValueNotifier('${h['frequency'] ?? 'daily'}');
  final days = ValueNotifier<Set<int>>({for (final d in (h['days'] as List?) ?? const []) (d as num).toInt()});
  final times = ValueNotifier(((h['times_per_week'] as num?) ?? 3).toInt());
  final err = ValueNotifier<String?>(null);
  const freqs = [('daily', 'Every day'), ('days', 'On some days'), ('times_week', 'Times a week')];

  Map<String, dynamic>? body() {
    final t = int.tryParse(target.text.trim().replaceAll(',', ''));
    if (counter && (t == null || t < 1)) {
      err.value = 'Enter a target, e.g. ${lib['target'] ?? 8000}.';
      return null;
    }
    if (freq.value == 'days' && days.value.isEmpty) {
      err.value = 'Pick at least one day.';
      return null;
    }
    return {
      if (counter) 'target': t,
      'frequency': freq.value,
      'days': (days.value.toList()..sort()),
      'times_per_week': freq.value == 'times_week' ? times.value : null,
      'note': note.text.trim(),
    };
  }

  Widget label(String t) => Text(t, style: AppText.label);
  return showAppModal<Map<String, dynamic>>(
    context,
    title: 'Edit ${h['name']} for ${c.first}',
    body: 'Only ${c.first}’s habit changes. The library habit stays ${'${lib['frequency_label'] ?? ''}'.toLowerCase()}${lib['target'] != null ? ' · ${lib['target']} ${lib['unit'] ?? ''}'.trimRight() : ''}.',
    icon: AppIcons.edit,
    content: (ctx) => ListenableBuilder(
      listenable: Listenable.merge([freq, days, times, err]),
      builder: (ctx, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        if (counter)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
            label('Target'),
            AppTextField(controller: target, keyboard: TextInputType.number, placeholder: '${lib['target'] ?? ''}', suffix: Text('${h['unit'] ?? ''}', style: AppText.cap)),
          ]),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
          label('How often'),
          fitTabsLeft(SegmentedTabs<String>(items: [for (final (k, l) in freqs) TabItem(k, l)], value: freq.value, onChanged: (v) => freq.value = v)),
          if (freq.value == 'days')
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var i = 0; i < 7; i++)
                FilterChipX(weekdayShort[i],
                    selected: days.value.contains(i),
                    onTap: () => days.value = days.value.contains(i) ? ({...days.value}..remove(i)) : {...days.value, i}),
            ]),
          if (freq.value == 'times_week')
            Row(spacing: 10, children: [
              AppIconButton(AppIcons.minus, tooltip: 'Fewer', small: true, onPressed: times.value <= 1 ? null : () => times.value--),
              Text('${times.value} times a week', style: AppText.s(13.5, W.w7, tabular: true)),
              AppIconButton(AppIcons.plus, tooltip: 'More', small: true, onPressed: times.value >= 7 ? null : () => times.value++),
            ]),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
          label('Note for ${c.first}'),
          AppTextField(controller: note, maxLines: 3, minLines: 2, placeholder: 'Why it matters, or how to do it'),
        ]),
        if (err.value != null) Text(err.value!, style: AppText.s(12.5, W.w6, color: AppColors.badText)),
      ]),
    ),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      AppButton.primary('Save', expand: ctx.isPhone, onPressed: () {
        final b = body();
        if (b != null) Navigator.of(ctx).pop(b);
      }),
    ],
  ).whenComplete(() => disposeLater([target, note, freq, days, times, err]));
}

/// `.dr-seg`: segment tabs as wide as their labels, on the left; they slide sideways when the drawer is narrow.
Widget fitTabsLeft(Widget tabs) => Align(alignment: Alignment.centerLeft, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: tabs));

Future<List<String>?> _pickHabits(BuildContext context, {required Set<String> have}) {
  final picked = ValueNotifier<Set<String>>({});
  final all = Services.api.get<List>('habits/');
  return showAppModal<List<String>>(
    context,
    title: 'Add habits',
    body: 'From the habit library',
    icon: AppIcons.plus,
    content: (ctx) => FutureBuilder<List>(
      future: all,
      builder: (ctx, snap) {
        if (!snap.hasData) return const CpLoading();
        final list = [for (final h in snap.data!) h as Map].where((h) => !have.contains('${h['id']}')).toList();
        if (list.isEmpty) return const EmptyState('Every habit is on the list already');
        return ValueListenableBuilder(
          valueListenable: picked,
          builder: (_, p, _) => Column(children: [
            for (final h in list)
              AppRow(
                leading: AppCheckbox(value: p.contains('${h['id']}')),
                title: '${h['name']}',
                sub: '${h['frequency_label']}',
                onTap: () => picked.value = p.contains('${h['id']}') ? ({...p}..remove('${h['id']}')) : {...p, '${h['id']}'},
              ),
          ]),
        );
      },
    ),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      ValueListenableBuilder(
        valueListenable: picked,
        builder: (_, p, _) => AppButton.primary(p.isEmpty ? 'Add' : 'Add ${p.length}', expand: ctx.isPhone, onPressed: p.isEmpty ? null : () => Navigator.of(ctx).pop(p.toList())),
      ),
    ],
  ).whenComplete(() => disposeLater([picked]));
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
