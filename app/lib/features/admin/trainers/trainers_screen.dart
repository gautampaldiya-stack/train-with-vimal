import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../app/shell/page.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/avatar.dart';
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
import '../../trainer/me/me_edit.dart';
import '../../trainer/me/me_model.dart';
import 'trainer_drawers.dart';
import 'trainers_model.dart';

/// Admin → Trainers (boards `Trainers` + `TrainersMobile`, D-48): the team with their load, check-ins to review,
/// adherence, access and status. Web: table; phone: one line per trainer with status and load. Row ⋯: Open
/// profile, Access and permissions, Edit details, Move clients to another trainer, Deactivate / Reactivate.
class TrainersScreen extends StatefulWidget {
  const TrainersScreen({super.key, this.openAdd = false});
  final bool openAdd;
  @override
  State<TrainersScreen> createState() => _TrainersScreenState();
}

class _TrainersScreenState extends State<TrainersScreen> {
  final c = TrainersController();
  final q = TextEditingController();
  final _hScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    c.load();
    if (widget.openAdd) WidgetsBinding.instance.addPostFrameCallback((_) => _add());
  }

  @override
  void dispose() {
    c.dispose();
    q.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final phone = context.isPhone;
          final n = c.counts;
          return StaffPage(
            onRefresh: c.load,
            header: PageTop(
              title: 'Trainers',
              sub: c.summary.isEmpty ? ' ' : '${n['all'] ?? 0} in the team · ${n['active'] ?? 0} active · ${c.summary['clients'] ?? 0} clients',
              actions: [AppButton.primary('Add trainer', icon: AppIcons.plus, iconOnly: compactTop(context), tooltip: 'Add trainer', onPressed: _add)],
            ),
            children: [
              if (c.summary.isNotEmpty) phone ? _strip() : _stats(),
              Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedTabs<String>(
                    items: [
                      for (final (k, l) in const [('all', 'All'), ('active', 'Active'), ('full', 'Full'), ('inactive', 'Inactive')]) TabItem(k, l, count: n[k]),
                    ],
                    value: c.tab,
                    onChanged: c.setTab,
                  ),
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _tools(phone),
                    if (c.chips.isNotEmpty) _chips(),
                    if (c.error != null && c.rows.isEmpty)
                      EmptyState('Could not load trainers', sub: c.error!.message, action: AppButton('Try again', onPressed: c.load))
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
                Pager(page: c.page, pageSize: TrainersController.pageSize, count: c.count, onPage: c.goPage, empty: 'No trainers'),
              ]),
            ],
          );
        },
      );

  // ─────────────────────────────── Stats

  /// (icon, label, value, note, note colour)
  List<(AppIconData, String, String, String, Color)> get _statRows {
    final s = c.summary;
    final n = c.counts;
    final spots = (s['spots'] as Map?) ?? const {};
    final ci = (s['checkins_to_review'] as Map?) ?? const {};
    final most = ci['most'] as Map?;
    final adh = s['adherence'] as num?, ch = s['adherence_change'] as num?;
    return [
      (AppIcons.team, 'Active trainers', '${n['active'] ?? 0}', '${n['inactive'] ?? 0} inactive', AppColors.text),
      (AppIcons.spots, 'Client spots', '${spots['used'] ?? 0} / ${spots['total'] ?? 0}', '${spots['free'] ?? 0} spots free', AppColors.text),
      (AppIcons.clipboardShort, 'Check-ins to review', '${ci['total'] ?? 0}', most == null ? 'All reviewed' : '${most['name']} has the most (${most['n']})', AppColors.text),
      (
        AppIcons.pulse,
        'Avg adherence',
        adh == null ? '—' : '$adh%',
        ch == null ? '' : (ch == 0 ? 'Same as last week' : '${ch > 0 ? '+' : '−'}${ch.abs()}% vs last week'),
        ch == null || ch == 0 ? AppColors.muted : (ch > 0 ? AppColors.okText : AppColors.badText),
      ),
    ];
  }

  /// `.stats`: content-wide cards on one line that scroll sideways when the page is narrow.
  Widget _stats() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(spacing: 10, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (icon, label, value, note, color) in _statRows)
            Container(
              constraints: const BoxConstraints(minHeight: 80),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: AppColors.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
                  IconTile(icon, radius: 8),
                  Text(label, style: AppText.s(12.5, W.w6, color: AppColors.muted)),
                ]),
                Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 10, children: [
                  Text(value, style: AppText.stat),
                  if (note.isNotEmpty) Text(note, style: AppText.s(12, W.w7, color: color)),
                ]),
              ]),
            ),
        ]),
      );

  /// Phone: one white strip of 4 cells (number over label).
  Widget _strip() => Container(
        decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(12), border: Border.all(color: AppColors.line)),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, s) in _statRows.indexed)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 9),
                  decoration: BoxDecoration(border: i == 0 ? null : const Border(left: BorderSide(color: AppColors.line))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                    CutText(s.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(16, W.w8, h: 1.2, tabular: true)),
                    CutText(s.$2, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(10.5, W.w6, color: AppColors.muted, h: 1.25)),
                  ]),
                ),
              ),
          ]),
        ),
      );

  // ─────────────────────────────── Tools: search, Filter, chips

  Widget _tools(bool phone) {
    final nf = c.activeFilters;
    final search = AppSearchField(controller: q, placeholder: 'Search name, phone or email', icon: AppIcons.search, onChanged: c.setSearch);
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

  void _filter(BuildContext anchor) => showFilterMenu(
        anchor,
        [
          for (final g in TrainersController.groups)
            MenuGroup(
              g.label,
              value: g.options.firstWhere((o) => o.$1 == (c.filters[g.key] ?? ''), orElse: () => g.options.first).$2,
              options: [for (final (v, l) in g.options) MenuEntry(l, selected: (c.filters[g.key] ?? '') == v, onTap: () => c.setFilter(g.key, v))],
            ),
        ],
        onClear: c.activeFilters > 0 ? c.clearFilters : null,
      );

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
    if (!c.filtered) {
      return EmptyState(c.tab == 'all' ? 'No trainers yet' : 'No trainers here',
          sub: c.tab == 'all' ? 'Add your first trainer to share the clients.' : null,
          action: c.tab == 'all' ? AppButton.primary('Add trainer', icon: AppIcons.plus, onPressed: _add) : null);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
        Text('No trainers match.', style: AppText.s(13, W.w5, color: AppColors.muted)),
        AppButton('Clear filters', kind: BtnKind.text, size: BtnSize.sm, onPressed: () {
          q.clear();
          c.search = '';
          c.clearFilters();
        }),
      ]),
    );
  }

  /// `.ap-foot`: "Showing 3 of 8. Adherence is the share of planned workouts and meals done in the last 7 days."
  Widget _foot() {
    final total = c.counts['all'] ?? 0;
    final showing = c.count < total && !c.loading ? 'Showing ${c.count} of $total. ' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      child: Text('${showing}Adherence is the share of planned workouts and meals done in the last 7 days.', style: AppText.s(12, W.w5, color: AppColors.muted, h: 1.45)),
    );
  }

  // ─────────────────────────────── Actions

  Future<void> _add() async {
    final r = await showAddTrainerDrawer(context);
    if (r == null || !mounted) return;
    final (t, give) = r;
    c.load();
    final first = '${t['full_name']}'.split(' ').first;
    if (give) {
      context.go('/trainers/${t['id']}?tab=clients&assign=1');
      return;
    }
    showToast(context, '$first is added', sub: 'Open their profile to give them clients', kind: ToastKind.ok, action: 'View', onAction: () => context.go('/trainers/${t['id']}'));
  }

  Future<void> _edit(TrRow r) async {
    final m = MeController(id: r.id);
    await m.load();
    if (!mounted) {
      m.dispose();
      return;
    }
    if (m.me.isEmpty) {
      showToast(context, 'Could not open ${r.first}', sub: m.error?.message, kind: ToastKind.err);
      m.dispose();
      return;
    }
    final saved = await showEditMyDetails(context, m);
    m.dispose();
    if (saved) c.load();
  }

  Future<void> _move(TrRow r) async {
    final n = await showMoveTrainerClients(context, id: r.id, name: r.name, clients: r.n);
    if (n == null || !mounted) return;
    c.load();
    showToast(context, '$n ${n == 1 ? 'client' : 'clients'} moved', sub: 'From ${r.name}', kind: ToastKind.ok);
  }

  Future<void> _deactivate(TrRow r) async {
    if (!await showDeactivateTrainer(context, id: r.id, name: r.name) || !mounted) return;
    c.load();
    showToast(context, '${r.first} is deactivated', sub: 'Find them in the Inactive tab', action: 'Undo', onAction: () => _reactivate(r, quiet: true));
  }

  Future<void> _reactivate(TrRow r, {bool quiet = false}) async {
    try {
      await Services.api.post('trainers/${r.id}/reactivate/', {});
      c.load();
      if (mounted && !quiet) showToast(context, '${r.first} is active again', sub: 'They can log in now', kind: ToastKind.ok);
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not reactivate ${r.first}', sub: e.message, kind: ToastKind.err);
    }
  }

  void _menu(BuildContext anchor, TrRow r) => showAppMenu(anchor, width: 260, [
        MenuEntry('Open profile', icon: AppIcons.open, onTap: () => context.go('/trainers/${r.id}')),
        if (!r.owner) ...[
          MenuEntry('Access and permissions', icon: AppIcons.access, onTap: () => context.go('/trainers/${r.id}?tab=access')),
          MenuEntry('Edit details', icon: AppIcons.editAlt, onTap: () => _edit(r)),
          MenuEntry('Move clients to another trainer', icon: AppIcons.swapBoth, onTap: () => _move(r)),
          const MenuEntry.separator(),
          if (r.active)
            MenuEntry('Deactivate', icon: AppIcons.deactivate, danger: true, onTap: () => _deactivate(r))
          else
            MenuEntry('Reactivate', icon: AppIcons.power, onTap: () => _reactivate(r)),
        ],
      ]);

  // ─────────────────────────────── Web table (`.tbl.dt.tr-t`)

  static const _cols = <(String, double, bool)>[
    // label, width, right aligned (Trainer takes what is left). Scrolls sideways when narrower.
    ('Trainer', 220, false),
    ('Clients', 190, false),
    ('Check-ins to review', 172, true),
    ('Adherence', 100, true),
    ('Access', 150, false),
    ('Status', 100, false),
    ('Joined', 110, false),
    ('', 56, true),
  ];

  Widget _table() => LayoutBuilder(builder: (context, box) {
        final min = _cols.fold<double>(0, (a, x) => a + x.$2);
        final extra = (box.maxWidth - min).clamp(0.0, double.infinity);
        // The room left goes to Trainer and Clients.
        final widths = [for (final (i, x) in _cols.indexed) x.$2 + (i == 0 ? extra * .55 : (i == 1 ? extra * .45 : 0))];
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
                for (final (i, x) in _cols.indexed)
                  Container(
                    width: widths[i],
                    padding: EdgeInsets.fromLTRB(i == 0 ? 16 : 12, 0, i == _cols.length - 1 ? 16 : 12, 0),
                    alignment: x.$3 ? Alignment.centerRight : Alignment.centerLeft,
                    child: Text(x.$1.toUpperCase(), maxLines: 1, style: AppText.s(11.5, W.w7, color: AppColors.muted, ls: .58)),
                  ),
              ]),
            ),
            for (final (i, r) in c.rows.indexed) _row(r, widths, i == c.rows.length - 1),
          ]),
        );
        if (box.maxWidth >= min) return table;
        return Scrollbar(
          controller: _hScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(controller: _hScroll, scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(bottom: 8), child: table),
        );
      });

  Widget _cell(List<double> widths, int i, Widget child, {bool right = false, bool dim = false}) => Container(
        width: widths[i],
        padding: EdgeInsets.fromLTRB(i == 0 ? 16 : 12, 0, i == _cols.length - 1 ? 16 : 12, 0),
        alignment: right ? Alignment.centerRight : Alignment.centerLeft,
        child: dim ? Opacity(opacity: .55, child: child) : child,
      );

  Widget _avatar(TrRow r, {double size = 30}) => AppAvatar(r.name, size: size, url: r.avatar, colors: AppColors.avatarCode(r.color), initials: r.initials);

  Widget _who(TrRow r) => Row(spacing: 10, children: [
        _avatar(r),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(spacing: 6, children: [
              Flexible(child: CutText(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w7))),
              if (r.isMe) const AppBadge('You', plain: true),
            ]),
            CutText(r.spec.isEmpty ? '—' : r.spec, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted)),
          ]),
        ),
      ]);

  /// `.tr-load`: bar (blue, amber at 80%, red when full), "24 / 30" and a Full badge.
  Widget _load(TrRow r, {double bar = 72}) => Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
        ProgressBar(value: r.load, width: bar, height: 5, color: !r.active ? AppColors.drLoad : (r.full ? AppColors.trLoadFull : (r.high ? AppColors.trLoadHi : AppColors.accent))),
        Text.rich(
          TextSpan(children: [TextSpan(text: '${r.n}', style: AppText.s(12.5, W.w7, color: AppColors.text)), TextSpan(text: ' / ${r.max}')]),
          maxLines: 1,
          softWrap: false,
          style: AppText.s(12.5, W.w5, color: AppColors.muted, tabular: true),
        ),
        if (r.full) const AppBadge('Full', tone: Tone.warn, plain: true),
      ]);

  Widget _status(TrRow r) => AppBadge(r.active ? 'Active' : 'Inactive', tone: r.active ? Tone.ok : Tone.neutral);

  Widget _dots(TrRow r) => Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'More actions', small: true, onPressed: () => _menu(b, r)));

  Widget _row(TrRow r, List<double> widths, bool last) {
    final off = !r.active;
    final ci = !r.active ? '—' : '${r.review}';
    final adh = !r.active || r.n == 0 || r.adherence == null ? '—' : '${r.adherence}%';
    TextStyle num(bool warn, bool zero) => AppText.s(13, zero ? W.w5 : W.w7, color: zero ? AppColors.muted : (warn ? AppColors.trWarn : AppColors.text), tabular: true);
    return Hover(
      onTap: () => context.go('/trainers/${r.id}'),
      builder: (_, h, _) => Container(
        height: 49,
        decoration: BoxDecoration(
          color: h ? AppColors.hover : null,
          border: last ? null : const Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(children: [
          _cell(widths, 0, _who(r), dim: off),
          _cell(widths, 1, _load(r), dim: off),
          _cell(widths, 2, Text(ci, style: num(r.review >= 3, !r.active || r.review == 0)), right: true, dim: off),
          _cell(widths, 3, Text(adh, style: num((r.adherence ?? 100) < 80, adh == '—')), right: true, dim: off),
          _cell(widths, 4, CutText(r.access, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w5, color: AppColors.text2)), dim: off),
          _cell(widths, 5, _status(r), dim: off),
          _cell(widths, 6, Text(r.joined, maxLines: 1, softWrap: false, style: AppText.s(13, W.w5, color: AppColors.text2)), dim: off),
          _cell(widths, 7, _dots(r), right: true),
        ]),
      ),
    );
  }

  // ─────────────────────────────── Phone list (`TrainersMobile`)

  /// Avatar | name (+ You) over speciality | status badge over load | ⋯.
  Widget _list() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final r in c.rows)
          Hover(
            onTap: () => context.go('/trainers/${r.id}'),
            builder: (_, h, _) => Container(
              padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
              decoration: BoxDecoration(
                color: h ? AppColors.hover : null,
                border: const Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(spacing: 10, children: [
                Opacity(opacity: r.active ? 1 : .55, child: _avatar(r, size: 32)),
                Expanded(
                  child: Opacity(
                    opacity: r.active ? 1 : .55,
                    child: Row(spacing: 8, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                          Row(spacing: 6, children: [
                            Flexible(child: CutText(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(14, W.w7))),
                            if (r.isMe) const AppBadge('You', plain: true),
                          ]),
                          CutText(r.spec.isEmpty ? '—' : r.spec, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, spacing: 4, children: [_status(r), _load(r, bar: 36)]),
                    ]),
                  ),
                ),
                _dots(r),
              ]),
            ),
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
