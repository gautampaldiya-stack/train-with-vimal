import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/util/input_rules.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import 'clients_model.dart';

const _genders = [('female', 'Female'), ('male', 'Male'), ('other', 'Other'), ('', 'Prefer not to say')];
const _goals = [('fat_loss', 'Lose fat'), ('muscle_gain', 'Muscle gain'), ('strength', 'Strength'), ('recomp', 'Recomp'), ('general', 'General fitness'), ('event', 'Event prep')];

class _EditState extends ChangeNotifier {
  bool loaded = false, busy = false;
  String gender = '', goal = '';
  DateTime? dob;
  Map<String, String> errors = {};
  void set(VoidCallback f) {
    f();
    notifyListeners();
  }
}

/// "Edit details" (row ⋯ menu): the board's client drawer sections — Must have, Good to have, Goal and body —
/// filled from `GET clients/<id>/`, saved with `PATCH clients/<id>/`. Returns true when saved.
Future<bool?> showEditClientDrawer(BuildContext context, MyClientsController c, McRow r) {
  final first = r.name.split(' ').first;
  final s = _EditState();
  final name = TextEditingController(), phone = TextEditingController(), email = TextEditingController();
  final city = TextEditingController(), goalW = TextEditingController();
  final height = TextEditingController(), weight = TextEditingController(), notes = TextEditingController();
  final detail = c.detail(r.id).then((d) {
    String num(Object? v) => v == null ? '' : '${double.tryParse('$v')?.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '') ?? v}';
    final p = (d['profile'] as Map?) ?? const {};
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
    s.set(() {
      s.gender = '${d['gender'] ?? ''}';
      s.goal = '${p['goal'] ?? ''}';
      s.dob = DateTime.tryParse(b);
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
    s.set(() => s.errors = errs);
    if (errs.isNotEmpty) return;
    s.set(() => s.busy = true);
    try {
      await c.save(r.id, {
        'full_name': name.text.trim(),
        'phone': '+91$digits',
        'email': email.text.trim(),
        'gender': s.gender,
        'date_of_birth': s.dob == null ? null : DateFormat('yyyy-MM-dd').format(s.dob!),
        'city': city.text.trim(),
        'goal': s.goal,
        'target_weight_kg': n(goalW),
        'height_cm': n(height),
        'current_weight_kg': n(weight),
        'health_notes': notes.text.trim(),
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

  return showAppDrawer<bool>(
    context,
    title: 'Edit details',
    sub: '${r.name} · changes show in their app straight away',
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
                  field('Gender', AppSelect(_genders.firstWhere((g) => g.$1 == s.gender, orElse: () => _genders.last).$2,
                      entries: [for (final (v, l) in _genders) MenuEntry(l, selected: v == s.gender, onTap: () => s.set(() => s.gender = v))])),
                ),
                two(
                  ctx,
                  field('Date of birth', _DateBox(s.dob, onPick: (v) => s.set(() => s.dob = v)), error: e['date_of_birth']),
                  field('City', AppTextField(controller: city, placeholder: 'City'), error: e['city']),
                ),
              ]),
              sec('Goal and body', 'Optional. If you leave these empty they fill them in onboarding.', last: true, [
                two(
                  ctx,
                  field('Goal', AppSelect(s.goal.isEmpty ? 'Pick a goal' : _goals.firstWhere((g) => g.$1 == s.goal, orElse: () => (s.goal, s.goal)).$2,
                      entries: [for (final (v, l) in _goals) MenuEntry(l, selected: v == s.goal, onTap: () => s.set(() => s.goal = v))])),
                  field('Goal weight', AppTextField(controller: goalW, keyboard: const TextInputType.numberWithOptions(decimal: true), suffix: _unit('kg')),
                      error: e['target_weight_kg']),
                ),
                two(
                  ctx,
                  field('Height', AppTextField(controller: height, keyboard: const TextInputType.numberWithOptions(decimal: true), suffix: _unit('cm')), error: e['height_cm']),
                  field('Current weight', AppTextField(controller: weight, keyboard: const TextInputType.numberWithOptions(decimal: true), suffix: _unit('kg')),
                      error: e['current_weight_kg']),
                ),
                field('Injuries or health notes', AppTextField(controller: notes, maxLines: 3, placeholder: 'Back pain, thyroid, recent surgery…'), error: e['health_notes']),
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
  ).whenComplete(() => disposeLater([s, name, phone, email, city, goalW, height, weight, notes]));
}

Widget _unit(String u) => Text(u, style: AppText.s(13, W.w6, color: AppColors.muted));

/// Date of birth: a box like the other inputs that opens the date picker (no typing).
class _DateBox extends StatelessWidget {
  const _DateBox(this.value, {required this.onPick});
  final DateTime? value;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) => Hover(
        onTap: () async {
          final now = DateTime.now();
          final v = await showDatePicker(
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
              child: Text(value == null ? 'Pick a date' : DateFormat('d MMM yyyy').format(value!),
                  style: AppText.s(14, value == null ? W.w5 : W.w6, color: value == null ? AppColors.muted : AppColors.text)),
            ),
            const AppIcon(AppIcons.calendar, size: 16, color: AppColors.muted),
          ]),
        ),
      );
}
