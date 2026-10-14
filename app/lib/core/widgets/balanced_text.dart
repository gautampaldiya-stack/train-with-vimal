import 'package:flutter/widgets.dart';

/// Text that keeps its line count but makes the lines as even as possible,
/// like CSS `text-wrap: balance` (used by the big headlines on the boards).
class BalancedText extends StatelessWidget {
  const BalancedText(this.text, {super.key, required this.style, this.textAlign = TextAlign.start});
  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final scaler = MediaQuery.textScalerOf(context);
        TextPainter lay(double w) => TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: scaler)..layout(maxWidth: w);
        final max = c.maxWidth;
        if (!max.isFinite) return Text(text, style: style, textAlign: textAlign);
        final full = lay(max);
        final lines = full.computeLineMetrics().length;
        full.dispose();
        var lo = 0.0, hi = max;
        if (lines > 1) {
          // Narrowest width that still fits in the same number of lines.
          while (hi - lo > 1) {
            final mid = (lo + hi) / 2;
            final p = lay(mid);
            final n = p.computeLineMetrics().length;
            p.dispose();
            if (n > lines) {
              lo = mid;
            } else {
              hi = mid;
            }
          }
        }
        return Align(
          alignment: textAlign == TextAlign.center ? Alignment.topCenter : AlignmentDirectional.topStart,
          child: SizedBox(width: (hi + 1).clamp(0, max), child: Text(text, style: style, textAlign: textAlign)),
        );
      });
}
