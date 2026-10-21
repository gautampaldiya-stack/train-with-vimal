import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/services.dart';
import '../../core/icons/app_icons.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/client.dart';
import '../../core/widgets/overlays.dart';

/// Public gym contact (`gym/`), loaded once.
Future<Map<String, dynamic>>? _gym;
Future<Map<String, dynamic>> gymInfo() => _gym ??= Services.api.get<Map<String, dynamic>>('gym/').catchError((Object _) {
      _gym = null;
      return const <String, dynamic>{};
    });

/// "+917087403476" → "+91 70874 03476".
String prettyPhone(String raw) {
  final d = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.length == 12 && d.startsWith('91')) return '+91 ${d.substring(2, 7)} ${d.substring(7)}';
  if (d.length == 10) return '+91 ${d.substring(0, 5)} ${d.substring(5)}';
  return raw;
}

/// "Need help?" — call, WhatsApp or email the gym (ClientLogin board, `helpO`).
/// The sheet opens at once; the gym's phone and email load meanwhile (a slow or unreachable server used to keep
/// the sheet from opening until the request gave up).
Future<void> showHelpSheet(BuildContext context) async {
  final info = gymInfo().timeout(const Duration(seconds: 4), onTimeout: () => const <String, dynamic>{});
  Future<String> phoneOf() async => '${(await info)['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9+]'), '');
  Future<String> emailOf() async => '${(await info)['email'] ?? ''}';
  Future<void> open(BuildContext ctx, Future<Uri?> Function() uriOf, String title, String Function(Uri) subOf, String missing) async {
    Navigator.of(ctx).pop();
    final uri = await uriOf();
    if (!context.mounted) return;
    if (uri == null) {
      showToast(context, missing, sub: 'Ask at the front desk', kind: ToastKind.info);
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!context.mounted) return;
    showToast(context, ok ? title : 'Could not open it', sub: ok ? subOf(uri) : uri.toString(), kind: ToastKind.info);
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
          onTap: () => open(ctx, () async {
            final phone = await phoneOf();
            return phone.isEmpty ? null : Uri(scheme: 'tel', path: phone);
          }, 'Calling Train With Vimal…', (_) => 'The front desk picks up in a minute',
              'No gym phone number yet'),
        ),
        CaMenuRow(
          lead: const CaIconTile(icon: AppIcons.send),
          title: 'WhatsApp support',
          sub: 'Usually replies in 10 minutes',
          trailing: const AppIcon(AppIcons.arrowRight, size: 16, color: AppColors.muted),
          onTap: () => open(ctx, () async {
            final phone = await phoneOf();
            return phone.isEmpty ? null : Uri.parse('https://wa.me/${phone.replaceAll('+', '')}');
          }, 'Opening WhatsApp', (_) => 'Chat with the gym support team',
              'No WhatsApp number yet'),
        ),
        CaMenuRow(
          lead: const CaIconTile(icon: AppIcons.mail),
          title: 'Email support',
          sub: 'They usually reply within an hour',
          trailing: const AppIcon(AppIcons.arrowRight, size: 16, color: AppColors.muted),
          onTap: () => open(ctx, () async {
            final email = await emailOf();
            return email.isEmpty ? null : Uri(scheme: 'mailto', path: email);
          }, 'Email draft opened', (u) => 'To ${u.path}', 'No support email yet'),
        ),
      ]),
      const CaCaption('Most login problems are a pending approval or a missing invite. The gym team can check both.'),
    ]),
  );
}

/// "Terms and privacy" — the four points, then I agree. [join] = the short version on the
/// join / login link pages (board `ClientJoinLink`).
Future<bool?> showTermsSheet(BuildContext context, {bool join = false, bool readOnly = false}) => showAppSheet<bool>(
      context,
      title: 'Terms and privacy',
      sub: join ? 'The short version · last updated 1 Sep 2026' : 'Last updated · 1 Sep 2026',
      footerStretch: true,
      footer: (ctx) => [
        Row(spacing: 8, children: [
          Expanded(child: CaButton('Close', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop(false))),
          if (!readOnly) Expanded(child: CaButton('I agree', onPressed: () => Navigator.of(ctx).pop(true))),
        ]),
      ],
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        for (final (t, s) in join ? _joinTerms : _loginTerms)
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

const _loginTerms = [
  ('Your data, your control', 'We keep only the data coaching needs: workouts, meals, check-ins and progress.'),
  ('Progress photos stay private', 'Only you and your coach see them.'),
  ('Health waiver', 'You confirm that you are fit to exercise and will tell your coach about any injury or pain.'),
  ('Leaving', 'You can delete your account and data any time from My account.'),
];

const _joinTerms = [
  ('Coaching, not medical care', 'Your coach gives training and food advice. See a doctor for medical problems.'),
  ('Your account', 'Keep your password safe. One account per person.'),
  ('Health waiver', 'You confirm you are fit to exercise and will tell your coach about any injury or pain.'),
  ('Your data', 'Only you and your coach see your photos and logs. We never sell your data.'),
];

/// "Need help?" on the account link pages (reset, verify, join, permissions): WhatsApp,
/// call or email support.
Future<void> showSupportSheet(BuildContext context) async {
  // Opens at once; the rows fill in the gym's number and email when they arrive.
  final info = gymInfo().timeout(const Duration(seconds: 4), onTimeout: () => const <String, dynamic>{});
  Future<void> open(BuildContext ctx, Uri? uri, String toast) async {
    Navigator.of(ctx).pop();
    if (uri == null) {
      showToast(context, 'Not set up yet', sub: 'Ask at the front desk', kind: ToastKind.info);
      return;
    }
    showToast(context, toast, sub: 'Train With Vimal support', kind: ToastKind.info);
    await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
  }

  Widget row(BuildContext ctx, AppIconData icon, String t, String s, Uri? uri, String toast, {bool first = false, bool ready = true}) => CaMenuRow(
        divider: !first,
        lead: CaIconTile(icon: icon),
        title: t,
        sub: s,
        trailing: const AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.muted),
        onTap: ready ? () => open(ctx, uri, toast) : null,
      );

  await showAppSheet<void>(
    context,
    title: 'Need help?',
    sub: 'Support is available Mon–Sat, 9 am – 9 pm.',
    builder: (ctx) => FutureBuilder<Map<String, dynamic>>(
      future: info,
      builder: (ctx, snap) {
        final gym = snap.data ?? const <String, dynamic>{};
        final ready = snap.connectionState == ConnectionState.done;
        final phone = '${gym['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9+]'), '');
        final email = '${gym['email'] ?? ''}';
        return Column(children: [
          row(ctx, AppIcons.whatsapp, 'WhatsApp support', '${phone.isEmpty ? 'WhatsApp' : prettyPhone(phone)} · usually replies in 10 minutes',
              phone.isEmpty ? null : Uri.parse('https://wa.me/${phone.replaceAll('+', '')}'), 'Opening WhatsApp',
              first: true, ready: ready),
          row(ctx, AppIcons.phone, 'Call support', 'Mon–Sat, 9 am – 9 pm', phone.isEmpty ? null : Uri(scheme: 'tel', path: phone), 'Calling Train With Vimal…', ready: ready),
          row(ctx, AppIcons.mail, 'Email support', email.isEmpty ? 'Email' : email, email.isEmpty ? null : Uri(scheme: 'mailto', path: email), 'Email draft opened', ready: ready),
        ]);
      },
    ),
  );
}
