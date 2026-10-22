import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import '../../trainer/client_profile/cp_content_drawers.dart' show drEveryone, DrOpt, DrOpts, DrScrollList;
import '../../trainer/client_profile/cp_plans_parts.dart' show MediaTile;
import '../../trainer/me/me_common.dart' show meField;
import '../lib_common.dart';
import 'builder_model.dart';
import '../../../core/widgets/tooltip.dart';

/// One-field modal: Rename program, Rename day, Add day. Returns the trimmed text.
Future<String?> showNameModal(BuildContext context,
    {required String title, required String sub, required String label, String initial = '', String? placeholder, required String button, AppIconData icon = AppIcons.edit}) async {
  final c = TextEditingController(text: initial);
  final err = ValueNotifier<String?>(null);
  void save(BuildContext ctx) {
    final v = c.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (v.length < 2) {
      err.value = 'Enter at least 2 letters.';
      return;
    }
    Navigator.of(ctx).pop(v);
  }

  final r = await showAppModal<String>(
    context,
    title: title,
    body: sub,
    icon: icon,
    content: (ctx) => ValueListenableBuilder(
      valueListenable: err,
      builder: (_, e, _) => meField(label,
          AppTextField(controller: c, placeholder: placeholder, autofocus: true, onChanged: (_) => err.value = null, onSubmitted: (_) => save(ctx)),
          req: true, error: e, hint: placeholder),
    ),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      AppButton.primary(button, icon: AppIcons.check, expand: ctx.isPhone, onPressed: () => save(ctx)),
    ],
  );
  disposeLater([c, err]);
  return r;
}

/// "Edit sets and rest": a live line on top, Sets / Rest / RPE steppers, Reps, Tempo and a note. Returns the new values.
Future<Map<String, dynamic>?> showSetsModal(BuildContext context, Map e) async {
  var sets = (e['sets'] as num?)?.toInt() ?? 3, rest = (e['rest_seconds'] as num?)?.toInt() ?? 90, rpe = (e['rpe'] as num?)?.toInt() ?? 0;
  final reps = TextEditingController(text: '${e['reps'] ?? ''}');
  final tempo = TextEditingController(text: '${e['tempo'] ?? ''}');
  final note = TextEditingController(text: '${e['note'] ?? ''}');
  final line = ValueNotifier('');
  final repsErr = ValueNotifier<String?>(null);
  void upd() => line.value = '$sets × ${reps.text.trim().isEmpty ? '–' : reps.text.trim()}${rpe > 0 ? ' · RPE $rpe' : ''}'
      '${tempo.text.trim().isEmpty ? '' : ' · Tempo ${tempo.text.trim()}'} · Rest ${restShort(rest)}';
  upd();
  final r = await showAppModal<Map<String, dynamic>>(
    context,
    title: exNameOf(e),
    width: 480,
    icon: AppIcons.dumbbell,
    lead: null,
    content: (ctx) => StatefulBuilder(builder: (ctx, set) {
      Widget pair(Widget a, Widget b) => ctx.isPhone
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [a, b])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [Expanded(child: a), Expanded(child: b)]);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        ValueListenableBuilder(valueListenable: line, builder: (_, l, _) => Text(l, style: AppText.s(13, W.w6, color: AppColors.muted))),
        pair(
          meField('Sets', LibStepper(value: sets, unit: '', min: 1, max: 12, onChanged: (v) => set(() {
                sets = v;
                upd();
              }))),
          ValueListenableBuilder(
            valueListenable: repsErr,
            builder: (_, er, _) => meField('Reps', AppTextField(controller: reps, placeholder: '8–10', onChanged: (_) {
              repsErr.value = null;
              upd();
            }), hint: 'e.g. 8–10, AMRAP, 45 s', error: er),
          ),
        ),
        pair(
          meField('Rest after each set', LibStepper(value: rest, unit: 's', min: 0, max: 300, step: 15, onChanged: (v) => set(() {
                rest = v;
                upd();
              }))),
          meField('RPE (0 = not set)', LibStepper(value: rpe, unit: '', min: 0, max: 10, onChanged: (v) => set(() {
                rpe = v;
                upd();
              }))),
        ),
        meField('Tempo (optional)', AppTextField(controller: tempo, placeholder: '3-1-1', onChanged: (_) => upd()), hint: 'e.g. 3-1-1'),
        meField('Note for the client (optional)', AppTextField(controller: note, placeholder: 'e.g. 30° incline only', maxLines: 3, minLines: 2)),
      ]);
    }),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      AppButton.primary('Update', icon: AppIcons.check, expand: ctx.isPhone, onPressed: () {
        if (reps.text.trim().isEmpty) {
          repsErr.value = 'Enter reps, e.g. 8–10, AMRAP, 45 s.';
          return;
        }
        Navigator.of(ctx).pop({
          'sets': sets,
          'reps': reps.text.trim(),
          'rest_seconds': rest,
          'rpe': rpe == 0 ? null : rpe,
          'tempo': tempo.text.trim(),
          'note': note.text.trim(),
        });
      }),
    ],
  );
  disposeLater([reps, tempo, note, line, repsErr]);
  return r;
}

String exNameOf(Map e) => '${(e['override'] as Map?)?['name'] ?? exDetail(e)['name'] ?? 'Exercise'}';

/// "Edit for this program": this program's own copy of a library exercise — its name, video (same as the library,
/// another video from the Content library, or a YouTube link), how-to steps and form cues. Returns the new
/// `override` ({} = reset to the library version), or null when closed.
Future<Map?> showEditForProgram(BuildContext context, Map e, {required String program, required String dayHead}) async {
  final lib = exDetail(e);
  final o = Map<String, dynamic>.from((e['override'] as Map?) ?? const {});
  final name = TextEditingController(text: '${o['name'] ?? lib['name'] ?? ''}');
  final yt = TextEditingController(text: '${o['youtube_url'] ?? ''}');
  var video = o['youtube_url'] != null && '${o['youtube_url']}'.isNotEmpty ? 'yt' : (o['video'] != null ? 'cl' : 'lib');
  String? contentId = o['video'] == null ? null : '${o['video']}';
  final steps = [for (final s in (o['how_to'] ?? lib['how_to'] ?? const []) as List) TextEditingController(text: '$s')];
  final cues = [for (final s in (o['form_cues'] ?? lib['form_cues'] ?? const []) as List) TextEditingController(text: '$s')];
  final videos = Services.api.get<Map>('content/', query: {'kind': 'video', 'page_size': 100}).then((r) => [for (final x in r['results'] as List) x as Map]).catchError((_) => <Map>[]);
  final ytErr = ValueNotifier<String?>(null);
  final edited = (e['override'] as Map?)?.isNotEmpty == true;

  Widget lines(StateSetter set, List<TextEditingController> list, String ph, String add) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        for (final (i, c) in list.indexed)
          Row(spacing: 10, children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
              child: Text('${i + 1}', style: AppText.s(11, W.w8, color: AppColors.accentText)),
            ),
            Expanded(child: AppTextField(controller: c, placeholder: ph)),
            AppIconButton(AppIcons.close, tooltip: 'Remove', ghost: true, small: true, onPressed: () => set(() => list.removeAt(i))),
          ]),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(add, kind: BtnKind.text, icon: AppIcons.plus, onPressed: () => set(() => list.add(TextEditingController()))),
        ),
      ]);

  final r = await showAppDrawer<Map>(
    context,
    title: 'Edit for this program',
    sub: '${lib['name']} · $dayHead',
    icon: AppIcons.edit,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
        const SizedBox(height: 0),
        _note(TextSpan(children: [
          const TextSpan(text: 'Changes stay inside '),
          TextSpan(text: program, style: AppText.s(12.5, W.w7, color: AppColors.text2)),
          const TextSpan(text: '. The exercise library and other programs keep the original. While it is edited here, library updates skip it in this program.'),
        ])),
        meField('Name in this program', AppTextField(controller: name), hint: 'Library name: ${lib['name']}'),
        meField(
          'Video',
          Container(
            decoration: BoxDecoration(borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.line2)),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DrOpts([
              DrOpt(title: 'Same as library', sub: '${lib['name']}', thumb: const MediaTile(tone: 0, size: 40), on: video == 'lib', onTap: () => set(() => video = 'lib')),
              DrOpt(title: 'Another video from Content library', sub: 'Pick one of your videos', thumb: const MediaTile(tone: 1, size: 40), on: video == 'cl', onTap: () => set(() => video = 'cl')),
              DrOpt(title: 'YouTube link', sub: 'Plays inside the app', thumb: const MediaTile(tone: 2, size: 40), on: video == 'yt', onTap: () => set(() => video = 'yt')),
            ]),
          ),
        ),
        if (video == 'cl')
          FutureBuilder<List<Map>>(
            future: videos,
            builder: (_, s) {
              final list = s.data ?? const <Map>[];
              final cur = list.where((x) => '${x['id']}' == contentId).firstOrNull;
              return meField(
                'Video from Content library',
                list.isEmpty && s.hasData
                    ? Text('No videos in the Content library yet.', style: AppText.s(12.5, W.w5, color: AppColors.muted))
                    : AppSelect(cur == null ? (s.hasData ? 'Pick a video' : 'Loading…') : '${cur['title']}', entries: [
                        for (final x in list) MenuEntry('${x['title']}', selected: '${x['id']}' == contentId, onTap: () => set(() => contentId = '${x['id']}')),
                      ]),
              );
            },
          ),
        if (video == 'yt')
          ValueListenableBuilder(
            valueListenable: ytErr,
            builder: (_, er, _) => meField('YouTube link', AppTextField(controller: yt, placeholder: 'https://youtu.be/…', onChanged: (_) => ytErr.value = null), hint: 'Plays inside the app.', error: er),
          ),
        meField('How to', lines(set, steps, 'Write the step', 'Add step')),
        meField('Form cues', lines(set, cues, 'Write the cue', 'Add cue')),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
            Text('Muscles', style: AppText.s(13, W.w6)),
            Expanded(child: Text(exMuscles(e, library: false), style: AppText.s(13, W.w6, color: AppColors.text2))),
            Text('From the library', style: AppText.cap),
          ]),
        ),
        const SizedBox(height: 4),
      ]);
    }),
    footer: (ctx) => [
      if (edited)
        ctx.isPhone
            ? SizedBox(width: double.infinity, child: AppButton('Reset to library', kind: BtnKind.text, onPressed: () => Navigator.of(ctx).pop(<String, dynamic>{})))
            : AppButton('Reset to library', kind: BtnKind.text, onPressed: () => Navigator.of(ctx).pop(<String, dynamic>{})),
      if (!ctx.isPhone) const Spacer(),
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      AppButton.primary('Save for this program', icon: AppIcons.check, expand: ctx.isPhone, onPressed: () {
        final link = yt.text.trim();
        if (video == 'yt' && !RegExp(r'(youtu\.be/|youtube\.com/)').hasMatch(link)) {
          ytErr.value = 'Paste a YouTube link.';
          return;
        }
        final n = name.text.trim();
        final out = <String, dynamic>{
          if (n.isNotEmpty && n != '${lib['name']}') 'name': n,
          if (video == 'cl' && contentId != null) 'video': contentId,
          if (video == 'yt') 'youtube_url': link,
        };
        final st = [for (final c in steps) c.text.trim()].where((s) => s.isNotEmpty).toList();
        final cu = [for (final c in cues) c.text.trim()].where((s) => s.isNotEmpty).toList();
        if (st.join('\n') != ((lib['how_to'] as List?) ?? const []).join('\n')) out['how_to'] = st;
        if (cu.join('\n') != ((lib['form_cues'] as List?) ?? const []).join('\n')) out['form_cues'] = cu;
        Navigator.of(ctx).pop(out);
      }),
    ],
  );
  disposeLater([name, yt, ytErr, ...steps, ...cues]);
  return r;
}

Widget _note(InlineSpan text) => Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(AppRadius.item)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        const Padding(padding: EdgeInsets.only(top: 2), child: AppIcon(AppIcons.info, size: 15, color: AppColors.muted)),
        Expanded(child: Text.rich(text, style: AppText.s(12.5, W.w5, color: AppColors.text2, h: 1.5))),
      ]),
    );

/// Assign to clients: every client this person can see, ticked = follows this program. "On X" shows another
/// program. Save makes the followers exactly the ticked clients (only the ones listed here).
Future<(int, int)?> showAssignModal(BuildContext context, BuilderModel m) async {
  final opts = Services.api.get<List>('programs/assign-options/');
  final current = Services.api.get<List>('programs/${m.id}/clients/');
  final data = Future.wait([opts, current]);
  final picked = ValueNotifier<Set<String>?>(null);
  final q = ValueNotifier('');
  var saving = false;
  final r = await showAppModal<(int, int)>(
    context,
    title: 'Assign to clients',
    body: '${m.name} · ${plural(m.weeks.length, 'week')}',
    icon: AppIcons.assign,
    width: 500,
    content: (ctx) => FutureBuilder(
      future: data,
      builder: (ctx, s) {
        if (s.hasError) return const EmptyState('Could not load your clients');
        if (!s.hasData) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)));
        final all = [for (final x in s.data![0]) x as Map];
        final on = {for (final x in s.data![1]) '${((x as Map)['client'] as Map?)?['id'] ?? x['client']}'};
        picked.value ??= on;
        return ListenableBuilder(
          listenable: Listenable.merge([picked, q]),
          builder: (ctx, _) {
            final rows = all.where((c) => q.value.isEmpty || '${c['full_name']}'.toLowerCase().contains(q.value)).toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
              AppSearchField(placeholder: 'Search clients', icon: AppIcons.search, onChanged: (v) => q.value = v.trim().toLowerCase()),
              if (all.isEmpty)
                Text('You have no clients yet.', style: AppText.s(13, W.w5, color: AppColors.muted))
              else if (rows.isEmpty)
                Text('No client matches.', style: AppText.s(13, W.w5, color: AppColors.muted))
              else
                DrScrollList(rows: 6, [
                  if (rows.length > 1) drEveryone(rows, picked, searching: q.value.isNotEmpty),
                  for (final c in rows)
                    () {
                      final id = '${c['id']}', sel = picked.value!.contains(id);
                      final other = '${c['current_program'] ?? ''}';
                      return DrOpt(
                        title: '${c['full_name']}',
                        sub: ['${c['goal'] ?? ''}', '${c['trainer'] ?? ''}'].where((x) => x.isNotEmpty).join(' · '),
                        multi: true,
                        on: sel,
                        thumb: AppAvatar('${c['full_name']}', size: 28, initials: '${c['initials'] ?? ''}', colors: AppColors.avatarCode('${c['avatar_color'] ?? 'c1'}')),
                        end: !sel && other.isNotEmpty && other != m.name ? 'On $other' : null,
                        onTap: () => picked.value = sel ? ({...picked.value!}..remove(id)) : {...picked.value!, id},
                      );
                    }(),
                ]),
              Text('Clients follow this master plan as it is. A trainer can make a custom version for one client from the client page.',
                  style: AppText.s(12, W.w5, color: AppColors.muted)),
            ]);
          },
        );
      },
    ),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      StatefulBuilder(
        builder: (bctx, set) => ValueListenableBuilder(
          valueListenable: picked,
          builder: (_, p, _) => AppButton.primary(
            p == null || p.isEmpty ? 'Save · no clients' : 'Save · ${plural(p.length, 'client')}',
            icon: AppIcons.check,
            expand: ctx.isPhone,
            loading: saving,
            onPressed: p == null
                ? null
                : () async {
                    set(() => saving = true);
                    try {
                      final res = await Services.api.post<Map>('programs/${m.id}/assign/', {'clients': p.toList()});
                      if (ctx.mounted) Navigator.of(ctx).pop((((res['added'] as num?) ?? 0).toInt(), ((res['removed'] as num?) ?? 0).toInt()));
                    } on ApiError catch (e) {
                      set(() => saving = false);
                      if (ctx.mounted) showToast(ctx, 'Could not save it', sub: e.message, kind: ToastKind.err);
                    }
                  },
          ),
        ),
      ),
    ],
  );
  disposeLater([picked, q]);
  return r;
}

/// Assigned clients drawer: who follows this program, Master or Custom; a row opens the client.
/// Returns true for "Change clients" / "Assign clients".
Future<bool?> showClientsDrawer(BuildContext context, BuilderModel m) {
  final rows = Services.api.get<List>('programs/${m.id}/clients/');
  String subOf(int n) => n == 0 ? 'Nobody follows this program yet' : '$n ${n == 1 ? 'follows' : 'follow'} ${m.name}';
  return showAppDrawer<bool>(
    context,
    title: 'Assigned clients',
    sub: subOf(m.clientCount),
    icon: AppIcons.clientsAlt,
    builder: (ctx) => FutureBuilder<List>(
      future: rows,
      builder: (ctx, s) {
        if (s.hasError) return const EmptyState('Could not load the clients');
        if (!s.hasData) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)));
        final list = [for (final x in s.data!) x as Map];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (list.isEmpty)
            Padding(padding: const EdgeInsets.all(28), child: Text('Nobody follows this program yet.', textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted))),
          for (final a in list)
            () {
              final c = (a['client'] as Map?) ?? const {};
              final custom = a['custom'] == true;
              return Hover(
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.go('/clients/${c['id']}?tab=plans');
                },
                builder: (_, h, _) => Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                  decoration: BoxDecoration(color: h ? AppColors.hover : null, border: const Border(bottom: BorderSide(color: AppColors.line))),
                  child: Row(spacing: 12, children: [
                    AppAvatar('${c['full_name']}', size: 32, initials: '${c['initials'] ?? ''}', colors: AppColors.avatarCode('${c['avatar_color'] ?? 'c1'}')),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                        Text('${c['full_name']}', style: AppText.s(13.5, W.w7)),
                        Text(['${a['goal'] ?? ''}', '${a['trainer'] ?? ''}'].where((x) => x.isNotEmpty).join(' · '), style: AppText.s(12, W.w5, color: AppColors.muted)),
                      ]),
                    ),
                    AppBadge(custom ? 'Custom' : 'Master', tone: custom ? Tone.warn : Tone.info, plain: true),
                    const AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.muted),
                  ]),
                ),
              );
            }(),
          const SizedBox(height: 14),
          _note(const TextSpan(children: [
            TextSpan(text: 'Master', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' follows this plan as it is. '),
            TextSpan(text: 'Custom', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' has changes made only for that client, which stay when the master plan is updated.'),
          ])),
          const SizedBox(height: 8),
        ]);
      },
    ),
    footer: (ctx) => [
      if (!ctx.isPhone) Expanded(child: CutText(subOf(m.clientCount), style: AppText.cap, maxLines: 1, overflow: TextOverflow.ellipsis)),
      AppButton('Close', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      if (m.canAssign && !m.archived)
        AppButton.primary(m.clientCount > 0 ? 'Change clients' : 'Assign clients', icon: AppIcons.assign, expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop(true)),
    ],
  );
}
