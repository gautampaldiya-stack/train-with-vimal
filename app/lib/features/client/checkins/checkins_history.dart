import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../home/home_model.dart' show dayShort;
import '../train/train_history.dart' show HistPill, HistSkeleton, histPage, histTile;
import 'checkins_model.dart';
import 'checkins_screen.dart' show dayLine, showPastCheckin, weekLine;

/// Check-in history (Probid 19 Nov): a page in place of the Past check-ins card on Check-ins. Weekly and Daily tabs
/// (tap or swipe), the totals as coloured cells, then months of check-ins as cards with a coloured status tile, the
/// numbers as pills and the coach's reply. Tap one for the whole check-in (Newer / Older walk the list).
class CheckinHistoryScreen extends StatefulWidget {
  const CheckinHistoryScreen({super.key});
  @override
  State<CheckinHistoryScreen> createState() => _CheckinHistoryScreenState();
}

class _CheckinHistoryScreenState extends State<CheckinHistoryScreen> {
  final c = CheckinsController();
  final _scroll = ScrollController();
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    c.start().whenComplete(() {
      if (mounted) setState(() => _busy = false);
    });
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 500) c.loadMore();
    });
  }

  @override
  void dispose() {
    c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pick(String t) async {
    if (t == c.tab) return;
    setState(() {
      _busy = true;
      c.tab = t;
      c.rows.clear();
      c.hasMore = false;
    });
    await c.load();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final d = c.data;
          final weekly = c.tab == 'weekly';
          final loading = _busy && c.rows.isEmpty;
          final months = <(DateTime, List<(int, CkRow)>)>[];
          for (final (i, r) in c.rows.indexed) {
            final m = DateTime(r.date.year, r.date.month);
            if (months.isEmpty || months.last.$1 != m) months.add((m, []));
            months.last.$2.add((i, r));
          }
          final list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (d == null && c.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(spacing: 10, children: [
                  Text(c.error!.offline ? 'You are offline. Connect to see your check-ins.' : 'Could not load your check-ins. Try again.',
                      textAlign: TextAlign.center, style: AppText.s(13.5, W.w5, color: AppColors.muted)),
                  CaButton('Try again', kind: CaBtnKind.out, small: true, expand: false, onPressed: c.load),
                ]),
              )
            else if (loading || d == null)
              const HistSkeleton(lines: 1)
            else ...[
              _totals(),
              const SizedBox(height: 6),
              if (c.rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: CaEmpty(
                    icon: AppIcons.clipboard,
                    title: weekly ? 'No weekly check-ins yet' : 'No daily check-ins yet',
                    sub: 'Check-ins you send show here, newest first.',
                  ),
                ),
              for (final (k, (m, rows)) in months.indexed) ...[
                Padding(
                  padding: EdgeInsets.only(top: k == 0 ? 12 : 18, bottom: 10),
                  child: Text(DateFormat(m.year == DateTime.now().year ? 'MMMM' : 'MMMM y').format(m), style: AppText.s(19, W.w7, ls: -0.2)),
                ),
                for (final (i, r) in rows) Padding(padding: const EdgeInsets.only(bottom: 12), child: _card(d, i, r)),
              ],
              if (c.hasMore) const HistSkeleton(cards: 1, lines: 1, header: false),
            ],
          ]);
          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: c.load,
            child: histPage(
              context,
              title: 'Check-in history',
              sub: 'Every weekly and daily check-in you sent',
              backTip: 'Check-ins',
              onBack: () => context.go('/checkins'),
              scroll: _scroll,
              children: [
                // full width, a little in from the sides (Probid 19 Nov)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: CaSeg2(
                    options: const ['Weekly', 'Daily'],
                    index: weekly ? 0 : 1,
                    onPick: (i) => _pick(i == 0 ? 'weekly' : 'daily'),
                  ),
                ),
                const SizedBox(height: 14),
                // a flick left / right moves Weekly ⇄ Daily, sliding (Probid 19 Nov)
                CaSwipe(index: weekly ? 0 : 1, count: 2, onPick: (i) => _pick(i == 0 ? 'weekly' : 'daily'), child: KeyedSubtree(key: ValueKey(c.tab), child: list)),
              ],
            ),
          );
        },
      );

  /// All, sent and missed of this tab: one plain white card, three numbers (Probid 19 Nov: simple).
  Widget _totals() {
    Widget cell(int n, String l, Color ink) => Expanded(
          child: Column(spacing: 2, children: [
            Text('$n', style: AppText.s(20, W.w8, color: ink, tabular: true)),
            Text(l, style: AppText.s(12, W.w5, color: AppColors.muted)),
          ]),
        );
    const div = VerticalDivider(width: 1, thickness: 1, color: AppColors.line);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: IntrinsicHeight(
        child: Row(children: [
          cell(c.total, 'In all', AppColors.text),
          div,
          cell(c.totalSent, 'Sent', c.totalSent > 0 ? AppColors.okText : AppColors.text),
          div,
          cell(c.totalMissed, 'Missed', c.totalMissed > 0 ? AppColors.badText : AppColors.text),
        ]),
      ),
    );
  }

  Widget _card(CheckinsData d, int i, CkRow r) {
    final weekly = c.tab == 'weekly';
    final today = !weekly && DateUtils.isSameDay(r.date, DateTime.now());
    final title = weekly ? 'Week ${r.week ?? '—'} check-in' : '${dayShort(r.date)}${today ? ' · today' : ''}';
    final sub = weekly ? weekLine(r) : dayLine(d, r);
    final (pill, pbg, pfg) = r.missed
        ? ('Missed', AppColors.badBg, AppColors.badText)
        : r.reply.isNotEmpty
            ? ('Replied', AppColors.okBg, AppColors.okText)
            : weekly
                ? (r.reviewed ? ('Reviewed', AppColors.okBg, AppColors.okText) : ('Waiting', AppColors.infoBg, AppColors.infoText))
                : ('Sent', AppColors.okBg, AppColors.okText);
    final (icon, ibg, ifg) = r.missed
        ? (AppIcons.missed, AppColors.sub, AppColors.muted)
        : weekly && r.waiting
            ? (AppIcons.clock, AppColors.infoBg, AppColors.infoText)
            : weekly
                ? (AppIcons.clipboard, AppColors.okBg, AppColors.okText)
                : (AppIcons.checkCircle, AppColors.okBg, AppColors.okText);
    final m = r.metrics;
    final pills = <Widget>[
      if (!r.missed && weekly) ...[
        if (r.weight != null) HistPill(AppIcons.scale, kg(r.weight!), bg: AppColors.accentSoft, fg: AppColors.accentText),
        if (r.change != null) HistPill(AppIcons.trendUp, kgChange(r.change!), bg: AppColors.skySoft, fg: AppColors.skyMid),
        HistPill(AppIcons.photo, r.photos > 0 ? '${r.photos} photos' : 'No photos', bg: AppColors.purpleBg, fg: AppColors.purpleText),
      ],
      if (!r.missed && !weekly) ...[
        if (m['sleep_hours'] is num) HistPill(AppIcons.moon, '${hrs(m['sleep_hours'] as num)} sleep', bg: AppColors.purpleBg, fg: AppColors.purpleText),
        if (r.steps != null) HistPill(AppIcons.steps, '${r.stepsText} steps', bg: AppColors.accentSoft, fg: AppColors.accentText),
        if (r.waterMl != null) HistPill(AppIcons.water, r.waterText, bg: AppColors.skySoft, fg: AppColors.skyMid),
      ],
    ];
    return Semantics(
      button: true,
      label: 'Open $title',
      child: Hover(
        onTap: () => showPastCheckin(context, c, i),
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: h ? AppColors.outlineHover : AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: h ? AppColors.line2 : AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
              histTile(icon, bg: ibg, fg: ifg),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                  Row(spacing: 8, children: [
                    Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(15.5, W.w7))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: pbg, borderRadius: BorderRadius.circular(7)),
                      child: Text(pill, style: AppText.s(11, W.w7, color: pfg)),
                    ),
                  ]),
                  Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.35)),
                ]),
              ),
              const Padding(padding: EdgeInsets.only(top: 12), child: AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.chevron)),
            ]),
            if (pills.isNotEmpty) Wrap(spacing: 8, runSpacing: 6, children: pills),
            if (r.reply.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(color: AppColors.replyBg, borderRadius: BorderRadius.circular(10)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                  const Padding(padding: EdgeInsets.only(top: 1), child: AppIcon(AppIcons.chatBubble, size: 15, color: AppColors.okText)),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${d.coachFirst}: ', style: AppText.s(12.5, W.w8, color: AppColors.okText)),
                        TextSpan(text: r.reply),
                      ]),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.s(12.5, W.w4, color: AppColors.text2, h: 1.4),
                    ),
                  ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Weekly / Daily: a two-option switch with a white thumb that slides.
class CaSeg2 extends StatelessWidget {
  const CaSeg2({super.key, required this.options, required this.index, required this.onPick});
  final List<String> options;
  final int index;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) => Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(12)),
        child: LayoutBuilder(
          builder: (_, box) {
            final w = box.maxWidth / options.length;
            return Stack(children: [
              AnimatedPositioned(
                duration: Motion.of(context, Motion.short),
                curve: Motion.curve,
                left: w * index,
                top: 0,
                bottom: 0,
                width: w,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: const [BoxShadow(color: AppColors.shadowSoft, blurRadius: 2, offset: Offset(0, 1)), BoxShadow(color: AppColors.line, spreadRadius: 1)],
                  ),
                ),
              ),
              Row(children: [
                for (final (i, o) in options.indexed)
                  Expanded(
                    child: Semantics(
                      selected: i == index,
                      button: true,
                      child: Hover(
                        onTap: () => onPick(i),
                        builder: (_, h, _) => Center(
                          child: Text(o, style: AppText.s(13.5, W.w7, color: i == index || h ? AppColors.text : AppColors.text2)),
                        ),
                      ),
                    ),
                  ),
              ]),
            ]);
          },
        ),
      );
}

