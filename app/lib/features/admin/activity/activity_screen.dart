import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../app/shell/page.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/util/save_file.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tooltip.dart';

/// Board ranges → API `range`.
const _ranges = [('today', 'Today'), ('7d', 'Last 7 days'), ('30d', 'Last 30 days'), ('3m', 'Last 3 months'), ('all', 'All time')];

/// Board chips → API `kind` ('' = All). Sessions and team rows show under All.
const _kinds = [
  ('', 'All'),
  ('checkin', 'Check-in'),
  ('plan', 'Plan'),
  ('workout', 'Workout'),
  ('meal', 'Meal'),
  ('body', 'Body'),
  ('client', 'Client'),
  ('content', 'Content'),
  ('system', 'System'),
];

/// Filter → Who (API `who`).
const _who = [('', 'Everyone'), ('team', 'Team'), ('clients', 'Clients'), ('automations', 'Automations')];

const _page = 20;

/// Admin → Activity log (boards `Activity` + `ActivityMobile`, D-48): every change by the team, the clients and the
/// system. Search (person, client or item), Filter (Who, Person), the range menu, kind chips with counts, rows by
/// day (old → new), "Showing 20 of 64" + Show more (cursor paged), Export (CSV of what the filters show).
class AdminActivityScreen extends StatefulWidget {
  const AdminActivityScreen({super.key});
  @override
  State<AdminActivityScreen> createState() => _AdminActivityScreenState();
}

class _AdminActivityScreenState extends State<AdminActivityScreen> {
  final q = TextEditingController();
  String range = '7d', kind = '', who = '', person = '', search = '';
  List<(String, String)> team = [];
  List<Map> rows = [];
  Map counts = const {};
  String? cursor;
  bool loading = true, more = false, exporting = false;
  ApiError? error;
  int _req = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _loadTeam();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    q.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _q => {
        'range': range,
        if (kind.isNotEmpty) 'kind': kind,
        if (who.isNotEmpty) 'who': who,
        if (person.isNotEmpty) 'person': person,
        if (search.isNotEmpty) 'search': search,
      };

  int get _activeFilters => (who.isNotEmpty ? 1 : 0) + (person.isNotEmpty ? 1 : 0);

  Future<void> _load() async {
    final req = ++_req;
    setState(() => loading = true);
    try {
      final r = await Future.wait([
        Services.api.get<Map>('activity/', query: {..._q, 'page_size': _page}),
        Services.api.get<Map>('activity/counts/', query: {..._q, 'by_day': 1}),
      ]);
      if (req != _req || !mounted) return;
      rows = [for (final x in (r[0]['results'] as List?) ?? const []) x as Map];
      cursor = _cursor(r[0]['next']);
      counts = r[1];
      error = null;
    } on ApiError catch (e) {
      if (req != _req || !mounted) return;
      error = e;
    }
    setState(() => loading = false);
  }

  /// Filter → Person: everyone in the team (owner first).
  Future<void> _loadTeam() async {
    try {
      final r = await Services.api.get<Map>('trainers/', query: {'tab': 'all', 'page_size': 100});
      if (!mounted) return;
      setState(() => team = [for (final t in (r['results'] as List?) ?? const []) ('${(t as Map)['id']}', '${t['full_name']}')]);
    } on ApiError {
      // The Person group just stays at Anyone.
    }
  }

  String? _cursor(Object? next) => next == null ? null : Uri.tryParse('$next')?.queryParameters['cursor'];

  Future<void> _more() async {
    if (cursor == null || more) return;
    final req = _req;
    setState(() => more = true);
    try {
      final r = await Services.api.get<Map>('activity/', query: {..._q, 'page_size': _page, 'cursor': cursor});
      if (req != _req || !mounted) return;
      rows = [...rows, for (final x in (r['results'] as List?) ?? const []) x as Map];
      cursor = _cursor(r['next']);
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not load more', sub: e.message, kind: ToastKind.info);
    }
    if (mounted) setState(() => more = false);
  }

  Future<void> _export() async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      final r = await Services.api.download('activity/export/', query: _q);
      final where = await saveFile('activity-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv', r.data ?? const []);
      if (mounted) showToast(context, 'Exported', sub: 'Activity log · $where', kind: ToastKind.ok);
    } catch (e) {
      if (mounted) showToast(context, 'Could not export', sub: e is ApiError ? e.message : 'Check your connection and try again.', kind: ToastKind.info);
    }
    if (mounted) setState(() => exporting = false);
  }

  void _set(VoidCallback f) {
    setState(f);
    _load();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || v.trim() == search) return;
      _set(() => search = v.trim());
    });
  }

  void _clearFilters() => _set(() {
        who = '';
        person = '';
      });

  int _n(String k) => ((counts[k.isEmpty ? 'all' : k] as num?) ?? 0).toInt();

  String get _personName => team.where((t) => t.$1 == person).firstOrNull?.$2 ?? 'Anyone';

  // ─────────────────────────────── Page

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    return StaffPage(
      maxWidth: 980,
      onRefresh: _load,
      header: PageTop(
        title: 'Activity log',
        sub: 'Every change by your team, your clients and the system.',
        actions: [
          AppButton('Export', icon: AppIcons.download, iconOnly: compactTop(context), tooltip: 'Export', loading: exporting, onPressed: _export),
        ],
      ),
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _tools(phone),
            if (_activeFilters > 0) _filterChips(),
            // Kind chips: one line, scrolls sideways.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.fromLTRB(phone ? 12 : 16, 0, phone ? 12 : 16, 4),
              child: Row(spacing: 6, children: [
                for (final (k, l) in _kinds)
                  FilterChipX(l, selected: kind == k, count: _n(k), onTap: () {
                    if (kind != k) _set(() => kind = k);
                  }),
              ]),
            ),
            if (error != null && rows.isEmpty)
              EmptyState('Could not load the activity log', sub: error!.message, action: AppButton('Try again', onPressed: _load))
            else if (loading && rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))),
              )
            else if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
                child: Text('Nothing matches. Try a longer date range or fewer filters.', textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)),
              )
            else
              Opacity(opacity: loading ? .55 : 1, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _days(phone))),
            if (rows.isNotEmpty) _foot(phone),
          ]),
        ),
      ],
    );
  }

  /// `.tp-atools`: search left; Filter and the range on the right. Phone: search on its own line, the buttons under it.
  Widget _tools(bool phone) {
    final nf = _activeFilters;
    final searchBox = AppSearchField(controller: q, placeholder: 'Search person, client or item', icon: AppIcons.search, onChanged: _onSearch);
    final filter = Builder(
      builder: (b) => AppButton(nf > 0 ? 'Filter · $nf' : 'Filter', icon: AppIcons.filter, onPressed: () => _filter(b)),
    );
    final rangeBtn = Builder(
      builder: (b) => AppButton(
        _ranges.firstWhere((r) => r.$1 == range).$2,
        icon: AppIcons.calStat,
        trailingIcon: AppIcons.chevronDown,
        onPressed: () => showAppMenu(b, [
          for (final (v, l) in _ranges)
            MenuEntry(l, selected: v == range, onTap: () {
              if (v != range) _set(() => range = v);
            }),
        ]),
      ),
    );
    if (phone) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
          searchBox,
          Row(spacing: 8, children: [filter, rangeBtn]),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(spacing: 8, children: [
        Expanded(child: Align(alignment: Alignment.centerLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 340), child: searchBox))),
        filter,
        rangeBtn,
      ]),
    );
  }

  void _filter(BuildContext anchor) => showFilterMenu(
        anchor,
        [
          MenuGroup('Who', value: _who.firstWhere((w) => w.$1 == who).$2, options: [
            for (final (v, l) in _who) MenuEntry(l, selected: v == who, onTap: () => _set(() => who = v)),
          ]),
          MenuGroup('Person', value: _personName, options: [
            MenuEntry('Anyone', selected: person.isEmpty, onTap: () => _set(() => person = '')),
            for (final (id, name) in team) MenuEntry(name, selected: id == person, onTap: () => _set(() => person = id)),
          ]),
        ],
        onClear: _activeFilters > 0 ? _clearFilters : null,
      );

  /// "Who: Team ×", "Person: Aman Verma ×", Clear.
  Widget _filterChips() => Padding(
        padding: EdgeInsets.fromLTRB(context.isPhone ? 12 : 16, 0, context.isPhone ? 12 : 16, 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(spacing: 6, children: [
            if (who.isNotEmpty) _FChip('Who: ${_who.firstWhere((w) => w.$1 == who).$2}', onRemove: () => _set(() => who = '')),
            if (person.isNotEmpty) _FChip('Person: $_personName', onRemove: () => _set(() => person = '')),
            AppButton('Clear', kind: BtnKind.text, size: BtnSize.sm, onPressed: _clearFilters),
          ]),
        ),
      );

  Widget _foot(bool phone) {
    final total = _n(kind);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: EdgeInsets.fromLTRB(phone ? 16 : 16, 12, 16, 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      child: Row(children: [
        Expanded(child: Text('Showing ${rows.length} of ${total < rows.length ? rows.length : total}', style: AppText.cap)),
        if (cursor != null) AppButton('Show more', loading: more, onPressed: _more),
      ]),
    );
  }

  // ─────────────────────────────── Day groups

  List<Widget> _days(bool phone) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final groups = <DateTime, List<Map>>{};
    for (final r in rows) {
      final t = DateTime.tryParse('${r['created_at']}')?.toLocal() ?? now;
      groups.putIfAbsent(DateTime(t.year, t.month, t.day), () => []).add(r);
    }
    final perDay = (counts['days'] as Map?) ?? const {};
    final out = <Widget>[];
    for (final MapEntry(key: d, value: items) in groups.entries) {
      final diff = today.difference(d).inDays;
      final label = diff == 0 ? 'Today' : (diff == 1 ? 'Yesterday' : DateFormat('EEE, d MMM').format(d));
      // The day's full count (not only the rows loaded so far).
      final n = math.max((perDay[DateFormat('yyyy-MM-dd').format(d)] as num?)?.toInt() ?? 0, items.length);
      out.add(Padding(
        padding: EdgeInsets.fromLTRB(phone ? 16 : 16, 12, 16, 6),
        child: Row(spacing: 6, children: [
          Text(label.toUpperCase(), style: AppText.s(11.5, W.w6, color: AppColors.muted, ls: .46)),
          Text('·', style: AppText.s(11.5, W.w5, color: AppColors.muted)),
          Text('$n', style: AppText.s(11.5, W.w5, color: AppColors.muted)),
        ]),
      ));
      out.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < items.length; i++) ActivityLogRow(items[i], today: diff == 0, last: i == items.length - 1),
        ]),
      ));
    }
    return out;
  }
}

/// `.tp-tl-row`: round kind icon, "<b>who</b> verb", the change (old struck → new blue) or a grey note, and the time
/// on the right ("2 min ago" today, "7:40 pm" before; hover shows where it came from: "Admin · Web").
class ActivityLogRow extends StatelessWidget {
  const ActivityLogRow(this.r, {super.key, required this.today, required this.last});
  final Map r;
  final bool today, last;

  static (AppIconData, Color, Color) look(String kind, String actorType) {
    if (actorType == 'automation' || kind == 'system') return (AppIcons.bolt, AppColors.sub, AppColors.muted);
    return switch (kind) {
      'workout' => (AppIcons.dumbbell, AppColors.tlPlBg, AppColors.tlPlFg),
      'meal' => (AppIcons.bowl, AppColors.tlChBg, AppColors.tlChFg),
      'checkin' => (AppIcons.clipboardShort, AppColors.tlCiBg, AppColors.tlCiFg),
      'body' => (AppIcons.scale, AppColors.tlClBg, AppColors.tlClFg),
      'plan' => (AppIcons.edit, AppColors.tlPkBg, AppColors.tlPkFg),
      'client' => (AppIcons.team, AppColors.tlTlBg, AppColors.tlTlFg),
      'content' => (AppIcons.play, AppColors.sub, AppColors.muted),
      'session' => (AppIcons.calendar, AppColors.sub, AppColors.muted),
      _ => (AppIcons.person, AppColors.sub, AppColors.muted),
    };
  }

  String get _who {
    final l = '${r['actor_label'] ?? ''}';
    if (l.isNotEmpty) return l;
    return r['actor_type'] == 'automation' ? 'Automation' : 'System';
  }

  /// The grey line under the title when there is no old → new change: the note, else the item when the verb
  /// doesn't name it, plus "18 of 18 sets".
  String get _note {
    final meta = (r['meta'] as Map?) ?? const {};
    final note = '${meta['note'] ?? ''}';
    if (note.isNotEmpty) return note;
    final target = '${r['target_label'] ?? ''}';
    final verb = '${r['verb'] ?? ''}'.toLowerCase();
    final parts = <String>[];
    if (target.isNotEmpty && !verb.contains(target.toLowerCase())) parts.add(target);
    if (meta['sets_planned'] is num && (meta['sets_planned'] as num) > 0) parts.add('${meta['sets_done']} of ${meta['sets_planned']} sets');
    return parts.join(' · ');
  }

  String get _time {
    final t = DateTime.tryParse('${r['created_at']}')?.toLocal();
    if (t == null) return '';
    if (!today) return DateFormat('h:mm a').format(t).toLowerCase();
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    return '${d.inHours} h ago';
  }

  @override
  Widget build(BuildContext context) {
    final (ic, bg, fg) = look('${r['kind']}', '${r['actor_type']}');
    final from = '${r['change_from'] ?? ''}', to = '${r['change_to'] ?? ''}';
    final note = _note;
    final src = '${r['source'] ?? ''}';
    final time = Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(_time, style: AppText.s(12, W.w5, color: AppColors.muted)),
    );
    return Stack(children: [
      if (!last) Positioned(left: 13, top: 34, bottom: 0, child: Container(width: 1.5, color: AppColors.line)),
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 5, 0, 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: AppIcon(ic, size: 14, color: fg),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text.rich(TextSpan(style: AppText.s(13.5, W.w4, color: AppColors.text2, h: 1.3), children: [
                  TextSpan(text: _who, style: AppText.s(13.5, W.w6, h: 1.3)),
                  TextSpan(text: ' ${r['verb'] ?? ''}'),
                ])),
                if (from.isNotEmpty || to.isNotEmpty)
                  Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                    Text(from, style: AppText.s(12.5, W.w4, color: AppColors.muted).copyWith(decoration: TextDecoration.lineThrough, decorationColor: AppColors.muted)),
                    const AppIcon(AppIcons.arrowRight, size: 13, color: AppColors.muted),
                    Text(to, style: AppText.s(12.5, W.w6, color: AppColors.accentText)),
                  ])
                else if (note.isNotEmpty)
                  Text(note, style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.3)),
              ]),
            ),
          ),
          if (src.isEmpty) time else AppTooltip(message: src, side: TipSide.below, child: time),
        ]),
      ),
    ]);
  }
}

/// `.fchip.on`: dark chip with ×.
class _FChip extends StatelessWidget {
  const _FChip(this.label, {required this.onRemove});
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
            decoration: BoxDecoration(color: h ? AppColors.text2 : AppColors.text, borderRadius: AppRadius.all(AppRadius.chip)),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              Text(label, style: AppText.s(12.5, W.w6, color: AppColors.white)),
              const AppIcon(AppIcons.close, size: 12, color: AppColors.white),
            ]),
          ),
        ),
      );
}
