import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../core/widgets/tabs.dart';
import '../../../core/widgets/tooltip.dart';
import '../../trainer/client_profile/cp_content_drawers.dart' show DrDateBox, DrOpts, DrSec, DrSwitch;
import '../../trainer/clients/clients_parts.dart' show ClientDateBox, clientGenders, clientGoals;

// Admin drawers of the Clients and Approvals boards: Add a client, Change trainer, and the trainer pick row
// (`.dr-opt` with avatar, tags and the load bar) that Approvals → Review uses too.

/// "she" / "he" / "they" from a gender key; the boards write "she".
String pronoun(String gender, {bool cap = false}) {
  final p = switch (gender) { 'female' => 'she', 'male' => 'he', _ => 'they' };
  return cap ? '${p[0].toUpperCase()}${p.substring(1)}' : p;
}

/// "sees" for she / he, "see" for they.
String verb(String gender, String s) {
  if (gender == 'female' || gender == 'male') return s;
  return switch (s) { 'has' => 'have', 'does' => 'do', 'is' => 'are', _ => s.endsWith('s') ? s.substring(0, s.length - 1) : s };
}

String possessive(String gender) => switch (gender) { 'female' => 'her', 'male' => 'his', _ => 'their' };
String objective(String gender) => switch (gender) { 'female' => 'her', 'male' => 'him', _ => 'them' };

/// One trainer in a pick list (`.dr-opt.sm` in `.dr-opts.joined.tr`): radio, avatar, name with Current / Full /
/// Good fit / Invited her tags, speciality, and "24 / 30 clients" with a load bar. Full trainers can't be picked.
class TrainerPickRow extends StatelessWidget {
  const TrainerPickRow({super.key, required this.t, required this.on, required this.onTap, this.tags = const []});
  final Map t;
  final bool on;
  final VoidCallback onTap;

  /// (label, tone) badges after the name.
  final List<(String, Tone)> tags;

  bool get _full => t['full'] == true || t['tag'] == 'full' || ((t['clients'] as num? ?? 0) >= (t['max_clients'] as num? ?? 1));
  bool get _current => t['current'] == true;

  @override
  Widget build(BuildContext context) {
    final n = (t['clients'] as num?) ?? 0, max = (t['max_clients'] as num?) ?? 1;
    final dis = _full || _current;
    final spec = [for (final x in (t['speciality'] as List?) ?? const []) '$x'].join(', ');
    return Opacity(
      opacity: dis ? .55 : 1,
      child: Hover(
        onTap: dis ? null : onTap,
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          color: h && !dis ? AppColors.outlineHover : null,
          child: Row(spacing: 12, children: [
            AppRadio(selected: on, onTap: dis ? null : onTap),
            AppAvatar('${t['full_name']}', size: 30, colors: AppColors.avatarCode('${t['avatar_color'] ?? 'c1'}'), initials: '${t['initials'] ?? ''}'),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('${t['full_name']}', style: AppText.s(13.5, W.w7)),
                  for (final (l, tone) in tags) AppBadge(l, tone: tone, plain: true),
                ]),
                if (spec.isNotEmpty) CutText(spec, maxLines: 1, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
              ]),
            ),
            SizedBox(
              width: 96,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, spacing: 5, children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$n / $max', style: AppText.s(12, W.w7, color: AppColors.text)),
                    const TextSpan(text: ' clients'),
                  ]),
                  maxLines: 1,
                  style: AppText.s(12, W.w6, color: AppColors.muted),
                ),
                ProgressBar(value: max == 0 ? 1 : n / max, width: 72, height: 5, color: AppColors.drLoad),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// `.dr-opts.tr` with a bounded height (about 4 rows) that scrolls inside, as `.ap-trs` (max 228).
class TrainerPickList extends StatefulWidget {
  const TrainerPickList(this.children, {super.key, this.maxHeight = 228});
  final List<Widget> children;
  final double maxHeight;
  @override
  State<TrainerPickList> createState() => _TrainerPickListState();
}

class _TrainerPickListState extends State<TrainerPickList> {
  final _s = ScrollController();
  @override
  void dispose() {
    _s.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: Scrollbar(
          controller: _s,
          thumbVisibility: widget.children.length > 4,
          child: SingleChildScrollView(controller: _s, padding: const EdgeInsets.only(right: 6), child: DrOpts(widget.children)),
        ),
      );
}

Widget _field(String label, Widget child, {bool req = false, String? error, String? hint, Widget? below}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      Text.rich(TextSpan(text: label, children: [if (req) TextSpan(text: '*', style: AppText.s(13, W.w7, color: AppColors.badText))]), style: AppText.label),
      child,
      ?below,
      if (error != null) Text(error, style: AppText.s(12, W.w6, color: AppColors.badText)),
      if (error == null && hint != null) Text(hint, style: AppText.s(12, W.w5, color: AppColors.muted)),
    ]);

Widget _two(BuildContext ctx, Widget a, Widget b) => ctx.isPhone
    ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [a, b])
    : Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [Expanded(child: a), Expanded(child: b)]);

Widget _unit(String u) => Text(u, style: AppText.s(13, W.w6, color: AppColors.muted));

// ─────────────────────────────── Add a client

class _AddState extends ChangeNotifier {
  bool busy = false, sendLink = true, askParq = true;
  String mode = 'active', gender = '', goal = '';
  String? trainer, program, mealPlan;
  DateTime? dob, start;
  Map<String, String> errors = {};

  /// Live mobile check: null while typing, 'ok', 'taken'.
  String? phoneCheck;
  List<Map> trainers = [], programs = [], mealPlans = [];
  void set(VoidCallback f) {
    f();
    notifyListeners();
  }
}

/// "Add a client" (boards Clients / Approvals, `openAdd`): Must have, Good to have, Goal and body, Coaching,
/// Access. Only name and mobile are needed. Returns the new client (`clients/<id>/` shape) when added.
Future<Map?> showAddClientDrawer(BuildContext context) {
  final s = _AddState();
  final name = TextEditingController(), phone = TextEditingController(), email = TextEditingController(), city = TextEditingController();
  final goalW = TextEditingController(), height = TextEditingController(), weight = TextEditingController(), notes = TextEditingController();
  var seq = 0;

  Future<void> loadLists() async {
    try {
      final r = await Future.wait([
        Services.api.get<Map>('trainers/', query: {'page_size': 100}),
        Services.api.get<Map>('programs/', query: {'page_size': 100}),
        Services.api.get<Map>('meal-plans/', query: {'page_size': 100}),
      ]);
      List<Map> rows(Map m) => [for (final x in (m['results'] as List? ?? const [])) x as Map];
      s.set(() {
        s.trainers = [for (final t in rows(r[0])) if ('${t['status']}' == 'active') t];
        s.programs = [for (final p in rows(r[1])) if (p['archived'] != true) p];
        s.mealPlans = [for (final p in rows(r[2])) if ('${p['status']}' == 'published') p];
      });
    } on ApiError {
      // The selects stay on "Pick later"; the client can still be added.
    }
  }

  Future<void> checkPhone() async {
    final digits = phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    final my = ++seq;
    if (!isMobile(digits)) {
      s.set(() => s.phoneCheck = null);
      return;
    }
    try {
      final r = await Services.api.get<Map>('clients/check-phone/', query: {'phone': '+91$digits'});
      if (my != seq) return;
      s.set(() => s.phoneCheck = r['taken'] == null ? 'ok' : 'taken');
    } on ApiError {
      if (my == seq) s.set(() => s.phoneCheck = null);
    }
  }

  Future<void> save(BuildContext ctx) async {
    final errs = <String, String>{};
    if (name.text.trim().length < 2) errs['full_name'] = 'Enter the full name.';
    final digits = phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (!isMobile(digits)) errs['phone'] = 'Enter a 10-digit mobile number.';
    if (s.phoneCheck == 'taken') errs['phone'] = 'A client or sign-up already uses this number.';
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
    String? ymd(DateTime? d) => d == null ? null : DateFormat('yyyy-MM-dd').format(d);
    try {
      final r = await Services.api.post<Map>('clients/', {
        'full_name': name.text.trim(),
        'phone': '+91$digits',
        'email': email.text.trim(),
        'gender': s.gender,
        'date_of_birth': ymd(s.dob),
        'city': city.text.trim(),
        'goal': s.goal,
        'target_weight_kg': n(goalW),
        'height_cm': n(height),
        'current_weight_kg': n(weight),
        'health_notes': notes.text.trim(),
        'trainer': s.trainer,
        'program': s.program,
        'meal_plan': s.mealPlan,
        'start_date': ymd(s.start),
        'send_login_link': s.sendLink,
        'ask_parq': s.askParq,
        'mode': s.mode == 'active' ? 'active' : 'approvals',
      });
      if (ctx.mounted) Navigator.of(ctx).pop(r);
    } on ApiError catch (e) {
      s.set(() {
        s.busy = false;
        s.errors = {for (final f in e.fields.entries) f.key: f.value.join(' ')};
      });
      if (ctx.mounted && e.fields.isEmpty) showToast(ctx, 'Could not add the client', sub: e.message, kind: ToastKind.info);
    }
  }

  loadLists();
  phone.addListener(checkPhone);
  s.start = DateTime.now().add(Duration(days: (8 - DateTime.now().weekday) % 7 == 0 ? 7 : (8 - DateTime.now().weekday) % 7)); // next Monday

  return showAppDrawer<Map>(
    context,
    title: 'Add a client',
    sub: 'For someone you already know. Link sign-ups go to Approvals.',
    icon: AppIcons.personAdd,
    builder: (ctx) => ListenableBuilder(
      listenable: s,
      builder: (ctx, _) {
        final e = s.errors;
        final she = pronoun(s.gender, cap: true), her = objective(s.gender);
        String trainerLabel(Map t) => '${t['full_name']} · ${t['clients'] ?? 0} / ${t['max_clients'] ?? 0}';
        final tr = s.trainers.where((t) => '${t['id']}' == s.trainer).firstOrNull;
        final pr = s.programs.where((p) => '${p['id']}' == s.program).firstOrNull;
        final mp = s.mealPlans.where((p) => '${p['id']}' == s.mealPlan).firstOrNull;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DrSec(title: 'Must have', sub: '$she ${verb(s.gender, 'logs')} in with this mobile number. We check it is not already used.', children: [
            _two(
              ctx,
              _field('Full name', AppTextField(controller: name, placeholder: 'Full name', autofocus: !ctx.isPhone), req: true, error: e['full_name']),
              _field(
                'Mobile',
                AppTextField(
                  controller: phone,
                  keyboard: TextInputType.phone,
                  placeholder: '98450 22118',
                  formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')), LengthLimitingTextInputFormatter(11)],
                  prefix: Text('+91', style: AppText.s(14, W.w6, color: AppColors.muted)),
                ),
                req: true,
                error: e['phone'] ?? (s.phoneCheck == 'taken' ? 'A client or sign-up already uses this number.' : null),
                below: s.phoneCheck == 'ok' && e['phone'] == null
                    ? Row(spacing: 5, children: [
                        const AppIcon(AppIcons.check, size: 13, color: AppColors.okText),
                        Flexible(child: Text('No client or sign-up with this number', style: AppText.s(12, W.w6, color: AppColors.okText))),
                      ])
                    : null,
              ),
            ),
          ]),
          DrSec(title: 'Good to have', sub: '$she can fill or change these in the app.', children: [
            _two(
              ctx,
              _field('Email', AppTextField(controller: email, keyboard: TextInputType.emailAddress, placeholder: 'For login links and receipts'), error: e['email']),
              _field(
                'Gender',
                AppSelect(s.gender.isEmpty ? 'Pick' : clientGenders.firstWhere((g) => g.$1 == s.gender, orElse: () => clientGenders.last).$2,
                    entries: [for (final (v, l) in clientGenders) MenuEntry(l, selected: v == s.gender, onTap: () => s.set(() => s.gender = v))]),
              ),
            ),
            _two(
              ctx,
              _field('Date of birth', ClientDateBox(s.dob, onPick: (v) => s.set(() => s.dob = v)), error: e['date_of_birth']),
              _field('City', AppTextField(controller: city, placeholder: 'City'), error: e['city']),
            ),
          ]),
          DrSec(title: 'Goal and body', sub: 'Optional. If you leave these empty ${pronoun(s.gender)} ${verb(s.gender, 'fills')} them in onboarding.', children: [
            _two(
              ctx,
              _field(
                'Goal',
                AppSelect(s.goal.isEmpty ? 'Pick a goal' : clientGoals.firstWhere((g) => g.$1 == s.goal, orElse: () => (s.goal, s.goal)).$2,
                    entries: [for (final (v, l) in clientGoals) MenuEntry(l, selected: v == s.goal, onTap: () => s.set(() => s.goal = v))]),
              ),
              _field('Goal weight', AppTextField(controller: goalW, keyboard: const TextInputType.numberWithOptions(decimal: true), suffix: _unit('kg')), error: e['target_weight_kg']),
            ),
            _two(
              ctx,
              _field('Height', AppTextField(controller: height, keyboard: const TextInputType.numberWithOptions(decimal: true), suffix: _unit('cm')), error: e['height_cm']),
              _field('Current weight', AppTextField(controller: weight, keyboard: const TextInputType.numberWithOptions(decimal: true), suffix: _unit('kg')),
                  error: e['current_weight_kg']),
            ),
            _field('Injuries or health notes', AppTextField(controller: notes, maxLines: 2, placeholder: 'Back pain, thyroid, recent surgery…'), error: e['health_notes']),
          ]),
          DrSec(title: 'Coaching', sub: 'Optional. Check-in forms are sent later from ${possessive(s.gender)} profile, under Forms.', children: [
            _two(
              ctx,
              _field(
                'Trainer',
                AppSelect(tr == null ? 'Pick later' : trainerLabel(tr), entries: [
                  MenuEntry('Pick later', selected: s.trainer == null, onTap: () => s.set(() => s.trainer = null)),
                  for (final t in s.trainers)
                    MenuEntry(trainerLabel(t),
                        selected: '${t['id']}' == s.trainer, onTap: t['is_full'] == true ? null : () => s.set(() => s.trainer = '${t['id']}')),
                ]),
                hint: 'You can change this later',
                error: e['trainer'],
              ),
              _field(
                'Workout program',
                AppSelect(pr == null ? 'Pick later' : '${pr['name']}', entries: [
                  MenuEntry('Pick later', selected: s.program == null, onTap: () => s.set(() => s.program = null)),
                  for (final p in s.programs) MenuEntry('${p['name']}', selected: '${p['id']}' == s.program, onTap: () => s.set(() => s.program = '${p['id']}')),
                ]),
                error: e['program'],
              ),
            ),
            _two(
              ctx,
              _field(
                'Meal plan',
                AppSelect(mp == null ? 'Pick later' : '${mp['name']}', entries: [
                  MenuEntry('Pick later', selected: s.mealPlan == null, onTap: () => s.set(() => s.mealPlan = null)),
                  for (final p in s.mealPlans) MenuEntry('${p['name']}', selected: '${p['id']}' == s.mealPlan, onTap: () => s.set(() => s.mealPlan = '${p['id']}')),
                ]),
                error: e['meal_plan'],
              ),
              _field('Plans start on', DrDateBox(s.start, onPick: (v) => s.set(() => s.start = v)),
                  hint: '${possessive(s.gender)[0].toUpperCase()}${possessive(s.gender).substring(1)} day 1 for workout and meal plans', error: e['start_date']),
            ),
          ]),
          DrSec(title: 'Access', last: true, children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedTabs<String>(
                items: const [TabItem('active', 'Active now'), TabItem('appr', 'Send to Approvals')],
                value: s.mode,
                onChanged: (v) => s.set(() => s.mode = v),
              ),
            ),
            Text(
              s.mode == 'active' ? '$she can log in as soon as ${pronoun(s.gender)} ${verb(s.gender, 'opens')} the link.' : '$she ${verb(s.gender, 'shows')} up in Approvals first, like people who sign up with a link.',
              style: AppText.s(12.5, W.w5, color: AppColors.muted),
            ),
            DrSwitch(
              title: 'Send $her the login link',
              sub: email.text.trim().isEmpty ? 'Add an email above to send it. $she ${verb(s.gender, 'sets')} ${possessive(s.gender)} own password.' : 'By email. $she ${verb(s.gender, 'sets')} ${possessive(s.gender)} own password.',
              value: s.sendLink,
              onChanged: (v) => s.set(() => s.sendLink = v),
            ),
            DrSwitch(
              title: 'Ask $her to fill the health form (PAR-Q)',
              sub: 'Shown on ${possessive(s.gender)} first login',
              value: s.askParq,
              onChanged: (v) => s.set(() => s.askParq = v),
            ),
          ]),
        ]);
      },
    ),
    footer: (ctx) => [
      if (!ctx.isPhone) Expanded(child: CutText('Only name and mobile are needed', maxLines: 1, style: AppText.s(12.5, W.w6, color: AppColors.muted))),
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      ListenableBuilder(
        listenable: s,
        builder: (_, _) => AppButton.primary(s.mode == 'active' ? 'Add client' : 'Add and send to Approvals',
            icon: AppIcons.check, expand: ctx.isPhone, loading: s.busy, onPressed: s.busy ? null : () => save(ctx)),
      ),
    ],
  ).whenComplete(() {
    phone.removeListener(checkPhone);
    disposeLater([s, name, phone, email, city, goalW, height, weight, notes]);
  });
}

// ─────────────────────────────── Change trainer

class _MoveState extends ChangeNotifier {
  Map? data;
  ApiError? error;
  String? pick;
  String q = '';
  bool busy = false, moveCheckins = true, tellClient = true, tellOld = false;
  void set(VoidCallback f) {
    f();
    notifyListeners();
  }
}

/// "Change Riya's trainer" drawer (board ClientProfile `tm`, Clients row ⋯ → Change trainer): trainers with
/// their load, what happens when she moves, a note for the new trainer. Returns true when moved.
Future<bool?> showChangeTrainerDrawer(BuildContext context, {required String id, required String name, String gender = ''}) {
  final s = _MoveState();
  final note = TextEditingController();
  final first = name.split(' ').first;
  Services.api.get<Map>('clients/$id/trainers/').then((d) {
    s.set(() {
      s.data = d;
      final rows = [for (final t in (d['trainers'] as List)) t as Map];
      // the board picks the best fit with space; nothing when no one has space
      s.pick = '${rows.where((t) => t['current'] != true && t['full'] != true && t['good_fit'] == true).firstOrNull?['id'] ?? rows.where((t) => t['current'] != true && t['full'] != true).firstOrNull?['id'] ?? ''}';
      if (s.pick!.isEmpty) s.pick = null;
    });
  }).catchError((Object e) {
    s.set(() => s.error = e is ApiError ? e : null);
  });

  Future<void> save(BuildContext ctx) async {
    if (s.pick == null) return;
    s.set(() => s.busy = true);
    try {
      await Services.api.post('clients/$id/change-trainer/', {
        'trainer': s.pick,
        'move_checkins': s.moveCheckins,
        'tell_client': s.tellClient,
        'tell_old': s.tellOld,
        'note': note.text.trim(),
      });
      if (ctx.mounted) Navigator.of(ctx).pop(true);
    } on ApiError catch (e) {
      s.set(() => s.busy = false);
      if (ctx.mounted) showToast(ctx, 'Could not change the trainer', sub: e.fields['trainer']?.join(' ') ?? e.message, kind: ToastKind.info);
    }
  }

  Map? picked() => s.data == null ? null : (s.data!['trainers'] as List).cast<Map>().where((t) => '${t['id']}' == s.pick).firstOrNull;
  return showAppDrawer<bool>(
    context,
    title: 'Change $first’s trainer',
    icon: AppIcons.swap,
    builder: (ctx) => ListenableBuilder(
      listenable: s,
      builder: (ctx, _) {
        if (s.data == null && s.error == null) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))),
          );
        }
        if (s.data == null) return EmptyState('Could not load the trainers', sub: s.error?.message);
        final d = s.data!;
        final current = d['current'] as Map?;
        final since = DateTime.tryParse('${d['since'] ?? ''}');
        final oldName = '${current?['full_name'] ?? ''}';
        final open = (d['open_checkins'] as num?)?.toInt() ?? 0;
        final rows = [
          for (final t in (d['trainers'] as List).cast<Map>())
            if (s.q.isEmpty || '${t['full_name']} ${(t['speciality'] as List?)?.join(' ') ?? ''}'.toLowerCase().contains(s.q.toLowerCase())) t,
        ];
        final she = pronoun(gender, cap: true);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(current == null ? '$first has no trainer yet' : 'With $oldName${since == null ? '' : ' since ${DateFormat('d MMM').format(since.toLocal())}'}',
                style: AppText.s(12.5, W.w5, color: AppColors.muted)),
          ),
          DrSec(title: 'Pick a trainer', sub: 'Load shows clients now vs the most they take.', children: [
            AppSearchField(placeholder: 'Search trainers', icon: AppIcons.search, onChanged: (v) => s.set(() => s.q = v.trim())),
            if (rows.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('No trainer matches "${s.q}".', style: AppText.cap))
            else
              TrainerPickList([
                for (final t in rows)
                  TrainerPickRow(
                    t: t,
                    on: '${t['id']}' == s.pick,
                    onTap: () => s.set(() => s.pick = '${t['id']}'),
                    tags: [
                      if (t['current'] == true) ('Current', Tone.neutral),
                      if (t['full'] == true) ('Full', Tone.warn),
                      if (t['good_fit'] == true && t['full'] != true && t['current'] != true) ('Good fit', Tone.ok),
                    ],
                  ),
              ]),
          ]),
          DrSec(title: 'When you move ${objective(gender)}', children: [
            if (open > 0)
              DrSwitch(
                title: 'Move ${possessive(gender)} open check-ins',
                sub: s.moveCheckins
                    ? '$open waiting for review go to the new trainer'
                    : '$open waiting for review are marked as seen. The new trainer starts fresh.',
                value: s.moveCheckins,
                onChanged: (v) => s.set(() => s.moveCheckins = v),
              ),
            DrSwitch(
              title: 'Tell $first',
              sub: '$she ${verb(gender, 'sees')} the new trainer’s name and photo',
              value: s.tellClient,
              onChanged: (v) => s.set(() => s.tellClient = v),
            ),
            if (current != null && '${current['id']}' != Services.session.me?.id)
              DrSwitch(
                title: 'Tell $oldName',
                sub: 'They get a notice that $first moved',
                value: s.tellOld,
                onChanged: (v) => s.set(() => s.tellOld = v),
              ),
          ]),
          DrSec(title: 'Note for the new trainer', last: true, children: [
            AppTextField(controller: note, maxLines: 3, placeholder: 'Knee issue, prefers veg meals, wedding in Feb…'),
          ]),
        ]);
      },
    ),
    footer: (ctx) => [
      if (!ctx.isPhone) Expanded(child: CutText('Plans, logs and notes stay with $first', maxLines: 1, style: AppText.s(12.5, W.w6, color: AppColors.muted))),
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      ListenableBuilder(
        listenable: s,
        builder: (_, _) {
          final t = picked();
          return AppButton.primary(t == null ? 'Pick a trainer' : 'Move to ${t['full_name']}',
              expand: ctx.isPhone, loading: s.busy, onPressed: t == null || s.busy ? null : () => save(ctx));
        },
      ),
    ],
  ).whenComplete(() => disposeLater([s, note]));
}
