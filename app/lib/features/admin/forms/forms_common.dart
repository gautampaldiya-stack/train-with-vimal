import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import '../../../core/widgets/tabs.dart';
import '../../../core/widgets/tooltip.dart';
import '../../trainer/client_profile/cp_content_drawers.dart' show DrSwitch, drField;

/// Shared bits of Forms & check-ins and the Form builder (boards `Forms` / `FormBuilder` and their Mobile boards,
/// D-50): form kinds and answer types with their icons, the status badge, the Create form modal, the fillable
/// client preview and the question editor.

/// (key, label, Create form line, Form type menu label)
const formKinds = [
  ('onboarding', 'Onboarding questionnaire', 'Goal, history, diet and schedule. Filled in once after registration.', 'Onboarding'),
  ('weekly', 'Weekly check-in', 'Weight, measurements and how the week went. Sent on a schedule.', 'Weekly check-ins'),
  ('daily', 'Daily check-in', 'A 30-second morning pulse: weight, sleep and energy.', 'Daily check-ins'),
  ('survey', 'Survey / feedback', 'Program feedback, ratings and quick polls.', 'Surveys'),
  ('waiver', 'Waiver / consent', 'Statements the client agrees to before starting.', 'Waivers'),
];

String kindLabel(String k) => formKinds.firstWhere((x) => x.$1 == k, orElse: () => formKinds[3]).$2;

AppIconData kindIcon(String k) => switch (k) {
      'onboarding' => AppIcons.usersAlt,
      'weekly' => AppIcons.calendarAlt,
      'daily' => AppIcons.sun,
      'survey' => AppIcons.star,
      'waiver' => AppIcons.shield,
      _ => AppIcons.clipboard,
    };

/// `.hb-ic` tone per kind (t1 blue, t2 green, t3 orange, t4 purple; the "All forms" row is green).
(Color, Color) kindTone(String k) => AppColors.hbTones[const {'onboarding': 0, 'weekly': 1, 'daily': 2, 'survey': 3, 'waiver': 0}[k] ?? 1];

/// The 9 answer types (`QT`), API key → label.
const qTypes = [
  ('short', 'Short answer'),
  ('long', 'Long answer'),
  ('number', 'Number'),
  ('single', 'Single choice'),
  ('multiple', 'Multiple choice'),
  ('dropdown', 'Dropdown'),
  ('scale', 'Scale 1–5'),
  ('yes_no', 'Yes / No'),
  ('photo', 'Photo upload'),
];
const choiceTypes = {'single', 'multiple', 'dropdown'};

String qTypeLabel(String t) => qTypes.firstWhere((x) => x.$1 == t, orElse: () => qTypes.first).$2;

AppIconData qTypeIcon(String t) => switch (t) {
      'long' => AppIcons.qLong,
      'number' => AppIcons.qNumber,
      'single' => AppIcons.qSingle,
      'multiple' => AppIcons.qMulti,
      'dropdown' => AppIcons.qDropdown,
      'scale' => AppIcons.qScale,
      'yes_no' => AppIcons.checkCircle,
      'photo' => AppIcons.camera,
      _ => AppIcons.qShort,
    };

String questionsLabel(int n) => '$n ${n == 1 ? 'question' : 'questions'}';

/// "18 Sep"; "just now" within a minute; "today, 4:12 pm".
String fmWhen(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (d == null) return '—';
  final now = DateTime.now();
  if (now.difference(d).inSeconds < 60) return 'just now';
  if (DateUtils.isSameDay(now, d)) return 'today, ${DateFormat('h:mm a').format(d).toLowerCase()}';
  return DateFormat(d.year == now.year ? 'd MMM' : 'd MMM yyyy').format(d);
}

/// Published (green) · Draft (amber, also a published form with unpublished changes) · Archived (grey).
(String, Tone) formStatus(Map f) {
  if (f['status'] == 'archived') return ('Archived', Tone.neutral);
  if (f['status'] == 'draft' || f['has_draft'] == true) return ('Draft', Tone.warn);
  return ('Published', Tone.ok);
}

/// One question in the builder (API shape `QuestionSerializer`). [key] stays the same while it moves.
class FmQ {
  FmQ(Map j)
      : id = (j['id'] as num?)?.toInt(),
        text = '${j['text'] ?? ''}',
        type = '${j['type'] ?? 'short'}',
        options = [for (final o in (j['options'] as List?) ?? const []) '$o'],
        scaleLabels = [for (final o in (j['scale_labels'] as List?) ?? const []) '$o'],
        other = j['allow_other'] == true,
        help = '${j['help_text'] ?? ''}',
        required = j['required'] == true,
        metric = '${j['metric'] ?? ''}',
        profileKey = '${j['profile_key'] ?? ''}',
        key = UniqueKey();
  FmQ.blank(this.type)
      : id = null,
        text = '',
        options = [],
        scaleLabels = [],
        other = false,
        help = '',
        required = true,
        metric = '',
        profileKey = '',
        key = UniqueKey();

  int? id;
  String text, type, help, metric, profileKey;
  List<String> options, scaleLabels;
  bool other, required;
  final Key key;

  /// Fills a client profile field (the onboarding questionnaire): its answer type and options stay as they are.
  bool get keyed => profileKey.isNotEmpty;
  bool get choice => choiceTypes.contains(type);

  FmQ copy({bool asNew = false}) => FmQ({...toJson(), if (asNew) 'id': null, if (asNew) 'profile_key': ''});

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'type': type,
        'options': options,
        'scale_labels': scaleLabels,
        'allow_other': other,
        'help_text': help,
        'required': required,
        'metric': metric,
        'profile_key': profileKey,
      };

  /// "4 options + Other" on a choice question.
  String get optionsLine => choice ? '${options.length} options${other ? ' + Other' : ''}' : '';
}

/// `.hb-ic.sm` tile of a form kind.
class KindTile extends StatelessWidget {
  const KindTile(this.kind, {super.key, this.size = 30});
  final String kind;
  final double size;
  @override
  Widget build(BuildContext context) {
    final t = kindTone(kind);
    return IconTile(kindIcon(kind), size: size, bg: t.$1, fg: t.$2, radius: 8, iconSize: 16);
  }
}

/// `.fm-qi`: grey tile (28) or bare small icon of an answer type.
class QTypeIcon extends StatelessWidget {
  const QTypeIcon(this.type, {super.key, this.small = false, this.color});
  final String type;
  final bool small;
  final Color? color;
  @override
  Widget build(BuildContext context) => small
      ? AppIcon(qTypeIcon(type), size: 13, color: color ?? AppColors.muted)
      : IconTile(qTypeIcon(type), size: 28, bg: AppColors.sub, fg: color ?? AppColors.text2, radius: 7, iconSize: 15);
}

/// `.pk-chk`: round (one choice) or square (many) tick.
class FmCheck extends StatelessWidget {
  const FmCheck({super.key, required this.on, this.square = false});
  final bool on, square;
  @override
  Widget build(BuildContext context) => Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: on ? AppColors.accent : AppColors.card,
          shape: square ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: square ? AppRadius.all(6) : null,
          border: Border.all(color: on ? AppColors.accent : AppColors.line2, width: 1.5),
        ),
        child: on ? const Center(child: AppIcon(AppIcons.check, size: 12, color: AppColors.white)) : null,
      );
}

/// `.hb-note`: grey note with an icon.
class FmNote extends StatelessWidget {
  const FmNote(this.icon, this.text, {super.key});
  final AppIconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(8)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: AppIcon(icon, size: 16, color: AppColors.muted)),
          Expanded(child: Text(text, style: AppText.s(12, W.w5, color: AppColors.text2, h: 1.45))),
        ]),
      );
}

// ─────────────────────────────── Create form

/// `Create form` modal: kind, name, Template / Blank form. Returns the new form (detail) or null.
Future<Map?> showCreateForm(BuildContext context) {
  var kind = 'weekly';
  var start = 'template';
  var typed = false;
  final name = TextEditingController(text: kindLabel(kind));
  String? error;
  var saving = false;
  return showAppModal<Map>(
    context,
    title: 'Create form',
    body: 'Pick what it is for, then add the questions',
    icon: AppIcons.clipboard,
    width: 540,
    content: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
        drField(
          'What kind of form?',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, k) in formKinds.indexed)
              Hover(
                onTap: () => set(() {
                  kind = k.$1;
                  if (!typed) name.text = k.$2;
                }),
                builder: (_, h, _) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
                  decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
                  child: Row(spacing: 10, children: [
                    FmCheck(on: kind == k.$1),
                    KindTile(k.$1),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                        Text(k.$2, style: AppText.s(13.5, W.w7, color: h ? AppColors.accentText : AppColors.text)),
                        Text(k.$3, style: AppText.s(12, W.w5, color: AppColors.muted, h: 1.4)),
                      ]),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
        drField(
          'Name',
          AppTextField(controller: name, error: error, onChanged: (_) => typed = true),
        ),
        drField(
          'Start from',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
            SegmentedTabs<String>(
              expand: true,
              items: const [TabItem('template', 'Template'), TabItem('blank', 'Blank form')],
              value: start,
              onChanged: (v) => set(() => start = v),
            ),
            Text(start == 'template' ? 'Starts with our standard questions. You can change every one of them.' : 'Starts empty. You add every question yourself.',
                style: AppText.s(12, W.w5, color: AppColors.muted)),
          ]),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: [
          if (!ctx.isPhone) AppButton('Cancel', onPressed: () => Navigator.of(ctx).pop()),
          Expanded(
            flex: ctx.isPhone ? 1 : 0,
            child: AppButton.primary('Continue to builder', trailingIcon: AppIcons.chevronRight, loading: saving, expand: ctx.isPhone, onPressed: () async {
              final n = name.text.trim();
              if (n.length < 2) return set(() => error = 'Enter a form name.');
              set(() {
                saving = true;
                error = null;
              });
              try {
                final r = await Services.api.post<Map>('forms/', {'name': n, 'type': kind, 'start': start});
                if (ctx.mounted) Navigator.of(ctx).pop(r);
              } on ApiError catch (e) {
                set(() {
                  saving = false;
                  error = e.fields['name']?.first ?? e.message;
                });
              }
            }),
          ),
        ]),
      ]),
    ),
  );
}

// ─────────────────────────────── Preview

/// `Preview` drawer: the form as the client sees it, and it can be filled in. Nothing is saved.
Future<void> showFormPreview(BuildContext context, {required String name, required List<FmQ> questions}) => showAppDrawer(
      context,
      title: name,
      sub: 'Client preview · ${questionsLabel(questions.length)}',
      icon: AppIcons.eye,
      builder: (_) => _Preview(questions),
      footer: (ctx) => [AppButton.primary('Close', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop())],
    );

class _Preview extends StatefulWidget {
  const _Preview(this.qs);
  final List<FmQ> qs;
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  final picked = <int, List<String>>{};

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
          for (final (i, q) in widget.qs.indexed) _q(i, q),
          if (widget.qs.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.tableHead, borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.line)),
              child: Text('This form has no questions yet.', style: AppText.s(13, W.w5, color: AppColors.muted)),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(8)),
            child: Row(spacing: 8, children: [
              const AppIcon(AppIcons.eye, size: 16, color: AppColors.muted),
              Expanded(child: Text('This is a preview. Answers typed here are not saved.', style: AppText.s(12.5, W.w6, color: AppColors.muted))),
            ]),
          ),
        ]),
      );

  Widget _q(int i, FmQ q) {
    final got = picked[i] ?? const <String>[];
    void pick(String o) => setState(() {
          picked[i] = q.type == 'multiple' ? (got.contains(o) ? [...got.where((x) => x != o)] : [...got, o]) : [o];
        });
    Widget box(String label, bool on, VoidCallback tap) => Expanded(
          child: Hover(
            onTap: tap,
            builder: (_, h, _) => Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.accentSoft : null,
                borderRadius: AppRadius.all(8),
                border: Border.all(color: on ? AppColors.accent : (h ? AppColors.lineHover : AppColors.line2)),
              ),
              child: Text(label, style: AppText.s(13, W.w7, color: on ? AppColors.accentText : AppColors.text2)),
            ),
          ),
        );
    final answer = switch (q.type) {
      'short' || 'number' => AppTextField(placeholder: q.type == 'number' ? '0' : 'Your answer', keyboard: q.type == 'number' ? TextInputType.number : null),
      'long' => const AppTextField(placeholder: 'Your answer', maxLines: 4, minLines: 3),
      'scale' => Row(spacing: 6, children: [for (var n = 1; n <= 5; n++) box('$n', got.contains('$n'), () => pick('$n'))]),
      'yes_no' => Row(spacing: 6, children: [box('Yes', got.contains('Yes'), () => pick('Yes')), box('No', got.contains('No'), () => pick('No'))]),
      'single' || 'multiple' => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          for (final o in [...q.options, if (q.other) 'Other'])
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => pick(o),
              child: Row(spacing: 10, children: [
                FmCheck(on: got.contains(o), square: q.type == 'multiple'),
                Expanded(child: Text(o, style: AppText.s(13.5, W.w5))),
              ]),
            ),
        ]),
      'dropdown' => AppSelect(got.isEmpty ? 'Choose one' : got.first, entries: [
          for (final o in [...q.options, if (q.other) 'Other']) MenuEntry(o, selected: got.contains(o), onTap: () => pick(o)),
        ]),
      _ => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.line2, width: 1.5)),
          child: Column(spacing: 3, children: [
            const AppIcon(AppIcons.camera, size: 20, color: AppColors.muted),
            Text('Add photos', style: AppText.s(13, W.w7, color: AppColors.text2)),
            Text('Camera or gallery · up to 3', style: AppText.s(12, W.w6, color: AppColors.muted)),
          ]),
        ),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(6)),
          child: Text('${i + 1}', style: AppText.s(11.5, W.w8, color: AppColors.text2)),
        ),
        Expanded(child: Text(q.text, style: AppText.s(14, W.w7, h: 1.4))),
        if (q.required) Padding(padding: const EdgeInsets.only(top: 2), child: Text('Required', style: AppText.s(11, W.w7, color: AppColors.muted))),
      ]),
      Padding(
        padding: const EdgeInsets.only(left: 30),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          if (q.help.isNotEmpty) Text(q.help, style: AppText.s(12, W.w5, color: AppColors.muted)),
          answer,
          if (got.contains('Other') && q.type != 'scale') const AppTextField(placeholder: 'Type your answer'),
        ]),
      ),
    ]);
  }
}

// ─────────────────────────────── Question editor

/// "New question / Placed at the end of the form" or "Edit question / Question i of N". Returns the saved
/// question, or null on Cancel.
/// Progress tags a question can carry (`Question.metric`, D-88): its answer also goes to the client's weigh-ins,
/// profile or measurements. Number questions: body numbers; 1–5 scales: how the day felt.
List<(String, String)> questionTags(String type) => switch (type) {
      'number' => const [
          ('weight', 'Weight (kg)'), ('height', 'Height (cm)'), ('body_fat', 'Body fat (%)'), ('muscle_mass', 'Muscle mass (kg)'),
          ('waist', 'Waist (cm)'), ('hips', 'Hips (cm)'), ('chest', 'Chest (cm)'), ('abdomen', 'Abdomen (cm)'), ('neck', 'Neck (cm)'),
          ('bicep_l', 'Left bicep (cm)'), ('bicep_r', 'Right bicep (cm)'), ('thigh_l', 'Left thigh (cm)'), ('thigh_r', 'Right thigh (cm)'),
          ('calf_l', 'Left calf (cm)'), ('calf_r', 'Right calf (cm)'), ('sleep_hours', 'Sleep (hours)'),
        ],
      'scale' => const [('energy', 'Energy'), ('mood', 'Mood'), ('hunger', 'Hunger'), ('soreness', 'Soreness'), ('sleep_hours', 'Sleep')],
      _ => const [],
    };

String tagLabel(String metric) => metric.isEmpty
    ? 'None'
    : [...questionTags('number'), ...questionTags('scale')].firstWhere((x) => x.$1 == metric, orElse: () => (metric, metric)).$2;

/// [used]: tags other questions of this form already carry (a tag is used once a form).
Future<FmQ?> showQuestionEditor(BuildContext context,
    {required FmQ q, required bool isNew, int index = 0, int total = 0, String profileLabel = '', Set<String> used = const {}}) {
  final w = q.copy();
  final text = TextEditingController(text: w.text);
  final opts = TextEditingController(text: w.options.join('\n'));
  final help = TextEditingController(text: w.help);
  String? textErr, optErr;
  return showAppModal<FmQ>(
    context,
    title: isNew ? 'New question' : 'Edit question',
    body: isNew ? 'Placed at the end of the form' : 'Question ${index + 1} of $total',
    icon: AppIcons.clipboard,
    width: 560,
    content: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        void save() {
          final t = text.text.trim();
          final list = [for (final l in opts.text.split('\n')) if (l.trim().isNotEmpty) l.trim()];
          textErr = t.isEmpty ? 'Enter the question.' : null;
          optErr = w.choice && !w.keyed && list.length + (w.other ? 1 : 0) < 2 ? 'Add at least two options.' : null;
          if (textErr != null || optErr != null) return set(() {});
          w
            ..text = t
            ..help = help.text.trim();
          if (!questionTags(w.type).any((x) => x.$1 == w.metric)) w.metric = '';
          // A new number question about weight / height gets its tag on its own (it can be set back to None).
          if (isNew && w.metric.isEmpty && w.type == 'number') {
            final l = t.toLowerCase();
            if (l.contains('weight') && !used.contains('weight')) w.metric = 'weight';
            if (l.contains('height') && !used.contains('height')) w.metric = 'height';
          }
          if (!w.keyed) w.options = w.choice ? list : (w.type == 'photo' ? w.options : []);
          if (!w.choice) w.other = false;
          Navigator.of(ctx).pop(w);
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
          _req('Question', AppTextField(controller: text, placeholder: 'Enter the question', error: textErr, autofocus: isNew)),
          drField(
            'Answer type',
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (k, l) in qTypes)
                if (!w.keyed || k == w.type)
                  _TypeChip(k, l, on: w.type == k, onTap: w.keyed ? null : () => set(() => w.type = k)),
            ]),
          ),
          if (w.keyed)
            FmNote(AppIcons.info, 'This question fills ${profileLabel.isEmpty ? 'a field' : '"$profileLabel"'} in the client profile, so its answer type and options stay as they are. You can change its words, help text and Required.'),
          if (w.choice && !w.keyed) ...[
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
              Text('Options, one per line', style: AppText.label),
              AppTextField(controller: opts, maxLines: 8, minLines: 4, error: optErr),
              if (optErr == null) Text('Add at least two options.', style: AppText.s(12, W.w5, color: AppColors.muted)),
            ]),
            DrSwitch(title: 'Add an "Other" option', sub: 'The client can pick Other and type their own answer', value: w.other, onChanged: (v) => set(() => w.other = v)),
          ],
          if (w.type == 'photo')
            const FmNote(AppIcons.camera, 'The client takes up to 3 photos or picks them from the gallery. They show in the client profile under Progress.'),
          if (w.type == 'scale') const FmNote(AppIcons.doc, 'Clients rate from 1 to 5. Use the help text to say what 1 and 5 mean.'),
          if (questionTags(w.type).isNotEmpty)
            drField(
              'Progress tag (optional)',
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
                AppSelect(tagLabel(w.metric), entries: [
                  for (final (k, l) in [('', 'None'), ...questionTags(w.type)])
                    if (k.isEmpty || !used.contains(k)) MenuEntry(l, selected: w.metric == k, onTap: () => set(() => w.metric = k)),
                ]),
                Text('The answer is saved there too: Weight → weigh-ins, Height → profile, Body fat, Muscle mass and body sizes → measurements. Progress and Home read it from there.',
                    style: AppText.s(12, W.w5, color: AppColors.muted)),
              ]),
            ),
          drField('Help text (optional)', AppTextField(controller: help, placeholder: 'e.g. Empty stomach, same scale')),
          DrSwitch(title: 'Required', sub: 'The client must answer it', value: w.required, onChanged: (v) => set(() => w.required = v)),
          Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: [
            Expanded(flex: ctx.isPhone ? 1 : 0, child: AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop())),
            Expanded(flex: ctx.isPhone ? 1 : 0, child: AppButton.primary(isNew ? 'Add question' : 'Save question', icon: AppIcons.check, expand: ctx.isPhone, onPressed: save)),
          ]),
        ]);
      },
    ),
  );
}

Widget _req(String label, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      Text.rich(TextSpan(text: label, style: AppText.label, children: [TextSpan(text: '*', style: AppText.label.copyWith(color: AppColors.badText))])),
      child,
    ]);

/// `.fm-tp`: one answer type chip (blue when picked).
class _TypeChip extends StatelessWidget {
  const _TypeChip(this.type, this.label, {required this.on, this.onTap});
  final String type, label;
  final bool on;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          height: 32,
          padding: const EdgeInsets.fromLTRB(6, 0, 10, 0),
          decoration: BoxDecoration(
            color: on ? AppColors.accentSoft : null,
            borderRadius: AppRadius.all(8),
            border: Border.all(color: on ? AppColors.accent : (h && onTap != null ? AppColors.hbIcoHover : AppColors.line2)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
            SizedBox(width: 22, child: Center(child: AppIcon(qTypeIcon(type), size: 14, color: on ? AppColors.accentText : AppColors.text2))),
            Text(label, style: AppText.s(12.5, W.w6, color: on ? AppColors.accentText : AppColors.text2)),
          ]),
        ),
      );
}

/// The status badge (`.badge.plain`).
Widget formBadge(Map f) {
  final (l, t) = formStatus(f);
  return AppBadge(l, tone: t, plain: true);
}

/// Shorthand for the tooltip-wrapped text of a cut line.
Widget fmCut(String s, TextStyle style) => CutText(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
