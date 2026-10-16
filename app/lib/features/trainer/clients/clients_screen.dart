import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/page.dart';
// import '../../../core/api/api_error.dart'; // Export is off for now
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
// import '../../../core/util/save_file.dart'; // Export is off for now
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
import 'clients_model.dart';
import 'clients_parts.dart';

/// My clients (boards `TrainerClients` + `TrainerClientsMobile`). Only the trainer's own clients (the API
/// starts from `visible_clients`). Web: table, row ⋯ menu, pager. Phone: one line per client.
class TrainerClientsScreen extends StatefulWidget {
  const TrainerClientsScreen({super.key});
  @override
  State<TrainerClientsScreen> createState() => _TrainerClientsScreenState();
}

const _tabs = [('all', 'All'), ('active', 'Active'), ('pending', 'Pending'), ('paused', 'Paused'), ('at_risk', 'At risk')];

const _badges = {
  'active': ('Active', Tone.ok),
  'pending': ('Pending', Tone.warn),
  'paused': ('Paused', Tone.neutral),
  'at_risk': ('At risk', Tone.bad),
  'no_trainer': ('No trainer', Tone.warn),
};

class _TrainerClientsScreenState extends State<TrainerClientsScreen> {
  final c = MyClientsController();
  final q = TextEditingController();
  final _hScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    c.load();
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
              title: 'My clients',
              sub: n.isEmpty ? ' ' : '${n['all']} client${n['all'] == 1 ? '' : 's'} given to you · ${n['active']} active · ${n['at_risk']} at risk',
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedTabs<String>(
                    items: [for (final (k, l) in _tabs) TabItem(k, l, count: n[k])],
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
                    if (c.error != null && c.rows.isEmpty)
                      EmptyState('Could not load your clients', sub: c.error!.message, action: AppButton('Try again', onPressed: c.load))
                    else if (!c.loading && c.rows.isEmpty)
                      EmptyState(
                        c.search.isNotEmpty || c.activeFilters > 0 ? 'No clients match' : 'No clients here yet',
                        sub: c.search.isNotEmpty || c.activeFilters > 0 ? 'Try another name or clear the filters.' : 'Clients Vimal gives you show up here.',
                        action: c.activeFilters > 0 ? AppButton('Clear filters', onPressed: c.clearFilters) : null,
                      )
                    else if (c.rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))),
                      )
                    else
                      phone ? _list() : _table(),
                  ]),
                ),
                Pager(page: c.page, pageSize: MyClientsController.pageSize, count: c.count, onPage: c.goPage),
              ]),
            ],
          );
        },
      );

  // ─────────────────────────────── Tools: search, Filter, Export

  Widget _tools(bool phone) {
    final nf = c.activeFilters;
    final search = AppSearchField(
      controller: q,
      placeholder: 'Search name or email',
      icon: AppIcons.search,
      onChanged: c.setSearch,
    );
    return Container(
      padding: phone ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: phone ? const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))) : null,
      child: Row(spacing: 8, children: [
        phone ? Expanded(child: search) : SizedBox(width: 300, child: search),
        if (!phone) const Spacer(),
        Builder(
          builder: (b) => phone
              ? AppIconButton(AppIcons.filter, tooltip: nf > 0 ? 'Filter · $nf' : 'Filter', dot: nf > 0, onPressed: () => _filter(b))
              : AppButton(nf > 0 ? 'Filter · $nf' : 'Filter', icon: AppIcons.filter, onPressed: () => _filter(b)),
        ),
        // Export is off for now (Gautam, 16 Oct: "abhi need nahi hai"). The API (`clients/export/`) is still there.
        // Builder(
        //   builder: (b) => phone
        //       ? AppIconButton(AppIcons.downloadLine, tooltip: 'Export', onPressed: () => _exportMenu(b))
        //       : AppButton('Export', icon: AppIcons.downloadLine, trailingIcon: AppIcons.chevronDown, onPressed: () => _exportMenu(b)),
        // ),
      ]),
    );
  }

  /// `.fm-menu`: one row per group with its current pick ("Goal   Any ›"); its options open beside it.
  void _filter(BuildContext anchor) => showFilterMenu(
        anchor,
        [
          for (final g in mcFilters)
            MenuGroup(
              g.label,
              value: g.options.firstWhere((o) => o.$1 == (c.filters[g.key] ?? ''), orElse: () => g.options.first).$2,
              options: [for (final (v, l) in g.options) MenuEntry(l, selected: (c.filters[g.key] ?? '') == v, onTap: () => c.setFilter(g.key, v))],
            ),
        ],
        onClear: c.activeFilters > 0 ? c.clearFilters : null,
      );

  // Export is off for now; the menu and the save are kept here to switch back on.
  // void _exportMenu(BuildContext anchor) => showAppMenu(
  //       anchor,
  //       [
  //         MenuEntry(c.activeFilters > 0 || c.search.isNotEmpty || c.tab != 'all' ? 'This list (${c.count})' : 'All clients (${c.count})',
  //             icon: AppIcons.downloadLine, onTap: () => _export(false)),
  //         MenuEntry(c.selected.isEmpty ? 'Selected clients' : 'Selected clients (${c.selected.length})',
  //             icon: AppIcons.check, onTap: c.selected.isEmpty ? null : () => _export(true)),
  //       ],
  //       width: 220,
  //     );

  // Future<void> _export(bool selected) async {
  //   try {
  //     final bytes = await c.export(onlySelected: selected);
  //     final d = DateTime.now();
  //     final where = await saveFile('my-clients-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.csv', bytes);
  //     if (mounted) showToast(context, 'Exported', sub: selected ? '${c.selected.length} clients · $where' : '${c.count} clients · $where', kind: ToastKind.ok);
  //   } catch (e) {
  //     if (mounted) showToast(context, 'Could not export', sub: e is ApiError ? e.message : 'Check your connection and try again.', kind: ToastKind.info);
  //   }
  // }

  // ─────────────────────────────── Row actions

  void _open(McRow r) => context.go('/clients/${r.id}');

  void _menu(BuildContext anchor, McRow r) => showAppMenu(anchor, [
        MenuEntry('View profile', icon: AppIcons.eye, onTap: () => _open(r)),
        MenuEntry('Edit details', icon: AppIcons.edit, onTap: () => _edit(r)),
      ]);

  Future<void> _edit(McRow r) async {
    final saved = await showEditClientDrawer(context, c, r);
    if (saved == true && mounted) showToast(context, '${r.name.split(' ').first}’s details saved', kind: ToastKind.ok);
  }

  // ─────────────────────────────── Web table (`.tbl.dt`)

  static const _cols = <(String, double, bool)>[
    // label, width, right aligned (Client takes what is left)
    // ('', 42, false), // select box: off with Export for now
    ('Client', 200, false),
    ('Goal', 124, false),
    ('Status', 104, false),
    ('Onboarding', 196, false),
    ('Phone', 140, false),
    ('Next check-in', 124, false),
    ('Last active', 100, true),
    ('Actions', 76, true),
  ];

  Widget _table() => LayoutBuilder(builder: (context, box) {
        final min = _cols.fold<double>(0, (a, x) => a + x.$2);
        final extra = (box.maxWidth - min).clamp(0.0, double.infinity);
        final widths = [for (final (i, x) in _cols.indexed) x.$2 + (i == 0 ? extra : 0)];
        // final allOn = c.rows.isNotEmpty && c.rows.every((r) => c.selected.contains(r.id));
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
                    padding: EdgeInsets.fromLTRB(i == 0 ? 16 : 12, 0, 12, 0),
                    alignment: x.$3 ? Alignment.centerRight : Alignment.centerLeft,
                    // child: i == 0 ? AppCheckbox(value: allOn, onChanged: (_) => c.toggleAll()) : …
                    child: Text(x.$1.toUpperCase(), maxLines: 1, style: AppText.s(11.5, W.w7, color: AppColors.muted, ls: .58)),
                  ),
              ]),
            ),
            for (final (i, r) in c.rows.indexed) _TableRow(r, widths: widths, last: i == c.rows.length - 1, c: c, onOpen: () => _open(r), onMenu: (b) => _menu(b, r)),
          ]),
        );
        if (box.maxWidth >= min) return table;
        // Narrower than the columns: the table scrolls sideways (as on the board), with a thin bar to show it.
        return Scrollbar(
          controller: _hScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(controller: _hScroll, scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(bottom: 8), child: table),
        );
      });

  // ─────────────────────────────── Phone list

  Widget _list() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, r) in c.rows.indexed)
          Hover(
            onTap: () => _open(r),
            builder: (_, h, _) => Container(
              padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
              decoration: BoxDecoration(
                color: h ? AppColors.hover : null,
                border: i == c.rows.length - 1 ? null : const Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(children: [
                SizedBox(width: 40, child: Align(alignment: Alignment.centerLeft, child: _av(r))),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                    Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(14, W.w7)),
                    Text(r.goal.isEmpty ? '—' : r.goal, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
                  ]),
                ),
                Padding(padding: const EdgeInsets.only(left: 8, right: 2), child: _badge(r)),
                Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'More actions', small: true, fill: true, onPressed: () => _menu(b, r))),
              ]),
            ),
          ),
      ]);
}

Widget _av(McRow r) => AppAvatar(r.name, size: 32, colors: AppColors.avatarCode(r.color), initials: r.initials.isEmpty ? null : r.initials);

Widget _badge(McRow r) {
  final (l, t) = _badges[r.badge] ?? (r.badge, Tone.neutral);
  return AppBadge(l, tone: t);
}

class _TableRow extends StatelessWidget {
  const _TableRow(this.r, {required this.widths, required this.last, required this.c, required this.onOpen, required this.onMenu});
  final McRow r;
  final List<double> widths;
  final bool last;
  final MyClientsController c;
  final VoidCallback onOpen;
  final void Function(BuildContext) onMenu;

  @override
  Widget build(BuildContext context) {
    final cap = AppText.s(12, W.w5, color: AppColors.muted);
    final body = AppText.s(13.5, W.w4);
    Widget cell(int i, Widget child, {bool right = false}) => Container(
          width: widths[i],
          padding: EdgeInsets.fromLTRB(i == 0 ? 16 : 12, 0, 12, 0),
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          child: child,
        );
    return Hover(
      builder: (_, h, _) => Container(
        height: 57,
        decoration: BoxDecoration(
          color: h ? AppColors.hover : null,
          border: last ? null : const Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(children: [
          // cell(0, AppCheckbox(value: c.selected.contains(r.id), onChanged: (_) => c.toggle(r.id))), // select box: off for now
          cell(
            0,
            Row(spacing: 10, children: [
              _av(r),
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Hover(
                    onTap: onOpen,
                    builder: (_, hn, _) => Text(r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.s(13.5, W.w7, color: hn ? AppColors.accentText : AppColors.text)),
                  ),
                  Text(r.email.isEmpty ? '—' : r.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: cap),
                ]),
              ),
            ]),
          ),
          cell(1, Text(r.goal.isEmpty ? '—' : r.goal, maxLines: 1, overflow: TextOverflow.ellipsis, style: body)),
          cell(2, _badge(r)),
          cell(
            3,
            Row(spacing: 8, children: [
              ProgressBar(value: r.onbDone <= 1 ? 0 : r.onb, width: 90),
              Flexible(child: Text(r.onbText, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: cap)),
            ]),
          ),
          cell(4, Text(r.phoneText, maxLines: 1, softWrap: false, style: cap)),
          cell(5, Text(r.next, maxLines: 1, style: r.next == 'Overdue' ? AppText.s(13.5, W.w7, color: AppColors.badText) : body)),
          cell(6, Text(r.lastActive, maxLines: 1, style: cap), right: true),
          cell(7, Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'More actions', small: true, fill: true, onPressed: () => onMenu(b))), right: true),
        ]),
      ),
    );
  }
}
