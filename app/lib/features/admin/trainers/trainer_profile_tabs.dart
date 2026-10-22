import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
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
import '../../../core/widgets/tooltip.dart';
import '../../trainer/clients/clients_parts.dart' show clientGoals;
import '../../trainer/me/me_common.dart';
import '../../trainer/me/me_model.dart';
import '../clients/admin_client_drawers.dart' show showChangeTrainerDrawer;

// Admin-only tabs of the Trainer profile (board `TrainerProfile`, D-48): Clients and Access and permissions.

const _badges = {
  'active': ('Active', Tone.ok),
  'pending': ('Pending', Tone.warn),
  'paused': ('Paused', Tone.neutral),
  'at_risk': ('At risk', Tone.bad),
};

// ═══════════════════════════════ Clients

/// Clients tab: search "Search his clients", Filter (Status, Goal), Assign clients; table Client, Program, Adherence,
/// Last check-in, Status, With him since, ⋯ (Open profile, Move to another trainer). 20 a page, most recent first.
class TpClientsTab extends StatefulWidget {
  const TpClientsTab(this.c, {super.key, required this.onAssign, required this.onChanged});
  final MeController c;
  final VoidCallback onAssign;

  /// A client moved away: the page numbers change.
  final VoidCallback onChanged;
  @override
  State<TpClientsTab> createState() => _TpClientsTabState();
}

class _TpClientsTabState extends State<TpClientsTab> {
  static const _size = 20;
  static const _groups = [
    ('status', 'Status', [('', 'Any'), ('active', 'Active'), ('at_risk', 'At risk'), ('paused', 'Paused'), ('pending', 'Pending')]),
  ];
  MeController get c => widget.c;
  final q = TextEditingController();
  final _h = ScrollController();
  final filters = <String, String>{};
  String search = '';
  List<Map> rows = [];
  int count = 0, page = 1, _seq = 0;
  bool loading = true;
  ApiError? error;
  Timer? _deb;

  List<(String, String, List<(String, String)>)> get groups => [..._groups, ('goal', 'Goal', [('', 'Any'), ...clientGoals])];
  int get nf => filters.values.where((v) => v.isNotEmpty).length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  late int _ver = c.version;

  @override
  void didUpdateWidget(TpClientsTab old) {
    super.didUpdateWidget(old);
    // Assign clients / Move all from the header changed the list.
    if (_ver != c.version) {
      _ver = c.version;
      _load();
    }
  }

  @override
  void dispose() {
    _deb?.cancel();
    q.dispose();
    _h.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => loading = true);
    try {
      final r = await Services.api.get<Map>('${c.api}/clients/', query: {'search': search, ...filters, 'page': page, 'page_size': _size});
      if (seq != _seq || !mounted) return;
      rows = [for (final x in (r['results'] as List?) ?? const []) x as Map];
      count = (r['count'] as num?)?.toInt() ?? rows.length;
      error = null;
    } on ApiError catch (e) {
      if (seq != _seq || !mounted) return;
      error = e;
    }
    setState(() => loading = false);
  }

  void _setFilter(String k, String v) {
    filters[k] = v;
    page = 1;
    _load();
  }

  void _clear() {
    filters.clear();
    q.clear();
    search = '';
    page = 1;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final total = (c.stats['clients'] as num?)?.toInt() ?? count;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _tools(phone),
          if (error != null && rows.isEmpty)
            EmptyState('Could not load ${c.his} clients', sub: error!.message, action: AppButton('Try again', onPressed: _load))
          else if (!loading && rows.isEmpty)
            nf > 0 || search.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
                      Text('No clients match.', style: AppText.s(13, W.w5, color: AppColors.muted)),
                      AppButton('Clear filters', kind: BtnKind.text, size: BtnSize.sm, onPressed: _clear),
                    ]),
                  )
                : EmptyState('${c.first} has no clients yet', sub: 'Assign clients to get ${c.him} started.', action: AppButton.primary('Assign clients', icon: AppIcons.plus, onPressed: widget.onAssign))
          else if (rows.isEmpty)
            const MeLoading()
          else
            Opacity(opacity: loading ? .6 : 1, child: phone ? _list() : _table()),
          if (rows.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
              child: Text('Showing ${rows.length} of ${nf > 0 || search.isNotEmpty ? count : total} · most recent first', style: AppText.s(12, W.w5, color: AppColors.muted)),
            ),
        ]),
      ),
      Pager(page: page, pageSize: _size, count: count, onPage: (p) {
        page = p;
        _load();
      }, empty: 'No clients'),
    ]);
  }

  Widget _tools(bool phone) {
    final search0 = AppSearchField(
      controller: q,
      placeholder: 'Search ${c.his} clients',
      icon: AppIcons.search,
      onChanged: (v) {
        search = v.trim();
        _deb?.cancel();
        _deb = Timer(const Duration(milliseconds: 300), () {
          page = 1;
          _load();
        });
      },
    );
    final filter = Builder(
      builder: (b) => phone
          ? AppIconButton(AppIcons.filter, tooltip: nf > 0 ? 'Filter · $nf' : 'Filter', dot: nf > 0, onPressed: () => _filter(b))
          : AppButton(nf > 0 ? 'Filter · $nf' : 'Filter', icon: AppIcons.filter, onPressed: () => _filter(b)),
    );
    final assign = phone
        ? AppButton.primary('Assign clients', icon: AppIcons.plus, iconOnly: true, tooltip: 'Assign clients', onPressed: widget.onAssign)
        : AppButton.primary('Assign clients', icon: AppIcons.plus, onPressed: widget.onAssign);
    return Padding(
      padding: phone ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(spacing: 8, children: [
        Expanded(
          child: phone ? search0 : Align(alignment: Alignment.centerLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 320), child: search0)),
        ),
        filter,
        assign,
      ]),
    );
  }

  void _filter(BuildContext anchor) => showFilterMenu(
        anchor,
        [
          for (final (k, l, opts) in groups)
            MenuGroup(
              l,
              value: opts.firstWhere((o) => o.$1 == (filters[k] ?? ''), orElse: () => opts.first).$2,
              options: [for (final (v, t) in opts) MenuEntry(t, selected: (filters[k] ?? '') == v, onTap: () => _setFilter(k, v))],
            ),
        ],
        onClear: nf > 0 ? _clear : null,
      );

  Future<void> _move(Map r) async {
    final ok = await showChangeTrainerDrawer(context, id: '${r['id']}', name: '${r['full_name']}');
    if (ok != true || !mounted) return;
    _load();
    widget.onChanged();
    showToast(context, '${'${r['full_name']}'.split(' ').first} has a new trainer', kind: ToastKind.ok);
  }

  void _menu(BuildContext b, Map r) => showAppMenu(b, width: 230, [
        MenuEntry('Open profile', icon: AppIcons.open, onTap: () => context.go('/clients/${r['id']}')),
        MenuEntry('Move to another trainer', icon: AppIcons.swapBoth, onTap: () => _move(r)),
      ]);

  Widget _dots(Map r) => Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'More actions', small: true, onPressed: () => _menu(b, r)));

  Widget _avatar(Map r, {double size = 30}) => AppAvatar('${r['full_name']}',
      size: size, url: r['avatar'] as String?, colors: AppColors.avatarCode('${r['avatar_color'] ?? 'c1'}'), initials: '${r['initials'] ?? ''}');

  Widget _badge(Map r) {
    final (l, t) = _badges['${r['badge']}'] ?? ('${r['badge']}', Tone.neutral);
    return AppBadge(l, tone: t);
  }

  String _since(Map r) {
    final d = DateTime.tryParse('${r['since'] ?? ''}');
    return d == null ? '—' : DateFormat('d MMM yyyy').format(d.toLocal());
  }

  Widget _adh(Map r) {
    final a = r['adherence'] as num?;
    final zero = a == null || a == 0;
    return Text(zero ? '—' : '$a%',
        style: AppText.s(13, zero ? W.w5 : W.w7, color: zero ? AppColors.muted : (a < 70 ? AppColors.trWarn : AppColors.text), tabular: true));
  }

  static const _cols = <(String, double, bool)>[
    ('Client', 210, false),
    ('Program', 210, false),
    ('Adherence', 96, true),
    ('Last check-in', 130, false),
    ('Status', 96, false),
    ('With him since', 120, false),
    ('', 56, true),
  ];

  Widget _table() => LayoutBuilder(builder: (context, box) {
        final min = _cols.fold<double>(0, (a, x) => a + x.$2);
        final extra = (box.maxWidth - min).clamp(0.0, double.infinity);
        final widths = [for (final (i, x) in _cols.indexed) x.$2 + (i == 0 ? extra * .5 : (i == 1 ? extra * .5 : 0))];
        Widget cell(int i, Widget child, {bool right = false}) => Container(
              width: widths[i],
              padding: EdgeInsets.fromLTRB(i == 0 ? 16 : 12, 0, i == _cols.length - 1 ? 16 : 12, 0),
              alignment: right ? Alignment.centerRight : Alignment.centerLeft,
              child: child,
            );
        final t2 = AppText.s(13, W.w5, color: AppColors.text2);
        final table = SizedBox(
          width: min + extra,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 34,
              decoration: const BoxDecoration(color: AppColors.tableHeadDt, border: Border.symmetric(horizontal: BorderSide(color: AppColors.line))),
              child: Row(children: [
                for (final (i, x) in _cols.indexed)
                  cell(i, Text((i == 5 ? 'With ${c.him} since' : x.$1).toUpperCase(), maxLines: 1, style: AppText.s(11.5, W.w7, color: AppColors.muted, ls: .58)), right: x.$3),
              ]),
            ),
            for (final (i, r) in rows.indexed)
              Hover(
                onTap: () => context.go('/clients/${r['id']}'),
                builder: (_, h, _) => Container(
                  height: 49,
                  decoration: BoxDecoration(color: h ? AppColors.hover : null, border: i == rows.length - 1 ? null : const Border(bottom: BorderSide(color: AppColors.line))),
                  child: Row(children: [
                    cell(
                        0,
                        Row(spacing: 10, children: [
                          _avatar(r),
                          Expanded(
                            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                              CutText('${r['full_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7)),
                              CutText('${r['goal_label'] ?? ''}'.isEmpty ? '—' : '${r['goal_label']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted)),
                            ]),
                          ),
                        ])),
                    cell(1, CutText('${r['program']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: t2)),
                    cell(2, _adh(r), right: true),
                    cell(3, CutText('${r['last_checkin']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: t2)),
                    cell(4, _badge(r)),
                    cell(5, Text(_since(r), maxLines: 1, softWrap: false, style: t2)),
                    cell(6, _dots(r), right: true),
                  ]),
                ),
              ),
          ]),
        );
        if (box.maxWidth >= min) return table;
        return Scrollbar(
          controller: _h,
          thumbVisibility: true,
          child: SingleChildScrollView(controller: _h, scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(bottom: 8), child: table),
        );
      });

  /// Phone: avatar | name over "Program · 86%" | status | ⋯.
  Widget _list() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final r in rows)
          Hover(
            onTap: () => context.go('/clients/${r['id']}'),
            builder: (_, h, _) => Container(
              padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
              decoration: BoxDecoration(color: h ? AppColors.hover : null, border: const Border(top: BorderSide(color: AppColors.line))),
              child: Row(spacing: 10, children: [
                _avatar(r, size: 32),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                    CutText('${r['full_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(14, W.w7)),
                    CutText(
                        [
                          '${r['program']}',
                          if (r['adherence'] != null && r['adherence'] != 0) '${r['adherence']}%',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.s(12.5, W.w5, color: AppColors.muted)),
                  ]),
                ),
                _badge(r),
                _dots(r),
              ]),
            ),
          ),
      ]);
}

// ═══════════════════════════════ Access and permissions

/// Access tab (admin): Access level (Assigned clients / All clients / Custom), Summary (Switched on, Clients he
/// sees, Not saved, Undo changes, Save access · N), the permission grid by group with toggles (changed rows
/// marked amber), and the admins-only note. Saves with PUT `trainers/<id>/access/`.
class TpAccessTab extends StatefulWidget {
  const TpAccessTab(this.c, {super.key});
  final MeController c;
  @override
  State<TpAccessTab> createState() => _TpAccessTabState();
}

class _TpAccessTabState extends State<TpAccessTab> {
  MeController get c => widget.c;
  Map<String, bool> saved = {}, now = {};

  bool busy = false;

  /// The server's presets (`access_presets` of `trainers/<id>/`): the switches of Assigned clients and All clients.
  Map<String, bool> _preset(String k) => {for (final e in (((c.me['access_presets'] as Map?)?[k] as Map?) ?? const {}).entries) '${e.key}': e.value == true};

  @override
  void initState() {
    super.initState();
    _read();
  }

  void _read() {
    saved = {
      for (final g in c.groups)
        for (final i in g['items'] as List) '${(i as Map)['key']}': i['on'] == true,
    };
    now = {...saved};
  }

  int get changes => now.keys.where((k) => now[k] != saved[k]).length;
  int get on => now.values.where((v) => v).length;

  bool _same(Map<String, bool> p) => p.isNotEmpty && now.keys.every((k) => (p[k] ?? false) == now[k]);

  String get level => _same(_preset('assigned')) ? 'Assigned clients' : (_same(_preset('all')) ? 'All clients' : 'Custom');

  String get _mode => switch (level) { 'All clients' => 'all', 'Assigned clients' => 'assigned', _ => 'custom' };

  void _pick(String l) {
    final p = _preset(l == 'All clients' ? 'all' : 'assigned');
    if (l == 'Custom' || p.isEmpty) return;
    setState(() => now = {for (final k in now.keys) k: p[k] ?? false});
  }

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      await Services.api.put<Map>('${c.api}/access/', {'access_mode': _mode, 'permissions': now});
      await c.reloadMe();
      if (!mounted) return;
      _read();
      showToast(context, '${c.first}’s access is saved', sub: '${c.first} gets a notice', kind: ToastKind.ok);
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not save the access', sub: e.message, kind: ToastKind.err);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final owner = c.profile['is_owner'] == true;
    if (owner) {
      return AppCard(child: EmptyState('${c.first} is the owner', sub: 'The owner can do everything. Access is only set for trainers.'));
    }
    final levels = [
      ('Assigned clients', 'Only the clients you give ${c.him}: plans and check-ins. Default for new trainers.'),
      ('All clients', 'Sees and can cover every client of the gym. For senior trainers.'),
      ('Custom', 'Switch each permission on or off below.'),
    ];
    final levelCard = MeCard(
      title: 'Access level',
      sub: 'Pick a starting point, then switch single permissions below',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.line2)),
          child: Column(children: [
            for (final (i, (t, s)) in levels.indexed)
              Hover(
                onTap: () => _pick(t),
                builder: (_, h, _) => Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: level == t ? AppColors.hover : (h ? AppColors.sub : null),
                    border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line)),
                  ),
                  child: Row(spacing: 10, children: [
                    AppRadio(selected: level == t, onTap: () => _pick(t)),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                        Text(t, style: AppText.s(13.5, W.w7)),
                        Text(s, style: AppText.s(12, W.w5, color: AppColors.muted, h: 1.4)),
                      ]),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
    final ch = changes;
    Widget sumRow(String k, String v, {Color? color, bool first = false}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: AppColors.line))),
          child: Row(spacing: 12, children: [
            Expanded(child: Text(k, style: AppText.s(13, W.w5, color: AppColors.muted))),
            Flexible(child: Text(v, textAlign: TextAlign.right, style: AppText.s(13, W.w7, color: color ?? AppColors.text))),
          ]),
        );
    final summary = MeCard(
      title: 'Summary',
      sub: level,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          sumRow('Switched on', '$on of ${now.length}', first: true),
          sumRow('Clients ${c.he} ${c.he == 'they' ? 'see' : 'sees'}', now['clients.view_all'] == true ? 'Every client of the gym' : 'Only ${c.his} clients'),
          sumRow('Not saved', ch == 0 ? 'Nothing' : '$ch ${ch == 1 ? 'change' : 'changes'}', color: ch == 0 ? null : AppColors.trWarn),
          const SizedBox(height: 12),
          Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
            AppButton('Undo changes', onPressed: ch == 0 ? null : () => setState(() => now = {...saved})),
            AppButton.primary(ch == 0 ? 'Saved' : 'Save access · $ch', loading: busy, onPressed: ch == 0 || busy ? null : _save),
          ]),
        ]),
      ),
    );
    final grid = LayoutBuilder(builder: (context, b) {
      final cols = b.maxWidth >= 900 ? 3 : (b.maxWidth >= 560 ? 2 : 1);
      final gap = 16.0;
      final w = (b.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(spacing: gap, runSpacing: gap, children: [for (final g in c.groups) SizedBox(width: w, child: _group(g))]);
    });
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      LayoutBuilder(builder: (context, b) {
        if (b.maxWidth < 760 || phone) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [levelCard, summary]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [Expanded(child: levelCard), SizedBox(width: 340, child: summary)]);
      }),
      grid,
      Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.line2)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: AppIcon(AppIcons.lock, size: 16, color: AppColors.muted)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text('Only for admins. Never given to a trainer.', style: AppText.s(13, W.w6)),
              Text('Add trainers · Gym settings · Approve sign-ups for other trainers · Delete gym data', style: AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.45)),
            ]),
          ),
        ]),
      ),
    ]);
  }

  Widget _group(Map g) {
    final items = [for (final i in g['items'] as List) i as Map];
    final n = items.where((i) => now['${i['key']}'] == true).length;
    return AppCard(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(children: [
            Expanded(child: Text('${g['group']}', style: AppText.s(13.5, W.w6))),
            Text('$n of ${items.length}', style: AppText.s(12, W.w5, color: AppColors.muted)),
          ]),
        ),
        for (final i in items) _perm(i),
      ]),
    );
  }

  /// `.tp-perm`: label over hint (or On / Off), toggle; a changed row has an amber edge.
  Widget _perm(Map i) {
    final k = '${i['key']}';
    final v = now[k] == true;
    final changed = v != saved[k];
    final hint = '${i['hint'] ?? ''}';
    return Hover(
      onTap: () => setState(() => now[k] = !v),
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 16, 8),
        decoration: BoxDecoration(
          color: changed ? AppColors.tpChangedBg : (h ? AppColors.sub : null),
          border: Border(left: BorderSide(color: changed ? AppColors.tpChangedEdge : Colors.transparent, width: 2)),
        ),
        child: Row(spacing: 10, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text('${i['label']}', style: AppText.s(13, W.w5)),
              Text(hint.isEmpty ? (v ? 'On' : 'Off') : hint, style: AppText.s(11.5, W.w5, color: AppColors.muted)),
            ]),
          ),
          AppTooltip(message: v ? 'Switch off' : 'Switch on', child: AppToggle(value: v, onChanged: (x) => setState(() => now[k] = x))),
        ]),
      ),
    );
  }
}
