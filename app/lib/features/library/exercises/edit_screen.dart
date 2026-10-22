import 'dart:async';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../app/shell/page.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/leave/leave_guard.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import '../../../core/widgets/tabs.dart';
import '../../client/train/train_parts.dart' show BodyMap;
import '../../trainer/me/me_docs.dart' show DashedBox;
import '../../trainer/me/me_pick.dart';
import '../lib_common.dart';
import 'ex_common.dart';
import '../../../core/widgets/tooltip.dart';

/// New / Edit exercise (boards `ExerciseAdd` / `ExerciseAddMobile`): Basics, Default sets and reps, How to, Form
/// cues, Video and image, Muscles (chips and the tappable body map). Everything the Exercise page shows is filled
/// in here. Only custom exercises open here; built-in ones are Duplicate to edit.
class ExerciseEditScreen extends StatefulWidget {
  const ExerciseEditScreen({super.key, this.id});

  /// null: a new exercise.
  final String? id;
  @override
  State<ExerciseEditScreen> createState() => _ExerciseEditScreenState();
}

// Board chips → muscle_group (+ primary_muscle for Glutes).
const _primaryChips = ['Chest', 'Back', 'Legs', 'Shoulders', 'Arms', 'Core', 'Glutes'];
const _alsoChips = ['Chest', 'Back', 'Shoulders', 'Triceps', 'Biceps', 'Forearms', 'Core', 'Glutes', 'Hamstrings', 'Quads', 'Calves'];
const _group = {'Chest': 'chest', 'Back': 'back', 'Legs': 'legs', 'Shoulders': 'shoulders', 'Arms': 'arms', 'Core': 'core', 'Glutes': 'legs', 'Cardio': 'cardio'};
const _reg = {
  'Chest': ['chest'], 'Back': ['back', 'traps', 'lowback'], 'Legs': ['quads', 'hamstrings', 'calves'], 'Shoulders': ['shoulders'],
  'Arms': ['biceps', 'triceps', 'forearms'], 'Core': ['abs', 'obliques'], 'Glutes': ['glutes'], 'Hamstrings': ['hamstrings'], 'Quads': ['quads'],
  'Calves': ['calves'], 'Triceps': ['triceps'], 'Biceps': ['biceps'], 'Forearms': ['forearms'],
};
const _r2m = {
  'chest': 'Chest', 'shoulders': 'Shoulders', 'biceps': 'Biceps', 'triceps': 'Triceps', 'forearms': 'Forearms', 'abs': 'Core', 'obliques': 'Core',
  'traps': 'Back', 'back': 'Back', 'lowback': 'Back', 'quads': 'Quads', 'hamstrings': 'Hamstrings', 'glutes': 'Glutes', 'calves': 'Calves',
};
const _what = {
  'Chest': 'push the arms forward', 'Back': 'pull the shoulder blades back', 'Shoulders': 'lift the arm', 'Triceps': 'straighten the arm at the top',
  'Biceps': 'bend the elbow', 'Forearms': 'hold the grip', 'Core': 'keep the body still', 'Glutes': 'drive the hips forward', 'Hamstrings': 'bend the knee',
  'Quads': 'straighten the knee', 'Calves': 'push through the toes',
};
// Client logs tab → (log_type, reps label, default reps, caption).
const _logs = {
  'w': ('weight_reps', 'Reps', '8–12', 'Client logs kg × reps per set, or Bodyweight (BW, BW+5, BW−10 for assistance).'),
  't': ('time', 'Time per set', '30 s', 'Client logs seconds per set, for holds like plank or wall sit.'),
  'c': ('distance', 'Minutes', '20 min', 'Client logs minutes and distance (km). Speed, incline or level go in the program note.'),
};

class _ExerciseEditScreenState extends State<ExerciseEditScreen> {
  Map? old;
  bool ready = false, allowed = false, saving = false, dirty = false;
  ApiError? loadErr;
  String? nameErr, formErr, ytErr, coverErr;

  final name = TextEditingController(), reps = TextEditingController(text: '8–12'), tempo = TextEditingController(), yt = TextEditingController();
  String equipment = 'barbell', level = 'intermediate', lt = 'w', primary = 'Chest';
  int sets = 3, rest = 90, rpe = 0;
  final steps = <TextEditingController>[], cues = <TextEditingController>[];
  final also = <String>[];
  final lv = <String, String>{};
  final notes = <String, TextEditingController>{};

  // video and cover
  String vsrc = 'lib', cover = 'frame';
  Map? video; // content library item
  Map? ytInfo;
  bool ytLoading = false;
  Timer? _ytDebounce;
  // "Frame from the video": real stills from the picked video (exercises/frames/, D-42)
  List<Map> frames = const [];
  bool framesLoading = false;
  String? frameKey, _framesFor;
  (String, Uint8List)? coverFile;
  String? coverUrl; // the uploaded cover the exercise has now
  bool dragging = false;
  void Function() _unwatch = () {};

  @override
  void initState() {
    super.initState();
    for (final c in [name, reps, tempo]) {
      c.addListener(_touch);
    }
    LeaveGuard.register(this, _askLeave);
    _load();
  }

  @override
  void dispose() {
    // after the tree settles: the library under this page reloads its cards
    Future.microtask(() => exercisesChanged.value++);
    LeaveGuard.unregister(this);
    _unwatch();
    _ytDebounce?.cancel();
    for (final c in [name, reps, tempo, yt, ...steps, ...cues, ...notes.values]) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _touch() => dirty = true;

  void _set(VoidCallback f) => setState(() {
        f();
        dirty = true;
      });

  TextEditingController _line([String text = '']) => TextEditingController(text: text)..addListener(_touch);

  Future<void> _load() async {
    setState(() => loadErr = null);
    try {
      if (widget.id == null) {
        final f = await Services.api.get<Map>('exercises/facets/');
        allowed = (f['can'] as Map?)?['create'] == true;
      } else {
        final x = await Services.api.get<Map>('exercises/${widget.id}/');
        old = x;
        allowed = x['can_edit'] == true;
        _fill(x);
        final vid = x['video'];
        if (vid != null) {
          try {
            video = await Services.api.get<Map>('content/$vid/');
          } on ApiError catch (_) {
            final m = x['media'] as Map?;
            video = {'id': vid, 'title': m?['title'] ?? x['video_title'] ?? 'Video', 'duration_seconds': m?['duration'] ?? 0, 'cover_url': m?['cover']};
          }
        }
      }
    } on ApiError catch (e) {
      loadErr = e;
    }
    if (steps.isEmpty) steps.add(_line());
    if (cues.isEmpty) cues.add(_line());
    if (!mounted) return;
    setState(() {
      ready = true;
      dirty = false;
    });
    _loadFrames();
    if (kIsWeb) {
      _unwatch = watchDrops(onOver: (o) => setState(() => dragging = o && cover == 'up'), onFile: (f) {
        if (cover == 'up') _takeCover(f);
      });
    }
  }

  void _fill(Map x) {
    name.text = '${x['name'] ?? ''}';
    equipment = '${x['equipment'] ?? 'barbell'}';
    level = '${x['level'] ?? 'beginner'}';
    lt = switch ('${x['log_type']}') { 'time' => 't', 'distance' => 'c', _ => 'w' };
    final g = '${x['muscle_group']}';
    primary = g == 'legs' && '${x['primary_muscle']}'.toLowerCase().contains('glute')
        ? 'Glutes'
        : (_group.entries.firstWhere((e) => e.value == g, orElse: () => const MapEntry('Chest', 'chest')).key);
    sets = (x['default_sets'] as num?)?.toInt() ?? 3;
    reps.text = '${x['default_reps'] ?? ''}';
    rest = (x['default_rest_seconds'] as num?)?.toInt() ?? 90;
    rpe = (x['default_rpe'] as num?)?.toInt() ?? 0;
    tempo.text = '${x['default_tempo'] ?? ''}';
    for (final s in (x['how_to'] as List? ?? const [])) {
      steps.add(_line('$s'));
    }
    for (final s in (x['form_cues'] as List? ?? const [])) {
      cues.add(_line('$s'));
    }
    for (final a in (x['also_works'] as List? ?? const [])) {
      final m = '${(a as Map)['muscle']}';
      if (also.contains(m)) continue;
      also.add(m);
      lv[m] = a['level'] == 'strong' ? 'strong' : 'light';
      notes[m] = _line('${a['note'] ?? ''}');
    }
    final link = '${x['youtube_url'] ?? ''}';
    if (x['video'] == null && link.isNotEmpty) {
      vsrc = 'yt';
      yt.text = link;
      _ytLookup(link);
    }
    coverUrl = x['cover_image'] as String?;
    cover = coverUrl != null ? 'up' : 'frame';
    final f = '${x['cover_frame'] ?? ''}';
    frameKey = f.isEmpty ? null : f;
  }

  /// Loads the stills of the video now picked (library upload or YouTube link). A frame key the new video doesn't
  /// have falls back to its second still, like the board's default.
  Future<void> _loadFrames() async {
    final q = vsrc == 'lib'
        ? (video == null ? null : {'video': '${video!['id']}'})
        : (ytInfo == null ? null : {'url': yt.text.trim()});
    final sig = q?.toString();
    if (sig == _framesFor) return;
    _framesFor = sig;
    if (q == null) {
      setState(() => frames = const []);
      return;
    }
    setState(() => framesLoading = true);
    try {
      final r = await Services.api.get<Map>('exercises/frames/', query: q);
      if (!mounted || _framesFor != sig) return;
      final list = [for (final f in (r['frames'] as List? ?? const [])) f as Map];
      setState(() {
        frames = list;
        if (list.isNotEmpty && !list.any((f) => f['key'] == frameKey)) frameKey = '${list[list.length > 1 ? 1 : 0]['key']}';
      });
    } on ApiError {
      if (mounted && _framesFor == sig) setState(() => frames = const []);
    }
    if (mounted && _framesFor == sig) setState(() => framesLoading = false);
  }

  // ─────────────────────────────── muscles

  void _pickPrimary(String m) => _set(() {
        primary = m;
        if (also.remove(m)) notes.remove(m)?.dispose();
      });

  void _toggle(String m) {
    if (m == primary) return;
    if (also.contains(m)) {
      _set(() {
        also.remove(m);
        notes.remove(m)?.dispose();
      });
      return;
    }
    if (also.length >= 8) {
      showToast(context, 'Up to 8 muscles', sub: 'Remove one to add $m.', kind: ToastKind.err);
      return;
    }
    _set(() {
      also.add(m);
      lv[m] ??= 'light';
      notes[m] = _line();
    });
  }

  void _tapRegion(String r) {
    if ((_reg[primary] ?? const []).contains(r)) return;
    final m = _r2m[r];
    if (m != null) _toggle(m);
  }

  Map<String, String> get _map {
    final out = <String, String>{};
    for (final m in also) {
      for (final r in _reg[m] ?? regionsFallback(m)) {
        out[r] = lv[m] == 'strong' ? 's' : 'l';
      }
    }
    for (final r in _reg[primary] ?? const <String>[]) {
      out[r] = 'p';
    }
    return out;
  }

  /// A muscle saved before (not one of the chips) still lights up its region.
  List<String> regionsFallback(String m) => [for (final e in _r2m.entries) if (m.toLowerCase().contains(e.value.toLowerCase())) e.key];

  // ─────────────────────────────── video and cover

  void _ytChanged(String v) {
    _ytDebounce?.cancel();
    setState(() {
      dirty = true;
      ytErr = null;
      ytInfo = null;
    });
    if (v.trim().isEmpty) return;
    _ytDebounce = Timer(const Duration(milliseconds: 500), () => _ytLookup(v.trim()));
  }

  Future<void> _ytLookup(String url) async {
    setState(() => ytLoading = true);
    try {
      final r = await Services.api.get<Map>('exercises/youtube-info/', query: {'url': url});
      if (mounted && yt.text.trim() == url) {
        setState(() => ytInfo = r);
        _loadFrames();
      }
    } on ApiError catch (e) {
      if (mounted && yt.text.trim() == url) setState(() => ytErr = e.field('url') ?? e.message);
    }
    if (mounted) setState(() => ytLoading = false);
  }

  Future<void> _pickVideo() async {
    final r = await showModalVideoPicker(context, video?['id']?.toString());
    if (r != null) {
      _set(() => video = r);
      _loadFrames();
    }
  }

  Future<void> _pickCover() async {
    final r = await pickDocument();
    if (r != null) _takeCover(r);
  }

  void _takeCover((String, Uint8List) r) {
    final ext = r.$1.split('.').last.toLowerCase();
    _set(() {
      dragging = false;
      if (!['jpg', 'jpeg', 'png'].contains(ext)) {
        coverErr = 'Upload a JPG or PNG.';
      } else if (r.$2.length > 5 * 1024 * 1024) {
        coverErr = 'This image is over 5 MB. Pick a smaller one.';
      } else {
        coverFile = r;
        coverErr = null;
      }
    });
  }

  // ─────────────────────────────── save

  String get _back => widget.id == null ? '/exercises' : '/exercises/${widget.id}';

  Future<void> _cancel() async {
    if (!await _askLeave(context) || !mounted) return;
    context.go(_back);
  }

  /// Also asked by the router when the page closes another way (sidebar, tabs, back) (D-43).
  Future<bool> _askLeave(BuildContext context) async {
    if (!dirty) return true;
    final ok = await confirmAction(context,
        title: 'Leave without saving?', body: 'Your changes to this exercise are not saved.', confirm: 'Leave', danger: true, icon: AppIcons.alert);
    if (ok) dirty = false;
    return ok;
  }

  Future<void> _save() async {
    final n = name.text.trim();
    setState(() {
      nameErr = n.length < 2 ? 'Enter the exercise name.' : null;
      formErr = null;
    });
    if (nameErr != null) return;
    if (vsrc == 'yt' && yt.text.trim().isNotEmpty && ytInfo == null) {
      setState(() => ytErr ??= 'Check the YouTube link.');
      return;
    }
    final keepPrimary = old != null && old!['muscle_group'] == _group[primary] && (primary != 'Glutes');
    final type = _logs[lt]!.$1 == 'weight_reps' && old?['log_type'] == 'bodyweight_reps' ? 'bodyweight_reps' : _logs[lt]!.$1;
    final body = {
      'name': n,
      'equipment': equipment,
      'level': level,
      'muscle_group': _group[primary],
      'primary_muscle': primary == 'Glutes' ? 'Glutes' : (keepPrimary ? '${old!['primary_muscle'] ?? ''}' : ''),
      'also_works': [for (final m in also) {'muscle': m, 'level': lv[m] ?? 'light', 'note': notes[m]?.text.trim() ?? ''}],
      'log_type': type,
      'default_sets': sets,
      'default_reps': reps.text.trim().isEmpty ? _logs[lt]!.$3 : reps.text.trim(),
      'default_rest_seconds': rest,
      'default_rpe': rpe == 0 ? null : rpe,
      'default_tempo': tempo.text.trim(),
      'how_to': [for (final c in steps) if (c.text.trim().isNotEmpty) c.text.trim()],
      'form_cues': [for (final c in cues) if (c.text.trim().isNotEmpty) c.text.trim()],
      'video': vsrc == 'lib' ? (video?['id']) : null,
      'youtube_url': vsrc == 'yt' ? yt.text.trim() : '',
      'cover_frame': cover == 'frame' && frames.isNotEmpty ? (frameKey ?? '') : '',
      if (cover == 'frame' && _frameAt != null) 'cover_at_seconds': _frameAt,
    };
    setState(() => saving = true);
    try {
      final r = widget.id == null ? await Services.api.post<Map>('exercises/', body) : await Services.api.patch<Map>('exercises/${widget.id}/', body);
      final id = r['id'];
      String? coverNote;
      try {
        if (cover == 'up' && coverFile != null) {
          await Services.api.post('exercises/$id/cover/', FormData.fromMap({'file': MultipartFile.fromBytes(coverFile!.$2, filename: coverFile!.$1)}));
        } else if (coverUrl != null && (cover == 'frame' || coverFile == null && _coverRemoved)) {
          await Services.api.delete('exercises/$id/cover/');
        }
      } on ApiError catch (e) {
        coverNote = e.message;
      }
      if (!mounted) return;
      dirty = false;
      context.go('/exercises/$id');
      if (coverNote != null) {
        showToast(context, 'Saved, but the cover image did not upload', sub: coverNote, kind: ToastKind.err);
      } else {
        showToast(context, widget.id == null ? 'Exercise added' : 'Exercise saved', sub: n);
      }
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        saving = false;
        nameErr = e.field('name');
        formErr = nameErr == null ? e.message : null;
      });
      if (formErr != null) showToast(context, 'Could not save the exercise', sub: formErr, kind: ToastKind.err);
    }
  }

  bool _coverRemoved = false;

  int? get _frameAt => (frames.firstWhere((f) => f['key'] == frameKey, orElse: () => const {})['at'] as num?)?.toInt();

  // ─────────────────────────────── build

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final title = widget.id == null ? 'New exercise' : 'Edit exercise';
    if (!ready) {
      return StaffPage(children: [_crumb(title), const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)))]);
    }
    if (loadErr != null || !allowed) {
      final gone = loadErr?.status == 404;
      return StaffPage(children: [
        _crumb(title),
        AppCard(
          child: EmptyState(
            loadErr == null ? (old?['is_builtin'] == true ? 'Built-in exercises do not change' : 'You can not change exercises') : (gone ? 'This exercise is gone' : 'Could not open this exercise'),
            icon: AppIcons.dumbbell,
            sub: loadErr == null
                ? (old?['is_builtin'] == true ? 'Use Duplicate to edit on the exercise page to make your own copy.' : 'Your access does not include "Add custom exercises". Ask the admin.')
                : (gone ? 'It may have been deleted.' : loadErr!.message),
            action: AppButton(loadErr != null && !gone ? 'Try again' : 'Back', onPressed: loadErr != null && !gone ? _load : () => context.go(_back)),
          ),
        ),
      ]);
    }
    final page = StaffPage(
      maxWidth: 1180,
      header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 10 : 14, children: [
        _crumb(title),
        PageTop(
          title: title,
          sub: 'Everything the exercise page shows is filled in here.',
          actions: [
            AppButton('Cancel', kind: phone ? BtnKind.text : BtnKind.outline, onPressed: _cancel),
            AppButton.primary('Save exercise', icon: AppIcons.check, loading: saving, onPressed: _save),
          ],
        ),
      ]),
      children: [
        LayoutBuilder(builder: (context, c) {
          final gap = phone ? 14.0 : 20.0;
          final left = [_basics(phone), _defaults(phone), _steps(phone), _cues(phone)];
          final right = [_media(phone), _muscles(phone)];
          // one column: kept to a readable width so the inputs do not stretch across a tablet
          if (c.maxWidth < 820) {
            return Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: gap, children: [...left, ...right]),
              ),
            );
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: gap, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: gap, children: left)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: gap, children: right)),
          ]);
        }),
      ],
    );
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (did, _) {
        if (!did) _cancel();
      },
      child: page,
    );
  }

  Widget _crumb(String t) => Row(spacing: 6, children: [
        Hover(
          onTap: () => context.go('/exercises'),
          builder: (_, h, _) => Text('Exercises', style: AppText.s(13, W.w5, color: h ? AppColors.text : AppColors.muted)),
        ),
        const AppIcon(AppIcons.chevronRight, size: 13, color: AppColors.chevron),
        Flexible(child: CutText(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w6))),
      ]);

  Widget _card(bool phone, List<Widget> children, {double gap = 14}) => AppCard(
        padding: EdgeInsets.all(phone ? 14 : 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: gap, children: children),
      );

  /// `.sec-h`: title left, caption right (stacked on a phone).
  Widget _secH(String t, String cap, bool phone, {String? extra}) {
    final head = Text.rich(TextSpan(text: t, children: [if (extra != null) TextSpan(text: ' $extra', style: AppText.cap.copyWith(fontWeight: FontWeight.w500))]), style: AppText.h3);
    // the note sits under the title, never floating in the middle of the card
    return Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [head, Text(cap, style: AppText.cap)]);
  }

  Widget _field(String label, Widget child, {String? hint, String? error, bool stretch = true}) => Column(crossAxisAlignment: stretch ? CrossAxisAlignment.stretch : CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, spacing: 6, children: [
        Text(label, style: AppText.label),
        child,
        if (error != null)
          Text(error, style: AppText.s(12, W.w6, color: AppColors.badText))
        else if (hint != null)
          Text(hint, style: AppText.cap),
      ]);

  Widget _tabs<T>(List<(T, String)> items, T value, ValueChanged<T> on, {bool expand = false, double height = 28}) => SegmentedTabs<T>(
        items: [for (final (v, l) in items) TabItem(v, l)],
        value: value,
        onChanged: on,
        expand: expand,
        height: height,
      );

  // ─────────────────────────────── left column

  Widget _basics(bool phone) {
    final equip = _field(
      'Equipment',
      AppSelect(equipmentLabels[equipment] ?? equipment, entries: [
        for (final e in equipmentLabels.entries) MenuEntry(e.value, selected: e.key == equipment, onTap: () => _set(() => equipment = e.key)),
      ]),
    );
    final lvl = _field('Level', _tabs([for (final e in levelLabels.entries) (e.key, e.value)], level, (v) => _set(() => level = v), expand: phone, height: 30), stretch: phone);
    return _card(phone, gap: 16, [
      Text('Basics', style: AppText.h3),
      AppTextField(
        label: 'Name',
        controller: name,
        placeholder: 'e.g. Landmine Press (half-kneeling)',
        error: nameErr,
        onChanged: (_) {
          if (nameErr != null) setState(() => nameErr = null);
        },
      ),
      if (phone)
        ...[equip, lvl]
      else
        // side by side only when Equipment still gets room for its longest word
        LayoutBuilder(
          builder: (_, b) => b.maxWidth < 500
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [equip, Align(alignment: Alignment.centerLeft, child: lvl)])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [Expanded(child: equip), lvl]),
        ),
    ]);
  }

  Widget _defaults(bool phone) {
    final l = _logs[lt]!;
    final setsF = _field('Sets', LibStepper(value: sets, unit: '', min: 1, max: 12, height: 36, onChanged: (v) => _set(() => sets = v)));
    final repsF = _field(l.$2, AppTextField(controller: reps, placeholder: l.$3));
    final restF = _field('Rest', LibStepper(value: rest, unit: 's', min: 0, max: 300, step: 15, height: 36, onChanged: (v) => _set(() => rest = v)));
    final rpeF = _field('RPE (0 = not set)', LibStepper(value: rpe, unit: '', min: 0, max: 10, height: 36, onChanged: (v) => _set(() => rpe = v)));
    final tempoF = _field('Tempo (optional)', AppTextField(controller: tempo, placeholder: 'e.g. 3-1-1'));
    Widget row(List<Widget> c) => Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [for (final w in c) Expanded(child: w)]);
    return _card(phone, [
      _secH('Default sets and reps', 'Filled in when added to a program', phone),
      _field(
        'Client logs',
        Align(
          alignment: Alignment.centerLeft,
          child: _tabs(const [('w', 'Weight & reps'), ('t', 'Time'), ('c', 'Cardio')], lt, (v) {
            _set(() {
              final was = _logs[lt]!.$3;
              if (reps.text.trim().isEmpty || reps.text.trim() == was) reps.text = _logs[v]!.$3;
              lt = v;
              if (v == 'c' && primary != 'Cardio' && old == null) primary = 'Cardio';
              if (v != 'c' && primary == 'Cardio') primary = 'Chest';
            });
          }, expand: phone, height: 30),
        ),
        hint: l.$4,
      ),
      if (phone) ...[
        row([setsF, repsF]),
        row([restF, rpeF]),
        tempoF,
      ] else ...[
        row([setsF, repsF, restF]),
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [Expanded(child: rpeF), Expanded(flex: 2, child: tempoF)]),
      ],
      Text('Every program day can change these. The client sees what the program day says.', style: AppText.cap),
    ]);
  }

  /// How to / Form cues: one input per line, × to remove. "Add step" / "Add cue" adds the next line (typing never
  /// adds one by itself); empty lines are dropped on save.
  Widget _lines(List<TextEditingController> list, {required bool numbered, required String ph, required String removeTip}) {
    final rows = <Widget>[];
    for (final (i, c) in list.indexed) {
      final last = c.text.trim().isEmpty;
      rows.add(Row(key: ObjectKey(c), spacing: 10, children: [
        if (numbered)
          Container(
            constraints: const BoxConstraints(minWidth: 20),
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: last ? AppColors.sub : AppColors.accentSoft, borderRadius: AppRadius.all(10)),
            child: Text('${i + 1}', style: AppText.s(11, W.w7, color: last ? AppColors.muted : AppColors.accentText)),
          )
        else
          AppIcon(AppIcons.check, size: 15, color: last ? AppColors.line2 : AppColors.okText, stroke: 2.2),
        Expanded(
          child: AppTextField(
            controller: c,
            focusNode: _focus.putIfAbsent(c, FocusNode.new),
            placeholder: ph,
            onChanged: (v) {
              if (v.trim().isEmpty != last) setState(() {});
            },
          ),
        ),
        if (list.length == 1)
          const SizedBox(width: 30)
        else
          AppIconButton(AppIcons.close, tooltip: removeTip, small: true, ghost: true, onPressed: () => _set(() {
                    final c = list.removeAt(i);
                    _focus.remove(c)?.dispose();
                    c.dispose();
                  })),
      ]));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: rows);
  }

  final _focus = <TextEditingController, FocusNode>{};

  Widget _steps(bool phone) => _card(phone, [
        _secH('How to', 'Shows on the How to tab', phone),
        _lines(steps, numbered: true, ph: 'Add a step', removeTip: 'Remove step'),
        Align(alignment: Alignment.centerLeft, child: AppButton('Add step', icon: AppIcons.plus, kind: BtnKind.text, onPressed: () => _addLine(steps))),
      ]);

  Widget _cues(bool phone) => _card(phone, [
        _secH('Form cues', 'Shows on the Form cues tab', phone, extra: '(optional)'),
        _lines(cues, numbered: false, ph: 'Add a cue', removeTip: 'Remove cue'),
        Align(alignment: Alignment.centerLeft, child: AppButton('Add cue', icon: AppIcons.plus, kind: BtnKind.text, onPressed: () => _addLine(cues))),
      ]);

  /// "Add step": a new empty line under the last one (or the empty last line); the cursor goes to it.
  void _addLine(List<TextEditingController> list) {
    if (list.isEmpty || list.last.text.trim().isNotEmpty) setState(() => list.add(_line()));
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus[list.last]?.requestFocus());
  }

  // ─────────────────────────────── right column

  Widget _media(bool phone) {
    final tone = vsrc == 'lib' && video != null ? exTone(video!) : 2;
    return _card(phone, [
      _secH('Video and image', 'Shows at the top of the exercise page', phone),
      _field(
        'Video',
        Align(
          alignment: Alignment.centerLeft,
          child: _tabs(const [('lib', 'From content library'), ('yt', 'YouTube link')], vsrc, (v) {
            _set(() => vsrc = v);
            _loadFrames();
          }, expand: phone, height: 30),
        ),
      ),
      if (vsrc == 'lib') ...[
        _vrow(
          thumb: _thumb(video == null ? null : '${video!['cover_url'] ?? ''}', tone, video == null ? null : clock(video!['duration_seconds']), phone: phone),
          title: video == null ? 'No video yet' : '${video!['title']}',
          sub: video == null ? 'Pick one from your Content library' : _libSub(video!),
          trailing: AppButton(video == null ? 'Pick video' : 'Change', size: BtnSize.sm, onPressed: _pickVideo),
          phone: phone,
        ),
        Text('Videos you upload in the Content library show up here.', style: AppText.cap),
      ] else ...[
        AppTextField(
          controller: yt,
          placeholder: 'Paste a YouTube link',
          keyboard: TextInputType.url,
          error: ytErr,
          onChanged: _ytChanged,
          suffix: ytLoading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)) : null,
        ),
        if (ytInfo != null)
          _vrow(
            thumb: _thumb('${ytInfo!['thumb'] ?? ''}', 2, 'YouTube', yt: true, phone: phone),
            title: '${ytInfo!['title'] ?? ''}'.isEmpty ? 'YouTube video' : '${ytInfo!['title']}',
            sub: ['YouTube', if ('${ytInfo!['author'] ?? ''}'.isNotEmpty) '${ytInfo!['author']}'].join(' · '),
            trailing: AppIconButton(AppIcons.close, tooltip: 'Remove video', small: true, ghost: true, onPressed: () {
              yt.clear();
              _set(() => ytInfo = null);
              _loadFrames();
            }),
            phone: phone,
          ),
        Text('Plays inside the app. Public or unlisted videos only.', style: AppText.cap),
      ],
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: _field(
          'Cover image',
          Align(
            alignment: Alignment.centerLeft,
            child: _tabs(const [('frame', 'Frame from the video'), ('up', 'Upload image')], cover, (v) => _set(() => cover = v), expand: phone, height: 30),
          ),
        ),
      ),
      if (cover == 'frame')
        _frameTiles(phone, tone)
      else
        _drop(phone),
      if (coverErr != null) Text(coverErr!, style: AppText.s(12, W.w6, color: AppColors.badText)),
      Text('The cover shows in the exercise library, the program builder and the client app.', style: AppText.cap),
    ]);
  }

  /// Four stills from the video to pick the cover from; tinted tiles while they load or when one couldn't be grabbed.
  Widget _frameTiles(bool phone, int tone) {
    if (frames.isEmpty && !framesLoading) {
      final none = vsrc == 'lib' ? video == null : ytInfo == null;
      return Text(none ? 'Pick a video first, then choose a frame from it.' : 'No frames could be taken from this video. Upload an image instead.',
          style: AppText.s(12.5, W.w5, color: AppColors.muted));
    }
    final list = framesLoading ? <Map>[for (var i = 0; i < 4; i++) const {}] : frames;
    return LayoutBuilder(builder: (context, c) {
      final w = phone ? ((c.maxWidth - 24) / 4).clamp(72.0, 110.0) : 84.0;
      // scrolls sideways when the card is too narrow for every frame
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(spacing: phone ? 8 : 10, children: [
        for (final (i, f) in list.indexed)
          Hover(
            onTap: f.isEmpty ? null : () => _set(() => frameKey = '${f['key']}'),
            builder: (_, h, _) {
              final on = f.isNotEmpty && frameKey == f['key'];
              final (a, b) = AppColors.mediaTiles[(tone + i) % 4];
              final tile = Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b])),
                child: framesLoading
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.mediaFg))
                    : const AppIcon(AppIcons.dumbbell, size: 20, color: AppColors.mediaFg, stroke: 1.6),
              );
              final url = f['url'] as String?;
              return Column(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                      borderRadius: AppRadius.all(11), border: Border.all(color: on ? AppColors.accent : (h && f.isNotEmpty ? AppColors.line2 : Colors.transparent), width: 2)),
                  child: ClipRRect(
                    borderRadius: AppRadius.all(8),
                    child: SizedBox(
                      width: w - 8,
                      height: (w - 8) * (phone ? 10 / 16 : 54 / 84),
                      child: url == null ? tile : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => tile),
                    ),
                  ),
                ),
                Text(f.isEmpty ? ' ' : '${f['label']}', style: AppText.s(11.5, W.w6, color: on ? AppColors.accentText : AppColors.muted)),
              ]);
            },
          ),
        ]),
      );
    });
  }

  String _libSub(Map v) {
    final parts = ['Content library'];
    final d = (v['duration_seconds'] as num?)?.toInt() ?? 0;
    if (d > 0) parts.add(clock(d));
    final at = DateTime.tryParse('${v['created_at'] ?? ''}');
    if (at != null) parts.add('added ${DateFormat('d MMM').format(at.toLocal())}');
    return parts.join(' · ');
  }

  /// `.ex-vrow`: thumbnail, title and line, then a button.
  Widget _vrow({required Widget thumb, required String title, required String sub, required Widget trailing, required bool phone}) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.line)),
        child: Row(spacing: 12, children: [
          thumb,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              CutText(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7)),
              CutText(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
            ]),
          ),
          trailing,
        ]),
      );

  Widget _thumb(String? url, int tone, String? badge, {bool yt = false, required bool phone, double w = 96, double h = 60}) {
    if (phone) (w, h) = (72, 46);
    final (a, b) = AppColors.mediaTiles[tone];
    final tile = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b])),
      child: const AppIcon(AppIcons.dumbbell, size: 22, color: AppColors.mediaFg, stroke: 1.6),
    );
    return ClipRRect(
      borderRadius: AppRadius.all(8),
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(fit: StackFit.expand, children: [
          tile,
          if (url != null && url.isNotEmpty) Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => tile),
          if (badge != null)
            Positioned(
              left: 5,
              bottom: 5,
              child: Container(
                height: 16,
                padding: const EdgeInsets.fromLTRB(3, 0, 5, 0),
                decoration: BoxDecoration(color: yt ? AppColors.ytRed : AppColors.playBadge, borderRadius: AppRadius.all(8)),
                child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
                  const AppIcon(AppIcons.play, size: 9, color: AppColors.white, fill: true),
                  Text(badge, style: AppText.s(9.5, W.w7, color: AppColors.white)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  /// `.ex-drop`: drop an image or browse; once picked, the picture with Remove.
  Widget _drop(bool phone) {
    final file = coverFile;
    final has = file != null || (coverUrl != null && !_coverRemoved);
    final zone = Hover(
      onTap: _pickCover,
      builder: (_, h, _) => CustomPaint(
        foregroundPainter: DashedBox(color: coverErr != null ? AppColors.badText : (dragging ? AppColors.accent : AppColors.line2), radius: 10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: dragging ? AppColors.accentSoft : (h ? AppColors.hover : AppColors.caWebBg), borderRadius: AppRadius.all(10)),
          child: Row(crossAxisAlignment: phone ? CrossAxisAlignment.start : CrossAxisAlignment.center, spacing: 12, children: [
            if (has)
              ClipRRect(
                borderRadius: AppRadius.all(8),
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: file != null ? Image.memory(file.$2, fit: BoxFit.cover) : Image.network(coverUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
                ),
              )
            else
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: AppRadius.all(10)),
                child: const AppIcon(AppIcons.upload, size: 18, color: AppColors.accent),
              ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                if (dragging)
                  Text('Drop it to use this image', style: AppText.s(13.5, W.w6, color: AppColors.accentText))
                else if (has)
                  CutText(file?.$1 ?? 'Current cover image', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w6))
                else
                  Text.rich(TextSpan(text: kIsWeb || !phone ? 'Drop an image here or ' : 'Pick an image or ', children: [
                    TextSpan(text: 'browse', style: AppText.s(13.5, W.w6, color: AppColors.accentText)),
                  ]), style: AppText.s(13.5, W.w6)),
                Text(has ? 'Click to pick another' : 'JPG or PNG, up to 5 MB. Square or 4:3 looks best.', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
              ]),
            ),
            if (has)
              AppIconButton(AppIcons.close, tooltip: 'Remove image', small: true, ghost: true, onPressed: () => _set(() {
                    coverFile = null;
                    if (file == null) _coverRemoved = true;
                  })),
          ]),
        ),
      ),
    );
    if (kIsWeb) return zone;
    return DropTarget(
      onDragEntered: (_) => setState(() => dragging = true),
      onDragExited: (_) => setState(() => dragging = false),
      onDragDone: (d) async {
        final f = d.files.whereType<DropItemFile>().firstOrNull;
        setState(() => dragging = false);
        if (f != null) _takeCover((f.name, await f.readAsBytes()));
      },
      child: zone,
    );
  }

  Widget _muscles(bool phone) {
    final prim = [..._primaryChips, if (lt == 'c' || primary == 'Cardio') 'Cardio'];
    final map = Column(crossAxisAlignment: CrossAxisAlignment.center, spacing: 6, children: [
      BodyMap(_map, onTap: _tapRegion),
      Text('Tap a muscle to add or remove it.', textAlign: TextAlign.center, style: AppText.cap),
    ]);
    final rows = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('HOW MUCH IT WORKS THEM', style: AppText.over),
      for (final (i, m) in also.indexed)
        Container(
          key: ValueKey(m),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
            Row(spacing: 8, children: [
              Expanded(child: CutText(m, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7))),
              _tabs(const [('light', 'Light'), ('strong', 'Strong')], lv[m] ?? 'light', (v) => _set(() => lv[m] = v), height: 26),
              AppIconButton(AppIcons.close, tooltip: 'Remove', small: true, ghost: true, onPressed: () => _toggle(m)),
            ]),
            AppTextField(controller: notes[m], height: 32, fontSize: 13, placeholder: 'e.g. ${_what[m] ?? 'helps keep the position'}'),
          ]),
        ),
      if (also.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Pick muscles above, or tap them on the figure.', style: AppText.s(13, W.w5, color: AppColors.muted))),
    ]);
    return _card(phone, gap: 16, [
      _secH('Muscles', 'Shows on the Muscles tab', phone),
      _field(
        'Primary muscle',
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in prim) _Chip(m, on: primary == m, strong: true, onTap: () => _pickPrimary(m)),
        ]),
        hint: 'Decides where the exercise shows in the library filter.',
      ),
      _field(
        'Also works (optional)',
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in _alsoChips)
            if (m != primary) _Chip(m, on: also.contains(m), onTap: () => _toggle(m)),
        ]),
      ),
      LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 440) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [map, rows]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [map, Expanded(child: rows)]);
      }),
    ]);
  }
}

/// `.chip` pick: primary is solid blue when on, "also works" is light blue with a blue edge.
class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.on, required this.onTap, this.strong = false});
  final String label;
  final bool on, strong;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          height: 30,
          padding: EdgeInsets.symmetric(horizontal: on && !strong ? 10 : 12),
          decoration: BoxDecoration(
            color: on ? (strong ? AppColors.accent : AppColors.accentSoft) : (h ? AppColors.hover : AppColors.card),
            borderRadius: AppRadius.all(AppRadius.chip),
            border: Border.all(color: on ? AppColors.accent : (h ? AppColors.lineHover : AppColors.line2)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
            if (on && !strong) const AppIcon(AppIcons.check, size: 12, color: AppColors.accentText, stroke: 2.4),
            Text(label, style: AppText.s(12.5, W.w6, color: on ? (strong ? AppColors.white : AppColors.accentText) : AppColors.text2)),
          ]),
        ),
      );
}

// ─────────────────────────────── Pick a video

/// "Pick a video" (from the Content library): search, one pick, Use video. "Upload to library" opens the Content
/// library page.
Future<Map?> showModalVideoPicker(BuildContext context, String? current) async {
  final pick = ValueNotifier<Map?>(null);
  final router = GoRouter.of(context);
  final r = await showAppModal<Map>(
    context,
    title: 'Pick a video',
    body: 'From your Content library',
    icon: AppIcons.play,
    width: 520,
    content: (_) => _VideoList(current: current, pick: pick),
    // Builder: the modal's own context, so pop closes the modal and not the page under it
    lead: Builder(
      builder: (mctx) => Align(alignment: Alignment.centerLeft, child: AppButton('Upload to library', kind: BtnKind.text, onPressed: () {
        Navigator.of(mctx).pop();
        router.go('/content?new=video');
      })),
    ),
    actions: (ctx) => [
      if (ctx.isPhone)
        AppButton('Upload to library', kind: BtnKind.text, onPressed: () {
          Navigator.of(ctx).pop();
          router.go('/content?new=video');
        }),
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      ValueListenableBuilder(
        valueListenable: pick,
        builder: (_, p, _) => AppButton.primary('Use video', expand: ctx.isPhone, onPressed: p == null ? null : () => Navigator.of(ctx).pop(p)),
      ),
    ],
  );
  disposeLater([pick]);
  return r;
}

class _VideoList extends StatefulWidget {
  const _VideoList({required this.current, required this.pick});
  final String? current;
  final ValueNotifier<Map?> pick;
  @override
  State<_VideoList> createState() => _VideoListState();
}

class _VideoListState extends State<_VideoList> {
  List<Map>? rows;
  String? err;
  Timer? _t;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load(String q) async {
    final req = ++_req;
    try {
      final r = await Services.api.get<Map>('content/', query: {'kind': 'video', 'search': q, 'page_size': 50});
      if (!mounted || req != _req) return;
      setState(() {
        rows = [for (final x in r['results'] as List) x as Map];
        err = null;
        if (widget.pick.value == null && widget.current != null) widget.pick.value = rows!.where((x) => '${x['id']}' == widget.current).firstOrNull;
      });
    } on ApiError catch (e) {
      if (mounted && req == _req) setState(() => err = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = rows;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      AppSearchField(placeholder: 'Search videos', icon: AppIcons.search, onChanged: (v) {
        _t?.cancel();
        _t = Timer(const Duration(milliseconds: 300), () => _load(v.trim()));
      }),
      if (err != null)
        EmptyState('Could not load your videos', sub: err)
      else if (list == null)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)))
      else if (list.isEmpty)
        const EmptyState('No videos yet', icon: AppIcons.play, sub: 'Upload one to the Content library first.')
      else
        ValueListenableBuilder(
          valueListenable: widget.pick,
          builder: (_, p, _) => Container(
            constraints: BoxConstraints(maxHeight: context.isPhone ? 300 : 330),
            decoration: BoxDecoration(borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: AppColors.line)),
            child: ClipRRect(
              borderRadius: AppRadius.all(AppRadius.card),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: list.length,
                separatorBuilder: (_, _) => Container(height: 1, color: AppColors.line),
                itemBuilder: (_, i) {
                  final v = list[i], on = p != null && '${p['id']}' == '${v['id']}';
                  final at = DateTime.tryParse('${v['created_at'] ?? ''}');
                  final (a, b) = AppColors.mediaTiles[exTone(v)];
                  final cover = '${v['thumb_url'] ?? v['cover_url'] ?? ''}';
                  return Hover(
                    onTap: () => widget.pick.value = v,
                    builder: (_, h, _) => Container(
                      color: h ? AppColors.caWebBg : null,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      child: Row(spacing: 12, children: [
                        Container(
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: on ? AppColors.accent : AppColors.card, border: Border.all(color: on ? AppColors.accent : AppColors.line2, width: 1.5)),
                          child: on ? const AppIcon(AppIcons.check, size: 12, color: AppColors.white, stroke: 3) : null,
                        ),
                        ClipRRect(
                          borderRadius: AppRadius.all(8),
                          child: SizedBox(
                            width: 72,
                            height: 46,
                            child: Stack(fit: StackFit.expand, children: [
                              Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b]))),
                              if (cover.isNotEmpty) Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
                              Positioned(
                                left: 4,
                                bottom: 4,
                                child: Container(
                                  height: 15,
                                  padding: const EdgeInsets.fromLTRB(3, 0, 5, 0),
                                  decoration: BoxDecoration(color: AppColors.playBadge, borderRadius: AppRadius.all(8)),
                                  child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
                                    const AppIcon(AppIcons.play, size: 8, color: AppColors.white, fill: true),
                                    Text(clock(v['duration_seconds']), style: AppText.s(9, W.w7, color: AppColors.white)),
                                  ]),
                                ),
                              ),
                            ]),
                          ),
                        ),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                            CutText('${v['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7)),
                            CutText(['Video', if (at != null) 'added ${DateFormat('d MMM').format(at.toLocal())}'].join(' · '),
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
                          ]),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
    ]);
  }
}
