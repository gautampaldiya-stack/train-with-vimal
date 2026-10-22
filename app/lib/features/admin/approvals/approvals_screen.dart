import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../app/shell/page.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/pager.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tabs.dart';
import '../../../core/widgets/tooltip.dart';
import '../clients/admin_client_drawers.dart';
import '../clients/invite_links_modal.dart';
import 'approvals_model.dart';
import 'approvals_parts.dart';

/// Approvals (boards `Approvals` + `ApprovalsMobile`, D-47). Waiting: people who signed up from an invite link,
/// oldest first; Review opens the drawer (approve and assign a trainer, reject, ask for info). History: every
/// decision, with Move back for a mistake. Web: table. Phone: one line per person with a Review button.
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key, this.tab});
  final String? tab;
  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  final c = ApprovalsController();
  final q = TextEditingController();
  final _hScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.tab == 'history') c.tab = 'history';
    c.load();
    c.loadStaff();
  }

  @override
  void dispose() {
    c.dispose();
    q.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  bool get _hist => c.tab == 'history';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final phone = context.isPhone;
          final n = c.counts;
          final w = n['waiting'] ?? 0;
          return StaffPage(
            onRefresh: c.load,
            header: PageTop(
              title: 'Approvals',
              sub: n.isEmpty
                  ? ' '
                  : [
                      w == 0 ? 'No one waiting' : '$w ${w == 1 ? 'person' : 'people'} waiting',
                      if (c.oldest.isNotEmpty) 'oldest waiting ${c.oldest}',
                      'new sign-ups from invite links land here',
                    ].join(' · '),
              actions: compactTop(context)
                  ? [
                      AppIconButton(AppIcons.link, tooltip: 'Invite link', onPressed: () => showInviteLinksModal(context)),
                      AppButton.primary('Add client', icon: AppIcons.plus, iconOnly: true, onPressed: _add),
                    ]
                  : [
                      AppButton('Invite link', icon: AppIcons.link, onPressed: () => showInviteLinksModal(context)),
                      AppButton.primary('Add client', icon: AppIcons.plus, onPressed: _add),
                    ],
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedTabs<String>(
                  items: [TabItem('waiting', 'Waiting', count: n['waiting']), TabItem('history', 'History', count: n['history'])],
                  value: c.tab,
                  onChanged: (t) {
                    q.clear();
                    c.search = '';
                    c.setTab(t);
                  },
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _tools(phone),
                    if (c.chips.isNotEmpty) _chips(),
                    if (c.error != null && c.rows.isEmpty)
                      EmptyState('Could not load approvals', sub: c.error!.message, action: AppButton('Try again', onPressed: c.load))
                    else if (!c.loading && c.rows.isEmpty)
                      _none()
                    else if (c.rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))),
                      )
                    else
                      phone ? _list() : _table(),
                    _foot(),
                  ]),
                ),
                Pager(page: c.page, pageSize: ApprovalsController.pageSize, count: c.count, onPage: c.goPage, empty: _hist ? 'No decisions' : 'No one waiting'),
              ]),
            ],
          );
        },
      );

  // ─────────────────────────────── Tools: search, Filter, chips

  Widget _tools(bool phone) {
    final nf = c.activeFilters;
    final search = AppSearchField(
      controller: q,
      placeholder: _hist ? 'Search history' : 'Search name, phone or email',
      icon: AppIcons.search,
      onChanged: c.setSearch,
    );
    return Padding(
      padding: phone ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(spacing: 8, children: [
        Expanded(
          child: phone ? search : Align(alignment: Alignment.centerLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 320), child: search)),
        ),
        Builder(
          builder: (b) => phone
              ? AppIconButton(AppIcons.filter, tooltip: nf > 0 ? 'Filter · $nf' : 'Filter', dot: nf > 0, onPressed: () => _filter(b))
              : AppButton(nf > 0 ? 'Filter · $nf' : 'Filter', icon: AppIcons.filter, onPressed: () => _filter(b)),
        ),
      ]),
    );
  }

  /// `.fm-menu`: one row per group with its current pick; options open beside it.
  void _filter(BuildContext anchor) => showFilterMenu(
        anchor,
        [
          for (final g in c.groups)
            MenuGroup(
              g.label,
              value: g.options.firstWhere((o) => o.$1 == (c.filters[g.key] ?? ''), orElse: () => g.options.first).$2,
              options: [for (final (v, l) in g.options) MenuEntry(l, selected: (c.filters[g.key] ?? '') == v, onTap: () => c.setFilter(g.key, v))],
            ),
        ],
        onClear: c.activeFilters > 0 ? c.clearFilters : null,
      );

  /// `.ap-fchips`: one chip per filter set (tap × to drop it) and Clear. One line, scrolls sideways.
  Widget _chips() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(spacing: 6, children: [
            for (final (k, t) in c.chips) _Chip(t, onRemove: () => c.setFilter(k, '')),
            AppButton('Clear', kind: BtnKind.text, size: BtnSize.sm, onPressed: c.clearFilters),
          ]),
        ),
      );

  Widget _none() {
    final filtered = c.activeFilters > 0 || c.search.isNotEmpty;
    if (!filtered) {
      return _hist
          ? const EmptyState('No decisions yet', sub: 'People you approve or reject show up here.')
          : const EmptyState('No one is waiting', sub: 'New sign-ups from invite links land here.');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
        Text(_hist ? 'Nothing matches these filters.' : 'No one matches these filters.', style: AppText.s(13, W.w5, color: AppColors.muted)),
        AppButton('Clear filters', kind: BtnKind.text, size: BtnSize.sm, onPressed: () {
          q.clear();
          c.search = '';
          c.clearFilters();
        }),
      ]),
    );
  }

  /// `.ap-foot`.
  Widget _foot() {
    final total = _hist ? (c.counts['history'] ?? 0) : (c.counts['waiting'] ?? 0);
    final showing = c.activeFilters > 0 || c.search.isNotEmpty ? 'Showing ${c.count} of $total. ' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      child: Text(
        _hist
            ? 'Rejected people cannot log in. Rejected by mistake? Move them back to Waiting. To stop an approved client, pause them from Clients.'
            : '${showing}Sorted oldest first. Amber after 1 day, red after 2 days.',
        style: AppText.s(12, W.w5, color: AppColors.muted, h: 1.45),
      ),
    );
  }

  // ─────────────────────────────── Actions

  Future<void> _add() async {
    final r = await showAddClientDrawer(context);
    if (r == null || !mounted) return;
    c.load();
    final first = '${r['full_name']}'.split(' ').first;
    final pending = r['status'] == 'pending';
    showToast(context, pending ? '$first is in Approvals' : '$first is added',
        sub: pending ? 'Review them here to let them log in' : 'Open their profile to plan what is next',
        kind: ToastKind.ok,
        action: pending ? null : 'View',
        onAction: pending ? null : () => context.go('/clients/${r['id']}'));
  }

  /// Review drawer; Previous / Next step through this page's people (round the end).
  Future<void> _review(int i) async {
    var idx = i;
    while (mounted && c.rows.isNotEmpty) {
      final r = c.rows[idx.clamp(0, c.rows.length - 1)];
      final out = await showReviewDrawer(context, r, canStep: c.rows.length > 1);
      if (!mounted) return;
      final len = c.rows.length;
      switch (out) {
        case ApOutcome.prev:
          idx = (idx - 1 + len) % len;
          continue;
        case ApOutcome.next:
          idx = (idx + 1) % len;
          continue;
        case ApOutcome.approved:
          c.load();
          showToast(context, '${r.first} is approved', sub: '${pronoun(r.gender, cap: true)} can log in now', kind: ToastKind.ok,
              action: 'View', onAction: () => context.go('/clients/${r.client['id']}'));
        case ApOutcome.rejected:
          c.load();
          showToast(context, '${r.first} is rejected', sub: 'Find ${objective(r.gender)} in History', action: 'Undo', onAction: () async {
            await Services.api.post('approvals/${r.id}/move-back/', {});
            c.load();
          });
        case ApOutcome.asked:
          c.load();
          showToast(context, 'Request sent to ${r.first}', sub: '${pronoun(r.gender, cap: true)} ${verb(r.gender, 'stays')} in Waiting', kind: ToastKind.ok);
        case null:
          break;
      }
      return;
    }
  }

  Future<void> _moveBack(ApRow r) async {
    if (!await showMoveBackModal(context, r) || !mounted) return;
    c.load();
    showToast(context, '${r.first} is back in Waiting', kind: ToastKind.ok, action: 'Open', onAction: () {
      q.clear();
      c.search = '';
      c.setTab('waiting');
    });
  }

  // ─────────────────────────────── Web tables (`.tbl.dt.ap-t`)

  static const _waitCols = <(String, double, bool)>[
    // label, width, right aligned (Person takes what is left). As on the board, it scrolls sideways when narrower.
    ('Person', 196, false),
    ('Mobile', 134, false),
    ('Invited by', 136, false),
    ('Signed up from', 132, false),
    ('Profile setup', 138, false),
    ('Health', 124, false),
    ('Waiting', 80, true),
    ('', 108, true),
  ];

  static const _histCols = <(String, double, bool)>[
    ('Person', 240, false),
    ('Decision', 112, false),
    ('Trainer or reason', 220, false),
    ('Decided by', 140, false),
    ('When', 110, true),
    ('', 60, true),
  ];

  Widget _table() => LayoutBuilder(builder: (context, box) {
        final cols = _hist ? _histCols : _waitCols;
        final min = cols.fold<double>(0, (a, x) => a + x.$2);
        final extra = (box.maxWidth - min).clamp(0.0, double.infinity);
        final widths = [for (final (i, x) in cols.indexed) x.$2 + (i == 0 ? extra : 0)];
        final table = SizedBox(
          width: min + extra,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 34,
              decoration: const BoxDecoration(
                color: AppColors.tableHeadDt,
                border: Border.symmetric(horizontal: BorderSide(color: AppColors.line)),
              ),
              child: Row(children: [
                for (final (i, x) in cols.indexed)
                  Container(
                    width: widths[i],
                    padding: EdgeInsets.fromLTRB(i == 0 ? 16 : 12, 0, 12, 0),
                    alignment: x.$3 ? Alignment.centerRight : Alignment.centerLeft,
                    child: Text(x.$1.toUpperCase(), maxLines: 1, style: AppText.s(11.5, W.w7, color: AppColors.muted, ls: .58)),
                  ),
              ]),
            ),
            for (final (i, r) in c.rows.indexed)
              _hist ? _histRow(r, widths, i == c.rows.length - 1) : _waitRow(i, r, widths, i == c.rows.length - 1),
          ]),
        );
        if (box.maxWidth >= min) return table;
        return Scrollbar(
          controller: _hScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(controller: _hScroll, scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(bottom: 8), child: table),
        );
      });

  Widget _cell(List<double> widths, int i, Widget child, {bool right = false}) => Container(
        width: widths[i],
        padding: EdgeInsets.fromLTRB(i == 0 ? 16 : 12, 0, 12, 0),
        alignment: right ? Alignment.centerRight : Alignment.centerLeft,
        child: child,
      );

  Widget _who(ApRow r, String sub) => Row(spacing: 10, children: [
        apAvatar(r.client),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(spacing: 6, children: [
              Flexible(child: CutText(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7))),
              if (r.movedBack && !_hist) const AppBadge('Moved back', tone: Tone.info, plain: true),
            ]),
            CutText(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted)),
          ]),
        ),
      ]);

  Widget _inviter(ApRow r, {double size = 22, double font = 13}) => r.invitedBy == null
      ? Text('—', style: AppText.s(font, W.w5, color: AppColors.muted))
      : Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
          apAvatar(r.invitedBy, size: size),
          Flexible(child: CutText('${r.invitedBy!['full_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(font, W.w5))),
        ]);

  Widget _health(ApRow r) => r.healthNote ? const AppBadge('Health note', tone: Tone.warn, plain: true) : Text('None', style: AppText.s(13, W.w5, color: AppColors.muted));

  Widget _waitRow(int i, ApRow r, List<double> widths, bool last) => Hover(
        onTap: () => _review(i),
        builder: (_, h, _) => Container(
          height: 49,
          decoration: BoxDecoration(
            color: h ? AppColors.hover : null,
            border: last ? null : const Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(children: [
            _cell(widths, 0, _who(r, r.email.isEmpty ? '—' : r.email)),
            _cell(widths, 1, Text(r.phone, maxLines: 1, softWrap: false, style: AppText.s(13, W.w5, color: AppColors.text2))),
            _cell(widths, 2, _inviter(r)),
            _cell(widths, 3, CutText(r.from.isEmpty ? '—' : r.from, maxLines: 1, style: AppText.s(13, W.w5, color: AppColors.text2))),
            _cell(widths, 4, Row(spacing: 8, children: [apPips(r.setupDone), Flexible(child: Text('${r.setupDone} of 5', maxLines: 1, softWrap: false, style: AppText.s(12.5, W.w5, color: AppColors.muted)))])),
            _cell(widths, 5, _health(r)),
            _cell(widths, 6, apWait(r), right: true),
            _cell(widths, 7, AppButton('Review', size: BtnSize.sm, onPressed: () => _review(i)), right: true),
          ]),
        ),
      );

  Widget _histRow(ApRow r, List<double> widths, bool last) => Hover(
        builder: (_, h, _) => Container(
          height: 49,
          decoration: BoxDecoration(
            color: h ? AppColors.hover : null,
            border: last ? null : const Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(children: [
            _cell(widths, 0, _who(r, r.signedUp)),
            _cell(widths, 1, AppBadge(r.decision, tone: r.status == 'approved' ? Tone.ok : Tone.bad)),
            _cell(widths, 2, CutText(r.why.isEmpty ? '—' : r.why, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w5, color: AppColors.text2))),
            _cell(widths, 3, CutText('${r.decidedBy?['full_name'] ?? '—'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w4))),
            _cell(widths, 4, Text(r.decided == null ? '—' : apDay(r.decided!), maxLines: 1, softWrap: false, style: AppText.s(13, W.w5, color: AppColors.text2)), right: true),
            _cell(widths, 5, _backBtn(r), right: true),
          ]),
        ),
      );

  Widget _backBtn(ApRow r) => r.status == 'rejected'
      ? AppIconButton(AppIcons.undo, tooltip: 'Move back to Waiting', small: true, ghost: true, onPressed: () => _moveBack(r))
      : const SizedBox(width: 30);

  // ─────────────────────────────── Phone list (`ApprovalsMobile`)

  Widget _list() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, r) in c.rows.indexed)
          Hover(
            onTap: _hist ? null : () => _review(i),
            builder: (_, h, _) => Container(
              padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
              decoration: BoxDecoration(
                color: h && !_hist ? AppColors.hover : null,
                border: Border(top: const BorderSide(color: AppColors.line)),
              ),
              child: Row(spacing: 10, children: [
                apAvatar(r.client),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
                    Row(spacing: 6, children: [
                      Flexible(child: CutText(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(14, W.w7))),
                      if (r.movedBack && !_hist) const AppBadge('Moved back', tone: Tone.info, plain: true),
                    ]),
                    _hist ? _histSub(r) : _waitSub(r),
                  ]),
                ),
                if (_hist) _backBtn(r) else AppButton('Review', size: BtnSize.sm, onPressed: () => _review(i)),
              ]),
            ),
          ),
      ]);

  /// "(V) Vimal · 2 days  [Health note]".
  Widget _waitSub(ApRow r) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(spacing: 6, children: [
          if (r.invitedBy != null) ...[
            apAvatar(r.invitedBy, size: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: CutText('${r.invitedBy!['full_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
            ),
            Text('·', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
          ],
          apWait(r),
          if (r.healthNote) const AppBadge('Health note', tone: Tone.warn, plain: true),
        ]),
      );

  /// "[Rejected] Already has an account · Tue, 6 Oct".
  Widget _histSub(ApRow r) => Row(spacing: 6, children: [
        AppBadge(r.decision, tone: r.status == 'approved' ? Tone.ok : Tone.bad),
        Flexible(
          child: CutText([if (r.why.isNotEmpty) r.why, if (r.decided != null) apDay(r.decided!)].join(' · '),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
        ),
      ]);
}

/// `.fchip.on` with ×: a filter that is set.
class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => AppTooltip(
        message: 'Remove this filter',
        child: Hover(
          onTap: onRemove,
          builder: (_, h, _) => Container(
            height: 28,
            padding: const EdgeInsets.only(left: 10, right: 8),
            decoration: BoxDecoration(
              color: h ? AppColors.text2 : AppColors.text,
              borderRadius: AppRadius.all(AppRadius.chip),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              Text(label, style: AppText.s(12.5, W.w6, color: AppColors.white)),
              const AppIcon(AppIcons.close, size: 12, color: AppColors.white),
            ]),
          ),
        ),
      );
}
