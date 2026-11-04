import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/photo_viewer.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tooltip.dart';
import 'checkins_model.dart';

/// Pieces of the Check-ins boards (`ck-*`), shared by the list, the two forms and the sheet.

/// `ck-q`: a question card — bold title, grey (or blue once answered) label on the right.
class CkQCard extends StatelessWidget {
  const CkQCard({super.key, required this.title, required this.label, this.got = false, this.sub = '', required this.children});
  final String title, label;

  /// The admin's description / subtitle of the question (builder → "Description / subtitle").
  final String sub;
  final bool got;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          spacing: 8,
          children: [
            Expanded(child: Text(title, style: AppText.s(14, W.w8))),
            Text(label, style: AppText.s(12, got ? W.w7 : W.w6, color: got ? AppColors.accentText : AppColors.muted)),
          ],
        ),
        if (sub.isNotEmpty) Transform.translate(offset: const Offset(0, -6), child: Text(sub, style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.4))),
        ...children,
      ],
    ),
  );
}

/// `ck-scale`: five buttons, number over a word.
class CkScale extends StatelessWidget {
  const CkScale({super.key, required this.labels, required this.value, required this.onPick, this.lg = false});
  final List<String> labels;
  final int? value; // 1–5
  final ValueChanged<int> onPick;
  final bool lg;
  @override
  Widget build(BuildContext context) {
    final web = CaWeb.of(context);
    return Row(
      spacing: 5,
      children: [
        for (var i = 0; i < 5; i++)
          Expanded(
            child: Semantics(
              button: true,
              selected: value == i + 1,
              label: '${i + 1} ${labels[i]}',
              child: Hover(
                onTap: () => onPick(i + 1),
                builder: (_, h, _) {
                  final on = value == i + 1;
                  return Container(
                    padding: lg
                        ? const EdgeInsets.fromLTRB(2, 12, 2, 10)
                        : (web ? const EdgeInsets.fromLTRB(4, 10, 4, 9) : const EdgeInsets.fromLTRB(2, 7, 2, 6)),
                    decoration: BoxDecoration(
                      color: on ? AppColors.accent : AppColors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: on ? AppColors.accent : (h ? AppColors.lineHover : AppColors.line)),
                    ),
                    child: Column(
                      spacing: lg ? 3 : 1,
                      children: [
                        Text('${i + 1}', style: AppText.s(lg ? 20 : 15, W.w8, color: on ? AppColors.white : AppColors.text, h: 1.2)),
                        CutText(
                          labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.s(lg ? 10.5 : (web ? 11 : 10), W.w6, color: on ? AppColors.white.withValues(alpha: .85) : AppColors.muted),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// `ch-qs ck-sl`: a grid of choice buttons (sleep hours), 4 a row on the phone, 7 on the web.
class CkChoiceGrid extends StatelessWidget {
  const CkChoiceGrid({super.key, required this.options, required this.value, required this.onPick});
  final List<String> options;
  final String? value;
  final ValueChanged<String> onPick;
  @override
  Widget build(BuildContext context) {
    final per = CaWeb.of(context) ? 7 : 4;
    final rows = <List<String>>[];
    for (var i = 0; i < options.length; i += per) {
      rows.add(options.sublist(i, (i + per).clamp(0, options.length)));
    }
    return Column(
      spacing: 6,
      children: [
        for (final r in rows)
          Row(
            spacing: 6,
            children: [
              for (var i = 0; i < per; i++)
                Expanded(
                  child: i >= r.length
                      ? const SizedBox()
                      : Semantics(
                          button: true,
                          selected: value == r[i],
                          child: Hover(
                            onTap: () => onPick(r[i]),
                            builder: (_, h, _) {
                              final on = value == r[i];
                              return Container(
                                height: 34,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: on ? AppColors.text : (h ? AppColors.outlineHover : AppColors.white),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: on ? AppColors.text : AppColors.line),
                                ),
                                child: Text(r[i], maxLines: 1, style: AppText.s(13, W.w7, color: on ? AppColors.white : AppColors.text)),
                              );
                            },
                          ),
                        ),
                ),
            ],
          ),
      ],
    );
  }
}

/// `fd-step lg` inside `ck-num`: round − / + and the big value.
/// − value + for a number question. With [onType] the middle is a box she can type in (Probid 2026-10-31):
/// [value] is the plain number, [suffix] ("kg") sits beside it.
class CkStepper extends StatefulWidget {
  const CkStepper({super.key, required this.value, required this.onMinus, required this.onPlus, this.under, this.onType, this.suffix});
  final String value;
  final VoidCallback onMinus, onPlus;
  final Widget? under;
  final ValueChanged<double?>? onType;
  final String? suffix;
  @override
  State<CkStepper> createState() => _CkStepperState();
}

class _CkStepperState extends State<CkStepper> {
  late final _t = TextEditingController(text: widget.value);
  final _f = FocusNode();

  @override
  void didUpdateWidget(CkStepper old) {
    super.didUpdateWidget(old);
    // − / + and quick picks change the number; while she types, her text stays as it is.
    if (!_f.hasFocus && _t.text != widget.value) _t.text = widget.value;
  }

  @override
  void dispose() {
    _t.dispose();
    _f.dispose();
    super.dispose();
  }

  void _step(VoidCallback f) {
    _f.unfocus();
    f();
  }

  @override
  Widget build(BuildContext context) => Column(
    spacing: 4,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 4,
        children: [
          _round(AppIcons.minus, 'Less', () => _step(widget.onMinus)),
          SizedBox(
            width: 132,
            child: widget.onType == null
                ? Text(widget.suffix == null ? widget.value : '${widget.value} ${widget.suffix}', textAlign: TextAlign.center, style: AppText.s(22, W.w8, tabular: true))
                : Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line2)),
                    child: Row(spacing: 4, children: [
                      Expanded(
                        child: TextField(
                          controller: _t,
                          focusNode: _f,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: AppText.s(22, W.w8, tabular: true),
                          decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
                          onChanged: (t) => widget.onType!(double.tryParse(t.trim().replaceAll(',', '.'))),
                        ),
                      ),
                      if (widget.suffix != null) Text(widget.suffix!, style: AppText.s(13, W.w7, color: AppColors.muted)),
                    ]),
                  ),
          ),
          _round(AppIcons.plus, 'More', () => _step(widget.onPlus)),
        ],
      ),
      ?widget.under,
    ],
  );

  Widget _round(AppIconData icon, String label, VoidCallback onTap) => Semantics(
    label: label,
    button: true,
    child: Hover(
      onTap: onTap,
      builder: (_, h, _) => Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: h ? AppColors.outlineHover : AppColors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.line),
        ),
        child: AppIcon(icon, size: 19, color: AppColors.text2),
      ),
    ),
  );
}

/// `fl-try`: small round suggestion chips, with an optional grey lead word.
class CkTry extends StatelessWidget {
  const CkTry({super.key, this.lead, required this.items, required this.onPick});
  final String? lead;
  final List<String> items;
  final ValueChanged<String> onPick;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (lead != null) Text(lead!, style: AppText.s(12, W.w6, color: AppColors.muted)),
      for (final t in items)
        Hover(
          onTap: () => onPick(t),
          builder: (_, h, _) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: h ? AppColors.accent : AppColors.line),
            ),
            child: Text(t, style: AppText.s(12, W.w6, color: h ? AppColors.accentText : AppColors.text2)),
          ),
        ),
    ],
  );
}

/// `fl-in ck-in`: the note / answer box (taller with [area]).
class CkInput extends StatelessWidget {
  const CkInput({super.key, required this.controller, required this.hint, this.area = false, this.onChanged, this.keyboard});
  final TextEditingController controller;
  final String hint;
  final bool area;
  final VoidCallback? onChanged;

  /// A number answer: the number keyboard, one line.
  final TextInputType? keyboard;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Container(
      constraints: BoxConstraints(minHeight: area ? 76 : 40),
      padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: area ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        spacing: 6,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboard,
              minLines: area ? 3 : 1,
              maxLines: area ? 6 : (keyboard != null ? 1 : 3),
              maxLength: area ? 3000 : 200,
              onChanged: (_) => onChanged?.call(),
              style: AppText.s(13.5, W.w6, h: 1.4),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                border: InputBorder.none,
                hintText: hint,
                hintStyle: AppText.s(13.5, W.w5, color: AppColors.muted, h: 1.4),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: area ? 7 : 0),
              child: Semantics(
                label: area ? 'Clear answer' : 'Clear note',
                button: true,
                child: Hover(
                  onTap: () {
                    controller.clear();
                    onChanged?.call();
                  },
                  builder: (_, h, _) => Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: h ? AppColors.line : AppColors.sub, borderRadius: BorderRadius.circular(10)),
                    child: const AppIcon(AppIcons.close, size: 14, color: AppColors.text2),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// `ck-auto` / `ck-wait`: blue note with an icon.
Widget ckInfo(String text, {AppIconData icon = AppIcons.info}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(10)),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: AppIcon(icon, size: 16, color: AppColors.infoText),
      ),
      Expanded(
        child: Text(text, style: AppText.s(12.5, W.w5, color: AppColors.infoText, h: 1.45)),
      ),
    ],
  ),
);

/// `ch-prog ck-bar`: thin blue progress line.
class CkBar extends StatelessWidget {
  const CkBar(this.ratio, {super.key, this.height = 5});
  final double ratio;
  final double height;
  @override
  Widget build(BuildContext context) => Container(
    height: height,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(color: AppColors.barTrack, borderRadius: BorderRadius.circular(6)),
    child: Align(
      alignment: Alignment.centerLeft,
      child: AnimatedFractionallySizedBox(
        duration: const Duration(milliseconds: 200),
        widthFactor: ratio.clamp(0.0, 1.0),
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(6)),
        ),
      ),
    ),
  );
}

/// `fl-top`: back button, big title, grey line (forms).
class CkTop extends StatelessWidget {
  const CkTop({super.key, required this.title, required this.sub, required this.onBack, this.backLabel = 'Back to check-ins'});
  final String title, sub, backLabel;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) {
    final web = CaWeb.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        spacing: 10,
        children: [
          CaBackBtn(tooltip: backLabel, onTap: onBack),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.s(web ? 24 : 20, W.w8, ls: web ? -.24 : -.2, h: 1.2)),
                Text(sub, style: AppText.s(12, W.w6, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A form page: the top bar and progress stay put, the questions scroll under them.
class CkPage extends StatelessWidget {
  const CkPage({super.key, required this.web, required this.header, required this.children});
  final bool web;
  final List<Widget> header, children;
  @override
  Widget build(BuildContext context) {
    final x = web ? 32.0 : 16.0;
    Widget center(Widget w) => Center(
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: web ? 640 : double.infinity), child: w),
    );
    return CaWeb(
      web: web,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(x, web ? 32 : 8, x, 12),
            child: center(Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: header)),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(x, 0, x, web ? 72 : 24),
              child: center(Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: children)),
            ),
          ),
        ],
      ),
    );
  }
}

/// `ck-done`: the green tick card after sending. A long question goes above its answer; [photos] show as
/// small pictures that open full size.
class CkDone extends StatelessWidget {
  const CkDone({super.key, required this.title, required this.sub, required this.rows, required this.buttons, this.photos = const []});
  final String title, sub;
  final List<(String, String)> rows;
  final List<(String, String)> photos;
  final Widget buttons;
  @override
  Widget build(BuildContext context) {
    Widget sec(String t) => Padding(
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Text(t.toUpperCase(), style: AppText.s(11.5, W.w8, color: AppColors.muted, ls: 0.5)),
    );
    Widget box(Widget child) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: child,
    );
    final skipped = {'', '—', 'Skipped'};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        // Sent: tick, title and when, in one soft green card.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.okBg, borderRadius: BorderRadius.circular(14)),
          child: Row(
            spacing: 12,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.okSolid, shape: BoxShape.circle),
                child: const AppIcon(AppIcons.check, size: 20, color: AppColors.white, stroke: 2.6),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                  Text(title, style: AppText.s(16, W.w8, color: AppColors.okText)),
                  Text(sub, style: AppText.s(12.5, W.w5, color: AppColors.okText)),
                ]),
              ),
            ],
          ),
        ),
        // Every question with its answer: the question in grey, the answer under it (E: finish page).
        if (rows.isNotEmpty) ...[
          sec('Your answers'),
          box(Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, (k, v)) in rows.indexed)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 10,
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text('${i + 1}.', style: AppText.s(12.5, W.w7, color: AppColors.muted, h: 1.4)),
                      ),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
                          Text(k, style: AppText.s(12.5, W.w6, color: AppColors.muted, h: 1.4)),
                          Text(
                            skipped.contains(v) ? 'Skipped' : v,
                            style: skipped.contains(v) ? AppText.s(13.5, W.w5, color: AppColors.muted) : AppText.s(14, W.w7, h: 1.4),
                          ),
                        ]),
                      ),
                    ],
                  ),
                ),
            ],
          )),
        ],
        if (photos.isNotEmpty) ...[
          sec('Photos'),
          box(Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Align(alignment: Alignment.centerLeft, child: photoThumbs(photos)))),
        ],
        const SizedBox(height: 2),
        buttons,
      ],
    );
  }
}

/// A photo answer kept as a data URL (works offline, goes through the outbox).
Uint8List? dataBytes(String? url) {
  if (url == null) return null;
  final i = url.indexOf(',');
  if (i < 0) return null;
  try {
    return base64Decode(url.substring(i + 1));
  } on FormatException {
    return null;
  }
}

/// Dashed rounded border (`ck-slot`).
class DashedBox extends StatelessWidget {
  const DashedBox({super.key, required this.child, this.color = AppColors.tickRing, this.radius = 12});
  final Widget child;
  final Color color;
  final double radius;
  @override
  Widget build(BuildContext context) => CustomPaint(foregroundPainter: _Dash(color, radius), child: child);
}

class _Dash extends CustomPainter {
  _Dash(this.color, this.radius);
  final Color color;
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(.75));
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 5), p);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_Dash old) => old.color != color;
}

/// A choice answer (single, dropdown, yes / no, multiple): option boxes, or small chips for 5+ short options, and
/// "Other" with a text box when the coach allows it (stored as "Other: …"). One widget for the daily and weekly
/// check-ins and the coach's forms, so every type answers the same way.
class CkChoice extends StatefulWidget {
  const CkChoice({super.key, required this.q, required this.value, required this.onChanged});
  final CkQ q;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  @override
  State<CkChoice> createState() => _CkChoiceState();
}

class _CkChoiceState extends State<CkChoice> {
  static bool _isOther(Object? x) => '$x'.toLowerCase().startsWith('other:');
  late final _t = TextEditingController(text: '${_sel.firstWhere(_isOther, orElse: () => '')}'.replaceFirst(RegExp(r'^[Oo]ther:\s*'), ''));

  CkQ get q => widget.q;
  bool get _multi => q.type == 'multiple';
  List<Object?> get _sel {
    final v = widget.value;
    if (_multi) return [...((v as List?) ?? const [])];
    if (v == null) return [];
    return [q.type == 'yes_no' ? (v == true ? 'Yes' : 'No') : v];
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  void _tap(String o) {
    final sel = _sel;
    if (_multi) {
      sel.contains(o) ? sel.remove(o) : sel.add(o);
      widget.onChanged(sel.isEmpty ? null : sel);
    } else {
      widget.onChanged(q.type == 'yes_no' ? o == 'Yes' : o);
    }
  }

  String get _mine => 'Other: ${_t.text.trim()}';

  void _tapOther(bool on) {
    final sel = _sel;
    if (_multi) {
      on ? sel.removeWhere(_isOther) : sel.add(_mine);
      widget.onChanged(sel.isEmpty ? null : sel);
    } else {
      widget.onChanged(on ? null : _mine);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sel = _sel;
    final other = q.allowOther && q.type != 'yes_no';
    final otherOn = sel.any(_isOther);
    final box = otherOn
        ? CkInput(
            controller: _t,
            hint: 'Type your answer',
            onChanged: () => widget.onChanged(_multi ? [..._sel.where((x) => !_isOther(x)), _mine] : _mine),
          )
        : null;
    if (q.compact) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in q.options) CkPickChip(o, on: sel.contains(o), onTap: () => _tap(o)),
          if (other) CkPickChip('Other', on: otherOn, onTap: () => _tapOther(otherOn)),
        ]),
        ?box,
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      for (final o in q.options) CkOpt(o, sub: q.subOf(o), on: sel.contains(o), onTap: () => _tap(o)),
      if (other) CkOpt('Other', on: otherOn, onTap: () => _tapOther(otherOn)),
      ?box,
    ]);
  }
}

/// `dr-opt`: a radio row (an option of a choice question).
class CkOpt extends StatelessWidget {
  const CkOpt(this.label, {super.key, this.sub, required this.on, required this.onTap});
  final String label;
  final String? sub;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    child: Hover(
      onTap: onTap,
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: on ? AppColors.pickBg : AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? AppColors.accent : (h ? AppColors.lineHover : AppColors.line2)),
          boxShadow: on ? const [BoxShadow(color: AppColors.accentSoft, spreadRadius: 3)] : null,
        ),
        child: Row(
          spacing: 12,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.white,
                shape: BoxShape.circle,
                border: Border.all(color: on ? AppColors.accent : AppColors.line2, width: on ? 5 : 1.5),
              ),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text(label, style: AppText.s(13.5, W.w7)),
                if (sub != null && sub!.isNotEmpty) Text(sub!, style: AppText.s(12, W.w5, color: AppColors.muted)),
              ]),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A short option of a long list: a small round chip.
class CkPickChip extends StatelessWidget {
  const CkPickChip(this.label, {super.key, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    child: Hover(
      onTap: onTap,
      builder: (_, h, _) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.pickBg : AppColors.white,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: on ? AppColors.accent : (h ? AppColors.lineHover : AppColors.line2)),
        ),
        child: Text(label, style: AppText.s(13, W.w7, color: on ? AppColors.accentText : AppColors.text2)),
      ),
    ),
  );
}

/// Leaving a check-in that is not finished (E32): true = save and continue later, false = discard, null = stay
/// (closed by tapping outside).
Future<bool?> ckAskLeave(BuildContext context) => showAppModal<bool>(
  context,
  title: 'You have not finished this check-in',
  body: 'Save and continue later, or discard?',
  icon: AppIcons.clipboard,
  actions: (ctx) {
    final discard = AppButton('Discard', kind: BtnKind.danger, onPressed: () => Navigator.of(ctx).pop(false), expand: ctx.isPhone);
    final save = AppButton('Save and continue later', kind: BtnKind.primary, onPressed: () => Navigator.of(ctx).pop(true), expand: ctx.isPhone);
    return ctx.isPhone ? [Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [save, discard])] : [discard, save];
  },
);
