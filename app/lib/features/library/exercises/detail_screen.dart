import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../app/shell/page.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tabs.dart';
import '../../client/train/train_model.dart' show regionsOf;
import '../../client/train/train_parts.dart' show BodyMap;
import '../../../core/widgets/media.dart' show OpenInYoutube;
import '../../trainer/client_profile/cp_plans_parts.dart' show ExMedia;
import '../lib_common.dart';
import 'ex_common.dart';
import 'ex_sheets.dart';
import '../../../core/widgets/tooltip.dart';

/// Exercise page (boards `ExerciseDetail` / `ExerciseDetailMobile`): header with the cover, Default sets and reps,
/// How to · Form cues · Muscles (body map), Video, Details and Used in N programs. Built-in exercises are read-only
/// (Duplicate to edit); custom ones open the edit page.
class ExerciseDetailScreen extends StatefulWidget {
  const ExerciseDetailScreen({super.key, required this.id});
  final String id;
  @override
  State<ExerciseDetailScreen> createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen> {
  Map? e;
  List<Map> used = [];
  bool canCreate = false;
  ApiError? error;
  String tab = 'muscles';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // Add to program / delete / duplicate here change the library cards under this page
    Future.microtask(() => exercisesChanged.value++);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        Services.api.get<Map>('exercises/${widget.id}/'),
        Services.api.get<List>('exercises/${widget.id}/used-in/'),
        Services.api.get<Map>('exercises/facets/'),
      ]);
      if (!mounted) return;
      setState(() {
        e = r[0] as Map;
        used = [for (final x in r[1] as List) x as Map];
        canCreate = ((r[2] as Map)['can'] as Map?)?['create'] == true;
        error = null;
      });
    } on ApiError catch (er) {
      if (mounted) setState(() => error = er);
    }
  }

  bool get _edit => e?['can_edit'] == true;

  void _more(BuildContext anchor) => showAppMenu(anchor, width: 210, [
        if (_edit) MenuEntry('Edit', icon: AppIcons.edit, onTap: () => context.go('/exercises/${widget.id}?edit=1')),
        if (canCreate) MenuEntry(_edit ? 'Duplicate' : 'Duplicate to edit', icon: AppIcons.copy, onTap: () => duplicateExercise(context, e!)),
        MenuEntry('Add to program', icon: AppIcons.plus, onTap: () => showAddToProgram(context, e!)),
        if (_edit) const MenuEntry.separator(),
        if (_edit)
          MenuEntry('Delete', icon: AppIcons.trash, danger: true, onTap: () async {
            final router = GoRouter.of(context);
            if (await deleteExercise(context, e!, onUndo: () => router.go('/exercises/${widget.id}'))) router.go('/exercises');
          }),
      ]);

  @override
  Widget build(BuildContext context) {
    final x = e;
    if (x == null) {
      return StaffPage(children: [
        _crumb(''),
        if (error == null)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)))
        else
          AppCard(
            child: EmptyState(error!.status == 404 ? 'This exercise is gone' : 'Could not open this exercise',
                icon: AppIcons.dumbbell,
                sub: error!.status == 404 ? 'It may have been deleted.' : error!.message,
                action: AppButton(error!.status == 404 ? 'Back to exercises' : 'Try again', onPressed: error!.status == 404 ? () => context.go('/exercises') : _load)),
          ),
      ]);
    }
    final phone = context.isPhone;
    return StaffPage(
      onRefresh: _load,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 12 : 14, children: [_crumb('${x['name']}'), _head(x, phone)]),
        _defaults(x, phone),
        LayoutBuilder(builder: (context, c) {
          if (c.maxWidth < 860) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 14 : 20, children: [
              _video(x, phone),
              _tabsCard(x, phone, narrow: true),
              _details(x, phone),
              _used(phone),
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
            Expanded(child: _tabsCard(x, phone, narrow: c.maxWidth < 1080)),
            SizedBox(
              width: 340,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 20, children: [_video(x, phone), _details(x, phone), _used(phone)]),
            ),
          ]);
        }),
      ],
    );
  }

  Widget _crumb(String name) => Row(spacing: 6, children: [
        Hover(
          onTap: () => context.go('/exercises'),
          builder: (_, h, _) => Text('Exercises', style: AppText.s(13, W.w5, color: h ? AppColors.text : AppColors.muted)),
        ),
        const AppIcon(AppIcons.chevronRight, size: 13, color: AppColors.chevron),
        Flexible(child: CutText(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w6))),
      ]);

  Widget _head(Map x, bool phone) {
    final sub = '${exMuscleLabel(x)} · ${exEquipLabel(x)} · ${x['is_builtin'] == true ? 'Built-in exercise' : 'Custom exercise'}';
    final narrow = compactTop(context);
    return Row(spacing: phone ? 10 : 14, children: [
      SizedBox(width: phone ? 48 : 76, height: phone ? 48 : 76, child: ExCover(x, radius: phone ? 9 : 12, iconSize: phone ? 20 : 32, badge: !phone, inset: 5)),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
          CutText('${x['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.h1.copyWith(fontSize: phone ? 17 : 28)),
          Text(sub, style: AppText.sub.copyWith(fontSize: phone ? 12 : 13)),
        ]),
      ),
      Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
        if (_edit)
          AppButton('Edit', icon: AppIcons.edit, iconOnly: phone || narrow, onPressed: () => context.go('/exercises/${widget.id}?edit=1'))
        else if (canCreate)
          AppButton('Duplicate to edit', icon: AppIcons.copy, iconOnly: phone || narrow, onPressed: () => duplicateExercise(context, x)),
        AppButton.primary('Add to program', icon: AppIcons.plus, iconOnly: phone, onPressed: () => showAddToProgram(context, x)),
        Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'More actions', onPressed: () => _more(b))),
      ]),
    ]);
  }

  /// `.ex-ds`: Default sets and reps, then six tiles (three per row on a phone).
  Widget _defaults(Map x, bool phone) {
    final rest = (x['default_rest_seconds'] as num?)?.toInt() ?? 0;
    final (restV, restU) = rest == 0 ? ('0', 's') : (rest % 60 == 0 ? ('${rest ~/ 60}', 'min') : ('$rest', 's'));
    final rpe = x['default_rpe'];
    // the numbers; how the client logs sits in the header as a pill, so no tile ever cuts its text
    final tiles = <(String, String, String?)>[
      ('Sets', '${x['default_sets'] ?? '–'}', null),
      (x['log_type'] == 'time' ? 'Time' : (x['log_type'] == 'distance' ? 'Minutes' : 'Reps'), '${x['default_reps'] ?? '–'}', null),
      ('Rest', restV, restU),
      ('RPE', rpe == null || rpe == 0 ? '–' : '$rpe', rpe == null || rpe == 0 ? null : '/ 10'),
      ('Tempo', '${x['default_tempo'] ?? ''}'.isEmpty ? '–' : '${x['default_tempo']}', null),
    ];
    Widget tile((String, String, String?) t, {required bool first, required bool top}) => Container(
          padding: EdgeInsets.fromLTRB(first ? 0 : (phone ? 10 : 16), top ? 0 : 10, 8, 0),
          decoration: BoxDecoration(border: Border(left: first ? BorderSide.none : const BorderSide(color: AppColors.line))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(t.$1, style: AppText.s(12, W.w6, color: AppColors.muted)),
            CutText.rich(
              TextSpan(children: [
                TextSpan(text: t.$2),
                if (t.$3 != null) TextSpan(text: ' ${t.$3}', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.s(phone ? 16 : 18, W.w8),
            ),
          ]),
        );
    final logs = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(99), border: Border.all(color: AppColors.line)),
      child: CutText.rich(
        TextSpan(children: [
          TextSpan(text: 'Client logs  ', style: AppText.s(12, W.w5, color: AppColors.muted)),
          TextSpan(text: logLabel(x['log_type']), style: AppText.s(12.5, W.w7)),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    return AppCard(
      padding: phone ? const EdgeInsets.fromLTRB(14, 12, 14, 14) : const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 520;
        final head = Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
          Text('Default sets and reps', style: AppText.h3),
          Text('Filled in when added to a program', style: AppText.cap),
        ]);
        // five in a row; a narrow card puts Sets · Reps · Rest over RPE · Tempo
        final rows = narrow ? [tiles.sublist(0, 3), tiles.sublist(3)] : [tiles];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
          narrow
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [head, logs])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [Expanded(child: head), ConstrainedBox(constraints: const BoxConstraints(maxWidth: 280), child: logs)]),
          Container(height: 1, color: AppColors.line),
          for (final (r, row) in rows.indexed)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < 3 || i < row.length; i++)
                if (i < row.length)
                  Expanded(child: tile(row[i], first: i == 0, top: r == 0))
                else if (narrow)
                  const Expanded(child: SizedBox()),
            ]),
        ]);
      }),
    );
  }

  // ─────────────────────────────── How to · Form cues · Muscles

  Widget _tabsCard(Map x, bool phone, {required bool narrow}) {
    final how = [for (final s in (x['how_to'] as List? ?? const [])) '$s'];
    final cues = [for (final s in (x['form_cues'] as List? ?? const [])) '$s'];
    final also = [for (final a in (x['also_works'] as List? ?? const [])) a as Map];
    final body = switch (tab) {
      'how' => how.isEmpty
          ? _none('No steps yet.')
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
              for (final (i, s) in how.indexed) _stepRow(Text('${i + 1}', style: AppText.s(12, W.w7)), s, phone),
            ]),
      'cues' => cues.isEmpty
          ? _none('No form cues yet.')
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
              for (final s in cues) _stepRow(const AppIcon(AppIcons.check, size: 14, color: AppColors.text, stroke: 2.2), s, phone),
            ]),
      _ => _muscles(x, also, phone, narrow: narrow),
    };
    return AppCard(
      padding: EdgeInsets.all(phone ? 14 : 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedTabs<String>(
            items: [
              TabItem('how', 'How to', count: how.length),
              TabItem('cues', 'Form cues', count: cues.length),
              TabItem('muscles', 'Muscles', count: 1 + also.length),
            ],
            value: tab,
            onChanged: (v) => setState(() => tab = v),
          ),
        ),
        body,
      ]),
    );
  }

  Widget _none(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('$t${_edit ? ' Add them in Edit.' : ''}', style: AppText.s(13, W.w5, color: AppColors.muted)),
      );

  /// `.steps li`: a 26 square (number or tick) and the line.
  Widget _stepRow(Widget mark, String text, bool phone) => Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: phone ? 10 : 14, children: [
        Container(width: 26, height: 26, alignment: Alignment.center, decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(6)), child: mark),
        Expanded(child: Padding(padding: const EdgeInsets.only(top: 2), child: Text(text, style: AppText.s(phone ? 13.5 : 14, W.w5, h: 1.5)))),
      ]);

  Widget _muscles(Map x, List<Map> also, bool phone, {required bool narrow}) {
    final map = <String, String>{};
    void put(String m, String lv) {
      for (final r in regionsOf(m)) {
        final have = map[r];
        if (have == null || 'psl'.indexOf(lv) < 'psl'.indexOf(have)) map[r] = lv;
      }
    }

    final group = exMuscleLabel(x), sub = '${x['primary_muscle'] ?? ''}';
    put(sub.isEmpty ? group : sub, 'p');
    if (regionsOf(sub).isEmpty) put(group, 'p');
    for (final a in also) {
      put('${a['muscle']}', a['level'] == 'strong' ? 's' : 'l');
    }
    final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.exPriBg, borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.exPriLine)),
        child: Row(spacing: 12, children: [
          Container(width: 34, height: 34, alignment: Alignment.center, decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.all(8)), child: const AppIcon(AppIcons.dumbbell, size: 16, color: AppColors.accent)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text('PRIMARY MUSCLE', style: AppText.over.copyWith(color: AppColors.accentText)),
              Text(group, style: AppText.s(15, W.w7)),
              Text('${sub.isEmpty ? '' : '$sub · '}decides where this exercise shows in the library filter', style: AppText.s(12, W.w5, color: AppColors.text2)),
            ]),
          ),
          const LevelBars(3),
        ]),
      ),
      if (also.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6, left: 2), child: Text('ALSO WORKS', style: AppText.over)),
      for (final a in also)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(borderRadius: AppRadius.all(8), border: Border.all(color: AppColors.line)),
          child: Row(spacing: 12, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text('${a['muscle']}', style: AppText.s(13.5, W.w7)),
                if ('${a['note'] ?? ''}'.isNotEmpty) Text('${a['note']}', style: AppText.s(12, W.w5, color: AppColors.muted)),
              ]),
            ),
            LevelBars(a['level'] == 'strong' ? 2 : 1),
            SizedBox(width: 46, child: Text(a['level'] == 'strong' ? 'Strong' : 'Light', style: AppText.s(13, W.w6))),
          ]),
        ),
    ]);
    final bm = BodyMap(map);
    if (narrow) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [left, bm]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [Expanded(child: left), bm]);
  }

  // ─────────────────────────────── right column

  Widget _cardHead(String t, {String? end}) => Row(children: [
        Expanded(child: Text(t, style: AppText.h3.copyWith(fontSize: 16))),
        if (end != null) Text(end, style: AppText.s(12, W.w5, color: AppColors.muted)),
      ]);

  Widget _video(Map x, bool phone) {
    final m = x['media'] as Map?;
    final yt = '${x['youtube_url'] ?? ''}';
    final none = m == null && yt.isEmpty;
    final fk = '${x['cover_frame'] ?? ''}';
    final cover = x['cover_image'] != null
        ? 'Uploaded image'
        : none
            ? 'Dumbbell tile'
            : fk.startsWith('yt/') || (m == null && yt.isNotEmpty && fk.isEmpty)
                ? 'YouTube frame'
                : 'Frame at ${clock(x['cover_at_seconds'])}';
    Widget line(String k, String v) => Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(spacing: 12, children: [
            Text(k, style: AppText.s(13, W.w5, color: AppColors.muted)),
            Expanded(child: CutText(v, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w6))),
          ]),
        );
    final title = m != null ? '${m['title'] ?? 'Video'}${((m['duration'] as num?) ?? 0) > 0 ? ' · ${clock(m['duration'])}' : ''}' : null;
    // a YouTube link: the header says so and has "Open in YouTube"; the player has no footer line of its own
    final ytOnly = m == null && yt.isNotEmpty;
    return AppCard(
      padding: EdgeInsets.all(phone ? 14 : 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        if (ytOnly)
          Row(spacing: 8, children: [
            Text('Video', softWrap: false, style: AppText.h3.copyWith(fontSize: 16)),
            const Spacer(),
            Flexible(
              flex: 20,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                  const AppIcon(AppIcons.video, size: 15, color: AppColors.muted),
                  Text('YouTube link', style: AppText.s(12.5, W.w7)),
                  const SizedBox(width: 4),
                  OpenInYoutube(yt),
                ]),
              ),
            ),
          ])
        else
          _cardHead('Video', end: m != null ? 'From content library' : null),
        if (none)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(fit: StackFit.expand, children: [
              ExCover(x, radius: 10, iconSize: 34, badge: false),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.white.withValues(alpha: .9), borderRadius: AppRadius.all(99)),
                  child: Text(_edit ? 'No video yet · add one in Edit' : 'No video yet', style: AppText.s(12.5, W.w6, color: AppColors.text2)),
                ),
              ),
            ]),
          )
        else
          ClipRRect(borderRadius: AppRadius.all(10), child: ExMedia(media: m, link: yt, name: '${x['name']}', tone: exTone(x), footer: !ytOnly)),
        Column(children: [
          if (title != null) ...[line('Video', title), Container(height: 1, color: AppColors.line)],
          line('Cover image', cover),
        ]),
      ]),
    );
  }

  Widget _details(Map x, bool phone) {
    Widget cell(String k, String v, {bool top = false}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: top ? null : const Border(bottom: BorderSide(color: AppColors.line))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
            Text(k, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
            Text(v, style: AppText.s(14, W.w7)),
          ]),
        );
    return AppCard(
      padding: EdgeInsets.all(phone ? 14 : 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        _cardHead('Details'),
        Row(spacing: 24, children: [Expanded(child: cell('Muscle group', exMuscleLabel(x))), Expanded(child: cell('Equipment', exEquipLabel(x)))]),
        Row(spacing: 24, children: [
          Expanded(child: cell('Level', exLevelLabel(x), top: true)),
          Expanded(child: cell('Source', x['is_builtin'] == true ? 'Built-in' : 'Custom', top: true)),
        ]),
      ]),
    );
  }

  Widget _used(bool phone) => AppCard(
        padding: EdgeInsets.fromLTRB(phone ? 14 : 16, phone ? 14 : 18, phone ? 14 : 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
          _cardHead(used.isEmpty ? 'Not in a program yet' : 'Used in ${plural(used.length, 'program')}'),
          if (used.isEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('Add it to a program with Add to program.', style: AppText.s(13, W.w5, color: AppColors.muted))),
          for (final p in used)
            Hover(
              onTap: () => context.go('/programs/${p['id']}'),
              builder: (_, h, _) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                decoration: BoxDecoration(color: h ? AppColors.hover : null, borderRadius: AppRadius.all(8)),
                child: Row(spacing: 8, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                      Text('${p['name']}', style: AppText.s(14, W.w7)),
                      Text(
                        [
                          if ((p['days'] as List? ?? const []).isNotEmpty) (p['days'] as List).join(', '),
                          plural((p['workouts'] as num?)?.toInt() ?? 0, 'workout'),
                          plural((p['clients'] as num?)?.toInt() ?? 0, 'client'),
                        ].join(' · '),
                        style: AppText.s(12.5, W.w5, color: AppColors.muted),
                      ),
                    ]),
                  ),
                  const AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.muted),
                ]),
              ),
            ),
        ]),
      );
}
