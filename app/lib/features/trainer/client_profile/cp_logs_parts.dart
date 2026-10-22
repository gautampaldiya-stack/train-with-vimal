import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/media.dart' show showImageViewer;
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import 'cp_common.dart';
import 'cp_model.dart';
import '../../../core/widgets/tooltip.dart';

// Pieces shared by the Logs and Progress tabs: the range both tabs use (one picker state, as on the board),
// the client's plans for "Plan: …", the board table (`.tbl.dt.cmp.cp-t`) and its phone card list, the log drawer
// with Previous / Next, and the drawer's blocks (numbers, answers, photos, reply box).

final _ranges = Expando<CpRange>('cp range');
final _plans = Expando<Future<List<CpPlan>>>('cp plans');

/// The picked range, kept for this profile while the trainer moves between Logs and Progress.
CpRange cpRangeOf(CpController c) => _ranges[c] ?? CpRange.fixed[1];
void cpSetRange(CpController c, CpRange r) => _ranges[c] = r;

/// A workout plan the client has (or had): "Plan: Fat Loss Phase 1" in the picker, A / B in Compare plans.
class CpPlan {
  CpPlan(Map j)
      : id = '${j['id']}',
        name = '${j['program_name'] ?? j['master_name'] ?? 'Plan'}',
        status = '${j['status'] ?? ''}',
        start = cpParse(j['start_date']),
        end = cpParse(j['end_date']),
        weeks = (j['weeks'] as num?)?.toInt();
  final String id, name, status;
  final DateTime? start, end;
  final int? weeks;
}

/// Current first, then past plans, newest first (up-next plans have no logs yet).
Future<List<CpPlan>> cpPlansOf(CpController c) => _plans[c] ??= () async {
      try {
        final r = await Services.api.get<Map>('clients/${c.id}/programs/');
        return [
          for (final k in ['current', 'history'])
            for (final p in (r[k] as List? ?? const [])) CpPlan(p as Map),
        ];
      } catch (_) {
        _plans[c] = null;
        return <CpPlan>[];
      }
    }();

final _n0 = NumberFormat.decimalPattern('en_IN');
String cpNum(num? v) => v == null ? '—' : _n0.format(v.round());
String cpG(num? v) => v == null ? '—' : '${_n0.format(v.round())} g';

/// "1.5", "7" — one decimal, no ".0".
String cpOne(num v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

// ─────────────────────────────── Table

/// One column of a [CpTable]: label, smallest width, right-aligned numbers.
class CpCol {
  const CpCol(this.label, this.width, {this.right = false, this.grow = 1});
  final String label;
  final double width;
  final bool right;

  /// Share of the spare width this column takes (0 = stays at [width]).
  final double grow;
}

/// The board's table: grey head row (uppercase 11.5), 13.5 rows with a line between, a chevron when rows open,
/// spare width shared out like an HTML table; narrower than its columns, it scrolls sideways.
class CpTable extends StatefulWidget {
  const CpTable({super.key, required this.cols, required this.rows, this.onTap, this.chevron = false, this.footer});
  final List<CpCol> cols;
  final List<List<Widget>> rows;
  final ValueChanged<int>? onTap;
  final bool chevron;

  /// A last row drawn bold (Measurements → Change).
  final List<Widget>? footer;

  @override
  State<CpTable> createState() => _CpTableState();
}

class _CpTableState extends State<CpTable> {
  final _h = ScrollController();

  @override
  void dispose() {
    _h.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final cols = [...widget.cols, if (widget.chevron) const CpCol('', 44, grow: 0)];
        final min = cols.fold<double>(0, (a, c) => a + c.width);
        final grow = cols.fold<double>(0, (a, c) => a + c.grow);
        final extra = (box.maxWidth - min).clamp(0.0, double.infinity);
        final w = [for (final c in cols) c.width + (grow == 0 ? 0 : extra * c.grow / grow)];
        Widget cell(int i, Widget child) => Container(
              width: w[i],
              padding: EdgeInsets.fromLTRB(i == 0 ? 16 : 12, 0, i == cols.length - 1 ? 16 : 12, 0),
              alignment: cols[i].right ? Alignment.centerRight : Alignment.centerLeft,
              child: child,
            );
        Widget row(List<Widget> cells, {int? index, bool last = false}) {
          final all = [...cells, if (widget.chevron) const AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.text2)];
          Widget body(bool h) => Container(
                constraints: const BoxConstraints(minHeight: 37),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: h ? AppColors.hover : null,
                  border: last ? null : const Border(bottom: BorderSide(color: AppColors.line)),
                ),
                child: Row(children: [for (final (i, c) in all.indexed) cell(i, c)]),
              );
          if (index == null || widget.onTap == null) return body(false);
          return Hover(onTap: () => widget.onTap!(index), builder: (_, h, _) => body(h));
        }

        final table = SizedBox(
          width: min + extra,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 32,
              decoration: const BoxDecoration(
                color: AppColors.tableHeadDt,
                border: Border.symmetric(horizontal: BorderSide(color: AppColors.line)),
              ),
              child: Row(children: [
                for (final (i, c) in cols.indexed)
                  cell(i, CutText(c.label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w7, color: AppColors.muted, ls: .58))),
              ]),
            ),
            for (final (i, r) in widget.rows.indexed) row(r, index: i, last: i == widget.rows.length - 1 && widget.footer == null),
            if (widget.footer != null) row(widget.footer!, last: true),
          ]),
        );
        if (box.maxWidth >= min) return table;
        return Scrollbar(
          controller: _h,
          thumbVisibility: true,
          child: SingleChildScrollView(controller: _h, scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(bottom: 8), child: table),
        );
      });
}

/// Table cell text: 13.5 regular, or bold for the name column.
Widget cpCell(String s, {bool bold = false, Color? color, bool muted = false}) => CutText(s,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: AppText.s(13.5, bold ? W.w7 : W.w5, color: color ?? (muted ? AppColors.muted : AppColors.text), tabular: true));

/// Phone version of a table (Mobile board): one block per row, the date as its title, then the columns as
/// label / value pairs, 3 to a line, with a chevron top right when it opens.
class CpPhoneRows extends StatelessWidget {
  const CpPhoneRows({super.key, required this.titles, required this.labels, required this.values, this.onTap, this.columns = 3});
  final List<String> titles;
  final List<String> labels;
  final List<List<Widget>> values;
  final ValueChanged<int>? onTap;
  final int columns;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, t) in titles.indexed)
          Hover(
            onTap: onTap == null ? null : () => onTap!(i),
            builder: (_, h, _) => Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
              decoration: BoxDecoration(
                color: h && onTap != null ? AppColors.hover : null,
                border: Border(top: const BorderSide(color: AppColors.line)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
                Row(children: [
                  Expanded(child: Text(t, style: AppText.s(14, W.w8))),
                  if (onTap != null) const AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.text2),
                ]),
                LayoutBuilder(builder: (_, b) {
                  final w = (b.maxWidth - 8 * (columns - 1)) / columns;
                  return Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final (j, l) in labels.indexed)
                      SizedBox(
                        width: w,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                          Text(l, style: AppText.s(12, W.w5, color: AppColors.muted)),
                          values[i][j],
                        ]),
                      ),
                  ]);
                }),
              ]),
            ),
          ),
      ]);
}

/// Phone value text (13.5, semibold).
Widget cpPv(String s, {Color? color}) => Text(s, style: AppText.s(13.5, W.w6, color: color ?? AppColors.text, tabular: true));

/// Ticked / not ticked square (`.cp-tick ok|no`).
Widget cpTick(bool? ok) => ok == null
    ? Text('—', style: AppText.s(13.5, W.w5, color: AppColors.muted))
    : Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: ok ? AppColors.okBg : AppColors.badBg, borderRadius: BorderRadius.circular(5)),
        child: AppIcon(ok ? AppIcons.check : AppIcons.close, size: 12, color: ok ? AppColors.okText : AppColors.badText, stroke: 2.4),
      );

/// Card with a table, its empty state and the pager under it.
class CpTableCard extends StatelessWidget {
  const CpTableCard({super.key, required this.title, this.sub, required this.child, this.pager, this.action});
  final String title;
  final String? sub;
  final Widget child;
  final Widget? pager, action;
  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHeader(title, sub: sub, action: action),
          child,
          if (pager != null) Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 10), child: pager),
        ]),
      );
}

// ─────────────────────────────── Log drawer

/// The log drawer (`.drawer.wide`): title and grey line change with Previous / Next, body below, footer note
/// left and buttons right. On a phone it is the tall sheet.
Future<T?> showCpLogDrawer<T>(
  BuildContext context, {
  required Listenable listen,
  required String Function() title,
  required String Function() sub,
  required Widget Function(BuildContext) body,
  required String Function() note,
  required List<Widget> Function(BuildContext) actions,
  VoidCallback? onPrev,
  VoidCallback? onNext,
  bool wide = true,
}) {
  Widget nav() => Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
        AppIconButton(AppIcons.chevronLeft, tooltip: 'Previous', ghost: true, small: true, onPressed: onPrev),
        AppIconButton(AppIcons.chevronRight, tooltip: 'Next', ghost: true, small: true, onPressed: onNext),
      ]);
  if (context.isPhone) {
    return showAppSheet<T>(
      context,
      tall: true,
      listen: listen,
      titleOf: title,
      subOf: sub,
      headerAction: nav(),
      builder: (ctx) => ListenableBuilder(listenable: listen, builder: (ctx, _) => Padding(padding: const EdgeInsets.only(bottom: 8), child: body(ctx))),
      footer: (ctx) => [
        if (note().isNotEmpty) Text(note(), textAlign: TextAlign.center, style: AppText.cap),
        ...actions(ctx),
      ],
    );
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Log',
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
          decoration: const BoxDecoration(color: AppColors.card, boxShadow: AppShadows.modal),
          child: ListenableBuilder(
            listenable: listen,
            builder: (ctx, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
                child: Row(spacing: 10, children: [
                  const IconTile(AppIcons.clipboard, size: 32, radius: 8, iconSize: 17),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                      CutText(title(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(15, W.w8, ls: -0.15, h: 1.3)),
                      CutText(sub(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.4)),
                    ]),
                  ),
                  nav(),
                  Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 4), color: AppColors.line),
                  AppIconButton(AppIcons.close, tooltip: 'Close', ghost: true, small: true, onPressed: () => Navigator.of(ctx).pop()),
                ]),
              ),
              Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), child: body(ctx))),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                child: Row(spacing: 8, children: [
                  Expanded(child: CutText(note(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted))),
                  ...actions(ctx),
                ]),
              ),
            ]),
          ),
        ),
      ),
    ),
  );
}

/// `.dr-kpis`: up to 4 numbers with a line between, a line under (2 × 2 on a phone).
class CpKpis extends StatelessWidget {
  const CpKpis(this.items, {super.key});
  final List<(String, String)> items;
  @override
  Widget build(BuildContext context) {
    Widget cell((String, String) k, int i) => Container(
          padding: EdgeInsets.fromLTRB(i == 0 ? 0 : 12, 2, 12, 2),
          decoration: BoxDecoration(border: i > 0 ? const Border(left: BorderSide(color: AppColors.line)) : null),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            CutText(k.$1, style: AppText.s(12, W.w5, color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            CutText(k.$2, style: AppText.s(14.5, W.w8, tabular: true), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        );
    final per = context.isPhone ? 2 : 4;
    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Column(spacing: 10, children: [
        for (var r = 0; r < items.length; r += per)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = r; i < r + per; i++) Expanded(child: i < items.length ? cell(items[i], i - r) : const SizedBox()),
            ]),
          ),
      ]),
    );
  }
}

/// `.dr-qa`: question left, answer right (bold), a line between.
class CpQa extends StatelessWidget {
  const CpQa(this.items, {super.key});
  final List<(String, String)> items;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, (q, a)) in items.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(border: i == items.length - 1 ? null : const Border(bottom: BorderSide(color: AppColors.line))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
              Expanded(child: Text(q, style: AppText.s(13.5, W.w5, color: AppColors.text2))),
              Expanded(child: Text(a.isEmpty ? '—' : a, style: AppText.s(13.5, W.w6))),
            ]),
          ),
      ]);
}

/// `.dr-sub`: small uppercase heading inside a drawer.
Widget cpDrSub(String t) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Text(t.toUpperCase(), style: AppText.s(11.5, W.w7, color: AppColors.muted, ls: .58)),
    );

/// `.dr-quote`: grey box with a bold label over the text ("Riya's note").
Widget cpQuote(String label, String text) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(color: AppColors.caWebBg, borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
        Text(label, style: AppText.s(12, W.w7, color: AppColors.muted)),
        Text(text, style: AppText.s(13.5, W.w5, color: AppColors.text2, h: 1.5)),
      ]),
    );

/// `.dr-photos`: photos in a row of 3 with the pose under each; tap opens them full screen.
class CpPhotoRow extends StatelessWidget {
  const CpPhotoRow(this.photos, {super.key, required this.title, this.height = 150});
  final List<(String, String)> photos; // (url, label)
  final String title;
  final double height;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, b) {
        final w = (b.maxWidth - 16) / 3;
        return Wrap(spacing: 8, runSpacing: 10, children: [
          for (final (i, (url, label)) in photos.indexed)
            SizedBox(
              width: w,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                CpPhoto(url, height: height, onTap: () => showImageViewer(context, [for (final p in photos) p.$1], start: i, title: title)),
                Text(label, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
              ]),
            ),
        ]);
      });
}

/// One photo tile (radius 10, sub grey behind, zoom cursor).
class CpPhoto extends StatelessWidget {
  const CpPhoto(this.url, {super.key, this.height = 150, this.onTap, this.selected = false});
  final String url;
  final double height;
  final VoidCallback? onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        label: 'Open photo',
        child: GestureDetector(
          onTap: onTap,
          child: MouseRegion(
            cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.zoomIn,
            child: Container(
              height: height,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.sub,
                borderRadius: AppRadius.all(10),
                border: selected ? Border.all(color: AppColors.accent, width: 2) : null,
              ),
              child: url.isEmpty
                  ? const Center(child: AppIcon(AppIcons.user, size: 22, color: AppColors.muted))
                  : Image.network(url, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, _, _) => const Center(child: AppIcon(AppIcons.photo, size: 22, color: AppColors.muted))),
            ),
          ),
        ),
      );
}

/// `.dr-reply`: text box with "`first` gets it as a message in the app" and Send.
class CpReplyBox extends StatefulWidget {
  const CpReplyBox({super.key, required this.hint, required this.first, required this.onSend, this.sendLabel = 'Send'});
  final String hint, first, sendLabel;
  final Future<void> Function(String text) onSend;
  @override
  State<CpReplyBox> createState() => _CpReplyBoxState();
}

class _CpReplyBoxState extends State<CpReplyBox> {
  final _t = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _t.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.onSend(text);
      _t.clear();
      if (mounted) showToast(context, 'Sent to ${widget.first}', sub: 'They get it as a message in the app', kind: ToastKind.ok);
    } catch (e) {
      if (mounted) showToast(context, 'Could not send', sub: e is ApiError ? e.message : 'Try again.', kind: ToastKind.err);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
          TextField(
            controller: _t,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            style: AppText.s(13.5, W.w5),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              hintText: widget.hint,
              hintStyle: AppText.s(13.5, W.w5, color: AppColors.muted),
            ),
          ),
          Row(children: [
            Expanded(child: Text('${widget.first} gets it as a message in the app', style: AppText.cap)),
            ListenableBuilder(
              listenable: _t,
              builder: (_, _) => AppButton(widget.sendLabel, icon: AppIcons.send, size: BtnSize.sm, loading: _busy, onPressed: _t.text.trim().isEmpty ? null : _send),
            ),
          ]),
        ]),
      );
}
