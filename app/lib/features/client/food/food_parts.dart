import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/util/input_rules.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/tooltip.dart';

/// Pieces of the Food and Log food boards (`fd-*`, `nv-*`, `fl-*`).

/// `fd-step` with a number you can also type: − and + move by [step]; tap the number to type it.
class NumStepper extends StatefulWidget {
  const NumStepper({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.step = 1,
    this.min = 0,
    this.max = 99999,
    this.big = false,
    this.spread = false,
    this.btn = 34,
    this.decimals = true,
    this.name = 'amount',
  });
  final double value, step, min, max;
  final ValueChanged<double> onChanged;

  /// What the number shows when not typing ("60 g", "2 pieces", "210").
  final String Function(double) label;
  final bool big, spread, decimals;
  final double btn;
  final String name;

  @override
  State<NumStepper> createState() => _NumStepperState();
}

class _NumStepperState extends State<NumStepper> {
  final _t = TextEditingController();
  final _f = FocusNode();
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    _f.addListener(() {
      if (!_f.hasFocus && _typing) _commit();
    });
  }

  @override
  void dispose() {
    _t.dispose();
    _f.dispose();
    super.dispose();
  }

  String _plain(double v) => v == v.roundToDouble() ? '${v.round()}' : '${(v * 10).round() / 10}';

  void _edit() {
    _t.text = _plain(widget.value);
    _t.selection = TextSelection(baseOffset: 0, extentOffset: _t.text.length);
    setState(() => _typing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _f.requestFocus());
  }

  void _commit() {
    final v = double.tryParse(_t.text.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), ''));
    setState(() => _typing = false);
    if (v != null) widget.onChanged(v.clamp(widget.min, widget.max).toDouble());
  }

  void _move(int d) {
    if (_typing) _commit();
    final v = ((widget.value + d * widget.step) * 10).round() / 10;
    widget.onChanged(v.clamp(widget.min, widget.max).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final fs = widget.big ? 22.0 : (widget.spread ? 15.0 : 13.5);
    final style = AppText.s(fs, W.w8);
    final Widget number = _typing
        ? SizedBox(
            width: widget.big ? 120 : (widget.spread ? 64 : 74),
            child: TextField(
              controller: _t,
              focusNode: _f,
              textAlign: TextAlign.center,
              style: style,
              keyboardType: TextInputType.numberWithOptions(decimal: widget.decimals),
              inputFormatters: inputRules(TextInputType.numberWithOptions(decimal: widget.decimals)),
              cursorColor: AppColors.accent,
              onSubmitted: (_) => _commit(),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                filled: true,
                fillColor: AppColors.white,
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accent)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
              ),
            ),
          )
        : Semantics(
            button: true,
            label: 'Type the ${widget.name}',
            child: Hover(
              onTap: _edit,
              builder: (_, h, _) => Container(
                constraints: BoxConstraints(minWidth: widget.big ? 120 : (widget.spread ? 0 : 74)),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: h ? AppColors.accentSoft : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: CutText(
                  widget.label(widget.value),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ),
          );
    final r = widget.big ? 12.0 : 10.0;
    Widget b(AppIconData i, String tip, int d) => Semantics(
      button: true,
      label: tip,
      child: Hover(
        onTap: () => _move(d),
        builder: (_, h, _) => Container(
          width: widget.big ? 38 : widget.btn,
          height: widget.big ? 38 : widget.btn,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: h ? AppColors.outlineHover : AppColors.white,
            borderRadius: BorderRadius.circular(r),
            border: Border.all(color: AppColors.line),
          ),
          child: AppIcon(i, size: widget.big ? 19 : 16, color: AppColors.text2),
        ),
      ),
    );
    return Row(
      mainAxisSize: widget.spread ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: widget.spread ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
      spacing: 4,
      children: [
        b(AppIcons.minus, 'Less', -1),
        if (widget.spread) Flexible(child: number) else number,
        b(AppIcons.plus, 'More', 1),
      ],
    );
  }
}

/// `fd-pill`: Logged (green) / Next (blue) / Skipped, Missed (amber) / To log, Planned (grey).
Widget fdPill(String t) {
  final (bg, fg) = switch (t) {
    'Logged' => (AppColors.okBg, AppColors.okText),
    'Next' => (AppColors.infoBg, AppColors.infoText),
    'Skipped' || 'Missed' => (AppColors.amberBg, AppColors.amberText),
    _ => (AppColors.sub, AppColors.text2),
  };
  return Container(
    height: 22,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    alignment: Alignment.center,
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
    child: Text(t, style: AppText.s(11.5, W.w7, color: fg)),
  );
}

/// `fd-tag`: Planned / Mine (grey) or Off-plan (amber).
Widget fdTag(String t, {bool amber = false}) => Container(
  height: 18,
  margin: const EdgeInsets.only(left: 6),
  padding: const EdgeInsets.symmetric(horizontal: 6),
  alignment: Alignment.center,
  decoration: BoxDecoration(color: amber ? AppColors.amberBg : AppColors.sub, borderRadius: BorderRadius.circular(5)),
  child: Text(t, style: AppText.s(10.5, W.w7, color: amber ? AppColors.amberText : AppColors.text2)),
);

/// `fd-kv`: label left, bold value right, lines between.
Widget fdKv(List<(String, String)> rows) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    for (final (i, (l, v)) in rows.indexed)
      Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          spacing: 12,
          children: [
            Text(l, style: AppText.s(13.5, W.w6, color: AppColors.muted)),
            Expanded(
              child: Text(v, textAlign: TextAlign.right, style: AppText.s(13.5, W.w7)),
            ),
          ],
        ),
      ),
  ],
);

/// `fd-cap`: grey caption.
Widget fdCap(String t, {TextAlign align = TextAlign.start}) => Text(t, textAlign: align, style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.45));

/// `fd-mi`: a menu row in a sheet — icon tile, bold title, grey line, chevron.
class FdMenuItem extends StatelessWidget {
  const FdMenuItem({super.key, required this.icon, required this.title, required this.sub, required this.onTap, this.danger = false, this.first = false, this.chevron = true});
  final AppIconData icon;
  final String title, sub;
  final VoidCallback onTap;
  final bool danger, first, chevron;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: Hover(
      onTap: onTap,
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
        decoration: BoxDecoration(
          border: first ? null : const Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          spacing: 12,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: danger ? AppColors.badBg : AppColors.sub, borderRadius: BorderRadius.circular(10)),
              child: AppIcon(icon, size: 16, color: danger ? AppColors.badText : AppColors.text),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 1,
                children: [
                  Text(title, style: AppText.s(14, W.w7, color: danger ? AppColors.badText : (h ? AppColors.accentText : AppColors.text))),
                  Text(sub, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
                ],
              ),
            ),
            if (chevron && !danger) const AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}

/// `fd-else`: dashed "+ Ate something else" / "Search any other food".
class FdElse extends StatelessWidget {
  const FdElse(this.label, {super.key, required this.icon, required this.onTap, this.small = false});
  final String label;
  final AppIconData icon;
  final VoidCallback onTap;
  final bool small;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: Hover(
      onTap: onTap,
      builder: (_, h, _) => CustomPaint(
        foregroundPainter: _Dashed(h ? AppColors.accent : AppColors.tickRing),
        child: Container(
          height: small ? 38 : 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: h ? AppColors.white : null, borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              AppIcon(icon, size: 16, color: h ? AppColors.accentText : AppColors.text2),
              Text(label, style: AppText.s(small ? 13 : 13.5, W.w7, color: h ? AppColors.accentText : AppColors.text2)),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Dashed extends CustomPainter {
  _Dashed(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, d + 5), p);
      }
    }
  }

  @override
  bool shouldRepaint(_Dashed old) => old.color != color;
}

/// Round chips (`fl-try`, `fd-swf`, `fl-units`, `fl-why`).
class FdChip extends StatelessWidget {
  const FdChip(this.label, {super.key, required this.onTap, this.on = false, this.amber = false, this.height = 30});
  final String label;
  final VoidCallback onTap;
  final bool on, amber;
  final double height;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    child: Hover(
      onTap: onTap,
      builder: (_, h, _) {
        final (bg, line, fg) = on
            ? (amber ? (AppColors.amberBg, AppColors.amberLine, AppColors.amberDeep) : (AppColors.text, AppColors.text, AppColors.white))
            : (AppColors.white, h ? AppColors.accent : AppColors.line, h ? AppColors.accentText : AppColors.text2);
        return Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: height < 28 ? 10 : 12),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99), border: Border.all(color: line)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Text(label, style: AppText.s(height < 28 ? 12 : 12.5, W.w6, color: fg))]),
        );
      },
    ),
  );
}

/// `fd-ptot`: a total line in a soft box.
Widget fdTotal(String left, String right) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  decoration: BoxDecoration(
    color: AppColors.caWebBg,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: AppColors.line),
  ),
  child: Row(
    spacing: 8,
    children: [
      Expanded(child: Text(left, style: AppText.s(12.5, W.w7))),
      Text(right, style: AppText.s(12.5, W.w7, color: AppColors.accentText)),
    ],
  ),
);

/// A small outline button (`ca-btn out sm`) that fills its space.
Widget fdBtn(String label, VoidCallback onTap, {AppIconData? icon, CaBtnKind kind = CaBtnKind.out, AppIconData? trailing}) =>
    CaButton(label, kind: kind, small: true, icon: icon, trailingIcon: trailing, onPressed: onTap);
