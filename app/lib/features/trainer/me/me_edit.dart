import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/util/input_rules.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import 'me_common.dart';
import 'me_model.dart';

/// "Edit my details" drawer (board `.drawer` in TrainerMe): Personal, Professional, Social media. Access and the
/// client limit stay with the admin. A new email is confirmed by a link first (auth/email/change/).
///
/// Admin (board TrainerProfile `edo`, "Edit Aman’s details"): also Work (most clients, joined on) and Login (send a
/// password reset link); the email changes straight away. Returns true when saved.
Future<bool> showEditMyDetails(BuildContext context, MeController c) async {
  final f = _EditForm(c);
  final note = c.admin ? 'Access is changed in the Access tab' : 'Your access and client limit are set by the admin';
  final saved = await showAppDrawer<String>(
    context,
    title: c.admin ? 'Edit ${c.first}’s details' : 'Edit my details',
    sub: c.admin ? 'Personal, professional and work details' : 'Personal and professional details',
    icon: c.admin ? AppIcons.editAlt : AppIcons.edit,
    builder: (ctx) => ListenableBuilder(listenable: f, builder: (ctx, _) => f.build(ctx)),
    footer: (ctx) => [
      if (!ctx.isPhone) Expanded(child: Text(note, maxLines: 2, style: AppText.s(12.5, W.w5, color: AppColors.muted))),
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      ListenableBuilder(
        listenable: f,
        builder: (_, _) => AppButton.primary('Save', expand: ctx.isPhone, loading: f.saving, onPressed: () async {
          final r = await f.save();
          if (r != null && ctx.mounted) Navigator.of(ctx).pop(r);
        }),
      ),
    ],
  );
  f.dispose();
  if (saved == null || !context.mounted) return saved != null;
  showToast(context, c.admin ? '${c.first}’s details are saved' : 'Your details are saved', sub: saved.isEmpty ? null : saved, kind: ToastKind.ok);
  return true;
}

class _EditForm extends ChangeNotifier {
  _EditForm(this.c) {
    final m = c.me, p = c.profile;
    t('full_name', '${m['full_name'] ?? ''}');
    t('phone', meDigits('${m['phone'] ?? ''}'));
    t('email', '${m['email'] ?? ''}');
    t('city', '${m['city'] ?? ''}');
    t('speciality', c.speciality.join(', '));
    t('years', c.years == null ? '' : '${c.years}');
    t('languages', c.languages.join(', '));
    t('works_best_with', '${p['works_best_with'] ?? ''}');
    t('bio', '${p['bio'] ?? ''}');
    for (final k in ['instagram', 'youtube', 'page_link', 'website']) {
      t(k, '${p[k] ?? ''}');
    }
    gender = '${m['gender'] ?? ''}';
    mode = '${p['mode'] ?? 'gym_online'}';
    dob = meParse(m['date_of_birth']);
    t('max_clients', '${m['max_clients'] ?? ''}');
    joined = meParse(m['joining_date']);
    for (final x in texts.values) {
      x.addListener(notifyListeners);
    }
  }

  final MeController c;
  final texts = <String, TextEditingController>{};
  final err = <String, String>{};
  String gender = '', mode = 'gym_online';
  DateTime? dob, joined;
  bool saving = false, reset = false;
  String? formErr;

  void t(String k, String v) => texts[k] = TextEditingController(text: v);
  String v(String k) => texts[k]!.text.trim();

  @override
  void dispose() {
    for (final x in texts.values) {
      x.dispose();
    }
    super.dispose();
  }

  void _set(VoidCallback f) {
    f();
    notifyListeners();
  }

  static const _genders = [('', 'Not set'), ('male', 'Male'), ('female', 'Female'), ('other', 'Other')];
  static const _modes = [('gym', 'Gym'), ('online', 'Online'), ('gym_online', 'Gym and online')];

  String _url(String s) => s.isEmpty || s.startsWith(RegExp(r'https?://')) ? s : 'https://$s';

  bool _validate() {
    err.clear();
    if (v('full_name').length < 2) err['full_name'] = 'Enter your full name.';
    if (!isMobile(v('phone'))) err['phone'] = 'Enter a 10 digit mobile number.';
    if (!isEmail(v('email'))) err['email'] = 'Enter a valid email, like aman@example.com.';
    final y = int.tryParse(v('years'));
    if (v('years').isNotEmpty && (y == null || y > 60)) err['years'] = 'Enter the years, 0 to 60.';
    final w = v('website');
    if (w.isNotEmpty && !RegExp(r'^(https?://)?[\w-]+(\.[\w-]+)+(/\S*)?$').hasMatch(w)) err['website'] = 'Enter a web address, like amanlifts.in.';
    if (v('bio').length > 1500) err['bio'] = 'Keep it under 1,500 letters.';
    if (c.admin) {
      final mx = int.tryParse(v('max_clients'));
      final now = (c.stats['clients'] as num?)?.toInt() ?? 0;
      if (mx == null || mx < 1 || mx > 500) {
        err['max_clients'] = 'Enter a number from 1 to 500.';
      } else if (mx < now) {
        err['max_clients'] = '${c.he[0].toUpperCase()}${c.he.substring(1)} has $now clients now. Move some first or keep $now or more.';
      }
    }
    return err.isEmpty;
  }

  /// Returns the toast line ('' when nothing extra to say), or null when it did not save.
  Future<String?> save() async {
    _set(() => formErr = null);
    if (!_validate()) {
      notifyListeners();
      return null;
    }
    _set(() => saving = true);
    final years = int.tryParse(v('years'));
    final email = v('email').toLowerCase();
    final emailChanged = !c.admin && email != '${c.me['email'] ?? ''}'.toLowerCase();
    try {
      await c.saveDetails({
        'full_name': v('full_name'),
        'phone': '+91${v('phone')}',
        'gender': gender,
        'date_of_birth': dob == null ? null : DateFormat('yyyy-MM-dd').format(dob!),
        'city': v('city'),
        'speciality': v('speciality'),
        'experience_since': years == null ? null : DateTime.now().year - years,
        'mode': mode,
        'languages': v('languages'),
        'works_best_with': v('works_best_with'),
        'bio': v('bio'),
        'instagram': v('instagram'),
        'youtube': v('youtube'),
        'page_link': v('page_link'),
        'website': _url(v('website')),
        if (c.admin) ...{
          'email': email,
          'max_clients': int.parse(v('max_clients')),
          if (joined != null) 'joining_date': DateFormat('yyyy-MM-dd').format(joined!),
          'send_password_reset': reset,
        },
      });
      if (c.admin && reset) return 'We sent ${c.first} a password reset link';
      if (emailChanged) {
        await Services.api.post('auth/email/change/', {'email': email});
        return 'We sent a link to $email. Your email changes when you open it.';
      }
      return '';
    } on ApiError catch (e) {
      _set(() {
        saving = false;
        for (final k in ['full_name', 'phone', 'email', 'city', 'speciality', 'languages', 'works_best_with', 'bio', 'instagram', 'youtube', 'page_link', 'website', 'max_clients']) {
          final m = e.field(k);
          if (m != null) err[k] = m;
        }
        final ys = e.field('experience_since');
        if (ys != null) err['years'] = ys;
        if (err.isEmpty) formErr = e.message;
      });
      return null;
    }
  }

  Widget _text(String k, String label, {bool req = false, String? hint, String? ph, TextInputType? kb, Widget? prefix, int lines = 1}) => meField(
        label,
        AppTextField(
          controller: texts[k],
          placeholder: ph,
          keyboard: kb,
          formatters: inputRules(kb),
          prefix: prefix,
          maxLines: lines,
          minLines: lines > 1 ? lines : null,
          onChanged: (_) {
            if (err.remove(k) != null) notifyListeners();
          },
        ),
        req: req,
        hint: hint,
        error: err[k],
      );

  Widget build(BuildContext context) {
    final years = int.tryParse(v('years'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MeSec('Personal', [
        MeGrid2([
          _text('full_name', 'Full name', req: true),
          _text('phone', 'Mobile', req: true, kb: TextInputType.phone, prefix: Text('+91', style: AppText.s(13.5, W.w6, color: AppColors.muted))),
          _text('email', 'Email', req: true, kb: TextInputType.emailAddress, hint: c.admin ? null : 'A new email is confirmed by a link first'),
          meField('Gender', AppSelect(_genders.firstWhere((g) => g.$1 == gender, orElse: () => _genders.first).$2, entries: [
            for (final (k, l) in _genders) MenuEntry(l, selected: k == gender, onTap: () => _set(() => gender = k)),
          ])),
          meField(
              'Date of birth',
              MeDateBox(
                value: dob,
                placeholder: 'Pick a date',
                first: DateTime(DateTime.now().year - 90),
                last: DateTime(DateTime.now().year - 16, DateTime.now().month, DateTime.now().day),
                onPick: (d) => _set(() => dob = d),
                onClear: () => _set(() => dob = null),
              )),
          _text('city', 'City'),
        ]),
      ]),
      MeSec('Professional', [
        MeGrid2([
          _text('speciality', 'Speciality', hint: 'Separate with a comma', ph: 'Strength, Fat loss'),
          _text('years', 'Experience (years)', kb: TextInputType.number, hint: years == null ? 'How many years you have coached' : 'Since ${DateTime.now().year - years}'),
          meField('Trains', AppSelect(_modes.firstWhere((m) => m.$1 == mode, orElse: () => _modes.last).$2, entries: [
            for (final (k, l) in _modes) MenuEntry(l, selected: k == mode, onTap: () => _set(() => mode = k)),
          ])),
          _text('languages', 'Languages', hint: 'Separate with a comma', ph: 'Hindi, English'),
        ]),
        _text('works_best_with', 'Best with', ph: 'Beginners and busy office workers'),
        _text('bio', c.admin ? 'About (shown to you, not to clients)' : 'About you', lines: 4, ph: 'A few lines clients read on “My trainer”'),
      ]),
      MeSec('Social media', sub: 'Optional. Clients see these only if you switch on Social media in What clients see.', last: !c.admin, [
        MeGrid2([
          _text('instagram', 'Instagram', ph: '@aman.lifts'),
          _text('youtube', 'YouTube', ph: 'youtube.com/@amanvermafit'),
          _text('page_link', 'Facebook', ph: 'Page link'),
          _text('website', 'Website', ph: 'amanlifts.in', kb: TextInputType.url),
        ]),
      ]),
      if (c.admin) ...[
        MeSec('Work', [
          MeGrid2([
            _text('max_clients', 'Most clients', kb: TextInputType.number, hint: '${c.he[0].toUpperCase()}${c.he.substring(1)} ${c.he == 'they' ? 'have' : 'has'} ${c.stats['clients'] ?? 0} now'),
            meField('Joined on', MeDateBox(value: joined, placeholder: 'Pick a date', first: DateTime(2015), last: DateTime.now(), onPick: (d) => _set(() => joined = d))),
          ]),
        ]),
        MeSec('Login', last: true, [
          MeToggleRow(
            title: 'Send password reset link',
            sub: '${c.he[0].toUpperCase()}${c.he.substring(1)} ${c.he == 'they' ? 'get' : 'gets'} a link on WhatsApp and email',
            value: reset,
            onChanged: (x) => _set(() => reset = x),
          ),
        ]),
      ],
      if (formErr != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(formErr!, style: AppText.s(12.5, W.w6, color: AppColors.badText))),
      if (context.isPhone)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(c.admin ? 'Access is changed in the Access tab' : 'Your access and client limit are set by the admin', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
        ),
    ]);
  }
}
