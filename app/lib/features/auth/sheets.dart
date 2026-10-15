import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/services.dart';
import '../../core/api/api_error.dart';
import '../../core/icons/app_icons.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/client.dart';
import '../../core/widgets/overlays.dart';

/// "Need help?" — call, WhatsApp or email the gym (ClientLogin board, `helpO`).
Future<void> showHelpSheet(BuildContext context) async {
  Map<String, dynamic> gym = const {};
  try {
    gym = await Services.api.get<Map<String, dynamic>>('gym/');
  } catch (_) {}
  if (!context.mounted) return;
  final phone = '${gym['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9+]'), '');
  final email = '${gym['email'] ?? ''}';
  Future<void> open(BuildContext ctx, Uri? uri, String title, String sub, String missing) async {
    Navigator.of(ctx).pop();
    if (uri == null) {
      showToast(context, missing, sub: 'Ask at the front desk', kind: ToastKind.info);
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!context.mounted) return;
    showToast(context, ok ? title : 'Could not open it', sub: ok ? sub : uri.toString(), kind: ToastKind.info);
  }

  await showAppSheet<void>(
    context,
    title: 'Need help?',
    sub: 'Support is available Mon–Sat, 9 am – 9 pm.',
    builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      Column(children: [
        CaMenuRow(
          divider: false,
          lead: const CaIconTile(icon: AppIcons.phone),
          title: 'Call the gym',
          sub: 'Front desk · 9 am – 9 pm',
          trailing: const AppIcon(AppIcons.arrowRight, size: 16, color: AppColors.muted),
          onTap: () => open(ctx, phone.isEmpty ? null : Uri(scheme: 'tel', path: phone), 'Calling Train With Vimal…', 'The front desk picks up in a minute',
              'No gym phone number yet'),
        ),
        CaMenuRow(
          lead: const CaIconTile(icon: AppIcons.send),
          title: 'WhatsApp support',
          sub: 'Usually replies in 10 minutes',
          trailing: const AppIcon(AppIcons.arrowRight, size: 16, color: AppColors.muted),
          onTap: () => open(ctx, phone.isEmpty ? null : Uri.parse('https://wa.me/${phone.replaceAll('+', '')}'), 'Opening WhatsApp', 'Chat with the gym support team',
              'No WhatsApp number yet'),
        ),
        CaMenuRow(
          lead: const CaIconTile(icon: AppIcons.mail),
          title: 'Email support',
          sub: 'They usually reply within an hour',
          trailing: const AppIcon(AppIcons.arrowRight, size: 16, color: AppColors.muted),
          onTap: () => open(ctx, email.isEmpty ? null : Uri(scheme: 'mailto', path: email), 'Email draft opened', 'To $email', 'No support email yet'),
        ),
      ]),
      const CaCaption('Most login problems are a pending approval or a missing invite. The gym team can check both.'),
    ]),
  );
}

/// "Reset password" — email or mobile, send link, then Send again / Back to log in.
Future<void> showForgotSheet(BuildContext context, {String initial = ''}) => showAppSheet<void>(
      context,
      title: 'Reset password',
      sub: 'We will email you a link to set a new password.',
      footerStretch: true,
      builder: (ctx) => _Forgot(initial: initial),
    );

class _Forgot extends StatefulWidget {
  const _Forgot({required this.initial});
  final String initial;
  @override
  State<_Forgot> createState() => _ForgotState();
}

class _ForgotState extends State<_Forgot> {
  late final _c = TextEditingController(text: widget.initial);
  bool _sent = false, _busy = false;
  String? _error;

  Future<void> _send() async {
    final v = _c.text.trim();
    if (v.isEmpty) {
      setState(() => _error = 'Type the email or mobile number you log in with.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Services.api.post('auth/password/forgot/', {'identifier': v}, null, false);
      if (!mounted) return;
      setState(() => _sent = true);
      showToast(context, 'Reset link sent', sub: 'Check $v · valid for 15 minutes', kind: ToastKind.ok);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.field('identifier') ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: CaField(
            label: 'Email or mobile number',
            hint: 'name@example.com or 98100 00000',
            controller: _c,
            error: _error,
            keyboard: TextInputType.emailAddress,
            action: TextInputAction.send,
            autofill: const [AutofillHints.email, AutofillHints.telephoneNumber],
            onSubmitted: (_) => _send(),
          ),
        ),
        if (_sent) CaHint('Link sent to ${_c.text.trim()}. It stays valid for 15 minutes.', icon: AppIcons.check, tone: CaTone.green),
        const SizedBox(height: 2),
        if (_sent)
          Row(spacing: 8, children: [
            Expanded(child: CaButton('Send again', kind: CaBtnKind.out, loading: _busy, onPressed: _send)),
            Expanded(child: CaButton('Back to log in', onPressed: () => Navigator.of(context).pop())),
          ])
        else
          CaButton('Send reset link', loading: _busy, onPressed: _send),
      ]);
}

/// "Terms and privacy" — the four points, then I agree.
Future<bool?> showTermsSheet(BuildContext context) => showAppSheet<bool>(
      context,
      title: 'Terms and privacy',
      sub: 'Last updated · 1 Sep 2026',
      footerStretch: true,
      footer: (ctx) => [
        Row(spacing: 8, children: [
          Expanded(child: CaButton('Close', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop(false))),
          Expanded(child: CaButton('I agree', onPressed: () => Navigator.of(ctx).pop(true))),
        ]),
      ],
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        for (final (t, s) in const [
          ('Your data, your control', 'We keep only the data coaching needs: workouts, meals, check-ins and progress.'),
          ('Progress photos stay private', 'Only you and your coach see them.'),
          ('Health waiver', 'You confirm that you are fit to exercise and will tell your coach about any injury or pain.'),
          ('Leaving', 'You can delete your account and data any time from My account.'),
        ])
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text(t, style: AppText.s(13.5, W.w8)),
              Text(s, style: AppText.s(12.5, W.w4, color: AppColors.text2, h: 1.45)),
            ]),
          ),
      ]),
    );
