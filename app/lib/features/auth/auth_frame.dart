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

enum BrandKind { soft, steps, plain, list }

/// Desktop side panel with a picture, title and line (`brandPlain`: reset, verify, broken link).
class BrandPlain {
  const BrandPlain({required this.ill, required this.title, required this.sub});
  final String ill, title, sub;
}

/// One row in the side panel list (join steps or permissions).
class BrandRow {
  const BrandRow(this.title, this.sub, {this.done = false, this.current = false, this.pill, this.pillTone = CaTone.gray, this.onTap});
  final String title, sub;
  final bool done, current;
  final String? pill;
  final CaTone pillTone;
  final VoidCallback? onTap;
}

/// Desktop side panel with a kicker, title, line and a list: numbered steps (join, login link)
/// or rows with a pill (permissions). [card] = the white card at the bottom.
class BrandList {
  const BrandList({required this.kicker, required this.title, required this.sub, required this.rows, this.numbered = true, this.card});
  final String kicker, title, sub;
  final List<BrandRow> rows;
  final bool numbered;
  final (String, String)? card;
}

/// Step list for the blue web side panel while setting up the profile.
class BrandSteps {
  const BrandSteps({required this.titles, required this.subs, required this.done, required this.current, required this.onTap, this.coachFirst = 'your coach'});
  final List<String> titles, subs;
  final Set<int> done;
  final int? current;
  final ValueChanged<int> onTap;
  final String coachFirst;
}

/// Phone layout only below 600 (phones). Tablets and desktop get the web layout.
const kSplitWidth = Breakpoints.tablet;

/// The side panel needs room: from 900 it sits next to the page, below that (tablet
/// portrait) the page is centred under a logo bar.
const kPanelWidth = 900.0;

bool authSplit(BuildContext context) => MediaQuery.sizeOf(context).width >= kSplitWidth;
bool authPanel(BuildContext context) => MediaQuery.sizeOf(context).width >= kPanelWidth;

/// Side panel width: 520 on wide screens, narrower on small laptops and tablet landscape.
double _panelW(BuildContext context) => (MediaQuery.sizeOf(context).width * .4).clamp(360.0, 520.0);

/// Panel picture: 260 tall, smaller on short laptop screens so the panel text still fits.
double _illH(BuildContext context, double rest) => (MediaQuery.sizeOf(context).height - rest).clamp(120.0, 260.0);

/// Side panel padding (`wl-brand` 36 / 44, tighter when the panel is narrow).
EdgeInsets _panelPad(BuildContext context) =>
    _panelW(context) < 460 ? const EdgeInsets.symmetric(horizontal: 32, vertical: 32) : const EdgeInsets.symmetric(horizontal: 44, vertical: 36);

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
    this.plain,
    this.list,
  });

  /// Panels for the account pages; they also use the short legal line (© only) and no foot line.
  final BrandPlain? plain;
  final BrandList? list;

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

  bool get _account => plain != null || list != null;
  bool get _webFootLine => footBorder && !_account;

  Widget _web(BuildContext context) => CaWeb(
        web: true,
        child: ToastOffset(
          offset: 28,
          dx: 60,
          child: Scaffold(
          backgroundColor: AppColors.caWebBg,
          body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (authPanel(context))
            SizedBox(
              width: _panelW(context),
              child: plain != null
                  ? _PlainPanel(plain!)
                  : list != null
                      ? _ListPanel(list!)
                      : brand == BrandKind.steps && steps != null
                          ? _StepsPanel(steps!)
                          : const _SoftPanel(),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight - 80),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, spacing: 16, children: [
                      // Tablet portrait: no side panel, so the logo sits above the page.
                      if (!authPanel(context))
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: wide ? 616 : 476),
                          child: const Padding(padding: EdgeInsets.only(bottom: 4), child: _BrandHead()),
                        ),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: (wide ? 560 : 420) + (authPanel(context) ? 0 : 56)),
                        child: Container(
                          // Tablet portrait: the page sits in a white card on the grey background.
                          padding: authPanel(context) ? const EdgeInsets.symmetric(vertical: 8) : const EdgeInsets.all(28),
                          decoration: authPanel(context)
                              ? null
                              : BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: AppColors.line),
                                  boxShadow: const [BoxShadow(color: AppColors.shadowSoft, offset: Offset(0, 8), blurRadius: 24)],
                                ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
                            Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: children),
                            if (foot.isNotEmpty)
                              Container(
                                padding: EdgeInsets.only(top: _webFootLine ? 16 : 0),
                                decoration: BoxDecoration(border: _webFootLine ? const Border(top: BorderSide(color: AppColors.line)) : null),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: foot),
                              ),
                          ]),
                        ),
                      ),
                      _Legal(short: _account),
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
  const _Legal({this.short = false});
  final bool short;
  @override
  Widget build(BuildContext context) {
    final s = AppText.s(12.5, W.w4, color: AppColors.muted);
    if (short) return Text('© ${DateTime.now().year} Train With Vimal', style: s);
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
        // The soft panels show the logo without the white ring (`wl-brand.soft img.wl-logo`).
        AppLogo(size: 44, ring: onBlue),
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
        padding: _panelPad(context),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 28, children: [
          const _BrandHead(),
          Expanded(
            child: _Centered(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: SvgPicture.asset('assets/welcome.svg', width: 400, height: _illH(context, 640), alignment: Alignment.center),
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
        padding: _panelPad(context),
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
                    child: Text('${s.titles.length} short steps, about 10 minutes. Fill every detail carefully: your plans are made from it. You can stop and finish later.', style: AppText.s(15, W.w4, color: AppColors.white, h: 1.5)),
                  ),
                ),
                // `wl-bs`: 4 apart, 14 below the line above.
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
                    for (var i = 0; i < s.titles.length; i++)
                      _StepButton(n: i + 1, title: s.titles[i], sub: s.subs[i], done: s.done.contains(i), cur: s.current == i, onTap: () => s.onTap(i)),
                  ]),
                ),
                Opacity(opacity: .8, child: Text('${s.done.length} of ${s.titles.length} done', style: AppText.s(12.5, W.w7, color: AppColors.white))),
              ]),
            ),
          ),
          // `wl-bq`: who sees the answers.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(color: AppColors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
              Text('Only you and your coach see your answers.', style: AppText.s(14, W.w8, color: AppColors.white, h: 1.5)),
              Opacity(
                opacity: .78,
                child: Text('${s.coachFirst[0].toUpperCase()}${s.coachFirst.substring(1)} uses them to set your training, calories and exercise swaps.',
                    style: AppText.s(12.5, W.w4, color: AppColors.white, h: 1.5)),
              ),
            ]),
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

/// `wl-brand soft` + `brandPlain`: picture, title, line, and the Need help card at the bottom.
class _PlainPanel extends StatelessWidget {
  const _PlainPanel(this.p);
  final BrandPlain p;
  @override
  Widget build(BuildContext context) => _AccountPanel(
        card: null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: SvgPicture.asset('assets/ill/${p.ill}.svg', width: 400, height: _illH(context, 420), alignment: Alignment.center),
          ),
          BalancedText(p.title, style: AppText.s(32, W.w8, ls: -0.64, h: 1.12)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Text(p.sub, style: AppText.s(15, W.w4, color: AppColors.muted, h: 1.5)),
          ),
        ]),
      );
}

/// `wl-brand soft ac-brand` + a list: join steps (numbered circles) or permissions (pills).
class _ListPanel extends StatelessWidget {
  const _ListPanel(this.l);
  final BrandList l;
  @override
  Widget build(BuildContext context) => _AccountPanel(
        card: l.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          Opacity(opacity: .75, child: Text(l.kicker, style: AppText.s(11.5, W.w8, ls: 1.38))),
          BalancedText(l.title, style: AppText.s(32, W.w8, ls: -0.64, h: 1.12)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Text(l.sub, style: AppText.s(15, W.w4, color: AppColors.muted, h: 1.5)),
          ),
          const SizedBox(height: 4),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
            for (final (i, r) in l.rows.indexed) _ListRow(n: i + 1, r: r, numbered: l.numbered),
          ]),
        ]),
      );
}

class _ListRow extends StatelessWidget {
  const _ListRow({required this.n, required this.r, required this.numbered});
  final int n;
  final BrandRow r;
  final bool numbered;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: r.onTap,
        builder: (_, h, _) => Container(
          padding: numbered ? const EdgeInsets.symmetric(horizontal: 12, vertical: 9) : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: r.current ? AppColors.white : (h && r.onTap != null ? AppColors.white.withValues(alpha: .5) : null),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: r.current ? AppColors.line : Colors.transparent),
          ),
          child: Row(spacing: 12, children: [
            if (numbered)
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: r.done ? AppColors.accent : null,
                  border: Border.all(color: r.done || r.current ? AppColors.accent : AppColors.line2, width: 2),
                ),
                child: r.done
                    ? const AppIcon(AppIcons.check, size: 14, color: AppColors.white, stroke: 3)
                    : Text('$n', style: AppText.s(12.5, W.w8, color: r.current ? AppColors.accent : AppColors.muted)),
              ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text(r.title, style: AppText.s(14, W.w8)),
                Text(r.sub, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
              ]),
            ),
            if (r.pill != null) CaPill(r.pill!, tone: r.pillTone),
          ]),
        ),
      );
}

/// Soft panel frame for the account pages: logo, the middle part, and a white card at the bottom
/// (`wl-bq ac-bq`). With no [card] it shows the gym's support contact ("Need help?").
class _AccountPanel extends StatelessWidget {
  const _AccountPanel({required this.child, required this.card});
  final Widget child;
  final (String, String)? card;
  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.brandSoft,
        padding: _panelPad(context),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 28, children: [
          const Align(alignment: Alignment.centerLeft, child: _BrandHead()),
          Expanded(child: _Centered(child: child)),
          card != null ? _HelpCard(card!.$1, card!.$2) : const _SupportCard(),
        ]),
      );
}

class _HelpCard extends StatelessWidget {
  const _HelpCard(this.title, this.sub);
  final String title, sub;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
          Text(title, style: AppText.s(14, W.w8, h: 1.5)),
          Text(sub, style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.5)),
        ]),
      );
}

class _SupportCard extends StatelessWidget {
  const _SupportCard();
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: gymInfo(),
        builder: (_, snap) {
          final g = snap.data ?? const {};
          final phone = '${g['phone'] ?? ''}';
          final email = '${g['email'] ?? ''}';
          return _HelpCard('Need help?', [
            if (phone.isNotEmpty) 'WhatsApp ${prettyPhone(phone)}',
            if (email.isNotEmpty) email,
            'Mon–Sat, 9 am – 9 pm',
          ].join(' · '));
        },
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
