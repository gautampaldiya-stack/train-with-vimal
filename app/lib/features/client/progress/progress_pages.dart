import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/responsive.dart';
import '../food/food_model.dart' show DateUtils0;
import '../food/food_parts.dart' show fdTag;
import '../home/home_parts.dart' show ChCard;
import 'progress_model.dart';
import 'progress_parts.dart';
import 'progress_screen.dart' show fdCapPx, pxLoading, pxMRow;
import 'progress_sheets.dart';

/// The Progress sub pages (boards `ClientProgress` / `ClientProgressWeb`): History (`/progress/history`),
/// Progress photos (`/progress/photos`) and Compare (`/progress/compare?a=&b=&pose=`).

/// Page frame: phone padding, or the web column (max 1080) on the light page.
Widget pxPage(BuildContext context, List<Widget> children, {Widget? bottom, ScrollController? scroll}) {
  final phone = context.isPhone;
  final body = SingleChildScrollView(
    controller: scroll,
    padding: phone ? const EdgeInsets.fromLTRB(16, 6, 16, 20) : const EdgeInsets.fromLTRB(32, 32, 32, 72),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 12 : 16, children: children),
      ),
    ),
  );
  final page = bottom == null
      ? body
      : Column(children: [
          Expanded(child: body),
          Padding(
            padding: phone ? const EdgeInsets.fromLTRB(16, 0, 16, 12) : const EdgeInsets.fromLTRB(32, 0, 32, 12),
            child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1080), child: bottom)),
          ),
        ]);
  return phone ? page : CaWeb(web: true, child: page);
}

/// `px-back` + `fd-top` (pulled up 6 like the board).
List<Widget> pxHeader(String back, VoidCallback onBack, String title, String sub, {List<Widget> actions = const []}) => [
  PxBack(back, onBack),
  Transform.translate(offset: const Offset(0, -6), child: PxTop(title, sub, actions: actions)),
];

/// `px-stick`: the child keeps to the top of the scroll view while its column scrolls past.
class PxSticky extends StatefulWidget {
  const PxSticky({super.key, required this.child});
  final Widget child;
  @override
  State<PxSticky> createState() => _PxStickyState();
}

class _PxStickyState extends State<PxSticky> {
  final _key = GlobalKey();
  ScrollPosition? _pos;
  double _dy = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = Scrollable.maybeOf(context)?.position;
    if (p != _pos) {
      _pos?.removeListener(_move);
      _pos = p?..addListener(_move);
    }
  }

  @override
  void dispose() {
    _pos?.removeListener(_move);
    super.dispose();
  }

  void _move() {
    final me = context.findRenderObject() as RenderBox?, view = Scrollable.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    final child = _key.currentContext?.findRenderObject() as RenderBox?;
    if (me == null || view == null || child == null || !me.hasSize) return;
    final top = me.localToGlobal(Offset.zero, ancestor: view).dy;
    final dy = (-top).clamp(0.0, math.max(0.0, me.size.height - child.size.height)).toDouble();
    if (dy != _dy) setState(() => _dy = dy);
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    // A Column lets the card keep its own height inside the stretched column.
    child: Transform.translate(
      offset: Offset(0, _dy),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [KeyedSubtree(key: _key, child: widget.child)]),
    ),
  );
}

// ─────────────────────────────── History

class ProgressHistoryScreen extends StatefulWidget {
  const ProgressHistoryScreen({super.key, this.type, this.range});
  final String? type, range;
  @override
  State<ProgressHistoryScreen> createState() => _ProgressHistoryScreenState();
}

class _ProgressHistoryScreenState extends State<ProgressHistoryScreen> {
  late final h = HistoryController(type: HistoryController.types.any((t) => t.$1 == widget.type) ? widget.type : null);

  @override
  void initState() {
    super.initState();
    if (HistoryController.ranges.any((r) => r.$1 == widget.range)) h.range = widget.range!;
    h.load();
  }

  @override
  void dispose() {
    h.dispose();
    super.dispose();
  }

  static const _icons = {'workout': AppIcons.dumbbell, 'meal': AppIcons.food, 'checkin': AppIcons.clipboard, 'weight': pxScale};

  String get _rangeLbl {
    final f = h.from, t = h.to;
    if (f == null || t == null) return '';
    return '${pxDm(f)} – ${DateFormat('d MMM y').format(t)}';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: h,
    builder: (context, _) {
      final web = !context.isPhone;
      final ri = HistoryController.ranges.indexWhere((r) => r.$1 == h.range);
      final head = [
        ...pxHeader('Progress', () => context.go('/progress'), 'History', 'All your logs in one place${_rangeLbl.isEmpty ? '' : ' · $_rangeLbl'}'),
        PxTabs(
          labels: [for (final r in HistoryController.ranges) r.$2],
          index: ri,
          onPick: (i) => h.setRange(HistoryController.ranges[i].$1),
        ),
        Transform.translate(
          offset: Offset(0, web ? -6 : -4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(spacing: 6, children: [
              for (final (k, n) in HistoryController.types)
                PxChip(n, icon: k == null ? null : _icons[k], small: true, on: h.type == k, onTap: () => h.setType(k)),
            ]),
          ),
        ),
      ];
      if (h.loading && h.days.isEmpty || h.error != null && h.days.isEmpty) {
        return pxPage(context, [...head, SizedBox(height: 240, child: pxLoading(h.loading ? null : h.error, h.load, 'your history'))]);
      }
      final sum = _summary();
      final days = _days();
      if (!web) return pxPage(context, [...head, sum, ...days]);
      // Web: the top (title, range tabs, chips) and the summary on the right stay put; only the day list
      // scrolls (Gautam 2026-10-16).
      return CaWeb(
        web: true,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1144),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: head),
              ),
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(32, 0, 20, 48),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: days),
                    ),
                  ),
                  Padding(padding: const EdgeInsets.only(right: 32), child: SizedBox(width: 340, child: SingleChildScrollView(padding: const EdgeInsets.only(bottom: 24), child: sum))),
                ]),
              ),
            ]),
          ),
        ),
      );
    },
  );

  Widget _summary() {
    final s = h.summary;
    num? n(String k) => s[k] as num?;
    final wf = n('weight_from'), wt = n('weight_to');
    final fmt = NumberFormat('#,##0');
    final cells = [
      ('Workouts done', '${n('workouts_done') ?? 0}/${n('workouts_planned') ?? 0}', 'sessions'),
      ('Avg calories', n('avg_kcal') == null ? '—' : fmt.format(n('avg_kcal')), n('kcal_target') == null ? 'kcal' : '/ ${fmt.format(n('kcal_target'))} kcal'),
      ('Avg protein', n('avg_protein') == null ? '—' : '${n('avg_protein')!.round()} g', n('protein_target') == null ? '' : '/ ${n('protein_target')!.round()} g'),
      (
        'Weight change',
        wf != null && wt != null ? pxChg(wt.toDouble() - wf.toDouble(), 'kg') : '—',
        wf != null && wt != null ? '${pxK1(wf.toDouble())} → ${pxK1(wt.toDouble())}' : 'not enough weigh-ins',
      ),
    ];
    final rl = HistoryController.ranges.firstWhere((r) => r.$1 == h.range).$2;
    return ChCard(gap: 10, children: [
      Row(spacing: 8, children: [
        Text('SUMMARY', style: AppText.s(11, W.w8, ls: .66, color: AppColors.muted)),
        Expanded(child: Text('$rl · ${n('days') ?? 0} days', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7))),
        if (n('adherence') != null) pxPill('${n('adherence')}% adherence', PxTone.green),
      ]),
      for (var r = 0; r < 2; r++)
        Row(spacing: 8, children: [
          for (final (l, v, u) in cells.sublist(r * 2, r * 2 + 2))
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w7, color: AppColors.muted)),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: v, style: AppText.s(16, W.w8)),
                      if (u.isNotEmpty) TextSpan(text: '  $u', style: AppText.s(11.5, W.w4, color: AppColors.muted)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
            ),
        ]),
    ]);
  }

  List<Widget> _days() {
    final today = DateUtils0.dateOnly(DateTime.now());
    final tName = (HistoryController.types.firstWhere((t) => t.$1 == h.type, orElse: () => (null, 'logs')).$2).toLowerCase();
    final showScore = h.type == null || h.type == 'workout' || h.type == 'meal';
    if (h.days.isEmpty) {
      return [
        ChCard(gap: 6, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22), children: [
          Center(
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(10)),
              child: const AppIcon(AppIcons.clock, size: 17, color: AppColors.muted),
            ),
          ),
          Text('No ${h.type == null ? 'logs' : tName} in this range', textAlign: TextAlign.center, style: AppText.s(15, W.w7)),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text('Nothing was logged in this range. Try a longer range or show every type.',
                  textAlign: TextAlign.center, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
            ),
          ),
          if (h.range != '3months' || h.type != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(spacing: 8, children: [
                if (h.range != '3months') Expanded(child: CaButton('Try 3 months', kind: CaBtnKind.out, small: true, onPressed: () => h.setRange('3months'))),
                if (h.type != null) Expanded(child: CaButton('Show all types', kind: CaBtnKind.out, small: true, onPressed: () => h.setType(null))),
              ]),
            ),
        ]),
      ];
    }
    final left = h.count - h.days.length;
    final rl = HistoryController.ranges.firstWhere((r) => r.$1 == h.range).$2;
    return [
      for (final d in h.days)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(children: [
              Text(pxWdm(d.date), style: AppText.s(13.5, W.w8)),
              if (DateUtils0.same(d.date, today)) Padding(padding: const EdgeInsets.only(left: 8), child: fdTag('Today')),
              if (DateUtils0.same(d.date, today.subtract(const Duration(days: 1)))) Padding(padding: const EdgeInsets.only(left: 8), child: fdTag('Yesterday')),
              const Spacer(),
              if (showScore && d.score != null)
                Text('${d.score}%',
                    style: AppText.s(12, W.w8, color: d.score! >= 90 ? AppColors.okText : (d.score! < 75 ? AppColors.amberText : AppColors.text2))),
            ]),
          ),
          Semantics(
            button: true,
            label: 'Open ${pxWdm(d.date)}',
            child: Hover(
              onTap: () => showHistoryDay(context, d),
              builder: (_, hv, _) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: hv ? AppColors.line2 : AppColors.line),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final (i, e) in d.entries.indexed) PxEntryRow(e, first: i == 0),
                ]),
              ),
            ),
          ),
        ]),
      if (left > 0)
        Center(
          child: CaButton(
            'Show ${math.min(10, left)} more days · $left left',
            kind: CaBtnKind.out,
            expand: false,
            loading: h.loadingMore,
            onPressed: () => h.load(more: true),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('That’s everything for ${rl == 'This week' ? 'this week' : 'the last ${rl.toLowerCase()}'}',
              textAlign: TextAlign.center, style: AppText.s(12, W.w6, color: AppColors.muted)),
        ),
    ];
  }
}

// ─────────────────────────────── Progress photos

class ProgressPhotosScreen extends StatefulWidget {
  const ProgressPhotosScreen({super.key});
  @override
  State<ProgressPhotosScreen> createState() => _ProgressPhotosScreenState();
}

class _ProgressPhotosScreenState extends State<ProgressPhotosScreen> {
  final c = ProgressController();
  String _pose = 'Front';
  List<String>? _pick; // set ids, oldest first (A, B)

  @override
  void initState() {
    super.initState();
    c.start();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  List<String> _picks(PxData d) {
    final ids = d.sets.map((s) => s.id).toList();
    final p = (_pick ?? [if (ids.isNotEmpty) ids.first, if (ids.length > 1) ids.last]).where(ids.contains).toList();
    p.sort((a, b) => ids.indexOf(a).compareTo(ids.indexOf(b)));
    return p;
  }

  void _toggle(PxData d, String id) {
    final p = _picks(d);
    if (p.contains(id)) {
      p.remove(id);
    } else {
      if (p.length >= 2) p.removeAt(0);
      p.add(id);
    }
    setState(() => _pick = p);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final d = c.data;
      if (d == null) return pxLoading(c.error, c.load, 'your photos');
      final web = !context.isPhone;
      final sets = d.sets;
      final n = sets.fold(0, (a, s) => a + s.photos.length);
      final pick = _picks(d);
      final byId = {for (final s in sets) s.id: s};
      final latest = sets.lastOrNull;
      final todaySet = latest != null && DateUtils0.same(latest.date, c.today) ? latest : null;

      // Month groups, newest first.
      final months = <(String, List<PxSet>)>[];
      for (final s in sets.reversed) {
        final k = DateFormat('MMMM y').format(s.date);
        if (months.isEmpty || months.last.$1 != k) months.add((k, []));
        months.last.$2.add(s);
      }

      Widget tile(PxSet s) {
        final pk = pick.indexOf(s.id);
        return Semantics(
          button: true,
          selected: pk >= 0,
          label: '${pxWdm(s.date)} set',
          child: Hover(
            onTap: () => _toggle(d, s.id),
            builder: (_, h, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: PxTile(set: s, pose: _pose, label: _pose, badge: pk < 0 ? null : 'AB'[pk], badgeAccent: true, selected: pk >= 0),
              ),
              Text(pxWdm(s.date), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w8, color: h ? AppColors.accentText : AppColors.text)),
              Text([if (s.kg != null) pxAmt(s.kg!, 'kg'), s.label].join(' · '), style: AppText.s(11, W.w4, color: AppColors.muted, h: 1.3)),
            ]),
          ),
        );
      }

      Widget grid(List<PxSet> list) => LayoutBuilder(builder: (_, b) {
        final gap = web ? 12.0 : 8.0;
        // Phone: 3 a row. Web: as many 140–160 wide as fit, left aligned.
        final cols = web ? math.max(1, ((b.maxWidth + gap) / (140 + gap)).floor()) : 3;
        final w = web ? math.min(160.0, (b.maxWidth - gap * (cols - 1)) / cols) : (b.maxWidth - gap * 2) / 3;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final s in list) SizedBox(width: w, child: tile(s))]);
      });

      final ready = pick.length == 2;
      final a = ready ? byId[pick[0]]! : null, b = ready ? byId[pick[1]]! : null;
      final selText = ready
          ? '${pxDm(a!.date)} vs ${pxDm(b!.date)}${a.kg != null && b.kg != null ? ' · ${pxChg(b.kg! - a.kg!, 'kg')}' : ''}'
          : (pick.isEmpty ? 'Tap two sets to compare' : 'Pick one more set');
      final cmpBtn = Opacity(
        opacity: ready ? 1 : .45,
        child: CaButton('Compare', icon: AppIcons.photo, small: true, expand: false, onPressed: () {
          if (!ready) {
            showPxToast(context, 'Pick two sets first', 'Tap two photos in the timeline');
            return;
          }
          context.go('/progress/compare?a=${a!.id}&b=${b!.id}&pose=$_pose');
        }),
      );
      final tabs = PxTabs(labels: pxPoses, index: pxPoses.indexOf(_pose), onPick: (i) => setState(() => _pose = pxPoses[i]));
      // Compare sits at the top, right of the pose tabs (Gautam 2026-10-16), not in a bar at the bottom.
      final pickRow = web
          ? Row(spacing: 12, children: [
              tabs,
              const Spacer(),
              if (sets.length > 1)
                Column(crossAxisAlignment: CrossAxisAlignment.end, spacing: 1, children: [
                  Text('${pick.length} of 2 selected', style: AppText.s(13, W.w7)),
                  Text(selText, style: AppText.s(12, W.w4, color: AppColors.muted)),
                ]),
              if (sets.length > 1) cmpBtn,
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
              Row(spacing: 8, children: [tabs, const Spacer(), if (sets.length > 1) cmpBtn]),
              if (sets.length > 1) Text('${pick.length} of 2 selected · $selText', style: AppText.s(12, W.w6, color: AppColors.muted)),
            ]);

      return pxPage(
        context,
        [
          ...pxHeader(
            'Progress',
            () => context.go('/progress'),
            'Progress photos',
            sets.isEmpty ? 'No photos yet' : '${sets.length} ${sets.length == 1 ? 'set' : 'sets'} · $n ${n == 1 ? 'photo' : 'photos'} · since ${pxDm(sets.first.date)}',
            actions: [CaButton('Add photos', kind: CaBtnKind.out, small: true, expand: false, icon: AppIcons.camera, onPressed: () => showAddPhotos(context, c, pose: _pose))],
          ),
          pickRow,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(10)),
            child: Row(spacing: 8, children: [
              const AppIcon(AppIcons.lock, size: 15, color: AppColors.infoText),
              Expanded(child: Text('Only you and Coach ${d.coach} can see these. Tap two sets to compare.', style: AppText.s(12.5, W.w6, color: AppColors.infoText))),
            ]),
          ),
          for (final (m, list) in months)
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 8, children: [
                Text(m, style: AppText.s(14, W.w8)),
                Text('${list.length} ${list.length == 1 ? 'set' : 'sets'}', style: AppText.s(12, W.w6, color: AppColors.muted)),
              ]),
              grid(list),
            ]),
          ChCard(padding: const EdgeInsets.all(12), children: [
            Row(spacing: 10, children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.icAmberBg, borderRadius: BorderRadius.circular(10)),
                child: const AppIcon(AppIcons.camera, size: 17, color: AppColors.icAmberText),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text(todaySet != null ? 'Today’s set · ${todaySet.photos.length} of 3 poses added' : 'Next set due ${pxWdm(d.nextPhotos)}', style: AppText.s(13.5, W.w7)),
                  Text('Same spot, same light, in the morning before eating', style: AppText.s(12, W.w4, color: AppColors.muted)),
                ]),
              ),
              CaButton('Add', kind: CaBtnKind.out, small: true, expand: false, onPressed: () => showAddPhotos(context, c, pose: _pose)),
            ]),
          ]),
          if (sets.isEmpty) fdCapPx('Your first photo set shows here. Add a front, side and back photo.'),
        ],
      );
    },
  );
}

// ─────────────────────────────── Compare

class ProgressCompareScreen extends StatefulWidget {
  const ProgressCompareScreen({super.key, this.a, this.b, this.pose});
  final String? a, b, pose;
  @override
  State<ProgressCompareScreen> createState() => _ProgressCompareScreenState();
}

class _ProgressCompareScreenState extends State<ProgressCompareScreen> {
  final c = ProgressController();
  late String _pose = pxPoses.contains(widget.pose) ? widget.pose! : 'Front';
  int? _a, _b;

  @override
  void initState() {
    super.initState();
    c.start();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final d = c.data;
      if (d == null) return pxLoading(c.error, c.load, 'your photos');
      final sets = d.sets;
      final back = pxHeader('Timeline', () => context.go('/progress/photos'), 'Compare', 'Pick two photo sets');
      if (sets.length < 2) {
        return pxPage(context, [
          ...back,
          ChCard(children: [
            const PxHead('Add a second photo set first', 'Then compare it with your first one'),
            CaButton('Add photos', icon: AppIcons.camera, small: true, onPressed: () => showAddPhotos(context, c)),
          ]),
        ]);
      }
      int at(String? id, int fallback) {
        final i = sets.indexWhere((s) => s.id == id);
        return i < 0 ? fallback : i;
      }

      var ai = (_a ?? at(widget.a, 0)).clamp(0, sets.length - 2);
      var bi = (_b ?? at(widget.b, sets.length - 1)).clamp(0, sets.length - 1);
      if (bi <= ai) bi = math.min(sets.length - 1, ai + 1);
      final a = sets[ai], b = sets[bi];
      final days = b.date.difference(a.date).inDays;
      final web = !context.isPhone;

      void move(bool isB, int i, int step, bool ok) {
        if (!ok) return;
        setState(() {
          _a = isB ? ai : i + step;
          _b = isB ? i + step : bi;
        });
      }

      Widget side(PxSet s, int i, String letter, bool acc) {
        final lo = acc ? ai + 1 : 0, hi = acc ? sets.length - 1 : bi - 1;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: web ? 520 : double.infinity),
            child: PxTile(set: s, pose: _pose, badge: letter, badgeAccent: acc, label: '${pxDm(s.date)} · $_pose', figure: .40),
          ),
          Row(spacing: 4, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text(pxWdm(s.date), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w8)),
                Text([if (s.kg != null) pxAmt(s.kg!, 'kg'), s.shortLabel].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11, W.w4, color: AppColors.muted)),
              ]),
            ),
            Opacity(
              opacity: i > lo ? 1 : .45,
              child: CaIconBtn(AppIcons.chevronLeft, size: 30, tooltip: 'Earlier set', onTap: () => move(acc, i, -1, i > lo)),
            ),
            Opacity(
              opacity: i < hi ? 1 : .45,
              child: CaIconBtn(AppIcons.chevronRight, size: 30, tooltip: 'Later set', onTap: () => move(acc, i, 1, i < hi)),
            ),
          ]),
        ]);
      }

      final ma = d.measureAt(a.date), mb = d.measureAt(b.date);
      final rows = <(String, String, String, String, bool?)>[
        if (a.kg != null && b.kg != null) _row('Weight', 'kg', a.kg!, b.kg!),
        for (final m in d.metrics)
          if (ma?.of(m) != null && mb?.of(m) != null) pxMRow(m, ma!.of(m)!, mb!.of(m)!),
      ];
      final sum = rows.isEmpty
          ? 'No measurements near these dates yet.'
          : 'In $days ${days == 1 ? 'day' : 'days'}: ${rows.take(3).map((r) => '${r.$1.toLowerCase()} ${r.$4}').join(', ')}.';
      final photos = Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: web ? 16 : 10, children: [
        Expanded(child: side(a, ai, 'A', false)),
        Expanded(child: side(b, bi, 'B', true)),
      ]);
      final table = ChCard(children: [
        PxHead('Measurements', '$days ${days == 1 ? 'day' : 'days'} apart · measured on the nearest check-in'),
        if (rows.isNotEmpty) PxTable(heads: (pxDm(a.date), pxDm(b.date)), rows: rows),
        fdCapPx(sum),
      ]);
      return pxPage(context, [
        ...pxHeader('Timeline', () => context.go('/progress/photos'), 'Compare', '$_pose · ${pxDm(a.date)} → ${pxDm(b.date)}'),
        PxTabs(labels: pxPoses, index: pxPoses.indexOf(_pose), onPick: (i) => setState(() => _pose = pxPoses[i])),
        if (web)
          LayoutBuilder(
            builder: (_, bx) => bx.maxWidth >= 860
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
                    SizedBox(width: 540, child: photos),
                    Expanded(child: table),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [photos, table]),
          )
        else ...[
          photos,
          table,
        ],
      ]);
    },
  );

  (String, String, String, String, bool?) _row(String m, String u, double a, double b) =>
      (m, pxAmt(a, u), pxAmt(b, u), pxChg(b - a, u), b < a ? true : (b > a ? false : null));
}
