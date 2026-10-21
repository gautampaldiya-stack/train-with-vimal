import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/badge.dart';
import '../../core/widgets/button.dart';
import '../../core/widgets/hover.dart';
import '../../core/widgets/responsive.dart';
import '../../core/widgets/tooltip.dart';

/// Shared bits of the Library pages (Programs, Exercises, Nutrition & foods, Habits & supplements, Content library).
/// They are the same pages for Vimal and trainers; what a trainer may change comes from the API (D-39).

const weekLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// "Edited 2 Oct" (this year) / "Edited 2 Oct 2025".
String editedOn(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (d == null) return '';
  final now = DateTime.now();
  return 'Edited ${DateFormat(d.year == now.year ? 'd MMM' : 'd MMM y').format(d)}';
}

/// `.pg-week`: 7 day cells, training days blue (grey on an archived card). [big] = the New program preview.
class WeekPattern extends StatelessWidget {
  const WeekPattern(this.days, {super.key, this.big = false, this.muted = false});
  final List<bool> days;
  final bool big, muted;

  @override
  Widget build(BuildContext context) => Semantics(
        label: [for (var i = 0; i < 7; i++) '${weekdayNames[i]} ${days[i] ? 'training' : 'rest'}'].join(', '),
        child: Row(spacing: 4, children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Container(
                height: big ? 32 : 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: days[i] ? (muted ? AppColors.line : AppColors.pgOnBg) : AppColors.sub,
                  borderRadius: AppRadius.all(6),
                ),
                child: Text(weekLetters[i],
                    style: AppText.s(big ? 12 : 10.5, W.w7, color: days[i] ? (muted ? AppColors.text2 : AppColors.accentText) : AppColors.muted)),
              ),
            ),
        ]),
      );
}

/// `.pg-step`: − value unit + in a 40 high box.
class LibStepper extends StatelessWidget {
  const LibStepper({super.key, required this.value, required this.unit, required this.min, required this.max, required this.onChanged, this.step = 1, this.height = 40});
  final int value, min, max, step;
  final String unit;
  final ValueChanged<int> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(borderRadius: AppRadius.all(AppRadius.input), border: Border.all(color: AppColors.line2)),
        child: Row(spacing: 8, children: [
          AppIconButton(AppIcons.minus, tooltip: 'Less', small: true, onPressed: value > min ? () => onChanged((value - step).clamp(min, max)) : null),
          // the value and its unit share all the room between the buttons, so "8 weeks" never shortens to "8 w…"
          Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 5, children: [
              Text('$value', style: AppText.s(16, W.w8, tabular: true)),
              if (unit.isNotEmpty) Flexible(child: Text(unit, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.muted))),
            ]),
          ),
          AppIconButton(AppIcons.plus, tooltip: 'More', small: true, onPressed: value < max ? () => onChanged((value + step).clamp(min, max)) : null),
        ]),
      );
}

/// Bumped when the Program builder closes, so the Programs page (still alive under it) reloads its cards.
final programsChanged = ValueNotifier<int>(0);

/// Bumped when an Exercise page or the Add / Edit exercise page closes, so the Exercise library reloads its cards.
final exercisesChanged = ValueNotifier<int>(0);

// ─────────────────────────────── Library filter (`ExerciseLibrary` Filter panel)

/// One filter category ("Muscle") with its options (value, label, count).
class LibFacet {
  const LibFacet(this.key, this.label, this.options);
  final String key, label;
  final List<(String, String, int)> options;
}

/// Picked options per category; several per category (multi-select).
typedef LibPicked = Map<String, Set<String>>;

int pickedCount(LibPicked p) => p.values.fold(0, (a, s) => a + s.length);

/// `Filter` outline button; with filters on it turns blue with the count.
class LibFilterButton extends StatelessWidget {
  const LibFilterButton({super.key, required this.count, required this.onTap});
  final int count;
  final void Function(BuildContext anchor) onTap;

  @override
  Widget build(BuildContext context) => Builder(
        builder: (b) => Hover(
          onTap: () => onTap(b),
          builder: (_, h, _) {
            final on = count > 0;
            return Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: on ? AppColors.accentSoft : (h ? AppColors.sub : AppColors.card),
                borderRadius: AppRadius.all(AppRadius.btn),
                border: Border.all(color: on ? AppColors.accent : AppColors.line2),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                AppIcon(AppIcons.filter, size: 15, color: on ? AppColors.accentText : AppColors.text),
                Text('Filter', style: AppText.button.copyWith(color: on ? AppColors.accentText : AppColors.text)),
                if (on) AppCount(count, color: AppColors.accent),
              ]),
            );
          },
        ),
      );
}

/// The two-panel filter menu: categories on the left (blue count when set), the open category's options on the
/// right with their counts and a tick on the picked ones. Picking keeps the menu open and changes [picked] at
/// once, so the list behind it filters as you go. Phone: both panels side by side across the width.
Future<void> showLibFilter(BuildContext anchor, {required List<LibFacet> facets, required ValueNotifier<LibPicked> picked}) {
  final box = anchor.findRenderObject() as RenderBox;
  final overlay = Overlay.of(anchor, rootOverlay: true).context.findRenderObject() as RenderBox;
  final at = box.localToGlobal(Offset.zero, ancestor: overlay);
  final phone = anchor.isPhone;
  // No option list until a category is hovered or clicked.
  int? cat;
  return showGeneralDialog(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: 'Filter',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 90),
    // Material: the panels' text gets the app's text style, not the debug yellow underline
    transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: Material(type: MaterialType.transparency, child: child)),
    pageBuilder: (ctx, _, _) => StatefulBuilder(
      builder: (ctx, set) => ValueListenableBuilder(
        valueListenable: picked,
        builder: (ctx, p, _) {
          Widget item({required Widget child, bool on = false, VoidCallback? onTap}) => Hover(
                onTap: onTap,
                builder: (_, h, _) => Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: h || on ? AppColors.sub : null, borderRadius: AppRadius.all(AppRadius.item)),
                  child: child,
                ),
              );
          final deco = BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.menu), border: Border.all(color: AppColors.line), boxShadow: AppShadows.menu);
          final cats = Container(
            padding: const EdgeInsets.all(6),
            decoration: deco,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 3, children: [
              for (final (i, c) in facets.indexed)
                MouseRegion(
                  onEnter: phone ? null : (_) => set(() => cat = i),
                  child: item(
                  on: i == cat,
                  onTap: () => set(() => cat = i),
                  child: Row(spacing: 6, children: [
                    Expanded(child: Text(c.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w5))),
                    if ((p[c.key] ?? const {}).isNotEmpty) AppCount(p[c.key]!.length, size: 18, color: AppColors.accent),
                    const AppIcon(AppIcons.chevronRight, size: 14, color: AppColors.muted),
                  ]),
                ),
                ),
              Container(height: 1, color: AppColors.line, margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2)),
              item(
                onTap: () => picked.value = {for (final c in facets) c.key: <String>{}},
                child: Align(alignment: Alignment.centerLeft, child: Text('Clear filters', style: AppText.s(13.5, W.w5, color: AppColors.muted))),
              ),
            ]),
          );
          final f = cat == null ? null : facets[cat!];
          final opts = f == null
              ? const SizedBox.shrink()
              : Container(
            padding: const EdgeInsets.all(6),
            decoration: deco,
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height - at.dy - box.size.height - 24),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 3, children: [
                Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 4), child: Text(f.label.toUpperCase(), style: AppText.over)),
                for (final (v, l, n) in f.options)
                  () {
                    final on = (p[f.key] ?? const {}).contains(v);
                    return item(
                      onTap: () {
                        final s = {...?p[f.key]};
                        on ? s.remove(v) : s.add(v);
                        picked.value = {...p, f.key: s};
                      },
                      child: Row(spacing: 8, children: [
                        Expanded(child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, on ? W.w7 : W.w5))),
                        Text('$n', style: AppText.s(12, W.w6, color: AppColors.muted)),
                        SizedBox(width: 16, child: on ? const AppIcon(AppIcons.check, size: 15, color: AppColors.accent, stroke: 2.4) : null),
                      ]),
                    );
                  }(),
              ]),
            ),
          );
          final top = at.dy + box.size.height + 6;
          if (phone) {
            return Stack(children: [
              Positioned(
                left: 16,
                right: 16,
                top: top,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [Expanded(child: cats), Expanded(child: opts)]),
              ),
            ]);
          }
          final left = at.dx.clamp(8.0, overlay.size.width - 440 - 8);
          return Stack(children: [
            Positioned(
              left: left,
              top: top,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [SizedBox(width: 210, child: cats), if (f != null) SizedBox(width: 220, child: opts)]),
            ),
          ]);
        },
      ),
    ),
  );
}

/// Chips under the tools: one per picked option ("Muscle Chest ×") and Clear all.
class LibFilterChips extends StatelessWidget {
  const LibFilterChips({super.key, required this.facets, required this.picked, this.trailing});
  final List<LibFacet> facets;
  final ValueNotifier<LibPicked> picked;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = picked.value;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
      Expanded(
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final f in facets)
            for (final (v, l, _) in f.options.where((o) => (p[f.key] ?? const {}).contains(o.$1)))
              SetChip(label: f.label, value: l, onRemove: () => picked.value = {...p, f.key: {...?p[f.key]}..remove(v)}),
          Hover(
            onTap: () => picked.value = {for (final f in facets) f.key: <String>{}},
            builder: (_, h, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text('Clear all', style: AppText.s(12.5, W.w7, color: h ? AppColors.linkHover : AppColors.accentText)),
            ),
          ),
        ]),
      ),
      ?trailing,
    ]);
  }
}


/// Who made a program (card tag): "Gym", "By you" or "By Aman", with the full line as a tooltip.
Widget ownerTag(Map o) {
  final kind = '${o['kind']}';
  final text = kind == 'gym' ? 'Gym' : (kind == 'you' ? 'By you' : 'By ${o['name']}');
  return AppTooltip(message: '${o['label']}', child: AppBadge(text, tone: kind == 'you' ? Tone.ok : Tone.neutral, plain: true));
}
