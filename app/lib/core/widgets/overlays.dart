import 'dart:async';

import 'package:flutter/material.dart';

import '../icons/app_icons.dart';
import '../theme/theme.dart';
import 'button.dart';
import 'card.dart';
import 'hover.dart';
import 'responsive.dart';

// ─────────────────────────────── Menu (docs/design.md §4.1)

class MenuEntry {
  const MenuEntry(this.label, {this.icon, this.onTap, this.danger = false, this.selected = false, this.end, this.header = false, this.separator = false});
  const MenuEntry.header(this.label)
      : icon = null, onTap = null, danger = false, selected = false, end = null, header = true, separator = false;
  const MenuEntry.separator()
      : label = '', icon = null, onTap = null, danger = false, selected = false, end = null, header = false, separator = true;
  final String label;
  final AppIconData? icon;
  final VoidCallback? onTap;
  final bool danger, selected, header, separator;
  final String? end;
}

/// Opens `.menu` anchored under [anchor]: white, radius 12, padding 6, items 34 high, picked item has a tick.
Future<void> showAppMenu(BuildContext anchor, List<MenuEntry> entries, {double width = 200, bool alignRight = true}) async {
  if (anchor.isPhone) return showActionSheet(anchor, entries);
  final box = anchor.findRenderObject() as RenderBox;
  final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final size = overlay.size;
  final left = alignRight ? (topLeft.dx + box.size.width - width) : topLeft.dx;
  final below = topLeft.dy + box.size.height + 6;
  final openUp = below + 40.0 * entries.length > size.height - 12;
  await showGeneralDialog(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: 'menu',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 90),
    pageBuilder: (ctx, _, _) => Stack(children: [
      Positioned(
        left: left.clamp(8, size.width - width - 8),
        top: openUp ? null : below,
        bottom: openUp ? size.height - topLeft.dy + 6 : null,
        width: width,
        child: _MenuBox(entries: entries, close: () => Navigator.of(ctx).pop()),
      ),
    ]),
    transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  );
}

class _MenuBox extends StatelessWidget {
  const _MenuBox({required this.entries, required this.close});
  final List<MenuEntry> entries;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(maxHeight: 420),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.menu), border: Border.all(color: AppColors.line), boxShadow: AppShadows.menu),
          child: SingleChildScrollView(
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
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: h ? (e.danger ? AppColors.badBg : AppColors.sub) : null, borderRadius: AppRadius.all(AppRadius.item)),
                        child: Row(spacing: 10, children: [
                          if (e.icon != null) AppIcon(e.icon!, size: 16, color: e.danger ? AppColors.badText : AppColors.muted),
                          Expanded(child: Text(e.label, style: AppText.s(13.5, e.selected ? W.w7 : W.w5, color: fg), overflow: TextOverflow.ellipsis)),
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
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(spacing: 12, children: [
                  if (e.icon != null) AppIcon(e.icon!, size: 18, color: e.danger ? AppColors.badText : AppColors.text2),
                  Expanded(child: Text(e.label, style: AppText.s(14.5, e.selected ? W.w7 : W.w6, color: e.danger ? AppColors.badText : AppColors.text))),
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
    transitionDuration: const Duration(milliseconds: 140),
    transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: .98, end: 1.0).animate(a), child: child)),
    pageBuilder: (ctx, _, _) => Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: wide ? 560 : 440,
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
    actions: (ctx) => [
      AppButton('Cancel', onPressed: () => Navigator.of(ctx).pop(false), expand: ctx.isPhone),
      AppButton(confirm, kind: danger ? BtnKind.danger : BtnKind.primary, onPressed: () => Navigator.of(ctx).pop(true), expand: ctx.isPhone),
    ],
  );
  return r ?? false;
}

// ─────────────────────────────── Drawer (§4.3): right side, 520 / 640 wide. Phone: full sheet.

Future<T?> showAppDrawer<T>(
  BuildContext context, {
  required String title,
  String? sub,
  bool wide = false,
  required Widget Function(BuildContext) builder,
  List<Widget> Function(BuildContext)? footer,
  Widget? headerAction,
}) {
  if (context.isPhone) {
    return showAppSheet<T>(context, title: title, sub: sub, builder: builder, footer: footer, tall: true);
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: AppColors.scrimDrawer,
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (_, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
    pageBuilder: (ctx, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: wide ? 640 : 520,
          height: double.infinity,
          decoration: const BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.horizontal(left: Radius.circular(AppRadius.modal)),
            boxShadow: AppShadows.modal,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 16, 14),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
                    Text(title, style: AppText.s(17, W.w8, ls: -0.2)),
                    if (sub != null) Text(sub, style: AppText.sub),
                  ]),
                ),
                ?headerAction,
                AppIconButton(AppIcons.close, tooltip: 'Close', ghost: true, small: true, onPressed: () => Navigator.of(ctx).pop()),
              ]),
            ),
            Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(22, 16, 22, 20), child: builder(ctx))),
            if (footer != null)
              Container(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
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
}) {
  Widget header(BuildContext ctx) => title == null
      ? const SizedBox(height: 6)
      : Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text(title, style: AppText.s(17, W.w8, ls: -0.2)),
                if (sub != null) Text(sub, style: AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.4)),
              ]),
            ),
            ?headerAction,
            SheetClose(onTap: () => Navigator.of(ctx).pop()),
          ]),
        );
  Widget body(BuildContext ctx, {required bool phone}) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (phone) Center(child: Container(width: 38, height: 4, margin: const EdgeInsets.fromLTRB(0, 8, 0, 2), decoration: BoxDecoration(color: AppColors.grab, borderRadius: AppRadius.all(4)))),
        header(ctx),
        Flexible(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 16), child: builder(ctx))),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: phone
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: footer(ctx))
                : Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: footer(ctx)),
          ),
        SizedBox(height: 18 + (phone ? MediaQuery.paddingOf(ctx).bottom : 0)),
      ]);

  if (context.isPhone) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.card,
      barrierColor: AppColors.scrimSheet,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * (tall ? .92 : .82)),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.caSheet))),
      builder: (ctx) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom), child: body(ctx, phone: true)),
    );
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title ?? 'sheet',
    barrierColor: AppColors.scrimSheet,
    transitionDuration: const Duration(milliseconds: 140),
    transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (ctx, _, _) => Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: webWidth,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.only(top: 6),
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .8),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.modal), boxShadow: AppShadows.modal),
          child: body(ctx, phone: false),
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
    _timer = Timer(Duration(seconds: t.action != null ? 7 : 5), hide);
  }

  void hide() {
    if (mounted) setState(() => _t = null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (ToastHost._instance == this) ToastHost._instance = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned.fill(child: widget.child),
        ValueListenableBuilder(
          valueListenable: ToastHost.bottomOffset,
          builder: (context, off, child) => AnimatedPositioned(
            duration: const Duration(milliseconds: 150),
            left: 12,
            right: 12,
            bottom: off + MediaQuery.paddingOf(context).bottom,
            child: child!,
          ),
          child: IgnorePointer(
            ignoring: _t == null,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, .3), end: Offset.zero).animate(a), child: c)),
              child: _t == null ? const SizedBox.shrink() : Center(key: ValueKey(_t), child: _ToastBox(t: _t!, close: hide)),
            ),
          ),
        ),
      ]);
}

/// Placed by a shell that has a bottom bar: moves toasts above it while the shell is on screen.
class ToastOffset extends StatefulWidget {
  const ToastOffset({super.key, required this.offset, required this.child});
  final double offset;
  final Widget child;
  @override
  State<ToastOffset> createState() => _ToastOffsetState();
}

class _ToastOffsetState extends State<ToastOffset> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ToastHost.bottomOffset.value = widget.offset);
  }

  @override
  void didUpdateWidget(ToastOffset old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => ToastHost.bottomOffset.value = widget.offset);
  }

  @override
  void dispose() {
    ToastHost.bottomOffset.value = 20;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ToastBox extends StatelessWidget {
  const _ToastBox({required this.t, required this.close});
  final _ToastData t;
  final VoidCallback close;

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
          ToastKind.info || ToastKind.water => AppIcons.info,
          _ => AppIcons.check,
        };
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 360,
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
void showToast(BuildContext context, String title, {String? sub, ToastKind kind = ToastKind.staff, String? action, VoidCallback? onAction, AppIconData? icon}) {
  ToastHost._instance?.show(_ToastData(kind, title, sub, action, onAction, icon));
}
