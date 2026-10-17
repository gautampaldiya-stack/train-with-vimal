import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/media.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tooltip.dart';
import 'tc_model.dart';

const _quick = ['Great week, keep going!', 'Let’s talk at your next session.', 'I’ve updated your plan.'];

/// "Tue 6 Oct, 7:40 pm", "Today, 11:45 am", "Yesterday, 6:05 pm".
String tcWhen(DateTime t) {
  final now = DateTime.now();
  final day = DateUtils.dateOnly(t), today = DateUtils.dateOnly(now);
  final time = DateFormat('h:mm a').format(t).toLowerCase();
  if (day == today) return 'Today, $time';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday, $time';
  return '${DateFormat('EEE d MMM').format(t)}, $time';
}

/// The open check-in (right side on web, its own page on a phone): who and when, ‹ › and Open profile, the 4
/// numbers, Answers compared with last time, what they wrote, photos, Your reply and Mark reviewed.
class TcPanel extends StatefulWidget {
  const TcPanel({super.key, required this.c, required this.row, required this.onProfile, this.onBack});
  final TcController c;
  final TcRow row;
  final VoidCallback onProfile;

  /// Phone only: the ← in the top bar.
  final VoidCallback? onBack;

  @override
  State<TcPanel> createState() => _TcPanelState();
}

class _TcPanelState extends State<TcPanel> {
  /// Unsent replies stay with their check-in while the trainer moves between them.
  static final _drafts = <String, String>{};
  late final reply = TextEditingController(text: _drafts[widget.row.id] ?? '');
  bool busy = false;

  TcRow get r => widget.row;
  TcController get c => widget.c;

  @override
  void initState() {
    super.initState();
    reply.addListener(() {
      _drafts[r.id] = reply.text;
      setState(() {});
    });
  }

  @override
  void dispose() {
    reply.dispose();
    super.dispose();
  }

  Future<void> _mark() async {
    setState(() => busy = true);
    final text = reply.text.trim();
    final messenger = context;
    try {
      await c.review(r.id, text);
      _drafts.remove(r.id);
      if (!messenger.mounted) return;
      showToast(messenger, '${r.first}’s check-in reviewed', sub: text.isEmpty ? 'Moved to Reviewed' : 'Your reply was sent', kind: ToastKind.ok, action: 'Undo', onAction: () => c.unreview(r.id));
      if (widget.onBack != null && c.tab == 'to_review') widget.onBack!();
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not save', sub: e.message, kind: ToastKind.info);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _reopen() async {
    try {
      await c.unreview(r.id);
      if (mounted) showToast(context, 'Marked as not reviewed', sub: '${r.first}’s check-in is back in To review', kind: ToastKind.info);
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not change it', sub: e.message, kind: ToastKind.info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    return FutureBuilder<Map>(
      future: c.detail(r.id),
      builder: (context, snap) {
        final head = _head(phone, snap.data);
        if (snap.hasError) {
          return Column(children: [head, EmptyState('Could not open this check-in', sub: snap.error is ApiError ? (snap.error as ApiError).message : null)]);
        }
        if (!snap.hasData) {
          return Column(children: [
            head,
            const Padding(padding: EdgeInsets.all(40), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))),
          ]);
        }
        final d = snap.data!;
        final body = _body(d, phone);
        // Phone: the page itself scrolls (board TrainerCheckinsMobile keeps the card in the page).
        if (widget.onBack != null) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            head,
            Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 20), child: body),
            if (!r.reviewed) _foot(phone),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          head,
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(phone ? 16 : 20, 14, phone ? 16 : 20, 20),
              child: body,
            ),
          ),
          if (!r.reviewed) _foot(phone),
        ]);
      },
    );
  }

  // ─────────────────────────────── Top: who, when, ‹ › and Open profile

  Widget _head(bool phone, Map? d) {
    final plan = d?['plan'] as Map?;
    final sub = [
      '${r.kind} · sent ${tcWhen(r.created)}',
      if (plan != null) '${plan['name']} · week ${plan['week']}',
    ].join(' · ');
    final i = c.index;
    final nav = [
      AppIconButton(AppIcons.chevronLeft, tooltip: 'Previous', small: phone, onPressed: i > 0 ? () => c.step(-1) : null),
      AppIconButton(AppIcons.chevronRight, tooltip: 'Next', small: phone, onPressed: i >= 0 && i < c.rows.length - 1 ? () => c.step(1) : null),
    ];
    return Container(
      padding: EdgeInsets.fromLTRB(phone ? 8 : 20, phone ? 8 : 16, phone ? 12 : 20, phone ? 10 : 16),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(spacing: phone ? 8 : 12, children: [
        if (widget.onBack != null) AppIconButton(AppIcons.chevronLeft, tooltip: 'Back', ghost: true, onPressed: widget.onBack),
        AppAvatar(r.name, size: 40, colors: AppColors.avatarCode(r.color), initials: r.initials),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(phone ? 16 : 15, W.w7)),
            Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
          ]),
        ),
        ...nav,
        phone
            ? AppIconButton(AppIcons.eye, tooltip: 'Open profile', small: true, onPressed: widget.onProfile)
            : AppButton('Open profile', icon: AppIcons.eye, size: BtnSize.sm, onPressed: widget.onProfile),
      ]),
    );
  }

  // ─────────────────────────────── Body

  Widget _body(Map d, bool phone) {
    final rv = (d['review'] as Map?) ?? const {};
    final kpis = [for (final k in (rv['kpis'] as List? ?? const [])) k as Map];
    final rows = [for (final q in (rv['rows'] as List? ?? const [])) q as Map];
    final note = '${rv['note'] ?? ''}';
    final photos = [for (final p in (d['photos'] as List? ?? const [])) p as Map];
    Color trend(Object? t, Color base) => t == 'up' ? AppColors.okText : (t == 'down' ? AppColors.badText : base);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 0, children: [
      if (kpis.isNotEmpty) _kpis(kpis, phone, trend),
      if (rows.isNotEmpty) ...[
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: Text('Answers', style: AppText.s(14, W.w8))),
          Text('Compared with last time', style: AppText.s(12, W.w5, color: AppColors.muted)),
        ]),
        const SizedBox(height: 6),
        for (final (i, q) in rows.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(border: i == rows.length - 1 ? null : const Border(bottom: BorderSide(color: AppColors.line))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
              SizedBox(width: phone ? 92 : 120, child: Text('${q['label']}', style: AppText.s(13.5, W.w5, color: AppColors.text2))),
              Expanded(child: Text('${q['value']}', style: AppText.s(13.5, W.w6))),
              if ('${q['last'] ?? ''}'.isNotEmpty)
                Text('${q['last']}' == 'same' ? 'same as last' : '${q['last']}', style: AppText.s(12.5, W.w5, color: trend(q['trend'], AppColors.muted))),
            ]),
          ),
      ],
      if (note.isNotEmpty) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(color: AppColors.caWebBg, borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
            Text('${r.first} wrote', style: AppText.s(12, W.w7, color: AppColors.muted)),
            Text(note, style: AppText.s(13.5, W.w5, color: AppColors.text2, h: 1.5)),
          ]),
        ),
      ],
      if (photos.isNotEmpty) ...[
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: Text('Photos', style: AppText.s(14, W.w8))),
          Text('${photos.length} new · click to open', style: AppText.s(12, W.w5, color: AppColors.muted)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (i, p) in photos.indexed)
            Semantics(
              button: true,
              label: 'Open ${p['label']} photo',
              child: GestureDetector(
                onTap: () => showImageViewer(context, [for (final x in photos) '${x['image']}'], start: i, title: '${r.first} · ${tcWhen(r.created)}'),
                child: MouseRegion(
                  cursor: SystemMouseCursors.zoomIn,
                  child: ClipRRect(
                    borderRadius: AppRadius.all(10),
                    child: Container(
                      width: phone ? 92 : 92,
                      height: 112,
                      color: AppColors.sub,
                      child: Stack(fit: StackFit.expand, children: [
                        Image.network('${p['image']}', fit: BoxFit.cover, errorBuilder: (_, _, _) => const Center(child: AppIcon(AppIcons.photo, size: 22, color: AppColors.muted))),
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.pxPoseBg, borderRadius: AppRadius.all(6)),
                            child: Text('${p['label']}', style: AppText.s(11.5, W.w6)),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ],
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: Text('Your reply', style: AppText.s(14, W.w8))),
        const AppTooltip(
          message: 'The client gets your reply in the app with their check-in. You can change their plan from their profile.',
          child: AppIcon(AppIcons.infoAlt, size: 16, color: AppColors.muted),
        ),
      ]),
      const SizedBox(height: 10),
      r.reviewed ? _reviewed() : _composer(),
    ]);
  }

  Widget _kpis(List<Map> kpis, bool phone, Color Function(Object?, Color) trend) {
    Widget cell(Map k, {bool line = true, double left = 14}) => Container(
          padding: EdgeInsets.fromLTRB(left, 2, 10, 2),
          decoration: BoxDecoration(border: line ? const Border(left: BorderSide(color: AppColors.line)) : null),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
            Text('${k['label']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted)),
            Text('${k['value']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(15, W.w8, color: trend(k['trend'], AppColors.text))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.only(bottom: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: phone
          ? IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final col in [0, 1])
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(border: col == 1 ? const Border(left: BorderSide(color: AppColors.line)) : null),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
                        for (var i = col; i < kpis.length; i += 2) cell(kpis[i], line: false, left: col == 0 ? 0 : 12),
                      ]),
                    ),
                  ),
              ]),
            )
          : IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (i, k) in kpis.indexed) Expanded(child: cell(k, line: i > 0, left: i == 0 ? 0 : 14)),
              ]),
            ),
    );
  }

  Widget _composer() => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
          TextField(
            controller: reply,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            style: AppText.s(13.5, W.w5),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              hintText: 'Write a short reply for ${r.first}…',
              hintStyle: AppText.s(13.5, W.w5, color: AppColors.muted),
            ),
          ),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final q in _quick)
              Hover(
                onTap: () {
                  reply.text = q;
                  reply.selection = TextSelection.collapsed(offset: q.length);
                },
                builder: (_, h, _) => Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: h ? AppColors.outlineHover : AppColors.white,
                    borderRadius: AppRadius.all(AppRadius.chip),
                    border: Border.all(color: AppColors.line2),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [Text(q, style: AppText.s(12.5, W.w6, color: AppColors.text2))]),
                ),
              ),
          ]),
        ]),
      );

  /// Reviewed: the green box with when, the reply sent and "Mark as not reviewed".
  Widget _reviewed() => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
        decoration: BoxDecoration(color: AppColors.okBg, borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: AppColors.doneValLine)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          const Padding(padding: EdgeInsets.only(top: 1), child: AppIcon(AppIcons.checkCircle, size: 18, color: AppColors.okText)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: 'Reviewed', style: AppText.s(13.5, W.w7)),
                if (r.reviewedAt != null) TextSpan(text: ' ${tcWhen(r.reviewedAt!).replaceFirst('Today', 'today').replaceFirst('Yesterday', 'yesterday')}', style: AppText.s(13.5, W.w5)),
              ])),
              Text(r.reply.isEmpty ? 'No reply, marked as seen' : r.reply, style: AppText.s(13.5, W.w5, color: AppColors.text2, h: 1.45)),
            ]),
          ),
          Hover(
            onTap: _reopen,
            builder: (_, h, _) => Text('Mark as not reviewed', style: AppText.s(13, W.w7, color: h ? AppColors.linkHover : AppColors.accent)),
          ),
        ]),
      );

  Widget _foot(bool phone) {
    final left = c.toReview - 1;
    final note = Text(left > 0 ? '$left more to review after this' : 'Last one to review', style: AppText.s(12.5, W.w5, color: AppColors.muted));
    final btn = AppButton.primary(reply.text.trim().isEmpty ? 'Mark reviewed' : 'Send and mark reviewed', icon: AppIcons.check, loading: busy, expand: phone, onPressed: _mark);
    return Container(
      padding: EdgeInsets.fromLTRB(phone ? 16 : 20, 12, phone ? 16 : 20, phone ? 14 : 12),
      decoration: const BoxDecoration(color: AppColors.white, border: Border(top: BorderSide(color: AppColors.line))),
      child: phone
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [Center(child: note), btn])
          : Row(children: [Expanded(child: note), btn]),
    );
  }
}
