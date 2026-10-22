import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/util/input_rules.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import 'clients_model.dart';

const clientGenders = [('female', 'Female'), ('male', 'Male'), ('other', 'Other'), ('', 'Prefer not to say')];
const clientGoals = [('fat_loss', 'Lose fat'), ('muscle_gain', 'Muscle gain'), ('strength', 'Strength'), ('recomp', 'Recomp'), ('general', 'General fitness'), ('event', 'Event prep')];

/// Onboarding answers the drawer edits besides the board's fields (D-36): free text, and choices whose options
/// come from the server (`options` of `clients/<id>/`). Choices with "Other" keep the client's own words.
const _texts = [
  'goal_detail', 'current_exercise', 'past_injuries', 'surgeries', 'addictions', 'digestive_issues', 'stresses', 'common_foods',
  'meal_breakfast', 'meal_mid_morning', 'meal_lunch', 'meal_pre_workout', 'meal_post_workout', 'meal_evening', 'meal_dinner',
  'supplements_detail', 'supplement_brands', 'medicines_detail',
];
const _others = {'enrolled_for': 'Other', 'workout_place': 'Other', 'workout_time': 'Other', 'diet_type': 'Other', 'food_allergies': 'Yes', 'smoking': 'Yes', 'open_to_supplements': 'Other'};
const _choices = ['experience', 'activity_level'];
const _multis = ['injury_areas', 'conditions'];
const _bools = ['doctor_ok', 'takes_supplements', 'takes_medicines'];

class _EditState extends ChangeNotifier {
  bool loaded = false, busy = false;
  String gender = '', goal = '';
  DateTime? dob, target;
  Map<String, String> errors = {};

  /// Choice, yes / no, list and days answers by field key; option lists by field key.
  Map<String, dynamic> vals = {};
  Map<String, List<(String, String)>> options = {};

  /// Choices where "Other" (or "Yes" for allergies / smoking) is picked: the text box holds their words.
  final Set<String> otherOpen = {};
  void set(VoidCallback f) {
    f();
    notifyListeners();
  }

  String label(String key, Object? v) => (options[key] ?? const []).where((o) => o.$1 == '$v').firstOrNull?.$2 ?? '$v';
  bool isOption(String key, Object? v) => (options[key] ?? const []).any((o) => o.$1 == '$v');
}

/// "Edit details" (row ⋯ menu): the board's client drawer sections — Must have, Good to have, Goal and body —
/// filled from `GET clients/<id>/`, saved with `PATCH clients/<id>/`. Returns true when saved.
Future<bool?> showEditClientDrawer(BuildContext context, MyClientsController c, McRow r) =>
    showClientDetailsDrawer(context, id: r.id, clientName: r.name, load: () => c.detail(r.id), onSave: (data) => c.save(r.id, data));

/// The same drawer for any screen (Client profile → Edit profile): [load] gives `clients/<id>/`, [save] PATCHes.
Future<bool?> showClientDetailsDrawer(BuildContext context,
    {required String id,
    required String clientName,
    required Future<Map> Function() load,
    required Future<void> Function(Map<String, dynamic>) onSave,
    String title = 'Edit details',
    bool admin = false,
    Future<void> Function()? onChangeTrainer}) {
  final first = clientName.split(' ').first;
  final s = _EditState();
  final name = TextEditingController(), phone = TextEditingController(), email = TextEditingController();
  final city = TextEditingController(), goalW = TextEditingController();
  // Admin only (board ClientProfile → Sign-in): a new password; empty keeps the old one.
  final password = TextEditingController();
  final trainer = ValueNotifier<Map?>(null);
  final height = TextEditingController(), weight = TextEditingController(), notes = TextEditingController();
  final texts = {for (final k in [..._texts, ..._others.keys]) k: TextEditingController()};
  final detail = load().then((d) {
    String num(Object? v) => v == null ? '' : '${double.tryParse('$v')?.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '') ?? v}';
    final p = (d['profile'] as Map?) ?? const {};
    trainer.value = d['trainer'] as Map?;
    name.text = '${d['full_name'] ?? ''}';
    final ph = '${d['phone'] ?? ''}';
    phone.text = ph.startsWith('+91') ? ph.substring(3).trim() : ph;
    email.text = '${d['email'] ?? ''}';
    final b = '${d['date_of_birth'] ?? ''}';
    city.text = '${d['city'] ?? ''}';
    goalW.text = num(p['target_weight_kg']);
    height.text = num(p['height_cm']);
    weight.text = num(p['current_weight_kg']);
    notes.text = '${p['health_notes'] ?? ''}';
    for (final k in _texts) {
      texts[k]!.text = '${p[k] ?? ''}';
    }
    s.set(() {
      s.gender = '${d['gender'] ?? ''}';
      s.goal = '${p['goal'] ?? ''}';
      s.dob = DateTime.tryParse(b);
      s.target = DateTime.tryParse('${p['target_date'] ?? ''}');
      s.options = {
        for (final e in ((d['options'] as Map?) ?? const {}).entries)
          '${e.key}': [for (final o in (e.value as List)) ('${o['value']}', '${o['label']}')],
      };
      for (final k in [..._choices, ..._bools, ..._others.keys, 'workout_days']) {
        s.vals[k] = p[k];
      }
      for (final k in _multis) {
        s.vals[k] = [for (final x in (p[k] as List?) ?? const []) '$x'];
      }
      for (final k in _others.keys) {
        final v = '${p[k] ?? ''}';
        if (v.isNotEmpty && !s.isOption(k, v)) {
          s.otherOpen.add(k);
          texts[k]!.text = v;
        }
      }
      s.loaded = true;
    });
    return d;
  });

  Future<void> save(BuildContext ctx) async {
    final errs = <String, String>{};
    if (name.text.trim().isEmpty) errs['full_name'] = 'Enter the full name.';
    final digits = phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (!isMobile(digits)) errs['phone'] = 'Enter a 10-digit mobile number.';
    if (email.text.trim().isNotEmpty && !isEmail(email.text)) errs['email'] = 'Enter a valid email.';
    num? n(TextEditingController t) => t.text.trim().isEmpty ? null : num.tryParse(t.text.trim());
    void range(String key, TextEditingController t, num lo, num hi, String msg) {
      final v = n(t);
      if (t.text.trim().isNotEmpty && (v == null || v < lo || v > hi)) errs[key] = msg;
    }
    range('target_weight_kg', goalW, 25, 300, 'Enter a weight between 25 and 300 kg.');
    range('current_weight_kg', weight, 25, 300, 'Enter a weight between 25 and 300 kg.');
    range('height_cm', height, 100, 250, 'Enter a height between 100 and 250 cm.');
    if (admin && password.text.isNotEmpty && password.text.length < 8) errs['password'] = 'Use at least 8 characters.';
    s.set(() => s.errors = errs);
    if (errs.isNotEmpty) return;
    s.set(() => s.busy = true);
    try {
      await onSave({
        'full_name': name.text.trim(),
        'phone': '+91$digits',
        'email': email.text.trim(),
        'gender': s.gender,
        'date_of_birth': s.dob == null ? null : DateFormat('yyyy-MM-dd').format(s.dob!),
        'city': city.text.trim(),
        'goal': s.goal,
        'target_weight_kg': n(goalW),
        'target_date': s.target == null ? null : DateFormat('yyyy-MM-dd').format(s.target!),
        'height_cm': n(height),
        'current_weight_kg': n(weight),
        'health_notes': notes.text.trim(),
        for (final k in _texts) k: texts[k]!.text.trim(),
        for (final k in _others.keys) k: s.otherOpen.contains(k) ? texts[k]!.text.trim() : '${s.vals[k] ?? ''}',
        for (final k in _choices) k: '${s.vals[k] ?? ''}',
        for (final k in _multis) k: s.vals[k] ?? <String>[],
        for (final k in _bools) k: s.vals[k],
        'workout_days': s.vals['workout_days'],
        if (admin && password.text.isNotEmpty) 'password': password.text,
      });
      if (ctx.mounted) Navigator.of(ctx).pop(true);
    } on ApiError catch (e) {
      s.set(() {
        s.busy = false;
        s.errors = {for (final f in e.fields.entries) f.key: f.value.join(' ')};
      });
      if (ctx.mounted && e.fields.isEmpty) showToast(ctx, e.message);
    }
  }

  Widget sec(String title, String sub, List<Widget> children, {bool last = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(title, style: AppText.s(13.5, W.w8)),
            Text(sub, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
          ]),
          ...children,
        ]),
      );

  Widget two(BuildContext ctx, Widget a, Widget b) => ctx.isPhone
      ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [a, b])
      : Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [Expanded(child: a), Expanded(child: b)]);

  Widget field(String label, Widget child, {bool req = false, String? error}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        Text.rich(TextSpan(text: label, children: [if (req) TextSpan(text: '*', style: AppText.s(13, W.w7, color: AppColors.badText))]), style: AppText.label),
        child,
        if (error != null) Text(error, style: AppText.s(12, W.w6, color: AppColors.badText)),
      ]);

  String? err(String k) => s.errors[k];

  // Onboarding answers (D-36): selects for choices (options from the server), a text box for "Other" words,
  // chips for lists, multi-line boxes for what they wrote.
  Widget choice(String k) {
    final v = '${s.vals[k] ?? ''}';
    return AppSelect(v.isEmpty ? 'Not set' : s.label(k, v), entries: [
      for (final (o, l) in s.options[k] ?? const <(String, String)>[]) MenuEntry(l, selected: o == v, onTap: () => s.set(() => s.vals[k] = o)),
    ]);
  }

  Widget other(String k) {
    final v = '${s.vals[k] ?? ''}', open = s.otherOpen.contains(k), word = _others[k]!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      AppSelect(open ? word : (v.isEmpty ? 'Not set' : s.label(k, v)), entries: [
        for (final (o, l) in s.options[k] ?? const <(String, String)>[])
          MenuEntry(l, selected: !open && o == v, onTap: () => s.set(() {
                s.otherOpen.remove(k);
                s.vals[k] = o;
              })),
        MenuEntry(word == 'Yes' ? 'Yes…' : 'Other…', selected: open, onTap: () => s.set(() => s.otherOpen.add(k))),
      ]),
      if (open)
        AppTextField(controller: texts[k], placeholder: switch (k) { 'smoking' => 'How many a day?', 'food_allergies' => 'Which foods?', _ => 'In their words' }),
      if (err(k) != null) Text(err(k)!, style: AppText.s(12, W.w6, color: AppColors.badText)),
    ]);
  }

  Widget multi(String k) {
    final picked = [for (final x in (s.vals[k] as List?) ?? const []) '$x'];
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final (o, l) in s.options[k] ?? const <(String, String)>[])
        FilterChipX(l, selected: picked.contains(o), onTap: () => s.set(() {
              s.vals[k] = o == 'none'
                  ? (picked.contains('none') ? <String>[] : ['none'])
                  : (picked.contains(o) ? (List.of(picked)..remove(o)) : [...picked.where((x) => x != 'none'), o]);
            })),
    ]);
  }

  Widget yesNo(String k) {
    final v = s.vals[k];
    return AppSelect(v == true ? 'Yes' : (v == false ? 'No' : 'Not set'), entries: [
      MenuEntry('Yes', selected: v == true, onTap: () => s.set(() => s.vals[k] = true)),
      MenuEntry('No', selected: v == false, onTap: () => s.set(() => s.vals[k] = false)),
      MenuEntry('Not set', selected: v == null, onTap: () => s.set(() => s.vals[k] = null)),
    ]);
  }

  Widget text(String k, String label, {int lines = 3, String? hint}) =>
      field(label, AppTextField(controller: texts[k], maxLines: lines, placeholder: hint), error: err(k));

  return showAppDrawer<bool>(
    context,
    title: title,
    sub: '$clientName · changes show in their app straight away',
    icon: AppIcons.edit,
    builder: (ctx) => FutureBuilder<Map>(
      future: detail,
      builder: (ctx, snap) {
        if (snap.hasError) {
          return EmptyState('Could not open $first’s details', sub: snap.error is ApiError ? (snap.error as ApiError).message : null);
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))),
          );
        }
        return ListenableBuilder(
          listenable: s,
          builder: (ctx, _) {
            final e = s.errors;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              sec('Must have', 'They log in with this mobile number. We check it is not already used.', [
                two(
                  ctx,
                  field('Full name', AppTextField(controller: name, placeholder: 'Full name'), req: true, error: e['full_name']),
                  field('Mobile', AppTextField(controller: phone, keyboard: TextInputType.phone, prefix: Text('+91', style: AppText.s(14, W.w6, color: AppColors.muted))),
                      req: true, error: e['phone']),
                ),
              ]),
              sec('Good to have', 'They can fill or change these in the app too.', [
                two(
                  ctx,
                  field('Email', AppTextField(controller: email, keyboard: TextInputType.emailAddress, placeholder: 'For login links and receipts'), error: e['email']),
                  field('Gender', AppSelect(clientGenders.firstWhere((g) => g.$1 == s.gender, orElse: () => clientGenders.last).$2,
                      entries: [for (final (v, l) in clientGenders) MenuEntry(l, selected: v == s.gender, onTap: () => s.set(() => s.gender = v))])),
                ),
                two(
                  ctx,
                  field('Date of birth', ClientDateBox(s.dob, onPick: (v) => s.set(() => s.dob = v)), error: e['date_of_birth']),
                  field('City', AppTextField(controller: city, placeholder: 'City'), error: e['city']),
                ),
              ]),
              if (admin) ...[
                sec('Sign-in', 'They get a notice when their password changes.', [
                  two(
                    ctx,
                    field('New password', AppTextField(controller: password, obscure: true, placeholder: 'Leave empty to keep it'), error: e['password']),
                    const SizedBox.shrink(),
                  ),
                  Text('At least 8 characters.', style: AppText.s(12, W.w5, color: AppColors.muted)),
                  Row(spacing: 6, children: [
                    const AppIcon(AppIcons.info, size: 15, color: AppColors.muted),
                    Flexible(child: Text('Or let $first pick their own:', style: AppText.s(13, W.w5, color: AppColors.text2))),
                    AppButton('Send a reset link', kind: BtnKind.text, size: BtnSize.sm, onPressed: () async {
                      try {
                        final r = await Services.api.post<Map>('clients/$id/send-reset/');
                        if (ctx.mounted) showToast(ctx, 'Reset link sent', sub: '${r['sent_to']}', kind: ToastKind.ok);
                      } on ApiError catch (er) {
                        if (ctx.mounted) showToast(ctx, 'Could not send the link', sub: er.message, kind: ToastKind.info);
                      }
                    }),
                  ]),
                ]),
                sec('Trainer', 'Who coaches them now.', [
                  ValueListenableBuilder<Map?>(
                    valueListenable: trainer,
                    builder: (_, t, _) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: AppRadius.all(AppRadius.input)),
                      child: Row(spacing: 10, children: [
                        if (t != null) AppAvatar('${t['full_name']}', size: 24, initials: '${t['initials'] ?? ''}', colors: AppColors.avatarCode('${t['avatar_color'] ?? 'c1'}')),
                        Expanded(
                          child: Text.rich(TextSpan(children: [
                            const TextSpan(text: 'Trainer '),
                            TextSpan(text: t == null ? 'none yet' : '${t['full_name']}', style: AppText.s(13.5, W.w7)),
                          ]), style: AppText.s(13.5, W.w5)),
                        ),
                        if (onChangeTrainer != null)
                          AppButton('Change trainer', kind: BtnKind.text, size: BtnSize.sm, onPressed: () async {
                            await onChangeTrainer();
                            try {
                              trainer.value = (await load())['trainer'] as Map?;
                            } catch (_) {}
                          }),
                      ]),
                    ),
                  ),
                ]),
              ],
              sec('Goal and body', 'Optional. If you leave these empty they fill them in onboarding.', [
                two(
                  ctx,
                  field('Goal', AppSelect(s.goal.isEmpty ? 'Pick a goal' : clientGoals.firstWhere((g) => g.$1 == s.goal, orElse: () => (s.goal, s.goal)).$2,
                      entries: [for (final (v, l) in clientGoals) MenuEntry(l, selected: v == s.goal, onTap: () => s.set(() => s.goal = v))])),
                  field('Goal weight', AppTextField(controller: goalW, keyboard: const TextInputType.numberWithOptions(decimal: true), suffix: _unit('kg')),
                      error: e['target_weight_kg']),
                ),
                two(
                  ctx,
                  field('Target date', ClientDateBox(s.target, future: true, onPick: (v) => s.set(() => s.target = v)), error: e['target_date']),
                  field('Enrolled for', other('enrolled_for')),
                ),
                two(
                  ctx,
                  field('Height', AppTextField(controller: height, keyboard: const TextInputType.numberWithOptions(decimal: true), suffix: _unit('cm')), error: e['height_cm']),
                  field('Current weight', AppTextField(controller: weight, keyboard: const TextInputType.numberWithOptions(decimal: true), suffix: _unit('kg')),
                      error: e['current_weight_kg']),
                ),
                field('Training experience', choice('experience')),
                text('goal_detail', 'Anything specific about the goal', lines: 1, hint: 'A wedding in March, lose belly fat…'),
              ]),
              sec('Training', 'From the coaching form. Change them when their routine changes.', [
                two(
                  ctx,
                  field('Days a week', AppSelect(s.vals['workout_days'] == null ? 'Not set' : '${s.vals['workout_days']} days a week', entries: [
                    for (var n = 1; n <= 7; n++) MenuEntry(n == 1 ? '1 day a week' : '$n days a week', selected: s.vals['workout_days'] == n, onTap: () => s.set(() => s.vals['workout_days'] = n)),
                  ]), error: e['workout_days']),
                  field('Where they train', other('workout_place')),
                ),
                two(ctx, field('Workout time', other('workout_time')), field('Activity level', choice('activity_level'))),
                text('current_exercise', 'Exercise they do now', hint: 'Not performing, walks, gym 3 days…'),
              ]),
              sec('Health', 'Only you and their coach see these.', [
                field('Injuries or pain now', multi('injury_areas'), error: e['injury_areas']),
                field('Injuries or health notes', AppTextField(controller: notes, maxLines: 3, placeholder: 'Back pain, thyroid, recent surgery…'), error: e['health_notes']),
                field('Health conditions', multi('conditions'), error: e['conditions']),
                two(ctx, field('Doctor cleared them for exercise', yesNo('doctor_ok')), const SizedBox.shrink()),
                text('past_injuries', 'Past injuries'),
                two(ctx, text('surgeries', 'Surgeries', lines: 2), text('addictions', 'Addictions', lines: 2)),
                two(ctx, text('digestive_issues', 'Digestive issues', lines: 2), text('stresses', '3 biggest stresses', lines: 2)),
              ]),
              sec('Food and lifestyle', 'What they eat now, from the coaching form.', [
                two(ctx, field('Diet', other('diet_type')), field('Food allergies', other('food_allergies'))),
                two(ctx, field('Smoking', other('smoking')), const SizedBox.shrink()),
                text('common_foods', 'Foods they eat most'),
                two(ctx, text('meal_breakfast', 'Breakfast', lines: 2), text('meal_mid_morning', 'Between breakfast and lunch', lines: 2)),
                two(ctx, text('meal_lunch', 'Lunch', lines: 2), text('meal_evening', 'Between lunch and dinner', lines: 2)),
                two(ctx, text('meal_pre_workout', 'Pre-workout', lines: 2), text('meal_post_workout', 'Post-workout', lines: 2)),
                text('meal_dinner', 'Dinner', lines: 2),
              ]),
              sec('Supplements and medicines', 'What they take now and how long.', last: true, [
                two(ctx, field('Takes supplements', yesNo('takes_supplements')), field('Open to supplements', other('open_to_supplements'))),
                text('supplements_detail', 'What, how often and why', lines: 2),
                text('supplement_brands', 'Brands', lines: 1),
                two(ctx, field('Uses medicines', yesNo('takes_medicines')), const SizedBox.shrink()),
                text('medicines_detail', 'Medicines and how long', lines: 2),
              ]),
            ]);
          },
        );
      },
    ),
    footer: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      ListenableBuilder(
        listenable: s,
        builder: (_, _) => AppButton.primary('Save changes', icon: AppIcons.check, expand: ctx.isPhone, loading: s.busy, onPressed: s.loaded && !s.busy ? () => save(ctx) : null),
      ),
    ],
  ).whenComplete(() => disposeLater([s, name, phone, email, city, goalW, height, weight, notes, password, trainer, ...texts.values]));
}

int _age(DateTime d) {
  final n = DateTime.now();
  return n.year - d.year - ((n.month < d.month || (n.month == d.month && n.day < d.day)) ? 1 : 0);
}

Widget _unit(String u) => Text(u, style: AppText.s(13, W.w6, color: AppColors.muted));

/// Date of birth: a box like the other inputs that opens the date picker (no typing).
class ClientDateBox extends StatelessWidget {
  const ClientDateBox(this.value, {super.key, required this.onPick, this.future = false});
  final DateTime? value;
  final ValueChanged<DateTime> onPick;

  /// Target date: today to 5 years ahead, shown as "Feb 2027" (date of birth: past, with the age).
  final bool future;

  @override
  Widget build(BuildContext context) => Hover(
        onTap: () async {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final v = future
              ? await showDatePicker(
                  context: context,
                  initialDate: value != null && !value!.isBefore(today) ? value! : DateTime(now.year, now.month + 3, now.day),
                  firstDate: today,
                  lastDate: DateTime(now.year + 5, now.month, now.day),
                )
              : await showDatePicker(
                  context: context,
                  initialDate: value ?? DateTime(now.year - 25),
                  firstDate: DateTime(now.year - 100),
                  lastDate: DateTime(now.year - 10, now.month, now.day),
                );
          if (v != null) onPick(v);
        },
        builder: (_, h, _) => Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.all(AppRadius.input), border: Border.all(color: h ? AppColors.lineHover : AppColors.line2)),
          child: Row(spacing: 8, children: [
            Expanded(
              child: Text(
                  value == null
                      ? 'Pick a date'
                      : future
                          ? DateFormat('d MMM yyyy').format(value!)
                          : '${DateFormat('d MMM yyyy').format(value!)} · ${_age(value!)} years',
                  style: AppText.s(14, value == null ? W.w5 : W.w6, color: value == null ? AppColors.muted : AppColors.text)),
            ),
            const AppIcon(AppIcons.calendar, size: 16, color: AppColors.muted),
          ]),
        ),
      );
}
