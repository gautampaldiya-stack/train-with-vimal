import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../util/input_rules.dart';
import 'hover.dart';

/// The number in a − n + stepper that can also be typed: tap it, type, Enter (or tap away) keeps it, clamped to
/// [min]–[max]. Same idea as the client's Log food amount (`NumStepper`), for the staff steppers.
class TypeNumber extends StatefulWidget {
  const TypeNumber({super.key, required this.value, required this.text, required this.onChanged, required this.min, required this.max, required this.style, this.name = 'amount', this.decimals = true, this.width = 60});
  final double value, min, max;

  /// What it shows when not typing ("60", "1.5").
  final String text;
  final ValueChanged<double> onChanged;
  final TextStyle style;
  final String name;
  final bool decimals;

  /// Width of the box while typing (it sits in a Row, so it needs one).
  final double width;

  @override
  State<TypeNumber> createState() => _TypeNumberState();
}

class _TypeNumberState extends State<TypeNumber> {
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

  void _edit() {
    final v = widget.value;
    _t.text = v == v.roundToDouble() ? '${v.round()}' : '${(v * 10).round() / 10}';
    _t.selection = TextSelection(baseOffset: 0, extentOffset: _t.text.length);
    setState(() => _typing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _f.requestFocus());
  }

  void _commit() {
    final v = double.tryParse(_t.text.replaceAll(',', '.'));
    setState(() => _typing = false);
    if (v != null) widget.onChanged(((v.clamp(widget.min, widget.max) * 10).round() / 10).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    if (_typing) {
      final k = TextInputType.numberWithOptions(decimal: widget.decimals);
      return SizedBox(
        width: widget.width,
        child: TextField(
          controller: _t,
          focusNode: _f,
          textAlign: TextAlign.center,
          style: widget.style,
          keyboardType: k,
          inputFormatters: inputRules(k),
          cursorColor: AppColors.accent,
          onSubmitted: (_) => _commit(),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            filled: true,
            fillColor: AppColors.white,
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.accent)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: 'Type the ${widget.name}',
      child: Hover(
        onTap: _edit,
        cursor: SystemMouseCursors.text,
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(color: h ? AppColors.accentSoft : null, borderRadius: BorderRadius.circular(6)),
          child: Text(widget.text, maxLines: 1, textAlign: TextAlign.center, style: widget.style),
        ),
      ),
    );
  }
}
