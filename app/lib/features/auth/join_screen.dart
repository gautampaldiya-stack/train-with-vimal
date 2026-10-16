import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../../app/services.dart';
import '../../core/api/api_error.dart';
import '../../core/icons/app_icons.dart';
import '../../core/theme/theme.dart';
import '../../core/util/input_rules.dart';
import '../../core/widgets/client.dart';
import '../../core/widgets/overlays.dart';
import 'account_widgets.dart';
import 'auth_frame.dart';
import 'sheets.dart';

/// Invite link and login link pages (boards `ClientJoinLink`, `ClientJoinLinkWeb`).
///
/// `/join/:code` (invite link a coach shares): invite → create account → account created,
/// or a broken link (expired, turned off, full).
/// `/start?token=` (login link sent when a coach adds a client): set password → you're in,
/// or "This link was already used".

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "8 Nov 2026".
String dayMonthYear(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// "Mon, 12 Oct".
String weekdayDayMonth(DateTime d) => '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

/// WhatsApp the coach (broken link → "Ask Aman for a new link").
Future<void> messageCoach(BuildContext context, String fullName, String phone) async {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) {
    showToast(context, 'No number for $fullName', sub: 'Ask at the front desk', kind: ToastKind.info);
    return;
  }
  showToast(context, 'Opening WhatsApp', sub: 'Message to $fullName · ${phone.trim()}', kind: ToastKind.info);
  await launchUrl(Uri.parse('https://wa.me/$digits'), mode: LaunchMode.externalApplication).catchError((_) => false);
}

/// "Opening the store" on phone; "Get the app" in a browser.
Widget _avatar(String initials, {double size = 38, double font = 13}) => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.caAvBg, shape: BoxShape.circle),
      child: Text(initials, style: AppText.s(font, W.w8, color: AppColors.caAvText)),
    );

/// `fd-kv`: label left, value right, a line between rows.
class _Kv extends StatelessWidget {
  const _Kv(this.label, this.value, {this.first = false});
  final String label, value;
  final bool first;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: AppColors.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
          Text(label, style: AppText.s(13.5, W.w6, color: AppColors.muted)),
          Expanded(child: Text(value, textAlign: TextAlign.right, style: AppText.s(13.5, W.w7))),
        ]),
      );
}

/// The four ways a link can fail (board `BAD`), plus a code that never existed.
class _Broken {
  const _Broken(this.title, this.sub, this.hint, this.ill, this.goT, this.logT);
  final String title, sub, hint, ill, goT, logT;
}

enum _Js { loading, inv, form, made, bad }

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.code});
  final String code;
  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  _Js _s = _Js.loading;
  Map<String, dynamic> _link = const {};
  String? _reason;
  final _name = TextEditingController(), _email = TextEditingController(), _phone = TextEditingController(), _pw = TextEditingController();
  final Map<String, String?> _err = {};
  bool _show = false, _agree = false, _tried = false, _busy = false;

  Map<String, dynamic> get _t => (_link['trainer'] as Map?)?.cast<String, dynamic>() ?? const {};
  String get _first => '${_t['first_name'] ?? 'your coach'}';
  String get _full => '${_t['full_name'] ?? 'Your coach'}';
  String get _code => '${_link['code'] ?? widget.code.toUpperCase()}';
  bool get _approval => _link['needs_approval'] != false;
  String get _url => shownUrl('/join/$_code');

  @override
  void initState() {
    super.initState();
    // Typing in a field clears its red error.
    for (final (c, k) in [(_name, 'name'), (_email, 'email'), (_phone, 'phone'), (_pw, 'password')]) {
      c.addListener(() => setState(() => _err[k] = null));
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _pw]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _link = await Services.api.get<Map<String, dynamic>>('join/${Uri.encodeComponent(widget.code)}/');
      _reason = _link['reason'] as String?;
      setState(() => _s = _reason == null ? _Js.inv : _Js.bad);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.offline) showToast(context, 'You are offline', sub: 'Connect to the internet, then open the link again', kind: ToastKind.err);
      setState(() {
        _reason = e.offline ? 'offline' : 'invalid';
        _s = _Js.bad;
      });
    }
  }

  _Broken get _broken {
    final till = DateTime.tryParse('${_link['expires_at']}')?.toLocal();
    return switch (_reason) {
      'expired' => _Broken('This invite has expired', '$_first’s invite $_code worked till ${till == null ? 'its end date' : dayMonthYear(till)}. Ask $_first for a new link.',
          'Invite links work for the time your coach picks, then stop.', 'time', 'Ask $_first for a new link', 'I already have an account'),
      'off' => _Broken('This invite was turned off', '$_first turned this link off, so it can’t make new accounts. Ask $_first for a new one.',
          'Coaches turn a link off when it was shared by mistake.', 'time', 'Ask $_first for a new link', 'I already have an account'),
      'full' => _Broken('This invite is full', 'All ${_link['max_uses'] ?? ''} places on this link are taken. Ask $_first to add you or send a new link.',
          'Coaches can limit how many people join from one link.', 'time', 'Ask $_first for a new link', 'I already have an account'),
      'offline' => const _Broken('You are offline', 'Connect to the internet, then open the link again.', 'Your invite still works once you are back online.', 'time',
          'Try again', 'I already have an account'),
      _ => const _Broken('This link does not work', 'Check you opened the whole link your coach sent, or ask them for a new one.',
          'Invite links look like trainwithvimal.app/join/AMAN-4821.', 'time', 'Get help', 'I already have an account'),
    };
  }

  bool get _emailOk => isEmail(_email.text);
  bool get _phoneOk => isMobile(_phone.text);

  Future<void> _create() async {
    setState(() {
      _err['name'] = _name.text.trim().isEmpty ? 'Enter your full name' : null;
      _err['email'] = _emailOk ? null : 'Enter a valid email';
      _err['phone'] = _phoneOk ? null : 'Enter a 10-digit mobile number';
      _tried = true;
    });
    if (_err.values.any((e) => e != null) || !Pw.long(_pw.text) || !Pw.mixed(_pw.text)) {
      showToast(context, 'Fill in every field', sub: 'Fix the fields marked in red', kind: ToastKind.warn);
      return;
    }
    if (!_agree) {
      showToast(context, 'Please accept the terms first', sub: 'Tick the checkbox, then continue', kind: ToastKind.warn);
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await Services.api.post<Map<String, dynamic>>(
        'join/${Uri.encodeComponent(_code)}/',
        {
          'full_name': _name.text.trim(),
          'email': _email.text.trim(),
          'phone': '+91${_phone.text.replaceAll(RegExp(r'[^0-9]'), '')}',
          'password': _pw.text,
          'accept_terms': true,
          'platform': Session.platform,
        },
        null,
        false,
      );
      await Services.session.adoptTokens(r);
      if (!mounted) return;
      setState(() {
        _s = _Js.made;
        _tried = false;
      });
      showToast(context, 'Account created',
          sub: _approval ? '$_first approves it next · usually within 24 hours' : 'Confirm your email to start', kind: ToastKind.ok);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.code.startsWith('link_')) {
        setState(() {
          _reason = e.code.substring(5);
          _s = _Js.bad;
        });
        return;
      }
      setState(() {
        _err['name'] = e.field('full_name');
        _err['email'] = e.field('email');
        _err['phone'] = e.field('phone');
        _err['password'] = e.field('password');
      });
      showToast(context, e.offline ? 'You are offline' : 'Could not create your account',
          sub: e.offline ? 'Connect to the internet and try again' : (e.fields.isEmpty ? e.message : 'Fix the fields marked in red'), kind: ToastKind.err);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final at = _s == _Js.made ? 2 : 1;
    final steps = [
      ('Open your invite link', 'From Coach $_first on WhatsApp'),
      ('Create your account', 'Name, email, phone, password'),
      ('Confirm your email', 'One tap on the link we send'),
      ('Get the app', _approval ? 'Log in there while $_first approves you' : 'Log in there and set up your profile'),
    ];
    final panel = BrandList(
      kicker: 'YOU’RE INVITED',
      title: 'Join Coach $_first',
      sub: 'Online coaching with workouts, meals and check-ins, made for you.',
      rows: [for (final (i, (t, s)) in steps.indexed) BrandRow(t, s, done: i < at, current: i == at)],
    );
    final (children, foot) = switch (_s) {
      _Js.loading => (const [LinkChecking(title: 'Opening your invite…')], const <Widget>[]),
      _Js.inv => (_inv(), [
          CaButton('Create my account', trailingIcon: AppIcons.chevronRight, onPressed: () => setState(() => _s = _Js.form)),
          AltLine('Already have an account?', 'Log in', () => context.go('/login')),
        ]),
      _Js.form => (_form(), [CaButton(_busy ? 'Creating your account…' : 'Create account', loading: _busy, onPressed: _create)]),
      _Js.made => (_made(), [CaButton('Confirm my email', trailingIcon: AppIcons.chevronRight, onPressed: () => context.go('/verify'))]),
      _Js.bad => (_bad(), [
          CaButton(_broken.goT, icon: _reason == 'offline' ? AppIcons.reset : AppIcons.whatsapp, onPressed: () {
            if (_reason == 'offline') {
              setState(() => _s = _Js.loading);
              _load();
            } else if (_reason == 'invalid') {
              _help();
            } else {
              messageCoach(context, _full, '${_t['phone'] ?? ''}');
            }
          }),
          CaButton(_broken.logT, kind: CaBtnKind.out, onPressed: () => context.go('/login')),
        ]),
    };
    return AutofillGroup(
      child: AuthFrame(
        plain: _s == _Js.bad ? BrandPlain(ill: _broken.ill, title: _broken.title, sub: _broken.sub) : null,
        list: _s == _Js.bad ? null : panel,
        foot: foot,
        children: children,
      ),
    );
  }

  void _help() => showSupportSheet(context);

  List<Widget> _inv() {
    final till = DateTime.tryParse('${_link['expires_at']}')?.toLocal();
    return [
      AuthTop(lead: UrlChip(_url), hideOnWeb: false),
      const IllBox('coach'),
      AuthHeading('Join Coach $_first at Train With Vimal',
          kicker: 'You’re invited',
          sub: '$_first sent you this link to start online coaching. Make your account, then $_first sets up your workouts and meals.'),
      CaCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(spacing: 10, children: [
              _avatar('${_t['initials'] ?? ''}'),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text(_full, style: AppText.s(14.5, W.w8)),
                  Text('Trainer at Train With Vimal', style: AppText.s(12.5, W.w4, color: AppColors.muted)),
                ]),
              ),
              const _LinkWorks(),
            ]),
          ),
          Column(children: [
            _Kv('Invited by', _full, first: true),
            const _Kv('Includes', 'Workouts, meals, check-ins'),
            _Kv('Invite valid till', till == null ? 'No end date' : dayMonthYear(till)),
          ]),
        ]),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
          Text('How it works', style: AppText.s(13, W.w8)),
          for (final (i, t) in [
            'Make your account here',
            'Confirm your email with one tap',
            _approval ? '$_first approves you, usually within a day' : 'Get the app and set up your profile',
          ].indexed)
            Row(spacing: 10, children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
                child: Text('${i + 1}', style: AppText.s(11.5, W.w8, color: AppColors.accentText)),
              ),
              Expanded(child: Text(t, style: AppText.s(13, W.w6, color: AppColors.text2))),
            ]),
        ]),
      ),
    ];
  }

  List<Widget> _form() => [
        AuthTop(onBack: () => setState(() => _s = _Js.inv), hideOnWeb: false),
        AuthHeading('Create your account', sub: 'Takes about a minute. ${_approval ? 'Coach $_first approves it next.' : 'Then you can log in.'}'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
          child: Row(spacing: 10, children: [
            _avatar('${_t['initials'] ?? ''}', size: 32, font: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text('Invite from Coach $_first', style: AppText.s(13.5, W.w8)),
                Text('Code $_code · filled in from your link', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w4, color: AppColors.muted)),
              ]),
            ),
            const AppIcon(AppIcons.check, size: 18, color: AppColors.okText, stroke: 2.6),
          ]),
        ),
        CaField(
          label: 'Full name',
          autofocus: true,
          hint: 'Your full name',
          controller: _name,
          error: _err['name'],
          action: TextInputAction.next,
          autofill: const [AutofillHints.name],
        ),
        CaField(
          label: 'Email',
          hint: 'you@email.com',
          controller: _email,
          error: _err['email'],
          keyboard: TextInputType.emailAddress,
          action: TextInputAction.next,
          autofill: const [AutofillHints.email],
        ),
        CaField(
          label: 'Phone number',
          hint: '98765 43210',
          leading: '+91',
          controller: _phone,
          error: _err['phone'],
          keyboard: TextInputType.phone,
          action: TextInputAction.next,
          autofill: const [AutofillHints.telephoneNumber],
        ),
        CaField(
          label: 'Password',
          hint: 'At least 8 characters',
          controller: _pw,
          error: _err['password'],
          obscure: !_show,
          action: TextInputAction.done,
          autofill: const [AutofillHints.newPassword],
          onSubmitted: (_) => _create(),
          trailing: CaShowButton(shown: _show, onTap: () => setState(() => _show = !_show)),
        ),
        PasswordStrength(_pw.text),
        PasswordRules([('At least 8 characters', Pw.long(_pw.text)), ('Letters and numbers', Pw.mixed(_pw.text))], tried: _tried),
        TermsCheck(on: _agree, tried: _tried, onChanged: (v) => setState(() => _agree = v)),
      ];

  List<Widget> _made() {
    final me = Services.session.me;
    final email = me?.email ?? _email.text.trim();
    return [
      const StatusBadge(ok: true),
      AuthHeading('Account created', sub: 'Welcome, ${me?.firstName ?? _name.text.trim().split(' ').first}! Two quick things and $_first can start on your plan.', center: true),
      NextCard([
        ('Account created', '$email · just now', true, false),
        ('Confirm your email', 'We sent a link to $email', false, true),
        if (_approval) ('Coach approval', '$_full · usually within 24 hours', false, false),
        ('Get the app and set up your profile', '5 short steps${_approval ? ' while you wait' : ''}', false, false),
      ]),
      GetAppCard('Log in there with $email after you confirm your email.'),
    ];
  }

  List<Widget> _bad() => [
        AuthTop(lead: UrlChip(_url), hideOnWeb: false),
        IllBox(_broken.ill),
        AuthHeading(_broken.title, sub: _broken.sub, center: true),
        CaHint(_broken.hint, icon: AppIcons.info, tone: CaTone.amber),
      ];
}

/// `fd-pill green` with a check: "Link works".
class _LinkWorks extends StatelessWidget {
  const _LinkWorks();
  @override
  Widget build(BuildContext context) => Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: AppColors.okBg, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 3, children: [
          const AppIcon(AppIcons.check, size: 12, color: AppColors.okText, stroke: 2.6),
          Text('Link works', style: AppText.s(11.5, W.w7, color: AppColors.okText)),
        ]),
      );
}

// ------------------------------------------------------------------ login link

enum _Ls { checking, log, ready, bad }

class LoginLinkScreen extends StatefulWidget {
  const LoginLinkScreen({super.key, required this.token});
  final String token;
  @override
  State<LoginLinkScreen> createState() => _LoginLinkScreenState();
}

class _LoginLinkScreenState extends State<LoginLinkScreen> {
  _Ls _s = _Ls.checking;
  Map<String, dynamic> _user = const {}, _coach = const {};
  DateTime? _start;
  String _problem = 'invalid';
  final _p1 = TextEditingController(), _p2 = TextEditingController();
  bool _show = false, _agree = false, _tried = false, _busy = false;

  String get _coachFirst => '${_coach['first_name'] ?? 'your coach'}';
  String get _coachFull => '${_coach['full_name'] ?? 'Your coach'}';
  String get _url => shownUrl('/start/${widget.token.length > 9 ? '${widget.token.substring(0, 9)}…' : widget.token}');

  @override
  void initState() {
    super.initState();
    _p1.addListener(() => setState(() {}));
    _p2.addListener(() => setState(() {}));
    _check();
  }

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final r = await Services.api.post<Map<String, dynamic>>('auth/login-link/check/', {'token': widget.token}, null, false);
      _user = (r['user'] as Map).cast<String, dynamic>();
      _coach = (r['coach'] as Map?)?.cast<String, dynamic>() ?? const {};
      _start = DateTime.tryParse('${r['start_date']}');
      if (mounted) setState(() => _s = _Ls.log);
    } on ApiError catch (e) {
      if (!mounted) return;
      _problem = e.offline ? 'offline' : e.code.replaceFirst('link_', '');
      _coach = {
        if (e.field('coach_first_name') != null) 'first_name': e.field('coach_first_name'),
        if (e.field('coach_full_name') != null) 'full_name': e.field('coach_full_name'),
        'phone': e.field('coach_phone') ?? '',
      };
      setState(() => _s = _Ls.bad);
    }
  }

  bool get _rulesOk => Pw.long(_p1.text) && Pw.mixed(_p1.text) && _p1.text == _p2.text;

  Future<void> _set() async {
    if (!_rulesOk) {
      setState(() => _tried = true);
      showToast(context, 'Meet every rule below first', sub: 'Then tap Set password and continue', kind: ToastKind.warn);
      return;
    }
    if (!_agree) {
      setState(() => _tried = true);
      showToast(context, 'Please accept the terms first', sub: 'Tick the checkbox, then continue', kind: ToastKind.warn);
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await Services.api.post<Map<String, dynamic>>('auth/login-link/accept/', {'token': widget.token, 'password': _p1.text, 'confirm_password': _p2.text}, null, false);
      await Services.session.adoptTokens(r);
      if (!mounted) return;
      setState(() => _s = _Ls.ready);
      showToast(context, 'Password set', sub: 'You are logged in', kind: ToastKind.ok);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.code.startsWith('link_')) {
        _problem = e.code.substring(5);
        setState(() => _s = _Ls.bad);
        return;
      }
      showToast(context, e.offline ? 'You are offline' : 'Could not set the password', sub: e.field('password') ?? e.message, kind: ToastKind.err);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _wrong() => showAppSheet<void>(
        context,
        title: 'Details not right?',
        sub: '$_coachFirst typed these in when ${_coachFirst == 'your coach' ? 'they' : _coachFirst} added you.',
        builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
          Column(children: [
            CaMenuRow(
              divider: false,
              lead: const CaIconTile(icon: AppIcons.edit),
              title: 'Fix my name or email',
              sub: 'You can change these yourself after you log in',
              trailing: const AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.muted),
              onTap: () {
                Navigator.of(ctx).pop();
                showToast(context, 'No problem', sub: 'You can edit them in More › My account', kind: ToastKind.info);
              },
            ),
            CaMenuRow(
              lead: const CaIconTile(icon: AppIcons.user),
              title: 'This is not me',
              sub: 'We tell $_coachFirst and close this link',
              trailing: const AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.muted),
              onTap: () async {
                Navigator.of(ctx).pop();
                try {
                  await Services.api.post('auth/login-link/not-me/', {'token': widget.token}, null, false);
                  if (!mounted) return;
                  showToast(context, 'Thanks for telling us', sub: '$_coachFirst was told. This link is now off', kind: ToastKind.info);
                  setState(() {
                    _problem = 'off';
                    _s = _Ls.bad;
                  });
                } on ApiError catch (e) {
                  if (mounted) showToast(context, 'Could not send', sub: e.message, kind: ToastKind.err);
                }
              },
            ),
          ]),
          CaCaption('Your mobile number is how you log in, so only $_coachFirst can change it.'),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final at = _s == _Ls.ready ? 2 : 1;
    const steps = [
      ('Open your login link', null),
      ('Set your password', 'You log in with your mobile number'),
      ('Get the app', 'Google Play or App Store'),
      ('Set up your profile', 'Five short steps, about 3 minutes'),
    ];
    final panel = BrandList(
      kicker: 'YOUR COACH ADDED YOU',
      title: 'Welcome to Train With Vimal',
      sub: '$_coachFirst already made your account. Set a password and start setting up your plan.',
      rows: [
        for (final (i, (t, s)) in steps.indexed) BrandRow(t, s ?? '$_coachFirst added you as a client', done: i < at, current: i == at),
      ],
    );
    final (children, foot) = switch (_s) {
      _Ls.checking => (const [LinkChecking()], const <Widget>[]),
      _Ls.log => (_log(), [CaButton(_busy ? 'Saving…' : 'Set password and continue', loading: _busy, onPressed: _set)]),
      _Ls.ready => (_ready(), [
          CaButton('Get the app', icon: AppIcons.phone, onPressed: () => openStore(context)),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: CaLink('Set up my profile on the web instead', size: 13, onTap: () {
                final me = Services.session.me;
                context.go(me == null ? '/login' : landingFor(me));
              }),
            ),
          ),
        ]),
      _Ls.bad => (_bad(), [
          CaButton(_problem == 'used' ? 'Message $_coachFirst' : 'Ask $_coachFirst for a new link',
              icon: AppIcons.whatsapp, onPressed: () => messageCoach(context, _coachFull, '${_coach['phone'] ?? ''}')),
          CaButton(_problem == 'used' ? 'Log in' : 'I already have an account', kind: CaBtnKind.out, onPressed: () => context.go('/login')),
        ]),
    };
    final b = _badText;
    return AutofillGroup(
      child: AuthFrame(
        plain: _s == _Ls.bad ? BrandPlain(ill: b.$4, title: b.$1, sub: b.$2) : null,
        list: _s == _Ls.bad ? null : panel,
        foot: foot,
        children: children,
      ),
    );
  }

  /// (title, line, hint, picture) for a login link that no longer works.
  (String, String, String, String) get _badText => switch (_problem) {
        'used' => (
            'This link was already used',
            'Your password is already set. Log in with your mobile number, or reset your password if you forgot it.',
            'Login links work once, for 7 days.',
            'secure'
          ),
        'expired' => ('This link has expired', 'Login links work for 7 days. Ask $_coachFirst to send you a new one.', 'Login links work once, for 7 days.', 'time'),
        'off' => ('This link is now off', '$_coachFirst was told these are not your details.', 'If this was a mistake, ask $_coachFirst for a new link.', 'time'),
        'offline' => ('You are offline', 'Connect to the internet, then open the link again.', 'Your link still works once you are back online.', 'time'),
        _ => ('This link does not work', 'Check you opened the whole link from the message, or ask your coach for a new one.', 'Login links work once, for 7 days.', 'time'),
      };

  List<Widget> _log() {
    final first = '${_user['first_name'] ?? ''}';
    final web = authSplit(context);
    return [
      AuthTop(lead: UrlChip(_url), hideOnWeb: false),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(spacing: 12, children: [
          _avatar('${_user['initials'] ?? ''}', size: 52, font: 17),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(bottom: 4), child: Kicker('Your coach added you')),
              Text('Hi $first, set your password', style: AppText.s(web ? 26 : 22, W.w8, ls: -0.22, h: 1.2)),
            ]),
          ),
        ]),
      ),
      Transform.translate(
        offset: const Offset(0, -4),
        child: Text('$_coachFull made your Train With Vimal account. Pick a password and you are in. No approval needed.',
            style: AppText.s(13.5, W.w4, color: AppColors.muted, h: 1.45)),
      ),
      CaCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Kv('Name', '${_user['full_name'] ?? ''}', first: true),
          _Kv('Mobile (you log in with this)', prettyPhone('${_user['phone'] ?? ''}')),
          _Kv('Email', '${_user['email'] ?? ''}'),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Align(alignment: Alignment.centerLeft, child: CaLink('These are not my details', size: 13, onTap: _wrong)),
          ),
        ]),
      ),
      CaField(
        label: 'New password',
        autofocus: true,
        hint: 'At least 8 characters',
        controller: _p1,
        obscure: !_show,
        action: TextInputAction.next,
        autofill: const [AutofillHints.newPassword],
        trailing: CaShowButton(shown: _show, onTap: () => setState(() => _show = !_show)),
      ),
      PasswordStrength(_p1.text),
      CaField(
        label: 'Confirm password',
        hint: 'Type it again',
        controller: _p2,
        obscure: !_show,
        error: _tried && !(_p1.text.isNotEmpty && _p1.text == _p2.text) ? 'Both passwords must match' : null,
        action: TextInputAction.done,
        autofill: const [AutofillHints.newPassword],
        onSubmitted: (_) => _set(),
        trailing: CaShowButton(shown: _show, onTap: () => setState(() => _show = !_show)),
      ),
      PasswordRules([
        ('At least 8 characters', Pw.long(_p1.text)),
        ('Letters and numbers', Pw.mixed(_p1.text)),
        ('Both passwords match', _p1.text.isNotEmpty && _p1.text == _p2.text),
      ], tried: _tried),
      TermsCheck(on: _agree, tried: _tried, onChanged: (v) => setState(() => _agree = v)),
    ];
  }

  List<Widget> _ready() {
    final first = '${_user['first_name'] ?? ''}';
    final phone = prettyPhone('${_user['phone'] ?? ''}');
    final email = '${_user['email'] ?? ''}';
    return [
      const IllBox('success'),
      AuthHeading('You’re in, $first', sub: 'Your password is set. You log in with $phone${email.isEmpty ? '' : ' or $email'}.', center: true),
      NextCard([
        ('Password set', 'Just now', true, false),
        ('Get the app', 'Log in with your mobile number and this password', false, true),
        ('Set up your profile', 'Goal, body, training days, health, food · about 3 minutes', false, false),
        ('$_coachFirst builds your plan', _start == null ? 'Workouts and meals start soon' : 'Workouts and meals start ${weekdayDayMonth(_start!)}', false, false),
      ]),
      GetAppCard('Log in with $phone and the password you just set.'),
    ];
  }

  List<Widget> _bad() {
    final b = _badText;
    return [
      AuthTop(lead: UrlChip(_url), hideOnWeb: false),
      IllBox(b.$4),
      AuthHeading(b.$1, sub: b.$2, center: true),
      CaHint(b.$3, icon: AppIcons.info, tone: CaTone.amber),
    ];
  }
}
