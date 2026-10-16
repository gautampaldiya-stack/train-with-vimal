import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/media.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../home/home_parts.dart';
import 'body_map_svg.dart';
import 'train_model.dart';

/// Pieces shared by the Train tab and the workout logger: exercise tile, exercise guide with the
/// body map, and the Past workouts sheet.

/// `tn-th`: 42px tile, blue for cardio, green for lifts, amber for timed holds. When the exercise has
/// a video or picture its still is shown instead of the icon, with a small play mark for videos.
class ExThumb extends StatelessWidget {
  const ExThumb(this.kind, {super.key, this.thumb, this.video = false});
  final ExKind kind;
  final String? thumb;
  final bool video;
  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (kind) {
      ExKind.cardio => (AppColors.tnBlueBg, AppColors.accentText, AppIcons.run),
      ExKind.weight => (AppColors.okBg, AppColors.okText, AppIcons.dumbbell),
      ExKind.time => (AppColors.amberBg, AppColors.amberText, AppIcons.clock),
    };
    final plain = Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
      child: AppIcon(icon, size: 20, color: fg),
    );
    final url = thumb;
    if (url == null) {
      if (!video) return plain;
      return Stack(clipBehavior: Clip.none, children: [
        plain,
        Positioned(
          right: -3,
          bottom: -3,
          child: Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.text.withValues(alpha: .7), shape: BoxShape.circle, border: Border.all(color: AppColors.white, width: 1.5)),
            child: const AppIcon(AppIcons.play, size: 9, color: AppColors.white, fill: true),
          ),
        ),
      ]);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: SizedBox(
        width: 42,
        height: 42,
        child: Stack(fit: StackFit.expand, children: [
          Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => plain),
          if (video)
            Center(
              child: Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.text.withValues(alpha: .55), shape: BoxShape.circle),
                child: const AppIcon(AppIcons.play, size: 10, color: AppColors.white),
              ),
            ),
        ]),
      ),
    );
  }
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// `bm`: front and back figure with the worked muscles filled, and the legend.
class BodyMap extends StatelessWidget {
  const BodyMap(this.regions, {super.key});
  final Map<String, String> regions;

  String _svg(String body) {
    var s = body.replaceAll('{base}', _hex(AppColors.barTrack)).replaceAll('{edge}', _hex(AppColors.caWebBg));
    for (final r in const ['chest', 'shoulders', 'biceps', 'triceps', 'forearms', 'abs', 'obliques', 'traps', 'back', 'lowback', 'glutes', 'quads', 'hamstrings', 'calves']) {
      final c = switch (regions[r]) { 'p' => AppColors.accent, 's' => AppColors.bmStrong, 'l' => AppColors.bmLight, _ => AppColors.bmOff };
      s = s.replaceAll('{$r}', _hex(c));
    }
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 244">$s</svg>';
  }

  @override
  Widget build(BuildContext context) {
    Widget fig(String body, String cap) => Column(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
          SizedBox(width: 102, height: 208, child: SvgPicture.string(_svg(body))),
          Text(cap, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
        ]);
    Widget key(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          Text(t, style: AppText.s(11.5, W.w6, color: AppColors.text2)),
        ]);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppColors.caWebBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
      child: Column(mainAxisSize: MainAxisSize.min, spacing: 10, children: [
        Row(mainAxisSize: MainAxisSize.min, spacing: 14, children: [fig(bodyFront, 'Front'), fig(bodyBack, 'Back')]),
        Row(mainAxisSize: MainAxisSize.min, spacing: 10, children: [key(AppColors.accent, 'Primary'), key(AppColors.bmStrong, 'Strong'), key(AppColors.bmLight, 'Light')]),
      ]),
    );
  }
}

// ─────────────────────────────── Exercise guide (`cg`)

class GuideInfo {
  const GuideInfo({required this.context, required this.program, required this.coachFirst, required this.coachInitials});
  final String context, program, coachFirst, coachInitials;
}

/// Phone: a full page over the app with a back button. Wider: a 980 wide two-column dialog.
Future<void> showGuide(BuildContext context, TrainEx e, GuideInfo g) {
  if (context.isPhone) {
    return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, _, _) => _GuidePage(e: e, g: g, web: false),
      transitionsBuilder: (_, a, _, child) => SlideTransition(
        position: Tween(begin: const Offset(0, .04), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: FadeTransition(opacity: a, child: child),
      ),
    ));
  }
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Exercise guide',
    barrierColor: AppColors.scrimSheet,
    transitionDuration: const Duration(milliseconds: 140),
    transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (ctx, _, _) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 980, maxHeight: MediaQuery.sizeOf(ctx).height * .88),
          // The shadow sits outside the clipped card: inside it painted a dark band over the page.
          child: DecoratedBox(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.guide),
            child: Material(
              color: AppColors.caWebBg,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
              child: CaWeb(web: true, child: _GuidePage(e: e, g: g, web: true)),
            ),
          ),
        ),
      ),
    ),
  );
}

class _GuidePage extends StatelessWidget {
  const _GuidePage({required this.e, required this.g, required this.web});
  final TrainEx e;
  final GuideInfo g;
  final bool web;

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).pop();
    final top = Container(
      padding: web ? const EdgeInsets.symmetric(horizontal: 20, vertical: 14) : const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: web ? const BoxDecoration(color: AppColors.white, border: Border(bottom: BorderSide(color: AppColors.line))) : null,
      child: Row(spacing: 10, children: [
        if (!web) CaIconBtn(AppIcons.chevronLeft, onTap: close, tooltip: 'Back'),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Exercise guide', style: AppText.s(14, W.w8)),
            Text(g.context, style: AppText.s(12, W.w4, color: AppColors.muted)),
          ]),
        ),
        if (web) CaIconBtn(AppIcons.close, onTap: close, tooltip: 'Close'),
      ]),
    );
    final head = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(e.name, style: AppText.s(23, W.w8, ls: -0.23)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final t in [e.muscleLabel, e.equipmentLabel, e.levelLabel].where((t) => t.isNotEmpty))
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(7), border: Border.all(color: AppColors.line)),
            child: Center(widthFactor: 1, child: Text(t, style: AppText.s(12.5, W.w6))),
          ),
      ]),
    ]);
    final video = e.media != null || e.youtube.isNotEmpty ? _video(context) : null;
    final note = e.note.isEmpty ? null : _note();
    final target = _target();
    final details = _details();
    final how = e.howTo.isEmpty ? null : _how();
    final cues = e.cues.isEmpty ? null : _cues();
    final muscles = _muscles();
    final gap = web ? 14.0 : 12.0;
    final body = web
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 14, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [?video, ?note, target, details])),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [?how, ?cues, muscles])),
          ])
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [?video, ?note, target, ?how, ?cues, muscles, details]);
    final scroll = SingleChildScrollView(
      padding: web ? const EdgeInsets.fromLTRB(20, 18, 20, 22) : const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: gap, children: [head, body]),
    );
    if (web) return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [top, Flexible(child: scroll)]);
    return Scaffold(
      backgroundColor: AppColors.caBg,
      body: SafeArea(bottom: false, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [top, Expanded(child: scroll)])),
    );
  }

  Widget _card(List<Widget> kids) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: kids),
      );

  Widget _h(String t, [String? count]) => Row(spacing: 6, children: [
        Text(t, style: AppText.s(15, W.w8)),
        if (count != null) Text(count, style: AppText.s(12, W.w7, color: AppColors.muted)),
      ]);

  Widget _video(BuildContext context) => _GuideMedia(e: e, web: web);

  Widget _note() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: AppColors.noteBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.noteLine)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          ChAvatar(g.coachInitials, green: true),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Note from ${g.coachFirst}', style: AppText.s(12, W.w7, color: AppColors.sessText)),
              Padding(padding: const EdgeInsets.only(top: 2, bottom: 4), child: Text(e.note, style: AppText.s(14, W.w4, h: 1.5))),
              Text('On this exercise in ${g.program}', style: AppText.s(11.5, W.w4, color: AppColors.muted)),
            ]),
          ),
        ]),
      );

  Widget _target() => _card([
        _h('Today’s target'),
        Row(spacing: 8, children: [
          for (final (v, l) in e.tiles)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(10)),
                child: Column(spacing: 1, children: [
                  Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(18, W.w8)),
                  Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
                ]),
              ),
            ),
        ]),
        if (e.extra.isNotEmpty) Text(e.extra, style: AppText.s(13, W.w4, color: AppColors.text2)),
        Pull(top: 4, child: Text('Last time: ${e.lastText}${e.prText.isEmpty ? '' : ' · PR ${e.prText}'}', style: AppText.s(12, W.w4, color: AppColors.muted))),
      ]);

  Widget _details() {
    final rows = [
      ('Muscle group', e.muscleLabel),
      ('Equipment', e.equipmentLabel),
      ('Level', e.levelLabel),
      ('You log', e.logsLabel),
      ('Video / picture', switch (e.mediaKind) {
        'video' => e.mediaSeconds > 0 ? 'Video · ${clockText(e.mediaSeconds)}' : 'Video',
        'image' => 'Picture',
        'youtube' => 'YouTube video',
        _ => e.youtube.isNotEmpty ? 'YouTube video' : 'Not added yet',
      }),
    ];
    return _card([
      _h('Details'),
      Column(children: [
        for (final (i, (k, v)) in rows.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            child: Row(spacing: 10, children: [
              Expanded(child: Text(k, style: AppText.s(13, W.w4, color: AppColors.muted))),
              Text(v, textAlign: TextAlign.right, style: AppText.s(13, W.w7)),
            ]),
          ),
      ]),
    ]);
  }

  Widget _how() => _card([
        _h('How to', '${e.howTo.length}'),
        for (final (i, t) in e.howTo.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
            child: Row(spacing: 10, children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.sub, shape: BoxShape.circle),
                child: Text('${i + 1}', style: AppText.s(12, W.w8, color: AppColors.text2)),
              ),
              Expanded(child: Text(t, style: AppText.s(13.5, W.w4, h: 1.45))),
            ]),
          ),
      ]);

  Widget _cues() => _card([
        _h('Form cues', '${e.cues.length}'),
        for (final t in e.cues)
          Row(spacing: 10, children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
              child: const AppIcon(AppIcons.check, size: 13, color: AppColors.accent, stroke: 2.6),
            ),
            Expanded(child: Text(t, style: AppText.s(13.5, W.w4, h: 1.45))),
          ]),
      ]);

  Widget _muscles() {
    Widget over(String t, {Color color = AppColors.muted}) => Text(t.toUpperCase(), style: AppText.s(11, W.w8, color: color, ls: .55));
    final list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.noteLine)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
          over('Primary muscle', color: AppColors.accentText),
          Text(e.primary.isEmpty ? e.muscleLabel : e.primary, style: AppText.s(16, W.w8)),
          Text(e.muscleLabel, style: AppText.s(12, W.w4, color: AppColors.text2)),
        ]),
      ),
      if (e.also.isNotEmpty) over('Also works'),
      for (final (m, lv) in e.also)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
          child: Row(spacing: 10, children: [
            Expanded(child: Text(m, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7))),
            Row(spacing: 3, children: [
              for (final on in [true, lv == 'Strong', false])
                Container(width: 14, height: 5, decoration: BoxDecoration(color: on ? AppColors.accent : AppColors.metOff, borderRadius: BorderRadius.circular(3))),
            ]),
            SizedBox(width: 44, child: Text(lv, style: AppText.s(12, W.w7, color: AppColors.text2))),
          ]),
        ),
    ]);
    return _card([
      _h('Muscles'),
      // Side by side only when the list keeps room for names ("Lower back" broke into letters).
      LayoutBuilder(
        builder: (_, box) => web && box.maxWidth >= 520
            ? IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
                  Expanded(child: list),
                  BodyMap(e.map),
                ]),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [list, BodyMap(e.map)]),
      ),
    ]);
  }
}

// ─────────────────────────────── Past workouts (`pw-*`)

/// History sheet. [thisName] adds the "this workout only" filter (named like today's workout).
Future<void> showPastWorkouts(BuildContext context, {String? thisName, bool startThis = false}) =>
    showFixedSheet(context, (ctx) => _PastSheet(thisName: thisName, startThis: startThis));

/// Logger → Past workouts: only this exercise, newest first, with its sets. "Use these sets"
/// fills the sets not ticked yet ([onUse]); the whole-workout view stays on the Train screen.
Future<void> showExerciseHistory(BuildContext context, TrainEx e, {required void Function(List<Map<String, dynamic>> sets, String from) onUse}) =>
    showFixedSheet(context, (ctx) => _ExHistorySheet(e: e, onUse: onUse));

class _ExHistorySheet extends StatefulWidget {
  const _ExHistorySheet({required this.e, required this.onUse});
  final TrainEx e;
  final void Function(List<Map<String, dynamic>> sets, String from) onUse;
  @override
  State<_ExHistorySheet> createState() => _ExHistorySheetState();
}

class _ExHistorySheetState extends State<_ExHistorySheet> {
  final _rows = <Map<String, dynamic>>[];
  int _page = 0, _count = 0;
  String? _next, _error;
  bool _loading = false, _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final j = await Services.api.get<Map<String, dynamic>>('me/workouts/exercise-history/', query: {'exercise': widget.e.exId, 'page': _page + 1, 'page_size': 20});
      _page += 1;
      _count = (j['count'] as num?)?.toInt() ?? 0;
      _next = j['next'] as String?;
      _rows.addAll([for (final r in (j['results'] as List? ?? const [])) (r as Map).cast<String, dynamic>()]);
      _error = null;
    } on ApiError catch (e) {
      _error = e.offline ? 'You are offline. Connect to see your past sets.' : 'Could not load your past sets. Try again.';
    } finally {
      _loaded = true;
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.e;
    final sub = !_loaded ? 'Loading…' : '$_count ${_count == 1 ? 'workout' : 'workouts'} with this exercise';
    Widget body;
    if (!_loaded) {
      body = const Padding(padding: EdgeInsets.all(24), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))));
    } else if (_rows.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(_error ?? 'You have not done ${e.name} yet. Your sets show here after the first time.', textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)),
      );
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, r) in _rows.indexed) _row(i, r),
          ]),
        ),
        if (_next != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: CaButton('Show more', kind: CaBtnKind.out, small: true, loading: _loading, onPressed: _load),
          ),
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text(e.name, style: AppText.s(17, W.w8, ls: -0.2)),
              Text(sub, style: AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.4)),
            ]),
          ),
          SheetClose(onTap: () => Navigator.of(context).pop()),
        ]),
      ),
      Flexible(child: SingleChildScrollView(child: body)),
    ]);
  }

  Widget _row(int i, Map<String, dynamic> r) {
    final e = widget.e;
    final date = DateTime.tryParse('${r['date']}') ?? DateTime.now();
    final sets = [for (final s in (r['sets'] as List? ?? const [])) (s as Map).cast<String, dynamic>()];
    final from = i == 0 ? 'last time' : DateFormat('d MMM').format(date);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        Row(spacing: 12, children: [
          Container(
            width: 48,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(9)),
            child: Column(children: [
              Text(DateFormat('d MMM').format(date), maxLines: 1, style: AppText.s(13, W.w7, h: 1.2)),
              Text(DateFormat('EEE').format(date), style: AppText.s(10.5, W.w6, color: AppColors.muted)),
            ]),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text('${r['name'] ?? 'Workout'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7)),
              Text('${sets.length} ${sets.length == 1 ? 'set' : 'sets'}${i == 0 ? ' · last time' : ''}', style: AppText.s(12, W.w4, color: AppColors.muted)),
            ]),
          ),
          CaButton('Use these sets', small: true, expand: false, kind: CaBtnKind.out, icon: AppIcons.restart, onPressed: sets.isEmpty
              ? null
              : () {
                  Navigator.of(context).pop();
                  widget.onUse(sets, from);
                }),
        ]),
        Wrap(spacing: 5, runSpacing: 5, children: [
          for (final (k, s) in sets.indexed)
            Container(
              padding: const EdgeInsets.fromLTRB(4, 3, 8, 3),
              decoration: BoxDecoration(color: s['is_warmup'] == true ? AppColors.white : AppColors.sub, borderRadius: BorderRadius.circular(8), border: s['is_warmup'] == true ? Border.all(color: AppColors.line) : null),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
                Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle),
                  child: Text(s['is_warmup'] == true ? 'W' : '${k + 1}', style: AppText.s(10, W.w7, color: AppColors.muted)),
                ),
                Text(e.setText(s), style: AppText.s(12.5, W.w6)),
                if (s['is_pr'] == true) const AppIcon(AppIcons.star, size: 11, color: AppColors.warnText),
              ]),
            ),
        ]),
      ]),
    );
  }
}

/// A sheet (phone) or centred 520 card (wider) whose header stays put while the body scrolls:
/// [builder] returns a Column with a `Flexible` scroll area.
Future<T?> showFixedSheet<T>(BuildContext context, Widget Function(BuildContext) builder) {
  final h = MediaQuery.sizeOf(context).height;
  if (context.isPhone) {
    return trackSheet(showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.card,
      barrierColor: AppColors.scrimSheet,
      constraints: BoxConstraints(maxHeight: h * .86),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.caSheet))),
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Container(width: 38, height: 4, margin: const EdgeInsets.fromLTRB(0, 8, 0, 8), decoration: BoxDecoration(color: AppColors.grab, borderRadius: AppRadius.all(4)))),
        Flexible(child: Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.paddingOf(ctx).bottom), child: builder(ctx))),
      ]),
    ));
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'sheet',
    barrierColor: AppColors.scrimSheet,
    transitionDuration: const Duration(milliseconds: 140),
    transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (ctx, _, _) => Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 520,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .8),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.modal), boxShadow: AppShadows.modal),
          child: CaWeb(web: true, child: builder(ctx)),
        ),
      ),
    ),
  );
}

class _PastSheet extends StatefulWidget {
  const _PastSheet({this.thisName, this.startThis = false});
  final String? thisName;
  final bool startThis;
  @override
  State<_PastSheet> createState() => _PastSheetState();
}

class _PastSheetState extends State<_PastSheet> {
  late bool _this = widget.startThis && widget.thisName != null;
  final _pages = <bool, PastPage>{};
  final _rows = <bool, List<PastRow>>{};
  bool _loading = false;
  String? _error;
  PastRow? _sel;
  PastDetail? _det;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    final key = _this;
    if (_loading || (!more && _pages.containsKey(key))) return;
    setState(() => _loading = true);
    try {
      final page = more ? (_pageNo[key] ?? 1) + 1 : 1;
      final p = await loadPast(name: key ? widget.thisName : null, page: page);
      _pageNo[key] = page;
      _pages[key] = p;
      _rows[key] = [...?(more ? _rows[key] : null), ...p.rows];
      _error = null;
    } catch (e) {
      _error = 'Could not load your past workouts. Check the connection and try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  final _pageNo = <bool, int>{};

  Future<void> _open(PastRow r) async {
    setState(() {
      _sel = r;
      _det = null;
    });
    try {
      final d = await loadPastDetail(r.id);
      if (mounted && _sel == r) setState(() => _det = d);
    } catch (_) {
      if (mounted) showToast(context, 'Could not open this workout', sub: 'Check the connection and try again', kind: ToastKind.warn);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _pages[_this];
    final rows = _rows[_this] ?? const <PastRow>[];
    final sel = _sel;
    final String title, sub;
    if (sel != null) {
      title = sel.name;
      sub = '${DateFormat('EEE, d MMM').format(sel.date)} · ${sel.minutes} min';
    } else {
      title = 'Past workouts';
      final n = p?.count ?? 0;
      sub = p == null
          ? 'Loading…'
          : '$n ${n == 1 ? 'workout' : 'workouts'}${_this ? ' · this workout only' : (p.since == null ? '' : ' · since ${DateFormat('d MMM').format(p.since!)}')}';
    }
    // Title, tabs and the back link stay; only the list or the workout scrolls.
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text(title, style: AppText.s(17, W.w8, ls: -0.2)),
              Text(sub, style: AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.4)),
            ]),
          ),
          SheetClose(onTap: () => Navigator.of(context).pop()),
        ]),
      ),
      if (sel == null && widget.thisName != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TwoTabs(
            labels: [widget.thisName!, 'All workouts'],
            index: _this ? 0 : 1,
            onPick: (i) {
              setState(() => _this = i == 0);
              _load();
            },
          ),
        ),
      if (sel != null) _back(),
      Flexible(
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: sel == null ? _list(rows, p) : _detail(sel)),
        ),
      ),
    ]);
  }

  Widget _back() => Align(
        alignment: Alignment.centerLeft,
        child: Hover(
          onTap: () => setState(() => _sel = null),
          builder: (_, h, _) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
              const AppIcon(AppIcons.chevronLeft, size: 15, color: AppColors.accent),
              Text('All past workouts', style: AppText.s(13, W.w6, color: AppColors.accent).copyWith(decoration: h ? TextDecoration.underline : null, decorationColor: AppColors.accent)),
            ]),
          ),
        ),
      );

  List<Widget> _list(List<PastRow> rows, PastPage? p) => [
        if (p == null && _error == null)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))))
        else if (_error != null && rows.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(_error!, textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)))
        else if (rows.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text('No past workouts yet.', textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)))
        else
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, r) in rows.indexed)
                Hover(
                  onTap: () => _open(r),
                  builder: (_, h, _) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: h ? AppColors.sub : AppColors.white, border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
                    child: Row(spacing: 12, children: [
                      Container(
                        width: 48,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(9)),
                        child: Column(children: [
                          Text(DateFormat('d MMM').format(r.date), maxLines: 1, style: AppText.s(13, W.w7, h: 1.2)),
                          Text(DateFormat('EEE').format(r.date), style: AppText.s(10.5, W.w6, color: AppColors.muted)),
                        ]),
                      ),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                          Text(r.name, style: AppText.s(13.5, W.w7)),
                          Text('${r.minutes} min · ${r.exercises} exercises · ${r.sets} sets', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w4, color: AppColors.muted)),
                        ]),
                      ),
                      if (r.pr) const PrFlag('PR'),
                      const AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.muted),
                    ]),
                  ),
                ),
            ]),
          ),
        if (p?.next != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: CaButton('Show more', kind: CaBtnKind.out, small: true, loading: _loading, onPressed: () => _load(more: true)),
          ),
      ];

  List<Widget> _detail(PastRow sel) {
    final d = _det;
    return [
      if (d == null)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))))
      else ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(spacing: 6, children: [
            for (final (l, v) in [('Time', '${sel.minutes} min'), ('Exercises', '${d.groups.length} of ${d.groups.length}'), ('Effort', sel.effort == null ? '—' : '${sel.effort} / 10')])
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(10)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                    Text(l, style: AppText.s(11, W.w4, color: AppColors.muted)),
                    Text(v, style: AppText.s(14, W.w7)),
                  ]),
                ),
              ),
          ]),
        ),
        if (sel.note.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text('Your note', style: AppText.s(11, W.w7, color: AppColors.infoText)),
              Text(sel.note, style: AppText.s(12.5, W.w4, color: AppColors.text2)),
            ]),
          ),
        Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, gr) in d.groups.indexed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
                  Row(spacing: 6, children: [
                    // name (+ New best) takes the room, the set count sits at the right edge
                    Expanded(
                      child: Row(spacing: 6, children: [
                        Flexible(child: Text(gr.name, style: AppText.s(13.5, W.w7))),
                        if (gr.pr) const PrFlag('New best'),
                      ]),
                    ),
                    Text('${gr.sets.length} ${gr.sets.length == 1 ? 'set' : 'sets'}', style: AppText.s(12, W.w4, color: AppColors.muted)),
                  ]),
                  Wrap(spacing: 5, runSpacing: 5, children: [
                    for (final (k, s) in gr.sets.indexed)
                      Container(
                        padding: const EdgeInsets.fromLTRB(4, 3, 8, 3),
                        decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(8)),
                        child: Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
                          Container(
                            width: 16,
                            height: 16,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle),
                            child: Text('${k + 1}', style: AppText.s(10, W.w7, color: AppColors.muted)),
                          ),
                          Text(PastDetail.setText(gr.logType, s), style: AppText.s(12.5, W.w6)),
                        ]),
                      ),
                  ]),
                ]),
              ),
            if (d.groups.isEmpty) Padding(padding: const EdgeInsets.all(14), child: Text('No sets were ticked in this workout.', style: AppText.s(13, W.w4, color: AppColors.muted))),
          ]),
        ),
      ],
    ];
  }
}

/// `pw-pr`: amber star pill ("PR", "New best").
class PrFlag extends StatelessWidget {
  const PrFlag(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: AppColors.warnBg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 3, children: [
          const AppIcon(AppIcons.star, size: 11, color: AppColors.warnText),
          Text(text, style: AppText.s(11, W.w7, color: AppColors.warnText)),
        ]),
      );
}

/// `tabs` (pw-f): grey track, the picked tab white with a hairline ring. [fit]: compact, as wide as the labels.
class TwoTabs extends StatelessWidget {
  const TwoTabs({super.key, required this.labels, required this.index, required this.onPick, this.fit = true});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onPick;
  final bool fit;
  @override
  Widget build(BuildContext context) {
    Widget tab(int i, String l) => Hover(
          onTap: () => onPick(i),
          builder: (_, h, _) => Container(
            height: fit ? 28 : 32,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: fit ? 16 : 14),
            decoration: BoxDecoration(
              color: i == index ? AppColors.white : null,
              borderRadius: BorderRadius.circular(6),
              boxShadow: i == index ? const [BoxShadow(color: AppColors.shadowSoft, blurRadius: 2, offset: Offset(0, 1)), BoxShadow(color: AppColors.line, spreadRadius: 1)] : null,
            ),
            child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(fit ? 12.5 : 13, W.w6, color: i == index || h ? AppColors.text : AppColors.text2)),
          ),
        );
    final track = Container(
      padding: EdgeInsets.all(fit ? 3 : 4),
      decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: fit ? MainAxisSize.min : MainAxisSize.max, spacing: fit ? 2 : 0, children: [
        for (final (i, l) in labels.indexed) fit ? tab(i, l) : Expanded(child: tab(i, l)),
      ]),
    );
    return fit ? Align(alignment: Alignment.centerLeft, child: track) : track;
  }
}

/// `cg-vwrap`: the exercise's video (plays here, seek, full screen), its picture (tap to zoom), or a YouTube
/// link (its still, opens YouTube), with the title line under it.
class _GuideMedia extends StatefulWidget {
  const _GuideMedia({required this.e, required this.web});
  final TrainEx e;
  final bool web;
  @override
  State<_GuideMedia> createState() => _GuideMediaState();
}

class _GuideMediaState extends State<_GuideMedia> {
  TrainEx get e => widget.e;
  late final VideoCtl? v = e.mediaKind == 'video' ? VideoCtl(e.mediaUrl, fallbackSeconds: e.mediaSeconds) : null;

  @override
  void dispose() {
    v?.dispose();
    super.dispose();
  }

  String _label() {
    final c = v!;
    if (c.failed) return 'Could not play here · tap to open';
    if (c.playing) return 'Playing';
    if (c.finished) return 'Finished · tap to watch again';
    if (c.pos > 0) return 'Paused';
    return 'Tap to play';
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.web ? 240.0 : 190.0;
    final kind = e.mediaKind;
    final Widget face = switch (kind) {
      'video' => VideoBox(
          ctl: v!,
          label: _label,
          bg: AppColors.videoDark.first,
          fg: AppColors.white,
          height: h,
          radius: 0,
          onTapEmpty: () => launchUrl(Uri.parse(e.mediaUrl), mode: LaunchMode.externalApplication),
        ),
      'image' => Semantics(
          button: true,
          label: 'Open the picture full screen',
          child: GestureDetector(
            onTap: () => showImageViewer(context, [e.mediaUrl], title: e.name),
            child: MouseRegion(
              cursor: SystemMouseCursors.zoomIn,
              child: Container(color: AppColors.sub, height: h, child: NetImage(e.mediaUrl, fit: BoxFit.contain, height: h)),
            ),
          ),
        ),
      'youtube' => YoutubeBox(url: e.mediaUrl),
      _ => YoutubeBox(url: e.youtube),
    };
    final source = kind.isEmpty ? 'YouTube' : 'From content library';
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        face,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(spacing: 8, children: [
            AppIcon(kind == 'image' ? AppIcons.photo : AppIcons.video, size: 15, color: AppColors.muted),
            Expanded(child: Text(e.videoTitle.isNotEmpty ? e.videoTitle : e.name, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w7))),
            Text(source, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
          ]),
        ),
      ]),
    );
  }
}
