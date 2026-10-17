import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/tooltip.dart';
import 'cp_common.dart';
import 'cp_model.dart';

/// Client profile → Activity tab (`.tp-act` on both boards): range picker, kind chips with counts, rows grouped by
/// day, "Showing 8 of 11" + Show more. Data: `activity/?client=<id>` (cursor paged, 8 at a time) and
/// `activity/counts/?client=<id>&by_day=1` for the chip and day counts.
class CpActivityTab extends StatefulWidget {
  const CpActivityTab(this.c, {super.key});
  final CpController c;
  @override
  State<CpActivityTab> createState() => _CpActivityTabState();
}

/// Board ranges → API `range`.
const _ranges = [('today', 'Today'), ('7d', 'Last 7 days'), ('30d', 'Last 30 days'), ('3m', 'Last 3 months'), ('all', 'All time')];

/// Board chips → API `kind` ('' = All).
const _kinds = [('', 'All'), ('workout', 'Workout'), ('meal', 'Meal'), ('checkin', 'Check-in'), ('body', 'Body'), ('plan', 'Plan'), ('content', 'Content')];

const _page = 8;

class _CpActivityTabState extends State<CpActivityTab> {
  String range = '7d', kind = '';
  List<Map> rows = [];
  Map counts = const {};
  String? cursor;
  bool loading = true, more = false;
  ApiError? error;
  int _seen = -1, _req = 0;

  CpController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _seen = c.version;
    c.addListener(_onController);
    _load();
  }

  @override
  void dispose() {
    c.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    if (c.version != _seen) {
      _seen = c.version;
      _load();
    }
  }

  Map<String, dynamic> get _q => {'client': c.id, 'range': range, if (kind.isNotEmpty) 'kind': kind};

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

  int _n(String k) => ((counts[k.isEmpty ? 'all' : k] as num?) ?? 0).toInt();

  String get _pron => switch ('${c.detail['gender']}') { 'female' => 'her', 'male' => 'his', _ => 'their' };

  @override
  Widget build(BuildContext context) {
    if (error != null && rows.isEmpty) return CpError(error!.message, onRetry: _load);
    final total = _n(kind);
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHeader(
            'Activity',
            sub: 'Everything ${c.first} and $_pron coaches did in the app',
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            action: Padding(padding: const EdgeInsets.only(left: 12), child: _rangeButton()),
          ),
          // Kind chips: one line, scrolls sideways.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Row(spacing: 6, children: [
              for (final (k, l) in _kinds)
                FilterChipX(l, selected: kind == k, count: _n(k), onTap: () {
                  if (kind == k) return;
                  setState(() => kind = k);
                  _load();
                }),
            ]),
          ),
          if (loading && rows.isEmpty)
            const CpLoading()
          else if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              child: Text('Nothing matches. Try a longer date range or fewer filters.', textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)),
            )
          else
            Opacity(opacity: loading ? .55 : 1, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _days())),
          if (rows.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
              child: Row(children: [
                Expanded(child: Text('Showing ${rows.length} of ${total < rows.length ? rows.length : total}', style: AppText.cap)),
                if (cursor != null) CpBtn32('Show more', loading: more, onTap: _more),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _rangeButton() {
    final label = _ranges.firstWhere((r) => r.$1 == range).$2;
    return Builder(
      builder: (b) => CpBtn32(
        label,
        icon: AppIcons.calendar,
        trailing: AppIcons.chevronDown,
        onTap: () => showAppMenu(b, [
          for (final (v, l) in _ranges)
            MenuEntry(l, selected: v == range, onTap: () {
              if (v == range) return;
              setState(() => range = v);
              _load();
            }),
        ]),
      ),
    );
  }

  // ─────────────────────────────── day groups

  List<Widget> _days() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final groups = <DateTime, List<Map>>{};
    for (final r in rows) {
      final t = cpParse(r['created_at']) ?? now;
      groups.putIfAbsent(DateTime(t.year, t.month, t.day), () => []).add(r);
    }
    final perDay = (counts['days'] as Map?) ?? const {};
    final out = <Widget>[];
    for (final MapEntry(key: d, value: items) in groups.entries) {
      final diff = today.difference(d).inDays;
      final label = diff == 0 ? 'Today' : (diff == 1 ? 'Yesterday' : DateFormat('EEE, d MMM').format(d));
      final n = (perDay[DateFormat('yyyy-MM-dd').format(d)] as num?)?.toInt() ?? items.length;
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Row(spacing: 6, children: [
          Text(label.toUpperCase(), style: AppText.s(11.5, W.w6, color: AppColors.muted, ls: .46)),
          Text('·', style: AppText.s(11.5, W.w5, color: AppColors.muted)),
          Text('${n < items.length ? items.length : n}', style: AppText.s(11.5, W.w5, color: AppColors.muted)),
        ]),
      ));
      out.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < items.length; i++) _ActRow(items[i], c: c, last: i == items.length - 1),
        ]),
      ));
    }
    return out;
  }
}

/// `.tp-tl-row`: round kind icon, "<b>who</b> verb", the change (old struck → new blue) or a note, time on the right
/// (hover shows where it came from: "Client · Android app").
class _ActRow extends StatelessWidget {
  const _ActRow(this.r, {required this.c, required this.last});
  final Map r;
  final CpController c;
  final bool last;

  static (AppIconData, Color, Color) look(String kind) => switch (kind) {
        'workout' => (AppIcons.dumbbell, AppColors.tlPlBg, AppColors.tlPlFg),
        'meal' => (AppIcons.bowl, AppColors.tlChBg, AppColors.tlChFg),
        'checkin' => (AppIcons.clipboardShort, AppColors.tlCiBg, AppColors.tlCiFg),
        'body' => (AppIcons.scale, AppColors.tlClBg, AppColors.tlClFg),
        'plan' => (AppIcons.edit, AppColors.tlPkBg, AppColors.tlPkFg),
        'content' => (AppIcons.play, AppColors.sub, AppColors.muted),
        'session' => (AppIcons.calendar, AppColors.sub, AppColors.muted),
        _ => (AppIcons.person, AppColors.sub, AppColors.muted),
      };

  String get _who {
    if ('${r['actor'] ?? ''}' == c.id) return c.first;
    final l = '${r['actor_label'] ?? ''}';
    return l.isEmpty ? 'Auto' : l;
  }

  /// The grey line under the title when there is no old → new change.
  String get _note {
    final meta = (r['meta'] as Map?) ?? const {};
    final note = '${meta['note'] ?? ''}';
    if (note.isNotEmpty) return note;
    final target = '${r['target_label'] ?? ''}';
    final verb = '${r['verb'] ?? ''}';
    final parts = <String>[];
    if (target.isNotEmpty && target != c.name && !verb.toLowerCase().contains(target.toLowerCase())) parts.add(target);
    if (meta['sets_planned'] is num && (meta['sets_planned'] as num) > 0) parts.add('${meta['sets_done']} of ${meta['sets_planned']} sets');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final (ic, bg, fg) = look('${r['kind']}');
    final from = '${r['change_from'] ?? ''}', to = '${r['change_to'] ?? ''}';
    final note = _note;
    final src = '${r['source'] ?? ''}';
    final time = Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(cpTime(r['created_at']), style: AppText.s(12, W.w5, color: AppColors.muted)),
    );
    return Stack(children: [
      if (!last)
        Positioned(left: 13, top: 34, bottom: 0, child: Container(width: 1.5, color: AppColors.line)),
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

/// `.btn.out` 32 high (range picker, Show more, Export).
class CpBtn32 extends StatelessWidget {
  const CpBtn32(this.label, {super.key, this.icon, this.trailing, this.onTap, this.loading = false});
  final String label;
  final AppIconData? icon, trailing;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) => Hover(
        onTap: loading ? null : onTap,
        builder: (_, h, _) => Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: h ? AppColors.outlineHover : AppColors.white,
            borderRadius: AppRadius.all(AppRadius.btn),
            border: Border.all(color: h ? AppColors.lineHover : AppColors.line2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 7, children: [
            if (loading)
              const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text))
            else if (icon != null)
              AppIcon(icon!, size: 16, color: AppColors.text),
            Text(label, style: AppText.button),
            if (trailing != null) AppIcon(trailing!, size: 14, color: AppColors.text),
          ]),
        ),
      );
}
