import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/services.dart';
import '../../core/api/api_error.dart';
import '../../core/icons/app_icons.dart';
import '../../core/widgets/client.dart';
import '../../core/widgets/overlays.dart';
import 'account_widgets.dart';
import 'auth_frame.dart';

enum _Rs { forgot, sent, checking, set, done, bad }

/// Forgot password and the reset link page (boards `ClientResetPassword`, `ClientResetPasswordWeb`).
///
/// `/forgot`: type the email → "Check your email" (resend after 30 s).
/// `/reset-password?token=`: the email link → "Set a new password" → "Password updated",
/// or "Link not valid" when it expired or was used.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.token, this.email = ''});
  final String? token;
  final String email;
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  late _Rs _s = widget.token == null ? _Rs.forgot : _Rs.checking;
  late final _email = TextEditingController(text: widget.email);
  final _p1 = TextEditingController(), _p2 = TextEditingController();
  final _clock = ResendClock();
  String? _emailErr;
  String _for = '';
  bool _busy = false, _show = false, _tried = false;

  @override
  void initState() {
    super.initState();
    _p1.addListener(_changed);
    _p2.addListener(_changed);
    if (widget.token != null) _check();
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _email.dispose();
    _p1.dispose();
    _p2.dispose();
    _clock.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final r = await Services.api.post<Map<String, dynamic>>('auth/password/reset/check/', {'token': widget.token}, null, false);
      _for = '${(r['user'] as Map?)?['email'] ?? ''}';
      if (mounted) setState(() => _s = _Rs.set);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.offline) {
        showToast(context, 'You are offline', sub: 'Connect to the internet, then open the link again', kind: ToastKind.err);
      }
      setState(() => _s = _Rs.bad);
    }
  }

  Future<void> _send({bool again = false}) async {
    final v = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
      setState(() => _emailErr = 'Enter a valid email');
      return;
    }
    setState(() {
      _busy = true;
      _emailErr = null;
    });
    try {
      await Services.api.post('auth/password/forgot/', {'identifier': v}, null, false);
      if (!mounted) return;
      _clock.start();
      if (again) {
        showToast(context, 'Email sent again', sub: v, kind: ToastKind.info);
      } else {
        setState(() => _s = _Rs.sent);
        showToast(context, 'Check your email', sub: 'Reset link sent · valid for 15 minutes', kind: ToastKind.ok);
      }
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.code == 'no_account') {
        setState(() {
          _s = _Rs.forgot;
          _emailErr = 'No account uses this email. Check for a typo.';
        });
        showToast(context, 'No account with this email', sub: 'Tap the field to fix the typo', kind: ToastKind.warn);
      } else {
        showToast(context, e.offline ? 'You are offline' : 'Could not send the link', sub: e.offline ? 'Connect to the internet and try again' : e.message, kind: ToastKind.err);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _rulesOk => Pw.long(_p1.text) && Pw.mixed(_p1.text) && _p1.text == _p2.text;

  Future<void> _save() async {
    if (!_rulesOk) {
      setState(() => _tried = true);
      showToast(context, 'Meet every rule below first', sub: 'Then tap Save new password', kind: ToastKind.warn);
      return;
    }
    setState(() => _busy = true);
    try {
      await Services.api.post('auth/password/reset/', {'token': widget.token, 'password': _p1.text, 'confirm_password': _p2.text}, null, false);
      if (!mounted) return;
      setState(() => _s = _Rs.done);
      showToast(context, 'Password updated', sub: 'Log in with your new password', kind: ToastKind.ok);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.code.startsWith('link_')) {
        setState(() => _s = _Rs.bad);
      } else {
        showToast(context, e.offline ? 'You are offline' : 'Could not save', sub: e.field('password') ?? e.message, kind: ToastKind.err);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Every other session was logged out by the reset, this one too.
  Future<void> _toLogin() async {
    if (Services.session.signedIn) await Services.session.signOut(remote: false);
    if (mounted) context.go('/login');
  }

  void _toForgot() {
    if (widget.token != null) return context.go('/forgot');
    setState(() => _s = _Rs.forgot);
  }

  @override
  Widget build(BuildContext context) {
    final (children, foot) = switch (_s) {
      _Rs.forgot => (_forgot(), [
          CaButton('Send reset link', loading: _busy, onPressed: _send),
          AltLine('Remembered it?', 'Log in', () => context.go('/login')),
        ]),
      _Rs.sent => (_sent(), [
          ResendButton(clock: _clock, busy: _busy, onResend: () => _send(again: true)),
          LinkPair('Use a different email', _toForgot, 'Back to log in', () => context.go('/login')),
        ]),
      _Rs.checking => (const [LinkChecking()], const <Widget>[]),
      _Rs.set => (_set(), [CaButton('Save new password', loading: _busy, onPressed: _save)]),
      _Rs.done => (
          const [
            StatusBadge(ok: true),
            AuthHeading('Password updated', sub: 'Log in with your new password. For your safety we logged you out on your other devices.', center: true),
          ],
          [CaButton('Back to log in', onPressed: _toLogin)],
        ),
      _Rs.bad => (
          const [
            StatusBadge(ok: false),
            AuthHeading('Link not valid', sub: 'This link has expired or was already used. Links work once, for 15 minutes.', center: true),
          ],
          [
            CaButton('Send a new link', onPressed: () => context.go('/forgot')),
            Padding(padding: const EdgeInsets.only(top: 4), child: Center(child: CaLink('Back to log in', size: 13, onTap: _toLogin))),
          ],
        ),
    };
    return AutofillGroup(
      child: AuthFrame(
        plain: BrandPlain(
          ill: _s == _Rs.set || _s == _Rs.done ? 'secure' : 'forgot',
          title: 'Back in a minute',
          sub: 'Reset links work once, for 15 minutes. Your plans, logs and photos stay as they are.',
        ),
        footBorder: _s != _Rs.bad,
        foot: foot,
        children: children,
      ),
    );
  }

  List<Widget> _forgot() => [
        AuthTop(onBack: () => context.go('/login')),
        const IllBox('forgot'),
        const AuthHeading('Forgot your password?', sub: 'Enter the email you joined with. We will send you a link to set a new one.'),
        CaField(
          label: 'Email',
          hint: 'you@email.com',
          controller: _email,
          error: _emailErr,
          keyboard: TextInputType.emailAddress,
          action: TextInputAction.send,
          autofill: const [AutofillHints.email],
          onTap: () {
            if (_emailErr != null) setState(() => _emailErr = null);
          },
          onSubmitted: (_) => _send(),
        ),
      ];

  List<Widget> _sent() => [
        AuthTop(onBack: _toForgot),
        const IllBox('forgot'),
        AuthHeading('Check your email', spans: [
          const TextSpan(text: 'We sent a reset link to '),
          em(_email.text.trim()),
          const TextSpan(text: '. It works once, for 15 minutes.'),
        ]),
        const CaHint('Not there? Check spam, or make sure this is the email you joined with.', icon: AppIcons.info),
      ];

  List<Widget> _set() => [
        const IllBox('secure'),
        AuthHeading('Set a new password', sub: 'For ${_for.isEmpty ? 'your account' : _for}. Pick one you do not use anywhere else.'),
        CaField(
          label: 'New password',
          hint: 'At least 8 characters',
          controller: _p1,
          obscure: !_show,
          action: TextInputAction.next,
          autofill: const [AutofillHints.newPassword],
          trailing: CaShowButton(shown: _show, onTap: () => setState(() => _show = !_show)),
        ),
        PasswordStrength(_p1.text),
        CaField(
          label: 'Confirm new password',
          hint: 'Type it again',
          controller: _p2,
          obscure: !_show,
          action: TextInputAction.done,
          autofill: const [AutofillHints.newPassword],
          onSubmitted: (_) => _save(),
          trailing: CaShowButton(shown: _show, onTap: () => setState(() => _show = !_show)),
        ),
        PasswordRules([
          ('At least 8 characters', Pw.long(_p1.text)),
          ('Letters and numbers', Pw.mixed(_p1.text)),
          ('Both passwords match', _p1.text.isNotEmpty && _p1.text == _p2.text),
        ], tried: _tried),
      ];
}
