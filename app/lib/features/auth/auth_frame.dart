import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/balanced_text.dart';
import '../../core/widgets/client.dart';
import '../../core/widgets/hover.dart';
import '../../core/widgets/overlays.dart';
import 'sheets.dart';

/// Signed-out and first-run pages (boards `ClientLogin`, `ClientLoginWeb`, `ClientWelcome`).
///
/// Phone / tablet: one column on `caBg` with an optional white foot (`wl-foot`).
/// Desktop (≥ 1000): a 520 side panel (`wl-brand`) and the page in a centred column (`wl-main`).

enum BrandKind { soft, steps }

/// Step list for the blue web side panel while setting up the profile.
class BrandSteps {
  const BrandSteps({required this.titles, required this.subs, required this.done, required this.current, required this.onTap, this.coachFirst = 'your coach'});
  final List<String> titles, subs;
  final Set<int> done;
  final int? current;
  final ValueChanged<int> onTap;
  final String coachFirst;
}

const kSplitWidth = 1000.0;

bool authSplit(BuildContext context) => MediaQuery.sizeOf(context).width >= kSplitWidth;

class AuthFrame extends StatelessWidget {
  const AuthFrame({
    super.key,
    required this.children,
    this.foot = const [],
    this.footBorder = true,
    this.brand = BrandKind.soft,
    this.steps,
    this.wide = false,
    this.loginBackground = false,
    this.phoneTop,
  });

  /// Full-width block above the page on phone (the blue log in hero).
  final Widget? phoneTop;

  /// The page (`wl-v`), laid out in a column with 14 gaps.
  final List<Widget> children;

  /// Buttons at the bottom (`wl-foot`). On desktop they sit under the page.
  final List<Widget> foot;
  final bool footBorder;
  final BrandKind brand;
  final BrandSteps? steps;

  /// Setup steps use a 560 column on desktop instead of 420.
  final bool wide;

  /// Phone log in page: sky blue top fading to white.
  final bool loginBackground;

  @override
  Widget build(BuildContext context) => authSplit(context) ? _web(context) : _phone(context);

  Widget _phone(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final scroll = SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ?phoneTop,
        Padding(
          padding: EdgeInsets.fromLTRB(18, phoneTop != null ? 0 : 4, 18, 18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: children),
            ),
          ),
        ),
      ]),
    );
    final body = Column(children: [
      Expanded(child: scroll),
      if (foot.isNotEmpty)
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(18, 12, 18, 22 + pad.bottom),
          decoration: BoxDecoration(
            color: loginBackground ? Colors.transparent : AppColors.white,
            border: footBorder ? const Border(top: BorderSide(color: AppColors.line)) : null,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: foot),
            ),
          ),
        ),
    ]);
    return CaWeb(
      web: false,
      child: Scaffold(
        backgroundColor: AppColors.caBg,
        body: loginBackground
            ? Stack(children: [
                Positioned.fill(
                  child: Column(children: [
                    Container(height: pad.top, color: AppColors.sky),
                    const Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [AppColors.skySoft, AppColors.skyFade, AppColors.white],
                            stops: [0, .6, 1],
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
                Padding(padding: EdgeInsets.only(top: pad.top), child: body),
              ])
            : SafeArea(bottom: false, child: body),
      ),
    );
  }

  Widget _web(BuildContext context) => CaWeb(
        web: true,
        child: ToastOffset(
          offset: 28,
          dx: 60,
          child: Scaffold(
          backgroundColor: AppColors.caWebBg,
          body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: 520, child: brand == BrandKind.steps && steps != null ? _StepsPanel(steps!) : const _SoftPanel()),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight - 80),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, spacing: 16, children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: wide ? 560 : 420),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
                            Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: children),
                            if (foot.isNotEmpty)
                              Container(
                                padding: EdgeInsets.only(top: footBorder ? 16 : 0),
                                decoration: BoxDecoration(border: footBorder ? const Border(top: BorderSide(color: AppColors.line)) : null),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: foot),
                              ),
                          ]),
                        ),
                      ),
                      const _Legal(),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
        ),
      );
}

class _Legal extends StatelessWidget {
  const _Legal();
  @override
  Widget build(BuildContext context) {
    final s = AppText.s(12.5, W.w4, color: AppColors.muted);
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
      Text('© ${DateTime.now().year} Train With Vimal ·', style: s),
      CaLink('Terms', onTap: () => showTermsSheet(context), size: 12.5, color: AppColors.muted, weight: W.w6),
      Text('·', style: s),
      CaLink('Privacy', onTap: () => showTermsSheet(context), size: 12.5, color: AppColors.muted, weight: W.w6),
      Text('·', style: s),
      CaLink('Help', onTap: () => showHelpSheet(context), size: 12.5, color: AppColors.muted, weight: W.w6),
    ]);
  }
}

class _BrandHead extends StatelessWidget {
  const _BrandHead({this.onBlue = false});
  final bool onBlue;
  @override
  Widget build(BuildContext context) => Row(spacing: 12, children: [
        const AppLogo(size: 44, ring: true),
        Text('Train With Vimal', style: AppText.s(17, W.w8, color: onBlue ? AppColors.white : AppColors.text)),
      ]);
}

class _SoftPanel extends StatelessWidget {
  const _SoftPanel();
  static const _feats = [
    (AppIcons.programs, 'Train with a plan', 'Your coach builds every workout. Open the app and start.'),
    (AppIcons.food, 'Eat right, without guessing', 'Meals and portions set for your goal, easy to log.'),
    (AppIcons.progress, 'See your progress', 'Check-ins, photos and numbers show how far you have come.'),
  ];
  static const _stats = [('10+', 'years coaching'), ('300+', 'transformations'), ('17,000+', 'followers')];

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.brandSoft,
        padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 36),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 28, children: [
          const _BrandHead(),
          Expanded(
            child: _Centered(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: SvgPicture.asset('assets/welcome.svg', width: 400, height: 260, alignment: Alignment.center),
                ),
                BalancedText('Your coach. Your plan. One app.', style: AppText.s(32, W.w8, ls: -0.64, h: 1.12)),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Text('Workouts, meals and check-ins in one place, made for you by your coach.', style: AppText.s(15, W.w4, color: AppColors.muted, h: 1.5)),
                ),
                const SizedBox(height: 4),
                Row(spacing: 22, children: [
                  for (final (n, l) in _stats)
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(n, style: AppText.s(20, W.w8, ls: -0.2)),
                      Text(l, style: AppText.s(12, W.w4, color: AppColors.muted)),
                    ]),
                ]),
                const SizedBox(height: 18),
                Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 14, children: [
                  for (final (icon, t, s) in _feats)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(10)),
                        child: AppIcon(icon, size: 18, color: AppColors.accent),
                      ),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                          Text(t, style: AppText.s(14.5, W.w8)),
                          Text(s, style: AppText.s(13, W.w4, color: AppColors.muted, h: 1.4)),
                        ]),
                      ),
                    ]),
                ]),
              ]),
            ),
          ),
        ]),
      );
}

/// Scrolls when too tall, otherwise sits in the vertical middle (`wl-bm`).
class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [child]),
          ),
        ),
      );
}

class _StepsPanel extends StatelessWidget {
  const _StepsPanel(this.s);
  final BrandSteps s;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 36),
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment(-0.34, -1), end: Alignment(0.34, 1), colors: [AppColors.accent, AppColors.accentHover]),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 28, children: [
          const _BrandHead(onBlue: true),
          Expanded(
            child: _Centered(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
                Opacity(opacity: .75, child: Text('SET UP YOUR PROFILE', style: AppText.s(11.5, W.w8, color: AppColors.white, ls: 1.38))),
                BalancedText('Help ${s.coachFirst} build your plan', style: AppText.s(38, W.w8, color: AppColors.white, ls: -0.76, h: 1.12)),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Opacity(
                    opacity: .85,
                    child: Text('Five short steps, about three minutes. You can stop and finish later.', style: AppText.s(15, W.w4, color: AppColors.white, h: 1.5)),
                  ),
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < s.titles.length; i++) _StepButton(n: i + 1, title: s.titles[i], sub: s.subs[i], done: s.done.contains(i), cur: s.current == i, onTap: () => s.onTap(i)),
                const SizedBox(height: 4),
                Opacity(opacity: .8, child: Text('${s.done.length} of ${s.titles.length} done', style: AppText.s(12.5, W.w7, color: AppColors.white))),
              ]),
            ),
          ),
        ]),
      );
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.n, required this.title, required this.sub, required this.done, required this.cur, required this.onTap});
  final int n;
  final String title, sub;
  final bool done, cur;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: cur ? AppColors.white.withValues(alpha: .18) : (h ? AppColors.white.withValues(alpha: .10) : null),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(spacing: 12, children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? AppColors.white : null,
                border: Border.all(color: done || cur ? AppColors.white : AppColors.white.withValues(alpha: .5), width: 2),
              ),
              child: done
                  ? const AppIcon(AppIcons.check, size: 14, color: AppColors.accent, stroke: 3)
                  : Text('$n', style: AppText.s(12.5, W.w8, color: AppColors.white)),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text(title, style: AppText.s(14, W.w8, color: AppColors.white)),
                Opacity(opacity: .78, child: Text(sub, style: AppText.s(12.5, W.w4, color: AppColors.white))),
              ]),
            ),
          ]),
        ),
      );
}

/// The round TWV logo (`img.wl-logo`). `ring` = white circle behind it (side panel, login hero).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 36, this.ring = false});
  final double size;
  final bool ring;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(ring ? 2 : 0),
        decoration: ring ? const BoxDecoration(color: AppColors.white, shape: BoxShape.circle) : null,
        child: SvgPicture.asset('assets/logo.svg'),
      );
}

/// Toast helper for these pages (client style toasts).
void authToast(BuildContext context, String title, {String? sub, ToastKind kind = ToastKind.ok, String? action, VoidCallback? onAction}) =>
    showToast(context, title, sub: sub, kind: kind, action: action, onAction: onAction);
