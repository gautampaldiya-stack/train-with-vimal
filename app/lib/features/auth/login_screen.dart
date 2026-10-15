import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/services.dart';
import '../../core/api/api_error.dart';
import '../../core/icons/app_icons.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/balanced_text.dart';
import '../../core/widgets/client.dart';
import '../../core/widgets/hover.dart';
import '../../core/widgets/overlays.dart';
import 'auth_frame.dart';
import 'intro_screen.dart';
import 'sheets.dart';

/// Welcome + Log in (boards `ClientWelcome`, `ClientLogin`, `ClientLoginWeb`).
/// Phone opens on Welcome; desktop goes straight to Log in (the side panel is the welcome).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _introKey = 'twv.introSeen';
  bool? _intro; // null while the saved flag loads
  bool _welcome = true;
  bool _show = false, _keep = true, _busy = false;
  String? _idError, _pwError;
  final _id = TextEditingController();
  final _pw = TextEditingController();
  final _pwFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _intro = !(p.getBool(_introKey) ?? false));
    });
  }

  Future<void> _introDone() async {
    setState(() => _intro = false);
    (await SharedPreferences.getInstance()).setBool(_introKey, true);
  }

  @override
  void dispose() {
    _id.dispose();
    _pw.dispose();
    _pwFocus.dispose();
    super.dispose();
  }

  Future<void> _logIn() async {
    final id = _id.text.trim();
    setState(() {
      _idError = id.isEmpty ? 'Type your email or mobile number.' : null;
      _pwError = _pw.text.isEmpty ? 'Type your password.' : null;
    });
    if (_idError != null || _pwError != null) return;
    setState(() => _busy = true);
    try {
      await Services.session.signIn(id, _pw.text, keep: _keep);
      if (!mounted) return;
      final me = Services.session.me!;
      showToast(context, 'Logged in', sub: 'Welcome back, ${me.firstName}', kind: ToastKind.ok);
      // The router moves on by itself (signed in → home, approval wait or setup).
    } on ApiError catch (e) {
      if (!mounted) return;
      switch (e.code) {
        case 'invalid_login':
          final left = int.tryParse(e.field('tries_left') ?? '');
          setState(() => _pwError = e.field('password') ?? 'Wrong password. Tap the field to type it again, or reset it.');
          showToast(context, 'Wrong password',
              sub: left == null ? null : '$left ${left == 1 ? 'try' : 'tries'} left before a 15 minute lock', kind: ToastKind.warn);
        case 'locked':
          setState(() => _pwError = e.message);
          showToast(context, 'Too many tries', sub: 'Wait 15 minutes, or reset your password', kind: ToastKind.err);
        default:
          showToast(context, e.offline ? 'You are offline' : 'Could not log in', sub: e.offline ? 'Connect to the internet to log in' : e.message, kind: ToastKind.err);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Tap the field to type it again": after a wrong password, tapping clears it.
  void _retype() {
    if (_pwError == null) return;
    _pw.clear();
    setState(() => _pwError = null);
  }

  @override
  Widget build(BuildContext context) {
    final split = authSplit(context);
    if (!split && _intro == null) return const ColoredBox(color: AppColors.caBg);
    if (!split && _intro == true) return IntroView(onDone: _introDone);
    if (_welcome && !split) return _welcomeView();
    return _loginView(split);
  }

  Widget _welcomeView() => AuthFrame(
        footBorder: false,
        foot: [
          CaButton('Log in', onPressed: () => setState(() => _welcome = false)),
          Text('New here? Open the invite link your coach sent you.', textAlign: TextAlign.center, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
          Padding(padding: const EdgeInsets.only(top: 4), child: Center(child: CaLink('Need help logging in?', onTap: () => showHelpSheet(context)))),
        ],
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(spacing: 10, children: [const AppLogo(size: 36), Text('Train With Vimal', style: AppText.s(16, W.w8))]),
          ),
          const SizedBox(height: 4),
          Container(
            height: (MediaQuery.sizeOf(context).height * .36).clamp(220.0, 320.0),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(20)),
            child: FractionallySizedBox(heightFactor: .82, child: SvgPicture.asset('assets/welcome.svg', fit: BoxFit.contain)),
          ),
          const SizedBox(height: 6),
          Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
            BalancedText('Your coach. Your plan. One app.', style: AppText.s(26, W.w8, ls: -0.52, h: 1.15)),
            Text('Workouts, meals and check-ins in one place, made for you by your coach.', style: AppText.s(14.5, W.w4, color: AppColors.muted, h: 1.45)),
          ]),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (icon, t) in const [(AppIcons.dumbbell, 'Workouts'), (AppIcons.food, 'Meals'), (AppIcons.progress, 'Progress')])
              Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 11),
                decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.line)),
                child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                  AppIcon(icon, size: 15, color: AppColors.accent),
                  Text(t, style: AppText.s(12.5, W.w6, color: AppColors.text2)),
                ]),
              ),
          ]),
        ],
      );

  Widget _loginView(bool split) => AutofillGroup(
        child: AuthFrame(
          loginBackground: !split,
          phoneTop: split ? null : _hero(),
          children: [
            Padding(
              padding: EdgeInsets.only(top: split ? 0 : 10),
              child: Column(crossAxisAlignment: split ? CrossAxisAlignment.start : CrossAxisAlignment.center, spacing: 4, children: [
                Text('Log in', style: AppText.s(split ? 28 : 24, W.w8, ls: -0.24, h: 1.2)),
                Text('Welcome back to Train With Vimal.', style: AppText.s(13.5, W.w4, color: AppColors.muted, h: 1.45)),
              ]),
            ),
            CaField(
              label: 'Email',
              autofocus: true,
              hint: 'Email or mobile number',
              controller: _id,
              error: _idError,
              keyboard: TextInputType.emailAddress,
              action: TextInputAction.next,
              autofill: const [AutofillHints.email, AutofillHints.username],
              onSubmitted: (_) => _pwFocus.requestFocus(),
            ),
            CaField(
              label: 'Password',
              hint: 'Your password',
              controller: _pw,
              focusNode: _pwFocus,
              obscure: !_show,
              error: _pwError,
              action: TextInputAction.done,
              autofill: const [AutofillHints.password],
              onTap: _retype,
              onSubmitted: (_) => _logIn(),
              trailing: CaShowButton(shown: _show, onTap: () => setState(() => _show = !_show)),
            ),
            Row(children: [
              CaCheckRow(on: _keep, onTap: () => setState(() => _keep = !_keep), title: 'Keep me logged in'),
              const Spacer(),
              CaLink('Forgot password?', size: 13, onTap: () {
                final id = _id.text.trim();
                context.go(id.contains('@') ? Uri(path: '/forgot', queryParameters: {'email': id}).toString() : '/forgot');
              }),
            ]),
            Padding(
              padding: EdgeInsets.only(top: split ? 0 : 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
                CaButton('Log in', loading: _busy, onPressed: _logIn),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('New here? Open the invite link your coach sent you.', textAlign: TextAlign.center, style: AppText.s(13, W.w4, color: AppColors.muted)),
                ),
              ]),
            ),
          ],
        ),
      );

  /// `wl-lhero`: blue card with Back / Help, logo, name and the illustration.
  Widget _hero() => Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
          gradient: LinearGradient(
            begin: Alignment(-0.36, -1),
            end: Alignment(0.36, 1),
            colors: [AppColors.sky, AppColors.skyMid, AppColors.accent],
            stops: [0, .55, 1],
          ),
        ),
        child: Column(children: [
          SizedBox(
            height: 44,
            child: Row(children: [
              _HeroButton(icon: AppIcons.chevronLeft, onTap: () => setState(() => _welcome = true), label: 'Back'),
              const Spacer(),
              _HeroButton(text: 'Help', onTap: () => showHelpSheet(context)),
            ]),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 170),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 8, children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
                    const Padding(padding: EdgeInsets.only(bottom: 8), child: AppLogo(size: 44, ring: true)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('Train With Vimal', maxLines: 1, style: AppText.s(24, W.w8, color: AppColors.white, ls: -0.48, h: 1.1)),
                    ),
                    Opacity(opacity: .9, child: Text('Your coach. Your plan.\nOne app.', style: AppText.s(13, W.w4, color: AppColors.white, h: 1.4))),
                  ]),
                ),
              ),
              Transform.translate(offset: const Offset(6, 0), child: SvgPicture.asset('assets/welcome.svg', width: 150, height: 160, fit: BoxFit.contain)),
            ]),
          ),
        ]),
      );
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({this.icon, this.text, required this.onTap, this.label});
  final AppIconData? icon;
  final String? text, label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        button: true,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            height: 32,
            constraints: const BoxConstraints(minWidth: 32),
            padding: EdgeInsets.symmetric(horizontal: text == null ? 0 : 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.white.withValues(alpha: h ? .3 : .2), borderRadius: BorderRadius.circular(10)),
            child: icon != null ? AppIcon(icon!, size: 17, color: AppColors.white) : Text(text!, style: AppText.s(13, W.w7, color: AppColors.white)),
          ),
        ),
      );
}
