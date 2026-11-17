import 'package:flutter/cupertino.dart';

import '../icons/app_icons.dart';
import '../theme/theme.dart';
import 'button.dart';
import 'hover.dart';
import 'overlays.dart';
import 'responsive.dart';

/// "2 min 30 s", "45 s", "2 min".
String restLabel(int s) {
  if (s <= 0) return 'Off';
  if (s < 60) return '$s s';
  return s % 60 == 0 ? '${s ~/ 60} min' : '${s ~/ 60} min ${s % 60} s';
}

/// A rest time box (plan builder, exercise drawer): it shows the time; a tap opens two wheels, minutes and
/// seconds, so the coach picks it instead of typing "2 min 30 s" (Probid 17 Nov). [sameAs] adds "Same as Rest"
/// (null) for the warm-up / drop rests.
class RestField extends StatelessWidget {
  const RestField({super.key, required this.value, required this.onChanged, this.sameAs, this.title = 'Rest', this.height = 36, this.maxMinutes = 5});
  final int? value;
  final ValueChanged<int?> onChanged;

  /// The rest it falls back to when empty (shown as "same as Rest · 2 min"); null = it cannot be empty.
  final int? sameAs;
  final String title;
  final double height;
  final int maxMinutes;

  @override
  Widget build(BuildContext context) {
    final v = value;
    final empty = v == null;
    final text = empty ? 'Same as Rest${sameAs != null ? ' · ${restLabel(sameAs!)}' : ''}' : restLabel(v);
    return Semantics(
      button: true,
      label: '$title: $text',
      child: Hover(
        onTap: () => _pick(context),
        builder: (_, h, _) => Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: AppRadius.all(AppRadius.input),
            border: Border.all(color: h ? AppColors.accent : AppColors.line2),
          ),
          child: Row(spacing: 8, children: [
            Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w6, color: empty ? AppColors.muted : AppColors.text, tabular: true))),
            const AppIcon(AppIcons.clock, size: 16, color: AppColors.muted),
          ]),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final start = value ?? sameAs ?? 90;
    var m = (start ~/ 60).clamp(0, maxMinutes), s = ((start % 60) ~/ 5) * 5;
    final r = await showAppSheet<int>(
      context,
      title: title,
      sub: 'Minutes and seconds',
      webWidth: 380,
      builder: (ctx) => StatefulBuilder(
        builder: (_, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
          Text(restLabel(m * 60 + s), textAlign: TextAlign.center, style: AppText.s(22, W.w8, tabular: true)),
          SizedBox(
            height: 170,
            child: Row(children: [
              Expanded(child: _wheel(maxMinutes + 1, m, (i) => '$i min', (i) => set(() => m = i))),
              Expanded(child: _wheel(12, s ~/ 5, (i) => '${i * 5} s', (i) => set(() => s = i * 5))),
            ]),
          ),
        ]),
      ),
      footer: (ctx) => [
        if (sameAs != null) AppButton('Same as Rest', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop(-1)),
        AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
        AppButton.primary('Done', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop(m * 60 + s)),
      ],
    );
    if (r == null) return;
    onChanged(r < 0 ? null : r);
  }

  Widget _wheel(int n, int at, String Function(int) label, ValueChanged<int> on) => CupertinoPicker(
        scrollController: FixedExtentScrollController(initialItem: at),
        itemExtent: 38,
        useMagnifier: true,
        magnification: 1.08,
        selectionOverlay: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(color: AppColors.accentSoft.withValues(alpha: .6), borderRadius: BorderRadius.circular(8)),
        ),
        onSelectedItemChanged: on,
        children: [for (var i = 0; i < n; i++) Center(child: Text(label(i), style: AppText.s(16, W.w6, tabular: true)))],
      );
}
