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
import '../../trainer/clients/clients_parts.dart' show clientGenders, clientGoals;
import '../clients/admin_client_drawers.dart' show TrainerPickList, TrainerPickRow, objective, possessive, pronoun, verb;

// Admin drawers of the Trainers and Trainer profile boards (D-48): Add a trainer, Deactivate, Move clients to
// another trainer, Assign clients.

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

Widget _spin() => const Padding(
      padding: EdgeInsets.all(40),
      child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))),
    );

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

// ─────────────────────────────── Add a trainer

class _AddState extends ChangeNotifier {
  bool busy = false, invite = true, giveClients = false;
  String access = 'assigned', gender = '';
  DateTime joined = DateTime.now();
  Map<String, String> errors = {};

  /// Live mobile check: null while typing, 'ok', 'taken'.
  String? phoneCheck;
  void set(VoidCallback f) {
    f();
    notifyListeners();
  }
}

const _accessModes = [('assigned', 'Assigned clients'), ('all', 'All clients'), ('custom', 'Custom')];
const _accessHelp = {
  'assigned': 'Only the clients you give them: their plans and check-ins. Best for new trainers.',
  'all': 'Every client of the gym. For senior trainers who cover for others.',
  'custom': 'Pick each permission yourself after adding. Starts the same as Assigned clients.',
};

/// "Add a trainer" (board Trainers `ato`): Login details (name, mobile with a live check, email, gender), Work
/// (speciality, most clients, years, joined on), What can they see?, After you add. Returns the new trainer and
/// whether to give them clients now.
Future<(Map, bool)?> showAddTrainerDrawer(BuildContext context) {
  final s = _AddState();
  final name = TextEditingController(), phone = TextEditingController(), email = TextEditingController();
  final spec = TextEditingController(), most = TextEditingController(text: '30'), years = TextEditingController();
  var seq = 0;

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
    if (s.phoneCheck == 'taken') errs['phone'] = 'A trainer or client already uses this number.';
    if (!isEmail(email.text)) errs['email'] = 'Enter a valid email, like tara@example.com.';
    final mx = int.tryParse(most.text.trim());
    if (mx == null || mx < 1 || mx > 500) errs['max_clients'] = 'Enter a number from 1 to 500.';
    final y = years.text.trim().isEmpty ? null : int.tryParse(years.text.trim());
    if (years.text.trim().isNotEmpty && (y == null || y > 60)) errs['years'] = 'Enter the years, 0 to 60.';
    s.set(() => s.errors = errs);
    if (errs.isNotEmpty) return;
    s.set(() => s.busy = true);
    try {
      final r = await Services.api.post<Map>('trainers/', {
        'full_name': name.text.trim(),
        'phone': '+91$digits',
        'email': email.text.trim(),
        'gender': s.gender,
        'speciality': spec.text.trim(),
        'max_clients': mx,
        'experience_since': y == null ? null : DateTime.now().year - y,
        'joining_date': DateFormat('yyyy-MM-dd').format(s.joined),
        'access_mode': s.access,
        'send_invite': s.invite,
      });
      if (ctx.mounted) Navigator.of(ctx).pop((r, s.giveClients));
    } on ApiError catch (e) {
      s.set(() {
        s.busy = false;
        s.errors = {for (final f in e.fields.entries) (f.key == 'experience_since' ? 'years' : f.key): f.value.join(' ')};
      });
      if (ctx.mounted && e.fields.isEmpty) showToast(ctx, 'Could not add the trainer', sub: e.message, kind: ToastKind.info);
    }
  }

  phone.addListener(checkPhone);
  return showAppDrawer<(Map, bool)>(
    context,
    title: 'Add a trainer',
    sub: 'They get their own login and see only what you allow.',
    icon: AppIcons.trainers,
    builder: (ctx) => ListenableBuilder(
      listenable: s,
      builder: (ctx, _) {
        final e = s.errors;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DrSec(title: 'Login details', sub: 'They log in with this mobile number or email.', children: [
            _two(
              ctx,
              _field('Full name', AppTextField(controller: name, placeholder: 'Full name', autofocus: !ctx.isPhone), req: true, error: e['full_name']),
              _field(
                'Mobile',
                AppTextField(
                  controller: phone,
                  keyboard: TextInputType.phone,
                  placeholder: '98330 41207',
                  formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')), LengthLimitingTextInputFormatter(11)],
                  prefix: Text('+91', style: AppText.s(14, W.w6, color: AppColors.muted)),
                ),
                req: true,
                error: e['phone'] ?? (s.phoneCheck == 'taken' ? 'A trainer or client already uses this number.' : null),
                below: s.phoneCheck == 'ok' && e['phone'] == null
                    ? Row(spacing: 5, children: [
                        const AppIcon(AppIcons.check, size: 13, color: AppColors.okText),
                        Flexible(child: Text('No trainer or client uses this number', style: AppText.s(12, W.w6, color: AppColors.okText))),
                      ])
                    : null,
              ),
            ),
            _two(
              ctx,
              _field('Email', AppTextField(controller: email, keyboard: TextInputType.emailAddress, placeholder: 'name@email.com'), req: true, error: e['email']),
              _field(
                'Gender',
                AppSelect(s.gender.isEmpty ? 'Pick' : clientGenders.firstWhere((g) => g.$1 == s.gender, orElse: () => clientGenders.last).$2,
                    entries: [for (final (v, l) in clientGenders) MenuEntry(l, selected: v == s.gender, onTap: () => s.set(() => s.gender = v))]),
                hint: 'For clients who ask for a woman trainer',
                error: e['gender'],
              ),
            ),
          ]),
          DrSec(title: 'Work', children: [
            _two(
              ctx,
              _field('Speciality', AppTextField(controller: spec, placeholder: 'Strength, Fat loss'), hint: 'Separate with a comma', error: e['speciality']),
              _field('Most clients they can take', AppTextField(controller: most, keyboard: TextInputType.number, formatters: inputRules(TextInputType.number)),
                  hint: 'A number. You can change this later', error: e['max_clients']),
            ),
            _two(
              ctx,
              _field('Experience (years)', AppTextField(controller: years, keyboard: TextInputType.number, formatters: inputRules(TextInputType.number), placeholder: '4'),
                  hint: 'Shown on their profile', error: e['years']),
              _field('Joined on', DrDateBox(s.joined, first: DateTime(2015), onPick: (v) => s.set(() => s.joined = v)), error: e['joining_date']),
            ),
            Text('Certificates and ID documents are added from their profile, under Documents.', style: AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.45)),
          ]),
          DrSec(title: 'What can they see?', sub: 'You can change every permission later under Access and permissions.', children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedTabs<String>(
                  items: [for (final (v, l) in _accessModes) TabItem(v, l)],
                  value: s.access,
                  onChanged: (v) => s.set(() => s.access = v),
                ),
              ),
            ),
            Text(_accessHelp[s.access]!, style: AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.45)),
          ]),
          DrSec(title: 'After you add', last: true, children: [
            DrSwitch(
              title: 'Send the login invite',
              sub: 'WhatsApp and email. They set their own password.',
              value: s.invite,
              onChanged: (v) => s.set(() => s.invite = v),
            ),
            DrSwitch(
              title: 'Give them clients now',
              sub: 'Opens their Clients tab to pick clients for them',
              value: s.giveClients,
              onChanged: (v) => s.set(() => s.giveClients = v),
            ),
          ]),
        ]);
      },
    ),
    footer: (ctx) => [
      if (!ctx.isPhone) Expanded(child: CutText('They cannot add trainers or change gym settings', maxLines: 1, style: AppText.s(12.5, W.w6, color: AppColors.muted))),
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      ListenableBuilder(
        listenable: s,
        builder: (_, _) => AppButton.primary('Add trainer', icon: AppIcons.check, expand: ctx.isPhone, loading: s.busy, onPressed: s.busy ? null : () => save(ctx)),
      ),
    ],
  ).whenComplete(() {
    phone.removeListener(checkPhone);
    disposeLater([s, name, phone, email, spec, most, years]);
  });
}

// ─────────────────────────────── Deactivate

/// "Deactivate Karan Mehta?" (board Trainers `deo`): What happens, Move their clients to (share between trainers with
/// space, one trainer, or keep them for now). Returns true when deactivated.
Future<bool> showDeactivateTrainer(BuildContext context, {required String id, required String name}) async {
  final first = name.split(' ').first;
  Map? pre;
  try {
    pre = await Services.api.get<Map>('trainers/$id/deactivate-preview/');
  } on ApiError catch (e) {
    if (context.mounted) showToast(context, 'Could not open this', sub: e.message, kind: ToastKind.err);
    return false;
  }
  if (!context.mounted) return false;
  final n = (pre['clients'] as num?)?.toInt() ?? 0;
  final others = [for (final t in (pre['trainers_with_space'] as List?) ?? const []) t as Map];
  final free = others.fold<int>(0, (a, t) => a + ((t['free'] as num?)?.toInt() ?? 0));
  // Share when everyone fits; else keep them with the trainer until they are moved.
  var to = n == 0 ? '' : (free >= n ? 'share' : 'keep');
  var busy = false;
  String label(String v) => switch (v) {
        '' => 'Nothing to move',
        'share' => 'Share between trainers with space',
        'keep' => 'Keep them with $first for now',
        _ => () {
            final t = others.firstWhere((t) => '${t['id']}' == v);
            return '${t['full_name']} (${t['free']} free)';
          }(),
      };
  final ok = await showAppModal<bool>(
    context,
    title: 'Deactivate $name?',
    body: 'You can reactivate $first any time.',
    icon: AppIcons.deactivate,
    danger: true,
    content: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final moving = to == 'share' || (to.isNotEmpty && to != 'keep');
        final bullets = [
          '$first cannot log in from now.',
          n == 0
              ? 'They have no clients right now.'
              : moving
                  ? 'Their $n ${n == 1 ? 'client moves' : 'clients move'} to ${to == 'share' ? 'trainers with space' : label(to).replaceFirst(RegExp(r' \(.*$'), '')} and ${n == 1 ? 'gets' : 'get'} a notice.'
                  : 'Their $n ${n == 1 ? 'client stays' : 'clients stay'} with them until you move them. Those clients get no check-in reviews meanwhile.',
          'Their plans, notes and check-in history stay.',
        ];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          Text('WHAT HAPPENS', style: AppText.s(11.5, W.w7, color: AppColors.muted, ls: .5)),
          for (final b in bullets)
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              Padding(padding: const EdgeInsets.only(top: 7), child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.muted, shape: BoxShape.circle))),
              Expanded(child: Text(b, style: AppText.s(13, W.w5, color: AppColors.text2, h: 1.45))),
            ]),
          const SizedBox(height: 6),
          _field(
            'Move their clients to',
            AppSelect(label(to), entries: n == 0
                ? const []
                : [
                    MenuEntry(label('share'), selected: to == 'share', onTap: free >= n ? () => set(() => to = 'share') : null),
                    for (final t in others) MenuEntry(label('${t['id']}'), selected: to == '${t['id']}', onTap: () => set(() => to = '${t['id']}')),
                    MenuEntry(label('keep'), selected: to == 'keep', onTap: () => set(() => to = 'keep')),
                  ]),
            hint: n == 0
                ? null
                : others.isEmpty
                    ? 'No trainer has free spots. Raise someone’s most clients first.'
                    : others.map((t) => '${'${t['full_name']}'.split(' ').first} (${t['free']} free)').join(', '),
          ),
        ]);
      },
    ),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop(false)),
      StatefulBuilder(
        builder: (bctx, set) => AppButton('Deactivate', kind: BtnKind.danger, expand: ctx.isPhone, loading: busy, onPressed: busy
            ? null
            : () async {
                set(() => busy = true);
                try {
                  await Services.api.post('trainers/$id/deactivate/', {if (to.isNotEmpty && to != 'keep') 'move_to': to});
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                } on ApiError catch (e) {
                  set(() => busy = false);
                  if (ctx.mounted) showToast(ctx, 'Could not deactivate $first', sub: e.message, kind: ToastKind.err);
                }
              }),
      ),
    ],
  );
  return ok ?? false;
}

// ─────────────────────────────── Move clients to another trainer

class _MoveState extends ChangeNotifier {
  List<Map>? trainers;
  ApiError? error;
  String? pick;
  bool busy = false, tell = true;
  void set(VoidCallback f) {
    f();
    notifyListeners();
  }
}

/// "Move Aman’s clients" (row ⋯ → Move clients to another trainer, profile ⋯ → Move all clients): share between
/// trainers with space or pick one trainer; Tell the clients. Returns how many moved.
Future<int?> showMoveTrainerClients(BuildContext context, {required String id, required String name, required int clients}) async {
  final first = name.split(' ').first;
  if (clients == 0) {
    showToast(context, '$first has no clients to move', kind: ToastKind.info);
    return null;
  }
  final s = _MoveState();
  Services.api.get<List>('trainers/with-space/').then((r) {
    s.set(() {
      s.trainers = [for (final t in r) if ('${(t as Map)['id']}' != id) t];
      final free = s.trainers!.fold<int>(0, (a, t) => a + ((t['free'] as num?)?.toInt() ?? 0));
      s.pick = free >= clients ? 'share' : s.trainers!.where((t) => ((t['free'] as num?) ?? 0) >= clients).firstOrNull?['id']?.toString();
    });
  }).catchError((Object e) {
    s.set(() => s.error = e is ApiError ? e : null);
  });

  Future<void> save(BuildContext ctx) async {
    if (s.pick == null) return;
    s.set(() => s.busy = true);
    try {
      final r = await Services.api.post<Map>('trainers/$id/move-clients/', {'to': s.pick, 'tell_clients': s.tell});
      if (ctx.mounted) Navigator.of(ctx).pop((r['moved'] as num?)?.toInt() ?? 0);
    } on ApiError catch (e) {
      s.set(() => s.busy = false);
      if (ctx.mounted) showToast(ctx, 'Could not move the clients', sub: e.message, kind: ToastKind.err);
    }
  }

  return showAppDrawer<int>(
    context,
    title: 'Move $first’s clients',
    sub: '$clients ${clients == 1 ? 'client' : 'clients'} · plans, logs and notes move with them',
    icon: AppIcons.swapBoth,
    builder: (ctx) => ListenableBuilder(
      listenable: s,
      builder: (ctx, _) {
        if (s.trainers == null && s.error == null) return _spin();
        if (s.trainers == null) return EmptyState('Could not load the trainers', sub: s.error?.message);
        final ts = s.trainers!;
        final free = ts.fold<int>(0, (a, t) => a + ((t['free'] as num?)?.toInt() ?? 0));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DrSec(title: 'Move them to', sub: 'Load shows clients now vs the most they take.', children: [
            DrOpts([
              Opacity(
                opacity: free >= clients ? 1 : .55,
                child: Hover(
                  onTap: free >= clients ? () => s.set(() => s.pick = 'share') : null,
                  builder: (_, h, _) => Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    color: h && free >= clients ? AppColors.outlineHover : null,
                    child: Row(spacing: 12, children: [
                      AppRadio(selected: s.pick == 'share', onTap: free >= clients ? () => s.set(() => s.pick = 'share') : null),
                      const IconTile(AppIcons.team, size: 30, radius: 15, iconSize: 15),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                          Text('Share between trainers with space', style: AppText.s(13.5, W.w7)),
                          Text(free >= clients ? '$free free spots across the team' : 'Only $free free spots. Pick fewer or raise most clients first.',
                              style: AppText.s(12.5, W.w5, color: AppColors.muted)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ]),
            TrainerPickList([
              for (final t in ts)
                TrainerPickRow(
                  t: {...t, 'full': ((t['free'] as num?) ?? 0) < clients},
                  on: '${t['id']}' == s.pick,
                  onTap: () => s.set(() => s.pick = '${t['id']}'),
                  tags: [if (((t['free'] as num?) ?? 0) < clients) (((t['free'] as num?) ?? 0) == 0 ? 'Full' : '${t['free']} free', Tone.warn)],
                ),
            ]),
          ]),
          DrSec(title: 'When you move them', last: true, children: [
            DrSwitch(
              title: 'Tell the clients',
              sub: 'Push notice with the new trainer’s name',
              value: s.tell,
              onChanged: (v) => s.set(() => s.tell = v),
            ),
          ]),
        ]);
      },
    ),
    footer: (ctx) => [
      if (!ctx.isPhone) Expanded(child: CutText('Check-ins waiting for review move too', maxLines: 1, style: AppText.s(12.5, W.w6, color: AppColors.muted))),
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      ListenableBuilder(
        listenable: s,
        builder: (_, _) => AppButton.primary('Move $clients ${clients == 1 ? 'client' : 'clients'}',
            expand: ctx.isPhone, loading: s.busy, onPressed: s.pick == null || s.busy ? null : () => save(ctx)),
      ),
    ],
  ).whenComplete(() => disposeLater([s]));
}

// ─────────────────────────────── Assign clients

class _AssignState extends ChangeNotifier {
  List<Map>? rows;
  ApiError? error;
  String kind = 'none', q = '';
  final picked = <String>{};
  bool busy = false, tell = true, keep = true;
  void set(VoidCallback f) {
    f();
    notifyListeners();
  }
}

/// "Assign clients to Aman" (board TrainerProfile `aso`): search, No trainer / With another trainer / All chips, a
/// multi-pick list (no more than his free spots), Tell the clients, Keep their current plans. Returns how many.
Future<int?> showAssignClients(BuildContext context, {required String id, required String name, required int clients, required int max, String gender = ''}) {
  final first = name.split(' ').first;
  final he = pronoun(gender), him = objective(gender);
  final s = _AssignState();
  var seq = 0;
  Future<void> load() async {
    final my = ++seq;
    try {
      final r = await Services.api.get<List>('trainers/$id/assignable-clients/', query: {if (s.q.isNotEmpty) 'search': s.q});
      if (my != seq) return;
      s.set(() {
        s.rows = [for (final x in r) x as Map];
        s.error = null;
      });
    } on ApiError catch (e) {
      if (my == seq) s.set(() => s.error = e);
    }
  }

  Future<void> save(BuildContext ctx) async {
    s.set(() => s.busy = true);
    try {
      final r = await Services.api.post<Map>('trainers/$id/assign-clients/', {'clients': s.picked.toList(), 'tell_clients': s.tell, 'keep_plans': s.keep});
      if (ctx.mounted) Navigator.of(ctx).pop((r['assigned'] as num?)?.toInt() ?? s.picked.length);
    } on ApiError catch (e) {
      s.set(() => s.busy = false);
      if (ctx.mounted) showToast(ctx, 'Could not assign them', sub: e.message, kind: ToastKind.err);
    }
  }

  load();
  final free0 = (max - clients).clamp(0, 9999);
  return showAppDrawer<int>(
    context,
    title: 'Assign clients to $first',
    icon: AppIcons.team,
    builder: (ctx) => ListenableBuilder(
      listenable: s,
      builder: (ctx, _) {
        final left = free0 - s.picked.length;
        final all = s.rows ?? const <Map>[];
        final none = all.where((r) => r['from'] == null).length;
        final list = [
          for (final r in all)
            if (s.kind == 'all' || (s.kind == 'none') == (r['from'] == null)) r,
        ];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('${_cap(he)} ${verb(gender, 'has')} $clients of $max · $left ${left == 1 ? 'spot' : 'spots'} left after this',
                style: AppText.s(12.5, W.w5, color: AppColors.muted)),
          ),
          DrSec(
              title: 'Pick clients',
              sub: free0 == 0
                  ? '$first is full. Raise ${possessive(gender)} most clients in Edit details first.'
                  : '${_cap(he)} can take $free0 more. Full trainers’ clients can be moved to $him.',
              children: [
                AppSearchField(
                  placeholder: 'Search clients',
                  icon: AppIcons.search,
                  onChanged: (v) {
                    s.q = v.trim();
                    load();
                  },
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(spacing: 6, children: [
                    for (final (k, l, c) in [('none', 'No trainer', none), ('other', 'With another trainer', all.length - none), ('all', 'All', all.length)])
                      FilterChipX(l, selected: s.kind == k, count: c, onTap: () => s.set(() => s.kind = k)),
                  ]),
                ),
                if (s.rows == null && s.error == null)
                  _spin()
                else if (s.rows == null)
                  EmptyState('Could not load clients', sub: s.error?.message, action: AppButton('Try again', onPressed: load))
                else if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(s.q.isNotEmpty ? 'No client matches "${s.q}".' : (s.kind == 'none' ? 'Every client has a trainer.' : 'No clients here.'),
                        textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)),
                  )
                else
                  TrainerPickList(maxHeight: 336, [
                    for (final r in list)
                      _assignRow(r, on: s.picked.contains('${r['id']}'), dis: !s.picked.contains('${r['id']}') && left <= 0, onTap: () {
                        final k = '${r['id']}';
                        s.set(() => s.picked.contains(k) ? s.picked.remove(k) : s.picked.add(k));
                      }),
                  ]),
              ],
            ),
          DrSec(title: 'When you assign', last: true, children: [
            DrSwitch(title: 'Tell the clients', sub: 'Push notice: "$name is your trainer now"', value: s.tell, onChanged: (v) => s.set(() => s.tell = v)),
            DrSwitch(title: 'Keep their current plans', sub: '$first can change them later', value: s.keep, onChanged: (v) => s.set(() => s.keep = v)),
          ]),
        ]);
      },
    ),
    footer: (ctx) => [
      if (!ctx.isPhone) Expanded(child: ListenableBuilder(listenable: s, builder: (_, _) => Text('${s.picked.length} picked', style: AppText.s(12.5, W.w6, color: AppColors.muted)))),
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      ListenableBuilder(
        listenable: s,
        builder: (_, _) {
          final n = s.picked.length;
          return AppButton.primary('Assign $n ${n == 1 ? 'client' : 'clients'}', expand: ctx.isPhone, loading: s.busy, onPressed: n == 0 || s.busy ? null : () => save(ctx));
        },
      ),
    ],
  ).whenComplete(() => disposeLater([s]));
}

/// `.dr-opt.sm` in `.dr-opts.multi`: square tick, avatar, name over "Fat loss · from Karan Mehta (full)", badge.
Widget _assignRow(Map r, {required bool on, required bool dis, required VoidCallback onTap}) {
  final from = r['from'] as Map?;
  final goal = clientGoals.where((g) => g.$1 == '${r['goal'] ?? ''}').firstOrNull?.$2 ?? '';
  final sub = [
    if (goal.isNotEmpty) goal,
    if (from != null) 'from ${from['full_name']}${from['full'] == true ? ' (full)' : ''}' else 'no trainer yet',
  ].join(' · ');
  return Opacity(
    opacity: dis ? .5 : 1,
    child: Hover(
      onTap: dis ? null : onTap,
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        color: h && !dis ? AppColors.outlineHover : null,
        child: Row(spacing: 10, children: [
          AppCheckbox(value: on, onChanged: dis ? null : (_) => onTap()),
          AppAvatar('${r['full_name']}', size: 28, colors: AppColors.avatarCode('${r['avatar_color'] ?? 'c1'}'), initials: '${r['initials'] ?? ''}'),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              CutText('${r['full_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7)),
              CutText(_cap(sub), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
            ]),
          ),
          AppTooltip(
            message: from == null ? 'Has no trainer' : 'With ${from['full_name']} now',
            child: AppBadge(from == null ? 'No trainer' : '${from['full_name']}', tone: from == null ? Tone.warn : Tone.neutral, plain: true),
          ),
        ]),
      ),
    ),
  );
}
