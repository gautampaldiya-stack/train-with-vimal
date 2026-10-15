import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/photo_viewer.dart';
import '../../../core/widgets/responsive.dart';
import '../habits/habits_sheets.dart' show HkCells, hkNote, hkPill, hkSec;
import '../home/home_model.dart' show clock, dayShort;
import '../home/home_parts.dart';
import 'checkins_daily.dart';
import 'checkins_model.dart';
import 'checkins_weekly.dart';

/// Check-ins (boards `ClientCheckin` phone and `ClientCheckinWeb`). `/checkins` is the list,
/// `/checkins/daily` and `/checkins/weekly` the two forms, `/checkins/<id>` opens a past check-in.
class ClientCheckinsScreen extends StatefulWidget {
  const ClientCheckinsScreen({super.key, this.id, this.edit = false});
  final String? id;
  final bool edit;
  @override
  State<ClientCheckinsScreen> createState() => _ClientCheckinsScreenState();
}

class _ClientCheckinsScreenState extends State<ClientCheckinsScreen> {
  final c = CheckinsController();
  final _scroll = ScrollController();
  final _list = ScrollController(); // past check-ins scroll inside their card
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    c.start().then((_) => _openFromLink());
    _list.addListener(() {
      if (_list.position.extentAfter < 200) c.loadMore();
    });
  }

  @override
  void dispose() {
    c.dispose();
    _scroll.dispose();
    _list.dispose();
    super.dispose();
  }

  /// A notification ("Aman replied to your check-in") opens `/checkins/<id>`.
  void _openFromLink() {
    final id = widget.id;
    if (_opened || !mounted || id == null || id == 'daily' || id == 'weekly') return;
    _opened = true;
    final i = c.rows.indexWhere((r) => r.id == id);
    if (i >= 0) showPastCheckin(context, c, i);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.id == 'daily') return DailyCheckin(c: c, edit: widget.edit);
    if (widget.id == 'weekly') return WeeklyCheckin(c: c);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final d = c.data;
        if (d == null) {
          final e = c.error;
          return Center(
            child: e == null
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 10,
                      children: [
                        Text(e.offline ? 'You are offline' : 'Could not load this', style: AppText.s(15, W.w7)),
                        Text(
                          e.offline ? 'Connect to the internet to load your check-ins' : e.message,
                          textAlign: TextAlign.center,
                          style: AppText.s(13, W.w4, color: AppColors.muted),
                        ),
                        CaButton('Try again', kind: CaBtnKind.out, expand: false, onPressed: c.load),
                      ],
                    ),
                  ),
          );
        }
        return context.isPhone ? _phone(d) : _web(d);
      },
    );
  }

  // ─────────────────────────────── Layouts

  Widget _phone(CheckinsData d) => RefreshIndicator(
    onRefresh: c.load,
    color: AppColors.accent,
    child: SingleChildScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [_top(d, web: false), _cells(d), ?_daily(d), ?_weekly(d), _history(d)],
      ),
    ),
  );

  Widget _web(CheckinsData d) => CaWeb(
    web: true,
    child: RefreshIndicator(
      onRefresh: c.load,
      color: AppColors.accent,
      child: SingleChildScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 72),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: LayoutBuilder(
              builder: (context, box) {
                final left = [_cells(d), ?_daily(d), ?_weekly(d)];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 18,
                  children: [
                    _top(d, web: true),
                    if (box.maxWidth >= 720)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 20,
                        children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: left),
                          ),
                          Expanded(child: _history(d)),
                        ],
                      )
                    else ...[
                      ...left,
                      _history(d),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );

  Widget _top(CheckinsData d, {required bool web}) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Check-ins', style: AppText.s(web ? 26 : 22, W.w8, ls: web ? -0.26 : -0.22, h: 1.2)),
        Text(
          d.sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.s(12, W.w6, color: AppColors.muted),
        ),
      ],
    );
    if (web) return title;
    return Row(
      spacing: 10,
      children: [
        CaIconBtn(AppIcons.chevronLeft, tooltip: 'Back to More', onTap: () => context.go('/more')),
        Expanded(child: title),
      ],
    );
  }

  Widget _cells(CheckinsData d) => ChCard(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    gap: 8,
    children: [HkCells(d.cells(false), big: !context.isPhone)],
  );

  // ─────────────────────────────── Daily card

  Widget? _daily(CheckinsData d) {
    final f = d.daily.form;
    if (f == null) return null;
    final s = d.daily.sent ?? CheckinsController.queuedDaily;
    final today = d.daily.date;
    String line() {
      final m = s!.metrics;
      final e = f.byMetric('energy')?.show(m['energy'], short: true);
      final parts = [if (m['sleep_hours'] is num) '${hrs(m['sleep_hours'] as num)} sleep', if (e != null) 'energy $e'];
      final at = s.sentAt;
      return [if (at != null) 'Sent at ${clock(at)}' else 'Saved · sends when you are online', if (parts.isNotEmpty) parts.join(', ')].join(' · ');
    }

    return ChCard(
      gap: 10,
      children: [
        ChHead(
          lead: const ChIcon(AppIcons.sun, tone: ChTone.blue),
          title: 'Daily check-in',
          sub: s == null
              ? 'Today, ${dayShortNoYear(today).replaceFirst(',', '')} · 30 seconds'
              : 'Today · sent at ${s.sentAt == null ? '—' : clock(s.sentAt!)}',
          action: s == null ? hkPill('Due today', bg: AppColors.infoBg, fg: AppColors.infoText) : hkPill('Sent', bg: AppColors.okBg, fg: AppColors.okText),
        ),
        if (s == null) ...[
          Text(_dailyWhat(f), style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.45)),
          CaButton('Start daily check-in', icon: AppIcons.play, onPressed: () => context.go('/checkins/daily')),
        ] else ...[
          ChNote(
            icon: AppIcons.checkCircle,
            bg: AppColors.okBg,
            fg: AppColors.okText,
            child: Text(line(), style: AppText.s(13, W.w7, color: AppColors.okText)),
          ),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: CaButton('View', kind: CaBtnKind.out, small: true, icon: AppIcons.eye, onPressed: () => context.go('/checkins/daily')),
              ),
              Expanded(
                child: CaButton('Edit answers', kind: CaBtnKind.out, small: true, icon: AppIcons.edit, onPressed: () => context.go('/checkins/daily?edit=1')),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// "Weight, sleep, energy, mood, hunger and soreness. Takes about 30 seconds."
  String _dailyWhat(CkForm f) {
    const names = {'weight': 'weight', 'sleep_hours': 'sleep'};
    final n = [for (final q in f.questions) names[q.metric] ?? q.text.toLowerCase()];
    final list = n.length < 2 ? n.join() : '${n.sublist(0, n.length - 1).join(', ')} and ${n.last}';
    return '${list[0].toUpperCase()}${list.substring(1)}. Takes about 30 seconds.';
  }

  // ─────────────────────────────── Weekly card

  Widget? _weekly(CheckinsData d) {
    final w = d.weekly, f = w.form;
    if (f == null) return null;
    final s = w.sent ?? CheckinsController.queuedWeekly;
    final now = DateTime.now();
    final dueToday = DateUtils.isSameDay(now, w.dueAt);
    final draft = w.draft;
    final answered = draft == null ? 0 : _draftCount(f, draft);
    String sentSub() {
      final at = s!.sentAt;
      final when = at == null ? 'Saved on this phone' : 'Sent ${DateUtils.isSameDay(at, now) ? 'today' : dayShort(at)}, ${clock(at)}';
      return '$when · ${s.reply.isNotEmpty ? '${d.coachFirst} replied' : (s.reviewed ? '${d.coachFirst} has seen it' : 'waiting for ${d.coachFirst}')}';
    }

    return ChCard(
      gap: 10,
      children: [
        ChHead(
          lead: const ChIcon(AppIcons.clipboard, tone: ChTone.amber),
          title: 'Weekly check-in · week ${w.week}',
          sub: s == null ? 'Due ${w.due} · ${now.isAfter(w.dueAt) ? 'you can still send it' : 'you can fill it in early'}' : sentSub(),
          action: s == null
              ? hkPill(now.isAfter(w.dueAt) ? 'Late' : (dueToday ? 'Due today' : 'Due ${dayName(w.dueAt)}'), bg: AppColors.amberBg, fg: AppColors.amberText)
              : hkPill('Sent', bg: AppColors.okBg, fg: AppColors.okText),
        ),
        if (s == null) ...[
          Wrap(spacing: 5, runSpacing: 5, children: [for (final q in f.questions) _chip(q.chip)]),
          if (answered > 0)
            Row(
              spacing: 10,
              children: [
                Expanded(child: ChBar(answered / f.questions.length, color: AppColors.accent)),
                Text('Draft · $answered of ${f.questions.length} answered', style: AppText.s(12, W.w7, color: AppColors.muted)),
              ],
            ),
          CaButton(
            answered > 0 ? 'Continue check-in' : 'Start weekly check-in',
            kind: answered > 0 ? CaBtnKind.pri : CaBtnKind.dark,
            icon: AppIcons.play,
            onPressed: () => context.go('/checkins/weekly'),
          ),
        ] else ...[
          ChNote(
            icon: AppIcons.checkCircle,
            bg: AppColors.okBg,
            fg: AppColors.okText,
            child: Text(
              'Week ${w.week} sent · ${[if (s.weight != null) kg(s.weight!), s.photos > 0 ? '${s.photos} photos' : 'no photos'].join(' · ')}',
              style: AppText.s(13, W.w7, color: AppColors.okText),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: CaButton(
              'View what you sent',
              kind: CaBtnKind.out,
              small: true,
              expand: false,
              icon: AppIcons.eye,
              onPressed: () {
                if (s.id == null) {
                  showToast(context, 'Still sending', sub: 'It goes to ${d.coachFirst} when you are online', kind: ToastKind.info);
                  return;
                }
                if (c.tab != 'weekly') c.pickTab('weekly');
                final i = c.rows.indexWhere((r) => r.id == s.id);
                showPastCheckin(context, c, i < 0 ? 0 : i, row: i < 0 ? s : null);
              },
            ),
          ),
        ],
      ],
    );
  }

  int _draftCount(CkForm f, Map<String, dynamic> dr) {
    final a = (dr['answers'] as Map?) ?? {};
    var n = 0;
    for (final q in f.questions) {
      if (q.type == 'photo') {
        if (dr['no_photos'] == true || ((dr['photos'] as Map?)?.isNotEmpty ?? false)) n++;
      } else if (q.metric == 'weight') {
        if ((dr['step'] as num? ?? 0) > 0) n++;
      } else if (a['${q.id}'] != null) {
        n++;
      }
    }
    return n;
  }

  Widget _chip(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
    decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(6)),
    child: Text(t, style: AppText.s(11.5, W.w7, color: AppColors.text2)),
  );

  // ─────────────────────────────── Past check-ins

  Widget _history(CheckinsData d) {
    Widget tab(String l, String v) => Hover(
      onTap: () => c.pickTab(v),
      builder: (_, h, _) {
        final on = c.tab == v;
        return Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.white : null,
            borderRadius: BorderRadius.circular(6),
            boxShadow: on
                ? const [BoxShadow(color: AppColors.shadowSoft, blurRadius: 2, offset: Offset(0, 1)), BoxShadow(color: AppColors.line, spreadRadius: 1)]
                : null,
          ),
          child: Text(l, style: AppText.s(13, W.w6, color: on || h ? AppColors.text : AppColors.text2)),
        );
      },
    );
    final rows = c.rows;
    final maxH = context.isPhone ? (MediaQuery.sizeOf(context).height * .6).clamp(320.0, 520.0) : 560.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              spacing: 8,
              children: [
                Expanded(child: Text('Past check-ins', style: AppText.s(15, W.w8))),
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [tab('Weekly', 'weekly'), tab('Daily', 'daily')]),
                ),
              ],
            ),
          ),
          if (rows.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: ListView.builder(
                controller: _list,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: rows.length + (c.hasMore ? 1 : 0),
                itemBuilder: (_, i) => i < rows.length
                    ? _row(d, i, rows[i])
                    : const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Center(
                          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
                        ),
                      ),
              ),
            ),
          if (rows.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Text(
                'No check-ins here yet.',
                textAlign: TextAlign.center,
                style: AppText.s(13, W.w4, color: AppColors.muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(CheckinsData d, int i, CkRow r) {
    final weekly = c.tab == 'weekly';
    final today = !weekly && DateUtils.isSameDay(r.date, DateTime.now());
    final title = weekly ? 'Week ${r.week ?? '—'}' : '${dayShortNoYear(r.date)}${today ? ' · today' : ''}';
    final sub = weekly ? weekLine(r) : dayLine(d, r);
    final (pill, pbg, pfg) = r.missed
        ? ('Missed', AppColors.badBg, AppColors.badText)
        : r.reply.isNotEmpty
        ? ('Replied', AppColors.okBg, AppColors.okText)
        : weekly
        ? (r.reviewed ? ('Reviewed', AppColors.okBg, AppColors.okText) : ('Sent', AppColors.infoBg, AppColors.infoText))
        : ('Sent', AppColors.sub, AppColors.text2);
    final wait = weekly && r.waiting;
    final (ibg, ifg, icon) = r.missed
        ? (AppColors.badBg, AppColors.badText, AppIcons.close)
        : wait
        ? (AppColors.infoBg, AppColors.infoText, AppIcons.clock)
        : (AppColors.okBg, AppColors.okText, AppIcons.check);
    return Hover(
      onTap: () => showPastCheckin(context, c, i),
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          spacing: 10,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: ibg, shape: BoxShape.circle),
              child: AppIcon(icon, size: 13, color: ifg, stroke: 2.6),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 1,
                children: [
                  Text(title, style: AppText.s(14, W.w7, color: h ? AppColors.accentText : AppColors.text)),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.s(12, W.w4, color: AppColors.muted),
                  ),
                  if (r.reply.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                      decoration: BoxDecoration(color: AppColors.replyBg, borderRadius: BorderRadius.circular(8)),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${d.coachFirst}: ',
                              style: AppText.s(12, W.w8, color: AppColors.okText),
                            ),
                            TextSpan(text: r.reply),
                          ],
                        ),
                        style: AppText.s(12, W.w4, color: AppColors.text2, h: 1.4),
                      ),
                    ),
                ],
              ),
            ),
            hkPill(pill, bg: pbg, fg: pfg),
            const AppIcon(AppIcons.chevronRight, size: 15, color: AppColors.chevron),
          ],
        ),
      ),
    );
  }
}

/// "Sun, 4 Oct · 71.6 kg · 3 photos" / "Sun, 20 Sep · not sent"
String weekLine(CkRow r) {
  if (r.missed) return '${dayShortNoYear(r.date)} · not sent';
  return [dayShortNoYear(r.date), if (r.weight != null) kg(r.weight!), r.photos > 0 ? '${r.photos} photos' : 'no photos'].join(' · ');
}

/// "7.5 h sleep · energy Good · “Felt strong today”" / "Not sent · reminder went at 9:00 pm"
String dayLine(CheckinsData d, CkRow r) {
  if (r.missed) return 'Not sent · reminder went at ${r.reminder}';
  final m = r.metrics, f = d.daily.form;
  final e = f?.byMetric('energy')?.show(m['energy'], short: true);
  return [
    if (m['sleep_hours'] is num) '${hrs(m['sleep_hours'] as num)} sleep',
    if (e != null) 'energy $e',
    if ('${m['note'] ?? ''}'.isNotEmpty) '“${m['note']}”',
  ].join(' · ');
}

// ─────────────────────────────── Past check-in sheet

/// One past check-in, with Newer / Older to walk the list. [row] shows a check-in that is not in the
/// list yet (just sent).
Future<void> showPastCheckin(BuildContext context, CheckinsController c, int index, {CkRow? row}) {
  final at = ValueNotifier<int>(index);
  final weekly = c.tab == 'weekly';
  CkRow cur() => row ?? c.rows[at.value.clamp(0, c.rows.length - 1)];
  String title() {
    final r = cur();
    return weekly ? 'Week ${r.week ?? c.data?.weekly.week} check-in' : '${dayShortNoYear(r.date)} · daily check-in';
  }

  String sub() {
    final r = cur();
    if (r.missed) return weekly ? '${dayShortNoYear(r.date)} · not sent' : 'Not sent';
    final s = r.sentAt;
    if (s == null) return 'Saved on this phone';
    return weekly ? 'Sent ${dayShortNoYear(s)}, ${clock(s)}' : 'Sent at ${clock(s)}';
  }

  Future<void> step(BuildContext ctx, int d) async {
    if (row != null) {
      showToast(ctx, d < 0 ? 'This is the newest one' : 'No older check-ins here', kind: ToastKind.info);
      return;
    }
    final j = at.value + d;
    if (j >= c.rows.length && c.hasMore) await c.loadMore();
    if (j < 0 || j >= c.rows.length) {
      if (ctx.mounted) showToast(ctx, d < 0 ? 'This is the newest one' : 'No older check-ins here', kind: ToastKind.info);
      return;
    }
    at.value = j;
  }

  return showAppSheet(
    context,
    listen: Listenable.merge([at, c]),
    titleOf: title,
    subOf: sub,
    footerStretch: true,
    builder: (ctx) => _PastBody(key: ValueKey(cur().id ?? cur().j['date']), c: c, row: cur(), weekly: weekly),
    footer: (ctx) => [
      Row(
        spacing: 8,
        children: [
          Expanded(
            child: CaButton('Newer', kind: CaBtnKind.out, icon: AppIcons.chevronLeft, onPressed: () => step(ctx, -1)),
          ),
          Expanded(
            child: CaButton('Older', kind: CaBtnKind.out, trailingIcon: AppIcons.chevronRight, onPressed: () => step(ctx, 1)),
          ),
        ],
      ),
    ],
  ).whenComplete(at.dispose);
}

class _PastBody extends StatefulWidget {
  const _PastBody({super.key, required this.c, required this.row, required this.weekly});
  final CheckinsController c;
  final CkRow row;
  final bool weekly;
  @override
  State<_PastBody> createState() => _PastBodyState();
}

class _PastBodyState extends State<_PastBody> {
  Map<String, dynamic>? _detail;
  int _pose = 0;

  @override
  void initState() {
    super.initState();
    final id = widget.row.id;
    if ((widget.weekly || widget.row.photos > 0) && id != null) {
      _detail = widget.c.cachedDetail(id);
      if (_detail == null) {
        widget.c.detail(id).then((j) {
          if (mounted) setState(() => _detail = j);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final d = widget.c.data!;
    final kids = <Widget>[];
    if (widget.weekly) {
      if (!r.missed) kids.add(HkCells(r.weekCells));
    } else if (!r.missed) {
      final f = d.daily.form;
      String lab(String m) => f?.byMetric(m)?.show(r.metrics[m], short: true) ?? '—';
      kids.add(
        HkCells([
          (r.metrics['sleep_hours'] is num ? hrs(r.metrics['sleep_hours'] as num) : '—', 'Sleep'),
          (lab('energy'), 'Energy'),
          (lab('mood'), 'Mood'),
          (r.stepsText, 'Steps'),
        ]),
      );
    }
    if (r.reply.isNotEmpty) {
      final when = r.reviewedAt;
      kids.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: AppColors.replyBg, borderRadius: BorderRadius.circular(12)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              ChAvatar(d.coachInitials, green: true),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: d.coachName, style: AppText.s(13, W.w8)),
                          if (when != null)
                            TextSpan(
                              text: '  ${widget.weekly ? dayShortNoYear(when) : '${dayShortNoYear(when)}, ${clock(when)}'}',
                              style: AppText.s(11, W.w6, color: AppColors.muted),
                            ),
                        ],
                      ),
                    ),
                    Text(r.reply, style: AppText.s(13.5, W.w4, color: AppColors.text2, h: 1.45)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else if (widget.weekly && !r.missed) {
      kids.add(
        _wait(
          r.reviewed
              ? '${d.coachFirst} reviewed this check-in and did not add a note.'
              : 'Waiting for ${d.coachFirst}’s reply. ${d.coachFirst} usually replies within a day.',
        ),
      );
    }
    if (r.missed) {
      kids.add(
        hkNote(
          AppIcons.clock,
          widget.weekly
              ? 'This check-in was not sent. A missed week cannot be filled in later, but the next one opens every Sunday at 6:00 pm.'
              : 'Not sent. A reminder went at ${r.reminder}. Daily check-ins cannot be sent for past days.',
        ),
      );
    }
    final qa = <(String, String)>[];
    if (widget.weekly && !r.missed) {
      final ans = (_detail?['answers'] as List? ?? []).cast<Map<String, dynamic>>();
      final f = d.weekly.form;
      final seen = <int>{};
      for (final a in ans) {
        final qid = (a['question'] as num?)?.toInt();
        final q0 = f?.questions.where((x) => x.id == qid).firstOrNull;
        if (qid == null || a['photo'] != null && '${a['photo']}'.isNotEmpty || q0?.type == 'photo' || a['question_type'] == 'photo') continue;
        seen.add(qid);
        final q =
            f?.questions.where((x) => x.id == qid).firstOrNull ??
            CkQ({'id': qid, 'text': a['question_text'], 'type': a['question_type'], 'metric': a['metric']});
        qa.add((q.text, q.show(a['value']) ?? '—'));
      }

      if (_detail == null) {
        kids.add(
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
            ),
          ),
        );
      }
    } else if (!r.missed) {
      final f = d.daily.form;
      String lab(String m) => f?.byMetric(m)?.show(r.metrics[m], short: true) ?? '—';
      qa.addAll([
        ('Hunger', lab('hunger')),
        ('Soreness', lab('soreness')),
        ('Water', r.waterText),
        ('Morning weight', r.weight == null ? '—' : kg(r.weight!)),
        ('Note', '${r.metrics['note'] ?? ''}'.isEmpty ? '—' : '${r.metrics['note']}'),
      ]);
    }
    if (qa.isNotEmpty) {
      kids.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, (q, a)) in qa.indexed)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 1,
                  children: [
                    Text(q, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
                    Text(a, style: AppText.s(13.5, W.w7)),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    final photos = [
      for (final p in (_detail?['photos'] as List? ?? []).cast<Map<String, dynamic>>()) ('${p['label'] ?? p['pose'] ?? 'Photo'}', '${p['image'] ?? ''}'),
    ];
    if (photos.isNotEmpty) {
      final at = _pose.clamp(0, photos.length - 1);
      final img = photoImage(photos[at].$2);
      kids.addAll([
        hkSec(photos.length == 1 ? 'Photo' : 'Photos'),
        Column(
          spacing: 8,
          children: [
            Semantics(
              button: true,
              label: 'Open ${photos[at].$1} photo full size',
              child: Hover(
                onTap: () => showPhotoViewer(context, photos, at),
                builder: (_, h, _) => Container(
                  height: 220,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: h ? AppColors.accent : AppColors.line),
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppColors.figBg),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (img != null) Image(image: img, fit: BoxFit.contain, errorBuilder: (_, _, _) => _fig(photos[at].$1, r)),
                      if (img == null) _fig(photos[at].$1, r),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.viewerBtnDark, borderRadius: BorderRadius.circular(6)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 4,
                            children: [
                              const AppIcon(AppIcons.eye, size: 12, color: AppColors.white),
                              Text('Tap to open', style: AppText.s(11, W.w7, color: AppColors.white)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (photos.length > 1)
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 2,
                  children: [
                    for (final (i, (n, _)) in photos.indexed)
                      Hover(
                        onTap: () => setState(() => _pose = i),
                        builder: (_, h, _) => Container(
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: i == at ? AppColors.white : null,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: i == at
                                ? const [
                                    BoxShadow(color: AppColors.shadowSoft, blurRadius: 2, offset: Offset(0, 1)),
                                    BoxShadow(color: AppColors.line, spreadRadius: 1),
                                  ]
                                : null,
                          ),
                          child: Text(n, style: AppText.s(13, W.w6, color: i == at || h ? AppColors.text : AppColors.text2)),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: kids);
  }

  Widget _fig(String pose, CkRow r) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    spacing: 4,
    children: [
      const AppIcon(AppIcons.user, size: 84, color: AppColors.figText, stroke: 1.2),
      Text(
        '$pose · ${r.date.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][r.date.month - 1]}',
        style: AppText.s(11.5, W.w7, color: AppColors.figText),
      ),
    ],
  );

  Widget _wait(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(10)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: AppIcon(AppIcons.clock, size: 16, color: AppColors.infoText),
        ),
        Expanded(
          child: Text(t, style: AppText.s(12.5, W.w5, color: AppColors.infoText, h: 1.45)),
        ),
      ],
    ),
  );
}
