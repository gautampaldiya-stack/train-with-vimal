import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/balanced_text.dart';
import '../../core/widgets/client.dart';
import '../../core/widgets/hover.dart';
import 'account_widgets.dart';
import 'auth_frame.dart';

/// First-open slides on the phone (board `ClientIntro`): Skip / Next / Get started → Welcome.
class IntroView extends StatefulWidget {
  const IntroView({super.key, required this.onDone});
  final VoidCallback onDone;
  @override
  State<IntroView> createState() => _IntroViewState();
}

class _IntroViewState extends State<IntroView> {
  static const _slides = [
    ('healthy', 'WHY IT MATTERS', 'Good health is your real wealth',
        'More energy for work and family, better sleep and a calmer mind. A strong body makes every day easier.',
        [('Energy', 'for the whole day'), ('Sleep', 'deeper and longer'), ('Mood', 'less stress')]),
    ('intro1', 'SMALL STEPS', 'Small steps, every single day',
        'You do not need a perfect week. Train a little, eat right, drink water and sleep well. It adds up fast.',
        [('Train', '3–5 days a week'), ('Eat', 'simple, home food'), ('Rest', '7–8 hours')]),
    ('coach', 'MEET YOUR COACH', 'Hi, I’m Vimal',
        'Certified nutritionist and personal trainer. I help people build strength and muscle the natural way, fully online.',
        [('10+', 'years coaching'), ('300+', 'transformations'), ('17,000+', 'followers')]),
    ('intro3', 'HOW IT WORKS', 'Your plan, made for you',
        'Tell us about you once. Your coach builds your workouts and meals, you log them here, and we check in every week.',
        [('1', 'Answer a few questions'), ('2', 'Get your plan'), ('3', 'Log and check in')]),
  ];
  final _pages = PageController();
  int _i = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _to(int k) => _pages.animateToPage(k, duration: const Duration(milliseconds: 380), curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final last = _i == _slides.length - 1;
    return CaWeb(
      web: false,
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.skySoft, AppColors.skyFade, AppColors.white],
              stops: [0, .45, 1],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(top: pad.top),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(children: [
                  Container(
                    height: 44,
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                    child: Row(spacing: 8, children: [
                      const AppLogo(size: 30),
                      Text('Train With Vimal', style: AppText.s(15, W.w8)),
                      const Spacer(),
                      if (!last)
                        Hover(
                          onTap: widget.onDone,
                          builder: (_, h, _) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                            child: Text('Skip', style: AppText.s(13.5, W.w7, color: AppColors.text2).copyWith(decoration: h ? TextDecoration.underline : null)),
                          ),
                        ),
                    ]),
                  ),
                  Expanded(
                    child: PageView(
                      controller: _pages,
                      onPageChanged: (k) => setState(() => _i = k),
                      children: [for (final s in _slides) _Slide(s)],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(18, 14, 18, 26 + pad.bottom),
                    child: Column(spacing: 16, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
                        for (var k = 0; k < _slides.length; k++)
                          Semantics(
                            label: 'Slide ${k + 1} of ${_slides.length}',
                            button: true,
                            child: GestureDetector(
                              onTap: () => _to(k),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                width: k == _i ? 24 : 8,
                                height: 8,
                                decoration: BoxDecoration(color: k == _i ? AppColors.accent : AppColors.dotOff, borderRadius: BorderRadius.circular(99)),
                              ),
                            ),
                          ),
                      ]),
                      Row(spacing: 8, children: [
                        if (_i > 0)
                          SizedBox(width: 48, child: CaButton('', kind: CaBtnKind.out, icon: AppIcons.chevronLeft, onPressed: () => _to(_i - 1))),
                        Expanded(
                          child: last
                              ? CaButton('Get started', trailingIcon: AppIcons.chevronRight, onPressed: widget.onDone)
                              : CaButton('Next', trailingIcon: AppIcons.chevronRight, onPressed: () => _to(_i + 1)),
                        ),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide(this.s);
  final (String, String, String, String, List<(String, String)>) s;
  @override
  Widget build(BuildContext context) {
    final num = s.$2 == 'MEET YOUR COACH' || s.$2 == 'HOW IT WORKS';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 300,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(color: AppColors.shadowSoft, blurRadius: 2, offset: Offset(0, 1)),
              BoxShadow(color: AppColors.shadowBlue, blurRadius: 24, offset: Offset(0, 8)),
            ],
          ),
          child: FractionallySizedBox(widthFactor: .86, child: SvgPicture.asset(ill(s.$1), height: 230, fit: BoxFit.contain)),
        ),
        const SizedBox(height: 22),
        Text(s.$2, style: AppText.s(11, W.w8, color: AppColors.accent, ls: 1.32)),
        const SizedBox(height: 6),
        BalancedText(s.$3, style: AppText.s(26, W.w8, ls: -0.52, h: 1.15)),
        const SizedBox(height: 6),
        Text(s.$4, style: AppText.s(14.5, W.w4, color: AppColors.muted, h: 1.5)),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
          for (final (a, b) in s.$5)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text(a, style: AppText.s(num ? 17 : 13.5, W.w8, color: num ? AppColors.accent : AppColors.text)),
                  Text(b, style: AppText.s(11.5, W.w4, color: AppColors.muted, h: 1.3)),
                ]),
              ),
            ),
        ]),
      ]),
    );
  }
}
