import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/overlays.dart';
import '../auth_frame.dart';
import 'setup_screen.dart';
import 'setup_state.dart';

/// "You're all set" — profile summary after the 5 steps (`wl-done`).
class DoneScreen extends StatefulWidget {
  const DoneScreen({super.key});
  @override
  State<DoneScreen> createState() => _DoneScreenState();
}

class _DoneScreenState extends State<DoneScreen> {
  final st = SetupState.instance;

  @override
  void initState() {
    super.initState();
    st.addListener(_changed);
    Services.session.addListener(_changed);
    st.load().catchError((_) {});
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    st.removeListener(_changed);
    Services.session.removeListener(_changed);
    super.dispose();
  }

  Future<void> _check() async {
    try {
      await Services.session.refreshMe();
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not check', sub: e.message, kind: ToastKind.err);
      return;
    }
    if (!mounted) return;
    final me = Services.session.me!;
    if (me.pending) {
      showToast(context, 'Still in review', sub: 'Checked just now · we will ping you when it is approved', kind: ToastKind.info);
    } else {
      showToast(context, '${me.coachFirst} approved your account', sub: 'You can use the app now', kind: ToastKind.star);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = Services.session.me!;
    final coach = me.coachFirst;
    final wait = me.pending;
    return AuthFrame(
      brand: BrandKind.steps,
      footBorder: !authSplit(context),
      steps: setupBrand(context, fromDone: true),
      foot: [
        CaButton(
          'Go to Home',
          trailingIcon: AppIcons.chevronRight,
          dimmed: wait,
          onPressed: wait
              ? () => showToast(context, 'Waiting for $coach’s approval', sub: 'Tap Check status, or we will ping you when it is done', kind: ToastKind.warn)
              : () => context.go('/home'),
        ),
      ],
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            margin: const EdgeInsets.only(top: 18),
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
            child: const AppIcon(AppIcons.star, size: 30, color: AppColors.accent, stroke: 2.2),
          ),
        ),
        Column(spacing: 4, children: [
          Text('You’re all set, ${me.firstName}!', textAlign: TextAlign.center, style: AppText.s(24, W.w8, ls: -0.24, h: 1.2)),
          Text('$coach has what is needed to build your plan.', textAlign: TextAlign.center, style: AppText.s(13.5, W.w4, color: AppColors.muted, h: 1.45)),
        ]),
        if (wait)
          CaHint('$coach is still reviewing your account', icon: AppIcons.clock, tone: CaTone.amber, action: 'Check status', onAction: _check)
        else
          CaHint('$coach approved your account · you can start now', icon: AppIcons.check, tone: CaTone.green),
        CaCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Expanded(child: Text('Your profile', style: AppText.s(15, W.w8))),
                const CaCaption('Tap a row to change it'),
              ]),
            ),
            for (final (i, row) in st.summary.indexed)
              CaMenuRow(
                labelFirst: true,
                title: row.$2,
                sub: row.$1,
                trailing: const AppIcon(AppIcons.edit, size: 16, color: AppColors.muted),
                onTap: () => context.go('/setup?step=$i&edit=1'),
              ),
          ]),
        ),
        if (me.hasCoach)
          CaCard(
            child: Row(spacing: 12, children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.caAvBg, shape: BoxShape.circle),
                child: Text(_initials(me.coachFull), style: AppText.s(13, W.w8, color: AppColors.caAvText)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                  Text('Coach $coach will guide you', style: AppText.s(14, W.w8)),
                  Text('Your first plan arrives within 24 hours. First check-in on day 7.', style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.4)),
                ]),
              ),
            ]),
          ),
      ],
    );
  }
}

String _initials(String name) {
  final p = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (p.isEmpty) return '';
  return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
}
