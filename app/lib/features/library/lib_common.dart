import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/button.dart';

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
          const Spacer(),
          Text('$value', style: AppText.s(16, W.w8, tabular: true)),
          Flexible(child: Text(unit, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.muted))),
          const Spacer(),
          AppIconButton(AppIcons.plus, tooltip: 'More', small: true, onPressed: value < max ? () => onChanged((value + step).clamp(min, max)) : null),
        ]),
      );
}
