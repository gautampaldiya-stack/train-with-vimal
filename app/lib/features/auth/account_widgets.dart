import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/client.dart';
import '../../core/widgets/hover.dart';
import '../../core/widgets/overlays.dart';
import 'auth_frame.dart';
import 'sheets.dart';

/// Pieces shared by the account pages (boards `ClientResetPassword`, `ClientVerifyEmail`,
/// `ClientJoinLink`, `ClientPermissions`): top row, illustration box, heading, badge,
/// password strength and rules, timeline, "Get the app" card.

/// `wl-top`: Back on the left (or a [lead] like the link chip), Help on the right.
/// Reset / verify pages hide it on desktop ([hideOnWeb]).
class AuthTop extends StatelessWidget {
  const AuthTop({super.key, this.onBack, this.lead, this.help = true, this.hideOnWeb = true});
  final VoidCallback? onBack;
  final Widget? lead;
  final bool help, hideOnWeb;

  @override
  Widget build(BuildContext context) {
    if (hideOnWeb && authSplit(context)) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: Row(spacing: 8, children: [
        if (lead != null)
          Expanded(child: Align(alignment: Alignment.centerLeft, child: lead!))
        else ...[
          if (onBack != null) CaIconBtn(AppIcons.chevronLeft, onTap: onBack, tooltip: 'Back'),
          const Spacer(),
        ],
        if (help) CaLink('Help', size: 13, onTap: () => showSupportSheet(context)),
      ]),
    );
  }
}

/// `jl-url`: grey pill with the link the person opened.
class UrlChip extends StatelessWidget {
  const UrlChip(this.url, {super.key});
  final String url;
  @override
  Widget build(BuildContext context) => Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
          const AppIcon(AppIcons.link, size: 13, color: AppColors.text2),
          Flexible(child: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w7, color: AppColors.text2))),
        ]),
      );
}

/// The link the browser is on, shortened for [UrlChip]: `trainwithvimal.app/join/AMAN-4821`.
String shownUrl(String path) {
  final host = Uri.base.host.isEmpty ? 'trainwithvimal.app' : Uri.base.host;
  return '$host$path';
}

/// Illustration file for a board picture (`assets/ill/<name>.svg`).
String ill(String name) => 'assets/ill/$name.svg';

/// `wl-illbox`: soft blue box with the page illustration. Phone only; on desktop the
/// picture sits in the side panel.
class IllBox extends StatelessWidget {
  const IllBox(this.name, {super.key});
  final String name;
  @override
  Widget build(BuildContext context) {
    if (authSplit(context)) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 4),
      height: 236,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(20)),
      child: FractionallySizedBox(widthFactor: .92, child: SvgPicture.asset(ill(name), height: 196, fit: BoxFit.contain)),
    );
  }
}

/// `wl-h`: 24/800 title and a muted line. [sub] can carry bold bits (`ac-em`).
class AuthHeading extends StatelessWidget {
  const AuthHeading(this.title, {super.key, this.sub, this.spans, this.center = false, this.kicker});
  final String title;
  final String? sub, kicker;
  final List<InlineSpan>? spans;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final align = center ? TextAlign.center : TextAlign.start;
    final subStyle = AppText.s(13.5, W.w4, color: AppColors.muted, h: 1.45);
    return Column(crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start, spacing: 4, children: [
      if (kicker != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: Kicker(kicker!)),
      Text(title, textAlign: align, style: AppText.s(24, W.w8, ls: -0.24, h: 1.2)),
      if (spans != null)
        Text.rich(TextSpan(children: spans), textAlign: align, style: subStyle)
      else if (sub != null)
        Text(sub!, textAlign: align, style: subStyle),
    ]);
  }
}

/// `ac-em`: bold dark bit inside a muted line.
TextSpan em(String t) => TextSpan(text: t, style: AppText.s(13.5, W.w7, color: AppColors.text));

/// `jl-kick`: small blue capitals above a title.
class Kicker extends StatelessWidget {
  const Kicker(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: AppText.s(11, W.w8, color: AppColors.accentText, ls: 0.88));
}

/// `wl-badge`: 64 round badge, green check (ok) or amber clock (wait). 40 from the top on phone.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.ok});
  final bool ok;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: authSplit(context) ? 0 : 26),
        child: Center(
          child: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: ok ? AppColors.okBg : AppColors.amberBg, shape: BoxShape.circle),
            child: AppIcon(ok ? AppIcons.check : AppIcons.clock, size: 30, color: ok ? AppColors.okText : AppColors.amberText, stroke: 2.2),
          ),
        ),
      );
}

/// Password checks used on every "set a password" page.
class Pw {
  static bool long(String p) => p.length >= 8;
  static bool mixed(String p) => RegExp('[a-zA-Z]').hasMatch(p) && RegExp(r'\d').hasMatch(p);
  static int score(String p) => p.isEmpty
      ? 0
      : (long(p) ? 1 : 0) + (mixed(p) ? 1 : 0) + (RegExp('[^a-zA-Z0-9]').hasMatch(p) ? 1 : 0) + (RegExp('[A-Z]').hasMatch(p) ? 1 : 0);
}

/// `wl-str ac-str`: four bars and Weak / Okay / Strong.
class PasswordStrength extends StatelessWidget {
  const PasswordStrength(this.password, {super.key});
  final String password;
  @override
  Widget build(BuildContext context) {
    final s = Pw.score(password);
    final on = s >= 3 ? AppColors.okSolid : AppColors.amberSolid;
    final (label, color) = password.isEmpty
        ? ('Strength', AppColors.muted)
        : s >= 3
            ? ('Strong', AppColors.okText)
            : (s == 2 ? 'Okay' : 'Weak', AppColors.amberText);
    return Transform.translate(
      offset: const Offset(0, -6),
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(spacing: 4, children: [
          for (var k = 0; k < 4; k++)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 4,
                decoration: BoxDecoration(color: k < s ? on : AppColors.sub, borderRadius: BorderRadius.circular(4)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 56),
              child: Text(label, textAlign: TextAlign.right, style: AppText.s(11.5, W.w7, color: color)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// `ac-rules`: grey box of rules that tick green; after a failed try the open ones turn red.
class PasswordRules extends StatelessWidget {
  const PasswordRules(this.rules, {super.key, this.tried = false});
  final List<(String, bool)> rules;
  final bool tried;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 7, children: [
          for (final (t, ok) in rules)
            Row(spacing: 9, children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ok ? AppColors.okSolid : AppColors.white,
                  border: Border.all(color: ok ? AppColors.okSolid : (tried ? AppColors.badText : AppColors.line2), width: 1.5),
                ),
                child: ok ? const AppIcon(AppIcons.check, size: 11, color: AppColors.white, stroke: 3) : null,
              ),
              Expanded(child: Text(t, style: AppText.s(13, W.w6, color: ok ? AppColors.okText : (tried ? AppColors.badText : AppColors.text2)))),
            ]),
        ]),
      );
}

/// `wl-tl`: "What happens next" timeline. Items: (title, sub, done, current).
class CaTimeline extends StatelessWidget {
  const CaTimeline(this.items, {super.key});
  final List<(String, String, bool, bool)> items;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final (i, t) in items.indexed) _TimelineItem(title: t.$1, sub: t.$2, done: t.$3, current: t.$4, last: i == items.length - 1),
      ]);
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.title, required this.sub, required this.done, required this.current, required this.last});
  final String title, sub;
  final bool done, current, last;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          SizedBox(
            width: 22,
            child: Column(children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? AppColors.okSolid : AppColors.white,
                  border: Border.all(color: done ? AppColors.okSolid : (current ? AppColors.accent : AppColors.line2), width: 2),
                  boxShadow: current ? const [BoxShadow(color: AppColors.accentSoft, spreadRadius: 3)] : null,
                ),
                child: done ? const AppIcon(AppIcons.check, size: 12, color: AppColors.white, stroke: 3) : null,
              ),
              if (!last) Expanded(child: Container(width: 2, color: done ? AppColors.okSolid : AppColors.line)),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text(title, style: AppText.s(14, W.w7, color: done || current ? AppColors.text : AppColors.muted)),
                Text(sub, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
              ]),
            ),
          ),
        ]),
      );
}

/// `ca-card ac-next`: "What happens next" card with a timeline.
class NextCard extends StatelessWidget {
  const NextCard(this.items, {super.key, this.pill});
  final List<(String, String, bool, bool)> items;
  final Widget? pill;
  @override
  Widget build(BuildContext context) => CaCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          Row(children: [Expanded(child: Text('What happens next', style: AppText.s(15, W.w8))), ?pill]),
          CaTimeline(items),
        ]),
      );
}

/// `ca-card jl-app`: "Get the app" with Google Play / App Store.
class GetAppCard extends StatelessWidget {
  const GetAppCard(this.sub, {super.key});
  final String sub;
  @override
  Widget build(BuildContext context) => CaCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          Row(spacing: 12, children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(12)),
              child: const AppIcon(AppIcons.phone, size: 20, color: AppColors.accent),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text('Get the app', style: AppText.s(14, W.w8)),
                Text(sub, style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.4)),
              ]),
            ),
          ]),
          Row(spacing: 8, children: [
            Expanded(child: CaButton('Google Play', kind: CaBtnKind.out, small: true, onPressed: () => openStore(context, play: true))),
            Expanded(child: CaButton('App Store', kind: CaBtnKind.out, small: true, onPressed: () => openStore(context, play: false))),
          ]),
        ]),
      );
}

/// Opens the store page (search, until the store listings exist).
Future<void> openStore(BuildContext context, {bool? play}) async {
  final usePlay = play ?? Theme.of(context).platform != TargetPlatform.iOS;
  final uri = usePlay
      ? Uri.parse('https://play.google.com/store/search?q=Train%20With%20Vimal&c=apps')
      : Uri.parse('https://apps.apple.com/search?term=Train%20With%20Vimal');
  showToast(context, play == null ? (authSplit(context) ? 'Scan or search the store' : 'Opening the store') : (usePlay ? 'Opening Google Play' : 'Opening the App Store'),
      sub: play == null ? 'Search “Train With Vimal” on Google Play or the App Store' : 'Train With Vimal · free', kind: ToastKind.info);
  unawaited(launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false));
}

/// `wl-cbx wl-terms`: "I agree to the Terms of use and Privacy policy".
class TermsCheck extends StatelessWidget {
  const TermsCheck({super.key, required this.on, required this.onChanged, this.tried = false});
  final bool on, tried;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    Future<void> terms() async {
      final ok = await showTermsSheet(context, join: true);
      if (ok == true) onChanged(true);
    }

    final link = AppText.s(13.5, W.w7, color: AppColors.accentText);
    return Hover(
      onTap: () => onChanged(!on),
      builder: (_, _, _) => Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: CaCheckBox(on)),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'I agree to the '),
              WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: _InlineLink('Terms of use', style: link, onTap: terms)),
              const TextSpan(text: ' and '),
              WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: _InlineLink('Privacy policy', style: link, onTap: terms)),
            ]),
            style: AppText.s(13.5, W.w6, h: 1.5),
          ),
        ),
      ]),
    );
  }
}

class _InlineLink extends StatelessWidget {
  const _InlineLink(this.text, {required this.style, required this.onTap});
  final String text;
  final TextStyle style;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Text(text, style: style.copyWith(decoration: h ? TextDecoration.underline : null, decorationColor: style.color)),
      );
}

/// Counts down the 30 s before "Resend email" works again.
class ResendClock extends ChangeNotifier {
  ResendClock({this.seconds = 30});
  final int seconds;
  int left = 0;
  Timer? _t;

  bool get waiting => left > 0;

  void start() {
    left = seconds;
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      left = left > 0 ? left - 1 : 0;
      if (left == 0) t.cancel();
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }
}

/// The resend button: "Resend in N s" (greyed, a tap says to wait) or "Resend email".
class ResendButton extends StatelessWidget {
  const ResendButton({super.key, required this.clock, required this.onResend, this.busy = false});
  final ResendClock clock;
  final VoidCallback onResend;
  final bool busy;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: clock,
        builder: (context, _) => clock.waiting
            ? CaButton('Resend in ${clock.left} s',
                kind: CaBtnKind.out,
                icon: AppIcons.clock,
                dimmed: true,
                onPressed: () => showToast(context, 'Wait ${clock.left} s', sub: 'Then you can send the email again', kind: ToastKind.info))
            : CaButton('Resend email', kind: CaBtnKind.out, icon: AppIcons.send, loading: busy, onPressed: onResend),
      );
}

/// `ac-links`: two centred links side by side.
class LinkPair extends StatelessWidget {
  const LinkPair(this.a, this.onA, this.b, this.onB, {super.key, this.mutedB = true});
  final String a, b;
  final VoidCallback onA, onB;
  final bool mutedB;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 22, children: [
          CaLink(a, size: 13, onTap: onA),
          CaLink(b, size: 13, onTap: onB, color: mutedB ? AppColors.muted : AppColors.accentText, weight: mutedB ? W.w6 : W.w7),
        ]),
      );
}

/// `wl-alt`: "Remembered it? Log in".
class AltLine extends StatelessWidget {
  const AltLine(this.text, this.link, this.onTap, {super.key});
  final String text, link;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 5, children: [
          Text(text, style: AppText.s(13, W.w4, color: AppColors.muted)),
          CaLink(link, size: 13, onTap: onTap),
        ]),
      );
}

/// `ac-spin`: the round spinner while a link is checked.
class LinkChecking extends StatelessWidget {
  const LinkChecking({super.key, this.title = 'Checking your link…', this.sub = 'This takes a second'});
  final String title, sub;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: authSplit(context) ? 40 : 106, bottom: 40),
        child: Column(spacing: 6, children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.accent, backgroundColor: AppColors.accentSoft)),
          ),
          Text(title, style: AppText.s(16, W.w8)),
          Text(sub, style: AppText.s(13, W.w4, color: AppColors.muted)),
        ]),
      );
}
