import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../icons/app_icons.dart';
import '../theme/theme.dart';
import 'button.dart';
import 'card.dart';
import 'client.dart';
import 'hover.dart';
import 'responsive.dart';
import 'tooltip.dart';

// ─────────────────────────────── Menu (docs/design.md §4.1)

class MenuEntry {
  const MenuEntry(this.label, {this.icon, this.lead, this.onTap, this.danger = false, this.selected = false, this.end, this.header = false, this.separator = false, this.sub});
  const MenuEntry.header(this.label)
      : icon = null, lead = null, onTap = null, danger = false, selected = false, end = null, header = true, separator = false, sub = null;
  const MenuEntry.separator()
      : label = '', icon = null, lead = null, onTap = null, danger = false, selected = false, end = null, header = false, separator = true, sub = null;

  /// A small widget in place of the icon (e.g. the diet mark in the Diet select).
  final Widget? lead;
  final String label;

  /// Grey line under the label (`.pb-ms`, e.g. "Swap with Monday"); the row grows to fit it.
  final String? sub;
  final AppIconData? icon;
  final VoidCallback? onTap;
  final bool danger, selected, header, separator;
  final String? end;
}

/// Opens `.menu` anchored under [anchor]: white, radius 12, padding 6, items 34 high, picked item has a tick.
Future<void> showAppMenu(BuildContext anchor, List<MenuEntry> entries, {double width = 200, bool alignRight = true}) async {
  if (anchor.isPhone) return showActionSheet(anchor, entries);
  final box = anchor.findRenderObject() as RenderBox;
  final overlay = Overlay.of(anchor, rootOverlay: true).context.findRenderObject() as RenderBox;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final size = overlay.size;
  final left = alignRight ? (topLeft.dx + box.size.width - width) : topLeft.dx;
  final below = topLeft.dy + box.size.height + 6;
  // Opens on the side with room; a long list gets that side's height and scrolls, starting at the picked row.
  final need = 12 + _rowH * entries.length + 14.0 * entries.where((e) => e.sub != null).length;
  final roomBelow = size.height - below - 12, roomAbove = topLeft.dy - 6 - 12;
  final openUp = need > roomBelow && roomAbove > roomBelow;
  final maxH = (openUp ? roomAbove : roomBelow).clamp(120.0, 420.0);
  final picked = entries.indexWhere((e) => e.selected);
  final start = picked <= 0 ? 0.0 : (_rowH * picked - (maxH - _rowH) / 2).clamp(0.0, (need - maxH).clamp(0.0, double.infinity));
  await showGeneralDialog(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: 'menu',
    barrierColor: Colors.transparent,
    transitionDuration: Motion.of(anchor, Motion.short),
    transitionBuilder: _menuIn,
    pageBuilder: (ctx, _, _) => Stack(children: [
      Positioned(
        left: left.clamp(8, size.width - width - 8),
        top: openUp ? null : below,
        bottom: openUp ? size.height - topLeft.dy + 6 : null,
        width: width,
        child: _MenuBox(entries: entries, maxHeight: maxH, start: start, close: () => Navigator.of(ctx).pop()),
      ),
    ]),
  );
}

/// One menu row (34) plus the gap under it (3).
const _rowH = 37.0;

class _MenuBox extends StatefulWidget {
  const _MenuBox({required this.entries, required this.close, this.maxHeight = 420, this.start = 0});
  final List<MenuEntry> entries;
  final VoidCallback close;
  final double maxHeight, start;
  @override
  State<_MenuBox> createState() => _MenuBoxState();
}

class _MenuBoxState extends State<_MenuBox> {
  late final scroll = ScrollController(initialScrollOffset: widget.start);
  List<MenuEntry> get entries => widget.entries;
  VoidCallback get close => widget.close;

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(6),
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.menu), border: Border.all(color: AppColors.line), boxShadow: AppShadows.menu),
          child: SingleChildScrollView(
            controller: scroll,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 3, children: [
              for (final e in entries)
                if (e.separator)
                  Container(height: 1, color: AppColors.line, margin: const EdgeInsets.symmetric(vertical: 3))
                else if (e.header)
                  Padding(padding: const EdgeInsets.fromLTRB(10, 6, 10, 2), child: Text(e.label.toUpperCase(), style: AppText.over))
                else
                  Hover(
                    onTap: e.onTap == null
                        ? null
                        : () {
                            close();
                            e.onTap!();
                          },
                    builder: (context, h, _) {
                      final fg = e.danger ? AppColors.badText : AppColors.text;
                      return Container(
                        height: e.sub == null ? 34 : null,
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: e.sub == null ? 0 : 7),
                        decoration: BoxDecoration(color: h ? (e.danger ? AppColors.badBg : AppColors.sub) : null, borderRadius: AppRadius.all(AppRadius.item)),
                        child: Row(spacing: 10, children: [
                          if (e.icon != null) AppIcon(e.icon!, size: 16, color: e.danger ? AppColors.badText : AppColors.muted),
                          ?e.lead,
                          Expanded(
                            child: e.sub == null
                                ? CutText(e.label, style: AppText.s(13.5, e.selected ? W.w7 : W.w5, color: fg), overflow: TextOverflow.ellipsis)
                                : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                    CutText(e.label, style: AppText.s(13.5, W.w5, color: fg), overflow: TextOverflow.ellipsis),
                                    CutText(e.sub!, style: AppText.s(11.5, W.w5, color: AppColors.muted), overflow: TextOverflow.ellipsis),
                                  ]),
                          ),
                          if (e.end != null) Text(e.end!, style: AppText.s(12, W.w5, color: AppColors.muted)),
                          if (e.selected) AppIcon(AppIcons.check, size: 15, color: AppColors.accent, stroke: 2.2),
                        ]),
                      );
                    },
                  ),
            ]),
          ),
        ),
      );
}

/// On phone a menu becomes an actions bottom sheet.
Future<void> showActionSheet(BuildContext context, List<MenuEntry> entries, {String? title}) => showAppSheet(
      context,
      title: title,
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final e in entries)
          if (e.separator)
            const Divider1()
          else if (e.header)
            Padding(padding: const EdgeInsets.fromLTRB(4, 10, 4, 4), child: Text(e.label.toUpperCase(), style: AppText.over))
          else
            Hover(
              onTap: e.onTap == null
                  ? null
                  : () {
                      Navigator.of(ctx).pop();
                      e.onTap!();
                    },
              builder: (_, h, _) => Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(spacing: 12, children: [
                  if (e.icon != null) AppIcon(e.icon!, size: 18, color: e.danger ? AppColors.badText : AppColors.text2),
                  ?e.lead,
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(e.label, style: AppText.s(14.5, e.selected ? W.w7 : W.w6, color: e.danger ? AppColors.badText : AppColors.text)),
                      if (e.sub != null) Text(e.sub!, style: AppText.s(12, W.w5, color: AppColors.muted)),
                    ]),
                  ),
                  if (e.end != null) Text(e.end!, style: AppText.cap),
                  if (e.selected) AppIcon(AppIcons.check, size: 16, color: AppColors.accent, stroke: 2.2),
                ]),
              ),
            ),
      ]),
    );

// ─────────────────────────────── Modal (§4.2). On phone it opens as a bottom sheet.

Future<T?> showAppModal<T>(
  BuildContext context, {
  required String title,
  String? body,
  AppIconData? icon,
  bool danger = false,
  bool wide = false,
  double? width,
  Widget Function(BuildContext)? content,
  List<Widget> Function(BuildContext)? actions,
  Widget? lead,
}) {
  if (context.isPhone) {
    return showAppSheet<T>(context, title: title, sub: body, builder: content ?? (_) => const SizedBox.shrink(), footer: actions);
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: AppColors.scrimModal,
    transitionDuration: Motion.of(context, Motion.medium),
    transitionBuilder: _popIn,
    pageBuilder: (ctx, _, _) => Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: width ?? (wide ? 560 : 440),
          margin: const EdgeInsets.all(24),
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .88),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.modal), boxShadow: AppShadows.modal),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 18, 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
                if (icon != null) IconTile(icon, size: 36, bg: danger ? AppColors.badBg : AppColors.accentSoft, fg: danger ? AppColors.badText : AppColors.accent, radius: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
                    Text(title, style: AppText.s(16.5, W.w8, ls: -0.2)),
                    if (body != null) Text(body, style: AppText.s(13, W.w5, color: AppColors.muted, h: 1.5)),
                  ]),
                ),
                AppIconButton(AppIcons.close, tooltip: 'Close', ghost: true, small: true, onPressed: () => Navigator.of(ctx).pop()),
              ]),
            ),
            if (content != null) Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 4), child: content(ctx))),
            if (actions != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                child: Row(spacing: 8, children: [if (lead != null) Expanded(child: lead) else const Spacer(), ...actions(ctx)]),
              ),
          ]),
        ),
      ),
    ),
  );
}

/// Confirm modal with a red or blue main action. Returns true when confirmed.
Future<bool> confirmAction(BuildContext context,
    {required String title, String? body, required String confirm, bool danger = false, AppIconData? icon}) async {
  final r = await showAppModal<bool>(
    context,
    title: title,
    body: body,
    icon: icon,
    danger: danger,
    // Phone sheet: Cancel and the action side by side, not stacked (Probid 2026-10-30).
    actions: (ctx) => ctx.isPhone
        ? [
            Row(spacing: 8, children: [
              Expanded(child: AppButton('Cancel', onPressed: () => Navigator.of(ctx).pop(false), expand: true)),
              Expanded(child: AppButton(confirm, kind: danger ? BtnKind.danger : BtnKind.primary, onPressed: () => Navigator.of(ctx).pop(true), expand: true)),
            ]),
          ]
        : [
            AppButton('Cancel', onPressed: () => Navigator.of(ctx).pop(false)),
            AppButton(confirm, kind: danger ? BtnKind.danger : BtnKind.primary, onPressed: () => Navigator.of(ctx).pop(true)),
          ],
  );
  return r ?? false;
}

/// Every Duplicate asks first (Gautam 2026-10-23). [what] is the thing being copied, e.g. "Fat loss 12 weeks".
Future<bool> confirmDuplicate(BuildContext context, String what, {String? body}) => confirmAction(
      context,
      title: 'Duplicate $what?',
      body: body ?? 'A copy is made with the same content. The original stays as it is.',
      confirm: 'Duplicate',
      icon: AppIcons.copy,
    );

// ─────────────────────────────── Drawer (§4.3): right side, 520 / 640 wide. Phone: full sheet.

Future<T?> showAppDrawer<T>(
  BuildContext context, {
  required String title,
  String? sub,
  bool wide = false,
  required Widget Function(BuildContext) builder,
  List<Widget> Function(BuildContext)? footer,
  Widget? headerAction,
  AppIconData? icon,
  Widget? leading,
  bool fixedBody = false,
  double? width,
}) {
  // [fixedBody]: the body does not scroll as a whole. It gets a bounded height, so a builder can keep a
  // header (search, tabs) fixed and scroll only its list (`Expanded(ListView)`), as `.pb-pk` boards do.
  if (context.isPhone) {
    return showAppSheet<T>(context, title: title, sub: sub, builder: builder, footer: footer, tall: true, fixedBody: fixedBody);
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: AppColors.scrimDrawer,
    transitionDuration: Motion.of(context, Motion.medium),
    transitionBuilder: (_, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
    pageBuilder: (ctx, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: width ?? (wide ? 640 : 520),
          height: double.infinity,
          // `.drawer` as the boards draw it: square edge, header 10/12/10/16 with a 32 icon tile, body 0 16 16.
          decoration: const BoxDecoration(color: AppColors.card, boxShadow: AppShadows.modal),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
              child: Row(spacing: 10, children: [
                if (leading != null) leading else if (icon != null) IconTile(icon, size: 32, radius: 8, iconSize: 17),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                    Text(title, style: AppText.s(15, W.w8, ls: -0.15, h: 1.3)),
                    if (sub != null) CutText(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.4)),
                  ]),
                ),
                ?headerAction,
                AppIconButton(AppIcons.close, tooltip: 'Close', ghost: true, small: true, onPressed: () => Navigator.of(ctx).pop()),
              ]),
            ),
            Expanded(
              child: fixedBody
                  ? Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: builder(ctx))
                  : SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: builder(ctx)),
            ),
            if (footer != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: footer(ctx)),
              ),
          ]),
        ),
      ),
    ),
  );
}

// ─────────────────────────────── Bottom sheet (§4.4). On wide screens it is a centred 520 card.

Future<T?> showAppSheet<T>(
  BuildContext context, {
  String? title,
  String? sub,
  required Widget Function(BuildContext) builder,
  List<Widget> Function(BuildContext)? footer,
  bool tall = false,
  double webWidth = 520,
  Widget? headerAction,
  bool footerStretch = false,
  Listenable? listen,
  String Function()? titleOf,
  String Function()? subOf,
  bool fixedBody = false,
}) {
  // A sheet whose content moves (Newer / Older) passes [listen] and reads its title from [titleOf] / [subOf].
  Widget header(BuildContext ctx) {
    final t = titleOf?.call() ?? title, s = subOf?.call() ?? sub;
    return t == null
      ? const SizedBox(height: 6)
      : Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text(t, style: AppText.s(17, W.w8, ls: -0.2)),
                if (s != null) Text(s, style: AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.4)),
              ]),
            ),
            ?headerAction,
            SheetClose(onTap: () => Navigator.of(ctx).pop()),
          ]),
        );
  }

  Widget content(BuildContext ctx, {required bool phone}) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (phone) Center(child: Container(width: 38, height: 4, margin: const EdgeInsets.fromLTRB(0, 8, 0, 2), decoration: BoxDecoration(color: AppColors.grab, borderRadius: AppRadius.all(4)))),
        header(ctx),
        Flexible(
          child: fixedBody
              ? Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: builder(ctx))
              : SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 16), child: builder(ctx)),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: phone || footerStretch
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: footer(ctx))
                : Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: footer(ctx)),
          ),
        // A toast no longer pushes the sheet up: while a sheet is open it shows at the top (phone).
        SizedBox(height: 18 + (phone ? MediaQuery.paddingOf(ctx).bottom : 0)),
      ]);

  Widget body(BuildContext ctx, {required bool phone}) => listen == null ? content(ctx, phone: phone) : ListenableBuilder(listenable: listen, builder: (ctx, _) => content(ctx, phone: phone));

  if (context.isPhone) {
    return trackSheet(showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.card,
      barrierColor: AppColors.scrimSheet,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * (tall ? .92 : .82)),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.caSheet))),
      sheetAnimationStyle: Motion.off(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(duration: Motion.sheet, reverseDuration: Motion.short, curve: Motion.curve),
      builder: (ctx) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom), child: body(ctx, phone: true)),
    ));
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title ?? 'sheet',
    barrierColor: AppColors.scrimSheet,
    transitionDuration: Motion.of(context, Motion.medium),
    transitionBuilder: _popIn,
    pageBuilder: (ctx, _, _) => Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: webWidth,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.only(top: 6),
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .8),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.modal), boxShadow: AppShadows.modal),
          // The dialog is outside the page, so tell client widgets they are on web (40 high buttons).
          child: CaWeb(web: true, child: body(ctx, phone: false)),
        ),
      ),
    ),
  );
}

class SheetClose extends StatelessWidget {
  const SheetClose({super.key, required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: h ? AppColors.line : AppColors.sub, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: AppIcon(AppIcons.close, size: 15, color: AppColors.text2),
        ),
      );
}

// ─────────────────────────────── Toast (§4.5)

enum ToastKind { staff, ok, star, info, water, warn, err, del }

/// Sits above the navigator (MaterialApp.builder) so toasts float over pages, sheets and dialogs.
class ToastHost extends StatefulWidget {
  const ToastHost({super.key, required this.child});
  final Widget child;

  /// 20 without a bottom bar; 83 above a 71-high bottom bar. Shells set it with [ToastOffset].
  static final bottomOffset = ValueNotifier<double>(20);

  /// Sideways nudge from the centre; the desktop log-in pages use 60 (`.wl-w .ca-toast`).
  static final shiftX = ValueNotifier<double>(0);

  /// True while a toast is on screen: sheets then leave room for it at the bottom
  /// (`:root:has(.ca-toast) .ca-sheet { padding-bottom: 78px }`).
  static final showing = ValueNotifier<bool>(false);

  /// Bottom sheets open now (phone). While one is open, toasts show at the top of the screen
  /// so they never cover the sheet (Gautam, 2026-10-15).
  static final sheets = ValueNotifier<int>(0);
  static _ToastHostState? _instance;

  @override
  State<ToastHost> createState() => _ToastHostState();
}

class _ToastData {
  _ToastData(this.kind, this.title, this.sub, this.action, this.onAction, this.icon);
  final ToastKind kind;
  final String title;
  final String? sub, action;
  final VoidCallback? onAction;
  final AppIconData? icon;
}

class _ToastHostState extends State<ToastHost> {
  _ToastData? _t;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    ToastHost._instance = this;
  }

  void show(_ToastData t) {
    _timer?.cancel();
    setState(() => _t = t);
    ToastHost.showing.value = true;
    // Undo toasts stay 10 s so there is time to tap Undo (Gautam, 2026-10-15); others 5 s.
    _timer = Timer(Duration(seconds: t.action != null ? 10 : 5), hide);
  }

  void hide() {
    if (mounted) setState(() => _t = null);
    ToastHost.showing.value = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (ToastHost._instance == this) ToastHost._instance = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Tablet and web: toasts sit at the bottom right (Gautam, 2026-10-15). Phone: centred above the tabs.
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.tablet;
    return Stack(children: [
        Positioned.fill(child: widget.child),
        ListenableBuilder(
          listenable: Listenable.merge([ToastHost.bottomOffset, ToastHost.sheets]),
          builder: (context, child) {
            final top = !wide && ToastHost.sheets.value > 0;
            return AnimatedPositioned(
              duration: const Duration(milliseconds: 150),
              left: wide ? 24 : 12,
              right: wide ? 24 : 12,
              top: top ? MediaQuery.paddingOf(context).top + 12 : null,
              bottom: top ? null : ToastHost.bottomOffset.value + MediaQuery.paddingOf(context).bottom,
              child: child!,
            );
          },
          child: IgnorePointer(
            ignoring: _t == null,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              reverseDuration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: wide ? const Offset(.12, 0) : Offset(0, ToastHost.sheets.value > 0 ? -.6 : .6), end: Offset.zero).animate(a),
                  child: ScaleTransition(scale: Tween(begin: .96, end: 1.0).animate(a), child: c),
                ),
              ),
              child: _t == null
                  ? const SizedBox.shrink()
                  : ValueListenableBuilder(
                      key: ValueKey(_t),
                      valueListenable: ToastHost.shiftX,
                      builder: (context, dx, child) => Transform.translate(offset: Offset(wide ? 0 : dx, 0), child: child),
                      child: Align(alignment: wide ? Alignment.centerRight : Alignment.center, child: _SwipeAway(onGone: hide, child: _ToastBox(t: _t!, close: hide, wide: wide))),
                    ),
            ),
          ),
        ),
      ]);
  }
}

/// Placed by a shell that has a bottom bar: moves toasts above it while the shell is on screen.
class ToastOffset extends StatefulWidget {
  const ToastOffset({super.key, required this.offset, this.dx = 0, required this.child});
  final double offset, dx;
  final Widget child;
  @override
  State<ToastOffset> createState() => _ToastOffsetState();
}

class _ToastOffsetState extends State<ToastOffset> {
  static _ToastOffsetState? _current;

  @override
  void initState() {
    super.initState();
    _current = this;
    _apply();
  }

  @override
  void didUpdateWidget(ToastOffset old) {
    super.didUpdateWidget(old);
    _apply();
  }

  // Changed outside the frame: a notifier changed while a frame is finishing
  // (e.g. from dispose) marks the toast dirty with no next frame, and the whole
  // app stops repainting until the next tap.
  void _apply() => Timer.run(() {
        if (!mounted || _current != this) return;
        ToastHost.bottomOffset.value = widget.offset;
        ToastHost.shiftX.value = widget.dx;
      });

  @override
  void dispose() {
    // A newer ToastOffset (the next page) already took over: leave its values alone.
    if (_current == this) {
      _current = null;
      Timer.run(() {
        if (_current != null) return;
        ToastHost.bottomOffset.value = 20;
        ToastHost.shiftX.value = 0;
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A toast follows the finger sideways and goes when swiped far or fast enough (Probid 2026-10-30); a short drag
/// springs back.
class _SwipeAway extends StatefulWidget {
  const _SwipeAway({required this.onGone, required this.child});
  final VoidCallback onGone;
  final Widget child;
  @override
  State<_SwipeAway> createState() => _SwipeAwayState();
}

class _SwipeAwayState extends State<_SwipeAway> {
  double _dx = 0;
  bool _drag = false;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return GestureDetector(
      onHorizontalDragStart: (_) => setState(() => _drag = true),
      onHorizontalDragUpdate: (d) => setState(() => _dx += d.delta.dx),
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (_dx.abs() > 90 || v.abs() > 700) {
          setState(() {
            _drag = false;
            _dx = (_dx == 0 ? v : _dx).sign * w;
          });
          widget.onGone();
        } else {
          setState(() {
            _drag = false;
            _dx = 0;
          });
        }
      },
      child: AnimatedSlide(
        duration: _drag ? Duration.zero : Motion.of(context, Motion.short),
        curve: Motion.curve,
        offset: Offset(w == 0 ? 0 : _dx / w, 0),
        child: Opacity(opacity: (1 - _dx.abs() / (w * .8)).clamp(0.0, 1.0), child: widget.child),
      ),
    );
  }
}

class _ToastBox extends StatelessWidget {
  const _ToastBox({required this.t, required this.close, required this.wide});
  final _ToastData t;
  final VoidCallback close;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, subC, actC) = switch (t.kind) {
      ToastKind.staff => (AppColors.toastStaff, AppColors.white, AppColors.toastStaffSub, AppColors.toastStaffAction),
      ToastKind.ok || ToastKind.star => (AppColors.accent, AppColors.white, AppColors.white, AppColors.white),
      ToastKind.info || ToastKind.water => (AppColors.toastInfo, AppColors.toastInk, AppColors.toastInk, AppColors.toastInk),
      ToastKind.warn => (AppColors.toastWarn, AppColors.toastInk, AppColors.toastInk, AppColors.toastInk),
      ToastKind.err => (AppColors.toastErr, AppColors.toastInk, AppColors.toastInk, AppColors.toastInk),
      ToastKind.del => (AppColors.toastDel, AppColors.toastDelText, AppColors.toastDelText, AppColors.toastDelText),
    };
    final icon = t.icon ??
        switch (t.kind) {
          ToastKind.err || ToastKind.warn => AppIcons.alert,
          ToastKind.del => AppIcons.trash,
          ToastKind.water => AppIcons.water,
          ToastKind.info => AppIcons.info,
          ToastKind.star => AppIcons.star,
          _ => AppIcons.check,
        };
    return Material(
      color: Colors.transparent,
      child: Container(
        // Phone: full width (12 from each edge). Tablet / web: 400 wide, bottom right.
        width: wide ? 400 : double.infinity,
        constraints: const BoxConstraints(minHeight: 49),
        padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
        decoration: BoxDecoration(color: bg, borderRadius: AppRadius.all(AppRadius.toast), boxShadow: AppShadows.toast),
        child: Row(spacing: 12, children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: fg.withValues(alpha: .14), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: AppIcon(icon, size: 16, color: fg, stroke: 2.6),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 1, children: [
              Text(t.title, style: AppText.s(14, W.w8, color: fg, h: 1.3)),
              if (t.sub != null) Text(t.sub!, style: AppText.s(12, W.w6, color: subC.withValues(alpha: t.kind == ToastKind.staff ? 1 : .78))),
            ]),
          ),
          if (t.action != null)
            Hover(
              onTap: () {
                close();
                t.onAction?.call();
              },
              builder: (_, h, _) => Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: fg.withValues(alpha: h ? .2 : .12), borderRadius: AppRadius.all(8)),
                child: Text(t.action!, style: AppText.s(13, W.w8, color: actC)),
              ),
            ),
          Hover(
            onTap: close,
            builder: (_, h, _) => Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              child: AppIcon(AppIcons.close, size: 14, color: fg.withValues(alpha: .7), stroke: 2.6),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Shows a toast in the nearest [ToastHost]. Staff screens use [ToastKind.staff]; client screens the coloured kinds.
/// Counts a phone bottom sheet as open until it closes (see [ToastHost.sheets]).
Future<T?> trackSheet<T>(Future<T?> sheet) {
  Timer.run(() => ToastHost.sheets.value += 1);
  return sheet.whenComplete(() => Timer.run(() => ToastHost.sheets.value = math.max(0, ToastHost.sheets.value - 1)));
}

void showToast(BuildContext context, String title, {String? sub, ToastKind kind = ToastKind.staff, String? action, VoidCallback? onAction, AppIconData? icon}) {
  ToastHost._instance?.show(_ToastData(kind, title, sub, action, onAction, icon));
}

/// Pop returns before the exit animation ends and the closing sheet still reads its text fields, so their
/// controllers are freed only after it has gone.
void disposeLater(List<ChangeNotifier> items) =>
    Future.delayed(const Duration(milliseconds: 700), () {
      for (final i in items) {
        i.dispose();
      }
    });

// ─────────────────────────────── Filter menu with side submenus (`.fm-menu` + `.dr-submenu`)

/// One `.mi.sub` row of a filter menu: its label, the current pick on the right, and its options.
class MenuGroup {
  const MenuGroup(this.label, {required this.value, required this.options});
  final String label, value;
  final List<MenuEntry> options;
}

/// `.fm-menu`: one row per group ("Goal   Any ›"); pointing at a row opens its options beside the menu
/// (`.dr-submenu`, on the left when there is room, else on the right). The last row clears every filter.
/// Phone: the groups as an action sheet, a group opens its options as a second sheet.
Future<void> showFilterMenu(BuildContext anchor, List<MenuGroup> groups, {VoidCallback? onClear, double width = 240}) async {
  if (anchor.isPhone) {
    return showActionSheet(anchor, [
      for (final g in groups)
        MenuEntry(g.label, end: g.value, onTap: () => Future.microtask(() {
              if (anchor.mounted) showActionSheet(anchor, g.options, title: g.label);
            })),
      MenuEntry('Clear filters', icon: AppIcons.close, onTap: onClear),
    ], title: 'Filter');
  }
  final box = anchor.findRenderObject() as RenderBox;
  final overlay = Overlay.of(anchor, rootOverlay: true).context.findRenderObject() as RenderBox;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final size = overlay.size;
  final left = (topLeft.dx + box.size.width - width).clamp(8.0, size.width - width - 8);
  final top = topLeft.dy + box.size.height + 4;
  await showGeneralDialog(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: 'menu',
    barrierColor: Colors.transparent,
    transitionDuration: Motion.of(anchor, Motion.short),
    pageBuilder: (ctx, _, _) => _FilterMenu(groups: groups, onClear: onClear, left: left, top: top, width: width, screen: size, close: () => Navigator.of(ctx).pop()),
    transitionBuilder: _menuIn,
  );
}

class _FilterMenu extends StatefulWidget {
  const _FilterMenu({required this.groups, required this.onClear, required this.left, required this.top, required this.width, required this.screen, required this.close});
  final List<MenuGroup> groups;
  final VoidCallback? onClear, close;
  final double left, top, width;
  final Size screen;
  @override
  State<_FilterMenu> createState() => _FilterMenuState();
}

class _FilterMenuState extends State<_FilterMenu> {
  static const _row = 32.0, _gap = 3.0, _subW = 200.0;
  int? open;

  Widget _item({required Widget child, required bool on, VoidCallback? onTap, VoidCallback? onEnter}) => MouseRegion(
        onEnter: (_) => onEnter?.call(),
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            height: _row,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: h || on ? AppColors.sub : null, borderRadius: AppRadius.all(AppRadius.item)),
            child: child,
          ),
        ),
      );

  BoxDecoration get _box => BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.menu), border: Border.all(color: AppColors.line), boxShadow: AppShadows.menu);

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final g = open == null ? null : w.groups[open!];
    // The submenu's first option lines up with its row: menu padding 6 + border 1.
    final subTop = w.top + 6 + (open ?? 0) * (_row + _gap) - 7;
    final onLeft = w.left - 4 - _subW >= 8;
    return DefaultTextStyle(
      style: AppText.s(13, W.w5),
      child: Stack(children: [
        Positioned(
          left: w.left,
          top: w.top,
          width: w.width,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: _box,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: _gap, children: [
              for (final (i, g) in w.groups.indexed)
                _item(
                  on: open == i,
                  onEnter: () => setState(() => open = i),
                  onTap: () => setState(() => open = open == i ? null : i),
                  child: Row(spacing: 10, children: [
                    Expanded(child: CutText(g.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w5))),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: CutText(g.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w6, color: AppColors.muted)),
                    ),
                    const AppIcon(AppIcons.chevronRight, size: 14, color: AppColors.muted),
                  ]),
                ),
              Container(height: 1, color: AppColors.line, margin: const EdgeInsets.symmetric(vertical: 3)),
              _item(
                on: false,
                onEnter: () => setState(() => open = null),
                onTap: w.onClear == null
                    ? null
                    : () {
                        w.close?.call();
                        w.onClear!();
                      },
                child: Align(alignment: Alignment.centerLeft, child: Text('Clear filters', style: AppText.s(13, W.w5, color: AppColors.muted))),
              ),
            ]),
          ),
        ),
        if (g != null)
          Positioned(
            left: onLeft ? w.left - 4 - _subW : w.left + w.width + 4,
            top: subTop.clamp(8.0, math.max(8.0, w.screen.height - 12 - 12 - g.options.length * (_row + _gap))),
            width: _subW,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: _box,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: _gap, children: [
                for (final o in g.options)
                  _item(
                    on: false,
                    onTap: () {
                      w.close?.call();
                      o.onTap?.call();
                    },
                    child: Row(children: [
                      Expanded(child: CutText(o.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, o.selected ? W.w7 : W.w5))),
                      if (o.selected) const AppIcon(AppIcons.check, size: 15, color: AppColors.accent, stroke: 2.2),
                    ]),
                  ),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Menus and dropdowns: fade in and grow a little from where they open (Phase 5).
Widget _menuIn(BuildContext _, Animation<double> a, Animation<double> _, Widget child) {
  final c = CurvedAnimation(parent: a, curve: Motion.curve, reverseCurve: Curves.easeIn);
  return FadeTransition(opacity: c, child: ScaleTransition(scale: Tween(begin: .96, end: 1.0).animate(c), alignment: Alignment.topCenter, child: child));
}

/// Dialogs and web sheets: fade in, grow from 96 %.
Widget _popIn(BuildContext _, Animation<double> a, Animation<double> _, Widget child) {
  final c = CurvedAnimation(parent: a, curve: Motion.curve, reverseCurve: Curves.easeIn);
  return FadeTransition(opacity: c, child: ScaleTransition(scale: Tween(begin: .96, end: 1.0).animate(c), child: child));
}
