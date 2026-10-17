import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/services.dart';
import '../../core/api/api_error.dart';
import '../../core/icons/app_icons.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/client.dart';
import '../../core/widgets/overlays.dart';
import 'account_widgets.dart';
import 'auth_frame.dart';
import 'setup/setup_state.dart';
import 'sheets.dart';

/// "Almost there" — waiting for the coach to approve a sign-up (`wl-pending`).
/// Also shows the approved state when the approval lands while the page is open.
class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key});
  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> with WidgetsBindingObserver {
  static const _alertKey = 'twv.approvalAlert';
  bool _alert = true, _checked = false, _busy = false;
  StreamSubscription? _rt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Services.session.addListener(_changed);
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _alert = p.getBool(_alertKey) ?? true);
    });
    // Anything from the server while waiting (approval, welcome) → look again.
    _rt = Services.realtime.events.listen((_) => _refresh(silent: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh(silent: true);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Services.session.removeListener(_changed);
    _rt?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    final was = Services.session.me?.pending ?? true;
    try {
      await Services.session.refreshMe();
    } on ApiError catch (e) {
      if (!silent && mounted) showToast(context, 'Could not check', sub: e.message, kind: ToastKind.err);
      return;
    }
    if (!mounted) return;
    final me = Services.session.me!;
    if (was && !me.pending) {
      showToast(context, '${me.coachFirst} approved your account', sub: 'You can use the app now', kind: ToastKind.star);
    } else if (!silent) {
      showToast(context, 'Still in review', sub: 'Checked just now · we will ping you when it is approved', kind: ToastKind.info);
      setState(() => _checked = true);
    }
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _setAlert(bool v) async {
    setState(() => _alert = v);
    (await SharedPreferences.getInstance()).setBool(_alertKey, v);
    if (!mounted) return;
    if (v) {
      showToast(context, 'Notifications on', sub: 'We will ping you as soon as you are approved', kind: ToastKind.ok);
    } else {
      showToast(context, 'Notifications off', sub: 'You will still get an email', kind: ToastKind.info, action: 'Undo', onAction: () => _setAlert(true));
    }
  }

  Future<void> _logOut() async {
    final email = Services.session.me?.email ?? Services.session.me?.phone ?? '';
    SetupState.instance.reset();
    await Services.session.signOut();
    if (mounted) showToast(context, 'Logged out', sub: 'Log in again any time with $email', kind: ToastKind.info);
  }

  void _go() {
    final me = Services.session.me!;
    if (me.setupComplete) return context.go('/setup/done');
    if (me.setupDone.isEmpty) return context.go('/setup?step=0');
    context.go('/setup/checklist');
  }

  String _joined(Me me) {
    final d = DateTime.tryParse('${me.json['date_joined']}')?.toLocal();
    if (d == null) return '';
    final ago = DateTime.now().difference(d);
    if (ago.inMinutes < 60) return 'just now';
    if (ago.inHours < 24) return 'today';
    if (ago.inDays < 2) return 'yesterday';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final me = Services.session.me!;
    final ok = !me.pending;
    final coach = me.coachFirst;
    final team = me.hasCoach ? 'Coach $coach' : 'The gym team';
    final n = me.setupDone.length;
    final tl = [
      ('Account created', '${me.email ?? me.phone ?? ''} · ${_joined(me)}', true, false),
      (
        'Coach approval',
        ok ? 'Approved by ${me.coachFull}' : '${me.hasCoach ? me.coachFull : 'The gym team'} · usually within 24 hours',
        ok,
        !ok,
      ),
      ('Complete your profile', n >= me.setupTotal ? 'All ${me.setupTotal} steps done' : '$n of ${me.setupTotal} steps done · goal, body, health, food', n >= me.setupTotal, ok && n < me.setupTotal),
    ];
    final goT = me.setupComplete ? 'See your profile' : (ok ? 'Set up your profile' : 'Finish your profile meanwhile');
    return AuthFrame(
      foot: [
        CaButton(goT, onPressed: _go),
        CaButton('Log out', kind: CaBtnKind.out, icon: AppIcons.logout, onPressed: _logOut),
      ],
      children: [
        SizedBox(height: 36, child: Row(children: [const Spacer(), CaLink('Need help?', size: 13, onTap: () => showHelpSheet(context))])),
        Center(
          child: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: ok ? AppColors.okBg : AppColors.amberBg, shape: BoxShape.circle),
            child: AppIcon(ok ? AppIcons.check : AppIcons.clock, size: 30, color: ok ? AppColors.okText : AppColors.amberText, stroke: 2.2),
          ),
        ),
        Column(spacing: 4, children: [
          Text(ok ? 'You’re approved, ${me.firstName}!' : 'Almost there, ${me.firstName}!', textAlign: TextAlign.center, style: AppText.s(24, W.w8, ls: -0.24, h: 1.2)),
          Text(
            ok
                ? '$coach approved your account. Finish your profile so $coach can build your plan.'
                : 'Your account is created. $team approves it next, usually within 24 hours.',
            textAlign: TextAlign.center,
            style: AppText.s(13.5, W.w4, color: AppColors.muted, h: 1.45),
          ),
        ]),
        CaCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
            Row(children: [
              Expanded(child: Text('What happens next', style: AppText.s(15, W.w8))),
              CaPill(ok ? 'Approved' : 'In review', tone: ok ? CaTone.green : CaTone.amber),
            ]),
            CaTimeline(tl),
            if (!ok) CaButton(_checked ? 'Check again' : 'Check status', kind: CaBtnKind.out, small: true, expand: false, loading: _busy, onPressed: _check),
          ]),
        ),
        if (!ok)
          CaCheckRow(
            boxed: true,
            on: _alert,
            onTap: () => _setAlert(!_alert),
            title: 'Get the approval alert right away',
            sub: _alert ? 'Push notification and email' : 'You will still get an email',
          ),
      ],
    );
  }
}
