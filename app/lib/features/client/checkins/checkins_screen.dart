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
import '../../../core/widgets/tooltip.dart';

/// Check-ins (boards `ClientCheckin` phone and `ClientCheckinWeb`). `/checkins` is the list,
/// `/checkins/daily` and `/checkins/weekly` the two forms, `/checkins/<id>` opens a past check-in.
class ClientCheckinsScreen extends StatefulWidget {
  const ClientCheckinsScreen({super.key, this.id, this.edit = false, this.from});
  final String? id;
  final bool edit;

  /// `?from=home`: opened from the Home card, so back goes to Home.
  final String? from;
  @override
  State<ClientCheckinsScreen> createState() => _ClientCheckinsScreenState();
}

class _ClientCheckinsScreenState extends State<ClientCheckinsScreen> {
  final c = CheckinsController();
  final _scroll = ScrollController();
  final _list = ScrollController(); // past check-ins scroll inside their card
  bool _opened = false;
  bool _atEnd = false;

  @override
  void initState() {
    super.initState();
    // From Home: the open day (today, or yesterday while unsent), not a day picked earlier on the strip.
    if (widget.from == 'home') CheckinsController.pickedDay = null;
    c.start().then((_) => _openFromLink());
    _list.addListener(() {
      if (_list.position.extentAfter < 200) c.loadMore();
      // The fade and "scroll for older" line follow the list's position.
      final end = _list.position.extentAfter < 4;
      if (end != _atEnd) setState(() => _atEnd = end);
    });
  }

  @override
  void dispose() {
    c.dispose();
    _scroll.dispose();
    _list.dispose();
    _dayCtl?.dispose();
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
    if (widget.id == 'daily') return DailyCheckin(c: c, edit: widget.edit, back: widget.from == 'home' ? '/home' : '/checkins');
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
        children: [_top(d, web: false), ?_setup(d), _cells(d), ?_daily(d), ?_weekly(d), ..._forms(d), _history(d)],
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
                final left = [?_setup(d), _cells(d), ?_daily(d), ?_weekly(d)];
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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              spacing: 14,
                              children: [..._forms(d), _history(d)],
                            ),
                          ),
                        ],
                      )
                    else ...[
                      ...left,
                      ..._forms(d),
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
        CutText(
          web ? d.sub : d.subShort,
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
        CaBackBtn(tooltip: 'Back to More', onTap: () => context.go('/more')),
        Expanded(child: title),
      ],
    );
  }

  Widget _cells(CheckinsData d) => ChCard(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    gap: 8,
    children: [HkCells(d.cells(false), big: !context.isPhone)],
  );

  // ─────────────────────────────── Setup questionnaire not finished (E42)

  Widget? _setup(CheckinsData d) {
    final ob = d.onboarding;
    if (ob == null) return null;
    final n = (ob['filled'] as num?)?.toInt() ?? 0, t = (ob['total'] as num?)?.toInt() ?? 0;
    return ChCard(
      gap: 10,
      children: [
        ChHead(
          lead: const ChIcon(AppIcons.user, tone: ChTone.purple),
          title: 'Onboarding',
          sub: '$n of $t filled · ${d.coachFirst} needs it to plan for you',
          action: hkPill('To finish', bg: AppColors.purpleBg, fg: AppColors.purpleText),
        ),
        ChBar(t == 0 ? 0 : n / t, color: AppColors.accent),
        CaButton(n > 0 ? 'Fill the remaining' : 'Start onboarding', icon: AppIcons.play, onPressed: () => context.go('/setup')),
      ],
    );
  }

  // ─────────────────────────────── Daily card

  Widget? _daily(CheckinsData d) {
    final f = d.daily.form;
    if (f == null) return null;
    final dd = d.daily;
    final now = DateTime.now();
    final realToday = DateTime(now.year, now.month, now.day);
    final day = DateTime(dd.date.year, dd.date.month, dd.date.day);
    final isToday = day == realToday;
    // Picked an older day on the strip: only its own sent row (the queued one is today's or yesterday's).
    final s = dd.sent ?? (dd.editable ? CheckinsController.queuedDaily : null);
    final name = isToday ? 'Today' : (dd.isYesterday ? 'Yesterday' : dayShortNoYear(day));
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
              ? (isToday || dd.isYesterday
                  ? '$name, ${dayShortNoYear(day).replaceFirst(',', '')}${dd.isYesterday ? ' · open until tonight' : ''}'
                  : name)
              : '$name · sent at ${s.sentAt == null ? '—' : clock(s.sentAt!)}',
          action: s == null
              ? (!dd.editable
                  ? hkPill('Missed', bg: AppColors.sub, fg: AppColors.muted)
                  : dd.isYesterday
                      ? hkPill('Still open', bg: AppColors.amberBg, fg: AppColors.amberText)
                      : hkPill('Due today', bg: AppColors.infoBg, fg: AppColors.infoText))
              : hkPill('Sent', bg: AppColors.okBg, fg: AppColors.okText),
        ),
        if (dd.strip.isNotEmpty) _dayStrip(dd, realToday),
        if (s == null && !dd.editable)
          Text('Not filled. Only today and yesterday can be filled, older days are view only.',
              style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.45))
        else if (s == null) ...[
          // Under the strip: the coach's description of the form, else one plain line (Probid 2026-11-04: no
          // auto text about the questions).
          f.description.isNotEmpty
              ? _desc(f.description)
              : Text(dd.isYesterday ? 'A quick look at how yesterday went.' : 'A quick look at how today went.',
                  style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.45)),
          CaButton(dd.isYesterday ? 'Fill yesterday\'s check-in' : 'Start daily check-in', icon: AppIcons.play, onPressed: () => context.go('/checkins/daily')),
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
              if (dd.editable)
                Expanded(
                  child: CaButton('Edit answers', kind: CaBtnKind.out, small: true, icon: AppIcons.edit, onPressed: () => context.go('/checkins/daily?edit=1')),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// Last week and this week, like the Food strip (E36): a tick for a sent day, today ringed, the picked one
  /// shaded. Days before the client started and future days can't be picked.
  Widget _dayStrip(CkDaily dd, DateTime today) {
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final days = dd.strip;
    final picked = DateTime(dd.date.year, dd.date.month, dd.date.day);
    return LayoutBuilder(builder: (_, b) {
      final w = b.maxWidth / 7;
      return SizedBox(
        height: 64,
        child: ListView.builder(
          controller: _dayCtl ??= ScrollController(initialScrollOffset: w * (days.length > 7 ? (today.weekday == 1 ? 5 : 7) : 0)),
          scrollDirection: Axis.horizontal,
          itemExtent: w,
          itemCount: days.length,
          itemBuilder: (_, i) {
            final x = days[i];
            final day = DateTime(x.date.year, x.date.month, x.date.day);
            final on = day == picked, real = day == today, future = day.isAfter(today);
            final off = future || x.beforeStart;
            final Widget mark = x.sent
                ? Container(
                    width: 16,
                    height: 16,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: AppColors.okSolid, shape: BoxShape.circle),
                    child: const AppIcon(AppIcons.check, size: 10, color: AppColors.white, stroke: 3),
                  )
                : real
                    ? Container(width: 16, height: 16, decoration: BoxDecoration(color: AppColors.white, shape: BoxShape.circle, border: Border.all(color: AppColors.accent, width: 2)))
                    : off
                        ? const DashedCircle(size: 16)
                        : Container(width: 16, height: 16, decoration: const BoxDecoration(color: AppColors.sub, shape: BoxShape.circle));
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Semantics(
                button: !off,
                selected: on,
                label: '${dayShortNoYear(day)}${x.sent ? ', sent' : ''}${real ? ', today' : ''}',
                child: Hover(
                  onTap: off || on ? null : () => c.pickDay(day),
                  builder: (_, h, _) => Container(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: on ? AppColors.accentSoft : (h && !off ? AppColors.outlineHover : null),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(spacing: 3, children: [
                      Text(real ? 'Today' : wd[day.weekday - 1], style: AppText.s(10.5, W.w6, color: on ? AppColors.sessText : AppColors.muted)),
                      Text('${day.day}', style: AppText.s(11.5, off ? W.w6 : W.w7, color: off ? AppColors.muted : (on ? AppColors.sessText : AppColors.text))),
                      mark,
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      );
    });
  }

  ScrollController? _dayCtl;

  /// The coach's description of the form, from the builder.
  Widget _desc(String t) => Text(t, style: AppText.s(13, W.w5, color: AppColors.text2, h: 1.45));

  /// About 5 seconds a question on the daily, 15 on the weekly.
  String _takes(int n, {int each = 5}) {
    final s = n * each;
    if (s <= 45) return '30 seconds';
    final m = (s / 60).round();
    return m <= 1 ? 'a minute' : '$m minutes';
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
          sub: s == null
              ? (!w.open
                  ? 'Opens ${w.due}'
                  : (w.late ? 'Was due ${w.due} · open until ${dayShort(w.closes)}' : 'Due today, ${clock(w.dueAt)} · open until ${dayShort(w.closes)}'))
              : sentSub(),
          action: s == null
              ? (!w.open
                  ? hkPill('Opens ${dayName(w.dueAt)}', bg: AppColors.sub, fg: AppColors.text2)
                  : hkPill(w.late ? 'Still open' : (dueToday ? 'Due today' : 'Open'), bg: AppColors.amberBg, fg: AppColors.amberText))
              : hkPill('Sent', bg: AppColors.okBg, fg: AppColors.okText),
        ),
        if (f.description.isNotEmpty) _desc(f.description),
        if (s == null) ...[
          // No question chips on the card (E28): only how long it takes.
          Text(
            '${f.questions.length} ${f.questions.length == 1 ? 'question' : 'questions'} · takes about ${_takes(f.questions.length, each: 15)}',
            style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.45),
          ),
          if (answered > 0)
            Row(
              spacing: 10,
              children: [
                Expanded(child: ChBar(answered / f.questions.length, color: AppColors.accent)),
                Text('Draft · $answered of ${f.questions.length} answered', style: AppText.s(12, W.w7, color: AppColors.muted)),
              ],
            ),
          // Only on its due day and the 2 days after (E23).
          CaButton(
            !w.open ? 'Opens ${dayName(w.dueAt)}' : (answered > 0 ? 'Continue check-in' : 'Start weekly check-in'),
            kind: answered > 0 ? CaBtnKind.pri : CaBtnKind.dark,
            icon: w.open ? AppIcons.play : AppIcons.lock,
            dimmed: !w.open,
            onPressed: !w.open
                ? () => showToast(context, 'Not open yet', sub: 'Your weekly check-in opens ${w.due}', kind: ToastKind.info)
                : () => context.go('/checkins/weekly'),
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

  // ─────────────────────────────── Forms the coach sent (D-49)

  List<Widget> _forms(CheckinsData d) => [for (final f in d.forms) _form(f)];

  Widget _form(CkSentForm f) {
    final now = DateTime.now();
    String when(DateTime t) => DateUtils.isSameDay(t, now) ? 'today, ${clock(t)}' : dayShort(t);
    final answered = c.formDrafts[f.id] ?? 0;
    void open() => context.go('/checkins/forms/${f.id}');
    if (f.filled) {
      return Hover(
        onTap: open,
        builder: (_, _, _) => ChCard(
          gap: 10,
          children: [
            ChHead(
              lead: const ChIcon(AppIcons.check, tone: ChTone.green),
              title: f.name,
              sub: 'From ${f.from} · you sent it ${when(f.filledAt!)}',
              action: hkPill('Sent', bg: AppColors.okBg, fg: AppColors.okText),
            ),
          ],
        ),
      );
    }
    return ChCard(
      gap: 10,
      children: [
        ChHead(
          lead: const ChIcon(AppIcons.check, tone: ChTone.purple),
          title: f.name,
          sub: [
            'From ${f.from}',
            if (f.sentAt != null) 'sent ${when(f.sentAt!)}',
            if (f.dueAt != null) 'due ${dayShort(f.dueAt!)}',
          ].join(' · '),
          action: hkPill('To fill', bg: AppColors.infoBg, fg: AppColors.infoText),
        ),
        if (f.why.isNotEmpty) Text(f.why, style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.45)),
        if (f.chips.isNotEmpty) Wrap(spacing: 5, runSpacing: 5, children: [for (final t in f.chips) _chip(t)]),
        if (answered > 0 && f.count > 0)
          Row(
            spacing: 10,
            children: [
              Expanded(child: ChBar(answered / f.count, color: AppColors.accent)),
              Text('Draft · $answered of ${f.count} answered', style: AppText.s(12, W.w7, color: AppColors.muted)),
            ],
          ),
        CaButton(answered > 0 ? 'Continue form' : 'Fill in form', kind: answered > 0 ? CaBtnKind.pri : CaBtnKind.dark, onPressed: open),
      ],
    );
  }

  Widget _chip(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
    decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(6)),
    child: Text(t, style: AppText.s(11.5, W.w7, color: AppColors.text2)),
  );

  // ─────────────────────────────── Past check-ins

  /// No cue when the list is at its end, or every row is loaded and fits without scrolling.
  bool get _scrollEnd {
    if (_list.hasClients && _list.position.hasContentDimensions) return _list.position.maxScrollExtent <= 0 || _atEnd && !c.hasMore;
    return !c.hasMore && c.rows.length >= c.total && c.rows.length <= 5;
  }

  Widget _history(CheckinsData d) {
    // The list's size is known only after layout: check the cue again once this frame is drawn.
    final shownEnd = _scrollEnd;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollEnd != shownEnd) setState(() {});
    });
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
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                    Text('Past check-ins', style: AppText.s(15, W.w8)),
                    // Count of the whole list, so it is clear how many there are before scrolling (Gautam 2026-10-16).
                    if (c.total > 0)
                      Text(
                        '${c.total} ${c.total == 1 ? 'check-in' : 'check-ins'} · ${c.totalSent} sent'
                        '${c.totalMissed == 0 ? '' : ' · ${c.totalMissed} missed'}',
                        style: AppText.s(12, W.w4, color: AppColors.muted),
                      ),
                  ]),
                ),
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
              child: Stack(children: [
                // No scrollbar (E24): the fade and "Scroll for older" show there is more.
                ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
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
                // Fade at the bottom while more rows are below: the list scrolls.
                if (!_scrollEnd)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 36,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.white.withValues(alpha: 0), AppColors.white]),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          if (rows.isNotEmpty && !_scrollEnd)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 4, children: [
                const AppIcon(AppIcons.chevronDown, size: 13, color: AppColors.muted),
                Text(rows.length < c.total ? 'Scroll for older · ${rows.length} of ${c.total} shown' : 'Scroll for more', style: AppText.s(12, W.w6, color: AppColors.muted)),
              ]),
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
                  CutText(
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
    if (id != null && !widget.row.missed) {
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
      String? lab(String m) => f?.byMetric(m)?.show(r.metrics[m], short: true);
      // Only the numbers this day has (the coach may not ask sleep or energy).
      final cells = [
        if (r.metrics['sleep_hours'] is num) (hrs(r.metrics['sleep_hours'] as num), 'Sleep'),
        if (lab('energy') != null) (lab('energy')!, 'Energy'),
        if (lab('mood') != null) (lab('mood')!, 'Mood'),
        if (r.steps != null) (r.stepsText, 'Steps'),
      ];
      if (cells.length >= 2) kids.add(HkCells(cells));
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
    // Every answer, in the coach's own words, label left and answer right (E24).
    final qa = <(String, String)>[];
    if (!r.missed) {
      final ans = (_detail?['answers'] as List? ?? []).cast<Map<String, dynamic>>();
      final f = widget.weekly ? d.weekly.form : d.daily.form;
      for (final a in ans) {
        final qid = (a['question'] as num?)?.toInt();
        final q0 = f?.questions.where((x) => x.id == qid).firstOrNull;
        if (qid == null || a['photo'] != null && '${a['photo']}'.isNotEmpty || q0?.type == 'photo' || a['question_type'] == 'photo') continue;
        final q = q0 ?? CkQ({'id': qid, 'text': a['question_text'], 'type': a['question_type'], 'metric': a['metric']});
        qa.add((q.text, q.show(a['value']) ?? '—'));
      }
      final note = '${r.metrics['note'] ?? ''}';
      if (note.isNotEmpty) qa.add(('Note', note));
      if (_detail == null && r.id != null) {
        kids.add(
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
            ),
          ),
        );
      }
    }
    if (qa.isNotEmpty) {
      kids.addAll([
        hkSec('Your answers'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, (q, a)) in qa.indexed)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 12,
                    children: [
                      Expanded(flex: 5, child: Text(q, style: AppText.s(12.5, W.w6, color: AppColors.muted, h: 1.35))),
                      Expanded(flex: 6, child: Text(a, textAlign: TextAlign.right, style: AppText.s(13.5, W.w7, h: 1.35))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ]);
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
