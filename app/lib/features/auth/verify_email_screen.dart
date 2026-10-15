import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/services.dart';
import '../../core/api/api_error.dart';
import '../../core/icons/app_icons.dart';
import '../../core/widgets/client.dart';
import '../../core/widgets/overlays.dart';
import 'account_widgets.dart';
import 'auth_frame.dart';
import 'setup/setup_state.dart';

enum _Vs { inbox, checking, ok, bad }

/// Confirm your email (boards `ClientVerifyEmail`, `ClientVerifyEmailWeb`).
///
/// `/verify` (signed in, email not confirmed yet): "Check your inbox", resend after 30 s,
/// change email, log out. `/verify-email?token=` (the email link): checking → "Email verified"
/// → permissions, or "Link not valid".
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, this.token});
  final String? token;
  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  late _Vs _s = widget.token == null ? _Vs.inbox : _Vs.checking;
  final _clock = ResendClock();
  bool _checking = false, _sending = false;
  String _confirmed = '';

  Me? get _me => Services.session.me;
  String get _email {
    final me = _me;
    if (me == null) return _confirmed;
    return me.pendingEmail.isNotEmpty ? me.pendingEmail : (me.email ?? '');
  }

  @override
  void initState() {
    super.initState();
    if (widget.token != null) {
      _open();
    } else if (_me != null && _me!.emailVerified && _me!.pendingEmail.isEmpty) {
      _confirmed = _me!.email ?? '';
      _s = _Vs.ok; // already confirmed (opened /verify again)
    } else {
      _clock.start(); // the email went out when the account was made
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      final r = await Services.api.post<Map<String, dynamic>>('auth/email/verify/', {'token': widget.token}, null, false);
      _confirmed = '${r['email'] ?? ''}';
      if (Services.session.signedIn) await Services.session.refreshMe().catchError((_) {});
      if (mounted) setState(() => _s = _Vs.ok);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.offline) showToast(context, 'You are offline', sub: 'Connect to the internet, then open the link again', kind: ToastKind.err);
      setState(() => _s = _Vs.bad);
    }
  }

  Future<void> _verified() async {
    setState(() => _checking = true);
    try {
      await Services.session.refreshMe();
      if (!mounted) return;
      if (_me?.emailVerified == true && _me!.pendingEmail.isEmpty) {
        _confirmed = _me!.email ?? '';
        setState(() => _s = _Vs.ok);
      } else {
        showToast(context, 'Not verified yet', sub: 'Open the link in the email first', kind: ToastKind.warn);
      }
    } on ApiError catch (e) {
      if (mounted) showToast(context, e.offline ? 'You are offline' : 'Could not check', sub: e.offline ? 'Connect to the internet and try again' : e.message, kind: ToastKind.err);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _sending = true);
    try {
      await Services.api.post('auth/email/resend/', {});
      if (!mounted) return;
      _clock.start();
      showToast(context, 'Email sent again', sub: _email, kind: ToastKind.info);
    } on ApiError catch (e) {
      if (mounted) showToast(context, e.offline ? 'You are offline' : 'Could not send', sub: e.offline ? 'Connect to the internet and try again' : e.message, kind: ToastKind.err);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _logOut() async {
    SetupState.instance.reset();
    await Services.session.signOut();
    if (mounted) showToast(context, 'Logged out', sub: 'Log in again to finish verifying', kind: ToastKind.info);
  }

  Future<void> _changeEmail() async {
    final changed = await showAppSheet<String>(
      context,
      title: 'Change email',
      sub: 'Typed it wrong? Fix it and we send a new link.',
      footerStretch: true,
      builder: (ctx) => _ChangeEmail(current: _email),
    );
    if (changed == null || !mounted) return;
    _clock.start();
    setState(() {});
    showToast(context, 'Email changed', sub: 'A new link went to $changed', kind: ToastKind.ok);
  }

  void _continue() {
    if (!Services.session.signedIn) return context.go('/login');
    context.go('/permissions');
  }

  @override
  Widget build(BuildContext context) {
    final coach = _me?.coachFirst ?? 'Your coach';
    final (children, foot) = switch (_s) {
      _Vs.inbox => (
          [
            AuthTop(onBack: _logOut),
            const IllBox('verify'),
            AuthHeading('Check your inbox', spans: [
              const TextSpan(text: 'We sent a link to '),
              em(_email),
              const TextSpan(text: '. Open it to confirm this is your email. Check spam if it is not there in a minute.'),
            ]),
            CaHint('The link works once, for 24 hours. ${_me?.hasCoach == true ? 'Coach $coach' : 'The gym team'} sees your account after this.', icon: AppIcons.clock),
          ],
          [
            CaButton(_checking ? 'Checking…' : 'I’ve verified', onPressed: _checking ? null : _verified),
            ResendButton(clock: _clock, busy: _sending, onResend: _resend),
            LinkPair('Change email', _changeEmail, 'Log out', _logOut),
          ],
        ),
      _Vs.checking => (const [LinkChecking()], const <Widget>[]),
      _Vs.ok => (
          [
            const StatusBadge(ok: true),
            AuthHeading('Email verified', sub: '${_me == null ? 'Thanks!' : 'Thanks, ${_me!.firstName}!'} ${_confirmed.isEmpty ? 'Your email' : _confirmed} is confirmed.', center: true),
            NextCard([
              ('Email verified', '${_confirmed.isEmpty ? 'Your email' : _confirmed} · just now', true, false),
              ('Turn on notifications', _me?.pending == true ? 'So you know the moment $coach approves you' : 'So you get reminders and replies from $coach', false, true),
              if (_me == null || _me!.pending) ('Coach approval', '${_me?.hasCoach == true ? _me!.coachFull : 'The gym team'} · usually within 24 hours', false, false),
            ]),
          ],
          [CaButton(Services.session.signedIn ? 'Continue' : 'Log in', trailingIcon: AppIcons.chevronRight, onPressed: _continue)],
        ),
      _Vs.bad => (
          const [
            StatusBadge(ok: false),
            AuthHeading('Link not valid', sub: 'This link was already used or has expired. Links work once, for 24 hours. Send a new one.', center: true),
          ],
          [CaButton(Services.session.signedIn ? 'Back to verification' : 'Log in to send a new one', onPressed: () => context.go(Services.session.signedIn ? '/verify' : '/login'))],
        ),
    };
    return AuthFrame(
      plain: const BrandPlain(
        ill: 'verify',
        title: 'Confirm your email',
        sub: 'One tap on the link we sent. It keeps your account safe and makes sure your coach can reach you.',
      ),
      foot: foot,
      children: children,
    );
  }
}

class _ChangeEmail extends StatefulWidget {
  const _ChangeEmail({required this.current});
  final String current;
  @override
  State<_ChangeEmail> createState() => _ChangeEmailState();
}

class _ChangeEmailState extends State<_ChangeEmail> {
  late final _c = TextEditingController(text: widget.current);
  String? _err;
  bool _busy = false;

  static const _domains = {'gmial.com': 'gmail.com', 'gmal.com': 'gmail.com', 'gmai.com': 'gmail.com', 'gamil.com': 'gmail.com', 'yaho.com': 'yahoo.com', 'hotmal.com': 'hotmail.com', 'outlok.com': 'outlook.com'};

  /// "riya@gmial.com" → "riya@gmail.com".
  String? get _fix {
    final v = _c.text.trim().toLowerCase();
    final at = v.lastIndexOf('@');
    if (at < 0) return null;
    final d = _domains[v.substring(at + 1)];
    return d == null ? null : '${v.substring(0, at)}@$d';
  }

  @override
  void initState() {
    super.initState();
    _c.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = _c.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) return setState(() => _err = 'Enter a valid email');
    if (_fix != null) return setState(() => _err = 'Check the spelling: did you mean ${_fix!.split('@').last}?');
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await Services.api.post('auth/email/change/', {'email': v});
      await Services.session.refreshMe();
      if (mounted) Navigator.of(context).pop(v);
    } on ApiError catch (e) {
      if (mounted) setState(() => _err = e.field('email') ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        CaField(
          label: 'New email',
          hint: 'you@email.com',
          controller: _c,
          error: _err,
          keyboard: TextInputType.emailAddress,
          action: TextInputAction.send,
          autofill: const [AutofillHints.email],
          onSubmitted: (_) => _save(),
        ),
        if (_fix != null)
          CaChips<String>(
            small: true,
            options: [_fix!],
            label: (s) => s,
            isOn: (_) => false,
            onTap: (s) {
              _c.text = s;
              setState(() => _err = null);
            },
          ),
        const CaCaption('The old link stops working.'),
        const SizedBox(height: 4),
        Row(spacing: 8, children: [
          Expanded(child: CaButton('Cancel', kind: CaBtnKind.out, onPressed: () => Navigator.of(context).pop())),
          Expanded(child: CaButton('Save and send link', loading: _busy, onPressed: _save)),
        ]),
      ]);
}

