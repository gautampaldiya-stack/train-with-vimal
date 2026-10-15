import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';

/// Pieces of the Check-ins boards (`ck-*`), shared by the list, the two forms and the sheet.

/// `ck-q`: a question card — bold title, grey (or blue once answered) label on the right.
class CkQCard extends StatelessWidget {
  const CkQCard({super.key, required this.title, required this.label, this.got = false, required this.children});
  final String title, label;
  final bool got;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          spacing: 8,
          children: [
            Expanded(child: Text(title, style: AppText.s(14, W.w8))),
            Text(label, style: AppText.s(12, got ? W.w7 : W.w6, color: got ? AppColors.accentText : AppColors.muted)),
          ],
        ),
        ...children,
      ],
    ),
  );
}

/// `ck-scale`: five buttons, number over a word.
class CkScale extends StatelessWidget {
  const CkScale({super.key, required this.labels, required this.value, required this.onPick, this.lg = false});
  final List<String> labels;
  final int? value; // 1–5
  final ValueChanged<int> onPick;
  final bool lg;
  @override
  Widget build(BuildContext context) {
    final web = CaWeb.of(context);
    return Row(
      spacing: 5,
      children: [
        for (var i = 0; i < 5; i++)
          Expanded(
            child: Semantics(
              button: true,
              selected: value == i + 1,
              label: '${i + 1} ${labels[i]}',
              child: Hover(
                onTap: () => onPick(i + 1),
                builder: (_, h, _) {
                  final on = value == i + 1;
                  return Container(
                    padding: lg
                        ? const EdgeInsets.fromLTRB(2, 12, 2, 10)
                        : (web ? const EdgeInsets.fromLTRB(4, 10, 4, 9) : const EdgeInsets.fromLTRB(2, 7, 2, 6)),
                    decoration: BoxDecoration(
                      color: on ? AppColors.accent : AppColors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: on ? AppColors.accent : (h ? AppColors.lineHover : AppColors.line)),
                    ),
                    child: Column(
                      spacing: lg ? 3 : 1,
                      children: [
                        Text('${i + 1}', style: AppText.s(lg ? 20 : 15, W.w8, color: on ? AppColors.white : AppColors.text, h: 1.2)),
                        Text(
                          labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.s(lg ? 10.5 : (web ? 11 : 10), W.w6, color: on ? AppColors.white.withValues(alpha: .85) : AppColors.muted),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// `ch-qs ck-sl`: a grid of choice buttons (sleep hours), 4 a row on the phone, 7 on the web.
class CkChoiceGrid extends StatelessWidget {
  const CkChoiceGrid({super.key, required this.options, required this.value, required this.onPick});
  final List<String> options;
  final String? value;
  final ValueChanged<String> onPick;
  @override
  Widget build(BuildContext context) {
    final per = CaWeb.of(context) ? 7 : 4;
    final rows = <List<String>>[];
    for (var i = 0; i < options.length; i += per) {
      rows.add(options.sublist(i, (i + per).clamp(0, options.length)));
    }
    return Column(
      spacing: 6,
      children: [
        for (final r in rows)
          Row(
            spacing: 6,
            children: [
              for (var i = 0; i < per; i++)
                Expanded(
                  child: i >= r.length
                      ? const SizedBox()
                      : Semantics(
                          button: true,
                          selected: value == r[i],
                          child: Hover(
                            onTap: () => onPick(r[i]),
                            builder: (_, h, _) {
                              final on = value == r[i];
                              return Container(
                                height: 34,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: on ? AppColors.text : (h ? AppColors.outlineHover : AppColors.white),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: on ? AppColors.text : AppColors.line),
                                ),
                                child: Text(r[i], maxLines: 1, style: AppText.s(13, W.w7, color: on ? AppColors.white : AppColors.text)),
                              );
                            },
                          ),
                        ),
                ),
            ],
          ),
      ],
    );
  }
}

/// `fd-step lg` inside `ck-num`: round − / + and the big value.
class CkStepper extends StatelessWidget {
  const CkStepper({super.key, required this.value, required this.onMinus, required this.onPlus, this.under});
  final String value;
  final VoidCallback onMinus, onPlus;
  final Widget? under;
  @override
  Widget build(BuildContext context) => Column(
    spacing: 4,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 4,
        children: [
          _round(AppIcons.minus, 'Less', onMinus),
          SizedBox(
            width: 120,
            child: Text(value, textAlign: TextAlign.center, style: AppText.s(22, W.w8, tabular: true)),
          ),
          _round(AppIcons.plus, 'More', onPlus),
        ],
      ),
      ?under,
    ],
  );

  Widget _round(AppIconData icon, String label, VoidCallback onTap) => Semantics(
    label: label,
    button: true,
    child: Hover(
      onTap: onTap,
      builder: (_, h, _) => Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: h ? AppColors.outlineHover : AppColors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.line),
        ),
        child: AppIcon(icon, size: 19, color: AppColors.text2),
      ),
    ),
  );
}

/// `fl-try`: small round suggestion chips, with an optional grey lead word.
class CkTry extends StatelessWidget {
  const CkTry({super.key, this.lead, required this.items, required this.onPick});
  final String? lead;
  final List<String> items;
  final ValueChanged<String> onPick;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (lead != null) Text(lead!, style: AppText.s(12, W.w6, color: AppColors.muted)),
      for (final t in items)
        Hover(
          onTap: () => onPick(t),
          builder: (_, h, _) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: h ? AppColors.accent : AppColors.line),
            ),
            child: Text(t, style: AppText.s(12, W.w6, color: h ? AppColors.accentText : AppColors.text2)),
          ),
        ),
    ],
  );
}

/// `fl-in ck-in`: the note / answer box (taller with [area]).
class CkInput extends StatelessWidget {
  const CkInput({super.key, required this.controller, required this.hint, this.area = false, this.onChanged});
  final TextEditingController controller;
  final String hint;
  final bool area;
  final VoidCallback? onChanged;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Container(
      constraints: BoxConstraints(minHeight: area ? 76 : 40),
      padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: area ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        spacing: 6,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: area ? 3 : 1,
              maxLines: area ? 6 : 3,
              maxLength: area ? 3000 : 200,
              onChanged: (_) => onChanged?.call(),
              style: AppText.s(13.5, W.w6, h: 1.4),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                border: InputBorder.none,
                hintText: hint,
                hintStyle: AppText.s(13.5, W.w5, color: AppColors.muted, h: 1.4),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: area ? 7 : 0),
              child: Semantics(
                label: area ? 'Clear answer' : 'Clear note',
                button: true,
                child: Hover(
                  onTap: () {
                    controller.clear();
                    onChanged?.call();
                  },
                  builder: (_, h, _) => Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: h ? AppColors.line : AppColors.sub, borderRadius: BorderRadius.circular(10)),
                    child: const AppIcon(AppIcons.close, size: 14, color: AppColors.text2),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// `ck-auto` / `ck-wait`: blue note with an icon.
Widget ckInfo(String text, {AppIconData icon = AppIcons.info}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(10)),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: AppIcon(icon, size: 16, color: AppColors.infoText),
      ),
      Expanded(
        child: Text(text, style: AppText.s(12.5, W.w5, color: AppColors.infoText, h: 1.45)),
      ),
    ],
  ),
);

/// `ch-prog ck-bar`: thin blue progress line.
class CkBar extends StatelessWidget {
  const CkBar(this.ratio, {super.key, this.height = 5});
  final double ratio;
  final double height;
  @override
  Widget build(BuildContext context) => Container(
    height: height,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(color: AppColors.barTrack, borderRadius: BorderRadius.circular(6)),
    child: Align(
      alignment: Alignment.centerLeft,
      child: AnimatedFractionallySizedBox(
        duration: const Duration(milliseconds: 200),
        widthFactor: ratio.clamp(0.0, 1.0),
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(6)),
        ),
      ),
    ),
  );
}

/// `fl-top`: back button, big title, grey line (forms).
class CkTop extends StatelessWidget {
  const CkTop({super.key, required this.title, required this.sub, required this.onBack, this.backLabel = 'Back to check-ins'});
  final String title, sub, backLabel;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) {
    final web = CaWeb.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        spacing: 10,
        children: [
          CaIconBtn(AppIcons.chevronLeft, tooltip: backLabel, onTap: onBack),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.s(web ? 24 : 20, W.w8, ls: web ? -.24 : -.2, h: 1.2)),
                Text(sub, style: AppText.s(12, W.w6, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `ck-done`: the green tick card after sending.
class CkDone extends StatelessWidget {
  const CkDone({super.key, required this.title, required this.sub, required this.rows, required this.buttons});
  final String title, sub;
  final List<(String, String)> rows;
  final Widget buttons;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      spacing: 6,
      children: [
        Container(
          width: 52,
          height: 52,
          margin: const EdgeInsets.only(bottom: 4),
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppColors.okSolid, shape: BoxShape.circle),
          child: const AppIcon(AppIcons.check, size: 26, color: AppColors.white, stroke: 2.6),
        ),
        Text(title, textAlign: TextAlign.center, style: AppText.s(18, W.w8)),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: AppText.s(12.5, W.w4, color: AppColors.muted),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Column(
            children: [
              for (final (i, (k, v)) in rows.indexed)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 12,
                    children: [
                      Text(k, style: AppText.s(13, W.w6, color: AppColors.muted)),
                      Expanded(
                        child: Text(v, textAlign: TextAlign.right, style: AppText.s(13, W.w7)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        buttons,
      ],
    ),
  );
}

/// A photo answer kept as a data URL (works offline, goes through the outbox).
Uint8List? dataBytes(String? url) {
  if (url == null) return null;
  final i = url.indexOf(',');
  if (i < 0) return null;
  try {
    return base64Decode(url.substring(i + 1));
  } on FormatException {
    return null;
  }
}

/// Dashed rounded border (`ck-slot`).
class DashedBox extends StatelessWidget {
  const DashedBox({super.key, required this.child, this.color = AppColors.tickRing, this.radius = 12});
  final Widget child;
  final Color color;
  final double radius;
  @override
  Widget build(BuildContext context) => CustomPaint(foregroundPainter: _Dash(color, radius), child: child);
}

class _Dash extends CustomPainter {
  _Dash(this.color, this.radius);
  final Color color;
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(.75));
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 5), p);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_Dash old) => old.color != color;
}
