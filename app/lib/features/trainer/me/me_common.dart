import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/responsive.dart';

// Small pieces of the TrainerMe board shared by the tabs.

/// `.card` + `.card-h` (title, grey line, a text button on the right), 16px sides like the board.
class MeCard extends StatelessWidget {
  const MeCard({super.key, required this.title, this.sub, this.action, required this.child});
  final String title;
  final String? sub;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHeader(title, sub: sub, action: action, padding: const EdgeInsets.fromLTRB(16, 14, 16, 8)),
          child,
        ]),
      );
}

/// `.btn.text` 12.5: blue text button ("Edit", "All documents", "My clients").
class MeTextBtn extends StatelessWidget {
  const MeTextBtn(this.label, {super.key, required this.onTap, this.danger = false});
  final String label;
  final VoidCallback? onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(label,
              style: AppText.s(12.5, W.w7, color: danger ? AppColors.badText : (h ? AppColors.linkHover : AppColors.accent))),
        ),
      );
}

/// `.cp-kv.c2`: label over value, a line under each pair, two columns.
class MeKv extends StatelessWidget {
  const MeKv(this.items, {super.key, this.columns = 2, this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 14)});
  final List<(String, Widget)> items;
  final int columns;
  final EdgeInsetsGeometry padding;

  static Widget text(String v, {Color? color}) => Text(v.isEmpty ? '—' : v, style: AppText.s(13.5, W.w7, color: color ?? AppColors.text, h: 1.35));

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: LayoutBuilder(builder: (context, b) {
          const gap = 20.0;
          final w = (b.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(spacing: gap, children: [
            for (final (l, v) in items)
              Container(
                width: w,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
                  Text(l, style: AppText.s(12, W.w6, color: AppColors.muted)),
                  v,
                ]),
              ),
          ]);
        }),
      );
}

/// `.tp-lbl`: 11.5 / 600 uppercase muted label ("ABOUT YOU", "SOCIAL MEDIA").
Widget meLabel(String t) => Text(t.toUpperCase(), style: AppText.s(11.5, W.w6, color: AppColors.muted, ls: .46));

/// `.pk-chip` grey speciality chip.
Widget meChip(String t) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(5)),
      child: Text(t, style: AppText.s(11.5, W.w6, color: AppColors.text2)),
    );

AppIconData meSocialIcon(String k) => switch (k) {
      'instagram' => AppIcons.instagram,
      'youtube' => AppIcons.youtube,
      _ => AppIcons.web,
    };

/// `.tp-sl`: outlined 28 high link chip with an icon ("@aman.lifts").
Widget meSocial(String kind, String text) => Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(borderRadius: AppRadius.all(8), border: Border.all(color: AppColors.line)),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
        AppIcon(meSocialIcon(kind), size: 14, color: AppColors.muted),
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6))),
      ]),
    );

/// `.tp-dic`: 30 tile, amber for certificates, blue for ID, purple for contracts.
Widget meDocIcon(String kind, {double size = 30}) {
  final (ic, bg, fg) = switch (kind) {
    'certificate' => (AppIcons.award, AppColors.tlChBg, AppColors.tlChFg),
    'id_proof' => (AppIcons.idCard, AppColors.tlCiBg, AppColors.tlCiFg),
    _ => (AppIcons.file, AppColors.tlPlBg, AppColors.tlPlFg),
  };
  return IconTile(ic, size: size, bg: bg, fg: fg, radius: 8, iconSize: 15);
}

Tone meDocTone(Map d) => switch ('${d['status']}') {
      'verified' || 'signed' => Tone.ok,
      'expires_soon' => Tone.warn,
      'expired' => Tone.bad,
      _ => Tone.neutral,
    };

/// `.tp-perm`: a toggle row (bold line, grey line, switch on the right; locked rows say "Always").
class MeToggleRow extends StatelessWidget {
  const MeToggleRow({super.key, required this.title, required this.sub, required this.value, this.onChanged, this.locked = false});
  final String title, sub;
  final bool value, locked;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Hover(
        onTap: locked || onChanged == null ? null : () => onChanged!(!value),
        builder: (_, h, _) => Container(
          color: h && !locked ? AppColors.sub : null,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(spacing: 10, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text(title, style: AppText.s(13, W.w5)),
                Text(sub, style: AppText.s(11.5, W.w4, color: AppColors.muted)),
              ]),
            ),
            if (locked)
              Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
                const AppIcon(AppIcons.lock, size: 12, color: AppColors.muted),
                Text('Always', style: AppText.s(11.5, W.w5, color: AppColors.muted)),
              ])
            else
              AppToggle(value: value, onChanged: onChanged),
          ]),
        ),
      );
}

// ─────────────────────────────── Form bits (drawers and modals)

Widget meField(String? label, Widget child, {String? hint, String? error, bool req = false}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      if (label != null)
        Text.rich(TextSpan(text: label, style: AppText.label, children: [
          if (req) TextSpan(text: '*', style: AppText.s(12.5, W.w7, color: AppColors.badText)),
        ])),
      child,
      if (error != null)
        Text(error, style: AppText.s(12, W.w6, color: AppColors.badText))
      else if (hint != null)
        Text(hint, style: AppText.s(12, W.w5, color: AppColors.muted)),
    ]);

/// `.dr-sec`: 18 above and below, a line under, h4 title and an optional grey line.
class MeSec extends StatelessWidget {
  const MeSec(this.title, this.children, {super.key, this.sub, this.last = false});
  final String title;
  final String? sub;
  final List<Widget> children;
  final bool last;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(title, style: AppText.s(13.5, W.w8)),
            if (sub != null) Text(sub!, style: AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.35)),
          ]),
          ...children,
        ]),
      );
}

/// `.cp-g2`: two fields a row (one on a phone).
class MeGrid2 extends StatelessWidget {
  const MeGrid2(this.children, {super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, b) {
        final one = context.isPhone || b.maxWidth < 380;
        const gap = 12.0;
        final w = one ? b.maxWidth : (b.maxWidth - gap) / 2;
        return Wrap(spacing: gap, runSpacing: 14, children: [for (final c in children) SizedBox(width: w, child: c)]);
      });
}

/// `.dr-sw`: switch, bold line, grey line.
class MeSwitch extends StatelessWidget {
  const MeSwitch({super.key, required this.title, required this.sub, required this.value, required this.onChanged});
  final String title, sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: AppToggle(value: value, onChanged: onChanged)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text(title, style: AppText.s(13.5, W.w7)),
              Text(sub, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
            ]),
          ),
        ]),
      );
}

/// A date box that opens the date picker (fields take dates only through it).
class MeDateBox extends StatelessWidget {
  const MeDateBox({super.key, required this.value, required this.onPick, required this.placeholder, this.first, this.last, this.format, this.onClear});
  final DateTime? value;
  final ValueChanged<DateTime> onPick;
  final VoidCallback? onClear;
  final String placeholder;
  final DateTime? first, last;
  final String Function(DateTime)? format;

  @override
  Widget build(BuildContext context) => Hover(
        onTap: () async {
          final now = DateTime.now();
          final lo = first ?? DateTime(now.year - 80);
          final hi = last ?? DateTime(now.year + 30);
          var init = value ?? (now.isAfter(hi) ? hi : (now.isBefore(lo) ? lo : now));
          if (init.isAfter(hi)) init = hi;
          if (init.isBefore(lo)) init = lo;
          final v = await showDatePicker(context: context, initialDate: init, firstDate: lo, lastDate: hi);
          if (v != null) onPick(v);
        },
        builder: (_, h, _) => Container(
          height: 36,
          padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppRadius.all(AppRadius.input),
            border: Border.all(color: h ? AppColors.lineHover : AppColors.line2),
          ),
          child: Row(spacing: 8, children: [
            Expanded(
              child: Text(value == null ? placeholder : (format?.call(value!) ?? '${value!.day} / ${value!.month.toString().padLeft(2, '0')} / ${value!.year}'),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, value == null ? W.w5 : W.w6, color: value == null ? AppColors.muted : AppColors.text)),
            ),
            if (value != null && onClear != null)
              AppIconButton(AppIcons.close, tooltip: 'Clear', ghost: true, small: true, onPressed: onClear)
            else
              const AppIcon(AppIcons.calendar, size: 16, color: AppColors.muted),
          ]),
        ),
      );
}

/// Loading spinner / error card used by the tabs.
class MeLoading extends StatelessWidget {
  const MeLoading({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))),
      );
}

class MeError extends StatelessWidget {
  const MeError(this.message, {super.key, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => AppCard(child: EmptyState('Could not load this', sub: message, action: AppButton('Try again', onPressed: onRetry)));
}

/// Two columns on wide screens (board `.dash-cols`), one on phone and tablet.
class MeColumns extends StatelessWidget {
  const MeColumns({super.key, required this.left, required this.right, this.leftFlex = 1, this.rightFlex = 1, this.breakpoint = 980});
  final List<Widget> left, right;
  final int leftFlex, rightFlex;
  final double breakpoint;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, b) {
        if (b.maxWidth < breakpoint) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: context.isPhone ? 12 : 16, children: [...left, ...right]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
          Expanded(flex: leftFlex, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: left)),
          Expanded(flex: rightFlex, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: right)),
        ]);
      });
}
