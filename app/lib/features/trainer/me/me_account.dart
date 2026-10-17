import 'package:flutter/material.dart';

import '../../../app/router.dart' show confirmLogOut;
import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import 'me_common.dart';
import 'me_model.dart';

/// Account tab: Password (Change password), Where you are logged in (Log out, Log out of all others, 5 a page),
/// Notifications (saved as you switch).
class MeAccountTab extends StatefulWidget {
  const MeAccountTab(this.c, {super.key});
  final MeController c;
  @override
  State<MeAccountTab> createState() => _MeAccountTabState();
}

const _notes = [
  ('new_checkin', 'New check-in', 'When a client sends a check-in'),
  ('missed_workouts', 'Missed workouts', 'When a client misses 2 in a row'),
  ('new_client', 'New client', 'When the admin gives you a client'),
  ('session_reminders', 'Session reminders', '30 minutes before each session'),
  ('daily_summary', 'Daily summary', 'Email at 8:00 am with your day'),
  ('gym_news', 'Gym news', 'Notices from Vimal'),
];

class _MeAccountTabState extends State<MeAccountTab> {
  List<Map> devs = [];
  int devCount = 0, others = 0, page = 1;
  bool devMore = false, devLoading = true, moreLoading = false;
  Map<String, dynamic> notes = {};

  @override
  void initState() {
    super.initState();
    _devices();
    Services.api.get<Map>('trainers/me/notifications/').then((r) {
      if (mounted) setState(() => notes = Map<String, dynamic>.from(r));
    }).catchError((_) {});
  }

  Future<void> _devices({bool next = false}) async {
    if (next) setState(() => moreLoading = true);
    try {
      final p = next ? page + 1 : 1;
      final r = await Services.api.get<Map>('trainers/me/devices/', query: {'page': p});
      if (!mounted) return;
      final rows = [for (final x in (r['results'] as List?) ?? const []) x as Map];
      setState(() {
        devs = next ? [...devs, ...rows] : rows;
        page = p;
        devCount = (r['count'] as num?)?.toInt() ?? rows.length;
        others = (r['others'] as num?)?.toInt() ?? 0;
        devMore = r['has_more'] == true;
      });
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not load your devices', sub: e.message, kind: ToastKind.err);
    }
    if (mounted) setState(() => devLoading = moreLoading = false);
  }

  Future<void> _out(Map d) async {
    try {
      await Services.api.delete('auth/sessions/${d['id']}/');
      if (!mounted) return;
      showToast(context, 'Logged out', sub: '${d['label']}', kind: ToastKind.ok);
      _devices();
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not log it out', sub: e.message, kind: ToastKind.err);
    }
  }

  Future<void> _outAll() async {
    try {
      final r = await Services.api.post<Map>('auth/sessions/logout-others/');
      if (!mounted) return;
      final n = (r['logged_out'] as num?)?.toInt() ?? 0;
      showToast(context, 'Logged out of $n ${n == 1 ? 'device' : 'devices'}', sub: 'Only this ${context.isPhone ? 'phone' : 'browser'} stays logged in', kind: ToastKind.ok);
      _devices();
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not log them out', sub: e.message, kind: ToastKind.err);
    }
  }

  Future<void> _note(String k, bool v) async {
    final old = notes[k];
    setState(() => notes = {...notes, k: v});
    try {
      final r = await Services.api.put<Map>('trainers/me/notifications/', {k: v});
      if (mounted) setState(() => notes = Map<String, dynamic>.from(r));
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => notes = {...notes, k: old});
      showToast(context, 'Could not save', sub: e.message, kind: ToastKind.err);
    }
  }

  String get _changed {
    final t = meParse(widget.c.me['password_changed_at']);
    if (t == null) return 'Not changed since you joined';
    final days = DateTime.now().difference(t).inDays;
    if (days < 1) return 'Last changed today';
    if (days < 2) return 'Last changed yesterday';
    if (days < 31) return 'Last changed $days days ago';
    final m = (days / 30).floor();
    if (m < 12) return 'Last changed $m ${m == 1 ? 'month' : 'months'} ago';
    final y = (days / 365).floor();
    return 'Last changed $y ${y == 1 ? 'year' : 'years'} ago';
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final pw = MeCard(
      title: 'Password',
      sub: _changed,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 12, spacing: 12, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('••••••••••', style: AppText.s(15, W.w7, ls: 1.5)),
            Text('Use at least 8 letters and a number', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
          ]),
          AppButton('Change password', icon: AppIcons.lock, expand: phone, onPressed: () async {
            if (await _changePassword(context) && mounted) {
              widget.c.reloadMe();
              _devices();
            }
          }),
        ]),
      ),
    );
    final devices = MeCard(
      title: 'Where you are logged in',
      sub: devLoading ? '' : '$devCount ${devCount == 1 ? 'device' : 'devices'}',
      action: others > 0 ? MeTextBtn('Log out of all others', onTap: _outAll) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: devLoading
            ? const MeLoading()
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (i, d) in devs.indexed)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
                    child: Row(spacing: 10, children: [
                      IconTile(d['phone'] == true ? AppIcons.mobile : AppIcons.web, size: 36, radius: 10, iconSize: 18, bg: AppColors.sub, fg: AppColors.text2),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                          Text('${d['label']}', style: AppText.s(13, W.w6)),
                          Text('${d['sub']}', style: AppText.s(12, W.w4, color: AppColors.muted)),
                        ]),
                      ),
                      if (d['this_device'] == true) ...[
                        const AppBadge('This device', tone: Tone.ok, plain: true),
                        AppButton('Log out', size: BtnSize.sm, onPressed: () => confirmLogOut(context)),
                      ] else
                        AppButton('Log out', size: BtnSize.sm, onPressed: () => _out(d)),
                    ]),
                  ),
                if (devMore)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 6),
                    child: Row(children: [
                      Expanded(child: Text('Showing ${devs.length} of $devCount', style: AppText.cap)),
                      AppButton('Show more', size: BtnSize.sm, loading: moreLoading, onPressed: () => _devices(next: true)),
                    ]),
                  ),
              ]),
      ),
    );
    final nts = MeCard(
      title: 'Notifications',
      sub: 'Push to your phone and email',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: notes.isEmpty
            ? const MeLoading()
            : Column(children: [
                for (final (k, t, s) in _notes) MeToggleRow(title: t, sub: s, value: notes[k] == true, onChanged: (v) => _note(k, v)),
              ]),
      ),
    );
    return MeColumns(leftFlex: 16, rightFlex: 10, left: [pw, devices], right: [nts]);
  }
}

/// "Change password" modal: Current, New (8+ with a letter and a number), Type it again. Other devices log out.
Future<bool> _changePassword(BuildContext context) async {
  final cur = TextEditingController(), nw = TextEditingController(), again = TextEditingController();
  String? eCur, eNew, eAgain;
  var saving = false;
  late StateSetter setForm;
  final done = await showAppModal<bool>(
    context,
    title: 'Change password',
    body: 'You stay logged in on this device.',
    icon: AppIcons.lock,
    content: (ctx) => StatefulBuilder(builder: (ctx, set) {
      setForm = set;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        meField('Current password', AppTextField(controller: cur, obscure: true, autofill: const [AutofillHints.password]), req: true, error: eCur),
        meField('New password', AppTextField(controller: nw, obscure: true, placeholder: 'At least 8 letters and a number', autofill: const [AutofillHints.newPassword]), req: true, error: eNew),
        meField('Type it again', AppTextField(controller: again, obscure: true), req: true, error: eAgain),
      ]);
    }),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      StatefulBuilder(
        builder: (_, setBtn) => AppButton.primary('Change password', expand: ctx.isPhone, loading: saving, onPressed: () async {
          final n = nw.text;
          setForm(() {
            eCur = cur.text.isEmpty ? 'Enter your current password.' : null;
            eNew = n.length < 8 || !RegExp(r'[A-Za-z]').hasMatch(n) || !RegExp(r'\d').hasMatch(n) ? 'Use at least 8 letters and a number.' : null;
            eAgain = eNew == null && again.text != n ? 'The two passwords do not match.' : null;
          });
          if (eCur != null || eNew != null || eAgain != null) return;
          setBtn(() => saving = true);
          try {
            await Services.api.post('auth/password/change/', {'current_password': cur.text, 'new_password': n});
            if (ctx.mounted) Navigator.of(ctx).pop(true);
          } on ApiError catch (e) {
            setBtn(() => saving = false);
            setForm(() {
              eCur = e.field('current_password');
              eNew = e.field('new_password') ?? (eCur == null ? e.message : null);
            });
          }
        }),
      ),
    ],
  );
  cur.dispose();
  nw.dispose();
  again.dispose();
  if (done == true && context.mounted) showToast(context, 'Password changed', sub: 'Other devices need the new password', kind: ToastKind.ok);
  return done == true;
}
