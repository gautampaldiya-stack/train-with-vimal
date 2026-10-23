import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../auth/sheets.dart' show gymInfo, prettyPhone;
import '../progress/progress_screen.dart' show pxLoading;
import 'more_parts.dart';
import '../../../core/widgets/tooltip.dart';

/// About (boards `ClientAbout` phone and `ClientAboutWeb`): the app card with the version, the head coach,
/// contact rows and the app rows (What's new, Rate the app, Terms, Privacy, Open-source licences).
/// Contact and coach words come from the gym settings (`gym/`).
class ClientAboutScreen extends StatefulWidget {
  const ClientAboutScreen({super.key});
  @override
  State<ClientAboutScreen> createState() => _ClientAboutScreenState();
}

/// The app's own version, the same as `version:` in pubspec.yaml ("1.0.0+1" → "1.0.0 (1)").
const appVersion = '1.0.0 (1)';
const _released = '12 Oct 2026';

const _news = [
  ('Verify your email', 'New accounts confirm their email with a one-tap link.'),
  ('Reset your password', 'Forgot it? Get a link and set a new one in a minute.'),
  ('Health & injuries', 'Tell your coach about injuries and health conditions in setup.'),
  ('Smarter permissions', 'We explain notifications and camera before your phone asks.'),
];

const _terms = [
  ('Coaching, not medical care', 'Your coach gives training and food advice. See a doctor for medical problems.'),
  ('Your account', 'Keep your password safe. One account per person.'),
  ('Health waiver', 'You confirm you are fit to exercise and will tell your coach about any injury or pain.'),
  ('Leaving', 'You can delete your account any time from My account.'),
];

const _privacy = [
  ('What we keep', 'Only what coaching needs: workouts, meals, check-ins and progress.'),
  ('Progress photos', 'Private. Only you and your coach see them.'),
  ('Who sees your data', 'Your coach and the Train With Vimal team. We never sell it.'),
  ('Your control', 'Download or delete your data any time from Privacy & data.'),
];

const _licences = [
  ('Flutter', 'BSD-3-Clause · Google'),
  ('Riverpod', 'MIT · Remi Rousselet'),
  ('go_router', 'BSD-3-Clause · Flutter team'),
  ('freezed', 'MIT · Remi Rousselet'),
  ('shared_preferences', 'BSD-3-Clause · Flutter team'),
  ('Plus Jakarta Sans', 'SIL Open Font License'),
  ('unDraw illustrations', 'unDraw licence · Katerina Limpitsouni'),
];

class _ClientAboutScreenState extends State<ClientAboutScreen> {
  Map<String, dynamic>? gym;
  Object? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => error = null);
    final g = await gymInfo();
    if (!mounted) return;
    setState(() => g.isEmpty ? error = 'offline' : gym = g);
  }

  String _s(String k) => '${gym?[k] ?? ''}';

  @override
  Widget build(BuildContext context) {
    if (gym == null) return pxLoading(error, _load, 'the About page');
    final phone = context.isPhone;
    final left = [_appCard(), _coachCard()];
    final right = [moSec('Contact'), _contact(), moSec('App'), _appRows()];
    final made = Padding(
      padding: const EdgeInsets.only(top: 0),
      child: Text('© 2026 ${_s('name').isEmpty ? 'Train With Vimal' : _s('name')} · Made in India',
          textAlign: TextAlign.center, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
    );
    if (phone) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [_head(), ...left, ...right, made]),
      );
    }
    return CaWeb(
      web: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 72),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: LayoutBuilder(builder: (context, box) {
              final two = box.maxWidth >= 680;
              Widget col(List<Widget> w) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: w);
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
                _head(),
                if (two)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
                    Expanded(child: col(left)),
                    Expanded(child: col([Padding(padding: const EdgeInsets.only(left: 2), child: Text('CONTACT', style: AppText.s(12, W.w8, color: AppColors.muted, ls: 0.48))), ...right.sublist(1)])),
                  ])
                else
                  col([...left, ...right]),
                made,
              ]);
            }),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────── Parts

  Widget _head() => Row(spacing: 10, children: [
        CaIconBtn(AppIcons.chevronLeft, tooltip: 'Back to More', onTap: () => context.go('/more')),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
            Text('About', style: AppText.s(21, W.w8, h: 1.2)),
            CutText('${_s('name')} · Version $appVersion', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.muted)),
          ]),
        ),
      ]);

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        child: child,
      );

  Widget _appCard() => _card(Row(spacing: 12, children: [
        SizedBox(width: 52, height: 52, child: SvgPicture.asset('assets/logo.svg')),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(_s('name'), style: AppText.s(16, W.w8)),
            Text(_s('tagline'), style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.4)),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Semantics(
                button: true,
                label: 'Copy the version',
                child: Hover(
                  onTap: _copy,
                  builder: (_, h, _) => Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: h ? AppColors.line : AppColors.sub, borderRadius: BorderRadius.circular(99), border: Border.all(color: AppColors.line)),
                    child: Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
                      Text('Version $appVersion', style: AppText.s(11.5, W.w7, color: AppColors.text2)),
                      const AppIcon(AppIcons.copy, size: 13, color: AppColors.text2),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]));

  Widget _coachCard() {
    final c = (gym?['coach'] as Map?) ?? const {};
    final name = '${c['name'] ?? 'Vimal'}';
    final photo = '${c['photo'] ?? ''}';
    final stats = [for (final s in (c['stats'] as List? ?? const [])) ('${s['value']}', '${s['label']}')];
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      Row(spacing: 12, children: [
        Container(
          width: 44,
          height: 44,
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
          child: photo.isNotEmpty
              ? Image.network(photo, width: 44, height: 44, fit: BoxFit.cover)
              : Text(name.isEmpty ? 'V' : name[0].toUpperCase(), style: AppText.s(17, W.w8, color: AppColors.white)),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
            Text(name, style: AppText.s(15, W.w8)),
            Text('${c['role'] ?? ''}', style: AppText.s(12.5, W.w4, color: AppColors.muted)),
          ]),
        ),
      ]),
      if ('${c['intro'] ?? ''}'.isNotEmpty) Text('${c['intro']}', style: AppText.s(13.5, W.w4, color: AppColors.text2, h: 1.5)),
      if (stats.isNotEmpty)
        Row(spacing: 6, children: [
          for (final (v, l) in stats)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(12)),
                child: Column(spacing: 1, children: [
                  FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: AppText.s(19, W.w8, color: AppColors.accentText, h: 1.2))),
                  CutText(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11, W.w6, color: AppColors.text2)),
                ]),
              ),
            ),
        ]),
    ]));
  }

  Widget _list(List<Widget> rows) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
      );

  Widget _contact() {
    final phone = prettyPhone(_s('phone'));
    final wa = prettyPhone(_s('whatsapp'));
    final email = _s('email'), web = _s('website');
    final dial = _s('phone').replaceAll(RegExp(r'[^0-9+]'), '');
    final waNum = _s('whatsapp').replaceAll(RegExp(r'[^0-9]'), '');
    return _list([
      MoMenuRow(first: true, icon: AppIcons.whatsapp, title: 'WhatsApp', sub: wa.isEmpty ? 'Not added yet' : wa,
          onTap: () => _open(waNum.isEmpty ? null : Uri.parse('https://wa.me/$waNum'), 'Opening WhatsApp', 'Chat with $wa', 'No WhatsApp number yet')),
      MoMenuRow(icon: AppIcons.phone, title: 'Call', sub: phone.isEmpty ? 'Not added yet' : phone,
          onTap: () => _open(dial.isEmpty ? null : Uri(scheme: 'tel', path: dial), 'Calling $phone', _s('hours'), 'No gym phone number yet')),
      MoMenuRow(icon: AppIcons.mail, title: 'Email', sub: email.isEmpty ? 'Not added yet' : email,
          onTap: () => _open(email.isEmpty ? null : Uri(scheme: 'mailto', path: email), 'Email draft opened', 'To $email', 'No support email yet')),
      MoMenuRow(icon: AppIcons.globe, title: 'Website', sub: web.isEmpty ? 'Not added yet' : web,
          onTap: () => _open(web.isEmpty ? null : Uri.parse(web.startsWith('http') ? web : 'https://$web'), 'Opening $web', 'In your browser', 'No website yet')),
      MoMenuRow(icon: AppIcons.clock, title: 'Support hours', sub: _s('hours'), onTap: null),
    ]);
  }

  Widget _appRows() => _list([
        MoMenuRow(first: true, icon: AppIcons.gift, title: 'What’s new', sub: 'Version $appVersion · $_released', pill: 'New', onTap: _whatsNew),
        MoMenuRow(icon: AppIcons.star, title: 'Rate the app', sub: 'Tell others what you think', onTap: _rate),
        MoMenuRow(icon: AppIcons.clipboard, title: 'Terms of use', sub: '', onTap: () => _doc('Terms of use', _terms)),
        MoMenuRow(icon: AppIcons.shield, title: 'Privacy policy', sub: '', onTap: () => _doc('Privacy policy', _privacy)),
        MoMenuRow(icon: AppIcons.code, title: 'Open-source licences', sub: 'Software that helps run this app', onTap: _licencesSheet),
      ]);

  // ─────────────────────────────── Actions

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: '${_s('name')} $appVersion'));
    if (mounted) showToast(context, 'Version copied', sub: '${_s('name')} $appVersion · paste it when you report a problem', kind: ToastKind.ok);
  }

  Future<void> _open(Uri? uri, String title, String sub, String missing) async {
    if (uri == null) {
      showToast(context, missing, sub: 'Ask at the front desk', kind: ToastKind.info);
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (mounted) showToast(context, ok ? title : 'Could not open it', sub: ok ? sub : uri.toString(), kind: ToastKind.info);
  }

  Future<void> _rate() async {
    final ios = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    if (ios) {
      // No App Store page until the iOS app is published.
      showToast(context, 'Opening the store', sub: 'Rate Train With Vimal', kind: ToastKind.info);
      return;
    }
    await _open(Uri.parse('https://play.google.com/store/apps/details?id=com.trainwithvimal.app'), 'Opening the store',
        kIsWeb ? 'Rate Train With Vimal on Google Play or the App Store' : 'Rate Train With Vimal', '');
  }

  Widget _items(List<(String, String)> items) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        for (final (t, s) in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text(t, style: AppText.s(13.5, W.w8)),
              Text(s, style: AppText.s(12.5, W.w4, color: AppColors.text2, h: 1.45)),
            ]),
          ),
      ]);

  Future<void> _whatsNew() => showAppSheet<void>(
        context,
        title: 'What’s new',
        sub: 'Version $appVersion · $_released',
        footerStretch: true,
        builder: (_) => _items(_news),
        footer: (ctx) => [CaButton('Got it', onPressed: () => Navigator.of(ctx).pop())],
      );

  Future<void> _doc(String title, List<(String, String)> items) => showAppSheet<void>(
        context,
        title: title,
        sub: 'Last updated · 1 Sep 2026',
        footerStretch: true,
        builder: (_) => _items(items),
        footer: (ctx) => [CaButton('Close', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop())],
      );

  Future<void> _licencesSheet() => showAppSheet<void>(
        context,
        title: 'Open-source licences',
        sub: 'Thank you to these projects',
        footerStretch: true,
        builder: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, (t, s)) in _licences.indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(border: i == _licences.length - 1 ? null : const Border(bottom: BorderSide(color: AppColors.line))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
                Text(t, style: AppText.s(13.5, W.w7)),
                Expanded(child: Text(s, textAlign: TextAlign.right, style: AppText.s(12.5, W.w4, color: AppColors.muted))),
              ]),
            ),
        ]),
        footer: (ctx) => [CaButton('Close', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop())],
      );
}
