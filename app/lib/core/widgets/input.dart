import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons/app_icon.dart';
import '../theme/theme.dart';

/// `.field` = label + `.inp` + hint/error (docs/design.md §3.2). Input 36 high, radius 8, focus ring accent-soft.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.label,
    this.hint,
    this.placeholder,
    this.error,
    this.controller,
    this.initial,
    this.onChanged,
    this.onSubmitted,
    this.obscure = false,
    this.keyboard,
    this.maxLines = 1,
    this.minLines,
    this.prefix,
    this.suffix,
    this.autofocus = false,
    this.enabled = true,
    this.height,
    this.formatters,
    this.textInputAction,
    this.autofill,
    this.focusNode,
    this.radius,
    this.fontSize,
  });
  final String? label, hint, placeholder, error, initial;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged, onSubmitted;
  final bool obscure, autofocus, enabled;
  final TextInputType? keyboard;
  final int maxLines;
  final int? minLines;
  final Widget? prefix, suffix;
  final double? height, radius, fontSize;
  final List<TextInputFormatter>? formatters;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofill;
  final FocusNode? focusNode;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final err = widget.error != null && widget.error!.isNotEmpty;
    final focused = _focus.hasFocus;
    final border = err ? AppColors.badText : (focused ? AppColors.accent : (_hover ? AppColors.lineHover : AppColors.line2));
    final multi = widget.maxLines > 1 || (widget.minLines ?? 1) > 1;
    final field = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: multi ? null : (widget.height ?? 36),
        constraints: multi ? const BoxConstraints(minHeight: 92) : null,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: multi ? 10 : 0),
        decoration: BoxDecoration(
          color: widget.enabled ? AppColors.white : AppColors.sub,
          borderRadius: AppRadius.all(widget.radius ?? AppRadius.input),
          border: Border.all(color: border),
          boxShadow: focused ? [BoxShadow(color: err ? AppColors.badBg : AppColors.accentSoft, spreadRadius: 3)] : null,
        ),
        child: Row(crossAxisAlignment: multi ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: [
          if (widget.prefix != null) Padding(padding: const EdgeInsets.only(right: 8), child: widget.prefix),
          Expanded(
            child: TextField(
              controller: widget.controller ?? (widget.initial != null ? TextEditingController(text: widget.initial) : null),
              focusNode: _focus,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              obscureText: widget.obscure,
              keyboardType: widget.keyboard,
              maxLines: widget.obscure ? 1 : (multi ? null : 1),
              minLines: widget.minLines,
              autofocus: widget.autofocus,
              enabled: widget.enabled,
              inputFormatters: widget.formatters,
              textInputAction: widget.textInputAction,
              autofillHints: widget.autofill,
              style: AppText.s(widget.fontSize ?? 14, W.w5),
              cursorHeight: 18,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: widget.placeholder,
                hintStyle: AppText.s(widget.fontSize ?? 14, W.w5, color: AppColors.muted),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (widget.suffix != null) Padding(padding: const EdgeInsets.only(left: 8), child: widget.suffix),
        ]),
      ),
    );
    if (widget.label == null && widget.hint == null && !err) return field;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, spacing: 6, children: [
      if (widget.label != null) Text(widget.label!, style: AppText.label),
      field,
      if (err)
        Text(widget.error!, style: AppText.s(12, W.w6, color: AppColors.badText))
      else if (widget.hint != null)
        Text(widget.hint!, style: AppText.cap),
    ]);
  }
}

/// `.search`: magnifier + placeholder, min-width 260.
class AppSearchField extends StatelessWidget {
  const AppSearchField({super.key, this.placeholder = 'Search', this.onChanged, this.controller, this.width, this.icon});
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;
  final double? width;
  final AppIconData? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: AppTextField(
          controller: controller,
          placeholder: placeholder,
          onChanged: onChanged,
          prefix: icon == null ? null : AppIcon(icon!, size: 16, color: AppColors.muted),
        ),
      );
}

/// Checkbox `.box` 16×16 radius 5; checked = accent fill + white tick.
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({super.key, required this.value, this.onChanged, this.size = 16});
  final bool value;
  final ValueChanged<bool>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: MouseRegion(
          cursor: onChanged == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: value ? AppColors.accent : AppColors.white,
              borderRadius: AppRadius.all(5),
              border: Border.all(color: value ? AppColors.accent : AppColors.line2, width: 1.5),
            ),
            child: value ? Icon(Icons.check_rounded, size: size - 4, color: AppColors.white) : null,
          ),
        ),
      );
}

/// Radio `.dr-radio` 18×18; selected = 5px accent border.
class AppRadio extends StatelessWidget {
  const AppRadio({super.key, required this.selected, this.onTap});
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.white,
            border: Border.all(color: selected ? AppColors.accent : AppColors.line2, width: selected ? 5 : 1.5),
          ),
        ),
      );
}

/// Toggle `.cp-tog` 30×18, knob 14, on = accent.
class AppToggle extends StatelessWidget {
  const AppToggle({super.key, required this.value, this.onChanged, this.width = 30, this.height = 18});
  final bool value;
  final ValueChanged<bool>? onChanged;
  final double width, height;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: MouseRegion(
          cursor: onChanged == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: width,
            height: height,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: value ? AppColors.accent : AppColors.line2, borderRadius: AppRadius.all(height)),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 150),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(width: height - 4, height: height - 4, decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle)),
            ),
          ),
        ),
      );
}
