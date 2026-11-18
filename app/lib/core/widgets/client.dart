import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../icons/app_icons.dart';
import '../theme/theme.dart';
import '../util/input_rules.dart';
import 'hover.dart';
import 'overlays.dart' show OpenGuard;
import 'tooltip.dart';

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

/// Page with a fixed header: the title row stays at the top and only the content under it scrolls.
/// Phone: 16 side padding. Web: 32 side padding and the header is centred to [maxWidth] like the content.
class CaPinned extends StatefulWidget {
  const CaPinned({super.key, required this.head, required this.body, this.web = false, this.maxWidth = 1080, this.titleTop = 4});
  final Widget head;
  final Widget body;
  final bool web;
  final double maxWidth;

  /// Phone: the list's top padding above the [CaPageTitle] (where the moving title starts).
  final double titleTop;

  @override
  State<CaPinned> createState() => _CaPinnedState();
}

class _CaPinnedState extends State<CaPinned> {
  /// How far the page's own list has scrolled; the [CaTopBar] reads it for its shadow and small title.
  final _scrolled = ValueNotifier<double>(0);

  /// Phone: the head is a [CaTopBar] (Back, icons), the title is in the body (Strong, Probid 18 Nov).
  bool get _bar => !widget.web && widget.head is CaTopBar;

  @override
  void dispose() {
    _scrolled.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    // only the page's own up-down list, not a week strip or a chips row inside it
    if (n.depth == 0 && n.metrics.axis == Axis.vertical) _scrolled.value = n.metrics.pixels.clamp(0, 400).toDouble();
    return false;
  }

  /// Strong (Probid 18 Nov, with screenshots): the big title moves up with the page, one to one, and gets smaller as
  /// it goes; when it reaches the bar it stays there, small, on the left (next to Back).
  Widget _movingTitle(String title, double off, {required bool back, required int actions}) {
    const big = CaPageTitle.size;
    const endScale = CaPageTitle.barSize / big;
    final travel = _travel;
    final p = (off / travel).clamp(0.0, 1.0);
    // it rides with the page (y one to one) while the size and the step right to Back ease in and out, so the
    // change looks soft, not stepped (Probid 18 Nov: "thoda smooth")
    final q = Curves.easeInOut.transform(p);
    final y = CaTopBar.height + widget.titleTop - travel * p;
    final scale = 1 - (1 - endScale) * q;
    // the step right (next to Back) only in the last part, once the title is up at the bar; before that it stays
    // in line with the line under it
    final x = 16 + ((back ? 54.0 : 16.0) - 16) * Curves.easeInOut.transform(((p - .35) / .65).clamp(0.0, 1.0));
    return Stack(children: [
      Positioned(
        left: x,
        top: y,
        right: 16 + 44.0 * actions * p,
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.topLeft,
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: CaPageTitle.style),
        ),
      ),
    ]);
  }

  /// How far the page scrolls before its title is fully in the bar: from its place in the page (under the bar, after
  /// the list's top padding) up to the middle of the bar's 48 px row (which starts 4 down).
  double get _travel {
    const endH = CaPageTitle.size * CaPageTitle.lineH * CaPageTitle.barSize / CaPageTitle.size;
    return CaTopBar.height + widget.titleTop - (4 + 24 - endH / 2);
  }

  @override
  Widget build(BuildContext context) {
    if (_bar) {
      // The bar is painted over the top of the list, so its shadow falls on the content scrolling under it.
      final bar = widget.head as CaTopBar;
      final title = bar.title;
      return Stack(children: [
        Positioned.fill(
          top: CaTopBar.height,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            // No Android edge stretch on these pages: it squeezed the page under the bar and cut the big title, or slid
            // the line under it behind it (Probid 18 Nov). Pull to refresh still works.
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
              child: title == null ? widget.body : _CaTitleMoves(scrolled: _scrolled, child: widget.body),
            ),
          ),
        ),
        Positioned(left: 0, right: 0, top: 0, child: _CaBarScroll(scrolled: _scrolled, shadowFrom: bar.title == null ? 0 : _travel, child: bar)),
        if (title != null)
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<double>(
                valueListenable: _scrolled,
                // at rest the page shows its own title (see CaPageTitle); this one takes over once the page moves
                builder: (_, off, _) => off > 0 ? _movingTitle(title, off, back: bar.onBack != null, actions: bar.actions.length) : const SizedBox.shrink(),
              ),
            ),
          ),
      ]);
    }
    final web = widget.web;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: web ? const EdgeInsets.fromLTRB(32, 32, 32, 14) : const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: web ? Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: widget.maxWidth), child: widget.head)) : widget.head,
        ),
        Expanded(child: widget.body),
      ],
    );
  }
}

/// Tells a [CaPageTitle] inside the page that the bar draws its title (the moving one), so it keeps only its place.
class _CaTitleMoves extends InheritedWidget {
  const _CaTitleMoves({required this.scrolled, required super.child});
  final ValueNotifier<double> scrolled;
  @override
  bool updateShouldNotify(_CaTitleMoves old) => old.scrolled != scrolled;
}

/// Hands the page's scroll offset down to its [CaTopBar].
class _CaBarScroll extends InheritedWidget {
  const _CaBarScroll({required this.scrolled, required this.shadowFrom, required super.child});
  final ValueNotifier<double> scrolled;

  /// The scroll at which the bar's shadow starts: once the moving title is fully in the bar.
  final double shadowFrom;
  @override
  bool updateShouldNotify(_CaBarScroll old) => old.scrolled != scrolled || old.shadowFrom != shadowFrom;
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
        // a double tap acts once (Probid 2026-11-03)
        onTap: loading || onPressed == null ? null : () => OpenGuard.tap() ? onPressed!() : null,
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
              if (label.isNotEmpty) Flexible(child: CutText(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(fs, W.w7, color: fg, h: 1))),
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
  const CaIconBtn(this.icon, {super.key, required this.onTap, this.size = 34, this.tooltip, this.plain = false});
  final AppIconData icon;
  final VoidCallback? onTap;
  final double size;
  final String? tooltip;

  /// Only the icon, no box or border; a round splash on tap (page top bars, like Strong, Probid 18 Nov).
  final bool plain;

  @override
  Widget build(BuildContext context) {
    if (plain) return CaBarIcon(icon: AppIcon(icon, size: 21, color: AppColors.text2), onTap: onTap, tooltip: tooltip);
    final b = Hover(
      onTap: onTap == null ? null : () => OpenGuard.tap() ? onTap!() : null,
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

/// A bare icon in a page's top bar: 44 tap target, no box or border, a round ink splash on tap (Probid 18 Nov, like
/// Strong). [icon] can carry a badge (the bell's unread count).
class CaBarIcon extends StatelessWidget {
  const CaBarIcon({super.key, required this.icon, required this.onTap, this.tooltip});
  final Widget icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => Semantics(
        label: tooltip,
        button: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkResponse(
            onTap: onTap == null ? null : () => OpenGuard.tap() ? onTap!() : null,
            radius: 22,
            splashColor: AppColors.line2,
            highlightColor: AppColors.logField,
            hoverColor: AppColors.logFieldHover,
            child: SizedBox(width: 44, height: 44, child: Center(child: icon)),
          ),
        ),
      );
}

/// An empty list, said nicely: a soft round icon, a bold line and a short muted line, centred (Probid 18 Nov: the
/// food log said "Nothing logged" in one small grey line).
class CaEmpty extends StatelessWidget {
  const CaEmpty({super.key, required this.icon, required this.title, required this.sub});
  final AppIconData icon;
  final String title, sub;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.sub, shape: BoxShape.circle),
            child: AppIcon(icon, size: 24, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: AppText.s(15, W.w7)),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(sub, textAlign: TextAlign.center, style: AppText.s(13, W.w4, color: AppColors.muted, h: 1.4)),
          ),
        ]),
      );
}

/// A swipe left / right on [child] moves to the next / previous tab (Probid 18 Nov: Habits Day ⇄ Week, Food,
/// Progress, Past check-ins). Only a quick flick counts, so lists still scroll up and down and inner sliders keep their
/// own drags.
class CaSwipe extends StatelessWidget {
  const CaSwipe({super.key, required this.index, required this.count, required this.onPick, required this.child});
  final int index, count;
  final ValueChanged<int> onPick;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -350 && index < count - 1) onPick(index + 1);
          if (v > 350 && index > 0) onPick(index - 1);
        },
        child: child,
      );
}

/// A text action in a page's top bar ("Mark all read"): blue text, no box, a soft ink splash on tap (Probid 18 Nov).
class CaBarText extends StatelessWidget {
  const CaBarText(this.label, {super.key, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap == null ? null : () => OpenGuard.tap() ? onTap!() : null,
            borderRadius: BorderRadius.circular(10),
            splashColor: AppColors.line2,
            highlightColor: AppColors.logField,
            hoverColor: AppColors.logFieldHover,
            child: Container(
              height: 40,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(label, style: AppText.s(13.5, W.w7, color: onTap == null ? AppColors.muted : AppColors.accentText)),
            ),
          ),
        ),
      );
}

/// A page's top bar on the phone (Strong): Back on the left when there is one, bare action icons on the right, no
/// title. The page's title sits in the content under it and scrolls away with it (Probid 18 Nov).
class CaTopBar extends StatelessWidget {
  const CaTopBar({super.key, this.onBack, this.backTip = 'Back', this.actions = const [], this.title});
  final VoidCallback? onBack;
  final String backTip;
  final List<Widget> actions;

  /// The page's title: [CaPinned] moves the big [CaPageTitle] up into the bar as the page scrolls (Strong).
  final String? title;

  /// 4 top padding + 48 bar.
  static const height = 52.0;

  @override
  Widget build(BuildContext context) {
    final host = context.dependOnInheritedWidgetOfExactType<_CaBarScroll>();
    final scrolled = host?.scrolled;
    final from = host?.shadowFrom ?? 0;
    // The page title is drawn by [CaPinned]: it moves up with the page into this bar (Strong, Probid 18 Nov).
    Widget row(double off) => SizedBox(
          height: 48,
          child: Row(children: [
            if (onBack != null) CaBackBtn(tooltip: backTip, onTap: onBack),
            const Spacer(),
            ...actions,
          ]),
        );

    Widget bar(double off) {
      // a soft shadow only under the bar, once the title has fully come up into it (Strong, Probid 18 Nov)
      final s = ((off - from) / 8).clamp(0.0, 1.0);
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.caBg,
          boxShadow: s == 0 ? null : [for (final b in AppShadows.topBar) b.copyWith(color: b.color.withValues(alpha: b.color.a * s))],
        ),
        child: Padding(padding: const EdgeInsets.fromLTRB(4, 4, 6, 0), child: row(off)),
      );
    }

    if (scrolled == null) return bar(0);
    return ValueListenableBuilder<double>(valueListenable: scrolled, builder: (_, off, _) => bar(off));
  }
}

/// A page's big title and line under it, inside the scrolling content (Strong, Probid 18 Nov).
class CaPageTitle extends StatelessWidget {
  const CaPageTitle(this.title, {super.key, this.sub, this.trailing});

  /// Size and weight like Strong's page titles: a bit bigger, less bold (Probid 18 Nov).
  static const size = 29.0, lineH = 1.15, barSize = 19.0;
  static final style = AppText.s(size, W.w6, ls: -0.4, h: lineH);
  final String title;
  final String? sub;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 10, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // In a phone page with a top bar, once the page has scrolled the bar draws this title and moves it up into
            // itself (Strong). At rest it stays here, so Android's stretch at the edge moves it with the page and the
            // line under it does not slide behind it (Probid 18 Nov).
            Builder(builder: (context) {
              final text = Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: style);
              final moves = context.getInheritedWidgetOfExactType<_CaTitleMoves>();
              if (moves == null) return text;
              return ValueListenableBuilder<double>(
                valueListenable: moves.scrolled,
                builder: (_, off, child) => Opacity(opacity: off > 0 ? 0 : 1, child: child),
                child: text,
              );
            }),
            if (sub != null && sub!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: AppText.s(13, W.w5, color: AppColors.muted))),
          ]),
        ),
        ?trailing,
      ]);
}

/// The back button of a sub-page: a full ← arrow (shaft and head, like Android's; Probid 18 Nov, the chevron looked
/// like "<"), no box, a round ink splash on tap like the other top bar icons. One widget for every sub-page.
class CaBackBtn extends StatelessWidget {
  const CaBackBtn({super.key, required this.onTap, this.tooltip = 'Back'});
  final VoidCallback? onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) => CaBarIcon(
        tooltip: tooltip,
        onTap: onTap,
        icon: Transform.flip(flipX: true, child: const AppIcon(AppIcons.arrowRightAlt, size: 22, color: AppColors.text, stroke: 2)),
      );
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
        duration: Motion.of(context, Motion.short),
        curve: Motion.curve,
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
                  duration: Motion.of(context, Motion.short),
                  curve: Motion.curve,
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
                    CutText(options[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11, W.w4, color: AppColors.muted)),
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
      // the label takes the accent colour with the border while the field is focused (Phase 5)
      AnimatedDefaultTextStyle(
        duration: Motion.of(context, Motion.short),
        curve: Motion.curve,
        style: AppText.s(12.5, W.w7, color: bad ? AppColors.badText : (focused ? AppColors.accentText : AppColors.text2)),
        child: Text(widget.label),
      ),
      MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.text,
        // a tap anywhere in the box (not only on the one-line text) focuses it
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? () {
            _focus.requestFocus();
            widget.onTap?.call();
          } : null,
          child: AnimatedContainer(
          duration: Motion.of(context, Motion.short),
          curve: Motion.curve,
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

/// Lets a list run to the screen's edges inside a page that keeps [by] px on each side (Strong lists, Probid 18 Nov:
/// "screen touch honi chahiye list"). Takes the parent's width and lays the child out [by] wider on both sides.
class CaBleed extends SingleChildRenderObjectWidget {
  const CaBleed({super.key, this.by = 16, required Widget super.child});
  final double by;
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBleed(by);
  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) => (renderObject as _RenderBleed).by = by;
}

class _RenderBleed extends RenderProxyBox {
  _RenderBleed(this._by);
  double _by;
  set by(double v) {
    if (v == _by) return;
    _by = v;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final w = constraints.maxWidth + 2 * _by;
    child!.layout(constraints.copyWith(minWidth: w, maxWidth: w), parentUsesSize: true);
    size = constraints.constrain(Size(constraints.maxWidth, child!.size.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) => context.paintChild(child!, offset - Offset(_by, 0));

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => result.addWithPaintOffset(
        offset: Offset(-_by, 0),
        position: position,
        hitTest: (r, p) => child!.hitTest(r, position: p),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) => transform.translateByDouble(-_by, 0, 0, 1);
}
