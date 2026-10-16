import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../icons/app_icons.dart';
import '../theme/theme.dart';
import '../util/input_rules.dart';
import 'hover.dart';

/// Client-app components (the `ca-*`, `fd-*`, `wl-*` classes on the client boards).
/// Staff screens use button.dart / input.dart instead.

/// Web client pages use slightly smaller controls (40 high buttons, radius 10). Layouts set this.
class CaWeb extends InheritedWidget {
  const CaWeb({super.key, required this.web, required super.child});
  final bool web;
  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<CaWeb>()?.web ?? false;
  @override
  bool updateShouldNotify(CaWeb old) => old.web != web;
}

enum CaBtnKind { pri, out, dark }

/// `ca-btn`: 44 high, radius 12, 14.5/700 (web: 40, radius 10, 14).
class CaButton extends StatelessWidget {
  const CaButton(this.label,
      {super.key, this.onPressed, this.kind = CaBtnKind.pri, this.icon, this.trailingIcon, this.small = false, this.dimmed = false, this.loading = false, this.expand = true});
  final String label;
  final VoidCallback? onPressed;
  final CaBtnKind kind;
  final AppIconData? icon, trailingIcon;
  final bool small, dimmed, loading, expand;

  @override
  Widget build(BuildContext context) {
    final web = CaWeb.of(context);
    final h = small ? (web ? 32.0 : 34.0) : (web ? 40.0 : 44.0);
    final r = small && web ? 8.0 : (small || web ? 10.0 : 12.0);
    final fs = small ? 13.0 : (web ? 14.0 : 14.5);
    final pri = kind != CaBtnKind.out;
    final dark = kind == CaBtnKind.dark;
    return Opacity(
      opacity: dimmed || onPressed == null ? 0.55 : 1,
      child: Hover(
        onTap: loading ? null : onPressed,
        builder: (_, hov, _) {
          final fg = pri ? AppColors.white : AppColors.text;
          return Container(
            height: h,
            padding: EdgeInsets.symmetric(horizontal: small ? 12 : 16),
            decoration: BoxDecoration(
              color: dark
                  ? (hov ? AppColors.black : AppColors.text)
                  : pri
                      ? (hov ? AppColors.accentHover : AppColors.accent)
                      : (hov ? AppColors.outlineHover : AppColors.white),
              borderRadius: BorderRadius.circular(r),
              border: Border.all(color: pri ? Colors.transparent : AppColors.line),
            ),
            child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, spacing: small ? 5 : 7, children: [
              if (loading)
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
              else if (icon != null)
                AppIcon(icon!, size: small ? 15 : 17, color: fg),
              if (label.isNotEmpty) Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(fs, W.w7, color: fg, h: 1))),
              if (trailingIcon != null) AppIcon(trailingIcon!, size: 17, color: fg),
            ]),
          );
        },
      ),
    );
  }
}

/// `ca-ib sm`: square white icon button with a border.
class CaIconBtn extends StatelessWidget {
  const CaIconBtn(this.icon, {super.key, required this.onTap, this.size = 34, this.tooltip});
  final AppIconData icon;
  final VoidCallback? onTap;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final b = Hover(
      onTap: onTap,
      builder: (_, h, _) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: h ? AppColors.outlineHover : AppColors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
        child: AppIcon(icon, size: 16, color: AppColors.text2),
      ),
    );
    return tooltip == null ? b : Semantics(label: tooltip, button: true, child: b);
  }
}

/// `wl-lnk`: blue bold text link.
class CaLink extends StatelessWidget {
  const CaLink(this.label, {super.key, required this.onTap, this.size = 13.5, this.color = AppColors.accentText, this.weight = W.w7});
  final String label;
  final VoidCallback? onTap;
  final double size;
  final Color color;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Text(label,
            style: AppText.s(size, weight, color: color).copyWith(decoration: h ? TextDecoration.underline : null, decorationColor: color)),
      );
}

/// `fl-cb`: 18px checkbox square.
class CaCheckBox extends StatelessWidget {
  const CaCheckBox(this.on, {super.key});
  final bool on;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.accent : AppColors.white,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: on ? AppColors.accent : AppColors.line2, width: on ? 1 : 1.5),
        ),
        child: on ? const AppIcon(AppIcons.check, size: 12, color: AppColors.white, stroke: 3) : null,
      );
}

/// `wl-cbx`: checkbox + label (and optional second line). `boxed` = the white card version (`wl-notif`).
class CaCheckRow extends StatelessWidget {
  const CaCheckRow({super.key, required this.on, required this.onTap, required this.title, this.sub, this.boxed = false});
  final bool on;
  final VoidCallback onTap;
  final String title;
  final String? sub;
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final text = sub == null
        ? Text(title, style: AppText.s(13.5, W.w6))
        : Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
            Text(title, style: AppText.s(13.5, W.w7)),
            Text(sub!, style: AppText.s(12, W.w5, color: AppColors.muted)),
          ]);
    return Semantics(
      checked: on,
      button: true,
      child: Hover(
        onTap: onTap,
        builder: (_, _, _) => Container(
          padding: boxed ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12) : EdgeInsets.zero,
          decoration: boxed ? BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)) : null,
          child: Row(
            mainAxisSize: boxed || sub != null ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: sub == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            spacing: 10,
            children: [
              Padding(padding: EdgeInsets.only(top: sub == null ? 0 : 1), child: CaCheckBox(on)),
              if (sub == null) Flexible(child: text) else Expanded(child: text),
            ],
          ),
        ),
      ),
    );
  }
}

enum CaTone { blue, green, amber, gray, purple }

(Color, Color) caTone(CaTone t) => switch (t) {
      CaTone.blue => (AppColors.accentSoft, AppColors.infoText),
      CaTone.green => (AppColors.okBg, AppColors.okText),
      CaTone.amber => (AppColors.amberBg, AppColors.amberText),
      CaTone.gray => (AppColors.sub, AppColors.text2),
      CaTone.purple => (AppColors.purpleBg, AppColors.purpleText),
    };

/// `wl-hint`: tinted note with an icon and an optional link at the end.
class CaHint extends StatelessWidget {
  const CaHint(this.text, {super.key, required this.icon, this.tone = CaTone.blue, this.action, this.onAction});
  final String text;
  final AppIconData icon;
  final CaTone tone;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = caTone(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(spacing: 8, children: [
        AppIcon(icon, size: 16, color: fg),
        Expanded(child: Text(text, style: AppText.s(13, W.w6, color: fg, h: 1.4))),
        if (action != null) CaLink(action!, onTap: onAction, size: 13, color: fg),
      ]),
    );
  }
}

/// `fd-pill`: small rounded status label.
class CaPill extends StatelessWidget {
  const CaPill(this.label, {super.key, this.tone = CaTone.gray});
  final String label;
  final CaTone tone;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = caTone(tone);
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: AppText.s(11.5, W.w7, color: fg)),
    );
  }
}

/// `ca-card`: white card, radius 14, 1px line, 14 padding.
class CaCard extends StatelessWidget {
  const CaCard({super.key, required this.child, this.padding = const EdgeInsets.all(14)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        child: child,
      );
}

/// `fd-mi`: a tappable row (icon tile, two lines, trailing). Rows after the first get a top line.
class CaMenuRow extends StatelessWidget {
  const CaMenuRow({super.key, this.lead, required this.title, this.sub, this.trailing, this.onTap, this.divider = true, this.labelFirst = false, this.padX = 2});
  final Widget? lead;
  final String title;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divider;

  /// Small grey label on top, value below (profile summary rows).
  final bool labelFirst;
  final double padX;

  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          padding: EdgeInsets.symmetric(horizontal: padX, vertical: 10),
          decoration: BoxDecoration(border: divider ? const Border(top: BorderSide(color: AppColors.line)) : null),
          child: Row(spacing: 12, children: [
            ?lead,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                if (labelFirst) ...[
                  if (sub != null) Text(sub!, style: AppText.s(11.5, W.w7, color: AppColors.muted)),
                  Text(title, style: AppText.s(13.5, W.w7)),
                ] else ...[
                  Text(title, style: AppText.s(14, W.w7)),
                  if (sub != null) Text(sub!, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
                ],
              ]),
            ),
            ?trailing,
          ]),
        ),
      );
}

/// `fd-mic`: 34px rounded icon tile used at the start of [CaMenuRow].
class CaIconTile extends StatelessWidget {
  const CaIconTile({super.key, this.icon, this.text, this.tone});
  final AppIconData? icon;
  final String? text;
  final CaTone? tone;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = tone == null ? (AppColors.sub, AppColors.text) : caTone(tone!);
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: icon != null ? AppIcon(icon!, size: 16, color: fg) : Text(text ?? '', style: AppText.s(13, FontWeight.w900, color: tone == null ? AppColors.muted : fg)),
    );
  }
}

/// `wl-chips`: pill chips, single or multi pick. `small` = the blue-tint suggestion chips.
class CaChips<T> extends StatelessWidget {
  const CaChips({super.key, required this.options, required this.label, required this.isOn, required this.onTap, this.small = false, this.checkWhenOn = false});
  final List<T> options;
  final String Function(T) label;
  final bool Function(T) isOn;
  final void Function(T) onTap;
  final bool small, checkWhenOn;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (final o in options)
          Hover(
            onTap: () => onTap(o),
            builder: (_, h, _) {
              final on = isOn(o);
              final (bg, fg, bd) = on
                  ? (small ? (AppColors.accentSoft, AppColors.accentText, AppColors.accent) : (AppColors.text, AppColors.white, AppColors.text))
                  : (AppColors.white, AppColors.text2, h ? AppColors.line2 : AppColors.line);
              return Container(
                height: small ? 28 : 34,
                padding: EdgeInsets.symmetric(horizontal: small ? 10 : 13),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99), border: Border.all(color: bd)),
                child: Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
                  if (checkWhenOn && on) AppIcon(AppIcons.check, size: 13, color: fg, stroke: 2.8),
                  Text(label(o), style: AppText.s(small ? 12 : 13, W.w6, color: fg)),
                ]),
              );
            },
          ),
      ]);
}

/// `wl-seg`: 3-way segmented choice with a title and a small line under it.
class CaSeg extends StatelessWidget {
  const CaSeg({super.key, required this.options, required this.index, required this.onPick});
  final List<(String, String)> options;
  final int index;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(12)),
        child: Row(spacing: 4, children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: Hover(
                onTap: () => onPick(i),
                builder: (_, _, _) => AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  decoration: BoxDecoration(
                    color: i == index ? AppColors.white : null,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: i == index ? const [BoxShadow(color: Color(0x14171717), blurRadius: 2, offset: Offset(0, 1)), BoxShadow(color: AppColors.line, spreadRadius: 1)] : null,
                  ),
                  // As the boards draw it: both lines 11 px grey, the title bold (twv.css `.wl-seg > button span`
                  // also hits the title's text), the picked one only stands out by its white tile.
                  child: Column(spacing: 1, children: [
                    Text(options[i].$1, style: AppText.s(11, W.w7, color: AppColors.muted)),
                    Text(options[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11, W.w4, color: AppColors.muted)),
                  ]),
                ),
              ),
            ),
        ]),
      );
}

/// `dr-opt sm`: radio cards stacked.
class CaRadioCards extends StatelessWidget {
  const CaRadioCards({super.key, required this.options, required this.index, required this.onPick});
  final List<(String, String)> options;
  final int index;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) => Column(spacing: 6, children: [
        for (var i = 0; i < options.length; i++)
          Semantics(
            selected: i == index,
            button: true,
            child: Hover(
              onTap: () => onPick(i),
              builder: (_, h, _) {
                final on = i == index;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: on ? AppColors.pickBg : AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: on ? AppColors.accent : (h ? AppColors.lineHover : AppColors.line2)),
                    boxShadow: on ? const [BoxShadow(color: AppColors.accentSoft, spreadRadius: 3)] : null,
                  ),
                  child: Row(spacing: 12, children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(color: AppColors.white, shape: BoxShape.circle, border: Border.all(color: on ? AppColors.accent : AppColors.line2, width: on ? 5 : 1)),
                    ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(options[i].$1, style: AppText.s(13.5, W.w7)),
                        Text(options[i].$2, style: AppText.s(12.5, W.w4, color: AppColors.text2)),
                      ]),
                    ),
                  ]),
                );
              },
            ),
          ),
      ]);
}

/// `fd-step`: minus · value · plus.
class CaStepper extends StatelessWidget {
  const CaStepper({super.key, required this.value, required this.onMinus, required this.onPlus, this.button = 28, this.valueWidth, this.valueStyle});
  final String value;
  final VoidCallback onMinus, onPlus;
  final double button;
  final double? valueWidth;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: valueWidth == null ? MainAxisSize.max : MainAxisSize.min, spacing: 4, children: [
        CaIconBtn(AppIcons.minus, onTap: onMinus, size: button, tooltip: 'Less'),
        if (valueWidth == null)
          Expanded(child: Text(value, textAlign: TextAlign.center, style: valueStyle ?? AppText.s(15, W.w8, tabular: true)))
        else
          SizedBox(width: valueWidth, child: Text(value, textAlign: TextAlign.center, style: valueStyle ?? AppText.s(14, W.w7, tabular: true))),
        CaIconBtn(AppIcons.plus, onTap: onPlus, size: button, tooltip: 'More'),
      ]);
}

/// `wl-prog`: 5 segment progress (done green, current blue).
class CaSegments extends StatelessWidget {
  const CaSegments({super.key, required this.count, required this.isDone, this.current});
  final int count;
  final bool Function(int) isDone;
  final int? current;

  @override
  Widget build(BuildContext context) => Row(spacing: 5, children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 5,
              decoration: BoxDecoration(
                color: isDone(i) ? AppColors.okSolid : (i == current ? AppColors.accent : AppColors.segTrack),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
      ]);
}

/// `wl-fld` + `wl-in`: label, 44 high input, optional trailing widget and error line.
class CaField extends StatefulWidget {
  const CaField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.error,
    this.obscure = false,
    this.trailing,
    this.leading,
    this.keyboard,
    this.action,
    this.onSubmitted,
    this.onTap,
    this.autofill,
    this.focusNode,
    this.maxLength,
    this.enabled = true,
    this.autofocus = false,
  });
  final String label;
  final TextEditingController? controller;
  final String? hint, error;
  final bool obscure, enabled;

  /// The main field of a page: the cursor is in it when the page opens.
  final bool autofocus;
  final Widget? trailing;

  /// Text before the value, behind a thin line (`mo-pre`: "+91").
  final String? leading;
  final TextInputType? keyboard;
  final TextInputAction? action;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final Iterable<String>? autofill;
  final FocusNode? focusNode;
  final int? maxLength;

  @override
  State<CaField> createState() => _CaFieldState();
}

class _CaFieldState extends State<CaField> {
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
    final bad = widget.error != null;
    final focused = _focus.hasFocus;
    final border = bad ? AppColors.badText : (focused || _hover ? AppColors.accent : AppColors.line2);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 5, children: [
      Text(widget.label, style: AppText.s(12.5, W.w7, color: AppColors.text2)),
      MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.text,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 44,
          padding: EdgeInsets.only(left: 12, right: widget.trailing == null ? 12 : 8),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
            boxShadow: bad
                ? const [BoxShadow(color: AppColors.badBg, spreadRadius: 3)]
                : focused
                    ? const [BoxShadow(color: AppColors.accentSoft, spreadRadius: 3)]
                    : null,
          ),
          child: Row(spacing: 8, children: [
            if (widget.leading != null)
              Container(
                padding: const EdgeInsets.only(right: 6),
                decoration: const BoxDecoration(border: Border(right: BorderSide(color: AppColors.line))),
                child: Text(widget.leading!, style: AppText.s(14.5, W.w6, color: AppColors.muted)),
              ),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                enabled: widget.enabled,
                autofocus: widget.autofocus,
                obscureText: widget.obscure,
                obscuringCharacter: '•',
                keyboardType: widget.keyboard,
                textInputAction: widget.action,
                onSubmitted: widget.onSubmitted,
                onTap: widget.onTap,
                autofillHints: widget.autofill,
                inputFormatters: [...inputRules(widget.keyboard), if (widget.maxLength != null) LengthLimitingTextInputFormatter(widget.maxLength)],
                cursorColor: AppColors.accent,
                style: AppText.s(14.5, W.w6),
                decoration: InputDecoration.collapsed(hintText: widget.hint, hintStyle: AppText.s(14.5, W.w5, color: AppColors.muted)),
              ),
            ),
            ?widget.trailing,
          ]),
        ),
      ),
      if (bad)
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: AppIcon(AppIcons.alert, size: 14, color: AppColors.badText)),
          Expanded(child: Text(widget.error!, style: AppText.s(12.5, W.w6, color: AppColors.badText, h: 1.4))),
        ]),
    ]);
  }
}

/// `wl-show`: the grey Show / Hide button inside a password field.
class CaShowButton extends StatelessWidget {
  const CaShowButton({super.key, required this.shown, required this.onTap});
  final bool shown;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: h ? AppColors.line : AppColors.sub, borderRadius: BorderRadius.circular(7)),
          child: Text(shown ? 'Hide' : 'Show', style: AppText.s(12, W.w7, color: AppColors.text2)),
        ),
      );
}

/// `wl-q`: question heading with an optional muted line.
class CaQuestion extends StatelessWidget {
  const CaQuestion(this.title, {super.key, this.sub, this.pull = 4});
  final String title;
  final String? sub;

  /// `margin-bottom: -4px` (in a sheet body: -2): the next block sits closer than the page gap.
  final double pull;
  @override
  Widget build(BuildContext context) => Pull(
        bottom: pull,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
          Text(title, style: AppText.s(15.5, W.w8)),
          if (sub != null) Text(sub!, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
        ]),
      );
}

/// `fd-cap`: small muted caption, optional leading icon.
class CaCaption extends StatelessWidget {
  const CaCaption(this.text, {super.key, this.icon, this.pullUp = 0});
  final String text;
  final AppIconData? icon;

  /// `.wl-v > .fd-cap { margin-top: -8px }`: a caption right under a block on a page.
  final double pullUp;
  @override
  Widget build(BuildContext context) => Pull(
        top: pullUp,
        child: Text.rich(TextSpan(children: [
          if (icon != null) WidgetSpan(alignment: PlaceholderAlignment.middle, child: Padding(padding: const EdgeInsets.only(right: 4), child: AppIcon(icon!, size: 13, color: AppColors.muted))),
          TextSpan(text: text),
        ]), style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.45)),
      );
}

/// Negative margin: lays the child out as usual but reports it [top] / [bottom] shorter, so the
/// blocks around it sit closer (CSS `margin-top: -8px`). The child still paints in full.
class Pull extends SingleChildRenderObjectWidget {
  const Pull({super.key, this.top = 0, this.bottom = 0, super.child});
  final double top, bottom;
  @override
  RenderObject createRenderObject(BuildContext context) => RenderPull(top, bottom);
  @override
  void updateRenderObject(BuildContext context, RenderPull renderObject) => renderObject
    ..top = top
    ..bottom = bottom;
}

class RenderPull extends RenderShiftedBox {
  RenderPull(this._top, this._bottom) : super(null);
  double _top, _bottom;
  set top(double v) {
    if (v == _top) return;
    _top = v;
    markNeedsLayout();
  }

  set bottom(double v) {
    if (v == _bottom) return;
    _bottom = v;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    c.layout(constraints.copyWith(minHeight: 0), parentUsesSize: true);
    (c.parentData! as BoxParentData).offset = Offset(0, -_top);
    size = constraints.constrain(Size(c.size.width, (c.size.height - _top - _bottom).clamp(0, double.infinity)));
  }
}
